require "application_system_test_case"

class HiddenLengthTournamentTest < ApplicationSystemTestCase
  include LengthHelper

  setup do
    @club = Club.first || create(:club)
    @organizer = create(:user, club: @club, role: :organizer)
    @walleye = create(:species, club: @club, name: "Walleye")
    @angler_a = create(:user, club: @club, name: "Angler A")
    @angler_b = create(:user, club: @club, name: "Angler B")
  end

  test "Hidden Length tournament: rolls target at end and reshuffles leaderboard" do
    t = build(:tournament, club: @club, name: "HL Wed",
              format: :hidden_length, mode: :solo, kind: :event,
              starts_at: 30.minutes.ago, ends_at: 5.minutes.from_now)
    t.scoring_slots.build(species: @walleye, slot_count: 1)
    t.save!

    ea = create(:tournament_entry, tournament: t)
    eb = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: ea, user: @angler_a)
    create(:tournament_entry_member, tournament_entry: eb, user: @angler_b)

    # Each angler logs two catches inside the tournament window.
    [
      [@angler_a, 22, 20.minutes.ago],
      [@angler_a, 17.5, 10.minutes.ago],
      [@angler_b, 14, 15.minutes.ago],
      [@angler_b, 19, 5.minutes.ago]
    ].each do |user, length, captured|
      Catches::PlaceInSlots.call(
        catch: create(:catch, user: user, species: @walleye,
                      length_inches: length, captured_at_device: captured)
      )
    end

    # Pre-reveal: leaderboard is per-catch, largest first.
    sign_in_as(@organizer)
    visit tournament_path(t)
    rows = all("#leaderboard tbody tr")
    assert_equal 4, rows.size, "expected 4 per-catch rows pre-reveal"
    # Topmost row should reference the 22" fish.
    assert_match "22", rows.first.text

    assert_text "Target rolls when the tournament ends"

    # Travel past ends_at and run the lifecycle job.
    t.update_columns(ends_at: 1.minute.ago)
    TournamentLifecycleAnnounceJob.perform_now(tournament_id: t.id, kind: "ended")
    t.reload

    assert_not_nil t.hidden_length_target
    target = t.hidden_length_target

    visit tournament_path(t)
    assert_text "Target was"
    # Pin to the helper output so a typography change in format_length_dual
    # (e.g., curly quotes, separator) is caught by this test rather than
    # silently flipping the substring match.
    assert_text format_length_dual(target)

    # Post-reveal: one row per entry (2 anglers).
    rows = all("#leaderboard tbody tr")
    assert_equal 2, rows.size, "expected 2 per-entry rows post-reveal"

    # Verify ranking: each angler's closest catch.
    a_lengths = [22, 17.5]
    b_lengths = [14, 19]
    a_closest = a_lengths.min_by { |l| (l - target.to_f).abs }
    b_closest = b_lengths.min_by { |l| (l - target.to_f).abs }
    expected_winner = (a_closest - target.to_f).abs <= (b_closest - target.to_f).abs ? "Angler A" : "Angler B"
    assert_match expected_winner, rows.first.text
  end

  private

  # Mirrors the helper used by test/system/big_fish_season_tournament_test.rb.
  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email
    click_button "Send sign-in link"
    visit consume_session_path(token: SignInToken.last.token)
  end
end
