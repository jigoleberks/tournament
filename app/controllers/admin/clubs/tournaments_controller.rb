class Admin::Clubs::TournamentsController < Admin::Clubs::BaseController
  def index
    @tournaments = @foreign_club.tournaments.order(starts_at: :desc)
    @entry_counts = TournamentEntry.where(tournament_id: @tournaments.select(:id))
                                   .group(:tournament_id)
                                   .count
  end

  def show
    @tournament = @foreign_club.tournaments.find(params[:id])
    @leaderboard = Leaderboards::Build.call(tournament: @tournament)
    @viewer_scope = Leaderboards::ViewerScope.full
    if @tournament.ended?
      @entry_count  = @tournament.tournament_entries.count
      @angler_count = TournamentEntryMember
                        .where(tournament_entry_id: @tournament.tournament_entries.select(:id))
                        .count
    end
    render template: "tournaments/show"
  end
end
