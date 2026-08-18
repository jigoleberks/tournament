module Boats
  # Reads a club's existing named team entries and proposes one boat per
  # distinct name, with a captain guessed from two independent signals that
  # agree in practice: the member aboard every night that boat fishes, and the
  # member who logs catches for the rest of the crew.
  #
  # Defaults to a dry run so the proposals can be read before anything is
  # written — the captain list is reviewed by a human, not assumed.
  class SeedFromHistory
    def self.call(club:, dry_run: true)
      new(club: club, dry_run: dry_run).call
    end

    def initialize(club:, dry_run:)
      @club = club
      @dry_run = dry_run
    end

    def call
      proposals = grouped_entries.map { |key, entries| propose(key, entries) }
      proposals.sort_by! { |p| -p[:nights] }
      apply(proposals) unless @dry_run
      proposals
    end

    private

    # Distinct boat names across the club's team tournaments, grouped by the
    # same normalization the near-match guard uses, so "Majestic red" and
    # "Team Magestic Red" arrive as one boat rather than three. A
    # whitespace-only entry name normalizes to "" and would otherwise form its
    # own (unsaveable) group, so it's dropped here rather than proposed.
    def grouped_entries
      ::TournamentEntry
        .joins(:tournament)
        .where(tournaments: { club_id: @club.id, mode: ::Tournament.modes[:team] })
        .where.not(name: [nil, ""])
        .includes(:tournament, tournament_entry_members: :user)
        .group_by { |entry| NearMatch.normalize(entry.name) }
        .reject { |key, _| key.blank? }
    end

    def propose(_key, entries)
      nights = entries.map { |e| e.tournament.starts_at.to_date }.uniq.size
      crews = entries.map { |e| e.tournament_entry_members.map(&:user_id) }
      constant_ids = crews.reduce(:&) || []
      active_constant_ids = active_member_ids(constant_ids)

      captain_id, signal =
        if active_constant_ids.size == 1
          [active_constant_ids.first, :constant_member]
        elsif active_constant_ids.size > 1
          proxy = busiest_proxy_logger(entries, active_constant_ids)
          proxy ? [proxy, :proxy_logger] : [nil, :none]
        else
          [nil, :none]
        end

      name = newest_spelling(entries)
      captain = captain_id ? ::User.find_by(id: captain_id) : nil

      {
        name: name,
        captain: captain,
        signal: signal,
        nights: nights,
        entry_ids: entries.map(&:id),
        errors: writability_errors(name, captain) + same_night_errors(entries)
      }
    end

    # A group is built across the whole club, but one boat can hold at most one
    # entry per tournament — index_tournament_entries_on_tournament_and_boat_uniq
    # is unique on [tournament_id, boat_id] where boat_id is not null. So a night
    # that ran both "Team Loos" and "Loos" lands two same-tournament entries in
    # one group, and apply's update_all writes the same boat_id across both.
    #
    # That can't reach the index today: TournamentEntryMember's
    # user_not_already_in_tournament keeps the two crews disjoint, so the
    # group's crew intersection is empty, no captain is proposed, and apply
    # skips it. What the organizer sees instead is a boat stuck on "— pick one
    # —" for no visible reason. So this exists to say why — and to stop the
    # write outright for rows that predate that validation or were made by
    # hand in SQL, where the index would raise RecordNotUnique: a
    # StatementInvalid, which escapes the rake task as a stack trace rather
    # than the clean rollback everything else here gets.
    def same_night_errors(entries)
      entries.group_by(&:tournament_id).filter_map do |_, night|
        next if night.size < 2
        spellings = night.map { |e| e.name.to_s.strip }.uniq.sort
        "#{night.first.tournament.name} has #{night.size} entries in this group " \
          "(#{spellings.to_sentence}) — one boat can't hold two entries in one " \
          "tournament; rename or merge them before seeding"
      end
    end

    # A departed member can still be the constant crew in old entries, but
    # Boat requires an active captain — proposing them would only fail at
    # save time, so they're filtered out of consideration entirely and the
    # group falls through to the proxy-logger signal, or to :none.
    #
    # with_active_user, not active: deactivating a member writes
    # users.deactivated_at and never the membership's own column, so `active`
    # alone filters nobody out and this seeds boats captained by anglers who
    # have left. See ClubMembership.
    def active_member_ids(ids)
      return [] if ids.empty?
      ::ClubMembership.with_active_user.where(club_id: @club.id, user_id: ids).pluck(:user_id)
    end

    # Validates a would-be boat without saving it, so the preview can flag a
    # proposal that looks clean but would actually fail to write — most often
    # a name collision with a boat that already exists in the club — before a
    # human approves a real run against it.
    def writability_errors(name, captain)
      return [] if captain.nil?
      boat = @club.boats.new(name: name, captain: captain)
      boat.valid?
      boat.errors.full_messages
    end

    # The most recent spelling wins — it's the one the organizers are using now.
    def newest_spelling(entries)
      entries.max_by { |e| e.tournament.starts_at }.name.to_s.strip
    end

    # Among tied candidates, whoever logged the most catches on someone else's
    # behalf during those tournaments' windows.
    def busiest_proxy_logger(entries, candidate_ids)
      windows = entries.map { |e| [e.tournament.starts_at, e.tournament.ends_at] }
      counts = Hash.new(0)
      candidate_ids.each do |uid|
        windows.each do |starts_at, ends_at|
          counts[uid] += ::Catch.where(logged_by_user_id: uid)
                              .where.not(user_id: uid)
                              .where(captured_at_device: starts_at..ends_at)
                              .count
        end
      end
      best = counts.max_by { |_, n| n }
      return nil if best.nil? || best.last.zero?
      return nil if counts.values.count(best.last) > 1
      best.first
    end

    # A club with 15 boats of history and one bad proposal (a stale name
    # collision, most likely) must not come out half-seeded and unrerunnable —
    # so the whole batch lives in one transaction, and a save failure anywhere
    # rolls all of it back rather than leaving the good boats standing.
    def apply(proposals)
      attempted = proposals.select { |proposal| proposal[:captain] }
      created = []

      ::Boat.transaction do
        attempted.each do |proposal|
          # A proposal the dry checks already rejected — a name collision, or
          # two entries from one night in the same group — can't be written.
          # Stop the batch here rather than discovering it mid-write, so the
          # rollback is the same clean all-or-nothing one a save failure gets.
          raise ActiveRecord::Rollback if proposal[:errors].any?

          boat = @club.boats.new(name: proposal[:name], captain: proposal[:captain])
          unless boat.save
            proposal[:errors] = boat.errors.full_messages
            raise ActiveRecord::Rollback
          end
          ::TournamentEntry.where(id: proposal[:entry_ids]).update_all(boat_id: boat.id)
          created << [proposal, boat]
        end
      end

      # Only mark proposals as created once the transaction above actually
      # committed everything — a mid-batch failure rolls back silently
      # (ActiveRecord::Rollback doesn't re-raise), so `created` can be
      # shorter than `attempted` with nothing in the database to show for it.
      created.each { |proposal, boat| proposal[:boat] = boat } if created.size == attempted.size
    end
  end
end
