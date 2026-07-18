require "application_system_test_case"

# In standalone iOS the only back-navigation is the edge swipe, which Turbo
# services as a *restoration* visit: the cached snapshot renders with no server
# round trip, and any Turbo Stream broadcasts missed while on the other page
# are never replayed. stream_refresh_controller must detect the restore in
# connect() and re-render from the server.
class StreamRefreshTest < ApplicationSystemTestCase
  test "a Turbo restore visit re-renders the leaderboard from the server" do
    club = create(:club)
    walleye = create(:species, club: club)
    angler = create(:user, club: club, name: "Angler A")

    tournament = create(:tournament, club: club, name: "League Night",
                        starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 1)
    entry = create(:tournament_entry, tournament: tournament, name: "Zebra Boat")
    create(:tournament_entry_member, tournament_entry: entry, user: angler)

    sign_in_as(angler)
    visit tournament_path(tournament)
    assert_text "Zebra Boat"

    # Leave via a Turbo-driven link so the page enters Turbo's snapshot cache
    # (Capybara's visit is a full navigation and would not), then mutate state
    # server-side — standing in for a broadcast missed while away.
    find("a[aria-label='Home']").click
    assert_text "Hello, #{angler.name}", wait: 5
    entry.update!(name: "Renamed Boat")

    page.go_back

    # The restored snapshot alone would still read "Zebra Boat"; only a
    # server re-render shows the new name.
    assert_text "Renamed Boat", wait: 5
  end

  # Offline on the water, the service worker answers fetches with a bare 503
  # ("offline"); an unguarded replace-visit on foreground/restore would render
  # that over a stale-but-readable leaderboard — strictly worse than doing
  # nothing. The controller must probe reachability and keep the snapshot.
  test "an offline restore visit keeps the stale leaderboard instead of wiping it" do
    club = create(:club)
    walleye = create(:species, club: club)
    angler = create(:user, club: club, name: "Angler A")

    tournament = create(:tournament, club: club, name: "League Night",
                        starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: tournament, species: walleye, slot_count: 1)
    entry = create(:tournament_entry, tournament: tournament, name: "Zebra Boat")
    create(:tournament_entry_member, tournament_entry: entry, user: angler)

    sign_in_as(angler)
    visit tournament_path(tournament)
    assert_text "Zebra Boat"

    find("a[aria-label='Home']").click
    assert_text "Hello, #{angler.name}", wait: 5

    # Simulate network loss the way the SW presents it: every fetch resolves
    # to a 503 "offline" response. Both the reachability probe and Turbo's
    # visit fetch see this.
    page.execute_script(<<~JS)
      window.fetch = () => Promise.resolve(
        new Response("offline", { status: 503, headers: { "Content-Type": "text/html" } })
      )
    JS

    page.go_back

    # The restored snapshot must survive. Before the guard, Turbo rendered the
    # 503 body and the leaderboard was wiped.
    sleep 1
    assert_text "Zebra Boat", wait: 5
  end
end
