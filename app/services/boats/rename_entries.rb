module Boats
  # Cascades a boat rename to every TournamentEntry the boat created — across
  # every tournament it has ever fished, finished ones included. Boats exist
  # so a team's name is typed once and reused (see NearMatch); a typo fixed
  # today on the boats screen should not go on haunting a leaderboard the boat
  # already fished under the old spelling. This is a correction to the one
  # name the boat has always had, not a rewrite of that night's roster.
  #
  # Matching is by NearMatch.normalize, not exact string equality, and that's
  # deliberate: rake boats:seed (Boats::SeedFromHistory#apply) attaches a
  # boat_id to every historical entry in its NearMatch-normalized group via a
  # bare update_all — it never rewrites those entries' names to the boat's
  # chosen "newest spelling". So right after a seed run, most of a boat's
  # entries carry names that have never once equalled boat.name; matching on
  # exact equality would only ever sweep the newest-spelling entries and
  # leave every older variant permanently stuck (their name would never equal
  # any future name_before_last_save either). Normalizing against the SAME
  # key SeedFromHistory grouped by re-admits those entries, and a human
  # already approved that grouping when they ran the seed.
  #
  # An entry whose normalized name has drifted from the boat's normalized old
  # name — e.g. "Majestic Red - DQ'd" — was hand-edited away from the boat
  # (via the entry-rename form) and is left alone; the cascade has no way to
  # tell "still tracking the boat" from "deliberately renamed to coincide"
  # after the fact, so an entry only counts as tracking once it stops
  # matching. Note NearMatch.normalize also strips a leading "Team "/"The ",
  # so an entry named e.g. "Team Majestic Red" now follows the boat too —
  # that's the same grouping decision already made at seed time, not a new
  # one made here.
  #
  # Linked pairs (the Wednesday Main + Side link_group) need no special
  # handling here: Boats::Enter and TournamentLinks::SyncEntry always copy
  # boat_id onto the mirrored counterpart, so both halves of a link already
  # carry boat_id and are reached by the same boat_id-keyed query.
  #
  # Broadcasting is handed off to BroadcastBoatRenameJob rather than done
  # inline: Placements::BroadcastLeaderboard renders synchronously, and for a
  # blind tournament (Catch the Average, Random Bag) it renders once for the
  # full board plus once per entry. A boat with a season of history can span
  # many tournaments, so doing that fan-out inline would make the PATCH
  # itself slow. The rename transaction still commits synchronously — only
  # the redraw is deferred. The job is enqueued after the transaction block
  # closes, not from inside it, for the same reason SyncEntry defers its push
  # notifications: a job enqueued (or a broadcast fired) for a write that
  # then rolls back would be a lie.
  class RenameEntries
    def self.call(boat:)
      new(boat: boat).call
    end

    def initialize(boat:)
      @boat = boat
    end

    def call
      return [] unless @boat.saved_change_to_name?

      entries = renamable_entries
      return [] if entries.empty?

      ::ActiveRecord::Base.transaction do
        entries.each { |entry| entry.update!(name: @boat.name) }
      end

      ::BroadcastBoatRenameJob.perform_later(entry_ids: entries.map(&:id))
      entries
    end

    private

    # Entries whose current name normalizes to the same key as the boat's OLD
    # name — the key SeedFromHistory grouped by (see class comment) — rather
    # than an exact string match.
    def renamable_entries
      old_key = ::Boats::NearMatch.normalize(@boat.name_before_last_save)
      return [] if old_key.blank?
      ::TournamentEntry.where(boat_id: @boat.id)
        .select { |entry| ::Boats::NearMatch.normalize(entry.name) == old_key }
    end
  end
end
