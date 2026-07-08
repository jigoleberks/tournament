require "application_system_test_case"

class OrganizerCatchEditTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @member = create(:user, club: @club, name: "Club Carl", role: :member)
    @walleye = create(:species, name: "Walleye", club: @club)
    @pike = create(:species, name: "Northern Pike", club: @club)
    @catch = create(:catch, user: @member, species: @walleye, length_inches: 20,
                            length_unit: "inches", captured_at_device: 30.minutes.ago)
  end

  test "organizer edits a catch's species and length from the admin list" do
    sign_in_as(@organizer)
    visit admin_catches_path
    find("a[href='#{admin_catch_path(@catch.id)}']").click

    assert_text(/Edit species & length/i)
    select "Northern Pike", from: "species_id"
    fill_in "length", with: "18.5"
    # The unit toggle is a styled pill: the radio is visually hidden (sr-only)
    # behind its label, so click the label rather than the radio itself.
    choose "Inches", allow_label_click: true
    click_button "Save changes"

    # The detail URL is identical before and after the PATCH (index → show, then
    # update redirects back to show), so asserting the path wouldn't actually wait
    # for the write. Gate on the post-save flash, which only renders after the
    # update commits and redirects, before reading the DB.
    assert_text "Catch updated."

    @catch.reload
    assert_equal @pike.id, @catch.species_id
    assert_equal 18.5, @catch.length_inches.to_f
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    visit consume_session_path(token: token.token)
  end
end
