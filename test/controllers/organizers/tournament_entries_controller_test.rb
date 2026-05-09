require "test_helper"

class Organizers::TournamentEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @member = create(:user, club: @club, name: "Joe", role: :member)
    @teammate = create(:user, club: @club, name: "Curtis", role: :member)
    # Roster edits are now permitted at any time; tests cover both pre-start and mid-tournament.
    @solo = create(:tournament, club: @club, mode: :solo, starts_at: 1.hour.from_now, ends_at: 3.hours.from_now)
    @team = create(:tournament, club: @club, mode: :team, starts_at: 1.hour.from_now, ends_at: 3.hours.from_now)
    sign_in_as(@organizer)
  end

  test "members are forbidden" do
    sign_in_as(@member)
    post organizers_tournament_tournament_entries_path(tournament_id: @solo.id),
         params: { tournament_entry: { member_user_ids: [@member.id] } }
    assert_response :forbidden
  end

  test "organizer creates a solo entry for one user" do
    assert_difference "TournamentEntry.count", 1 do
      post organizers_tournament_tournament_entries_path(tournament_id: @solo.id),
           params: { tournament_entry: { member_user_ids: [@member.id] } }
    end
    entry = TournamentEntry.last
    assert_equal [@member], entry.users
    assert_redirected_to edit_organizers_tournament_path(@solo)
  end

  test "organizer bulk-adds multiple solo entries in one submit" do
    assert_difference "TournamentEntry.count", 2 do
      post organizers_tournament_tournament_entries_path(tournament_id: @solo.id),
           params: { tournament_entry: { member_user_ids: [@member.id, @teammate.id] } }
    end
    new_entries = TournamentEntry.order(:id).last(2)
    assert_equal [[@member], [@teammate]], new_entries.map(&:users)
    assert_equal "2 entries added.", flash[:notice]
  end

  test "organizer creates a team entry with two members and a boat name" do
    assert_difference "TournamentEntry.count", 1 do
      post organizers_tournament_tournament_entries_path(tournament_id: @team.id),
           params: { tournament_entry: { name: "Curtis's Boat", member_user_ids: [@member.id, @teammate.id] } }
    end
    entry = TournamentEntry.last
    assert_equal "Curtis's Boat", entry.name
    assert_equal [@member, @teammate].sort_by(&:id), entry.users.sort_by(&:id)
  end

  test "deactivated members can't be added to a new entry" do
    @member.update!(deactivated_at: Time.current)
    assert_no_difference "TournamentEntry.count" do
      post organizers_tournament_tournament_entries_path(tournament_id: @solo.id),
           params: { tournament_entry: { member_user_ids: [@member.id] } }
    end
    assert_match(/unavailable/i, flash[:alert])
  end

  test "organizer adds a solo entry after tournament starts" do
    started = create(:tournament, club: @club, mode: :solo, starts_at: 1.minute.ago, ends_at: 1.hour.from_now)
    assert_difference "TournamentEntry.count", 1 do
      post organizers_tournament_tournament_entries_path(tournament_id: started.id),
           params: { tournament_entry: { member_user_ids: [@member.id] } }
    end
    assert_redirected_to edit_organizers_tournament_path(started)
  end

  test "destroying an entry mid-tournament cascades placements and broadcasts the leaderboard" do
    walleye = create(:species, club: @club)
    started = create(:tournament, club: @club, mode: :team, starts_at: 30.minutes.ago, ends_at: 30.minutes.from_now)
    create(:scoring_slot, tournament: started, species: walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: started, name: "Doomed")
    create(:tournament_entry_member, tournament_entry: entry, user: @member)
    fish = create(:catch, user: @member, species: walleye, length_inches: 18, captured_at_device: 5.minutes.ago)
    Catches::PlaceInSlots.call(catch: fish)
    assert_equal 1, fish.reload.catch_placements.where(active: true).count

    broadcast_calls = with_broadcast_spy do
      assert_difference "TournamentEntry.count", -1 do
        delete organizers_tournament_tournament_entry_path(tournament_id: started.id, id: entry.id)
      end
    end
    assert_equal [started.id], broadcast_calls
    assert_equal 0, CatchPlacement.where(catch_id: fish.id).count, "placements should cascade-destroy with the entry"
  end

  test "organizer renames a team entry before tournament starts" do
    entry = create(:tournament_entry, tournament: @team, name: "Old Boat")
    create(:tournament_entry_member, tournament_entry: entry, user: @member)

    patch organizers_tournament_tournament_entry_path(tournament_id: @team.id, id: entry.id),
          params: { tournament_entry: { name: "New Boat" } }

    assert_redirected_to edit_organizers_tournament_path(@team)
    assert_equal "New Boat", entry.reload.name
  end

  test "rename clears the name when blank submitted" do
    entry = create(:tournament_entry, tournament: @team, name: "Was Named")
    create(:tournament_entry_member, tournament_entry: entry, user: @member)

    patch organizers_tournament_tournament_entry_path(tournament_id: @team.id, id: entry.id),
          params: { tournament_entry: { name: "  " } }
    assert_nil entry.reload.name
  end

  test "organizer renames an entry after tournament starts" do
    started = create(:tournament, club: @club, mode: :team, starts_at: 1.minute.ago, ends_at: 1.hour.from_now)
    entry = create(:tournament_entry, tournament: started, name: "Old")
    create(:tournament_entry_member, tournament_entry: entry, user: @member)
    patch organizers_tournament_tournament_entry_path(tournament_id: started.id, id: entry.id),
          params: { tournament_entry: { name: "New" } }
    assert_redirected_to edit_organizers_tournament_path(started)
    assert_equal "New", entry.reload.name
  end

  test "organizer destroys an entry" do
    entry = create(:tournament_entry, tournament: @solo)
    create(:tournament_entry_member, tournament_entry: entry, user: @member)

    assert_difference "TournamentEntry.count", -1 do
      delete organizers_tournament_tournament_entry_path(tournament_id: @solo.id, id: entry.id)
    end
    assert_redirected_to edit_organizers_tournament_path(@solo)
  end

  test "solo entry creation enqueues a push to each new member" do
    with_perform_later_capture do |enqueued|
      post organizers_tournament_tournament_entries_path(tournament_id: @solo.id),
           params: { tournament_entry: { member_user_ids: [@member.id, @teammate.id] } }
      assert_equal 2, enqueued.size
      assert_equal [@member.id, @teammate.id].sort, enqueued.map { |e| e[:user_id] }.sort
      assert(enqueued.all? { |e| e[:body].include?("entered into") && e[:body].include?(@solo.name) })
      assert(enqueued.all? { |e| e[:tournament_id] == @solo.id })
    end
  end

  test "team entry creation enqueues a push to each member of the entry" do
    with_perform_later_capture do |enqueued|
      post organizers_tournament_tournament_entries_path(tournament_id: @team.id),
           params: { tournament_entry: { name: "Boat", member_user_ids: [@member.id, @teammate.id] } }
      assert_equal 2, enqueued.size
      assert_equal [@member.id, @teammate.id].sort, enqueued.map { |e| e[:user_id] }.sort
    end
  end

  test "no push enqueued when validation rejects the request" do
    @member.update!(deactivated_at: Time.current)
    with_perform_later_capture do |enqueued|
      post organizers_tournament_tournament_entries_path(tournament_id: @solo.id),
           params: { tournament_entry: { member_user_ids: [@member.id] } }
      assert_empty enqueued
    end
  end

  private

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end

  def with_perform_later_capture
    enqueued = []
    klass = DeliverPushNotificationJob
    original = klass.method(:perform_later)
    klass.define_singleton_method(:perform_later) { |**kwargs| enqueued << kwargs }
    yield enqueued
  ensure
    klass.singleton_class.send(:remove_method, :perform_later)
    klass.define_singleton_method(:perform_later, original) if original
  end
end
