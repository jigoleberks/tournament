module Leaderboards
  module Rankers
    # Sentinel timestamp for rows with no catch yet: sorts them after every real
    # catch timestamp. Built once at load time (Time.zone is fixed to UTC in this
    # app) and shared across rankers so it isn't reallocated on every .call.
    FAR_FUTURE = (::Time.zone.at(0) + 100.years).freeze
  end
end
