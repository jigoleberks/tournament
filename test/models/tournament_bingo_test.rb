# test/models/tournament_bingo_test.rb
require "test_helper"

class TournamentBingoTest < ActiveSupport::TestCase
  def club = Club.create!(name: "Test Club")

  def build_bingo(**attrs)
    Tournament.new(
      club: club, name: "Bingo Night", mode: :solo, format: :bingo,
      starts_at: 1.hour.from_now, ends_at: 4.hours.from_now, **attrs
    )
  end

  test "creating a bingo tournament auto-assigns a valid random layout" do
    t = build_bingo
    assert t.save, t.errors.full_messages.to_sentence
    assert_equal 25, t.bingo_layout.size
    assert_equal "free", t.bingo_layout[12]
    assert_equal Catches::Bingo::Tasks.keys.sort, (t.bingo_layout - ["free"]).sort
  end

  test "a malformed layout is rejected" do
    t = build_bingo
    t.bingo_layout = ["free"] * 25
    assert_not t.valid?
    assert t.errors[:bingo_layout].any?
  end

  test "layout is locked once the tournament has started" do
    t = build_bingo(starts_at: 1.hour.ago, ends_at: 2.hours.from_now)
    t.save!(validate: false)
    t.bingo_layout = Catches::Bingo::Tasks.random_layout
    assert_not t.valid?
    assert t.errors[:bingo_layout].any?
  end

  test "non-bingo tournaments do not get a layout" do
    t = Tournament.create!(club: club, name: "Std", mode: :solo, format: :standard,
                           starts_at: 1.hour.from_now, ends_at: 4.hours.from_now)
    assert_nil t.bingo_layout
  end

  test "switching an existing unstarted tournament to bingo assigns a layout on update" do
    t = Tournament.create!(club: club, name: "Std", mode: :solo, format: :standard,
                           starts_at: 1.hour.from_now, ends_at: 4.hours.from_now)
    assert_nil t.bingo_layout
    assert t.update(format: :bingo), t.errors.full_messages.to_sentence
    assert t.format_bingo?
    assert_equal 25, t.bingo_layout.size
    assert_equal "free", t.bingo_layout[12]
  end

  test "PERCH_NAME and PIKE_NAME constants exist" do
    assert_equal "Perch", Species::PERCH_NAME
    assert_equal "Pike", Species::PIKE_NAME
  end

  test "bingo tournament with blind_leaderboard true is invalid" do
    t = build_bingo(blind_leaderboard: true)
    assert_not t.valid?
    assert t.errors[:blind_leaderboard].any?
  end

  test "bingo tournament with blind_leaderboard false is valid" do
    t = build_bingo(blind_leaderboard: false)
    assert t.valid?, t.errors.full_messages.to_sentence
  end
end
