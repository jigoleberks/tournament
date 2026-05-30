require "application_system_test_case"

class LogbookButtonTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @original_logbook_enabled = ENV["LOGBOOK_ENABLED"]
  end

  teardown do
    if @original_logbook_enabled.nil?
      ENV.delete("LOGBOOK_ENABLED")
    else
      ENV["LOGBOOK_ENABLED"] = @original_logbook_enabled
    end
  end

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    visit consume_session_path(token: token.token)
  end

  test "Logbook button appears when LOGBOOK_ENABLED is truthy" do
    ENV["LOGBOOK_ENABLED"] = "true"

    sign_in_as(@user)
    visit root_path

    link = find("a", text: "Logbook", exact_text: true)
    assert_equal logbook_path, URI.parse(link[:href]).path
  end

  test "Logbook button accepts '1' as enabled" do
    ENV["LOGBOOK_ENABLED"] = "1"

    sign_in_as(@user)
    visit root_path

    assert_selector "a", text: "Logbook", exact_text: true
  end

  test "Logbook button is hidden when LOGBOOK_ENABLED is unset" do
    ENV.delete("LOGBOOK_ENABLED")

    sign_in_as(@user)
    visit root_path

    assert_no_selector "a", text: "Logbook", exact_text: true
  end

  test "Logbook button is hidden when LOGBOOK_ENABLED is blank" do
    ENV["LOGBOOK_ENABLED"] = ""

    sign_in_as(@user)
    visit root_path

    assert_no_selector "a", text: "Logbook", exact_text: true
  end

  test "Logbook button is hidden when LOGBOOK_ENABLED is a non-truthy value" do
    ENV["LOGBOOK_ENABLED"] = "false"

    sign_in_as(@user)
    visit root_path

    assert_no_selector "a", text: "Logbook", exact_text: true
  end
end
