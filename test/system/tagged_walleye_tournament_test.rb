require "application_system_test_case"

class TaggedWalleyeTournamentTest < ApplicationSystemTestCase
  setup do
    @club = Club.first || create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @angler = create(:user, club: @club, role: :member, name: "Tagged Angler")
    @tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    Species.find_or_create_by!(name: "Walleye") # so the species dropdown has another option

    @t = build(:tournament, club: @club, format: :tagged, mode: :solo,
               kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               name: "Test Tagged")
    @t.scoring_slots.build(species: @tagged, slot_count: 1)
    @t.save!

    @entry = create(:tournament_entry, tournament: @t)
    create(:tournament_entry_member, tournament_entry: @entry, user: @angler)
  end

  test "tag input appears when Tagged Walleye is selected and hides for other species" do
    sign_in_as(@angler)
    visit new_catch_path

    # Initially Walleye is the default; tag input hidden.
    assert_no_selector "#catch_tag_number", visible: true

    select "Tagged Walleye", from: "catch_species_id"
    assert_selector "#catch_tag_number", visible: true

    select "Walleye", from: "catch_species_id"
    assert_no_selector "#catch_tag_number", visible: true
  end

  test "leaderboard shows ticket count per angler" do
    %w[A0001 A0002].each do |tag|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: @angler, species: @tagged, length_inches: 18.0,
                      tag_number: tag, captured_at_device: 30.minutes.ago)
      )
    end

    sign_in_as(@organizer)
    visit tournament_path(@t)

    assert_text "Tagged Angler"
    rows = all("#leaderboard tbody tr")
    assert_equal 1, rows.size
    assert_match "2", rows.first.text   # ticket count
    assert_match "A0001", rows.first.text
    assert_match "A0002", rows.first.text
  end

  test "leaderboard tag numbers link to the catch photo modal for members" do
    Catches::PlaceInSlots.call(
      catch: create(:catch, user: @angler, species: @tagged, length_inches: 18.0,
                    tag_number: "A0001", captured_at_device: 30.minutes.ago)
    )

    sign_in_as(@angler)
    visit tournament_path(@t)

    assert_selector "#leaderboard a[data-turbo-frame='catch_photo_modal']", text: "A0001"
  end

  test "organizer can draw a winner after tournament ends" do
    Catches::PlaceInSlots.call(
      catch: create(:catch, user: @angler, species: @tagged, length_inches: 18.0,
                    tag_number: "A0001", captured_at_device: 30.minutes.ago)
    )
    @t.update_columns(starts_at: 2.hours.ago, ends_at: 1.hour.ago)

    sign_in_as(@organizer)
    visit tournament_path(@t)

    accept_confirm do
      click_button "Draw winner"
    end

    assert_text "Tagged Angler"
    assert_text "A0001"
    assert_text "Winner"
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    visit consume_session_path(token: token.token)
  end
end
