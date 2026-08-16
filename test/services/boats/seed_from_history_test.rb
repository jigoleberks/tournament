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
end
