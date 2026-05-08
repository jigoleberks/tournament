module Leaderboards
  class ViewerScope
    Scope = Struct.new(:visibility, :entry_id, keyword_init: true)

    # Precedence: judge > entered angler > organizer > non-entered member.
    # An entered organizer sees the angler view (so they can't peek at their own
    # tournament); a judge wins over angler so they can review live.
    def self.for(tournament:, user:)
      return full unless tournament.blind?

      if TournamentJudge.exists?(tournament_id: tournament.id, user_id: user.id)
        return full
      end

      entry_id = TournamentEntryMember
        .joins(:tournament_entry)
        .where(tournament_entries: { tournament_id: tournament.id }, user_id: user.id)
        .pick("tournament_entries.id")

      return Scope.new(visibility: :own_entry_only, entry_id: entry_id) if entry_id

      return full if user.organizer_in?(tournament.club)

      Scope.new(visibility: :entries_only, entry_id: nil)
    end

    def self.full
      Scope.new(visibility: :full, entry_id: nil)
    end
  end
end
