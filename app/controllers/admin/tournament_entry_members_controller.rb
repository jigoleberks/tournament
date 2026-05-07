class Admin::TournamentEntryMembersController < Admin::BaseController
  before_action :load_tournament_and_entry

  def create
    return locked unless editable?
    user = current_club.members.active.find_by(id: params[:user_id])
    unless user
      redirect_to edit_admin_tournament_path(@tournament), alert: "Member not found." and return
    end
    @entry.tournament_entry_members.create!(user_id: user.id)
    redirect_to edit_admin_tournament_path(@tournament), notice: "Added #{user.name}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_admin_tournament_path(@tournament), alert: e.message
  end

  def destroy
    return locked unless editable?
    member = @entry.tournament_entry_members.find(params[:id])
    name = member.user&.name || "Member"
    member.destroy
    redirect_to edit_admin_tournament_path(@tournament), notice: "Removed #{name}."
  end

  private

  def load_tournament_and_entry
    @tournament = current_club.tournaments.find(params[:tournament_id])
    @entry = @tournament.tournament_entries.find(params[:tournament_entry_id])
  end

  def editable?
    @tournament.mode_team? && !@tournament.started?
  end

  def locked
    redirect_to edit_admin_tournament_path(@tournament),
                alert: "Roster is locked once the tournament starts."
  end
end
