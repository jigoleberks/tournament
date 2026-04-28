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
end
