require "test_helper"

class TournamentsHelperTest < ActionView::TestCase
  setup do
    @club = create(:club)
  end

  def team_with_members(tournament, name:, member_names:)
    entry = create(:tournament_entry, tournament: tournament, name: name)
    member_names.each do |n|
      create(:tournament_entry_member, tournament_entry: entry,
                                        user: create(:user, club: @club, name: n))
    end
    entry
  end

  test "returns the joined member names for an ended team tournament with a custom-named entry" do
    t = create(:tournament, club: @club, mode: :team,
               starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    entry = team_with_members(t, name: "Reel Deal", member_names: ["Alice", "Bob"])

    assert_equal "Alice + Bob", team_roster_line(t, entry)
  end

  test "returns nil when the tournament has not ended yet" do
    t = create(:tournament, club: @club, mode: :team,
               starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    entry = team_with_members(t, name: "Reel Deal", member_names: ["Alice", "Bob"])

    assert_nil team_roster_line(t, entry)
  end

  test "returns nil when the entry has no custom name" do
    t = create(:tournament, club: @club, mode: :team,
               starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    entry = team_with_members(t, name: nil, member_names: ["Alice", "Bob"])

    assert_nil team_roster_line(t, entry)
  end

  test "returns nil for a solo tournament" do
    t = create(:tournament, club: @club, mode: :solo,
               starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    entry = team_with_members(t, name: "Reel Deal", member_names: ["Alice"])

    assert_nil team_roster_line(t, entry)
  end
end
