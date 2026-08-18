require "test_helper"

class Boats::EnterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @club = create(:club)
    @kurtis = create(:user, club: @club, name: "Kurtis Sanguin")
    @nate = create(:user, club: @club, name: "Nate Rosengren")
    @boat = create(:boat, club: @club, name: "Majestic Red", captain: @kurtis)
    group = SecureRandom.uuid
    @main = create(:tournament, club: @club, mode: :team, name: "Main", link_group_id: group)
    @side = create(:tournament, club: @club, mode: :team, name: "Side", link_group_id: group)
  end

  test "creates an entry named after the boat with the captain aboard" do
    entry = Boats::Enter.call(tournament: @main, boat: @boat)
    assert_equal "Majestic Red", entry.name
    assert_equal @boat, entry.boat
    assert_equal [@kurtis], entry.users
  end

  test "enters the boat in the linked tournament too" do
    Boats::Enter.call(tournament: @main, boat: @boat)
    mirrored = @side.tournament_entries.sole
    assert_equal @boat, mirrored.boat
    assert_equal [@kurtis], mirrored.users
  end

  test "returns the existing entry instead of double-entering the boat" do
    first = Boats::Enter.call(tournament: @main, boat: @boat)
    assert_no_difference "TournamentEntry.count" do
      assert_equal first, Boats::Enter.call(tournament: @main, boat: @boat)
    end
  end

  test "accepts an explicit crew in place of the captain default" do
    entry = Boats::Enter.call(tournament: @main, boat: @boat, user_ids: [@kurtis.id, @nate.id])
    assert_equal [@kurtis, @nate].sort_by(&:id), entry.users.sort_by(&:id)
  end

  test "queues a push for each angler aboard" do
    assert_enqueued_with(job: DeliverPushNotificationJob) do
      Boats::Enter.call(tournament: @main, boat: @boat)
    end
  end

  # Two organizers tapping the same boat at once (or one impatient double-tap
  # on the button_to) both pass the find_by pre-check; the loser's INSERT then
  # trips index_tournament_entries_on_tournament_and_boat_uniq and raises
  # RecordNotUnique — a StatementInvalid, so the controllers' `rescue
  # RecordInvalid` misses it and the organizer gets an error page. The promise
  # is idempotence: return the winner's entry.
  test "returns the winner's entry after losing the double-tap race" do
    winner = @main.tournament_entries.create!(name: @boat.name, boat: @boat)

    # Blind only the pre-check, so the insert below races into the index the
    # way a genuinely concurrent second tap would.
    main = @main
    blinded = false
    main.define_singleton_method(:tournament_entries) do
      relation = TournamentEntry.where(tournament_id: id)
      unless blinded
        blinded = true
        relation.define_singleton_method(:find_by) { |*| nil }
      end
      relation
    end

    assert_no_difference "TournamentEntry.count" do
      assert_equal winner, Boats::Enter.call(tournament: main, boat: @boat)
    end
  end
end
