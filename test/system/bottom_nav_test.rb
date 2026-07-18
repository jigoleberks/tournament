require "application_system_test_case"

class BottomNavTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
  end

  test "bottom nav shows Home and Refresh" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit root_path

    assert_selector "nav a[aria-label='Home']"
    assert_selector "nav button[aria-label='Refresh'][data-controller~='app-refresh']"
  end

  # iOS keeps position:fixed elements pinned to the visual viewport, so the
  # opened keyboard pushes the nav up to float directly over the form — with
  # the Refresh button (which discards an unsaved catch photo/video) one
  # accidental thumb-tap above the keyboard. The nav must hide while a
  # text-entering control has focus.
  test "bottom nav hides while typing and returns on blur" do
    create(:species, club: @club, name: "Walleye")
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit "/catches/new"

    assert_selector "nav[data-controller~='keyboard-nav']"
    page.execute_script("document.querySelector('#catch_length_inches').focus()")
    assert_no_selector "nav[data-controller~='keyboard-nav']", wait: 2

    page.execute_script("document.querySelector('#catch_length_inches').blur()")
    assert_selector "nav[data-controller~='keyboard-nav']", wait: 2
  end

  test "bottom nav stays visible while hopping between fields" do
    create(:species, club: @club, name: "Walleye")
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit "/catches/new"

    page.execute_script("document.querySelector('#catch_length_inches').focus()")
    assert_no_selector "nav[data-controller~='keyboard-nav']", wait: 2
    page.execute_script("document.querySelector('#catch_note').focus()")
    # Past the 150ms re-show delay: a field-to-field hop must not flash the nav back in.
    sleep 0.4
    assert_no_selector "nav[data-controller~='keyboard-nav']"
  end
end
