require "application_system_test_case"

class SignInTest < ApplicationSystemTestCase
  test "user can sign in via magic link" do
    user = create(:user, email: "joe@example.com", name: "Joe")

    visit new_session_path
    fill_in "Email", with: "joe@example.com"
    click_button "Send sign-in link"
    assert_text "Check your email"

    token = SignInToken.last.token
    visit consume_session_path(token: token)
    assert_text "Welcome, Joe"
  end
end
