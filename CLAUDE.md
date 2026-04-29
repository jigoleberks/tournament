# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Jigoleberks Tournament PWA — a self-hosted Progressive Web App for club-scale catch-photo-release fishing tournaments. Members log catches from their phone (in-app camera, offline-capable), and a live leaderboard re-renders via Turbo Streams over Action Cable.

Ruby 3.3.6, Rails 8.0, PostgreSQL 16, Hotwire (Turbo + Stimulus), Solid Queue/Cache/Cable, Tailwind CSS v4, Importmap for JS.

## Commands

All development commands run through Docker Compose:

```bash
# Start the app
docker compose up

# Run a one-off Rails command
docker compose run --rm web bin/rails <command>

# Database setup
docker compose run --rm web bin/rails db:create db:migrate db:seed

# Run the full test suite
docker compose run --rm web bin/rails test
docker compose run --rm web bin/rails test:system

# Run a single test
docker compose run --rm web bin/rails test test/models/user_test.rb
docker compose run --rm web bin/rails test test/models/user_test.rb:42

# Rails console
docker compose exec web bin/rails console
```

## Authentication

Custom-built (no Devise). Magic-link sign-in via `SignInToken` (email-delivered or console-fetched). Also supports 8-digit codes with attempt tracking. Session stores `user_id`. Roles are `member` (0) or `organizer` (1) on the `User` model.

`Authentication` concern (`app/controllers/concerns/authentication.rb`) provides `current_user`, `signed_in?`, `require_sign_in!`, `sign_in!`, `sign_out!`.

Three base controller patterns enforce access:
- `Organizers::BaseController` — requires organizer role
- `Judges::BaseController` — requires judge assignment for a specific tournament
- `Api::BaseController` — requires sign-in, returns 401 (not redirect)

## Routing

Three namespaced areas plus public routes:
- `/organizers/*` — tournament CRUD, member management, judge assignment, catch history, templates
- `/judges/tournaments/:tournament_id/*` — catch review (approve/flag/DQ/manual override)
- `/api/*` — offline catch submission, push subscription management
- Public: catches logging, tournament leaderboards, sign-in flow

## Domain Models

Single-tenant: one `Club` per deployment. All users, species, and tournaments are club-scoped.

Core models: `User`, `Catch`, `Tournament`, `ScoringSlot`, `TournamentEntry`, `CatchPlacement`, `JudgeAction`, `Species`, `PushSubscription`, `SignInToken`, `TournamentTemplate`.

Key patterns:
- Soft deletes via `deactivated_at` on User, `active: false` on CatchPlacement
- Append-only audit log for judge actions (`JudgeAction` with `before_state`/`after_state` JSONB)
- Catches have `client_uuid` for offline deduplication

## Services

Business logic lives in `app/services/` using the `Module::Class` pattern with a `self.call` class method interface:

- `Catches::PlaceInSlots` — Core scoring: places a catch into tournament scoring slots, broadcasts leaderboard, triggers push notifications
- `Leaderboards::Build` — Builds ranked leaderboard by summing active placement lengths per entry
- `Placements::BroadcastLeaderboard` — Turbo Stream replace to the tournament channel
- `Placements::DetectNotifications` — Detects bumped-from-slot and took-the-lead events
- `Tournaments::ActiveForUser` — Finds active tournaments a user is entered in
- `Catches::ApplyJudgeAction` — Applies judge actions (approve/flag/DQ) to catches
- `TournamentTemplates::Clone` — Clones a template into a new tournament

## JavaScript / PWA

Stimulus controllers in `app/javascript/controllers/`. Offline support via IndexedDB (`offline/db.js`) and Background Sync (`offline/sync.js`). Service worker registration in `sw_register.js`.

## Tests

Minitest with parallel execution, FactoryBot for factories, and `fixtures :all`. System tests use Cuprite + Chromium (with `--use-fake-device-for-media-stream` for camera tests).

Test directories: `test/models/`, `test/controllers/` (including api/judges/organizers namespaces), `test/services/`, `test/jobs/`, `test/mailers/`, `test/system/`.

## Conventions

- Service objects for non-trivial business logic (`Module::Class` with `self.call`)
- Tailwind utility classes inline in ERB views — no separate CSS files
- Enums stored as integers
- No member self-signup; organizers add members
- Catch photo detail pages gated to organizers/judges only
- Branch off `main`, name branches by change not author, squash-merge by default
