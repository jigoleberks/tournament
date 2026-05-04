require "test_helper"

module Tournaments
  class RebalanceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @t = create(:tournament, club: @club, starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
    end

    test "broadcasts the leaderboard exactly once and enqueues no push jobs" do
      broadcast_calls = 0
      with_broadcast_stub(->(tournament:) { broadcast_calls += 1 }) do
        assert_no_enqueued_jobs only: DeliverPushNotificationJob do
          Tournaments::Rebalance.call(tournament: @t)
        end
      end
      assert_equal 1, broadcast_calls
    end

    private

    def with_broadcast_stub(callable)
      original = ::Placements::BroadcastLeaderboard.method(:call)
      ::Placements::BroadcastLeaderboard.define_singleton_method(:call) { |**kw| callable.call(**kw) }
      yield
    ensure
      ::Placements::BroadcastLeaderboard.singleton_class.remove_method(:call)
      ::Placements::BroadcastLeaderboard.define_singleton_method(:call, original)
    end
  end
end
