# Copy Server (Phase 1, in progress)

Standalone copy core described in [`docs/design/0001-copy-core.md`](../docs/design/0001-copy-core.md)
(issue #77). FastAPI + SQLAlchemy 2 (sync) + Alembic, Python 3.12, SQLite (WAL) by default,
Postgres optional.

This first PR is the skeleton: the complete data model (design 5.1), enrollment, per-account
tokens and two-step rotation (D8), the minimal admin API, `GET /v4/config` and `/health`.
Snapshots, fan-out, commands and results come in later PRs.

## Run locally

```bash
cd server
uv sync                                   # Python 3.12 venv in server/.venv
export ENV=development DATABASE_URL=sqlite:///./copy.db
uv run alembic upgrade head
uv run uvicorn copycore.app:create_app --factory --reload
```

`ENV=development` (or `test`) supplies throwaway `TOKEN_PEPPER`/`ADMIN_TOKEN` (`dev-admin-token`).
Any other `ENV` (default `production`) refuses to start without both.

## Docker

```bash
docker build -t copy-server server/
docker run -p 8000:8000 -v copy-data:/data \
  -e TOKEN_PEPPER=$(openssl rand -hex 32) -e ADMIN_TOKEN=$(openssl rand -hex 32) copy-server
```

The container runs `alembic upgrade head` and then uvicorn (one worker) as a non-root user;
the database lives at `/data/copy.db`. Healthcheck: `GET /healthz` (alias `/health`).

## Configuration (env only, design D7)

| Var | Default | Notes |
|---|---|---|
| `ENV` | `production` | `development`/`dev`/`test` allow dev secrets |
| `DATABASE_URL` | `sqlite:////data/copy.db` | `postgresql://...` switches to Postgres (psycopg 3) |
| `TOKEN_PEPPER` (alias `TOKEN_HMAC_KEY`) | required | HMAC key; tokens and enrollment codes are stored only as HMAC-SHA256 |
| `ADMIN_TOKEN` | required | bearer for `/admin/*` |
| `CLOSE_ABSENT_SNAPSHOTS`, `CLOSE_ABSENT_SECONDS` | `3`, `60` | seconds below 60 are rejected at startup |
| `MASS_DISAPPEAR_MIN`, `MASS_DISAPPEAR_SECONDS` | `3`, `300` | |
| `OPEN_TTL_SECONDS`, `MASTER_STALE_SECONDS` | `30`, `120` | |
| `RAW_SNAPSHOT_RETENTION_H`, `EVENT_RETENTION_D`, `LOG_RETENTION_D` | `48`, `30`, `7` | |
| `RAW_DAILY_QUOTA_MB`, `LOG_DAILY_QUOTA_MB` | `50`, `20` | |
| `WEBHOOK_URL`, `WEBHOOK_SECRET` | unset | |
| `ENROLL_CODE_TTL_SECONDS`, `PENDING_TOKEN_TTL_HOURS`, `IDEMPOTENCY_TTL_HOURS` | `900`, `24`, `24` | |
| `MIN_EA_VERSION`, `POLL_MS` | unset, `2000` | returned by `/v4/config` |
| `RATE_LIMIT_ENABLED` | `false` | placeholder; limits (6.4) arrive in a later PR |
| `WEB_CONCURRENCY` | `1` | must be 1 on SQLite |

## API so far

| Route | Auth | Notes |
|---|---|---|
| `GET /health`, `/healthz` | none | |
| `POST /admin/accounts` | admin | `{broker_server, login, role, label?}` |
| `GET /admin/accounts/{id}` | admin | |
| `POST /admin/accounts/{id}/enroll_codes` | admin | one-time code, 15 min, bound to (server, login, role) |
| `POST /admin/accounts/{id}/revoke` | admin | 401 on every EA call afterwards |
| `PATCH /admin/accounts/{id}` | admin | `{status: active|suspended}`: suspension = drain (403 only without open copies) |
| `POST /v4/enroll` | code | `201 {token, account_id}`, never cached |
| `POST /v4/token/rotate[?restart=true]` | token | `{new_token, pending_id}`; replay while pending → `409 rotation_pending` |
| `POST /v4/token/confirm` | **new** token | `{pending_id}` → `204`, revokes the old token |
| `GET /v4/config` | token | `{mode, message, poll_ms, debug, send_history, symbols_wanted, min_ea_version}` |

Mutating `/v4/*` calls require `Idempotency-Key`.

## Tests

```bash
cd server
uv run ruff check .
uv run pytest
# same suite on Postgres (throwaway database):
createdb copycore_test && COPYCORE_TEST_DATABASE_URL=postgresql:///copycore_test uv run pytest; dropdb copycore_test
```

Tests reference the design's scenario ids (S14, S22, S25, S26, S34) where they cover one.
CI: `.github/workflows/server.yml` (SQLite and Postgres).
