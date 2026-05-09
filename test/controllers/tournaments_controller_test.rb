require "test_helper"

class TournamentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    post session_path, params: { email: @user.email }
    get consume_session_path(token: SignInToken.last.token)
  end

  test "archived redirects to sign in when not signed in" do
    delete session_path
    get archived_tournaments_path
    assert_redirected_to new_session_path
  end

  test "archived returns 200 when signed in" do
    get archived_tournaments_path
    assert_response :success
  end

  test "archived includes tournaments ended more than 24h ago, newest first" do
    older = create(:tournament, club: @club, name: "Older", ends_at: 5.days.ago)
    newer = create(:tournament, club: @club, name: "Newer", ends_at: 26.hours.ago)
    get archived_tournaments_path
    assert_match "Older", response.body
    assert_match "Newer", response.body
    assert response.body.index("Newer") < response.body.index("Older"),
      "Newer (more recent ends_at) should appear before Older"
  end

  test "archived excludes tournaments ended within the last 24h" do
    create(:tournament, club: @club, name: "RecentlyEnded", ends_at: 2.hours.ago)
    get archived_tournaments_path
    assert_no_match "RecentlyEnded", response.body
  end

  test "archived excludes tournaments with no ends_at" do
    create(:tournament, club: @club, name: "OpenEnded", ends_at: nil)
    get archived_tournaments_path
    assert_no_match "OpenEnded", response.body
  end

  test "archived is scoped to the current user's club" do
    other_club = create(:club)
    create(:tournament, club: other_club, name: "OtherClubTourney", ends_at: 5.days.ago)
    get archived_tournaments_path
    assert_no_match "OtherClubTourney", response.body
  end

  test "show renders the ends label and date/time on the same line, date right-aligned" do
    ends_at = Time.zone.local(2026, 6, 15, 18, 30)
    tournament = create(:tournament, club: @club, ends_at: ends_at)
    get tournament_path(tournament)
    assert_response :success
    assert_select "[class~='justify-between']" do
      assert_select "*", text: /Ends|Ended/
      assert_select "*", text: /Jun 15, 2026 ·\s+6:30 PM/
    end
  end

  test "show shows a green check beside an approved fish on the leaderboard (no 'Approved by' tag here)" do
    tournament = create(:tournament, club: @club)
    species = create(:species, club: @club)
    create(:scoring_slot, tournament: tournament, species: species, slot_count: 1)
    entry = create(:tournament_entry, tournament: tournament, name: "Team Reel Deal")
    create(:tournament_entry_member, tournament_entry: entry, user: @user)
    catch_record = create(:catch, user: @user, species: species, length_inches: 18.5)
    create(:catch_placement, catch: catch_record, tournament: tournament,
                              tournament_entry: entry, species: species, slot_index: 0)
    judge = create(:user, club: @club, name: "Judge Judy")
    create(:judge_action, judge_user: judge, catch: catch_record, action: :approve)

    get tournament_path(tournament)
    assert_response :success
    assert_select "[data-test=approved-check]", count: 1
    assert_no_match "Approved by", response.body
  end

  test "show does not render approved markers for unreviewed fish" do
    tournament = create(:tournament, club: @club)
    species = create(:species, club: @club)
    create(:scoring_slot, tournament: tournament, species: species, slot_count: 1)
    entry = create(:tournament_entry, tournament: tournament, name: "Team Reel Deal")
    create(:tournament_entry_member, tournament_entry: entry, user: @user)
    catch_record = create(:catch, user: @user, species: species, length_inches: 18.5)
    create(:catch_placement, catch: catch_record, tournament: tournament,
                              tournament_entry: entry, species: species, slot_index: 0)

    get tournament_path(tournament)
    assert_response :success
    assert_select "[data-test=approved-check]", count: 0
    assert_no_match "Approved by", response.body
  end

  test "blind+active show page: entered angler sees own entry's fish, others blanked" do
    species = create(:species, club: @club)
    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               blind_leaderboard: true)
    create(:scoring_slot, tournament: t, species: species, slot_count: 1)

    my_entry = create(:tournament_entry, tournament: t, name: "My Entry")
    create(:tournament_entry_member, tournament_entry: my_entry, user: @user)
    my_catch = create(:catch, user: @user, species: species, length_inches: 22.5)
    create(:catch_placement, catch: my_catch, tournament: t,
                              tournament_entry: my_entry, species: species, slot_index: 0)

    other_user = create(:user, club: @club, name: "Other Angler")
    other_entry = create(:tournament_entry, tournament: t, name: "Other Entry")
    create(:tournament_entry_member, tournament_entry: other_entry, user: other_user)
    other_catch = create(:catch, user: other_user, species: species, length_inches: 28.0)
    create(:catch_placement, catch: other_catch, tournament: t,
                              tournament_entry: other_entry, species: species, slot_index: 0)

    get tournament_path(t)
    assert_response :success

    # Both entry names are visible in the leaderboard
    assert_match "My Entry", response.body
    assert_match "Other Entry", response.body

    # My length appears, but the other angler's length does not
    assert_match "22.5", response.body
    assert_no_match "28.0", response.body

    # Banner is rendered, AND lives inside the #leaderboard wrapper so a
    # reveal-stream replace (which targets id="leaderboard") sweeps the banner
    # away alongside the table.
    assert_match(/Blind leaderboard/i, response.body)
    assert_select "#leaderboard #blind-leaderboard-banner"
  end

  test "blind+active show page: non-entered, non-organizer member sees only entry names, totals dashed" do
    member = create(:user, club: @club, name: "Bystander", role: :member)
    post session_path, params: { email: member.email }
    get consume_session_path(token: SignInToken.last.token)

    species = create(:species, club: @club)
    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               blind_leaderboard: true)
    create(:scoring_slot, tournament: t, species: species, slot_count: 1)

    competitor = create(:user, club: @club, name: "Competitor")
    entry = create(:tournament_entry, tournament: t, name: "Sole Entry")
    create(:tournament_entry_member, tournament_entry: entry, user: competitor)
    catch_record = create(:catch, user: competitor, species: species, length_inches: 31.25)
    create(:catch_placement, catch: catch_record, tournament: t,
                              tournament_entry: entry, species: species, slot_index: 0)

    get tournament_path(t)
    assert_response :success
    assert_match "Sole Entry", response.body
    assert_no_match "31.25", response.body
  end

  test "blind+active show page: judge sees full data" do
    judge = create(:user, club: @club, name: "Judge", role: :member)
    species = create(:species, club: @club)
    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               blind_leaderboard: true)
    create(:scoring_slot, tournament: t, species: species, slot_count: 1)
    create(:tournament_judge, tournament: t, user: judge)

    competitor = create(:user, club: @club, name: "Competitor")
    entry = create(:tournament_entry, tournament: t, name: "Some Entry")
    create(:tournament_entry_member, tournament_entry: entry, user: competitor)
    catch_record = create(:catch, user: competitor, species: species, length_inches: 31.25)
    create(:catch_placement, catch: catch_record, tournament: t,
                              tournament_entry: entry, species: species, slot_index: 0)

    post session_path, params: { email: judge.email }
    get consume_session_path(token: SignInToken.last.token)

    get tournament_path(t)
    assert_response :success
    assert_match "31.25", response.body
    assert_no_match "blind-leaderboard-banner", response.body
  end

  test "ended blind tournament show page: every viewer sees full leaderboard" do
    species = create(:species, club: @club)
    t = create(:tournament, club: @club, starts_at: 2.hours.ago, ends_at: 1.hour.ago,
               blind_leaderboard: true)
    create(:scoring_slot, tournament: t, species: species, slot_count: 1)

    competitor = create(:user, club: @club, name: "Competitor")
    entry = create(:tournament_entry, tournament: t, name: "Winning Entry")
    create(:tournament_entry_member, tournament_entry: entry, user: competitor)
    catch_record = create(:catch, user: competitor, species: species, length_inches: 31.25)
    create(:catch_placement, catch: catch_record, tournament: t,
                              tournament_entry: entry, species: species, slot_index: 0)

    get tournament_path(t)
    assert_response :success
    assert_match "31.25", response.body
    assert_no_match "blind-leaderboard-banner", response.body
  end

  test "blind+active show page: entered angler subscribes to entry stream and reveal" do
    species = create(:species, club: @club)
    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               blind_leaderboard: true)
    create(:scoring_slot, tournament: t, species: species, slot_count: 1)

    entry = create(:tournament_entry, tournament: t, name: "My Entry")
    create(:tournament_entry_member, tournament_entry: entry, user: @user)

    get tournament_path(t)
    assert_response :success
    assert_match Turbo::StreamsChannel.signed_stream_name("tournament:#{t.id}:leaderboard:entry:#{entry.id}"), response.body
    assert_match Turbo::StreamsChannel.signed_stream_name("tournament:#{t.id}:leaderboard:reveal"), response.body
    assert_no_match Regexp.new(Regexp.escape(Turbo::StreamsChannel.signed_stream_name("tournament:#{t.id}:leaderboard:full"))), response.body
  end

  test "blind+active show page: non-entered member subscribes only to reveal" do
    member = create(:user, club: @club, name: "Bystander", role: :member)
    post session_path, params: { email: member.email }
    get consume_session_path(token: SignInToken.last.token)

    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               blind_leaderboard: true)

    get tournament_path(t)
    assert_response :success
    assert_match Turbo::StreamsChannel.signed_stream_name("tournament:#{t.id}:leaderboard:reveal"), response.body
    assert_no_match Regexp.new(Regexp.escape(Turbo::StreamsChannel.signed_stream_name("tournament:#{t.id}:leaderboard:full"))), response.body
    # No entry-stream subscription. We match the un-signed-name prefix encoded into the signed token's payload.
    # Since signed names don't surface plaintext, fall back to: any entry-stream signed name would change per entry id;
    # easiest invariant — assert there's no signed turbo-cable-stream-source that decodes to an entry stream.
    sources = response.body.scan(/signed-stream-name="([^"]+)"/).flatten
    decoded_names = sources.map do |signed|
      Turbo::StreamsChannel.send(:verifier).verified(signed) rescue nil
    end.compact
    assert decoded_names.none? { |n| n.start_with?("tournament:#{t.id}:leaderboard:entry:") },
      "Expected no entry-stream subscription, got: #{decoded_names.inspect}"
  end

  test "non-blind tournament: every viewer subscribes to :full" do
    t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
               blind_leaderboard: false)
    get tournament_path(t)
    assert_response :success
    assert_match Turbo::StreamsChannel.signed_stream_name("tournament:#{t.id}:leaderboard:full"), response.body
    assert_no_match Regexp.new(Regexp.escape(Turbo::StreamsChannel.signed_stream_name("tournament:#{t.id}:leaderboard:reveal"))), response.body
  end

  test "show: ended solo tournament with entries renders angler count footer in Scoring section" do
    species = create(:species, club: @club)
    t = create(:tournament, club: @club, mode: :solo,
               starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    create(:scoring_slot, tournament: t, species: species, slot_count: 1)

    3.times do
      angler = create(:user, club: @club)
      entry  = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: angler)
    end

    get tournament_path(t)
    assert_response :success
    assert_match "3 anglers", response.body
    assert_no_match "team", response.body
  end

  test "show: ended team tournament renders 'N anglers across M teams' footer" do
    species = create(:species, club: @club)
    t = create(:tournament, club: @club, mode: :team,
               starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    create(:scoring_slot, tournament: t, species: species, slot_count: 1)

    # Two teams: one with 3 anglers, one with 2 anglers — 5 anglers across 2 teams.
    team1 = create(:tournament_entry, tournament: t)
    3.times do
      create(:tournament_entry_member, tournament_entry: team1, user: create(:user, club: @club))
    end
    team2 = create(:tournament_entry, tournament: t)
    2.times do
      create(:tournament_entry_member, tournament_entry: team2, user: create(:user, club: @club))
    end

    get tournament_path(t)
    assert_response :success
    assert_match "5 anglers across 2 teams", response.body
  end

  test "show: active tournament does not render the participation footer" do
    species = create(:species, club: @club)
    t = create(:tournament, club: @club, mode: :solo,
               starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: t, species: species, slot_count: 1)

    3.times do
      angler = create(:user, club: @club)
      entry  = create(:tournament_entry, tournament: t)
      create(:tournament_entry_member, tournament_entry: entry, user: angler)
    end

    get tournament_path(t)
    assert_response :success
    assert_no_match "anglers", response.body
  end

  test "show: ended tournament with zero entries does not render participation footer" do
    species = create(:species, club: @club)
    t = create(:tournament, club: @club, mode: :solo,
               starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    create(:scoring_slot, tournament: t, species: species, slot_count: 1)
    # Intentionally no tournament_entry records.

    get tournament_path(t)
    assert_response :success
    assert_no_match "0 anglers", response.body
    assert_no_match "anglers", response.body
  end
end
