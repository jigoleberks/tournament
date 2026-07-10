require "test_helper"

module Catches
  class ReconcileProgressiveLengthTest < ActiveSupport::TestCase
    setup do
      @club = create(:club)
      @walleye = Species.find_or_create_by!(name: "Walleye")
      @user = create(:user, club: @club)
      @tournament = build(:tournament, club: @club, format: :progressive_length, mode: :solo,
                          starts_at: 3.hours.ago, ends_at: 1.hour.from_now)
      @tournament.scoring_slots.build(species: @walleye, slot_count: 1)
      @tournament.save!
      @entry = create(:tournament_entry, tournament: @tournament)
      create(:tournament_entry_member, tournament_entry: @entry, user: @user)
    end

    # captured_at_device must fall inside the tournament window or the catch is
    # not eligible and is silently skipped.
    def catch_at(length, minutes_ago)
      create(:catch, user: @user, species: @walleye, length_inches: length,
                     captured_at_device: minutes_ago.minutes.ago, status: :synced)
    end

    def reconcile(exclude_catch_id: nil)
      ReconcileProgressiveLength.call(tournament: @tournament, entry: @entry,
                                      species: @walleye, exclude_catch_id: exclude_catch_id)
    end

    def active_rungs
      @entry.catch_placements.where(active: true).order(:slot_index)
            .map { |p| [p.slot_index, p.catch.length_inches.to_i] }
    end

    test "builds an ascending ladder with slot_index 0 as the smallest rung" do
      catch_at(12, 120)
      catch_at(15, 90)
      catch_at(18, 60)
      reconcile
      assert_equal [[0, 12], [1, 15], [2, 18]], active_rungs
    end

    test "a smaller fish never joins the ladder" do
      catch_at(12, 120)
      catch_at(9, 90)
      catch_at(15, 60)
      reconcile
      assert_equal [[0, 12], [1, 15]], active_rungs
    end

    test "a late big fish captured early renumbers the ladder and drops rungs above it" do
      catch_at(12, 120)
      catch_at(15, 60)
      catch_at(18, 30)
      reconcile
      assert_equal [[0, 12], [1, 15], [2, 18]], active_rungs

      catch_at(20, 90) # captured between the 12 and the 15
      reconcile
      assert_equal [[0, 12], [1, 20]], active_rungs
    end

    test "a small fish captured earliest inserts at rung 0 and shifts every rung up" do
      catch_at(12, 90)
      catch_at(15, 60)
      reconcile
      assert_equal [[0, 12], [1, 15]], active_rungs

      catch_at(8, 120) # captured before both — becomes the new rung 0
      reconcile
      assert_equal [[0, 8], [1, 12], [2, 15]], active_rungs
    end

    test "renumbering surviving rungs on insert does not appear in created or bumped" do
      first = catch_at(12, 90)
      second = catch_at(15, 60)
      reconcile
      assert_equal [[0, 12], [1, 15]], active_rungs

      small = catch_at(8, 120) # captured earliest and smallest — becomes the new rung 0
      result = reconcile

      # The 12 and 15 survive but get new placement rows at shifted slot_index
      # values (activate_placement! looks up by (catch_id, entry_id, species_id,
      # slot_index)). Only the genuinely new catch should show up as created;
      # the renumbered survivors must not, and nothing fell off the ladder.
      assert_equal [small.id], result[:created].map(&:catch_id)
      assert_empty result[:bumped]
      assert_equal [[0, 8], [1, 12], [2, 15]], active_rungs
    end

    test "returns created and bumped placements" do
      catch_at(12, 120)
      catch_at(15, 60)
      result = reconcile
      assert_equal [12, 15], result[:created].map { |p| p.catch.length_inches.to_i }.sort
      assert_empty result[:bumped]

      catch_at(20, 90)
      result = reconcile
      assert_equal [20], result[:created].map { |p| p.catch.length_inches.to_i }
      assert_equal [15], result[:bumped].map { |p| p.catch.length_inches.to_i }
    end

    test "an unchanged ladder reports nothing created and nothing bumped" do
      catch_at(12, 120)
      catch_at(15, 60)
      reconcile
      catch_at(10, 30) # no-op: doesn't beat 15
      result = reconcile
      assert_empty result[:created]
      assert_empty result[:bumped]
      assert_equal [[0, 12], [1, 15]], active_rungs
    end

    test "a disqualified rung is re-derived out, re-qualifying a later fish" do
      catch_at(12, 120)
      mid = catch_at(20, 90)
      catch_at(15, 60) # currently a no-op, blocked by the 20
      reconcile
      assert_equal [[0, 12], [1, 20]], active_rungs

      mid.update!(status: :disqualified)
      reconcile
      assert_equal [[0, 12], [1, 15]], active_rungs
    end

    test "exclude_catch_id keeps a catch off the ladder" do
      catch_at(12, 120)
      excluded = catch_at(18, 60)
      reconcile(exclude_catch_id: excluded.id)
      assert_equal [[0, 12]], active_rungs
    end
  end
end
