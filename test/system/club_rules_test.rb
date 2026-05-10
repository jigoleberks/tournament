require "application_system_test_case"

class ClubRulesTest < ApplicationSystemTestCase
  setup do
    @club = Club.first || create(:club)
    @organizer = create(:user, club: @club, role: :organizer, name: "Aron Funk")
    @member    = create(:user, club: @club, role: :member,    name: "Joe Fisher")
  end

  test "organizer creates open-water rules; member sees them on /rules" do
    sign_in_as(@organizer)
    visit admin_rules_path
    click_on "Edit (new revision)", match: :first  # open_water card
    fill_in "Body (Markdown)", with: "# Open water rules\n\n- No live bait"
    click_on "Save revision"

    assert_text "New revision saved."

    sign_in_as(@member)
    visit root_path
    assert_text "Rules ("  # button visible
    find("a", text: /^Rules \(/).click
    assert_text "Open water rules"
    assert_text "No live bait"
    assert_text "Last edited"
    assert_no_text "Aron Funk"   # member should NOT see editor name
  end

  test "organizer toggles active season; home button date follows the active set" do
    create(:club_rules_revision, club: @club, edited_by_user: @organizer,
                                 season: :open_water, body: "ow",
                                 created_at: Time.zone.local(2026, 5, 9, 10))
    create(:club_rules_revision, club: @club, edited_by_user: @organizer,
                                 season: :ice, body: "ice",
                                 created_at: Time.zone.local(2026, 1, 1, 10))

    sign_in_as(@member)
    visit root_path
    assert_text "Rules (May 9, 2026)"

    sign_in_as(@organizer)
    visit admin_rules_path
    click_on "Ice"  # the active-season toggle button labelled "Ice"
    assert_text "Active season set to Ice."

    sign_in_as(@member)
    visit root_path
    assert_text "Rules (Jan 1, 2026)"
  end

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    visit consume_session_path(token: SignInToken.last.token)
  end
end
