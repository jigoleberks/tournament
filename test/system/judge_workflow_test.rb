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
    fill_in "note", with: "Looks fine to me"
    click_button "Approve"

    assert_text "Status: Synced"
    assert_text "Mike — approve"
  end

  test "judge disqualifies a catch and the leaderboard reflects it" do
    token = SignInToken.issue!(user: @judge)
    visit consume_session_path(token: token.token)

    visit tournament_path(@t)
    assert_text "22"   # currently in the leaderboard

    visit judges_tournament_catches_path(tournament_id: @t.id)
    click_link "Open"
    fill_in "note", with: "Mouth open"
    click_button "Disqualify"

    visit tournament_path(@t)
    assert_no_text "22"
  end
end
