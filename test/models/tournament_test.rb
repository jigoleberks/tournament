require "test_helper"

class TournamentTest < ActiveSupport::TestCase
  setup { @club = create(:club) }

  test "requires name, kind, mode, starts_at" do
    assert_not Tournament.new(club: @club).valid?
  end

  test "kind enum: event and ongoing" do
    t = create(:tournament, club: @club, kind: :event)
    assert t.event?
    t.update!(kind: :ongoing)
    assert t.ongoing?
  end

  test "mode enum: solo and team" do
    t = create(:tournament, club: @club, mode: :team)
    assert t.mode_team?
  end

  test "active? is true when now is between starts_at and ends_at" do
    t = create(:tournament, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    assert t.active?
  end

  test "active? is true when ends_at is nil and starts_at has passed" do
    t = create(:tournament, starts_at: 1.day.ago, ends_at: nil)
    assert t.active?
  end

  test "active? is false before starts_at" do
    t = create(:tournament, starts_at: 1.hour.from_now)
    assert_not t.active?
  end

  test "ended? is true when ends_at is in the past" do
    t = create(:tournament, starts_at: 2.days.ago, ends_at: 1.hour.ago)
    assert t.ended?
  end

  test "ended? is false when ends_at is in the future" do
    t = create(:tournament, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    assert_not t.ended?
  end

  test "ended? is false when ends_at is nil" do
    t = create(:tournament, starts_at: 1.day.ago, ends_at: nil)
    assert_not t.ended?
  end

  test "friendly? is true by default and judged? is false" do
    t = create(:tournament, club: @club)
    assert t.friendly?
    assert_not t.judged?
  end

  test "judged? is true and friendly? is false when judged is set" do
    t = create(:tournament, club: @club, judged: true)
    assert t.judged?
    assert_not t.friendly?
  end

  test "blind? is false when blind_leaderboard is false" do
    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    assert_not t.blind?
  end

  test "blind? is true when blind_leaderboard is true and tournament is active" do
    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               blind_leaderboard: true)
    assert t.blind?
  end

  test "blind? is false when blind_leaderboard is true but tournament has ended" do
    t = create(:tournament, club: @club, starts_at: 2.hours.ago, ends_at: 1.hour.ago,
               blind_leaderboard: true)
    assert_not t.blind?
  end

  test "blind? is false when blind_leaderboard is true but tournament has not started" do
    t = create(:tournament, club: @club, starts_at: 1.hour.from_now, ends_at: 5.hours.from_now,
               blind_leaderboard: true)
    assert_not t.blind?
  end

  test "blind? respects the at: argument" do
    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               blind_leaderboard: true)
    assert_not t.blind?(at: 2.hours.from_now)
    assert t.blind?(at: 30.minutes.from_now)
  end

  test "blind_leaderboard requires ends_at" do
    t = build(:tournament, club: @club, blind_leaderboard: true, ends_at: nil)
    assert_not t.valid?
    assert t.errors[:blind_leaderboard].any? { |e| e.include?("end time") }
  end

  test "blind_leaderboard rejected when kind is ongoing" do
    t = build(:tournament, club: @club, blind_leaderboard: true,
              kind: :ongoing, ends_at: 1.hour.from_now)
    assert_not t.valid?
    assert t.errors[:blind_leaderboard].any? { |e| e.include?("end time") }
  end

  test "blind_leaderboard valid when kind is event and ends_at present" do
    t = build(:tournament, club: @club, blind_leaderboard: true,
              kind: :event, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    assert t.valid?
  end

  test "blind_leaderboard cannot be changed after the tournament has started" do
    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               blind_leaderboard: false)
    t.blind_leaderboard = true
    assert_not t.valid?
    assert t.errors[:blind_leaderboard].any? { |e| e.include?("can't be changed") }
  end

  test "blind_leaderboard can be changed before the tournament starts" do
    t = create(:tournament, club: @club, starts_at: 1.hour.from_now, ends_at: 5.hours.from_now,
               blind_leaderboard: false)
    t.blind_leaderboard = true
    assert t.valid?
  end

  test "saving an unrelated attribute on a started tournament does not trigger the lock" do
    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               blind_leaderboard: true)
    t.name = "Renamed mid-event"
    assert t.valid?
  end

  test "default format is standard" do
    t = create(:tournament, club: @club)
    assert_equal "standard", t.format
    assert t.standard?
    assert_not t.big_fish_season?
  end

  test "big_fish_season tournament requires solo mode" do
    t = build(:tournament, club: @club, format: :big_fish_season, mode: :team)
    assert_not t.valid?
    assert_includes t.errors[:format], "Big Fish Season tournaments must be solo"
  end

  test "big_fish_season tournament accepts solo mode" do
    species = create(:species)
    t = build(:tournament, club: @club, format: :big_fish_season, mode: :solo)
    t.scoring_slots.build(species: species, slot_count: 1)
    assert t.valid?, t.errors.full_messages.to_sentence
  end

  test "standard tournament accepts team mode" do
    t = build(:tournament, club: @club, format: :standard, mode: :team)
    assert t.valid?, t.errors.full_messages.to_sentence
  end

  test "big_fish_season tournament errors when no scoring slot is configured" do
    t = build(:tournament, club: @club, format: :big_fish_season, mode: :solo)
    t.save!(validate: false)
    # No scoring_slot created.
    t.valid?
    assert_includes t.errors[:scoring_slots], "Big Fish Season tournaments must have exactly one species configured"
  end

  test "big_fish_season tournament errors when more than one scoring slot is configured" do
    species_a = create(:species)
    species_b = create(:species)
    t = build(:tournament, club: @club, format: :big_fish_season, mode: :solo)
    t.save!(validate: false)
    create(:scoring_slot, tournament: t, species: species_a, slot_count: 1)
    create(:scoring_slot, tournament: t, species: species_b, slot_count: 1)
    t.reload
    t.valid?
    assert_includes t.errors[:scoring_slots], "Big Fish Season tournaments must have exactly one species configured"
  end

  test "big_fish_season tournament accepts exactly one scoring slot" do
    species = create(:species)
    t = build(:tournament, club: @club, format: :big_fish_season, mode: :solo)
    t.save!(validate: false)
    create(:scoring_slot, tournament: t, species: species, slot_count: 3)
    t.reload
    assert t.valid?, t.errors.full_messages.to_sentence
  end

  test "format cannot be changed after the tournament has started" do
    species = create(:species)
    t = create(:tournament, club: @club, format: :standard, mode: :solo,
               starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: t, species: species, slot_count: 1)

    t.format = :big_fish_season
    assert_not t.valid?
    assert_includes t.errors[:format], "can't be changed once the tournament has started"
  end

  test "format can be changed before the tournament starts" do
    species = create(:species)
    t = create(:tournament, club: @club, format: :standard, mode: :solo,
               starts_at: 1.hour.from_now, ends_at: 4.hours.from_now)
    create(:scoring_slot, tournament: t, species: species, slot_count: 1)

    t.format = :big_fish_season
    assert t.valid?, t.errors.full_messages.to_sentence
  end
end
