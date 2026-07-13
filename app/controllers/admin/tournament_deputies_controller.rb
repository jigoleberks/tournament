class Admin::TournamentDeputiesController < Admin::BaseController
  # See Organizers::TournamentDeputiesController — granting is permanent-only.
  before_action :require_permanent_organizer!
  before_action :load_tournament

  def create
    user = current_club.members.active.find(params.dig(:tournament_deputy, :user_id))
    @tournament.tournament_deputies.find_or_create_by(user: user) do |deputy|
      deputy.granted_by_user = current_user
    end
    redirect_to edit_admin_tournament_path(@tournament), notice: "Deputy added."
  rescue ActiveRecord::RecordNotFound
    redirect_to edit_admin_tournament_path(@tournament), alert: "Pick a member first."
  end

  def destroy
    deputy = @tournament.tournament_deputies.find(params[:id])
    deputy.destroy
    redirect_to edit_admin_tournament_path(@tournament), notice: "Deputy removed."
  end

  private

  def load_tournament
    @tournament = current_club.tournaments.find(params[:tournament_id])
  end
end
