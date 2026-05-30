require "test_helper"

class OfflinePageTest < ActionDispatch::IntegrationTest
  test "GET /offline renders without a signed-in user" do
    get "/offline"
    assert_response :success
    assert_select "h1", text: /log catch/i
  end

  test "offline page does not require authentication and shows no user chrome" do
    get "/offline"
    assert_response :success
    # No bottom-nav / personalized chrome — the cached page must be user-agnostic.
    assert_select "nav", count: 0
    # No CSRF meta tag: the cached shell must carry no per-session token.
    assert_select "meta[name=csrf-token]", count: 0
  end

  test "offline page renders the core catch form with species options" do
    walleye = create(:species, name: "Walleye")
    perch   = create(:species, name: "Perch")
    get "/offline"
    assert_response :success
    assert_select "select#catch_species_id option", minimum: 2
    assert_select "select#catch_species_id", text: /Walleye/
    assert_select "[data-controller~=catch-form]"
    assert_select "button[data-catch-form-target=submitButton]"
  end

  test "offline page omits the teammate id and uses an empty csrf token" do
    get "/offline"
    assert_response :success
    assert_select "[data-catch-form-teammate-user-id-value='']"
    assert_select "[data-catch-form-csrf-token-value='']"
  end
end
