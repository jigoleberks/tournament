require "application_system_test_case"

class CatchFormNativePhotoTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Joe")
    create(:species, club: @club, name: "Walleye")
  end

  test "choosing a photo via the native file input shows the preview and clears the take-photo prompt" do
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit new_catch_path

    find("select#catch_species_id").select("Walleye")
    fill_in "catch_length_inches", with: "18"

    # The input is display:none (Tailwind `hidden`); Cuprite can still set it.
    input = find("input[data-photo-capture-target='input']", visible: :all)
    input.set(Rails.root.join("test/fixtures/files/sample_walleye.jpg"))

    # Preview becomes visible, Retake appears, and the form's missing-field
    # status no longer asks for a photo.
    assert_selector "img[data-photo-capture-target='preview']", visible: true
    assert_selector "button[data-photo-capture-target='retakeButton']", visible: true
    assert_no_text "Take a photo first."
  end
end
