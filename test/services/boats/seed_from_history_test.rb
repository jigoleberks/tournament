require "test_helper"

class Boats::SeedFromHistoryTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @curtis = create(:user, club: @club, name: "Curtis Johnston")
    @ellen = create(:user, club: @club, name: "Ellen Johnston")
    @scott = create(:user, club: @club, name: "Scott Brown")
    @galen = create(:user, club: @club, name: "Galen Patterson")
    @troy = create(:user, club: @club, name: "Troy Patterson")
  end

  def night(name, crew, weeks_ago:, entry_name:)
    tournament = create(:tournament, club: @club, mode: :team, name: name,
                        starts_at: weeks_ago.weeks.ago, ends_at: weeks_ago.weeks.ago + 3.hours)
    entry = create(:tournament_entry, tournament: tournament, name: entry_name)
    crew.each { |u| entry.tournament_entry_members.create!(user: u) }
    entry
  end

  test "picks the member who is aboard every night" do
    night("Wk1", [@curtis, @ellen], weeks_ago: 3, entry_name: "Team Willow River")
    night("Wk2", [@curtis, @scott], weeks_ago: 2, entry_name: "team willow river ")
    night("Wk3", [@curtis, @ellen], weeks_ago: 1, entry_name: "Team Willow River")

    proposal = Boats::SeedFromHistory.call(club: @club).sole
    assert_equal "Team Willow River", proposal[:name]
    assert_equal @curtis, proposal[:captain]
    assert_equal :constant_member, proposal[:signal]
    assert_equal 3, proposal[:nights]
  end

  test "breaks a tie with whoever logs catches for the other" do
    entry_one = night("Wk1", [@galen, @troy], weeks_ago: 2, entry_name: "Team Patterson")
    night("Wk2", [@galen, @troy], weeks_ago: 1, entry_name: "Team Patterson")
    create(:catch, user: @troy, logged_by_user_id: @galen.id,
           captured_at_device: entry_one.tournament.starts_at + 30.minutes)

    proposal = Boats::SeedFromHistory.call(club: @club).sole
    assert_equal @galen, proposal[:captain]
    assert_equal :proxy_logger, proposal[:signal]
  end

  test "leaves a one-night multi-member boat for a manual pick" do
    night("Wk1", [@galen, @troy], weeks_ago: 1, entry_name: "Loose Goose")
    proposal = Boats::SeedFromHistory.call(club: @club).sole
    assert_nil proposal[:captain]
    assert_equal :none, proposal[:signal]
  end

  test "dry run writes nothing" do
    night("Wk1", [@curtis], weeks_ago: 1, entry_name: "Team Willow River")
    assert_no_difference "Boat.count" do
      Boats::SeedFromHistory.call(club: @club, dry_run: true)
    end
  end

  test "a real run creates boats and back-fills the entries" do
    entry = night("Wk1", [@curtis], weeks_ago: 1, entry_name: " Team Willow River ")
    assert_difference "Boat.count", 1 do
      Boats::SeedFromHistory.call(club: @club, dry_run: false)
    end
    boat = Boat.sole
    assert_equal "Team Willow River", boat.name
    assert_equal @curtis, boat.captain
    assert_equal boat, entry.reload.boat
  end

  test "does not propose a captain who has since left the club" do
    night("Wk1", [@curtis], weeks_ago: 2, entry_name: "Team Willow River")
    night("Wk2", [@curtis], weeks_ago: 1, entry_name: "Team Willow River")
    @curtis.club_memberships.find_by(club: @club).update!(deactivated_at: 1.day.ago)

    proposal = Boats::SeedFromHistory.call(club: @club).sole
    assert_nil proposal[:captain]
    assert_equal :none, proposal[:signal]
  end

  # Same case via the path the app actually uses to remove a member: the
  # membership row is left alone and only users.deactivated_at is written.
  test "does not propose a captain whose user account has been deactivated" do
    night("Wk1", [@curtis], weeks_ago: 2, entry_name: "Team Willow River")
    night("Wk2", [@curtis], weeks_ago: 1, entry_name: "Team Willow River")
    @curtis.update!(deactivated_at: 1.day.ago)

    proposal = Boats::SeedFromHistory.call(club: @club).sole
    assert_nil proposal[:captain]
    assert_equal :none, proposal[:signal]
  end

  test "a real run creates nothing for a boat whose only captain candidate has left the club" do
    entry = night("Wk1", [@curtis], weeks_ago: 1, entry_name: "Team Willow River")
    @curtis.club_memberships.find_by(club: @club).update!(deactivated_at: 1.day.ago)

    assert_no_difference "Boat.count" do
      Boats::SeedFromHistory.call(club: @club, dry_run: false)
    end
    assert_nil entry.reload.boat_id
  end

  test "a real run rolls back the whole batch if one boat fails to save" do
    create(:boat, club: @club, name: "Team Willow River")

    # More nights, so this one is applied first and would otherwise succeed.
    night("Wk1", [@galen], weeks_ago: 3, entry_name: "Team Patterson")
    patterson_entry = night("Wk2", [@galen], weeks_ago: 2, entry_name: "Team Patterson")

    # Collides case-insensitively with the boat already on record.
    colliding_entry = night("Wk3", [@curtis], weeks_ago: 1, entry_name: "team willow river")

    assert_no_difference "Boat.count" do
      Boats::SeedFromHistory.call(club: @club, dry_run: false)
    end
    assert_nil patterson_entry.reload.boat_id
    assert_nil colliding_entry.reload.boat_id
  end

  # Two entries from one night can't both take the same boat_id — the boat's
  # partial unique index forbids it. TournamentEntryMember keeps the two crews
  # disjoint, so the group ends up with no constant member and no captain, and
  # without this the organizer just sees an unexplained "— pick one —".
  test "flags a group holding two entries from the same night" do
    entry = night("Wk1", [@curtis, @ellen], weeks_ago: 1, entry_name: "Team Loos")
    dupe = create(:tournament_entry, tournament: entry.tournament, name: "Loos")
    dupe.tournament_entry_members.create!(user: @scott)

    proposal = Boats::SeedFromHistory.call(club: @club).sole

    assert_nil proposal[:captain]
    assert_match(/one boat can't hold two entries in one tournament/, proposal[:errors].join)
    assert_match(/Loos and Team Loos/, proposal[:errors].join)
  end

  # A flagged proposal that DOES carry a captain (only reachable from rows that
  # predate user_not_already_in_tournament) must stop the batch at the check
  # rather than at the index, where RecordNotUnique would escape the rake task.
  test "a real run rolls back rather than writing a flagged proposal" do
    create(:boat, club: @club, name: "Team Willow River")
    night("Wk1", [@galen], weeks_ago: 2, entry_name: "Team Patterson")
    colliding = night("Wk2", [@curtis], weeks_ago: 1, entry_name: "team willow river")

    assert_no_difference "Boat.count" do
      Boats::SeedFromHistory.call(club: @club, dry_run: false)
    end
    assert_nil colliding.reload.boat_id
  end

  test "a whitespace-only entry name does not form its own boat" do
    night("Wk1", [@curtis], weeks_ago: 1, entry_name: "   ")
    assert_equal [], Boats::SeedFromHistory.call(club: @club)
  end
end
