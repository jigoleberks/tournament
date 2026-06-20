# Shared strong-params for the admin/ and organizers/ tournament-template
# controllers (twins). Mirrors TournamentParams: one permit-list so the /admin
# template form can set :format, :blind_leaderboard, :entrants_only_leaderboard,
# and :train_cars that the /organizers form already permitted.
module TemplateParams
  extend ActiveSupport::Concern

  private

  def template_params
    params.require(:tournament_template).permit(
      :name, :mode, :format, :default_duration_days, :season_tag,
      :default_weekday, :default_start_time, :default_end_time,
      :awards_season_points, :blind_leaderboard, :entrants_only_leaderboard,
      train_cars: [],
      tournament_template_scoring_slots_attributes: [:id, :species_id, :slot_count, :_destroy]
    )
  end
end
