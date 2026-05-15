require "application_system_test_case"

class LakeFilterTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Filter Tester")
    @walleye = create(:species, club: @club, name: "Walleye")
    @tobin_catch = create(:catch,
      user: @user, species: @walleye, length_inches: 22.5,
      lake: "tobin", latitude: 53.55, longitude: -103.65,
      captured_at_device: 2.days.ago)
    @other_catch = create(:catch,
      user: @user, species: @walleye, length_inches: 18.0,
      lake: nil, captured_at_device: 1.day.ago)
  end

  test "picking Tobin Lake from the dropdown narrows the list to Tobin catches" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit catches_path(start: "", end: "")

    assert_text "My catches"
    assert_text "22.5"
    assert_text "18.0"

    find("select[name='lake']").find("option", text: "Tobin Lake").select_option
    page.execute_script("document.querySelector(\"select[name='lake']\").dispatchEvent(new Event('change', {bubbles: true}))")

    assert_no_text "18.0"
    assert_text "22.5"
    assert_match(/lake=tobin/, current_url)
  end

  test "picking Other shows only catches with no lake match" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit catches_path(start: "", end: "")

    find("select[name='lake']").find("option", text: "Other (no lake match)").select_option
    page.execute_script("document.querySelector(\"select[name='lake']\").dispatchEvent(new Event('change', {bubbles: true}))")

    assert_no_text "22.5"
    assert_text "18.0"
    assert_match(/lake=other/, current_url)
  end
end
