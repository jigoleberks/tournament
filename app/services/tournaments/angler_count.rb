module Tournaments
  class AnglerCount
    def self.call(tournament:)
      ::TournamentEntryMember
        .joins(:tournament_entry)
        .where(tournament_entries: { tournament_id: tournament.id })
        .distinct
        .count(:user_id)
    end
  end
end
