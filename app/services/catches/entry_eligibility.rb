module Catches
  class EntryEligibility
    # Returns an Array<Catch> of catches eligible to be placed for this
    # (entry, tournament, species) triple, ordered by length_inches DESC then
    # captured_at_device ASC.
    #
    # Eligibility rules:
    #   - The catch's user must currently be a member of the entry.
    #   - The catch's captured_at_device must fall within
    #     (max(tournament.starts_at, member.created_at) ..
    #      tournament.ends_at || Time.current).
    #   - The catch's species must match.
    #   - The catch must not be disqualified.
    #   - GPS-bearing catches must fall inside the Saskatchewan polygon, and
    #     for local tournaments, also inside the lake polygon. GPS-less
    #     catches are always allowed.
    def self.candidates_for(entry:, tournament:, species:)
      new(entry: entry, tournament: tournament, species: species).candidates
    end

    def initialize(entry:, tournament:, species:)
      @entry = entry
      @tournament = tournament
      @species = species
    end

    def candidates
      window_end = @tournament.ends_at || Time.current
      ::Catch
        .joins("INNER JOIN tournament_entry_members tem ON tem.user_id = catches.user_id")
        .where("tem.tournament_entry_id = ?", @entry.id)
        .where("catches.captured_at_device >= GREATEST(?, tem.created_at)", @tournament.starts_at)
        .where("catches.captured_at_device <= ?", window_end)
        .where(species_id: @species.id)
        .where.not(status: ::Catch.statuses[:disqualified])
        .order(length_inches: :desc, captured_at_device: :asc)
        .distinct
        .to_a
        .select { |c| geofence_ok?(c) }
    end

    private

    def geofence_ok?(catch_record)
      return true if catch_record.latitude.nil?
      return false unless ::Geofence.includes?(:sask, catch_record.latitude, catch_record.longitude)
      return true unless @tournament.local?
      ::Geofence.includes?(:lake, catch_record.latitude, catch_record.longitude)
    end
  end
end
