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
  end
end
