# Jigoleberks Tournament PWA

A small, self-hosted Progressive Web App for running club-scale catch-photo-release fishing tournaments. Members log catches from their phone (in-app camera, no gallery uploads), the app queues offline and syncs when the network returns, and a live leaderboard re-renders for everyone watching when a fish lands.

## Highlights

- **Installable PWA** — manifest + service worker; iOS and Android home-screen install
- **Offline catch capture** — IndexedDB queue + Background Sync; works with zero bars
- **In-app camera** — anti-cheat: photo and (optional) release video must come from `getUserMedia`, no gallery import
- **Live leaderboard** — Turbo Streams over Action Cable; updates every viewer when placement changes
- **Judged or friendly tournaments** — judged events run through review/approve/DQ; friendly events skip judging and let placements settle from member submissions
- **Organizer flow** — tournament CRUD, scoring slots per species, templates, season tags, entries (members can't self-sign-up; organizers control who's in), judge assignment, full catch history with photos
- **Laptop admin UI** — `/admin` (or `admin.<your-domain>` via a second tunnel route) for managing tournaments, members, and judges and reviewing catch photos at full screen; same data as the PWA, different presentation
- **Judge workflow** — needs-review queue, approve / flag / disqualify / dock-verify, manual override (length + slot), append-only `JudgeAction` audit log
- **Web Push** — VAPID; bumped-from-slot, took-the-lead, judge-flagged, tournament started/ended; per-user mute / snooze / per-tournament mute
- **Per-user units** — inches or centimeters; leaderboard shows both
- **Completed-tournaments archive** — anything ended within the last 24h stays on the home page; older completions move to a dedicated archive page
- **Configurable time zone** — set `APP_TIME_ZONE` to any Rails time zone name; defaults to UTC

## Tech stack

Ruby 3.3, Rails 8, Postgres 16, Hotwire (Turbo + Stimulus), Active Storage on local disk, Solid Queue, Action Cable, the `web-push` gem, Tailwind v4, Cuprite + Chromium for system tests. Docker Compose for local + production-style deployment. Cloudflare Tunnel for public HTTPS without home-network port forwarding.

## Architecture

```
[ phone PWA ] --HTTPS--> [ Cloudflare tunnel ] --> [ Linux VM ]
                                                       |
                                                       +-- rails 8 (puma + solid queue + action cable)
                                                       +-- postgres 16
                                                       +-- /srv/tournament/storage (active storage media)
```

---

## Installing on a fresh machine

These steps assume Linux (tested on Debian/Ubuntu); macOS works the same with Homebrew. The whole app runs in Docker — you don't need Ruby or Postgres on the host.

### 1. Prerequisites

- Docker + Docker Compose v2 (`docker compose ...`)
- Git

That's it — no Ruby, Postgres, or image tooling on the host. To rebrand the favicon and PWA icon, drop a square image in at `public/icon.jpg` (browsers and Android scale it; 512×512 looks best for the home-screen install).

### 2. Clone

```bash
git clone <repo-url> tournament
cd tournament
```

### 3. Configure your environment

Copy the example env file and edit values you actually care about:

```bash
cp .env.example .env
```

Every variable has a sensible default, so the app boots without `.env` — but you'll want to set `APP_NAME`, `APP_HOST`, `APP_TIME_ZONE`, `MAIL_FROM`, and the VAPID/Resend keys before going public.

### 4. Generate VAPID keys for Web Push

The Web Push gem needs a public/private keypair to sign push messages:

```bash
docker compose run --rm web bin/rails runner '
  require "web_push"
  k = WebPush.generate_key
  puts "public:  #{k.public_key}"
  puts "private: #{k.private_key}"
'
```

Paste the values into `.env` as `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY`, and set `VAPID_SUBJECT` to a `mailto:` address you control. The committed `config/vapid.yml` reads these env vars via ERB — no copy step needed.

### 5. Resend SMTP for magic-link sign-in (optional)

If you want real magic links delivered to phones:

1. Verify a sending domain in [Resend](https://resend.com/) (e.g. a subdomain like `mail.yourdomain.com`).
2. Set `MAIL_FROM` in `.env` to use that domain — e.g. `MAIL_FROM=Tournament <noreply@mail.yourdomain.com>`.
3. Set `RESEND_API_KEY=re_xxxxxxxxxxxxxxxx` in `.env`.

If `RESEND_API_KEY` is unset, the app skips outbound mail entirely. You can still sign in by grabbing tokens from the console:

```bash
docker compose exec web bin/rails runner '
  u = User.find_by!(email: "you@example.com")
  t = SignInToken.issue!(user: u)
  puts "https://#{ENV.fetch(\"APP_HOST\", \"localhost\")}/session/consume?token=#{t.token}"
'
```

### 6. Public hostname / Cloudflare Tunnel (only for real-phone access)

The PWA's camera (`getUserMedia`) requires HTTPS, and a real phone won't trust your laptop's IP. The simplest path is a Cloudflare Tunnel pointing at the host running Docker. Set `APP_HOST` in `.env` to your tunnel hostname:

```
APP_HOST=tournament.example.com
```

The app reads it in `config/environments/development.rb` for host authorization, mailer URLs, and ActiveStorage redirects.

**Optional: a dedicated admin subdomain.** The `/admin` laptop UI also responds on `admin.<APP_HOST>` if you add a second tunnel ingress rule pointing at the same `localhost:3000`. The bare-domain `/admin` path always works; the subdomain is just a convenience so the laptop URL bar reads cleanly. Rails' host allowlist already accepts `admin.<APP_HOST>` whenever `APP_HOST` is set, and the session cookie is scoped broadly so signing in on one host carries over to the other.

### 7. Bring up the stack

```bash
docker compose up --build
```

Three things happen:
1. The web container builds (installs gems including `web-push`).
2. On startup, the web service runs `bin/rails tailwindcss:build` then starts Puma.
3. The Postgres container starts and exposes 5432 to the host.

### 8. Create the database

In another terminal (or after stopping `up` and using `run`):

```bash
docker compose run --rm web bin/rails db:create
docker compose run --rm web bin/rails db:migrate
docker compose run --rm web bin/rails db:seed
```

`db:seed` creates a sample club ("Example Fishing Club" by default — override with `SEED_CLUB_NAME` in `.env`), three species (Walleye, Perch, Pike), four sample users (one organizer + three members), and two sample tournaments.

### 9. Sign in for the first time

Visit the app and submit your real email through the sign-in form. If your email matches a seeded user *and* you've configured Resend, the magic link arrives in your inbox. Otherwise, either add yourself first:

```bash
docker compose exec web bin/rails runner 'User.create!(club: Club.first, name: "Your Name", email: "you@example.com", role: :organizer)'
```

…or skip mail entirely and grab a token from the console (see step 5).

### 10. Optional: clean out the seeded sample users

Once you have your own organizer:

```bash
docker compose exec web bin/rails runner 'User.where(email: %w[member1@example.com member2@example.com member3@example.com]).destroy_all'
```

---

## Day-to-day commands

```bash
# Start everything (after env vars are set)
docker compose up

# Run migrations after pulling new code
docker compose run --rm web bin/rails db:migrate

# Open a Rails console
docker compose exec web bin/rails console

# Tail logs
docker compose logs -f web

# Run the test suite
docker compose run --rm web bin/rails test
docker compose run --rm web bin/rails test:system
```

## Updating an existing install

The repo ships a `bin/update` script that does it all in one shot — pull, rebuild image if needed, run pending migrations, recreate containers, then tail logs:

```bash
./bin/update
```

It handles the common gotchas (stale `tmp/pids/server.pid` boot loop, auto-stashing the regenerated `app/assets/builds/tailwind.css` so `git pull` doesn't refuse). Press Ctrl-C to stop tailing once you've seen Puma listening.

Manual equivalent if you'd rather run the steps individually:

```bash
git pull --ff-only --autostash
rm -f tmp/pids/server.pid
docker compose build web      # no-op unless Dockerfile/Gemfile changed
docker compose run --rm web bin/rails db:migrate
docker compose up -d
```

## Maintenance (optional)

A `storage:cleanup_orphans` rake task removes files in `storage/` that no longer have a matching `active_storage_blobs` row — useful after a DB wipe, restore from backup, or any case where blob metadata gets out of sync with disk. Idempotent; safe to run any time.

```bash
docker compose run --rm web bin/rails storage:cleanup_orphans
```

A `catches:warm_photo_variants` task pre-generates the resized thumbnail variants (200/400/1200 px) for every existing catch photo. Variants are also generated lazily on first request, so this is only useful as a one-shot after first enabling the variant code or after restoring a backup, to avoid users paying the per-photo first-load cost. Idempotent; already-generated variants are reused.

```bash
docker compose exec web bin/rails catches:warm_photo_variants
```

To run it monthly via cron (replace `/path/to/tournament` with the absolute path to your checkout):

```cron
0 4 1 * * cd /path/to/tournament && docker compose run --rm web bin/rails storage:cleanup_orphans >> log/cleanup.log 2>&1
```

Install with `crontab -e` as the user that runs docker — typically not root. `log/cleanup.log` is gitignored.

## Notes

- **Time zone** is read from `APP_TIME_ZONE` (defaults to `UTC`). Use any Rails time zone name — e.g. `Saskatchewan` (UTC-6, no DST), `Eastern Time (US & Canada)`, etc.
- **Per-tournament release-video toggle** — organizers can disable the release-video step on a tournament. The catch form hides that section if none of the angler's active tournaments require it. New tournaments default to "video off"; flip it on per tournament when the rules call for it.
- **Judged vs friendly mode** — friendly tournaments skip the judge queue entirely; member submissions place straight onto the leaderboard. Judged tournaments require approval and support flag/DQ/manual override.
- **Member self-sign-up is disabled by design.** Organizers add members to tournaments via the tournament edit page.
- **Catch detail privacy** — the `/catches/:id` photo+meta page is gated to organizers and judges of the relevant tournament. Members see lengths on the leaderboard but not the underlying photos.
- **Completed tournaments** appear on the home page for 24h after `ends_at`, then move to `/tournaments/archived`, reachable from the "View older completed tournaments" button on the home page.

## License

[MIT](LICENSE).
