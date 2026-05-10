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

  test "fish_train: first catch matching car 0 species creates a placement at slot_index 0" do
    club = create(:club)
    perch = create(:species, club: club, name: "Perch")
    pike  = create(:species, club: club, name: "Pike")
    user  = create(:user, club: club)
    t = build(:tournament, club: club, format: :fish_train, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
              train_cars: [perch.id, pike.id, perch.id])
    [perch, pike].each { |s| t.scoring_slots.build(species: s, slot_count: 1) }
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: perch, length_inches: 12,
                    captured_at_device: 30.minutes.ago)
    )

    placements = CatchPlacement.where(tournament: t, active: true).order(:slot_index)
    assert_equal 1, placements.count
    assert_equal 0, placements.first.slot_index
    assert_equal perch, placements.first.species
  end

  test "fish_train: a longer catch of the current car species replaces it" do
    club = create(:club)
    perch = create(:species, club: club)
    pike  = create(:species, club: club)
    user  = create(:user, club: club)
    t = build(:tournament, club: club, format: :fish_train, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
              train_cars: [perch.id, pike.id, perch.id])
    [perch, pike].each { |s| t.scoring_slots.build(species: s, slot_count: 1) }
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    [10, 14].each do |len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: perch, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    active = CatchPlacement.where(tournament: t, active: true).includes(:catch)
    assert_equal 1, active.count
    assert_equal 14, active.first.catch.length_inches.to_i
    inactive = CatchPlacement.where(tournament: t, active: false)
    assert_equal 1, inactive.count, "expected the smaller perch placement to be deactivated"
  end

  test "fish_train: a same-or-shorter catch of the current car species is a no-op" do
    club = create(:club)
    perch = create(:species, club: club)
    pike  = create(:species, club: club)
    user  = create(:user, club: club)
    t = build(:tournament, club: club, format: :fish_train, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
              train_cars: [perch.id, pike.id, perch.id])
    [perch, pike].each { |s| t.scoring_slots.build(species: s, slot_count: 1) }
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: perch, length_inches: 14, captured_at_device: 30.minutes.ago)
    )
    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: perch, length_inches: 14, captured_at_device: 25.minutes.ago)
    )
    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: perch, length_inches: 10, captured_at_device: 20.minutes.ago)
    )

    active = CatchPlacement.where(tournament: t, active: true).includes(:catch).to_a
    assert_equal 1, active.size
    assert_equal 14, active.first.catch.length_inches.to_i
  end

  test "fish_train: catching the next car species advances and locks the previous car" do
    club = create(:club)
    perch = create(:species, club: club)
    pike  = create(:species, club: club)
    walleye = create(:species, club: club)
    user  = create(:user, club: club)
    t = build(:tournament, club: club, format: :fish_train, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
              train_cars: [perch.id, pike.id, walleye.id])
    [perch, pike, walleye].each { |s| t.scoring_slots.build(species: s, slot_count: 1) }
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: perch, length_inches: 12, captured_at_device: 30.minutes.ago)
    )
    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: pike, length_inches: 22, captured_at_device: 25.minutes.ago)
    )

    active = CatchPlacement.where(tournament: t, active: true).order(:slot_index).includes(:catch).to_a
    assert_equal [0, 1], active.map(&:slot_index)
    assert_equal perch, active[0].species
    assert_equal pike,  active[1].species
  end

  test "fish_train: catching a previously-locked car species is a no-op" do
    club = create(:club)
    perch = create(:species, club: club)
    pike  = create(:species, club: club)
    walleye = create(:species, club: club)
    user  = create(:user, club: club)
    t = build(:tournament, club: club, format: :fish_train, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
              train_cars: [perch.id, pike.id, walleye.id])
    [perch, pike, walleye].each { |s| t.scoring_slots.build(species: s, slot_count: 1) }
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: perch, length_inches: 12, captured_at_device: 30.minutes.ago)
    )
    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: pike, length_inches: 22, captured_at_device: 25.minutes.ago)
    )
    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: perch, length_inches: 30, captured_at_device: 20.minutes.ago)
    )

    active = CatchPlacement.where(tournament: t, active: true).order(:slot_index).includes(:catch).to_a
    assert_equal [0, 1], active.map(&:slot_index), "perch car 0 stays locked at the previous length"
    assert_equal 12, active[0].catch.length_inches.to_i, "locked car length unchanged"
  end

  test "fish_train: a repeated species in the train opens a new car after walking through" do
    club = create(:club)
    perch   = create(:species, club: club)
    pike    = create(:species, club: club)
    walleye = create(:species, club: club)
    user    = create(:user, club: club)
    t = build(:tournament, club: club, format: :fish_train, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
              train_cars: [perch.id, pike.id, walleye.id, perch.id])
    [perch, pike, walleye].each { |s| t.scoring_slots.build(species: s, slot_count: 1) }
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    [
      [perch,   12], [pike,    20], [walleye, 18], [perch, 16]
    ].each do |species, len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: species, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    active = CatchPlacement.where(tournament: t, active: true).order(:slot_index).includes(:catch).to_a
    assert_equal [0, 1, 2, 3], active.map(&:slot_index)
    assert_equal [perch, pike, walleye, perch], active.map(&:species)
    assert_equal [12, 20, 18, 16], active.map { |p| p.catch.length_inches.to_i }
  end

  test "fish_train: catch of an off-pool species is a no-op" do
    club = create(:club)
    perch = create(:species, club: club)
    pike  = create(:species, club: club)
    off_pool = create(:species, club: club)
    user  = create(:user, club: club)
    t = build(:tournament, club: club, format: :fish_train, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
              train_cars: [perch.id, pike.id, perch.id])
    [perch, pike].each { |s| t.scoring_slots.build(species: s, slot_count: 1) }
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    Catches::PlaceInSlots.call(
      catch: create(:catch, user: user, species: off_pool, length_inches: 30,
                    captured_at_device: 30.minutes.ago)
    )

    assert_equal 0, CatchPlacement.where(tournament: t).count
  end

  test "fish_train: improving the last (final) car works indefinitely (no implicit end-of-train lock)" do
    club = create(:club)
    perch = create(:species, club: club)
    pike  = create(:species, club: club)
    user  = create(:user, club: club)
    t = build(:tournament, club: club, format: :fish_train, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
              train_cars: [perch.id, pike.id, perch.id])
    [perch, pike].each { |s| t.scoring_slots.build(species: s, slot_count: 1) }
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    [
      [perch, 10], [pike, 22], [perch, 12], [perch, 14], [perch, 18]
    ].each do |species, len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: species, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    active = CatchPlacement.where(tournament: t, active: true).order(:slot_index).includes(:catch).to_a
    assert_equal [0, 1, 2], active.map(&:slot_index)
    assert_equal 10, active[0].catch.length_inches.to_i, "car 0 locked at first perch"
    assert_equal 22, active[1].catch.length_inches.to_i, "car 1 locked at first pike"
    assert_equal 18, active[2].catch.length_inches.to_i, "car 2 (last car) keeps improving"
  end

  test "fish_train: consecutive same-species cars form a top-N group (W=14, W=22 fill both W slots)" do
    club = create(:club)
    perch   = create(:species, club: club)
    walleye = create(:species, club: club)
    user    = create(:user, club: club)
    t = build(:tournament, club: club, format: :fish_train, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
              train_cars: [perch.id, walleye.id, walleye.id])
    [perch, walleye].each { |s| t.scoring_slots.build(species: s, slot_count: 1) }
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    [
      [perch,   10],
      [walleye, 14],
      [walleye, 22]
    ].each do |species, len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: species, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    active = CatchPlacement.where(tournament: t, active: true).order(:slot_index).includes(:catch).to_a
    assert_equal [0, 1, 2], active.map(&:slot_index), "all three slots filled (P group + 2-car W group)"
    assert_equal 14, active[1].catch.length_inches.to_i, "first W fills the first W slot"
    assert_equal 22, active[2].catch.length_inches.to_i, "second W fills the second W slot (not improve)"
  end

  test "fish_train: a bigger catch replaces the smallest in a full same-species group; survivor shifts down" do
    club = create(:club)
    perch   = create(:species, club: club)
    walleye = create(:species, club: club)
    user    = create(:user, club: club)
    t = build(:tournament, club: club, format: :fish_train, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
              train_cars: [perch.id, walleye.id, walleye.id])
    [perch, walleye].each { |s| t.scoring_slots.build(species: s, slot_count: 1) }
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    # State after first three catches: slots [P10, W14, W22].
    # Then W=23 bumps the smallest W (=14). Survivor W=22 shifts from slot 2
    # down to slot 1, and W=23 lands at slot 2 ("fill forward — newest highest").
    # Then W=18 is smaller than the new smallest (22), no-op.
    # Then W=22.5 bumps 22; W=23 shifts to slot 1, W=22.5 to slot 2.
    [
      [perch,   10],
      [walleye, 14],
      [walleye, 22],
      [walleye, 23],
      [walleye, 18],
      [walleye, 22.5]
    ].each do |species, len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: species, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    active = CatchPlacement.where(tournament: t, active: true).order(:slot_index).includes(:catch).to_a
    assert_equal [0, 1, 2], active.map(&:slot_index)
    assert_in_delta 10,   active[0].catch.length_inches.to_f
    assert_in_delta 23,   active[1].catch.length_inches.to_f, 0.01, "older survivor (23) in the lower W slot"
    assert_in_delta 22.5, active[2].catch.length_inches.to_f, 0.01, "newest survivor (22.5) in the highest W slot"
  end

  test "fish_train: catching the next group's species locks the previous group permanently" do
    club = create(:club)
    perch   = create(:species, club: club)
    walleye = create(:species, club: club)
    pike    = create(:species, club: club)
    user    = create(:user, club: club)
    t = build(:tournament, club: club, format: :fish_train, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
              train_cars: [perch.id, walleye.id, walleye.id, pike.id])
    [perch, walleye, pike].each { |s| t.scoring_slots.build(species: s, slot_count: 1) }
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    # Fill P + both W slots, then advance to pike. A later walleye should be
    # a no-op because the W group is now locked.
    [
      [perch,   10],
      [walleye, 14],
      [walleye, 22],
      [pike,    30],
      [walleye, 100]  # bigger than anything in the W group, but locked
    ].each do |species, len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: species, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    active = CatchPlacement.where(tournament: t, active: true).order(:slot_index).includes(:catch).to_a
    assert_equal [0, 1, 2, 3], active.map(&:slot_index)
    assert_equal 14, active[1].catch.length_inches.to_i, "W group locked — W=100 did not replace W=14"
    assert_equal 22, active[2].catch.length_inches.to_i, "W group locked — W=100 did not replace W=22"
    assert_equal 30, active[3].catch.length_inches.to_i, "pike advanced and locked the W group"
  end

  test "fish_train: full P→W→K→W→W walkthrough matches the score-maximizing top-N rule" do
    club = create(:club)
    perch   = create(:species, club: club)
    pike    = create(:species, club: club)
    walleye = create(:species, club: club)
    user    = create(:user, club: club)
    t = build(:tournament, club: club, format: :fish_train, mode: :solo,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
              train_cars: [perch.id, walleye.id, pike.id, walleye.id, walleye.id])
    [perch, pike, walleye].each { |s| t.scoring_slots.build(species: s, slot_count: 1) }
    t.save!
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: user)

    # User's smoke-test catches: P14, W14, K14, W14, W28, W16
    # Expected with the group rule:
    #   - P14 fills P group (slot 0).
    #   - W14 advances to W-group-1, fills slot 1.
    #   - K14 advances to K group, fills slot 2.
    #   - W14 advances to W-group-2 (slots 3 and 4), fills slot 3.
    #   - W28 fills empty slot 4. State: slot 3=14, slot 4=28.
    #   - W16 bumps smallest (W=14). Survivor W=28 shifts slot 4→3. W=16 lands at slot 4.
    [
      [perch,   14],
      [walleye, 14],
      [pike,    14],
      [walleye, 14],
      [walleye, 28],
      [walleye, 16]
    ].each do |species, len|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: species, length_inches: len,
                      captured_at_device: 30.minutes.ago)
      )
    end

    active = CatchPlacement.where(tournament: t, active: true).order(:slot_index).includes(:catch).to_a
    assert_equal [0, 1, 2, 3, 4], active.map(&:slot_index), "all 5 cars filled"
    assert_equal [14, 14, 14, 28, 16], active.map { |p| p.catch.length_inches.to_i }
    sum = active.sum { |p| p.catch.length_inches.to_i }
    assert_equal 86, sum, "score = 14+14+14+28+16 (top 2 of {14, 28, 16} placed in W-group-2)"
  end

  end
end
