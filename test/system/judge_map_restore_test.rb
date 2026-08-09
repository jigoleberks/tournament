require "application_system_test_case"

# The judge catch page carries location_edit_controller's draggable GPS pin,
# and Judges::BaseController never opts out of snapshot caching — so an
# edge-swipe back is a Turbo *restoration* visit rendering a cached snapshot
# that was captured with the Leaflet panes still live (measured: 7 panes at
# turbo:before-cache). What must never happen is the container ending up with
# two maps stacked in it, because dragging then moves only one pin and which
# one correct_location submits is ambiguous.
#
# This currently holds on its own — the restored container keeps its
# _leaflet_id, so connect() does not build a second map and the restored map
# stays interactive. That is a property of how Turbo restores the node, not
# something location_edit_controller enforces, so it is worth pinning: the
# controller has a turbo:before-cache teardown to guarantee it either way.
class JudgeMapRestoreTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @walleye = create(:species, club: @club)
    @t = create(:tournament, club: @club, name: "Wed",
                starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)

    # The GPS editor section is gated on current_user.admin?, so only a site
    # admin reviewing a catch ever mounts location_edit_controller.
    @judge = create(:user, club: @club, name: "Mike", admin: true)
    create(:tournament_judge, tournament: @t, user: @judge)

    angler = create(:user, club: @club, name: "Joe")
    entry = create(:tournament_entry, tournament: @t)
    create(:tournament_entry_member, tournament_entry: entry, user: angler)

    @catch = create(:catch, user: angler, species: @walleye, length_inches: 22,
                    status: :needs_review, latitude: 52.9, longitude: -106.0)
    Catches::PlaceInSlots.call(catch: @catch)
  end

  test "a Turbo restore visit to a judged catch rebuilds one map, not two" do
    token = SignInToken.issue!(user: @judge)
    visit consume_session_path(token: token.token)

    visit judges_tournament_catch_path(tournament_id: @t.id, id: @catch.id)
    assert_selector ".leaflet-container", count: 1, wait: 5
    assert_selector ".leaflet-marker-icon", count: 1

    # Leave via a Turbo-driven link so the page enters Turbo's snapshot cache
    # (Capybara's visit is a full navigation and would not).
    find("a[aria-label='Home']").click
    assert_text "Hello, #{@judge.name}", wait: 5

    page.go_back

    assert_selector ".leaflet-container", count: 1, wait: 5
    assert_selector ".leaflet-marker-icon", count: 1
    # Exactly one set of Leaflet panes — two maps in one container would double it.
    assert_equal 7, page.evaluate_script("document.querySelectorAll('.leaflet-pane').length")

    # And the surviving map must still be the live one: a dead instance leaves
    # the pin undraggable, so the judge silently can't correct the location.
    before = page.evaluate_script("document.querySelector('[data-location-edit-target=readout]').textContent")
    page.execute_script(<<~JS)
      const el = document.querySelector('[data-location-edit-target=map]');
      const r = el.getBoundingClientRect();
      ['mousedown', 'mouseup', 'click'].forEach((type) => {
        el.dispatchEvent(new MouseEvent(type, {
          bubbles: true, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2
        }));
      });
    JS
    assert_no_equal_text = ->(v) { refute_equal before, v, "restored map ignored a click — it is not live" }
    Timeout.timeout(5) do
      loop do
        now = page.evaluate_script("document.querySelector('[data-location-edit-target=readout]').textContent")
        break assert_no_equal_text.call(now) if now != before
        sleep 0.1
      end
    end
  end
end
