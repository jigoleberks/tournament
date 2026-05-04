class CatchesController < ApplicationController
  before_action :require_sign_in!

  def index
    @selected_start, @selected_end =
      if params.key?(:start) || params.key?(:end)
        parse_date_range(params)
      else
        default_date_range
      end
    @month_start = parse_date(params[:month]) || (@selected_start || Date.current).beginning_of_month
    @month_start = @month_start.beginning_of_month
    @species_filter_id = params[:species].presence&.to_i
    @sort = params[:sort].presence&.to_sym || :newest

    # :catch_placements is preloaded so visible_flags_for -> can_review_catch?
    # (which walks placements to find tournament_ids) doesn't N+1 for staff
    # viewers when any rendered catch carries the possible_duplicate flag.
    @catches = filter_and_sort(current_user.catches.includes(:species, :catch_placements, photo_attachment: :blob))
    @counts_by_date = counts_by_date(@month_start)
    @available_species = current_user.club.species.order(:name)
  end

  def map
    @selected_start, @selected_end =
      if params.key?(:start) || params.key?(:end)
        parse_date_range(params)
      else
        default_date_range
      end
    @month_start = parse_date(params[:month]) || (@selected_start || Date.current).beginning_of_month
    @month_start = @month_start.beginning_of_month
    @species_filter_id = params[:species].presence&.to_i
    @available_species = current_user.club.species.order(:name)

    scope = current_user.catches.includes(:species, photo_attachment: :blob)
    if @selected_start
      scope = scope.where(captured_at_device: @selected_start.beginning_of_day..@selected_end.end_of_day)
    end
    scope = scope.where(species_id: @species_filter_id) if @species_filter_id
    @catches = scope.order(captured_at_device: :desc)
    @counts_by_date = counts_by_date(@month_start)

    @map_points = @catches.filter_map do |c|
      next unless c.latitude && c.longitude
      {
        lat: c.latitude.to_f,
        lng: c.longitude.to_f,
        popup: render_to_string(partial: "catches/map_popup", locals: { catch: c }, formats: [:html])
      }
    end
  end

  def show
    @catch = Catch.joins(:user)
                  .where(users: { club_id: current_user.club_id })
                  .find(params[:id])
    head :forbidden and return unless authorized_to_view?(@catch)
    @action_tournament = resolve_action_tournament(@catch)
  end

  def new
    @catch = current_user.catches.build(captured_at_device: Time.current,
                                         client_uuid: SecureRandom.uuid)
    @species = current_user.club.species.order(:name)
    @length_caps = @species.each_with_object({}) do |s, h|
      cap = Catch::MAX_LENGTH_BY_SPECIES[s.name.to_s.downcase]
      h[s.id] = cap if cap
    end
  end

  def create
    @catch = current_user.catches.build(catch_params)
    @catch.flags = Catches::ComputeFlags.call(@catch)
    @catch.status = @catch.flags.empty? ? :synced : :needs_review
    @catch.synced_at = Time.current

    if @catch.save && @catch.photo.attached?
      Catches::PlaceInSlots.call(catch: @catch)
      Catches::FlagDuplicates.call(catch: @catch) if @catch.flags.include?("possible_duplicate")
      FetchCatchConditionsJob.perform_later(catch_id: @catch.id)
      redirect_to root_path, notice: "Catch logged"
    else
      @catch.errors.add(:photo, "is required") unless @catch.photo.attached?
      @species = current_user.club.species.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def update
    catch_record = current_user.catches.find(params[:id])
    if catch_record.update(catch_note_params)
      redirect_to catch_record, notice: "Notes saved"
    else
      @catch = catch_record
      @action_tournament = resolve_action_tournament(@catch)
      flash.now[:alert] = catch_record.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  private

  def authorized_to_view?(catch_record)
    return true if catch_record.user_id == current_user.id
    return true if current_user.organizer?
    judge_tournament_ids = TournamentJudge.where(user: current_user).pluck(:tournament_id)
    catch_tournament_ids = catch_record.catch_placements.pluck(:tournament_id).uniq
    (judge_tournament_ids & catch_tournament_ids).any?
  end

  # Tournament to act in (DQ / length edit) from this catch's show page.
  # Prefer ?t= when supplied and the user has authority there; otherwise
  # the first placement the user can act on. Returns nil if none.
  def resolve_action_tournament(catch_record)
    candidate_ids = catch_record.catch_placements.pluck(:tournament_id).uniq
    return nil if candidate_ids.empty?
    tournaments = current_user.club.tournaments.where(id: candidate_ids)
    preferred = tournaments.find_by(id: params[:t])
    [preferred, *tournaments].compact.find { |t| can_act_on?(t) }
  end

  def can_act_on?(tournament)
    return true if tournament.friendly? && current_user.organizer?
    TournamentJudge.exists?(tournament: tournament, user: current_user)
  end

  def catch_note_params
    params.require(:catch).permit(:note)
  end

  def catch_params
    params.require(:catch).permit(
      :species_id, :length_inches, :captured_at_device, :captured_at_gps,
      :latitude, :longitude, :gps_accuracy_m, :app_build, :client_uuid, :photo, :note
    )
  end

  def parse_date_range(params)
    start = parse_date(params[:start])
    finish = parse_date(params[:end]) || start
    return [nil, nil] if start.nil? && finish.nil?
    start ||= finish
    start, finish = finish, start if start > finish
    [start, finish]
  end

  def default_date_range
    today = Date.current
    if current_user.catches.where(captured_at_device: today.beginning_of_day..today.end_of_day).exists?
      [today, today]
    elsif (latest = current_user.catches.maximum(:captured_at_device))
      d = latest.to_date
      [d, d]
    else
      [nil, nil]
    end
  end

  def parse_date(s)
    return nil unless s.present?
    Date.parse(s) rescue nil
  end

  def filter_and_sort(scope)
    if @selected_start
      scope = scope.where(captured_at_device: @selected_start.beginning_of_day..@selected_end.end_of_day)
    end
    scope = scope.where(species_id: @species_filter_id) if @species_filter_id
    case @sort
    when :longest  then scope.order(length_inches: :desc, captured_at_device: :desc)
    when :shortest then scope.order(length_inches: :asc, captured_at_device: :desc)
    else                scope.order(captured_at_device: :desc)
    end
  end

  def counts_by_date(month_start)
    # Group in Time.zone, not Postgres's session zone — DATE() on a UTC-stored
    # timestamp would mis-bucket evening catches in non-UTC deployments.
    range = month_start.beginning_of_day..month_start.end_of_month.end_of_day
    current_user.catches
      .where(captured_at_device: range)
      .pluck(:captured_at_device)
      .group_by { |t| t.in_time_zone.to_date }
      .transform_values(&:size)
  end
end
