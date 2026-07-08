require "test_helper"

class Judges::ManualOverridesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @club = create(:club)
    @t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    @walleye = create(:species, club: @club)
    @pike = create(:species, club: @club)
    create(:scoring_slot, tournament: @t, species: @walleye, slot_count: 1)
    create(:scoring_slot, tournament: @t, species: @pike, slot_count: 1)
    @judge = create(:user, club: @club)
    create(:tournament_judge, tournament: @t, user: @judge)
    angler = create(:user, club: @club)
    entry = create(:tournament_entry, tournament: @t)
    create(:tournament_entry_member, tournament_entry: entry, user: angler)
    @catch = create(:catch, user: angler, species: @walleye, length_inches: 20)
    Catches::PlaceInSlots.call(catch: @catch)
    sign_in_as(@judge)
  end

  test "POST changes length and notes the override" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { length_inches: "19.75", note: "tail" }
    assert_equal 19.75, @catch.reload.length_inches.to_f
  end

  test "GET new prefills cm length snapped to the quarter grid like the show page" do
    # Seed from the catch's own logged unit (cm), not the judge's preference.
    @catch.update!(length_unit: "centimeters")
    get new_judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id)
    assert_response :success
    # 20 in = 50.8 cm, which snaps to the 0.25 grid as 50.75 — the same value the
    # catch show page prefills. (A plain .round(1) would give 50.8.)
    assert_select "input#length[value=?]", "50.75"
  end

  test "GET new seeds the unit toggle from the catch's logged unit, not the judge's preference" do
    # Catch logged in inches; judge prefers cm. The form must seed the catch's
    # unit so a species- or note-only override round-trips instead of re-snapping
    # length and flipping the unit — LengthParamParsing's untouched-length guard
    # only fires when the submitted unit matches the catch's.
    @judge.update!(length_unit: "centimeters")
    get new_judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id)
    assert_select "input[name=length_unit][value=inches][checked=checked]"
    assert_select "input[name=length_unit][value=centimeters][checked=checked]", count: 0
  end

  test "POST note-only override by a differently-unit'd judge does not drift the length" do
    # Regression: a judge who prefers cm opens an inches-logged catch and edits
    # only the note. With the form seeded from the catch's unit, the resubmitted
    # prefill (20 inches) must round-trip — no length change, no re-score.
    @judge.update!(length_unit: "centimeters")
    assert_no_changes -> { @catch.reload.length_inches } do
      post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
           params: { species_id: @catch.species_id, length: "20", length_unit: "inches", note: "clean fish" }
    end
    assert_equal "inches", @catch.reload.length_unit
  end

  test "POST with length and length_unit=inches stores inches as-is" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { length: "19.5", length_unit: "inches", note: "remeasured" }
    assert_equal 19.5, @catch.reload.length_inches.to_f
  end

  test "POST with length and length_unit=centimeters converts cm to inches" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { length: "50", length_unit: "centimeters", note: "remeasured" }
    # 50 cm / 2.54 = 19.685 in, stored to 2dp by the schema (~19.69)
    assert_in_delta 19.685, @catch.reload.length_inches.to_f, 0.01
  end

  test "POST with cm length records the centimeters unit" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { length: "50", length_unit: "centimeters", note: "remeasured" }
    assert_equal "centimeters", @catch.reload.length_unit
  end

  test "POST with inch length records the inches unit" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { length: "19.5", length_unit: "inches", note: "remeasured" }
    assert_equal "inches", @catch.reload.length_unit
  end

  test "POST snaps an off-grid override to the quarter grid before converting" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { length: "50.1", length_unit: "centimeters", note: "remeasured" }
    # 50.1 cm snaps to 50.0 cm (nearest 0.25), then 50 / 2.54 = 19.685 in.
    # Without the snap it would store 50.1 / 2.54 = 19.72.
    assert_in_delta 19.685, @catch.reload.length_inches.to_f, 0.01
  end

  test "POST with inches snaps an off-grid value to the quarter grid" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { length: "19.8", length_unit: "inches", note: "remeasured" }
    assert_equal 19.75, @catch.reload.length_inches.to_f
  end

  test "POST with an invalid length redirects with an alert instead of 500" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { length_inches: "-5", note: "typo" }

    assert_redirected_to judges_tournament_catch_path(tournament_id: @t.id, id: @catch.id)
    assert_not_nil flash[:alert]
    assert_equal 20, @catch.reload.length_inches.to_f, "invalid override should not persist"
  end

  test "GET new on a catch from another tournament is not found" do
    foreign_catch = build_foreign_catch
    get new_judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: foreign_catch.id)
    assert_response :not_found
  end

  test "POST override on a catch from another tournament is not found" do
    foreign_catch = build_foreign_catch
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: foreign_catch.id),
         params: { length_inches: "40", note: "drive-by" }
    assert_response :not_found
    assert_equal 21, foreign_catch.reload.length_inches.to_f
  end

  test "POST with species_id changes the catch's species" do
    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { species_id: @pike.id, note: "misidentified" }

    @catch.reload
    assert_equal @pike.id, @catch.species_id
    assert_equal @pike.id, @catch.catch_placements.active.first.species_id
  end

  test "a judge length edit leaves another club's tournament stale" do
    # The angler is also entered in a second club's tournament, with this catch
    # holding the slot there too. A judge is assigned per-tournament, so a
    # club-A judge's length correction must not reconcile or reshuffle club B.
    angler = @catch.user
    club_b = create(:club)
    create(:club_membership, user: angler, club: club_b)
    t_b = create(:tournament, club: club_b, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    create(:scoring_slot, tournament: t_b, species: @walleye, slot_count: 1)
    entry_b = create(:tournament_entry, tournament: t_b)
    create(:tournament_entry_member, tournament_entry: entry_b, user: angler)
    @catch.catch_placements.destroy_all
    Catches::PlaceInSlots.call(catch: @catch) # placed in @t (club A) and t_b (club B)
    # A larger backup that a whole-basket re-derive would promote if club B ran.
    create(:catch, user: angler, species: @walleye, length_inches: 16,
                   captured_at_device: 30.minutes.ago, status: :synced)

    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { length: "14", length_unit: "inches", note: "remeasured" }

    active_b = t_b.catch_placements.active.where(species: @walleye)
    assert_equal @catch.id, active_b.first&.catch_id, "club B left stale, not reconciled by a club-A judge"
  end

  test "POST override with entry from another tournament is not found" do
    other_t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    other_entry = create(:tournament_entry, tournament: other_t)
    create(:scoring_slot, tournament: other_t, species: @walleye, slot_count: 1)

    post judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id),
         params: { slot_index: "0", entry_id: other_entry.id, note: "drive-by" }
    assert_response :not_found
    assert_equal 0, other_entry.catch_placements.count
  end

  test "GET new shows the force-slot fields on a slot-based format" do
    get new_judges_tournament_catch_manual_override_path(tournament_id: @t.id, catch_id: @catch.id)
    assert_response :success
    assert_select "input[name=slot_index]"
    assert_select "input[name=entry_id]"
  end

  test "GET new hides the force-slot fields on a re-derive format (Pro Walleye)" do
    pw, catch = pro_walleye_setup
    get new_judges_tournament_catch_manual_override_path(tournament_id: pw.id, catch_id: catch.id)
    assert_response :success
    assert_select "input[name=slot_index]", count: 0
    assert_select "input[name=entry_id]", count: 0
  end

  test "POST force-slot on a re-derive format redirects with an alert instead of 500" do
    pw, catch, entry = pro_walleye_setup(with_entry: true)
    post judges_tournament_catch_manual_override_path(tournament_id: pw.id, catch_id: catch.id),
         params: { slot_index: "2", entry_id: entry.id, note: "force" }
    assert_redirected_to judges_tournament_catch_path(tournament_id: pw.id, id: catch.id)
    assert_not_nil flash[:alert]
  end

  private

  def pro_walleye_setup(with_entry: false)
    walleye = Species.find_or_create_by!(name: "Walleye")
    pw = build(:tournament, club: @club, format: :pro_walleye, mode: :team,
               starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    pw.scoring_slots.build(species: walleye, slot_count: 5)
    pw.save!
    create(:tournament_judge, tournament: pw, user: @judge)
    angler = create(:user, club: @club)
    entry = create(:tournament_entry, tournament: pw)
    create(:tournament_entry_member, tournament_entry: entry, user: angler)
    catch = create(:catch, user: angler, species: walleye, length_inches: 23,
                           captured_at_device: 30.minutes.ago)
    Catches::PlaceInSlots.call(catch: catch)
    with_entry ? [pw, catch, entry] : [pw, catch]
  end

  def build_foreign_catch
    other_t = create(:tournament, club: @club, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    other_angler = create(:user, club: @club)
    other_entry = create(:tournament_entry, tournament: other_t)
    create(:tournament_entry_member, tournament_entry: other_entry, user: other_angler)
    create(:scoring_slot, tournament: other_t, species: @walleye, slot_count: 1)
    foreign_catch = create(:catch, user: other_angler, species: @walleye, length_inches: 21, status: :synced)
    Catches::PlaceInSlots.call(catch: foreign_catch)
    foreign_catch
  end

  def sign_in_as(user)
    token = SignInToken.issue!(user: user)
    get consume_session_path(token: token.token)
  end
end
