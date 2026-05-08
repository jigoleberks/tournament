class Admin::TournamentEntriesController < Admin::BaseController
  before_action :load_tournament

  def create
    user_ids = Array(params.dig(:tournament_entry, :member_user_ids)).map(&:to_i).reject(&:zero?).uniq
    name = params.dig(:tournament_entry, :name)
    valid_ids = current_club.members.active.where(id: user_ids).pluck(:id)
    if valid_ids.size != user_ids.size
      redirect_to edit_admin_tournament_path(@tournament), alert: "One or more selected members are unavailable." and return
    end

    Tournament.transaction do
      if @tournament.mode_solo?
        valid_ids.each do |uid|
          entry = @tournament.tournament_entries.create!
          entry.tournament_entry_members.create!(user_id: uid)
        end
      else
        entry = @tournament.tournament_entries.create!(name: name)
        valid_ids.each { |uid| entry.tournament_entry_members.create!(user_id: uid) }
      end
    end

    valid_ids.each do |uid|
      DeliverPushNotificationJob.perform_later(
        user_id: uid,
        title: @tournament.name,
        body: "You've been entered into #{@tournament.name}.",
        url: "/tournaments/#{@tournament.id}",
        tournament_id: @tournament.id
      )
    end

    Placements::BroadcastLeaderboard.call(tournament: @tournament)

    added = @tournament.mode_solo? ? valid_ids.size : 1
    redirect_to edit_admin_tournament_path(@tournament),
                notice: added == 1 ? "Entry added." : "#{added} entries added."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_admin_tournament_path(@tournament), alert: e.message
  end

  def update
    entry = @tournament.tournament_entries.find(params[:id])
    if entry.update(name: params.dig(:tournament_entry, :name).to_s.strip.presence)
      Placements::BroadcastLeaderboard.call(tournament: @tournament)
      redirect_to edit_admin_tournament_path(@tournament), notice: "Entry renamed."
    else
      redirect_to edit_admin_tournament_path(@tournament), alert: entry.errors.full_messages.to_sentence
    end
  end

  def destroy
    entry = @tournament.tournament_entries.find(params[:id])
    entry.destroy
    Placements::BroadcastLeaderboard.call(tournament: @tournament)
    redirect_to edit_admin_tournament_path(@tournament), notice: "Entry removed."
  end

  private

  def load_tournament
    @tournament = current_club.tournaments.find(params[:tournament_id])
  end
end
