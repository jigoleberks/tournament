require "application_system_test_case"

class SeasonPointsTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @walleye = create(:species, club: @club)
    @member = create(:user, club: @club, name: "Member")
  end

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    visit consume_session_path(token: token.token)
  end

  # Builds a finished, points-eligible tournament. Catches' captured_at_device is set
  # to a timestamp inside the window so PlaceInSlots actually places them.
  def build_finished_solo_tournament(season_tag:, ends_at: 1.day.ago, names_with_lengths:)
    starts_at = ends_at - 4.hours
    in_window = ends_at - 1.hour
    t = create(:tournament, club: @club, mode: :solo, awards_season_points: true,
               season_tag: season_tag, starts_at: starts_at, ends_at: ends_at, name: "League Night")
    create(:scoring_slot, tournament: t, species: @walleye, slot_count: 2)
    names_with_lengths.each do |name, lengths|
      u = create(:user, club: @club, name: name)
      e = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: e, user: u)
      lengths.each do |len|
        Catches::PlaceInSlots.call(catch: create(:catch, user: u, species: @walleye, length_inches: len, captured_at_device: in_window))
      end
    end
    t
  end

  test "no standings section when no points-eligible tournaments" do
    sign_in_as(@member)
    visit root_path
    assert_no_text "standings"
  end

  test "shows top 5 with correct points for a 10-angler solo tournament" do
    names_with_lengths = (1..10).map { |i| ["Angler #{i}", [25 - i]] }.to_h
    build_finished_solo_tournament(season_tag: "Wednesday 2026", names_with_lengths: names_with_lengths)

    sign_in_as(@member)
    visit root_path

    assert_text(/Wednesday 2026.*standings/i)
    within("section", text: /Wednesday 2026.*standings/i) do
      assert_text "1. Angler 1"
      assert_text "6.5 pts"
      assert_text "2. Angler 2"
      assert_text "4.5 pts"
      assert_text "3. Angler 3"
      assert_text "2.5 pts"
      # 4th and 5th appear with the 0.5 attendance bonus (the partial caps at 5)
      assert_text "0.5 pts"
      # 6th onward (Angler 5-9) are not shown by the top-5 partial
      assert_no_text "6. Angler"
    end
  end

  test "view full standings page shows all entered anglers including 0.5 attendance bonus" do
    names_with_lengths = (1..10).map { |i| ["Angler #{i}", [25 - i]] }.to_h
    build_finished_solo_tournament(season_tag: "Wednesday 2026", names_with_lengths: names_with_lengths)

    sign_in_as(@member)
    visit season_points_path

    assert_text(/Wednesday 2026.*standings/i)
    # Top 3 receive placement points plus the 0.5 attendance bonus
    assert_text "Angler 1"
    assert_text "6.5"
    assert_text "Angler 2"
    assert_text "4.5"
    assert_text "Angler 3"
    assert_text "2.5"
    # 4th and beyond now appear in standings with the bonus only
    assert_text "Angler 4"
    assert_text "0.5"
    assert_link "Past league nights →"
  end

  test "past league nights page lists ended points-eligible tournaments with winner" do
    t = build_finished_solo_tournament(
      season_tag: "Wednesday 2026",
      ends_at: 1.week.ago,
      names_with_lengths: { "Winner" => [25], "Second" => [20], "Third" => [15] }
    )
    t.update!(name: "League Night #1")

    sign_in_as(@member)
    visit season_points_tournaments_path

    assert_text(/Wednesday 2026 league nights/i)
    assert_text "League Night #1"
    assert_text "Won by: Winner"
    click_link "League Night #1"
    assert_current_path tournament_path(t)
  end
end
