require "application_system_test_case"

class CatchesFilteringTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @walleye = create(:species, club: @club, name: "Walleye")
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
  end

  test "applying a wind direction chip filters the list" do
    ne = create(:catch, user: @user, species: @walleye, length_inches: 18,
                        captured_at_device: Time.current, wind_direction_deg: 45)
    sw = create(:catch, user: @user, species: @walleye, length_inches: 18,
                        captured_at_device: Time.current, wind_direction_deg: 225)

    visit catches_path(start: "")
    assert_text "Match conditions"

    find("[data-test='match-conditions-toggle']").click
    assert_selector "[data-test='chip-wind_dir-ne']", visible: :visible

    find("[data-test='chip-wind_dir-ne']").click

    # After submit, page reloads with wind_dir=ne; only the NE catch should be in the grid.
    assert_current_path(/wind_dir=ne/, url: true)
    assert_selector "a[href='#{catch_path(ne.id)}']"
    assert_no_selector "a[href='#{catch_path(sw.id)}']"

    # Tapping the active chip clears it.
    find("[data-test='chip-wind_dir-ne']").click
    assert_no_match(/wind_dir=ne/, current_url)
    assert_selector "a[href='#{catch_path(ne.id)}']"
    assert_selector "a[href='#{catch_path(sw.id)}']"
  end

  test "min-length input narrows the grid to longer catches" do
    short = create(:catch, user: @user, species: @walleye, length_inches: 12, captured_at_device: Time.current)
    long  = create(:catch, user: @user, species: @walleye, length_inches: 22, captured_at_device: Time.current)

    visit catches_path(start: "")
    input = find("input[name='min_length']")
    input.fill_in with: "18"
    input.send_keys(:return)

    assert_current_path(/min_length=18/, url: true)
    assert_selector "a[href='#{catch_path(long.id)}']"
    assert_no_selector "a[href='#{catch_path(short.id)}']"
  end
end
