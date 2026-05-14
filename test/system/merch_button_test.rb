require "application_system_test_case"

class MerchButtonTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @original_merch_url = ENV["MERCH_URL"]
  end

  teardown do
    if @original_merch_url.nil?
      ENV.delete("MERCH_URL")
    else
      ENV["MERCH_URL"] = @original_merch_url
    end
  end

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    visit consume_session_path(token: token.token)
  end

  test "Merch button appears with configured URL when MERCH_URL is set" do
    ENV["MERCH_URL"] = "https://example.test/merch"

    sign_in_as(@user)
    visit root_path

    link = find("a", text: "Merch")
    assert_equal "https://example.test/merch", link[:href]
    assert_equal "_blank", link[:target]
    assert_includes link[:rel].to_s, "noopener"
    assert_includes link[:rel].to_s, "noreferrer"
  end

  test "Merch button is hidden when MERCH_URL is unset" do
    ENV.delete("MERCH_URL")

    sign_in_as(@user)
    visit root_path

    assert_no_selector "a", text: "Merch"
  end

  test "Merch button is hidden when MERCH_URL is set to a blank string" do
    ENV["MERCH_URL"] = ""

    sign_in_as(@user)
    visit root_path

    assert_no_selector "a", text: "Merch"
  end
end
