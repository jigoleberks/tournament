module Tournaments
  class TopThree
    def self.call(tournament:)
      rows = ::Leaderboards::Build.call(tournament: tournament)
      ::Leaderboards::QualifiedRows.call(tournament: tournament, rows: rows).first(3)
    end
  end
end
