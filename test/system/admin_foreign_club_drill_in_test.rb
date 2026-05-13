require "application_system_test_case"

class AdminForeignClubDrillInTest < ApplicationSystemTestCase
  setup do
    @host_club    = create(:club, name: "Host Anglers")
    @foreign_club = create(:club, name: "Northtown Anglers")
    @admin = create(:user, club: @host_club, admin: true, role: :organizer)
    create(:tournament, club: @foreign_club, name: "Northtown Spring Bash")
  end

  test "admin can drill from clubs index into a foreign club's tournaments via the hub" do
    token = SignInToken.issue!(user: @admin)
    visit consume_session_path(token: token.token)

    visit admin_clubs_path
    assert_text "Northtown Anglers"

    within("tr", text: "Northtown Anglers") do
      click_link "View"
    end

    # On the hub now
    assert_text "Viewing Northtown Anglers"
    assert_text "read-only"
    assert_selector "h1", text: "Northtown Anglers"
    assert_text "Tournaments"
    assert_text "Members"

    within("main") { click_link "Tournaments" }
    assert_text "Northtown Spring Bash"
  end
end
