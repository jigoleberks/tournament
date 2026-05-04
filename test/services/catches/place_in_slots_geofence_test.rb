require "test_helper"

class Catches::PlaceInSlotsGeofenceTest < ActiveSupport::TestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    @walleye = create(:species, club: @club, name: "Walleye")
  end

  test "skips placement in local tournament when catch is out of bounds" do
    tournament = create(:tournament, club: @club, local: true,
                         starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: tournament, species: @walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)

    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18,
                                   captured_at_device: Time.current,
                                   latitude: 49.9, longitude: -97.1)

    assert_no_difference -> { CatchPlacement.where(tournament: tournament).count } do
      Catches::PlaceInSlots.call(catch: catch_record)
    end
  end

  test "places in away tournament when catch is in-province but out of lake" do
    tournament = create(:tournament, club: @club, local: false,
                         starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: tournament, species: @walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)

    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18,
                                   captured_at_device: Time.current,
                                   latitude: 50.45, longitude: -104.61) # Regina

    assert_difference -> { CatchPlacement.where(tournament: tournament).count }, 1 do
      Catches::PlaceInSlots.call(catch: catch_record)
    end
  end

  test "places in local tournament when catch is in bounds" do
    tournament = create(:tournament, club: @club, local: true,
                         starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: tournament, species: @walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)

    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18,
                                   captured_at_device: Time.current,
                                   latitude: 49.41, longitude: -103.62)

    assert_difference -> { CatchPlacement.where(tournament: tournament).count }, 1 do
      Catches::PlaceInSlots.call(catch: catch_record)
    end
  end

  test "places in local tournament when catch has no GPS (per soft-treatment rule)" do
    tournament = create(:tournament, club: @club, local: true,
                         starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: tournament, species: @walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)

    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18,
                                   captured_at_device: Time.current,
                                   latitude: nil, longitude: nil)

    assert_difference -> { CatchPlacement.where(tournament: tournament).count }, 1 do
      Catches::PlaceInSlots.call(catch: catch_record)
    end
  end

  test "skips placement in local tournament when catch is out of province" do
    tournament = create(:tournament, club: @club, local: true,
                         starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: tournament, species: @walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)

    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18,
                                   captured_at_device: Time.current,
                                   latitude: 51.05, longitude: -114.07) # Calgary

    assert_no_difference -> { CatchPlacement.where(tournament: tournament).count } do
      Catches::PlaceInSlots.call(catch: catch_record)
    end
  end

  test "skips placement in away tournament when catch is out of province" do
    tournament = create(:tournament, club: @club, local: false,
                         starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: tournament, species: @walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)

    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18,
                                   captured_at_device: Time.current,
                                   latitude: 49.9, longitude: -97.1) # Winnipeg

    assert_no_difference -> { CatchPlacement.where(tournament: tournament).count } do
      Catches::PlaceInSlots.call(catch: catch_record)
    end
  end

  test "places in away tournament when catch has no GPS (province check skipped)" do
    tournament = create(:tournament, club: @club, local: false,
                         starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: tournament, species: @walleye, slot_count: 2)
    entry = create(:tournament_entry, tournament: tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: @user)

    catch_record = create(:catch, user: @user, species: @walleye, length_inches: 18,
                                   captured_at_device: Time.current,
                                   latitude: nil, longitude: nil)

    assert_difference -> { CatchPlacement.where(tournament: tournament).count }, 1 do
      Catches::PlaceInSlots.call(catch: catch_record)
    end
  end
end
