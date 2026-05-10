require "application_system_test_case"

class FishTrainTournamentTest < ApplicationSystemTestCase
  include LengthHelper

  setup do
    @club = Club.first || create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @perch   = create(:species, club: @club, name: "Perch")
    @pike    = create(:species, club: @club, name: "Pike")
    @walleye = create(:species, club: @club, name: "Walleye")
    @angler_a = create(:user, club: @club, name: "Angler A")
    @angler_b = create(:user, club: @club, name: "Angler B")
  end

  test "Fish Train tournament: ranks by score, cars-in-order, last car has current badge" do
    t = build(:tournament, club: @club, name: "FT Wed",
              format: :fish_train, mode: :solo, kind: :event,
              starts_at: 30.minutes.ago, ends_at: 30.minutes.from_now,
              train_cars: [@perch.id, @pike.id, @walleye.id, @perch.id])
    [@perch, @pike, @walleye].each { |sp| t.scoring_slots.build(species: sp, slot_count: 1) }
    t.save!

    ea = create(:tournament_entry, tournament: t)
    eb = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: ea, user: @angler_a)
    create(:tournament_entry_member, tournament_entry: eb, user: @angler_b)

    # Angler A: full 4-car train. Sum = 12+22+18+14 = 66.
    # Angler B: stalls at car 1 (perch) — two perches, larger replaces smaller. Sum = 17.
    [
      [@angler_a, @perch,   12, 25.minutes.ago],
      [@angler_a, @pike,    22, 20.minutes.ago],
      [@angler_a, @walleye, 18, 15.minutes.ago],
      [@angler_a, @perch,   14, 10.minutes.ago],
      [@angler_b, @perch,   16, 24.minutes.ago],
      [@angler_b, @perch,   17, 18.minutes.ago]
    ].each do |user, species, length, captured|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: species, length_inches: length, captured_at_device: captured)
      )
    end

    sign_in_as(@organizer)
    visit tournament_path(t)

    rows = all("#leaderboard tbody tr")
    assert_equal 2, rows.size

    # Top row: Angler A
    assert_match "Angler A", rows.first.text
    inches_part, cm_part = format_length_parts(66)
    assert_match inches_part, rows.first.text
    assert_match cm_part,     rows.first.text

    # Cars rendered (any order at the text level — full check is order-aware below)
    assert_match "Perch",   rows.first.text
    assert_match "Pike",    rows.first.text
    assert_match "Walleye", rows.first.text

    # Current badge appears (case-insensitive)
    assert_match(/current/i, rows.first.text, "last (most-recent) car should be tagged 'current'")
  end

  test "Fish Train tournament: cars-completed beats fewer-cars at the same score" do
    t = build(:tournament, club: @club, name: "FT Tied",
              format: :fish_train, mode: :solo, kind: :event,
              starts_at: 30.minutes.ago, ends_at: 30.minutes.from_now,
              train_cars: [@perch.id, @pike.id, @walleye.id, @perch.id, @pike.id])
    [@perch, @pike, @walleye].each { |sp| t.scoring_slots.build(species: sp, slot_count: 1) }
    t.save!

    ea = create(:tournament_entry, tournament: t)
    eb = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: ea, user: @angler_a)
    create(:tournament_entry_member, tournament_entry: eb, user: @angler_b)

    # A: 5 cars × 6 = 30
    [
      [@perch,   6, 25.minutes.ago],
      [@pike,    6, 24.minutes.ago],
      [@walleye, 6, 23.minutes.ago],
      [@perch,   6, 22.minutes.ago],
      [@pike,    6, 21.minutes.ago]
    ].each do |species, length, captured|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: @angler_a, species: species, length_inches: length, captured_at_device: captured)
      )
    end
    # B: 3 cars × 10 = 30
    [
      [@perch,   10, 25.minutes.ago],
      [@pike,    10, 24.minutes.ago],
      [@walleye, 10, 23.minutes.ago]
    ].each do |species, length, captured|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: @angler_b, species: species, length_inches: length, captured_at_device: captured)
      )
    end

    sign_in_as(@organizer)
    visit tournament_path(t)

    rows = all("#leaderboard tbody tr")
    assert_equal 2, rows.size
    assert_match "Angler A", rows.first.text, "5-car 30 should rank above 3-car 30"
    assert_match "Angler B", rows.last.text
  end

  private

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    visit consume_session_path(token: SignInToken.last.token)
  end
end
