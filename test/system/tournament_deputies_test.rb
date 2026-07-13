require "application_system_test_case"

class TournamentDeputiesTest < ApplicationSystemTestCase
  setup do
    @club      = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @member    = create(:user, club: @club, role: :member, name: "Deputy Dan")
    @upcoming  = create(:tournament, club: @club, starts_at: 2.hours.from_now, ends_at: 5.hours.from_now)
  end

  test "an organizer deputizes a member from the tournament builder" do
    sign_in_as(@organizer)
    visit edit_organizers_tournament_path(@upcoming)

    assert_text "Deputies"
    assert_text "No deputies yet."

    select "Deputy Dan", from: "tournament_deputy[user_id]"
    click_on "Add deputy"

    assert_text "Deputy Dan"
    assert TournamentDeputy.exists?(tournament: @upcoming, user: @member)
  end

  test "a deputy does not see the Deputies control" do
    create(:tournament_deputy, tournament: @upcoming, user: @member, granted_by_user: @organizer)
    sign_in_as(@member)
    visit edit_organizers_tournament_path(@upcoming)

    assert_text "Entries"
    assert_no_text "Add deputy"
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    visit consume_session_path(token: token.token)
  end
end
