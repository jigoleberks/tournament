require "test_helper"

class TournamentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @user = create(:user, club: @club)
    post session_path, params: { email: @user.email }
    get consume_session_path(token: SignInToken.last.token)
  end

  # Helper for the gate tests where the tournament uses entrants_only_leaderboard
  # — adds the test user (or a passed-in user) to a fresh tournament entry.
  def enroll_user_in(tournament, user: @user)
    entry = create(:tournament_entry, tournament: tournament)
    create(:tournament_entry_member, tournament_entry: entry, user: user)
    entry
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
    older = create(:tournament, club: @club, name: "Older", starts_at: 6.days.ago, ends_at: 5.days.ago)
    newer = create(:tournament, club: @club, name: "Newer", starts_at: 2.days.ago, ends_at: 26.hours.ago)
    get archived_tournaments_path
    assert_match "Older", response.body
    assert_match "Newer", response.body
    assert response.body.index("Newer") < response.body.index("Older"),
      "Newer (more recent ends_at) should appear before Older"
  end

  test "archived excludes tournaments ended within the last 24h" do
    create(:tournament, club: @club, name: "RecentlyEnded", starts_at: 4.hours.ago, ends_at: 2.hours.ago)
    get archived_tournaments_path
    assert_no_match "RecentlyEnded", response.body
  end

  test "archived excludes tournaments with no ends_at" do
    # Legacy NULL-ends_at row: bypass the now-required ends_at validation.
    build(:tournament, club: @club, name: "OpenEnded", ends_at: nil).save!(validate: false)
    get archived_tournaments_path
    assert_no_match "OpenEnded", response.body
  end

  test "archived is scoped to the current user's club" do
    other_club = create(:club)
    create(:tournament, club: other_club, name: "OtherClubTourney", starts_at: 6.days.ago, ends_at: 5.days.ago)
    get archived_tournaments_path
    assert_no_match "OtherClubTourney", response.body
  end

  test "archived renders the winner's display_name for tournaments with a placed catch" do
    species = create(:species, club: @club)
    t = create(:tournament, club: @club, name: "BigFishNight",
               starts_at: 6.days.ago, ends_at: 5.days.ago)
    create(:scoring_slot, tournament: t, species: species, slot_count: 1)
    angler = create(:user, club: @club, name: "Galen Patterson")
    entry = create(:tournament_entry, tournament: t)
    create(:tournament_entry_member, tournament_entry: entry, user: angler)
    catch_record = create(:catch, user: angler, species: species, length_inches: 22.5,
                                  captured_at_device: 5.days.ago - 1.hour)
    create(:catch_placement, catch: catch_record, tournament: t,
                              tournament_entry: entry, species: species, slot_index: 0)

    get archived_tournaments_path
    assert_response :success
    assert_match "Galen Patterson", response.body
    assert_match "winner", response.body
  end

  test "archived omits the winner suffix when a tournament has no placed catches" do
    create(:tournament, club: @club, name: "EmptyTourney", starts_at: 6.days.ago, ends_at: 5.days.ago)
    get archived_tournaments_path
    assert_response :success
    assert_match "EmptyTourney", response.body
    assert_no_match "winner", response.body
  end

  test "archived does not render the season_tag on rows" do
    create(:tournament, club: @club, name: "TaggedTourney",
           starts_at: 6.days.ago, ends_at: 5.days.ago, season_tag: "Spring 2026")
    get archived_tournaments_path
    assert_response :success
    assert_match "TaggedTourney", response.body
    assert_no_match "Spring 2026", response.body
  end

  test "index shows the leaderboard hint on a locked entrants-only row" do
    create(:tournament, club: @club, name: "Closed Active", entrants_only_leaderboard: true)
    get tournaments_path
    assert_response :success
    assert_match "Ask an organizer to add you", response.body
  end

  test "index shows no leaderboard hint when the tournament is open to everyone" do
    create(:tournament, club: @club, name: "Open Active")
    get tournaments_path
    assert_response :success
    assert_no_match "Ask an organizer to add you", response.body
  end

  test "archived shows the leaderboard hint on a locked entrants-only row" do
    create(:tournament, club: @club, name: "Closed Archive",
           starts_at: 6.days.ago, ends_at: 5.days.ago, entrants_only_leaderboard: true)
    get archived_tournaments_path
    assert_response :success
    assert_match "Ask an organizer to add you", response.body
  end

  test "show with entrants_only_leaderboard on: non-entered member is redirected with a flash" do
    tournament = create(:tournament, club: @club, name: "Closed Doors", entrants_only_leaderboard: true)
    get tournament_path(tournament)
    assert_redirected_to root_path
    follow_redirect!
    assert_match(/Ask an organizer to add you/, flash[:alert].to_s)
  end

  test "show with entrants_only_leaderboard on: redirect still applies after the tournament ends" do
    tournament = create(:tournament, club: @club, starts_at: 2.hours.ago, ends_at: 1.hour.ago,
                                     entrants_only_leaderboard: true)
    get tournament_path(tournament)
    assert_redirected_to root_path
  end

  test "show with entrants_only_leaderboard on: entered member is allowed" do
    tournament = create(:tournament, club: @club, entrants_only_leaderboard: true)
    enroll_user_in(tournament)
    get tournament_path(tournament)
    assert_response :success
  end

  test "show with entrants_only_leaderboard on: assigned judge (not entered) is allowed" do
    judge = create(:user, club: @club, name: "Hon. Judge", role: :member)
    tournament = create(:tournament, club: @club, entrants_only_leaderboard: true)
    create(:tournament_judge, tournament: tournament, user: judge)
    post session_path, params: { email: judge.email }
    get consume_session_path(token: SignInToken.last.token)
    get tournament_path(tournament)
    assert_response :success
  end

  test "show with entrants_only_leaderboard on: club organizer (not entered) is allowed" do
    organizer = create(:user, club: @club, name: "Org", role: :organizer)
    tournament = create(:tournament, club: @club, entrants_only_leaderboard: true)
    post session_path, params: { email: organizer.email }
    get consume_session_path(token: SignInToken.last.token)
    get tournament_path(tournament)
    assert_response :success
  end

  test "show with entrants_only_leaderboard on: site admin (not entered) is allowed" do
    admin = create(:user, club: @club, name: "Site Admin", role: :member, admin: true)
    tournament = create(:tournament, club: @club, entrants_only_leaderboard: true)
    post session_path, params: { email: admin.email }
    get consume_session_path(token: SignInToken.last.token)
    get tournament_path(tournament)
    assert_response :success
  end

  test "show with entrants_only_leaderboard off (default): any signed-in club member can view" do
    tournament = create(:tournament, club: @club, name: "Open Doors")
    get tournament_path(tournament)
    assert_response :success
  end

  test "show renders the ends label and date/time on the same line, date right-aligned" do
    ends_at = Time.zone.local(2026, 6, 15, 18, 30)
    tournament = create(:tournament, club: @club, starts_at: ends_at - 4.hours, ends_at: ends_at)
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

  test "show: ended team tournament lists member names under a custom team name" do
    t = create(:tournament, club: @club, mode: :team,
               starts_at: 2.hours.ago, ends_at: 1.hour.ago)
    entry = create(:tournament_entry, tournament: t, name: "Reel Deal")
    create(:tournament_entry_member, tournament_entry: entry,
                                      user: create(:user, club: @club, name: "Alice Angler"))
    create(:tournament_entry_member, tournament_entry: entry,
                                      user: create(:user, club: @club, name: "Bob Bobber"))

    get tournament_path(t)
    assert_response :success
    assert_match "Reel Deal", response.body
    assert_match "Alice Angler + Bob Bobber", response.body
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
