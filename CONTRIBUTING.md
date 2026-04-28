# Contributing

Thanks for picking this up. The app is small enough that one person can hold the whole picture in their head — keep it that way.

## Local setup

See [README.md](README.md). Short version:

```bash
cp .env.example .env          # edit values you actually need
docker compose up --build
docker compose run --rm web bin/rails db:create db:migrate db:seed
```

## Running tests

```bash
docker compose run --rm web bin/rails test
docker compose run --rm web bin/rails test:system
```

System tests use Cuprite + Chromium; the camera path uses `--use-fake-device-for-media-stream`.

## Branches and PRs

- Branch off `main`. Name the branch by the change, not the author (e.g. `judge-flag-button`, `pwa-icon-mask`).
- One PR per logical change. Don't bundle a refactor and a feature.
- The PR description should explain *why*, not just *what*. The diff already shows the what.
- Run the full test suite locally before opening the PR. CI is a backstop, not a substitute.
- Squash-merge unless the branch is genuinely a series of standalone commits.

## Style

- Match what's already in the codebase — Ruby/Rails idioms, no extra abstractions.
- Tailwind utility classes inline; no CSS files unless you have a reason.
- Keep ERB readable. If a view is doing too much, lift to a helper.
- Tests for new behavior, period. Test names describe behavior, not implementation.

## Reporting bugs

Open a GitHub issue with: what you did, what happened, what you expected. A failing test or repro script earns extra love.
