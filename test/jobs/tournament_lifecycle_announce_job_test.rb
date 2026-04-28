require "test_helper"

class TournamentLifecycleAnnounceJobTest < ActiveJob::TestCase
  setup do
    @club = create(:club)
    @t = create(:tournament, club: @club, name: "Wed", starts_at: 1.hour.from_now, ends_at: 5.hours.from_now)
    @user = create(:user, club: @club)
    entry = create(:tournament_entry, tournament: @t)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)
  end

  test "fires a 'started' push to every entered user" do
    with_perform_later_capture do |enqueued|
      TournamentLifecycleAnnounceJob.perform_now(tournament_id: @t.id, kind: "started")
      assert_equal 1, enqueued.size
      assert_equal @user.id, enqueued.first[:user_id]
      assert_match "started", enqueued.first[:body]
    end
  end

  test "fires an 'ended' push" do
    with_perform_later_capture do |enqueued|
      TournamentLifecycleAnnounceJob.perform_now(tournament_id: @t.id, kind: "ended")
      assert_equal 1, enqueued.size
      assert_match "ended", enqueued.first[:body]
    end
  end

  private

  def with_perform_later_capture
    enqueued = []
    klass = DeliverPushNotificationJob
    klass.define_singleton_method(:perform_later_stub_orig, klass.method(:perform_later)) rescue nil
    klass.define_singleton_method(:perform_later) { |**kwargs| enqueued << kwargs }
    yield enqueued
  ensure
    klass.singleton_class.send(:remove_method, :perform_later)
  end
end
