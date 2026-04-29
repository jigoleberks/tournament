class Organizers::TournamentJudgesController < Organizers::BaseController
  before_action :load_tournament

  def create
    user = current_user.club.users.active.find(params.dig(:tournament_judge, :user_id))
    @tournament.tournament_judges.find_or_create_by(user: user)
    redirect_to edit_organizers_tournament_path(@tournament), notice: "Judge added."
  rescue ActiveRecord::RecordNotFound
    redirect_to edit_organizers_tournament_path(@tournament), alert: "Pick a member first."
  end

  def destroy
    judge = @tournament.tournament_judges.find(params[:id])
    judge.destroy
    redirect_to edit_organizers_tournament_path(@tournament), notice: "Judge removed."
  end

  private

  def load_tournament
    @tournament = current_user.club.tournaments.find(params[:tournament_id])
  end
end
