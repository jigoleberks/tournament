require "test_helper"

module SeasonPoints
  class StandingsTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
    end

    # Returns [tournament, in_window_timestamp]. The in_window timestamp is
    # safe to pass as captured_at_device for catches in this tournament.
    def build_finished(season_tag:, ends_at: 1.day.ago, awards: true)
      starts_at = ends_at - 4.hours
      tournament = create(
        :tournament,
        club: @club,
        mode: :solo,
        awards_season_points: awards,
        season_tag: season_tag,
        starts_at: starts_at,
        ends_at: ends_at
      )
      create(:scoring_slot, tournament: tournament, species: @walleye, slot_count: 2)
      [tournament, ends_at - 1.hour]
    end

    def add_solo(tournament:, in_window:, name:, lengths:)
      user = ::User.find_by(name: name) ||
             create(:user, club: @club, name: name)
      entry = create(:tournament_entry, tournament: tournament)
      create(:tournament_entry_member, tournament_entry: entry, user: user)
      lengths.each do |len|
        Catches::PlaceInSlots.call(
          catch: create(:catch, user: user, species: @walleye, length_inches: len, captured_at_device: in_window)
        )
      end
      user
    end

    test "returns [] for nil season_tag" do
      assert_equal [], Standings.call(club: @club, season_tag: nil)
    end

    test "sums points across multiple tournaments per user" do
      t1, w1 = build_finished(season_tag: "Wednesday 2026", ends_at: 2.weeks.ago)
      t2, w2 = build_finished(season_tag: "Wednesday 2026", ends_at: 1.week.ago)

      [[t1, w1], [t2, w2]].each do |t, w|
        add_solo(tournament: t, in_window: w, name: "Alpha",   lengths: [25])
        add_solo(tournament: t, in_window: w, name: "Bravo",   lengths: [20])
        add_solo(tournament: t, in_window: w, name: "Charlie", lengths: [15])
      end

      result = Standings.call(club: @club, season_tag: "Wednesday 2026")
      points_by_name = result.to_h { |r| [r[:user].name, r[:points]] }
      assert_equal 7.0, points_by_name["Alpha"]    # (3 + 0.5) * 2
      assert_equal 5.0, points_by_name["Bravo"]    # (2 + 0.5) * 2
      assert_equal 3.0, points_by_name["Charlie"]  # (1 + 0.5) * 2
    end

    test "skunked but entered anglers show up with the 0.5 attendance bonus only" do
      t, w = build_finished(season_tag: "Wednesday 2026")
      add_solo(tournament: t, in_window: w, name: "Alpha",   lengths: [25])
      add_solo(tournament: t, in_window: w, name: "Bravo",   lengths: [20])
      add_solo(tournament: t, in_window: w, name: "Charlie", lengths: [15])
      add_solo(tournament: t, in_window: w, name: "Skunked", lengths: [])

      result = Standings.call(club: @club, season_tag: "Wednesday 2026")
      skunked = result.find { |r| r[:user].name == "Skunked" }
      assert_not_nil skunked, "Skunked angler should appear in standings via attendance bonus"
      assert_equal 0.5, skunked[:points]
    end

    test "excludes in-progress tournaments" do
      future_end = 1.hour.from_now
      starts_at = future_end - 4.hours
      tournament = create(:tournament, club: @club, mode: :solo, awards_season_points: true,
                          season_tag: "Wednesday 2026", starts_at: starts_at, ends_at: future_end)
      create(:scoring_slot, tournament: tournament, species: @walleye, slot_count: 2)
      add_solo(tournament: tournament, in_window: starts_at + 1.hour, name: "Alpha",   lengths: [25])
      add_solo(tournament: tournament, in_window: starts_at + 1.hour, name: "Bravo",   lengths: [20])
      add_solo(tournament: tournament, in_window: starts_at + 1.hour, name: "Charlie", lengths: [15])

      assert_equal [], Standings.call(club: @club, season_tag: "Wednesday 2026")
    end

    test "excludes non-points-eligible tournaments with same season_tag" do
      t, w = build_finished(season_tag: "Wednesday 2026", awards: false)
      add_solo(tournament: t, in_window: w, name: "Alpha",   lengths: [25])
      add_solo(tournament: t, in_window: w, name: "Bravo",   lengths: [20])
      add_solo(tournament: t, in_window: w, name: "Charlie", lengths: [15])
      assert_equal [], Standings.call(club: @club, season_tag: "Wednesday 2026")
    end

    test "tied total sorts alphabetically by name" do
      t1, w1 = build_finished(season_tag: "Wednesday 2026", ends_at: 2.weeks.ago)
      t2, w2 = build_finished(season_tag: "Wednesday 2026", ends_at: 1.week.ago)

      # Bravo wins t1, Charlie+Delta finish 2/3
      add_solo(tournament: t1, in_window: w1, name: "Bravo",   lengths: [25])
      add_solo(tournament: t1, in_window: w1, name: "Charlie", lengths: [20])
      add_solo(tournament: t1, in_window: w1, name: "Delta",   lengths: [15])

      # Alpha wins t2, Charlie+Delta again finish 2/3
      add_solo(tournament: t2, in_window: w2, name: "Alpha",   lengths: [25])
      add_solo(tournament: t2, in_window: w2, name: "Charlie", lengths: [20])
      add_solo(tournament: t2, in_window: w2, name: "Delta",   lengths: [15])

      result = Standings.call(club: @club, season_tag: "Wednesday 2026")

      # With the 0.5 attendance bonus per-tournament:
      #   Alpha   in t2 only     → 3 + 0.5         = 3.5
      #   Bravo   in t1 only     → 3 + 0.5         = 3.5
      #   Charlie in both        → 2 + 2 + 0.5*2   = 5.0
      #   Delta   in both        → 1 + 1 + 0.5*2   = 3.0
      # Alpha and Bravo tied at 3.5 — Alpha first by alphabetical
      # Charlie still highest overall, Delta lowest
      assert_equal "Charlie", result.first[:user].name
      tied_at_3_5 = result.select { |r| r[:points] == 3.5 }.map { |r| r[:user].name }
      assert_equal ["Alpha", "Bravo"], tied_at_3_5
    end

    test "row includes per-tournament breakdown" do
      t, w = build_finished(season_tag: "Wednesday 2026", ends_at: 1.week.ago)
      add_solo(tournament: t, in_window: w, name: "Alpha",   lengths: [25])
      add_solo(tournament: t, in_window: w, name: "Bravo",   lengths: [20])
      add_solo(tournament: t, in_window: w, name: "Charlie", lengths: [15])

      result = Standings.call(club: @club, season_tag: "Wednesday 2026")
      alpha = result.find { |r| r[:user].name == "Alpha" }
      assert_equal 1, alpha[:breakdown].size
      assert_equal t.id, alpha[:breakdown].first[:tournament_id]
      assert_equal 3.5,  alpha[:breakdown].first[:points]
    end
  end
end
