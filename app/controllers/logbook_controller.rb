class LogbookController < ApplicationController
  include CatchFilterHelpers
  before_action :require_sign_in!
  before_action :ensure_logbook_enabled

  def index
    @selected_start, @selected_end = resolve_date_range
    @month_start = Catches::ApplyFilters.parse_date(params[:month_nav]) || (@selected_start || Date.current).beginning_of_month
    @month_start = @month_start.beginning_of_month
    @species_filter_id = params[:species].presence&.to_i
    @lake_filter_key   = Geofence::Lakes.normalize_key(params[:lake])
    @structure_filter  = params[:structure].presence
    @bait_filter_id    = params[:bait_id].presence&.to_i
    @sort = params[:sort].presence&.to_sym || :newest
    @month_of_year_active = month_of_year_param

    base = current_user.catches.includes(:species, :bait, :catch_placements, photo_attachment: :blob)
    filtered = Logbook::ApplyFilters.call(scope: base, params: effective_filter_params)
    @catches = sort_catches(filtered)
    @counts_by_date = counts_by_date(@month_start)
    @available_species = Species.order(:name)
    @available_baits = current_user.baits.active.order(:created_at)

    @map_points = @catches.filter_map do |c|
      next unless c.latitude && c.longitude
      {
        lat: c.latitude.to_f,
        lng: c.longitude.to_f,
        popup: render_to_string(partial: "catches/map_popup", locals: { catch: c }, formats: [:html])
      }
    end
  end

  private

  def ensure_logbook_enabled
    return if logbook_enabled?
    redirect_to root_path, alert: "Logbook isn't enabled on this server."
  end
end
