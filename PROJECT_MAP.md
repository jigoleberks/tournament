# Project Map

A skim-friendly index of every file in `app/` and `test/`. Use it to find the right file when you know roughly what you want to touch. For the domain primer (multi-club model, role boundaries, soft-delete conventions), see `CLAUDE.md`.

## app/controllers/

- `application_controller.rb` — base controller; mixes in `Authentication`, exposes `tournament_leaderboard_visible?` helper, touches `last_seen_at`.
- `home_controller.rb` — signed-in landing page (pending-catches widget, season-points teaser).
- `catches_controller.rb` — member-facing list/map/new/show/edit of catches; owns date-range parsing for the filter bar.
- `tournaments_controller.rb` — public tournament index/show (live leaderboard) and archived listing.
- `notification_settings_controller.rb` — push snooze/unmute per club and per tournament.
- `pre_trip_controller.rb` — renders the pre-trip permissions check page.
- `pwa_controller.rb` — serves `/manifest.webmanifest` and `/service-worker.js` with no-cache headers.
- `rules_controller.rb` — current club rules display.
- `season_points_controller.rb` — season standings and per-season tournament list.
- `sessions_controller.rb` — magic-link create/consume + 8-digit code submission with per-IP rate limits.
- `users_controller.rb` — saves the current user's `length_unit` preference.
- `concerns/`
  - `authentication.rb` — `current_user`, `current_club`, `signed_in?`, `require_sign_in!`, `sign_in!`, `sign_out!`.
- `tournaments/`
  - `catches_controller.rb` — public catch photo modal (turbo-frame), gated to non-blind tournaments where the catch is actively placed.
- `admin/` (laptop UI, organizer-only via `Admin::BaseController`)
  - `base_controller.rb` — requires organizer in `current_club`; sets `admin` layout.
  - `dashboards_controller.rb` — site-wide counters (only populated for `admin?` users).
  - `catches_controller.rb` — club catch history filtered by member.
  - `members_controller.rb` — invite/edit/deactivate/reactivate members; site-admins only for edit/delete.
  - `rules_controller.rb` — CRUD on `ClubRulesRevision` for open-water / ice seasons.
  - `tournaments_controller.rb` — tournament CRUD + nested scoring slots.
  - `tournament_templates_controller.rb` — template CRUD + clone-to-tournament.
  - `tournament_entries_controller.rb` — create/destroy entries (solo or team).
  - `tournament_entry_members_controller.rb` — add/drop team members on an entry (adds are forward-only).
  - `tournament_judges_controller.rb` — assign/remove tournament judges.
  - `clubs_controller.rb` — site-admin club CRUD; renders foreign-club drill-in show page.
  - `clubs/` (site-admin only via `Admin::Clubs::BaseController`)
    - `base_controller.rb` — requires `admin: true`; loads `@foreign_club` from `:club_id`.
    - `catches_controller.rb` — foreign-club catch history.
    - `members_controller.rb` — foreign-club member invite/edit/deactivate.
    - `rules_controller.rb` — foreign-club rules viewer (show/history).
    - `tournaments_controller.rb` — foreign-club tournament list / drill-in show.
    - `tournament_templates_controller.rb` — foreign-club template index/show.
- `judges/` (per-tournament judge UI)
  - `base_controller.rb` — requires a `TournamentJudge` row (or organizer if tournament is friendly).
  - `catches_controller.rb` — review queue (needs-review first) and per-catch detail.
  - `reviews_controller.rb` — applies approve/flag/disqualify judge actions.
  - `manual_overrides_controller.rb` — judge-edit length/species/slot/entry on a catch.
- `organizers/` (mobile organizer UI, mirrors `/admin/*` minus dashboards/rules)
  - `base_controller.rb` — requires organizer in `current_club`; default layout.
  - `catches_controller.rb` / `members_controller.rb` / `tournaments_controller.rb` / `tournament_templates_controller.rb` / `tournament_entries_controller.rb` / `tournament_entry_members_controller.rb` / `tournament_judges_controller.rb` — same actions as their `admin/` cousins.
- `api/` (JSON, session-cookie auth, returns 401 not redirect)
  - `base_controller.rb` — null-session CSRF, requires sign-in.
  - `catches_controller.rb` — offline catch ingest; idempotent on `client_uuid`; supports `teammate_user_id` for logged-by-another.
  - `push_subscriptions_controller.rb` — register/unregister WebPush endpoint.

## app/models/

- `application_record.rb` — primary abstract base.
- `user.rb` — global identity; `admin` flag, `length_unit`, `deactivated_at`, normalizes email lowercase.
- `club.rb` — tenant root; has rules revisions, members, tournaments, templates; tracks `active_rules_season`.
- `club_membership.rb` — join table carrying per-club `role` enum (member/organizer) and `deactivated_at`.
- `club_rules_revision.rb` — append-only rules history per club per season (Action Text body).
- `catch.rb` — `catches` table; status enum (pending_sync/synced/needs_review/disputed/disqualified), `client_uuid`, GPS + conditions + flags; attaches photo/video.
- `catch_placement.rb` — places a catch into a tournament's scoring slot; `active` boolean drives leaderboard inclusion.
- `judge_action.rb` — append-only audit log (`before_state`/`after_state` JSONB) for approve/flag/DQ/manual_override/dock_verify.
- `push_subscription.rb` — WebPush endpoint per user with `muted_until` and `muted_tournament_ids`.
- `scoring_slot.rb` — per-tournament per-species slot count.
- `sign_in_token.rb` — magic-link tokens and 8-digit codes with TTL and attempt cap.
- `species.rb` — global species registry (uniqueness case-insensitive).
- `tournament.rb` — kind (event/ongoing), mode (solo/team), format (standard, big_fish_season, hidden_length, biggest_vs_smallest, fish_train); validates blind/format/train-cars are locked after start; holds `awards_season_points`, `season_tag`, `hidden_length_target`.
- `tournament_entry.rb` — boat/team for a tournament; many entry members + placements.
- `tournament_entry_member.rb` — join row, enforces solo cap (1) and team cap (5), no double-entry across entries.
- `tournament_judge.rb` — assignment of a user to judge a tournament.
- `tournament_template.rb` — reusable tournament spec with default schedule/format; same enums + format-shape validations.
- `tournament_template_scoring_slot.rb` — slot config rows for a template.

## app/services/

### `Catches::*`

- `apply_filters.rb` — single entrypoint for catch list/map filtering (species, lake, date range, sort, match conditions); exposes `MATCH_CONDITION_KEYS`.
- `apply_judge_action.rb` — applies approve/flag/disqualify/manual_override; raises `SelfApprovalError`, `DisqualifyNoteRequired`.
- `compute_flags.rb` — derives flags (`missing_gps`, `clock_skew`, `out_of_bounds`); constants for thresholds.
- `detect_lake.rb` — point-in-polygon lake lookup, swallows errors (lake is metadata).
- `drop_member_from_entry.rb` — removes a user from a tournament entry, rebalancing placements they held.
- `filter_bands.rb` — band definitions for wind direction/speed, pressure, moon phase, time-of-day; shared by server + UI.
- `flag_duplicates.rb` — flags neighbor catches by teammates inside a 90 s window as `possible_duplicate`.
- `place_in_slots.rb` — core scoring: places a catch into every applicable tournament, triggers leaderboard broadcast + notifications.
- `promote_backup.rb` — when a slot is freed, promote the largest unplaced backup catch.
- `rebalance_slots.rb` — re-derives standard top-N placements after a length/species edit.
- `reconcile_bvs_extremes.rb` — re-derives BvS biggest+smallest placements from scratch (PromoteBackup semantics are wrong for BvS).

### `Leaderboards::*`

- `build.rb` — entrypoint; dispatches to format-specific ranker.
- `broadcast_reveal.rb` — broadcasts the post-end leaderboard reveal to the `reveal` Turbo channel.
- `presentation_order.rb` — reorders rows per viewer scope so a blind tournament doesn't leak rank via row position.
- `viewer_scope.rb` — decides what a viewer sees during a blind tournament (full / own_entry_only / entries_only).
- `rankers/standard.rb` — top-N per species, sum lengths, cascading tiebreaker.
- `rankers/big_fish_season.rb` — one row per catch, longest fish ranks highest.
- `rankers/biggest_vs_smallest.rb` — score = max(length) − min(length) per entry within one species.
- `rankers/fish_train.rb` — sum of train-car lengths; cars-completed cascade.
- `rankers/hidden_length.rb` — closest-to-target after reveal; pre-reveal shows raw lengths.

### `Placements::*`

- `broadcast_leaderboard.rb` — Turbo Streams replace to full + per-entry channels (blind splits per entry).
- `detect_notifications.rb` — derives "you were bumped" / "you took the lead" payloads for push.

### `Tournaments::*`

- `active_for_user.rb` — tournaments a user is currently entered in (excludes judges).
- `angler_count.rb` — distinct user count across all entries.
- `points_scale.rb` — angler-count → `[1st, 2nd, 3rd]` point values, nil under 3 anglers.
- `roll_hidden_length_target.rb` — picks the random target on tournament end; idempotent via `with_lock`.
- `season_points_awarded.rb` — applies the scale to top-3 + attendance bonus.
- `shared_entry_at.rb` — finds the entry two users share at a given time (teammate detection).
- `teammates_for.rb` — active teammates of a user in one tournament.
- `top_three.rb` — first three ranked leaderboard rows (skipping empties).
- `winners_for.rb` — batched winner lookup for the archived-tournaments index (avoids N+1).

### `SeasonPoints::*`

- `current_season_tag.rb` — most recent season_tag among season-points tournaments in a club.
- `standings.rb` — sums points across ended season-points tournaments.
- `tournaments.rb` — list of ended season-points tournaments for a season.

### `TournamentTemplates::*`

- `clone.rb` — clones a template into a new event tournament with copied scoring slots.

## app/views/

### Layouts

- `layouts/application.html.erb` — default mobile layout (bottom nav, iOS install coach, sync toast).
- `layouts/admin.html.erb` — wider laptop admin layout.
- `layouts/mailer.html.erb` / `mailer.text.erb` — email envelopes.
- `layouts/action_text/contents/_content.html.erb` — Action Text wrapper.

### Shared / cross-controller partials

- `shared/_catch_calendar.html.erb` — month grid with per-date catch counts; powers catches index date nav.
- `shared/_ios_install_coach.html.erb` — Safari-only "Add to Home Screen" coachmark.

### `home/`

- `index.html.erb` — pending-catches widget + season-points teaser.
- `_season_points_top.html.erb` — top-of-page standings card.

### `catches/`

- `index.html.erb` / `map.html.erb` — list and Leaflet map of personal catch history.
- `new.html.erb` / `show.html.erb` — log-a-catch form (camera + offline) and detail page.
- `select_teammate.html.erb` — chooser when logging for a teammate.
- `_filter_bar.html.erb` — species/lake/sort filters with auto-submit.
- `_match_conditions.html.erb` / `_match_condition_row.html.erb` — collapsible weather/moon/time filter panel.
- `_flag_badges.html.erb` — small badges for catch flags + latest-approver chip.
- `_map_popup.html.erb` — Leaflet popup body for one catch.

### `tournaments/`

- `index.html.erb` / `archived.html.erb` / `show.html.erb` — public tournament list, completed list, detail with leaderboard.
- `_leaderboard.html.erb` — render the ranked rows (Turbo Stream target).
- `_season_filter.html.erb` — season-tag pill nav.
- `catches/show.html.erb` — turbo-frame photo modal for a placed catch.

### `judges/`

- `catches/index.html.erb` / `show.html.erb` — review queue and catch detail.
- `manual_overrides/new.html.erb` — judge edit-length/species/slot form.
- `reviews/_actions.html.erb` — approve/flag/disqualify form embedded on the judge catch page.

### `organizers/`

Mobile organizer screens for tournaments, templates, members, entries, judges. Each resource has the standard new/edit/index pages (no show; `edit.html.erb` doubles as detail with embedded sections). Notable partials:

- `tournaments/_form.html.erb` / `tournament_templates/_form.html.erb` — share the format/scoring-slot UI.
- `shared/_format_select.html.erb` — format dropdown with descriptions; locks post-start.
- `shared/_fish_train_builder.html.erb` / `_fish_train_car_row.html.erb` — train-car composer with min/max constraints.
- `tournament_entries/_section.html.erb` / `tournament_judges/_section.html.erb` / `catches/_section.html.erb` — embedded sections rendered inside `tournaments/edit`.
- `members/code.html.erb` — shows an issued 8-digit sign-in code for a member.

### `admin/`

Laptop versions of the organizer screens (same controllers list, plus `dashboards`, `rules`, `clubs/*`). Standard CRUD pages: `tournaments/{index,new,edit,_form}`, `tournament_templates/{index,new,edit,_form}`, `members/{index,new,edit,code}`. Sections under `tournament_entries/_section`, `tournament_judges/_section`, `catches/_section` mirror the organizers' versions but use admin paths.

- `dashboards/index.html.erb` — counter grid + recent-activity blocks.
- `rules/{index,new,show,history}.html.erb` — current rules per season, edit form (rich text), per-revision show, full history.
- `clubs/{index,new,edit,show,_form}.html.erb` — site-admin club CRUD.
- `clubs/catches/index.html.erb` — foreign-club catch history.
- `clubs/members/{index,new,edit,code}.html.erb` — foreign-club member management + sign-in code.
- `clubs/rules/{index,show,history}.html.erb` — read-only foreign-club rules.
- `clubs/tournaments/index.html.erb` — foreign-club tournament list (reuses `tournaments/show.html.erb` for drill-in).
- `clubs/tournament_templates/{index,show}.html.erb` — foreign-club template viewer.

### Auth / settings / misc

- `sessions/{new,check_email,code}.html.erb` — email entry, post-magic-link confirmation, 8-digit code submit.
- `notification_settings/show.html.erb` — push toggle + snooze controls.
- `pre_trip/show.html.erb` — runs the pre-trip Stimulus checks (camera/mic/GPS/notifications/network).
- `rules/show.html.erb` — public rules viewer for the current club.
- `season_points/{show,tournaments}.html.erb` — standings table and per-season tournament list.

### Mail templates

- `sign_in_mailer/magic_link.{html,text}.erb` — magic-link sign-in email.
- `invitation_mailer/welcome.{html,text}.erb` — first-time invite email.

### PWA

- `pwa/manifest.json.erb` — webmanifest template.
- `pwa/service_worker.js.erb` — service worker: cache-first for assets, network-first for everything else, `/api/*` bypassed; cache key bumped per deploy via `AppVersion.current`.

### Misc

- `active_storage/blobs/_blob.html.erb` — Action Text image embed.

## app/javascript/

- `application.js` — importmap entrypoint; loads controllers, SW register, offline sync, Turbo, Trix.
- `sw_register.js` — registers `/service-worker.js` on window load.
- `controllers/application.js` / `index.js` — Stimulus boot + eager-load all `*_controller.js`.
- `controllers/app_refresh_controller.js` — single `reload()` action for "new version available" banners.
- `controllers/auto_submit_controller.js` — submits parent form on change (filter bars).
- `controllers/catch_form_controller.js` — the log-a-catch form: photo blob, video blob, GPS, unit toggle, persists length-unit choice, enqueues to IndexedDB.
- `controllers/catch_sync_toast_controller.js` — flashes a toast on `bsfamilies:catch-synced`.
- `controllers/fish_train_builder_controller.js` — add/remove train cars within min/max bounds in the tournament form.
- `controllers/length_edit_controller.js` — live in/cm conversion on judge edit-length form; transient (does not persist preference).
- `controllers/lightbox_controller.js` — `<dialog>`-based image lightbox with backdrop close.
- `controllers/map_controller.js` — Leaflet map for catches/map.
- `controllers/match_conditions_controller.js` — opens/closes match-conditions panel and syncs `?mc=open` to URL.
- `controllers/pending_catches_controller.js` — renders pending/failed queue from IndexedDB; listens for sync events.
- `controllers/photo_capture_controller.js` — getUserMedia photo capture with fullscreen and frame guide; idle/streaming/captured state machine.
- `controllers/photo_modal_controller.js` — closes a Turbo-frame photo modal by clearing the frame body.
- `controllers/photo_save_controller.js` — Web Share API → anchor-download fallback for saving a catch photo.
- `controllers/pre_trip_controller.js` — runs the on-device permissions checks.
- `controllers/push_register_controller.js` — Notification.permission + PushManager subscribe/unsubscribe, posts to API.
- `controllers/tournament_format_controller.js` — toggles tournament form UI when format changes (forces solo for big_fish_season, hides extra slots, etc.).
- `controllers/video_capture_controller.js` — MediaRecorder with mime-type probe (iOS Safari needs mp4/h264).
- `offline/db.js` — IndexedDB wrapper (`bsfamilies` DB, single `catches` store keyed by `client_uuid`).
- `offline/sync.js` — drain loop that POSTs pending catches to `/api/catches`; reentrant guard; triggered on online/load/visibilitychange/SW message/manual.

## app/jobs/

- `application_job.rb` — ActiveJob base.
- `deliver_push_notification_job.rb` — sends one push payload per subscription, skipping muted ones.
- `fetch_catch_conditions_job.rb` — Open-Meteo lookup for wind/pressure/temp + moon-phase calc; retries 3x.
- `tournament_lifecycle_announce_job.rb` — fires "started"/"ended" actions (rolls hidden_length target, reveal broadcast, push); idempotent via `lifecycle_*_announced_at` stamps.

## app/mailers/

- `application_mailer.rb` — `from:` default.
- `sign_in_mailer.rb` — magic-link email.
- `invitation_mailer.rb` — new-member welcome email.

## app/helpers/

- `application_helper.rb` — `tournament_window` formatter and friends.
- `catches_helper.rb` — `thumb` Active Storage variant + `can_view_catch?` / flag visibility predicates.
- `conditions_helper.rb` — dual C/F temp and km/h-mph wind formatters.
- `length_helper.rb` — dual in/cm length formatters.

## app/lib/

- `geofence.rb` — point-in-polygon over named region GeoJSON files (`lake`, `sask`).
- `geofence/lakes.rb` — registry of named lakes with key normalization and best-match lookup.

## app/assets/

- `assets/tailwind/application.css` — Tailwind v4 entrypoint with theme config.
- `assets/stylesheets/application.css` / `actiontext.css` — propshaft-served stylesheets (mostly Tailwind output + Action Text defaults).
- `assets/builds/tailwind.css` — generated Tailwind build (committed).

---

## test/

- `test_helper.rb` — parallel test config; loads fixtures, FactoryBot, custom helpers.
- `application_system_test_case.rb` — Cuprite + Chromium driver setup (`--use-fake-device-for-media-stream`).
- `factories.rb` — FactoryBot factories for User, Club, Tournament, Catch, etc.
- `fixtures/files/sample_walleye.jpg` — fixture photo used by catch tests.
- `fixtures/action_text/rich_texts.yml` — empty rich-text fixture.

### `test/models/`

One file per model — `*_test.rb` covers validations, scopes, and enum predicates for its target. No surprises.

### `test/controllers/`

Mirror `app/controllers/` 1:1 except for `catches_controller_judge_test.rb` (focused on the judge-side gating in the public `CatchesController#show`). Each test exercises auth, redirect targets, and rendered selectors.

### `test/services/`

One test per service. `place_in_slots_geofence_test.rb` is the second file for `PlaceInSlots` covering geofence interaction. The `leaderboards/rankers/*_test.rb` files lock in the tiebreaker cascade for each format.

### `test/jobs/`

- `deliver_push_notification_job_test.rb` — mocks WebPush; verifies muting/skip behavior.
- `fetch_catch_conditions_job_test.rb` — stubs Open-Meteo HTTP; verifies moon-phase math.
- `tournament_lifecycle_announce_job_test.rb` — verifies idempotence stamps + reveal broadcast.

### `test/mailers/`

- `sign_in_mailer_test.rb` — magic-link email rendering.

### `test/helpers/`

- `application_helper_test.rb` / `catches_helper_test.rb` / `conditions_helper_test.rb` — formatters and view predicates.

### `test/lib/`

- `geofence_test.rb` / `geofence/lakes_test.rb` — polygon math + lake registry.

### `test/integration/`

- `ios_install_coach_test.rb` — UA sniffing: Safari iPhone/iPad sees the coachmark; Android/desktop don't.
- `security_headers_test.rb` — CSP / `frame-ancestors 'none'` and friends.
- `service_worker_test.rb` — verifies SW response is served with a per-deploy cache key bump.

### `test/system/` (Cuprite end-to-end)

- `smoke_test.rb` — root URL returns 200.
- `sign_in_test.rb` — magic-link sign-in flow.
- `pwa_install_test.rb` / `sw_registration_test.rb` — manifest link + SW registration on first visit.
- `bottom_nav_test.rb` — bottom-nav highlights and link targets.
- `log_catch_test.rb` — fill-in-the-form happy path with fake camera/GPS.
- `catch_form_over_length_test.rb` — submit a length above the species cap; expects validation error.
- `catches_filtering_test.rb` — exercises filter bar (species/lake/date/sort) and URL round-trip.
- `lake_filter_test.rb` — geofence-based lake assignment + filter chip behavior.
- `tournament_catch_photo_test.rb` — photo modal opens/closes on non-blind tournaments.
- `judge_workflow_test.rb` — approve/flag/DQ flow from the judge UI.
- `edit_species_test.rb` — judge changes species via the catch detail page.
- `blind_leaderboard_test.rb` — blind tournament hides fish and reveals on end.
- `big_fish_season_tournament_test.rb` / `biggest_vs_smallest_tournament_test.rb` / `fish_train_tournament_test.rb` / `hidden_length_tournament_test.rb` — format-specific leaderboard rendering.
- `season_filter_test.rb` / `season_points_test.rb` — season tag pills + standings.
- `pre_trip_test.rb` / `pre_trip_retest_test.rb` — pre-trip Stimulus checklist runs and re-runs.
- `offline_sync_test.rb` — IndexedDB drain triggers (visibilitychange, manual retry); regression test for the 2026-05-13 stuck-pending incident.
- `club_rules_test.rb` — organizer publishes rules; members see them.
- `admin_foreign_club_drill_in_test.rb` — site admin drills into a foreign club from `/admin/clubs`.
- `merch_button_test.rb` — gated merch link respects `MERCH_URL` env var.
