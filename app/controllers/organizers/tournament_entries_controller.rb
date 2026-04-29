class Organizers::TournamentEntriesController < Organizers::BaseController
  before_action :load_tournament

  def create
    user_ids = Array(params.dig(:tournament_entry, :member_user_ids)).map(&:to_i).reject(&:zero?).uniq
    name = params.dig(:tournament_entry, :name)
    valid_ids = current_user.club.users.active.where(id: user_ids).pluck(:id)
    if valid_ids.size != user_ids.size
      redirect_to edit_organizers_tournament_path(@tournament), alert: "One or more selected members are unavailable." and return
    end

    Tournament.transaction do
      entry = @tournament.tournament_entries.create!(name: name)
      valid_ids.each { |uid| entry.tournament_entry_members.create!(user_id: uid) }
    end

    redirect_to edit_organizers_tournament_path(@tournament), notice: "Entry added."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_organizers_tournament_path(@tournament), alert: e.message
  end

  def destroy
    entry = @tournament.tournament_entries.find(params[:id])
    entry.destroy
    redirect_to edit_organizers_tournament_path(@tournament), notice: "Entry removed."
  end

  private

  def load_tournament
    @tournament = current_user.club.tournaments.find(params[:tournament_id])
  end
end
