# Shared strong-params for the admin/ and organizers/ tournament controllers,
# which are otherwise twins. Keeping one permit-list here prevents the drift
# that previously left the /admin form unable to set :format, :blind_leaderboard,
# and :train_cars that the /organizers form already permitted.
module TournamentParams
  extend ActiveSupport::Concern

  private

  def tournament_params
    params.require(:tournament).permit(
      :name, :mode, :format, :starts_at, :ends_at, :season_tag, :requires_release_video, :judged, :local,
      :awards_season_points, :blind_leaderboard, :entrants_only_leaderboard,
      :target_min_inches, :target_max_inches,
      train_cars: [],
      scoring_slots_attributes: [:id, :species_id, :slot_count, :_destroy]
    )
  end
end
