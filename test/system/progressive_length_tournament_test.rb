require "application_system_test_case"

class ProgressiveLengthTournamentTest < ApplicationSystemTestCase
  include LengthHelper

  setup do
    @club = Club.first || create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @walleye = create(:species, club: @club, name: "Walleye")
    @angler_a = create(:user, club: @club, name: "Angler A")
    @angler_b = create(:user, club: @club, name: "Angler B")
  end

  test "Progressive Length leaderboard ranks by up-sizes and renders the ladder in order" do
    t = build(:tournament, club: @club, name: "Progressive Thu",
              format: :progressive_length, mode: :solo,
              starts_at: 3.hours.ago, ends_at: 1.hour.from_now)
    t.scoring_slots.build(species: @walleye, slot_count: 1)
    t.save!

    # Angler B's entry is created first so it gets the LOWER id, while Angler A
    # (the correct winner by up-sizes) gets the HIGHER id. This makes the
    # ranker's id-asc tiebreak fight against the correct ordering, so a
    # regression that dropped the up-sizes/race/top-rung sort keys (leaving
    # only the id tiebreak, or sorting purely by entry id) would surface B
    # first instead of A and fail the assertions below.
    eb = create(:tournament_entry, tournament: t)
    ea = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: ea, user: @angler_a)
    create(:tournament_entry_member, tournament_entry: eb, user: @angler_b)

    # Angler A climbs 12 → 15 → 18 (2 up-sizes). The 10" is a no-op.
    [[12, 150], [10, 140], [15, 120], [18, 100]].each do |len, mins|
      c = create(:catch, user: @angler_a, species: @walleye, length_inches: len,
                         captured_at_device: mins.minutes.ago, status: :synced)
      Catches::PlaceInSlots.call(catch: c, broadcast: false)
    end
    # Angler B climbs 20 → 22 (1 up-size) — bigger fish, fewer up-sizes.
    [[20, 150], [22, 120]].each do |len, mins|
      c = create(:catch, user: @angler_b, species: @walleye, length_inches: len,
                         captured_at_device: mins.minutes.ago, status: :synced)
      Catches::PlaceInSlots.call(catch: c, broadcast: false)
    end

    sign_in_as @organizer
    visit tournament_path(t)

    assert_text "Up-sizes"
    assert_text "most up-sizes of walleye"
    assert_no_text "Largest walleye"
    rows = all("#leaderboard tbody tr")
    assert_match "Angler A", rows[0].text
    assert_match "2 up-sizes", rows[0].text
    assert_match "Angler B", rows[1].text
    assert_match "1 up-size", rows[1].text
    # Ladder renders smallest-first; the 10" no-op never appears.
    assert_no_match(/10"/, rows[0].text)
    a_text = rows[0].text
    assert_operator a_text.index('12"'), :<, a_text.index('15"'),
                    "ladder must render smallest-first: 12\" before 15\""
    assert_operator a_text.index('15"'), :<, a_text.index('18"'),
                    "ladder must render smallest-first: 15\" before 18\""
  end

  test "organizer sees Progressive Length in the format select with one species row" do
    sign_in_as @organizer
    visit new_organizers_tournament_path

    select "Progressive Length", from: "Format"
    assert_text "Every fish must beat your previous fish"
    assert_text "Slots (ignored)"
  end

  private

  # Mirrors the helper used by test/system/biggest_vs_smallest_tournament_test.rb.
  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    assert_text "Check your email"  # wait for the POST to commit the token before reading it
    visit consume_session_path(token: SignInToken.last.token)
  end
end
