require "application_system_test_case"

class CatchFormNativePhotoTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Joe")
    create(:species, club: @club, name: "Walleye")
  end

  test "choosing a photo via the native file input shows the preview and clears the take-photo prompt" do
    visit_catch_form_with_photo

    # Preview becomes visible, Retake appears, and the form's missing-field
    # status no longer asks for a photo.
    assert_selector "img[data-photo-capture-target='preview']", visible: true
    assert_selector "button[data-photo-capture-target='retakeButton']", visible: true
    assert_no_text "Take a photo first."
  end

  test "dismissing the retake confirmation keeps the existing photo" do
    visit_catch_form_with_photo
    assert_selector "button[data-photo-capture-target='retakeButton']", visible: true

    dismiss_confirm do
      click_button "Retake"
    end

    # retake() returned before clearing the input, so the chosen file is still
    # attached and the preview still renders.
    assert_selector "img[data-photo-capture-target='preview']", visible: true
    assert_no_text "Take a photo first."
    assert_match(/sample_walleye\.jpg\z/, photo_input_value)
  end

  test "accepting the retake confirmation clears the attached photo" do
    visit_catch_form_with_photo
    assert_match(/sample_walleye\.jpg\z/, photo_input_value)

    accept_confirm do
      click_button "Retake"
    end

    # retake() ran past the guard and cleared the input so a re-pick of the same
    # file still fires a change event. The OS camera itself can't open headless.
    assert_equal "", photo_input_value
  end

  private

  # Signs in, opens the catch form, and attaches a photo — the starting state
  # for every test in this file.
  def visit_catch_form_with_photo
    token = SignInToken.issue!(user: @user)
    visit consume_session_path(token: token.token)
    visit new_catch_path

    find("select#catch_species_id").select("Walleye")
    fill_in "catch_length_inches", with: "18"

    # The input is display:none (Tailwind `hidden`); Cuprite can still set it.
    input = find("input[data-photo-capture-target='input']", visible: :all)
    input.set(Rails.root.join("test/fixtures/files/sample_walleye.jpg"))
  end

  def photo_input_value
    page.evaluate_script(
      "document.querySelector(\"input[data-photo-capture-target='input']\").value"
    )
  end
end
