require "test_helper"

class TournamentTemplateTest < ActiveSupport::TestCase
  setup { @club = create(:club) }

  test "scheduled? requires all three default fields" do
    t = create(:tournament_template, club: @club)
    assert_not t.scheduled?
    t.update!(default_weekday: 3, default_start_time: "19:00", default_end_time: "21:00")
    assert t.scheduled?
  end

  test "validation rejects partial schedule" do
    t = build(:tournament_template, club: @club, default_weekday: 3)
    assert_not t.valid?
    assert_includes t.errors[:base].join, "must all be set together"
  end

  test "validation rejects end time at or before start time" do
    t = build(:tournament_template, club: @club,
              default_weekday: 3, default_start_time: "21:00", default_end_time: "19:00")
    assert_not t.valid?
    assert_includes t.errors[:default_end_time].join, "after the start time"
  end

  test "next_occurrence_at returns nil when not scheduled" do
    t = create(:tournament_template, club: @club)
    assert_nil t.next_occurrence_at
  end

  test "next_occurrence_at picks today when weekday matches and start is in the future" do
    Time.use_zone("Saskatchewan") do
      wednesday = Time.zone.local(2026, 5, 6, 12, 0)
      t = create(:tournament_template, club: @club,
                 default_weekday: 3, default_start_time: "19:00", default_end_time: "21:00")
      starts, ends = t.next_occurrence_at(now: wednesday)
      assert_equal Time.zone.local(2026, 5, 6, 19, 0), starts
      assert_equal Time.zone.local(2026, 5, 6, 21, 0), ends
    end
  end

  test "next_occurrence_at jumps a week when weekday matches but start has passed" do
    Time.use_zone("Saskatchewan") do
      late_wednesday = Time.zone.local(2026, 5, 6, 22, 0)
      t = create(:tournament_template, club: @club,
                 default_weekday: 3, default_start_time: "19:00", default_end_time: "21:00")
      starts, _ends = t.next_occurrence_at(now: late_wednesday)
      assert_equal Time.zone.local(2026, 5, 13, 19, 0), starts
    end
  end

  test "next_occurrence_at finds next weekday when today is different" do
    Time.use_zone("Saskatchewan") do
      monday = Time.zone.local(2026, 5, 4, 9, 0)
      t = create(:tournament_template, club: @club,
                 default_weekday: 3, default_start_time: "19:00", default_end_time: "21:00")
      starts, _ends = t.next_occurrence_at(now: monday)
      assert_equal Time.zone.local(2026, 5, 6, 19, 0), starts
    end
  end

  test "default format is standard" do
    t = create(:tournament_template, club: @club)
    assert_equal "standard", t.format
  end

  test "big_fish_season template requires solo mode" do
    t = build(:tournament_template, club: @club, format: :big_fish_season, mode: :team)
    assert_not t.valid?
    assert_includes t.errors[:format], "Big Fish Season tournaments must be solo"
  end

  test "big_fish_season template accepts solo mode with one scoring slot" do
    species = create(:species)
    t = build(:tournament_template, club: @club, format: :big_fish_season, mode: :solo)
    t.tournament_template_scoring_slots.build(species: species, slot_count: 3)
    assert t.valid?, t.errors.full_messages.to_sentence
  end

  test "standard template accepts team mode" do
    t = build(:tournament_template, club: @club, format: :standard, mode: :team)
    assert t.valid?, t.errors.full_messages.to_sentence
  end

  test "big_fish_season template errors when no scoring slot is configured" do
    t = build(:tournament_template, club: @club, format: :big_fish_season, mode: :solo)
    assert_not t.valid?
    assert_includes t.errors[:tournament_template_scoring_slots],
                    "Big Fish Season tournaments must have exactly one species configured"
  end

  test "big_fish_season template errors when more than one scoring slot is configured" do
    species_a = create(:species)
    species_b = create(:species)
    t = build(:tournament_template, club: @club, format: :big_fish_season, mode: :solo)
    t.save!(validate: false)
    t.tournament_template_scoring_slots.create!(species: species_a, slot_count: 1)
    t.tournament_template_scoring_slots.create!(species: species_b, slot_count: 1)
    t.reload
    assert_not t.valid?
    assert_includes t.errors[:tournament_template_scoring_slots],
                    "Big Fish Season tournaments must have exactly one species configured"
  end

  test "format enum includes hidden_length" do
    walleye = create(:species, club: @club)
    tpl = build(:tournament_template, club: @club, format: :hidden_length, mode: :solo)
    tpl.tournament_template_scoring_slots.build(species: walleye, slot_count: 1)
    assert tpl.valid?, tpl.errors.full_messages.inspect
    assert tpl.format_hidden_length?
  end

  test "hidden_length template errors when no scoring slot is configured" do
    tpl = build(:tournament_template, club: @club, format: :hidden_length, mode: :solo)
    assert_not tpl.valid?
    assert_includes tpl.errors[:tournament_template_scoring_slots],
                    "Hidden Length tournaments must have exactly one species configured"
  end

  test "hidden_length template errors with more than one scoring slot" do
    walleye = create(:species, club: @club)
    pike    = create(:species, club: @club)
    tpl = build(:tournament_template, club: @club, format: :hidden_length, mode: :solo)
    tpl.tournament_template_scoring_slots.build(species: walleye, slot_count: 1)
    tpl.tournament_template_scoring_slots.build(species: pike, slot_count: 1)
    assert_not tpl.valid?
    assert_includes tpl.errors[:tournament_template_scoring_slots],
                    "Hidden Length tournaments must have exactly one species configured"
  end

  test "hidden_length template accepts team mode" do
    walleye = create(:species, club: @club)
    tpl = build(:tournament_template, club: @club, format: :hidden_length, mode: :team)
    tpl.tournament_template_scoring_slots.build(species: walleye, slot_count: 1)
    assert tpl.valid?, tpl.errors.full_messages.inspect
  end

  test "format enum includes biggest_vs_smallest" do
    walleye = create(:species, club: @club)
    tpl = build(:tournament_template, club: @club, format: :biggest_vs_smallest, mode: :solo)
    tpl.tournament_template_scoring_slots.build(species: walleye, slot_count: 1)
    assert tpl.valid?, tpl.errors.full_messages.inspect
    assert tpl.format_biggest_vs_smallest?
  end

  test "biggest_vs_smallest template errors when no scoring slot is configured" do
    tpl = build(:tournament_template, club: @club, format: :biggest_vs_smallest, mode: :solo)
    assert_not tpl.valid?
    assert_includes tpl.errors[:tournament_template_scoring_slots],
                    "Biggest vs Smallest tournaments must have exactly one species configured"
  end

  test "biggest_vs_smallest template errors with more than one scoring slot" do
    walleye = create(:species, club: @club)
    pike    = create(:species, club: @club)
    tpl = build(:tournament_template, club: @club, format: :biggest_vs_smallest, mode: :solo)
    tpl.tournament_template_scoring_slots.build(species: walleye, slot_count: 1)
    tpl.tournament_template_scoring_slots.build(species: pike, slot_count: 1)
    assert_not tpl.valid?
    assert_includes tpl.errors[:tournament_template_scoring_slots],
                    "Biggest vs Smallest tournaments must have exactly one species configured"
  end

  test "biggest_vs_smallest template accepts team mode" do
    walleye = create(:species, club: @club)
    tpl = build(:tournament_template, club: @club, format: :biggest_vs_smallest, mode: :team)
    tpl.tournament_template_scoring_slots.build(species: walleye, slot_count: 1)
    assert tpl.valid?, tpl.errors.full_messages.inspect
  end

  test "format enum includes fish_train" do
    walleye = create(:species, club: @club)
    tpl = build(:tournament_template, club: @club, format: :fish_train, mode: :solo,
                train_cars: [walleye.id, walleye.id, walleye.id])
    tpl.tournament_template_scoring_slots.build(species: walleye, slot_count: 1)
    assert tpl.valid?, tpl.errors.full_messages.inspect
    assert tpl.format_fish_train?
  end

  test "fish_train template errors when no scoring slot is configured" do
    tpl = build(:tournament_template, club: @club, format: :fish_train, mode: :solo,
                train_cars: [1, 1, 1])
    assert_not tpl.valid?
    assert_includes tpl.errors[:tournament_template_scoring_slots],
                    "Fish Train tournaments must have between 1 and 3 species in the pool"
  end

  test "fish_train template errors when pool has more than 3 species" do
    s1 = create(:species, club: @club)
    s2 = create(:species, club: @club)
    s3 = create(:species, club: @club)
    s4 = create(:species, club: @club)
    tpl = build(:tournament_template, club: @club, format: :fish_train, mode: :solo,
                train_cars: [s1.id, s2.id, s3.id])
    [s1, s2, s3, s4].each { |s| tpl.tournament_template_scoring_slots.build(species: s, slot_count: 1) }
    assert_not tpl.valid?
    assert_includes tpl.errors[:tournament_template_scoring_slots],
                    "Fish Train tournaments must have between 1 and 3 species in the pool"
  end

  test "fish_train template errors when train length is out of 3..6 range" do
    s = create(:species, club: @club)
    short = build(:tournament_template, club: @club, format: :fish_train, mode: :solo,
                  train_cars: [s.id, s.id])
    short.tournament_template_scoring_slots.build(species: s, slot_count: 1)
    long  = build(:tournament_template, club: @club, format: :fish_train, mode: :solo,
                  train_cars: Array.new(7) { s.id })
    long.tournament_template_scoring_slots.build(species: s, slot_count: 1)
    assert_not short.valid?
    assert_not long.valid?
    assert_includes short.errors[:train_cars], "Fish Train must have between 3 and 6 cars"
    assert_includes long.errors[:train_cars],  "Fish Train must have between 3 and 6 cars"
  end

  test "fish_train template errors when a car species is off-pool" do
    pool   = create(:species, club: @club)
    outsider = create(:species, club: @club)
    tpl = build(:tournament_template, club: @club, format: :fish_train, mode: :solo,
                train_cars: [pool.id, outsider.id, pool.id])
    tpl.tournament_template_scoring_slots.build(species: pool, slot_count: 1)
    assert_not tpl.valid?
    assert_includes tpl.errors[:train_cars],
                    "Fish Train cars must reference species in the pool"
  end

  test "fish_train template accepts team mode and a valid 6-car train" do
    s1 = create(:species, club: @club)
    s2 = create(:species, club: @club)
    tpl = build(:tournament_template, club: @club, format: :fish_train, mode: :team,
                train_cars: [s1.id, s2.id, s1.id, s2.id, s1.id, s2.id])
    [s1, s2].each { |sp| tpl.tournament_template_scoring_slots.build(species: sp, slot_count: 1) }
    assert tpl.valid?, tpl.errors.full_messages.inspect
  end

  test "tagged template requires solo mode" do
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    tpl = build(:tournament_template, club: @club, format: :tagged, mode: :team)
    tpl.tournament_template_scoring_slots.build(species: tagged, slot_count: 1)
    assert_not tpl.valid?
    assert_includes tpl.errors[:format], "Tagged Walleye tournaments must be solo"
  end

  test "tagged template errors when scoring slot references a non-Tagged-Walleye species" do
    Species.find_or_create_by!(name: "Tagged Walleye")
    other = create(:species, name: "Walleye Test #{SecureRandom.hex(2)}")
    tpl = build(:tournament_template, club: @club, format: :tagged, mode: :solo)
    tpl.tournament_template_scoring_slots.build(species: other, slot_count: 1)
    assert_not tpl.valid?
    assert_includes tpl.errors[:tournament_template_scoring_slots],
                    "Tagged Walleye tournaments must have exactly one scoring slot for the Tagged Walleye species"
  end

  test "tagged template errors when no scoring slot is configured" do
    Species.find_or_create_by!(name: "Tagged Walleye")
    tpl = build(:tournament_template, club: @club, format: :tagged, mode: :solo)
    assert_not tpl.valid?
    assert_includes tpl.errors[:tournament_template_scoring_slots],
                    "Tagged Walleye tournaments must have exactly one scoring slot for the Tagged Walleye species"
  end

  test "tagged template accepts a single Tagged Walleye scoring slot in solo mode" do
    tagged = Species.find_or_create_by!(name: "Tagged Walleye")
    tpl = build(:tournament_template, club: @club, format: :tagged, mode: :solo)
    tpl.tournament_template_scoring_slots.build(species: tagged, slot_count: 1)
    assert tpl.valid?, tpl.errors.full_messages.to_sentence
  end

  test "pro_walleye template requires one Walleye scoring slot" do
    club = create(:club)
    walleye = create(:species, name: "Walleye")
    tmpl = build(:tournament_template, club: club, format: :pro_walleye, mode: :team)
    assert_not tmpl.valid?
    tmpl.tournament_template_scoring_slots.build(species: walleye, slot_count: 5)
    assert tmpl.valid?, tmpl.errors.full_messages.to_sentence
  end

  test "pro_walleye template pins its scoring slot to the basket size" do
    walleye = create(:species, name: "Walleye")
    tmpl = build(:tournament_template, club: @club, format: :pro_walleye, mode: :team)
    # The slot_count field is "ignored" in the UI; whatever is entered, the basket
    # is a fixed 5 (matching Tournament#force_pro_walleye_slot_count).
    tmpl.tournament_template_scoring_slots.build(species: walleye, slot_count: 3)
    tmpl.save!
    assert_equal Catches::ProWalleye::BASKET_SIZE, tmpl.tournament_template_scoring_slots.first.slot_count
  end
end
