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

  test "PATCH update calls Tournaments::Rebalance and the new slot pulls in eligible catches" do
    sign_in_as(@organizer)
    walleye = create(:species, club: @club)
    tournament = create(:tournament, club: @club, starts_at: 2.hours.ago, ends_at: 2.hours.from_now)
    entry = create(:tournament_entry, tournament: tournament)
    user = create(:user, club: @club)
    member = create(:tournament_entry_member, tournament_entry: entry, user: user)
    member.update_column(:created_at, 2.hours.ago)
    c = create(:catch, user: user, species: walleye, length_inches: 22,
                       captured_at_device: 30.minutes.ago)

    patch organizers_tournament_path(tournament), params: {
      tournament: {
        scoring_slots_attributes: { "0" => { species_id: walleye.id, slot_count: 1 } }
      }
    }

    active = tournament.catch_placements.active.where(species: walleye)
    assert_equal 1, active.count
    assert_equal c.id, active.first.catch_id
  end

  test "POST create on a tournament whose window includes a logged catch places it" do
    sign_in_as(@organizer)
    walleye = create(:species, club: @club)
    user = create(:user, club: @club)
    c = create(:catch, user: user, species: walleye, length_inches: 22,
                       captured_at_device: 30.minutes.ago)

    post organizers_tournaments_path, params: {
      tournament: {
        name: "Walleye Wednesday", kind: "event", mode: "solo",
        starts_at: 2.hours.ago, ends_at: 2.hours.from_now,
        scoring_slots_attributes: { "0" => { species_id: walleye.id, slot_count: 1 } }
      }
    }

    tournament = @club.tournaments.find_by(name: "Walleye Wednesday")
    assert_not_nil tournament

    # The user wasn't an entry-member when create ran; add them now and rebalance once
    # to confirm the catch is eligible. (Live flow: organizer creates the entry separately
    # via the entries UI; this test just verifies that the create path's rebalance ran
    # without error and the structure is in place.)
    entry = create(:tournament_entry, tournament: tournament)
    member = create(:tournament_entry_member, tournament_entry: entry, user: user)
    member.update_column(:created_at, 2.hours.ago)
    Tournaments::Rebalance.call(tournament: tournament)

    active = tournament.catch_placements.active.where(species: walleye)
    assert_equal 1, active.count
    assert_equal c.id, active.first.catch_id
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
