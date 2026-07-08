class TournamentsController < ApplicationController
  before_action :require_sign_in!

  def index
    scope = current_club.tournaments.order(starts_at: :desc)
    scope = scope.where(season_tag: params[:season]) if params[:season].present?
    now = Time.current
    @active_tournaments = scope.where("ends_at IS NULL OR ends_at >= ?", now)
    @completed_tournaments = scope.where("ends_at IS NOT NULL AND ends_at < ?", now)
    @season_tags = current_club.tournaments.where.not(season_tag: nil).distinct.pluck(:season_tag)
  end

  def show
    @tournament = current_club.tournaments.find(params[:id])
    unless tournament_leaderboard_visible?(@tournament)
      redirect_to root_path,
                  alert: "Ask an organizer to add you to this tournament to see its leaderboard."
      return
    end
    @leaderboard = Leaderboards::Build.call(tournament: @tournament)
    @viewer_scope = Leaderboards::ViewerScope.for(tournament: @tournament, user: current_user)
    if @tournament.ended?
      @entry_count  = @tournament.tournament_entries.count
      @angler_count = TournamentEntryMember
                        .where(tournament_entry_id: @tournament.tournament_entries.select(:id))
                        .count
    end
  end

  def bingo_card
    @tournament = current_club.tournaments.find(params[:id])
    unless @tournament.format_bingo?
      redirect_to tournament_path(@tournament) and return
    end
    @entry = @tournament.tournament_entries
      .joins(:tournament_entry_members)
      .find_by(tournament_entry_members: { user_id: current_user.id })
    unless @entry
      redirect_to tournament_path(@tournament),
                  alert: "You're not entered in this tournament." and return
    end
    @result = Catches::Bingo::EvaluateCard.call(tournament: @tournament, entry: @entry)
  end

  def archived
    @tournaments = current_club.tournaments
      .where("ends_at IS NOT NULL AND ends_at < ?", 24.hours.ago)
      .order(ends_at: :desc)
    @winners = Tournaments::WinnersFor.call(tournaments: @tournaments)
  end
end
