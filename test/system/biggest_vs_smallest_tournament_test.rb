require "application_system_test_case"

class BiggestVsSmallestTournamentTest < ApplicationSystemTestCase
  include LengthHelper

  setup do
    @club = Club.first || create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @walleye = create(:species, club: @club, name: "Walleye")
    @angler_a = create(:user, club: @club, name: "Angler A")
    @angler_b = create(:user, club: @club, name: "Angler B")
  end

  test "Biggest vs Smallest tournament: leaderboard ranks by spread, biggest-first per row" do
    t = build(:tournament, club: @club, name: "BvS Wed",
              format: :biggest_vs_smallest, mode: :solo, kind: :event,
              starts_at: 30.minutes.ago, ends_at: 30.minutes.from_now)
    t.scoring_slots.build(species: @walleye, slot_count: 1)
    t.save!

    ea = create(:tournament_entry, tournament: t)
    eb = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: ea, user: @angler_a)
    create(:tournament_entry_member, tournament_entry: eb, user: @angler_b)

    # Angler A: 22, 12 → spread 10. Angler B: 18, 14 → spread 4.
    [
      [@angler_a, 22, 20.minutes.ago],
      [@angler_a, 12, 10.minutes.ago],
      [@angler_b, 18, 15.minutes.ago],
      [@angler_b, 14,  5.minutes.ago]
    ].each do |user, length, captured|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: @walleye,
                      length_inches: length, captured_at_device: captured)
      )
    end

    sign_in_as(@organizer)
    visit tournament_path(t)

    # Spread column header
    assert_text "Spread"

    # Two rows, one per entry
    rows = all("#leaderboard tbody tr")
    assert_equal 2, rows.size, "expected 2 per-entry rows"

    # Top row should reference Angler A (spread 10 > spread 4)
    assert_match "Angler A", rows.first.text, "expected Angler A (spread 10) on top"

    # Top row's spread renders via format_length_parts (two separate <div>s),
    # so assert on each part — full format_length_dual would not match the
    # newline-separated text of the score cell.
    inches_part, cm_part = format_length_parts(10)
    assert_match inches_part, rows.first.text
    assert_match cm_part,     rows.first.text

    # Top row should show Biggest 22.00" and Smallest 12.00"
    assert_match "Biggest", rows.first.text
    assert_match "Smallest", rows.first.text
    assert_match format_length_dual(22), rows.first.text
    assert_match format_length_dual(12), rows.first.text
  end

  private

  # Mirrors the helper used by test/system/big_fish_season_tournament_test.rb.
  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    visit consume_session_path(token: SignInToken.last.token)
  end
end
