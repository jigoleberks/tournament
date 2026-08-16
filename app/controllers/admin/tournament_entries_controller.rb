class Admin::TournamentEntriesController < Admin::BaseController
  before_action :load_tournament

  def create
    user_ids = Array(params.dig(:tournament_entry, :member_user_ids)).map(&:to_i).reject(&:zero?).uniq
    name = params.dig(:tournament_entry, :name)
    valid_ids = current_club.members.active.where(id: user_ids).pluck(:id)
    if valid_ids.size != user_ids.size
      redirect_to edit_admin_tournament_path(@tournament), alert: "One or more selected members are unavailable." and return
    end

    created_entry_ids = []
    Tournament.transaction do
      if @tournament.mode_solo?
        valid_ids.each do |uid|
          entry = @tournament.tournament_entries.create!
          entry.tournament_entry_members.create!(user_id: uid)
          created_entry_ids << entry.id
        end
      else
        entry = @tournament.tournament_entries.create!(name: name)
        valid_ids.each { |uid| entry.tournament_entry_members.create!(user_id: uid) }
        created_entry_ids << entry.id
      end
    end

    # Linked tournaments (the Wednesday Main + Side pair) share one roster:
    # mirror each new entry across the group. Solo entries have neither a boat
    # nor a name, so SyncEntry no-ops on them.
    TournamentEntry.where(id: created_entry_ids).each do |created|
      TournamentLinks::SyncEntry.call(entry: created)
    end

    # Adds are forward-only by default. With the admin-only backfill flag set,
    # replay the new entrants' already-logged in-window catches now — before the
    # broadcast below, so it reflects the backfilled standings. The sweep skips
    # already-placed catches, so on-time entrants are no-ops.
    if @tournament.backfill_late_entrants?
      Tournaments::BackfillEntrantCatches.call(
        tournament: @tournament, users: User.where(id: valid_ids).to_a
      )
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

    # Only the new entries' cards changed (bingo); leave existing anglers' cards alone.
    Placements::BroadcastLeaderboard.call(tournament: @tournament, changed_entry_ids: created_entry_ids)

    added = @tournament.mode_solo? ? valid_ids.size : 1
    redirect_to edit_admin_tournament_path(@tournament),
                notice: added == 1 ? "Entry added." : "#{added} entries added."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_admin_tournament_path(@tournament), alert: e.message
  end

  def update
    entry = @tournament.tournament_entries.find(params[:id])
    if entry.update(name: params.dig(:tournament_entry, :name).to_s.strip.presence)
      # A rename only affects the leaderboard row, not the bingo card grids.
      Placements::BroadcastLeaderboard.call(tournament: @tournament, changed_entry_ids: [entry.id])
      TournamentLinks::SyncEntry.call(entry: entry)
      redirect_to edit_admin_tournament_path(@tournament), notice: "Entry renamed."
    else
      redirect_to edit_admin_tournament_path(@tournament), alert: entry.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_admin_tournament_path(@tournament), alert: e.message
  end

  def destroy
    entry = @tournament.tournament_entries.find(params[:id])
    TournamentLinks::RemoveEntry.call(entry: entry)
    entry.destroy
    # The removed entry drops off the leaderboard; sibling cards are untouched.
    Placements::BroadcastLeaderboard.call(tournament: @tournament, changed_entry_ids: [entry.id])
    redirect_to edit_admin_tournament_path(@tournament), notice: "Entry removed."
  end

  private

  def load_tournament
    @tournament = current_club.tournaments.find(params[:tournament_id])
  end
end
