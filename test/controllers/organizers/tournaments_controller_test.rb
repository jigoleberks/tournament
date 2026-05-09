require "test_helper"

class Organizers::TournamentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @member = create(:user, club: @club, role: :member)
    @organizer = create(:user, club: @club, role: :organizer)
  end

  test "members are forbidden" do
    sign_in_as(@member)
    get organizers_tournaments_path
    assert_response :forbidden
  end

  test "organizers can list tournaments" do
    sign_in_as(@organizer)
    create(:tournament, club: @club, name: "Wednesday Throwdown")
    get organizers_tournaments_path
    assert_response :success
    assert_match "Wednesday Throwdown", response.body
  end

  test "organizers can create a tournament with scoring slots" do
    sign_in_as(@organizer)
    species = create(:species, club: @club, name: "Walleye")
    assert_difference -> { Tournament.count } => 1, -> { ScoringSlot.count } => 1 do
      post organizers_tournaments_path, params: {
        tournament: {
          name: "Wed Night",
          kind: "event",
          mode: "solo",
          starts_at: 1.day.from_now,
          ends_at: 1.day.from_now + 4.hours,
          season_tag: "Open Water 2026",
          scoring_slots_attributes: { "0" => { species_id: species.id, slot_count: 3 } }
        }
      }
    end
    assert_redirected_to organizers_tournaments_path
  end

  test "create accepts local: false" do
    organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(organizer)
    assert_difference -> { @club.tournaments.count }, 1 do
      post organizers_tournaments_path, params: {
        tournament: { name: "Away Trip", kind: "event", mode: "solo",
                      starts_at: Time.current, ends_at: 1.day.from_now,
                      local: "0" }
      }
    end
    assert_equal false, @club.tournaments.last.local
  end

  test "create defaults local to true when checkbox omitted" do
    organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(organizer)
    post organizers_tournaments_path, params: {
      tournament: { name: "Local Trip", kind: "event", mode: "solo",
                    starts_at: Time.current, ends_at: 1.day.from_now }
    }
    assert_equal true, @club.tournaments.last.local
  end

  test "index shows (away) tag for non-local tournaments" do
    organizer = create(:user, club: @club, role: :organizer)
    sign_in_as(organizer)
    away = create(:tournament, club: @club, local: false, name: "Out of Town",
                               starts_at: 1.day.from_now)
    get organizers_tournaments_path
    assert_response :success
    assert_match "(away)", response.body
  end

  test "create accepts awards_season_points: true" do
    sign_in_as(@organizer)
    assert_difference -> { @club.tournaments.count }, 1 do
      post organizers_tournaments_path, params: {
        tournament: { name: "Season Tournament", kind: "event", mode: "solo",
                      starts_at: 1.day.from_now, ends_at: 1.day.from_now + 4.hours,
                      awards_season_points: "1" }
      }
    end
    assert_redirected_to organizers_tournaments_path
    assert @club.tournaments.last.awards_season_points?
  end

  test "create accepts blind_leaderboard true" do
    sign_in_as(@organizer)
    species = create(:species, club: @club)
    post organizers_tournaments_path, params: {
      tournament: {
        name: "Blind League Night",
        kind: "event",
        mode: "solo",
        starts_at: 1.hour.from_now,
        ends_at: 4.hours.from_now,
        blind_leaderboard: "1",
        scoring_slots_attributes: { "0" => { species_id: species.id, slot_count: 1 } }
      }
    }
    assert_redirected_to organizers_tournaments_path
    assert Tournament.last.blind_leaderboard?
  end

  test "edit form locks blind_leaderboard after starts_at has passed" do
    sign_in_as(@organizer)
    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               blind_leaderboard: true)
    get edit_organizers_tournament_path(t)
    assert_response :success
    assert_select "input[type=checkbox][name='tournament[blind_leaderboard]'][disabled]"
    assert_select "input[type=hidden][name='tournament[blind_leaderboard]'][value='1']"
  end

  test "update rejects toggling blind_leaderboard after starts_at" do
    sign_in_as(@organizer)
    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               blind_leaderboard: false)
    patch organizers_tournament_path(t), params: { tournament: { blind_leaderboard: "1" } }
    assert_response :unprocessable_entity
    t.reload
    assert_not t.blind_leaderboard?
  end

  test "create accepts format: big_fish_season with a single scoring slot" do
    sign_in_as(@organizer)
    walleye = create(:species, club: @club, name: "Walleye")
    assert_difference -> { Tournament.count }, 1 do
      post organizers_tournaments_path, params: {
        tournament: {
          name: "Big Walleye Season",
          kind: "ongoing",
          mode: "solo",
          format: "big_fish_season",
          starts_at: 1.day.from_now,
          ends_at: 30.days.from_now,
          scoring_slots_attributes: { "0" => { species_id: walleye.id, slot_count: 3 } }
        }
      }
    end
    assert_redirected_to organizers_tournaments_path
    assert Tournament.last.format_big_fish_season?
  end

  test "create rejects big_fish_season + team mode" do
    sign_in_as(@organizer)
    walleye = create(:species, club: @club)
    assert_no_difference -> { Tournament.count } do
      post organizers_tournaments_path, params: {
        tournament: {
          name: "Bad Combo",
          kind: "event",
          mode: "team",
          format: "big_fish_season",
          starts_at: 1.day.from_now,
          ends_at: 1.day.from_now + 4.hours,
          scoring_slots_attributes: { "0" => { species_id: walleye.id, slot_count: 1 } }
        }
      }
    end
    assert_response :unprocessable_entity
    assert_match "must be solo", response.body
  end

  test "create rejects big_fish_season with multiple scoring slots" do
    sign_in_as(@organizer)
    walleye = create(:species, club: @club)
    pike = create(:species, club: @club)
    assert_no_difference -> { Tournament.count } do
      post organizers_tournaments_path, params: {
        tournament: {
          name: "Two Species",
          kind: "event",
          mode: "solo",
          format: "big_fish_season",
          starts_at: 1.day.from_now,
          ends_at: 1.day.from_now + 4.hours,
          scoring_slots_attributes: {
            "0" => { species_id: walleye.id, slot_count: 1 },
            "1" => { species_id: pike.id, slot_count: 1 }
          }
        }
      }
    end
    assert_response :unprocessable_entity
    assert_match "exactly one species configured", response.body
  end

  test "update rejects format change after the tournament has started" do
    sign_in_as(@organizer)
    species = create(:species, club: @club)
    tournament = create(:tournament, club: @club, format: :standard, mode: :solo,
                        starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: tournament, species: species, slot_count: 1)

    patch organizers_tournament_path(tournament), params: {
      tournament: { format: "big_fish_season" }
    }

    assert_response :unprocessable_entity
    assert_match "once the tournament has started", response.body
    assert tournament.reload.format_standard?
  end

  test "create accepts format: hidden_length" do
    sign_in_as(@organizer)
    walleye = create(:species, club: @club, name: "Walleye HL")

    assert_difference -> { Tournament.count } => 1 do
      post organizers_tournaments_path, params: {
        tournament: {
          name: "HL Wed",
          kind: "event",
          mode: "solo",
          format: "hidden_length",
          starts_at: 1.day.from_now,
          ends_at: 1.day.from_now + 4.hours,
          scoring_slots_attributes: { "0" => { species_id: walleye.id, slot_count: 1 } }
        }
      }
    end
    assert Tournament.order(:id).last.format_hidden_length?
  end

  test "update silently ignores hidden_length_target submitted via params" do
    sign_in_as(@organizer)
    walleye = create(:species, club: @club, name: "Walleye HL2")
    t = build(:tournament, club: @club, format: :hidden_length, mode: :solo,
              kind: :event, starts_at: 1.hour.from_now, ends_at: 4.hours.from_now)
    t.scoring_slots.build(species: walleye, slot_count: 1)
    t.save!

    patch organizers_tournament_path(t), params: {
      tournament: { hidden_length_target: "17.25" }
    }

    assert_nil t.reload.hidden_length_target,
               "expected strong params to drop hidden_length_target"
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
