require "test_helper"

module Catches
  class PlaceInSlotsTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club, name: "Walleye")
      @user = create(:user, club: @club)
      @tournament = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: @tournament, species: @walleye, slot_count: 2)
      @entry = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: @entry, user: @user)
    end

    test "places a single fish into the first empty slot of its species" do
      catch_record = create(:catch, user: @user, species: @walleye, length_inches: 20)
      result = PlaceInSlots.call(catch: catch_record)

      placement = catch_record.catch_placements.sole
      assert_equal @entry, placement.tournament_entry
      assert_equal @walleye, placement.species
      assert_equal 0, placement.slot_index
      assert placement.active?
      assert_includes result[:created], placement
    end

    test "fills slot_index 1 when slot 0 is occupied" do
      first = create(:catch, user: @user, species: @walleye, length_inches: 14)
      PlaceInSlots.call(catch: first)
      second = create(:catch, user: @user, species: @walleye, length_inches: 17)
      PlaceInSlots.call(catch: second)

      assert_equal [0, 1], CatchPlacement.where(tournament_entry: @entry, active: true).order(:slot_index).pluck(:slot_index)
    end

    test "ignores tournaments that don't score this species" do
      perch = create(:species, club: @club, name: "Perch")
      catch_record = create(:catch, user: @user, species: perch, length_inches: 10)
      result = PlaceInSlots.call(catch: catch_record)
      assert_empty result[:created]
    end

    test "when all slots are full, replaces the smallest active fish if new is bigger" do
      small = create(:catch, user: @user, species: @walleye, length_inches: 14)
      PlaceInSlots.call(catch: small)
      medium = create(:catch, user: @user, species: @walleye, length_inches: 17)
      PlaceInSlots.call(catch: medium)
      big = create(:catch, user: @user, species: @walleye, length_inches: 22)
      result = PlaceInSlots.call(catch: big)

      assert_includes result[:bumped], small.catch_placements.first
      assert_not small.catch_placements.first.reload.active?
      assert_equal [17, 22],
        CatchPlacement.active.where(tournament_entry: @entry).joins(:catch).order("catches.length_inches").pluck("catches.length_inches").map(&:to_i)
    end

    test "when all slots are full and new fish is smaller, no placement is made" do
      big1 = create(:catch, user: @user, species: @walleye, length_inches: 22)
      big2 = create(:catch, user: @user, species: @walleye, length_inches: 21)
      small = create(:catch, user: @user, species: @walleye, length_inches: 10)
      PlaceInSlots.call(catch: big1)
      PlaceInSlots.call(catch: big2)
      result = PlaceInSlots.call(catch: small)

      assert_empty result[:created]
      assert_empty result[:bumped]
      assert small.catch_placements.empty?
    end

    test "skips placement when membership is dropped between tournament resolution and entry lock" do
      catch_record = create(:catch, user: @user, species: @walleye, length_inches: 20)

      original = ::Tournaments::ActiveForUser.method(:with_entries)
      ::Tournaments::ActiveForUser.define_singleton_method(:with_entries) do |user:, at: Time.current|
        rows = original.call(user: user, at: at)
        # Simulate the user being dropped between this query and PlaceInSlots's entry.lock!
        user.tournament_entry_members.destroy_all
        rows
      end
      begin
        result = PlaceInSlots.call(catch: catch_record)
      ensure
        ::Tournaments::ActiveForUser.define_singleton_method(:with_entries, original)
      end

      assert_empty result[:created]
      assert_equal 0, catch_record.catch_placements.count
    end

    test "credits multiple active tournaments — boat entry and individual entry" do
      # Boat tournament (team mode)
      boat_tournament = create(:tournament, club: @club, mode: :team,
                                starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create(:scoring_slot, tournament: boat_tournament, species: @walleye, slot_count: 2)
      boat = create(:tournament_entry, tournament: boat_tournament, name: "Curtis's Boat")
      create(:tournament_entry_member, tournament_entry: boat, user: @user)

      # Individual ongoing tournament (already set up in setup as @tournament + @entry)
      catch_record = create(:catch, user: @user, species: @walleye, length_inches: 20)
      result = PlaceInSlots.call(catch: catch_record)

      assert_equal 2, result[:created].size
      entries = result[:created].map(&:tournament_entry).sort_by(&:id)
      assert_equal [@entry, boat].sort_by(&:id), entries
    end

  test "hidden_length: every catch creates a placement, no bumping" do
    club = create(:club)
    walleye = create(:species, club: club)
    user = create(:user, club: club)
    t = build(:tournament, club: club, format: :hidden_length, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    t.scoring_slots.build(species: walleye, slot_count: 1)
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    # Three catches; each must produce a placement, even though slot_count is 1.
    [22, 16, 14].each do |len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: walleye, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    placements = CatchPlacement.where(tournament: t, active: true).order(:slot_index)
    assert_equal 3, placements.count, "expected all three catches to be placed (no bumping)"
    # Slot indices ascend with creation order
    assert_equal [0, 1, 2], placements.map(&:slot_index)
  end

  test "hidden_length: new catch after a placement is deactivated does not collide on slot_index" do
    club = create(:club)
    walleye = create(:species, club: club)
    user = create(:user, club: club)
    t = build(:tournament, club: club, format: :hidden_length, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    t.scoring_slots.build(species: walleye, slot_count: 1)
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    [22, 16, 14].each do |len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: walleye, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    # Simulate a judge DQ on the middle placement: deactivate slot_index = 1.
    # The unique partial index on (entry, species, slot_index WHERE active=true)
    # leaves indexes 0 and 2 active.
    middle = CatchPlacement.find_by!(tournament: t, slot_index: 1, active: true)
    middle.update!(active: false)

    # A new catch must place without colliding with the existing active row at
    # slot_index = 2.
    assert_nothing_raised do
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: walleye, length_inches: 18,
                      captured_at_device: 25.minutes.ago)
      )
    end

    active_indexes = CatchPlacement.where(tournament: t, active: true).order(:slot_index).pluck(:slot_index)
    assert_equal [0, 2, 3], active_indexes,
                 "expected new placement to land at max(active)+1, never reusing an occupied index"
  end

  test "biggest_vs_smallest: first catch creates one placement at slot_index 0" do
    club = create(:club)
    walleye = create(:species, club: club)
    user = create(:user, club: club)
    t = build(:tournament, club: club, format: :biggest_vs_smallest, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    t.scoring_slots.build(species: walleye, slot_count: 1)
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: walleye, length_inches: 18,
                    captured_at_device: 30.minutes.ago)
    )

    placements = CatchPlacement.where(tournament: t, active: true).order(:slot_index)
    assert_equal 1, placements.count
    assert_equal 0, placements.first.slot_index
  end

  test "biggest_vs_smallest: second catch fills the unused slot index, both are kept" do
    club = create(:club)
    walleye = create(:species, club: club)
    user = create(:user, club: club)
    t = build(:tournament, club: club, format: :biggest_vs_smallest, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    t.scoring_slots.build(species: walleye, slot_count: 1)
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    [18, 12].each do |len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: walleye, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    placements = CatchPlacement.where(tournament: t, active: true).order(:slot_index)
    assert_equal 2, placements.count
    assert_equal [0, 1], placements.map(&:slot_index)
  end

  test "biggest_vs_smallest: a catch bigger than current biggest bumps the old biggest, smallest unchanged" do
    club = create(:club)
    walleye = create(:species, club: club)
    user = create(:user, club: club)
    t = build(:tournament, club: club, format: :biggest_vs_smallest, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    t.scoring_slots.build(species: walleye, slot_count: 1)
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    [18, 12].each do |len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: walleye, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: walleye, length_inches: 22,
                    captured_at_device: 25.minutes.ago)
    )

    active = CatchPlacement.where(tournament: t, active: true).includes(:catch).to_a
    active_lens = active.map { |p| p.catch.length_inches }.sort
    assert_equal [12, 22], active_lens, "expected smallest unchanged, biggest replaced"
    assert_equal 2, active.count
  end

  test "biggest_vs_smallest: a catch smaller than current smallest bumps the old smallest, biggest unchanged" do
    club = create(:club)
    walleye = create(:species, club: club)
    user = create(:user, club: club)
    t = build(:tournament, club: club, format: :biggest_vs_smallest, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    t.scoring_slots.build(species: walleye, slot_count: 1)
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    [18, 12].each do |len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: walleye, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: walleye, length_inches: 8,
                    captured_at_device: 25.minutes.ago)
    )

    active = CatchPlacement.where(tournament: t, active: true).includes(:catch).to_a
    active_lens = active.map { |p| p.catch.length_inches }.sort
    assert_equal [8, 18], active_lens, "expected biggest unchanged, smallest replaced"
  end

  test "biggest_vs_smallest: a catch in the middle is dropped — no new placement, no bump" do
    club = create(:club)
    walleye = create(:species, club: club)
    user = create(:user, club: club)
    t = build(:tournament, club: club, format: :biggest_vs_smallest, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    t.scoring_slots.build(species: walleye, slot_count: 1)
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    [22, 10].each do |len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: walleye, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: walleye, length_inches: 16,
                    captured_at_device: 25.minutes.ago)
    )

    active = CatchPlacement.where(tournament: t, active: true).includes(:catch).to_a
    active_lens = active.map { |p| p.catch.length_inches }.sort
    assert_equal [10, 22], active_lens, "expected the middle catch to be ignored"
  end

  test "biggest_vs_smallest: a catch tying the current biggest or smallest is a no-op (first to set wins)" do
    club = create(:club)
    walleye = create(:species, club: club)
    user = create(:user, club: club)
    t = build(:tournament, club: club, format: :biggest_vs_smallest, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    t.scoring_slots.build(species: walleye, slot_count: 1)
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    [22, 10].each do |len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: walleye, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    original_max_id = CatchPlacement.where(tournament: t, active: true)
                                    .joins(:catch).order("catches.length_inches DESC").first.id
    original_min_id = CatchPlacement.where(tournament: t, active: true)
                                    .joins(:catch).order("catches.length_inches ASC").first.id

    [22, 10].each do |tied_len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: walleye, length_inches: tied_len,
                      captured_at_device: 25.minutes.ago)
      )
    end

    active = CatchPlacement.where(tournament: t, active: true).includes(:catch).to_a
    active_lens = active.map { |p| p.catch.length_inches }.sort
    assert_equal [10, 22], active_lens, "expected ties to neither bump nor add a placement"
    assert_equal [original_min_id, original_max_id].sort, active.map(&:id).sort,
                 "expected the original biggest/smallest placements to remain active"
  end

  test "biggest_vs_smallest: new catch after a placement is deactivated fills the freed slot index without colliding" do
    club = create(:club)
    walleye = create(:species, club: club)
    user = create(:user, club: club)
    t = build(:tournament, club: club, format: :biggest_vs_smallest, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    t.scoring_slots.build(species: walleye, slot_count: 1)
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    [22, 10].each do |len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: walleye, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    smaller = CatchPlacement.find_by!(tournament: t, slot_index: 1, active: true)
    smaller.update!(active: false)

    assert_nothing_raised do
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: walleye, length_inches: 14,
                      captured_at_device: 25.minutes.ago)
      )
    end

    active_indexes = CatchPlacement.where(tournament: t, active: true).order(:slot_index).pluck(:slot_index)
    assert_equal [0, 1], active_indexes,
                 "expected new placement to land at the freed slot_index without colliding"
  end
  end
end
