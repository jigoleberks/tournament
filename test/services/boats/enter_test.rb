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

  # Boat#captain_is_an_active_club_member only fires on create or a captain
  # change, so "boat whose captain has since left" is a valid, designed-in
  # state and the boat stays in the picker. One tap must not seat them —
  # TournamentEntryMember checks cap, already-entered and judge, but not this.
  test "refuses a boat whose captain has left the club" do
    @kurtis.update!(deactivated_at: 1.day.ago)

    assert_no_difference "TournamentEntry.count" do
      error = assert_raises(Boats::Enter::InactiveCrew) do
        Boats::Enter.call(tournament: @main, boat: @boat)
      end
      assert_match(/Kurtis Sanguin has left the club/, error.message)
      assert_match(/Reassign Majestic Red's captain/, error.message)
    end
  end

  test "refuses an explicit crew that includes a departed member" do
    @nate.update!(deactivated_at: 1.day.ago)

    assert_no_difference "TournamentEntry.count" do
      error = assert_raises(Boats::Enter::InactiveCrew) do
        Boats::Enter.call(tournament: @main, boat: @boat, user_ids: [@kurtis.id, @nate.id])
      end
      assert_match(/Nate Rosengren has left the club/, error.message)
      assert_match(/Update Majestic Red's crew/, error.message)
    end
  end

  # The idempotent early return comes first: a boat already entered before its
  # captain left stays entered, and a stray second tap must not start alarming
  # anyone about a crew nobody is changing.
  test "an already-entered boat still returns its entry after the captain leaves" do
    entry = Boats::Enter.call(tournament: @main, boat: @boat)
    @kurtis.update!(deactivated_at: 1.day.ago)

    assert_equal entry, Boats::Enter.call(tournament: @main, boat: @boat)
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
