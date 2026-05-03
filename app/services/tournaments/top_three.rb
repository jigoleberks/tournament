module Tournaments
  class TopThree
    def self.call(tournament:)
      rows = ::Leaderboards::Build.call(tournament: tournament)
      rows.reject { |r| r[:fish].empty? }.first(3)
    end
  end
end
