require "test_helper"

class TournamentTest < ActiveSupport::TestCase
  setup { @club = create(:club) }

  test "requires name, kind, mode, starts_at" do
    assert_not Tournament.new(club: @club).valid?
  end

  test "kind enum: event and ongoing" do
    t = create(:tournament, club: @club, kind: :event)
    assert t.event?
    t.update!(kind: :ongoing)
    assert t.ongoing?
  end

  test "mode enum: solo and team" do
    t = create(:tournament, club: @club, mode: :team)
    assert t.mode_team?
  end

  test "active? is true when now is between starts_at and ends_at" do
    t = create(:tournament, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    assert t.active?
  end

  test "active? is true when ends_at is nil and starts_at has passed" do
    t = create(:tournament, starts_at: 1.day.ago, ends_at: nil)
    assert t.active?
  end

  test "active? is false before starts_at" do
    t = create(:tournament, starts_at: 1.hour.from_now)
    assert_not t.active?
  end

  test "ended? is true when ends_at is in the past" do
    t = create(:tournament, starts_at: 2.days.ago, ends_at: 1.hour.ago)
    assert t.ended?
  end

  test "ended? is false when ends_at is in the future" do
    t = create(:tournament, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    assert_not t.ended?
  end

  test "ended? is false when ends_at is nil" do
    t = create(:tournament, starts_at: 1.day.ago, ends_at: nil)
    assert_not t.ended?
  end

  test "friendly? is true by default and judged? is false" do
    t = create(:tournament, club: @club)
    assert t.friendly?
    assert_not t.judged?
  end

  test "judged? is true and friendly? is false when judged is set" do
    t = create(:tournament, club: @club, judged: true)
    assert t.judged?
    assert_not t.friendly?
  end
end
