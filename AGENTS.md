# Repository Guidelines

## Project Structure & Module Organization
`dashboard/` contains the Next.js 14 App Router UI, with pages in `dashboard/app/`, API routes in `dashboard/app/api/`, and shared UI in `dashboard/app/components/`. `terminal/` contains the Node WebSocket bridge in `terminal/server.js`. Database bootstrap and schema changes live in `supabase/migrations/` and use numeric prefixes such as `001_initial_schema.sql`. Operational scripts live in `scripts/`, configuration lives in `config/`, and infrastructure is defined in `docker-compose.yml`, `Caddyfile`, and `bootstrap.sh`.

## Build, Test, and Development Commands
- `bash ./bootstrap.sh`: run the installer from the local checkout.
- `docker compose up --build`: start the full stack locally.
- `cd dashboard && npm install && npm run dev`: run the dashboard in dev mode.
- `cd dashboard && npm run build`: verify the Next.js production build.
- `cd terminal && npm install && npm start`: run the terminal WebSocket server on port `3002`.
- `bash scripts/status.sh`: inspect service and cron health on an installed system.

## Coding Style & Naming Conventions
Follow the existing style in the repo: 2-space indentation, single quotes, and no semicolons in JavaScript. Keep React components in PascalCase files such as `SecretsTab.js`; keep route handlers in `route.js` under the App Router tree. Name shell scripts in kebab-case (`server-health.sh`), and keep SQL migrations ordered with zero-padded numeric prefixes. Prefer small, focused modules over new shared abstractions unless multiple files already need the same behavior.

## Testing Guidelines
There is no committed automated test suite yet. For dashboard changes, run `cd dashboard && npm run build` and manually exercise the affected page or API route. For terminal or infrastructure changes, validate with `docker compose up --build` and a relevant maintenance script such as `bash scripts/status.sh`. Document the manual checks you performed in the PR.

## Commit & Pull Request Guidelines
Recent commits use short, imperative subjects like `Improve watchdog, env safety, and status checks`. Keep subjects concise, capitalized, and focused on one change. PRs should explain the problem, the fix, any config or migration impact, and the validation steps you ran. Include screenshots for dashboard UI changes and call out changes to `.env`, secrets flow, cron behavior, or exposed ports.

## Security & Configuration Notes
Do not commit real secrets from `.env`, `terminal-ssh-key`, or Telegram/Claude setup. Treat changes to auth, JWT handling, Caddy routes, and `scripts/security-sync.sh` as high risk, and verify them against the install mode you changed (`AGENTOS_ADD_DOMAIN=true` or `false`).
