class Admin::TournamentEntryMembersController < Admin::BaseController
  before_action :load_tournament_and_entry

  def create
    unless @tournament.mode_team?
      return redirect_to edit_admin_tournament_path(@tournament),
                         alert: "Solo entries can't have additional members; create a new entry instead."
    end
    user = current_club.members.active.find_by(id: params[:user_id])
    unless user
      redirect_to edit_admin_tournament_path(@tournament), alert: "Member not found." and return
    end
    # Adds are forward-only: catches the user already logged in this tournament's
    # window before being added to the entry are NOT retroactively placed. Only
    # catches submitted after this point flow through PlaceInSlots for this entry.
    @entry.tournament_entry_members.create!(user_id: user.id)
    redirect_to edit_admin_tournament_path(@tournament), notice: "Added #{user.name}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_admin_tournament_path(@tournament), alert: e.message
  end

  def destroy
    unless @tournament.mode_team?
      return redirect_to edit_admin_tournament_path(@tournament),
                         alert: "Solo entries don't have removable members; remove the entry itself."
    end
    member = @entry.tournament_entry_members.find(params[:id])
    name = member.user&.name || "Member"
    Catches::DropMemberFromEntry.call(entry: @entry, user: member.user)
    redirect_to edit_admin_tournament_path(@tournament), notice: "Removed #{name}."
  end

  private

  def load_tournament_and_entry
    @tournament = current_club.tournaments.find(params[:tournament_id])
    @entry = @tournament.tournament_entries.find(params[:tournament_entry_id])
  end
end
