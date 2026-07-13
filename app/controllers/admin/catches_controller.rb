class Admin::CatchesController < Admin::BaseController
  include ClubCatchIndex
  include CatchDetailEditing
  include CatchHistoryFiltering

  def index
    @selected_start, @selected_end = resolve_date_range
    @month_start = Catches::ApplyFilters.parse_date(params[:month_nav]) || (@selected_start || Date.current).beginning_of_month
    @month_start = @month_start.beginning_of_month
    @species_filter_id = params[:species].presence&.to_i
    @lake_filter_key   = Geofence::Lakes.normalize_key(params[:lake])
    @sort = params[:sort].presence&.to_sym || :newest
    @month_of_year_active = month_of_year_param
    @available_species = Species.order(:name)

    scoped = club_catch_base(current_club)
    base = scoped.includes(:user, :logged_by_user, :species, :catch_placements, :judge_actions, photo_attachment: :blob, reference_photo_attachment: :blob)
    filtered = Catches::ApplyFilters.call(scope: base, params: effective_filter_params)
    @catches = sort_catches(filtered)
    @counts_by_date = counts_by_date(scoped, @month_start)
  end

  private

  # Admin defaults to ALL submissions (the calendar is still navigable); only the
  # personal "My catches" page defaults to a single day.
  def default_date_range
    [nil, nil]
  end
end
