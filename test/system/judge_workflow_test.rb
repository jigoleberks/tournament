require "application_system_test_case"

class JudgeWorkflowTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @walleye = create(:species, club: @club)
    @t = create(:tournament, club: @club, name: "Wed", starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)

    @judge = create(:user, club: @club, name: "Mike")
    create(:tournament_judge, tournament: @t, user: @judge)

    angler = create(:user, club: @club, name: "Joe")
    entry = create(:tournament_entry, tournament: @t)
    create(:tournament_entry_member, tournament_entry: entry, user: angler)

    @suspect_catch = create(:catch, user: angler, species: @walleye, length_inches: 22, status: :needs_review)
    Catches::PlaceInSlots.call(catch: @suspect_catch)
  end

  test "judge approves a flagged catch" do
    token = SignInToken.issue!(user: @judge)
    visit consume_session_path(token: token.token)

    visit judges_tournament_catches_path(tournament_id: @t.id)
    click_link "Open"
    # The catch page now carries several "note" fields (geofence-override,
    # reinstate); target the review form's by its label to stay unambiguous.
    fill_in "Note (required if disqualifying)", with: "Looks fine to me"
    click_button "Approve"

    assert_text "Status: Synced"
    assert_text "Mike — approve"
  end

  test "judge disqualifies a catch and the leaderboard reflects it" do
    token = SignInToken.issue!(user: @judge)
    visit consume_session_path(token: token.token)

    visit tournament_path(@t)
    # Use the inch-mark suffix so "22" doesn't false-match the wall-clock minute
    # in the rendered ends_at timestamp (e.g. "3:22 AM"). The per-fish label
    # renders a factory-default inches catch as `22"` (native unit, no decimals).
    assert_text '22"'

    visit judges_tournament_catches_path(tournament_id: @t.id)
    click_link "Open"
    fill_in "Note (required if disqualifying)", with: "Mouth open"
    click_button "Disqualify"

    # Wait for the disqualify to commit (status + audit line render) before
    # visiting the leaderboard, else under parallel load the visit can race the
    # DQ request and still find the catch placed.
    assert_text "Status: Disqualified"
    assert_text "Mike — disqualify"

    visit tournament_path(@t)
    assert_no_text '22"'
  end
end
