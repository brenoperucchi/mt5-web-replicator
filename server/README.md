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
adoption by the `c<copy_id>` part of the comment `c<copy_id>-<master position_id>` + magic, duplicate siblings, `symbol_conflicts`, and promotion of
the blocked netting successor.
PR 4 adds master close detection (fast path by history exit deal, guarded absence path with the
mass-disappearance guard, epoch-aware timers), the 5.5 "master closed" transitions, proportional
partial reductions (`reduction_target`, coalesced, one financial mutation in flight per position),
netting reversal as close-then-open by generation, `processed_deals` dedup, and SL/TP `modify`.
PR 5 adds the operator side: the 5.8 resolution actions with the `resolve` command to the EA journal,
symbol-conflict resolution, the C6 drain transitions on account suspension and link/group disable,
events/alerts/EA-log/orphan listings, scoped admin and service tokens, and a minimal server-rendered
admin UI at `/ui` (Q9).

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
| `MIN_EA_VERSION`, `POLL_MS` | unset, `2000` | returned by `/v4/config`; `POLL_MS` must be >= 500 (the EA clamps too) |
| `LAST_SEEN_WRITE_SECONDS` | `30` | `last_seen_at` is written at most this often per account, so idle polls stay read-only |
| `ACCESS_TRACE_PATH` | unset | opt-in file with one line per `/v4` call (`start_ms account_id method path status ms`; no tokens), for latency and load tests |
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
| `GET /admin/accounts?role=&status=` | readonly | account listing |
| `POST /admin/copies/{id}/resolve` | admin | `{executed: position_id}` \| `{not_executed: true}` \| `{resolution: closed\|retry_close}`; optional `volume`, `price`, `note` |
| `POST /admin/symbol_conflicts/{id}/resolve` | admin | `{resolution: accept\|close, note?}` |
| `GET /admin/symbol_conflicts?open=&slave_id=` | readonly | |
| `GET /admin/events?type=&prefix=&alerts=&copy_id=&account_id=&before_id=&limit=` | readonly | newest first; `next_before_id` pages back |
| `GET /admin/alerts?account_id=&before_id=` | readonly | operator alert types only |
| `GET /admin/logs?account_id=&before_id=` | readonly | EA log uploads (`ea_logs`) |
| `GET /admin/orphans` | readonly | uncertain, close_unconfirmed, exposure on revoked slaves, open conflicts |
| `POST/GET /admin/api_tokens`, `POST /admin/api_tokens/{id}/revoke` | admin | scoped bearer (`admin`/`readonly`); the token is returned once and stored as HMAC |
| `GET /ui/` | cookie | server-rendered admin (see below) |

Mutating `/v4/*` calls require `Idempotency-Key`.

## Tests

```bash
cd server
uv run ruff check .
uv run pytest
# same suite on Postgres (throwaway database):
createdb copycore_test && COPYCORE_TEST_DATABASE_URL=postgresql:///copycore_test uv run pytest; dropdb copycore_test
```

Tests reference the design's scenario ids (S01, S04-S22, S25-S35, S37-S47, S49-S53) where they
cover one.

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

## Admin operations (PR 5)

### Admin UI

`/ui` is a minimal server-rendered admin (no SPA, no JavaScript). Sign in at `/ui/login` with
`ADMIN_TOKEN` or an `api_tokens` bearer. The cookie stores only a signed reference and expiry
(8 h, HttpOnly, SameSite=Strict, `Secure` behind HTTPS, path `/ui`); it stops working when the
token is revoked or `ADMIN_TOKEN` changes. Forms carry a CSRF token. A `readonly` token sees every
page and changes nothing.

Pages: attention (orphans + recent alerts), accounts (create, enrollment code shown once,
suspend/reactivate, revoke with confirmation, groups), links (create, per-link parameters:
lot mode/multiplier, below-min policy, contract-size opt-in, magic, max slippage, max entry
deviation, SL/TP), symbol maps, copies (filters, commands, events, resolution form), symbol
conflicts, events/alerts with filters, EA logs, admin/service tokens. Every action goes through the
same functions as the JSON API, in one unit of work, and is recorded in `events`.

### Drain: suspension and link/group disable (6.2, C6)

`PATCH /admin/accounts/{id} {status: "suspended"}`, `PATCH /admin/links/{id} {enabled: false}` and
`PATCH /admin/groups/{id} {enabled: false}` apply, in the same transaction:

| Copy | Effect |
|---|---|
| `pending`, open only `queued` (proven unsent) | open `superseded`, copy `cancelled` (`account_drain` / `link_disabled`) |
| `pending`, open delivered / in progress | `cancel_requested` + `cancel` (the EA closes the position if the open executed) |
| `pending_blocked` | `cancelled` |
| `open`, `closing`, `uncertain`, `superseded` with `close_intent` | unchanged: modify, close, close_partial, adoption and resolution continue |

The response carries `drain: {cancelled, cancel_requested}`. New master positions for the slave or
link become `skipped` (`account_drain`) or are not created (disabled link). A suspended slave gets
`403` once nothing is exposed (S14). `status: active` lifts the suspension; nothing is re-opened.

### Resolving a copy (4.6 step 7, 5.8)

`POST /admin/copies/{id}/resolve`, audited as `admin.resolved` (actor, note, prior and new state).
When an EA attempt was suspended, a `resolve` command is issued **before** any follow-up command of
the copy and is delivered first; the EA applies it on receipt (journal entry `suspended` →
`confirmed`) and answers `done`. Payload: `resolves_command_id`, `resolves_attempt_id`,
`resolves_action`, `resolution`, `position_id`, `residual_volume`.

| Suspended attempt | `executed` | `not_executed` |
|---|---|---|
| open | requires `position_id` (optional `volume`, `price`): copy `open`, or `closing` + `close` when the master closed meanwhile | copy `cancelled` (`operator_not_executed`) |
| close | copy `closed` | same close, new `attempt_id`; copy back to `closing` |
| close_partial | requires `volume` = residual position volume; copy `open`, next reduction or close | copy `open`, next reduction from the persisted target |
| cancel | the open executed and the EA closed it: copy `closed` | no position came from this copy: `cancelled` |

Without a suspended attempt:

- `closed`: a close answered `position_not_found` without an exit deal (`close_unconfirmed`), an
  `uncertain` copy, or exposure left on a revoked slave. The copy becomes `closed`
  (`operator_closed`), freeing its netting slot.
- `retry_close`: re-issues the `position_not_found` close as a new attempt.

`409 not_resolvable` when the action does not apply to the copy's state; `422` for a missing
`position_id`/`volume`.

### Resolving a symbol conflict (5.8, C8)

`POST /admin/symbol_conflicts/{id}/resolve {resolution, note?}`:

- `accept`: the exposure stays as it is, the conflict is closed and new opens on that slave symbol
  are allowed again (on netting the EA still refuses an open while an unmanaged position holds the
  slot). Refused while a close of it is in flight.
- `close`: closes the position by its id. The close rides on a `superseded` sibling copy without
  `close_intent`, so it never takes a reservation and never touches the managed copy. It is retried
  like any close; the conflict (and the block on new opens) ends only when the close is confirmed
  (`symbol_conflict.closed`). `position_not_found` leaves the conflict open
  (`symbol_conflict.close_failed`). Repeating `close` returns the same command.

Both emit a `resolve` command for the conflict's copy (`conflict_id`, `resolution`, `position_id`)
so the EA can clear any suspended journal entry for that position.

### Orphans and alerts

`GET /admin/orphans` (and the UI front page) lists what only an operator, or later broker evidence,
can settle: `uncertain` copies, `close_unconfirmed` closes, exposure on revoked slaves, and open
symbol conflicts. `GET /admin/alerts` lists the alert event types (`master.stale`,
`master.mass_disappearance`, `copy.uncertain`, `copy.symbol_conflict`, `copy.duplicate_position`,
`copy.close_unconfirmed`, `account.mismatch`, `account.revoked`, `link.disabled_conflict`, ...).

### Tokens

`ADMIN_TOKEN` (env) is the bootstrap admin. `POST /admin/api_tokens {name, scopes}` issues scoped
tokens (`admin` for Rails or automation, `readonly` for dashboards); the token is returned once with
`Cache-Control: no-store`. Revoking one ends its API access and its UI sessions immediately. EA tokens
are per account: `POST /admin/accounts/{id}/enroll_codes` (15 min code), `POST /admin/accounts/{id}/revoke`.

### Not in PR 5

- Background adoption sweep for copies older than the 7-day inline window (background worker PR).
- Diagnostic candidate matching (magic + symbol + open time ±2 s, 5.8a): slave positions are not
  stored outside the gzipped raw snapshots, so the admin shows no candidates yet.
- `POST /v4/logs` (EA log upload) is not implemented yet; the log viewer reads `ea_logs`.
- Changing `MIN_EA_VERSION` does not run the drain transitions (there is no admin action to hook);
  version-gated EAs already get `mode: drain` and refuse opens with `failed: drain`.

CI: `.github/workflows/server.yml` (SQLite and Postgres).

## Polling at scale

Idle polls (`GET /v4/slave/commands` with nothing to deliver or expire, `GET /v4/config`) run first in a
read-only unit (a deferred `BEGIN` on SQLite, no write lock); only when the work would change something
is it rolled back and re-run as a normal `BEGIN IMMEDIATE` unit. With `last_seen_at` throttled, many
EAs polling at once no longer serialize on the SQLite write lock. `scripts/poll_load.py` measures this
against a throwaway server and database (never a live one):

```bash
uv run python scripts/poll_load.py --database-url sqlite:////tmp/load/a.db --slaves 50 --poll-ms 1000 --duration 60
```
