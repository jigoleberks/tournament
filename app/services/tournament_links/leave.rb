module TournamentLinks
  # Drops one tournament out of its link group. Entries already created stay
  # exactly where they are on both sides — unlinking stops future mirroring, it
  # never deletes a roster. When only one tournament is left in the group, its
  # id is cleared too so it isn't left "linked" to nothing.
  class Leave
    def self.call(tournament:)
      new(tournament: tournament).call
    end

    def initialize(tournament:)
      @tournament = tournament
    end

    def call
      remaining = @tournament.linked_tournaments
      @tournament.update!(link_group_id: nil)
      remaining.first.update!(link_group_id: nil) if remaining.size == 1
    end
  end
end
