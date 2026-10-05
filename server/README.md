# Copy Server (Phase 1, in progress)

Standalone copy core described in [`docs/design/0001-copy-core.md`](../docs/design/0001-copy-core.md)
(issue #77). FastAPI + SQLAlchemy 2 (sync) + Alembic, Python 3.12, SQLite (WAL) by default,
Postgres optional.

PR 1 was the skeleton: the complete data model (design 5.1), enrollment, per-account tokens and
two-step rotation (D8), the minimal admin API, `GET /v4/config` and `/health`.
PR 2 adds server-issued sessions (C4), symbol specs, master snapshots with fan-out of **new**
positions (lots, symbol maps, filters, netting admission), command delivery with the
`in_progress` lease, and the admin API for groups/links/maps.
PR 3 adds command results (copy state separate from command status, one result per
`(command_id, attempt_id)`, new attempts for rejected close/cancel), the slave snapshot with the
same session/seq fencing as the master, reconciliation (slave-side closes, `position_not_found`),
adoption by comment `c<copy_id>` + magic, duplicate siblings, `symbol_conflicts`, and promotion of
the blocked netting successor.
PR 4 adds master close detection (fast path by history exit deal, guarded absence path with the
mass-disappearance guard, epoch-aware timers), the 5.5 "master closed" transitions, proportional
partial reductions (`reduction_target`, coalesced, one financial mutation in flight per position),
netting reversal as close-then-open by generation, `processed_deals` dedup, and SL/TP `modify`.
The admin UI (including the 5.8 resolve actions) comes in a later PR.

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
| `COMMAND_LEASE_SECONDS` | `120` | lease of an `in_progress` receipt ack (4.5) |
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
| `POST /v4/session` | token | `{boot_nonce, taken_at, ea_clock_offset_ms}` → `201 {session_id, epoch}`; retires the previous session |
| `PUT /v4/symbols` | token | `{symbols:[{name, volume_min/step/max, contract_size, digits, point, tick_size, trade_mode, filling_modes, stops_level, freeze_level}]}` → `204` |
| `POST /v4/master/snapshot` | master | `200 {accepted, seq}`; `409 account_mismatch` / `stale_session`; new positions fanned out; reductions, reversal, SL/TP and closes (rules below) |
| `GET /v4/slave/commands?after=` | slave | un-acked commands (cursor is a hint); never-sent `open` past TTL expires |
| `POST /v4/slave/results` | slave | `{results:[{command_id, attempt_id, copy_id, status, order, deal, position_ticket, position_id, volume, executed_volume, residual_volume, price, sl, tp, profit, commission, swap, error_code, message}]}` → `200 {unknown, applied, duplicates}`; status `in_progress\|done\|done_partial\|closed\|failed\|expired\|not_executed\|uncertain\|skipped\|notmodify`; unknown status → 422 |
| `POST /v4/slave/snapshot` | slave | same body/fencing as the master snapshot; reconciliation + adoption; renews `in_progress` leases |
| `POST/GET/PATCH /admin/groups` | admin | `{master_id, name, enabled, magic_allow, symbol_filter}` |
| `POST/GET/PATCH /admin/links` | admin | lot/magic/guard params; 422 `config_conflict` on hedging→netting, cycles, netting filter overlap, contract size |
| `POST/GET/PATCH/DELETE /admin/symbol_maps` | admin | per-slave or global (`slave_id: null`); duplicate → `409 map_conflict` |
| `GET /admin/copies`, `GET /admin/commands` | readonly | debugging listings |

Mutating `/v4/*` calls require `Idempotency-Key`.

## Tests

```bash
cd server
uv run ruff check .
uv run pytest
# same suite on Postgres (throwaway database):
createdb copycore_test && COPYCORE_TEST_DATABASE_URL=postgresql:///copycore_test uv run pytest; dropdb copycore_test
```

Tests reference the design's scenario ids (S01, S04-S22, S25-S35, S37, S38, S40, S41, S43-S46,
S49-S53) where they cover one.

### Master snapshot rules (PR 4)

Per `position_id`, one interpretation, in this order (5.4, C1). Closes are applied before new
positions of the same snapshot, so a close-then-reopen on a netting slave blocks behind the close.

| Master event | Effect |
|---|---|
| present, same side, lower volume | per copy `reduction_target = floor_step(opened × new / master volume at issue)`; `close_partial` of `confirmed − target` only when no open/close/close_partial/cancel is in flight; deltas below `volume_min` wait; target below `volume_min` → full `close`; `done_partial` → rest as a new attempt |
| present, side changed or unprocessed `inout` | generation g `closed` (`reversal`), copies follow "master closed"; generation g+1 fanned out `pending_blocked` behind each link's previous copy (netting and hedging slaves) |
| present, higher volume | `copy.volume_drift` only (netting, Phase 1) |
| present, SL/TP changed | `modify` (supersedes queued modifies); undelivered open / blocked copy → SL/TP in the open payload |
| absent + `out`/`out_by` deal after the generation start | fast close (`history`) |
| absent, no exit deal | absence: `CLOSE_ABSENT_SNAPSHOTS` snapshots **and** `CLOSE_ABSENT_SECONDS` on the server monotonic clock in the current epoch; only `connected` + `history_synced` snapshots count; mass disappearance → alert, `send_history=true`, `MASS_DISAPPEAR_SECONDS`; reappearance resets |
| closed id reappears | not re-copied; `master_position.reappeared` alert once |

"Master closed" per copy state (5.5): `open` → `closing` + `close`; `pending` with the open never
delivered → `cancelled`; delivered → `cancel_requested` + `cancel`; `pending_blocked` → `cancelled`;
`uncertain` → `close_intent` (adoption/resolution decides). Deals are recorded once in
`processed_deals` with the generation they affected.

Deviation: a superseded `modify` that was already delivered is not tombstoned (4.5); only queued
modifies are superseded, delivered ones run first in `seq_in_copy` order so the latest SL/TP ends last.

### Result rules (PR 3)

| Action | Result | Copy |
|---|---|---|
| open | `done` (with `position_id`) | `open`; `closing` + `close` if the master already closed / cancel was requested; late fill on `cancelled`/`error` reopens it (exposure wins) or opens a `symbol_conflicts` row when the slot was re-taken |
| open | `failed` | `error` (`price_out_of_range` → `skipped`; `drain` → `cancelled`); `expired`/`not_executed` → `cancelled` |
| any | `uncertain` | `uncertain` (per copy, command not re-delivered until a new session); a later conclusive result of the same attempt resolves it |
| close / cancel / close_partial | `failed` (definitive) | same command, new `attempt_id` after backoff (5 s doubling, max 300 s); state and reservation kept |
| close | `done_partial` | `confirmed_volume` = residual, stays `closing`, remainder as a new attempt |
| close | `failed: position_not_found` | waits for slave history; 3 snapshots without an exit deal → `copy.close_unconfirmed` (stays `closing`, reservation kept) |
| cancel | `not_executed` / `closed` | `cancelled` / `closed` |
| modify | `done` / `notmodify` / `failed` | audit only; 2 NOTMODIFY per day → `no_sltp` |
CI: `.github/workflows/server.yml` (SQLite and Postgres).
