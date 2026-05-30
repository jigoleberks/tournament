require "application_system_test_case"

class LogbookFlowTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Logan")
    @walleye = create(:species, club: @club, name: "Walleye")
    @original_logbook_enabled = ENV["LOGBOOK_ENABLED"]
    ENV["LOGBOOK_ENABLED"] = "true"
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

  test "/logbook renders a catch's enrichment data" do
    bait = create(:bait, user: @user, color: "orange", weight: "3/8 oz",
                  lure_type: "fireball", bait_type: "minnow")
    create(:catch, user: @user, species: @walleye, length_inches: 19.5,
           bait: bait, structure: :hump, water_depth_feet: 22.5, water_temperature_c: 18.5)

    sign_in_as(@user)
    visit logbook_path

    assert_text "Logbook"
    assert_text bait.display_name
    assert_text "Hump"
  end

  test "/logbook shows other anglers' catches don't leak in" do
    other = create(:user, club: @club, name: "Other")
    create(:catch, user: other, species: @walleye, length_inches: 25.0, structure: :rocks)

    sign_in_as(@user)
    visit logbook_path

    assert_text "Logbook"
    assert_text "No catches in this view"
  end

  test "new-catch page shows step 1 visible and step 2 hidden when logbook enabled" do
    sign_in_as(@user)
    visit new_catch_path

    # Step indicator says "1 of 2"
    assert_selector "[data-test='step-indicator']", text: "1"
    # Step 1 elements visible
    assert_selector "label", text: "Species"
    # Step 2 fields exist in the DOM but hidden
    assert_selector "[data-catch-form-target='step2']", visible: :hidden
    # Next button is present, Back button not yet visible
    assert_selector "[data-test='next-button']", text: "Next"
    assert_selector "[data-test='back-button']", visible: :hidden
  end

  test "new-catch page (logbook disabled) shows single-page form with note on step 1" do
    ENV.delete("LOGBOOK_ENABLED")
    sign_in_as(@user)
    visit new_catch_path

    assert_no_selector "[data-test='next-button']"
    assert_no_selector "[data-test='step-indicator']"
    assert_selector "label", text: "Notes (private)"
  end

  test "new-catch page lists only current user's active baits in the step 2 dropdown" do
    mine = create(:bait, user: @user, color: "mine-orange")
    archived = create(:bait, user: @user, color: "archived-color", archived_at: Time.current)
    other = create(:user, club: @club)
    theirs = create(:bait, user: other, color: "others-color")

    sign_in_as(@user)
    visit new_catch_path

    select_html = find("#catch_bait_id", visible: :hidden)[:innerHTML]
    assert_includes select_html, mine.display_name
    assert_not_includes select_html, archived.display_name
    assert_not_includes select_html, theirs.display_name
  end
end
