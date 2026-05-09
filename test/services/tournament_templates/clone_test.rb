require "test_helper"

module TournamentTemplates
  class CloneTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = create(:species, club: @club)
      @template = create(:tournament_template, club: @club, name: "Monthly Walleye", mode: :solo)
      @template.tournament_template_scoring_slots.create!(species: @walleye, slot_count: 1)
    end

    test "clone copies template into a new tournament with given dates" do
      starts = 1.day.from_now
      ends   = 1.day.from_now + 4.hours
      tournament = Clone.call(template: @template, starts_at: starts, ends_at: ends)
      assert tournament.persisted?
      assert_equal "Monthly Walleye", tournament.name
      assert_equal 1, tournament.scoring_slots.count
      assert_equal @walleye, tournament.scoring_slots.first.species
      assert_in_delta starts, tournament.starts_at, 1
      assert_equal @template.id, tournament.template_source_id
    end

    test "carries awards_season_points from template onto cloned tournament" do
      template = create(:tournament_template, club: @club, awards_season_points: true)
      tournament = Clone.call(
        template: template,
        starts_at: 1.day.from_now,
        ends_at: 1.day.from_now + 4.hours
      )
      assert tournament.awards_season_points?
    end

    test "does not award season points by default when template flag is off" do
      template = create(:tournament_template, club: @club, awards_season_points: false)
      tournament = Clone.call(
        template: template,
        starts_at: 1.day.from_now,
        ends_at: 1.day.from_now + 4.hours
      )
      refute tournament.awards_season_points?
    end

    test "carries blind_leaderboard from template to tournament" do
      club = create(:club)
      template = create(:tournament_template, club: club, blind_leaderboard: true)

      tournament = TournamentTemplates::Clone.call(
        template: template,
        starts_at: 1.hour.from_now,
        ends_at: 4.hours.from_now,
        name: "League Night"
      )

      assert tournament.blind_leaderboard?
    end

    test "does not flip blind_leaderboard on if template has it off" do
      club = create(:club)
      template = create(:tournament_template, club: club, blind_leaderboard: false)

      tournament = TournamentTemplates::Clone.call(
        template: template,
        starts_at: 1.hour.from_now,
        ends_at: 4.hours.from_now
      )

      assert_not tournament.blind_leaderboard?
    end

    test "clones template format onto the new tournament" do
      template = build(:tournament_template, club: @club, format: :big_fish_season)
      template.tournament_template_scoring_slots.build(species: @walleye, slot_count: 3)
      template.save!

      tournament = TournamentTemplates::Clone.call(
        template: template,
        starts_at: 1.day.from_now,
        ends_at: 2.days.from_now
      )

      assert_equal "big_fish_season", tournament.format
      assert tournament.format_big_fish_season?
    end

    test "default standard format clones onto the new tournament" do
      template = create(:tournament_template, club: @club)
      template.tournament_template_scoring_slots.create!(species: @walleye, slot_count: 1)

      tournament = TournamentTemplates::Clone.call(
        template: template,
        starts_at: 1.day.from_now,
        ends_at: 2.days.from_now
      )

      assert_equal "standard", tournament.format
    end
  end
end
