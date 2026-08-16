class Organizers::TournamentLinksController < Organizers::BaseController
  before_action :load_tournament

  def create
    other = current_club.tournaments.find_by(id: params[:linked_tournament_id])
    if other.nil?
      redirect_to edit_organizers_tournament_path(@tournament), alert: "Pick a tournament to link with." and return
    end
    unless @tournament.mode_team? && other.mode_team?
      redirect_to edit_organizers_tournament_path(@tournament), alert: "Only team tournaments can be linked." and return
    end

    TournamentLinks::Join.call(tournament: @tournament, other: other)
    redirect_to edit_organizers_tournament_path(@tournament),
                notice: "Linked with #{other.name}. Entries are now shared."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_organizers_tournament_path(@tournament), alert: e.message
  end

  def destroy
    TournamentLinks::Leave.call(tournament: @tournament)
    redirect_to edit_organizers_tournament_path(@tournament), notice: "Unlinked."
  end

  private

  def load_tournament
    @tournament = current_club.tournaments.find(params[:id])
  end
end
