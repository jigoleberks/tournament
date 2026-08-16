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
    # "Team Magestic Red" arrive as one boat rather than three.
    def grouped_entries
      ::TournamentEntry
        .joins(:tournament)
        .where(tournaments: { club_id: @club.id, mode: ::Tournament.modes[:team] })
        .where.not(name: [nil, ""])
        .includes(:tournament, tournament_entry_members: :user)
        .group_by { |entry| NearMatch.normalize(entry.name) }
    end

    def propose(_key, entries)
      nights = entries.map { |e| e.tournament.starts_at.to_date }.uniq.size
      crews = entries.map { |e| e.tournament_entry_members.map(&:user_id) }
      constant_ids = crews.reduce(:&) || []

      captain_id, signal =
        if constant_ids.size == 1
          [constant_ids.first, :constant_member]
        elsif constant_ids.size > 1
          proxy = busiest_proxy_logger(entries, constant_ids)
          proxy ? [proxy, :proxy_logger] : [nil, :none]
        else
          [nil, :none]
        end

      {
        name: newest_spelling(entries),
        captain: captain_id ? ::User.find_by(id: captain_id) : nil,
        signal: signal,
        nights: nights,
        entry_ids: entries.map(&:id)
      }
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

    def apply(proposals)
      proposals.each do |proposal|
        next if proposal[:captain].nil?
        boat = @club.boats.create!(name: proposal[:name], captain: proposal[:captain])
        ::TournamentEntry.where(id: proposal[:entry_ids]).update_all(boat_id: boat.id)
        proposal[:boat] = boat
      end
    end
  end
end
