require "application_system_test_case"

class SmallestFishTournamentTest < ApplicationSystemTestCase
  include LengthHelper

  setup do
    @club = Club.first || create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @walleye = create(:species, club: @club, name: "Walleye")
    @angler_a = create(:user, club: @club, name: "Angler A")
    @angler_b = create(:user, club: @club, name: "Angler B")
  end

  test "Smallest Fish tournament: leaderboard ranks by lowest total, smallest-first per row" do
    t = build(:tournament, club: @club, name: "Smallest Wed",
              format: :smallest_fish, mode: :solo, kind: :event,
              starts_at: 30.minutes.ago, ends_at: 30.minutes.from_now)
    t.scoring_slots.build(species: @walleye, slot_count: 2)
    t.save!

    ea = create(:tournament_entry, tournament: t)
    eb = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: ea, user: @angler_a)
    create(:tournament_entry_member, tournament_entry: eb, user: @angler_b)

    # Angler A: 12, 10 → total 22. Angler B: 9, 8 → total 17 (lower wins).
    [
      [@angler_a, 12, 20.minutes.ago],
      [@angler_a, 10, 10.minutes.ago],
      [@angler_b,  9, 15.minutes.ago],
      [@angler_b,  8,  5.minutes.ago]
    ].each do |user, length, captured|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: @walleye,
                      length_inches: length, captured_at_device: captured)
      )
    end

    sign_in_as(@organizer)
    visit tournament_path(t)

    # Standard "Total" score column header.
    assert_text "Total"

    rows = all("#leaderboard tbody tr")
    assert_equal 2, rows.size, "expected 2 per-entry rows"

    # Top row should be Angler B (total 17 < total 22).
    assert_match "Angler B", rows.first.text, "expected Angler B (total 17) on top"

    # Top row's total renders via format_length_parts (two separate parts).
    inches_part, cm_part = format_length_parts(17)
    assert_match inches_part, rows.first.text
    assert_match cm_part,     rows.first.text

    # Top row shows both of B's fish.
    assert_match format_length_dual(8, "inches"), rows.first.text
    assert_match format_length_dual(9, "inches"), rows.first.text
  end

  test "selecting Smallest Fish on the form keeps the multi-row scoring-slot UI" do
    pike = create(:species, club: @club, name: "Pike")

    tournament = create(:tournament, club: @club, name: "Smallest Draft",
                                     mode: :solo, format: :standard, kind: :event,
                                     starts_at: 1.day.from_now, ends_at: 2.days.from_now)
    create(:scoring_slot, tournament: tournament, species: @walleye, slot_count: 2)
    create(:scoring_slot, tournament: tournament, species: pike,     slot_count: 1)

    sign_in_as(@organizer)
    visit edit_organizers_tournament_path(tournament)

    select "Smallest Fish", from: "Format"
    click_button "Update Tournament"

    assert_current_path organizers_tournaments_path
    tournament.reload
    assert tournament.format_smallest_fish?
    # Standard-style: both species' scoring slots are preserved.
    assert_equal 2, tournament.scoring_slots.count
  end

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    assert_text "Check your email"  # wait for the POST to commit the token before reading it
    visit consume_session_path(token: SignInToken.last.token)
  end
end
