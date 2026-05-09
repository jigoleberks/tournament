require "test_helper"

class TournamentLifecycleAnnounceJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

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
    @t.update_columns(ends_at: 1.minute.ago)
    with_perform_later_capture do |enqueued|
      TournamentLifecycleAnnounceJob.perform_now(tournament_id: @t.id, kind: "ended")
      assert_equal 1, enqueued.size
      assert_match "ended", enqueued.first[:body]
    end
  end

  test "ended on a blind tournament fires the 'Results are in' body and a reveal broadcast" do
    @t.update_columns(blind_leaderboard: true, ends_at: 1.minute.ago)

    with_perform_later_capture do |enqueued|
      assert_broadcasts("tournament:#{@t.id}:leaderboard:reveal", 1) do
        TournamentLifecycleAnnounceJob.perform_now(tournament_id: @t.id, kind: "ended")
      end
      assert_equal 1, enqueued.size
      assert_equal "Results are in, GO CHECK YOUR STANDINGS", enqueued.first[:body]
    end

    @t.reload
    assert_not_nil @t.lifecycle_ended_announced_at
  end

  test "ended on a non-blind tournament uses the legacy body and does not broadcast reveal" do
    @t.update_columns(ends_at: 1.minute.ago)

    with_perform_later_capture do |enqueued|
      assert_broadcasts("tournament:#{@t.id}:leaderboard:reveal", 0) do
        TournamentLifecycleAnnounceJob.perform_now(tournament_id: @t.id, kind: "ended")
      end
      assert_match "ended", enqueued.first[:body]
    end

    @t.reload
    assert_not_nil @t.lifecycle_ended_announced_at
  end

  test "ended job is a no-op when lifecycle_ended_announced_at is already set" do
    @t.update_columns(lifecycle_ended_announced_at: 1.minute.ago, ends_at: 2.minutes.ago,
                      blind_leaderboard: true)

    with_perform_later_capture do |enqueued|
      assert_broadcasts("tournament:#{@t.id}:leaderboard:reveal", 0) do
        TournamentLifecycleAnnounceJob.perform_now(tournament_id: @t.id, kind: "ended")
      end
      assert_empty enqueued
    end
  end

  test "ended job is a no-op when ends_at is in the future (extended mid-tournament)" do
    @t.update_columns(ends_at: 1.hour.from_now, blind_leaderboard: true)

    with_perform_later_capture do |enqueued|
      assert_broadcasts("tournament:#{@t.id}:leaderboard:reveal", 0) do
        TournamentLifecycleAnnounceJob.perform_now(tournament_id: @t.id, kind: "ended")
      end
      assert_empty enqueued
    end

    @t.reload
    assert_nil @t.lifecycle_ended_announced_at
  end

  test "ended on a hidden_length tournament rolls the target and pushes the reveal body" do
    walleye = create(:species, club: @club)
    @t.scoring_slots.create!(species: walleye, slot_count: 1)
    @t.update!(format: :hidden_length, mode: :solo, kind: :event)
    @t.update_columns(ends_at: 1.minute.ago)

    with_perform_later_capture do |enqueued|
      TournamentLifecycleAnnounceJob.perform_now(tournament_id: @t.id, kind: "ended")
      @t.reload
      assert_not_nil @t.hidden_length_target
      assert_equal 1, enqueued.size
      assert_match "Target was", enqueued.first[:body]
      assert_match @t.hidden_length_target.to_s, enqueued.first[:body]
    end

    assert_not_nil @t.lifecycle_ended_announced_at
  end

  test "ended on a hidden_length tournament with future ends_at does not roll" do
    walleye = create(:species, club: @club)
    @t.scoring_slots.create!(species: walleye, slot_count: 1)
    @t.update!(format: :hidden_length, mode: :solo, kind: :event)
    @t.update_columns(ends_at: 1.hour.from_now)

    with_perform_later_capture do |enqueued|
      TournamentLifecycleAnnounceJob.perform_now(tournament_id: @t.id, kind: "ended")
      assert_empty enqueued
    end

    @t.reload
    assert_nil @t.hidden_length_target
    assert_nil @t.lifecycle_ended_announced_at
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
