require "test_helper"

module Tournaments
  class DrawTaggedWinnerTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @club = create(:club)
      @tagged = Species.find_or_create_by!(name: "Tagged Walleye")
      @user = create(:user, club: @club)
      @organizer = create(:user, club: @club, role: :organizer)
      @t = build(:tournament, club: @club, format: :tagged, mode: :solo,
                 kind: :event, starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      @t.scoring_slots.build(species: @tagged, slot_count: 1)
      @t.save!
      @entry = create(:tournament_entry, tournament: @t)
      create(:tournament_entry_member, tournament_entry: @entry, user: @user)
    end

    test "picks one active placement and writes draw columns" do
      placement = Catches::PlaceInSlots.call(
        catch: create(:catch, user: @user, species: @tagged, length_inches: 18.0,
                      tag_number: "A001", captured_at_device: 90.minutes.ago)
      )[:created].first

      result = Tournaments::DrawTaggedWinner.call(tournament: @t, drawn_by: @organizer)

      @t.reload
      assert_equal placement.id, @t.drawn_winning_placement_id
      assert_not_nil @t.drawn_at
      assert_equal @organizer.id, @t.drawn_by_user_id
      assert_equal placement.id, result.id
    end

    test "raises NoEligibleCatchesError when there are no active placements" do
      assert_raises(Tournaments::DrawTaggedWinner::NoEligibleCatchesError) do
        Tournaments::DrawTaggedWinner.call(tournament: @t, drawn_by: @organizer)
      end
    end

    test "raises WrongFormatError if tournament format is not tagged" do
      standard = create(:tournament, club: @club, format: :standard, mode: :solo,
                        starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      assert_raises(Tournaments::DrawTaggedWinner::WrongFormatError) do
        Tournaments::DrawTaggedWinner.call(tournament: standard, drawn_by: @organizer)
      end
    end

    test "raises NotEndedError if tournament has not yet ended" do
      @t.update_columns(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: @user, species: @tagged, length_inches: 18.0,
                      tag_number: "A001", captured_at_device: 30.minutes.ago)
      )
      assert_raises(Tournaments::DrawTaggedWinner::NotEndedError) do
        Tournaments::DrawTaggedWinner.call(tournament: @t, drawn_by: @organizer)
      end
    end

    test "refuses a second draw without force" do
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: @user, species: @tagged, length_inches: 18.0,
                      tag_number: "A001", captured_at_device: 90.minutes.ago)
      )
      Tournaments::DrawTaggedWinner.call(tournament: @t, drawn_by: @organizer)
      assert_raises(Tournaments::DrawTaggedWinner::AlreadyDrawnError) do
        Tournaments::DrawTaggedWinner.call(tournament: @t, drawn_by: @organizer)
      end
    end

    test "force: true overwrites a previous draw" do
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: @user, species: @tagged, length_inches: 18.0,
                      tag_number: "A001", captured_at_device: 90.minutes.ago)
      )
      first = Tournaments::DrawTaggedWinner.call(tournament: @t, drawn_by: @organizer)
      first_drawn_at = @t.reload.drawn_at

      travel 1.second do
        second = Tournaments::DrawTaggedWinner.call(tournament: @t, drawn_by: @organizer, force: true)
        @t.reload
        assert_not_equal first_drawn_at, @t.drawn_at
        assert_kind_of CatchPlacement, second
      end
    end

    test "enqueues a push notification to the winner" do
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: @user, species: @tagged, length_inches: 18.0,
                      tag_number: "A001", captured_at_device: 90.minutes.ago)
      )
      assert_enqueued_with(job: DeliverPushNotificationJob) do
        Tournaments::DrawTaggedWinner.call(tournament: @t, drawn_by: @organizer)
      end
    end
  end
end
