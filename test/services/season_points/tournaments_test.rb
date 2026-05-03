require "test_helper"

module SeasonPoints
  class TournamentsTest < ActiveSupport::TestCase
    setup { @club = create(:club) }

    test "returns empty when season_tag is nil" do
      assert_equal [], Tournaments.call(club: @club, season_tag: nil).to_a
    end

    test "returns ended + points-eligible tournaments for the tag, ordered by ends_at desc" do
      t1 = create(:tournament, club: @club, awards_season_points: true,
                  season_tag: "Wednesday 2026", starts_at: 2.weeks.ago, ends_at: 2.weeks.ago + 4.hours)
      t2 = create(:tournament, club: @club, awards_season_points: true,
                  season_tag: "Wednesday 2026", starts_at: 1.week.ago,  ends_at: 1.week.ago + 4.hours)
      _other_tag = create(:tournament, club: @club, awards_season_points: true,
                          season_tag: "Casual", starts_at: 1.week.ago, ends_at: 1.week.ago + 4.hours)
      _not_eligible = create(:tournament, club: @club, awards_season_points: false,
                             season_tag: "Wednesday 2026", starts_at: 1.week.ago, ends_at: 1.week.ago + 4.hours)
      _in_progress = create(:tournament, club: @club, awards_season_points: true,
                            season_tag: "Wednesday 2026", starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

      result = Tournaments.call(club: @club, season_tag: "Wednesday 2026").to_a
      assert_equal [t2.id, t1.id], result.map(&:id)
    end
  end
end
