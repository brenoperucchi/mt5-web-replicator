# TradeMirror quickstart: from zero to a first copy

TradeMirror copies trades from a **master** MetaTrader 5 account to one or more **slave** accounts.
It has two parts: the **Copy Server** (Python, in [`server/`](../../server/README.md)) and the
**TradeMirror EA** (MQL5, in [`ea/mt5/`](../../ea/mt5/README.md)). This guide takes you to one
copied trade on two **demo** accounts. Read [Status and limits](#status-and-limits) first.

> Layout note: this guide describes the repository after the EA pull request (#88,
> branch `feat/ea-trademirror`) is merged. Until then, `ea/mt5/` exists only on that branch.

## What you need

- Two **demo** MT5 accounts (one master, one slave), from any broker. Hedging accounts are the
  tested path; netting is covered too (see limits).
- MetaTrader 5 (Windows, or Wine on Linux; see the [appendix](#appendix-vnc-and-wine)). The two
  accounts can be logged into two terminals, or two terminal installs on one machine. One terminal
  runs one account at a time.
- Docker with Compose v2 (or Podman with `podman compose`) for the server.
- `openssl` and `curl` for the commands below.

## 1. Start the Copy Server

```bash
git clone https://github.com/brenoperucchi/mt5-web-replicator.git
cd mt5-web-replicator/server
cp .env.example .env
```

Fill `.env`. With `ENV=production` (what the compose file uses) the server refuses to start without
`ADMIN_TOKEN` and `TOKEN_PEPPER`. Generate every secret with:

```bash
openssl rand -hex 32     # run once each for ADMIN_TOKEN, TOKEN_PEPPER and POSTGRES_PASSWORD
```

Keep `TOKEN_PEPPER` stable: tokens and enrollment codes are stored only as HMAC-SHA256 of it, so
changing it invalidates every enrolled EA. Then:

```bash
docker compose -f docker-compose.copy-server.yml up -d --build
docker compose -f docker-compose.copy-server.yml ps        # copy-server and db should be "healthy"
curl http://localhost:8000/healthz                          # {"status":"ok",...}
```

This starts the server plus Postgres 16 with a named volume `pg-data`. Set `COPY_SERVER_PORT` in
`.env` to use a host port other than 8000. Migrations run on start.

**SQLite variant** (one container, no Postgres; fine for a trial; the server runs one worker, which
SQLite requires):

```bash
docker compose -f docker-compose.copy-server.yml --profile sqlite up -d --build copy-server-sqlite
```

The database lives in the named volume `sqlite-data` (`/data/copy.db`). `POSTGRES_PASSWORD` is still
read by the compose file, so keep a value in `.env`. Do not run both variants at once on the same
port. Stop with `docker compose -f docker-compose.copy-server.yml [--profile sqlite] down`; add `-v`
only if you want to delete the data.

The EA refuses `http://` URLs except `http://localhost` and `http://127.0.0.1`. For a server on
another machine, put it behind HTTPS (a reverse proxy such as Caddy or nginx).

## 2. Create the accounts, group and link

Use the admin UI at `http://localhost:8000/ui` (sign in with `ADMIN_TOKEN`) or the admin API. With
the API:

```bash
export U=http://localhost:8000
export A="Authorization: Bearer <your ADMIN_TOKEN>"
J='Content-Type: application/json'

# broker_server must be the exact server name shown in MT5 (File > Login to Trade Account)
curl -s -X POST $U/admin/accounts -H "$A" -H "$J" -d '{"broker_server":"YourBroker-Demo","login":11111111,"role":"master","label":"master"}'
curl -s -X POST $U/admin/accounts -H "$A" -H "$J" -d '{"broker_server":"YourBroker-Demo","login":22222222,"role":"slave","label":"slave"}'

# one enrollment code per account (valid 15 minutes, one use); use the account ids returned above
curl -s -X POST $U/admin/accounts/1/enroll_codes -H "$A"
curl -s -X POST $U/admin/accounts/2/enroll_codes -H "$A"

# a group (the master) and a link (master to slave)
curl -s -X POST $U/admin/groups -H "$A" -H "$J" -d '{"master_id":1,"name":"first"}'
curl -s -X POST $U/admin/links  -H "$A" -H "$J" -d '{"group_id":1,"slave_id":2,"lot_mode":"master","magic_mode":"same","copy_sl_tp":true}'
```

`lot_mode` is one of `master`, `multiplier`, `fixed`, `min_lot_x`; link parameters are listed in
[`server/README.md`](../../server/README.md). Generate the enrollment codes right before step 4,
since they expire.

## 3. Install the EA (on both terminals)

1. In MetaTrader 5: *File > Open Data Folder*. Copy `ea/mt5/Include/TradeMirror` to
   `MQL5\Include\TradeMirror`, and the files of `ea/mt5/Experts` to `MQL5\Experts`.
2. Open `TradeMirror.mq5` in MetaEditor and compile with F7 (0 errors expected).
3. *Tools > Options > Expert Advisors*: tick **Allow algorithmic trading** and **Allow WebRequest
   for listed URL**, and add the server URL **exactly** as you will type it in `ServerUrl`
   (for example `http://localhost:8000`).
4. Make sure the **AutoTrading** button in the toolbar is on.

## 4. Enroll the master and the slave

On each terminal, attach `TradeMirror` to any chart with:

| Input | Value |
|---|---|
| `ServerUrl` | your server URL (the default is `http://127.0.0.1:8099`; change it to match, e.g. `http://localhost:8000`) |
| `Role` | `Master` on the master terminal, `Slave` on the slave terminal |
| `EnrollCode` | the code for that account |

The EA enrolls, stores its token in `MQL5\Files\TradeMirror\`, and starts a session. Check the
account in `/ui` (accounts page) or `GET /admin/accounts`: `enrolled` is `true` and `last_seen_at`
moves. The code works once; after enrollment you can clear the `EnrollCode` input.

## 5. Make a first trade and see the copy

1. On the master demo account, open a small market position (buy or sell).
2. Within a few seconds the slave opens the same symbol and side. Its order comment looks like
   `c<copy_id>-<master position id>`.
3. In `/ui` (copies page) or `GET /admin/copies` the copy is `open`. Modify SL/TP on the master and it
   follows; close the position on the master and the slave closes, ending in `closed`.
4. `GET /admin/orphans` (and the front page of `/ui`) should be empty. Anything listed there needs a
   decision from you.

Do not trade the copied symbols by hand on the slave, especially on a netting account.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Error 4006, 4014 or 4060, or an alert "URL not allowed" | The server URL is not in *Tools > Options > Expert Advisors > Allow WebRequest for listed URL*, or does not match `ServerUrl` exactly (scheme, host, port, no typo). Add it, and re-attach the EA. |
| Error 1009 or other TLS failures | The EA refuses `http://` except `localhost`/`127.0.0.1`. For a remote server use `https://` with a valid certificate. Check the certificate chain from the machine running the terminal. |
| "not enrolled" / chart says "re-enroll" (server answered 401) | No token file, a revoked token, or the code expired or was already used. Generate a new code, set `EnrollCode` and `ForceReEnroll=true`, then set `ForceReEnroll` back to false. A token file for another login is ignored automatically. |
| Enrollment keeps failing | The account row must match the terminal's logged-in `broker_server` and `login`, and the `Role` input must match the role of the account. Codes are valid 15 minutes. |
| Server unreachable | Check `docker compose ... ps` and `curl <ServerUrl>/healthz` **from the machine running MT5**. Inside Docker or Wine, `localhost` may not be the host (see the appendix). The EA retries with backoff; results are kept in a durable outbox. |
| Nothing is copied | AutoTrading is off, the link or group is disabled, the account is suspended (EA shows "BLOCKED by server"), or the master EA is not connected (the EA only sends snapshots while the terminal is connected and logged into the token's account). Look at `/ui` events and the *Experts* log (set `VerboseLog=true`). |
| Slave refuses an open | `/ui` shows the reason: `price_out_of_range` (price moved beyond `max_entry_deviation_points`), `symbol_not_found` (add a symbol map), `unmanaged_position_on_symbol` (netting slave already holds the symbol), `drain`. |

## Tests

**Server** (needs [uv](https://docs.astral.sh/uv/)):

```bash
cd server
uv run ruff check .
uv run pytest
# same suite on Postgres (throwaway database):
createdb copycore_test && COPYCORE_TEST_DATABASE_URL=postgresql:///copycore_test uv run pytest; dropdb copycore_test
```

**EA self-test in the Strategy Tester** (no network): compile `TradeMirrorSelfTest.mq5`, run it on a
hedging account, any liquid symbol, "Every tick", one day. The journal prints `PASS`/`FAIL` lines
and ends with `TradeMirror self-test: N passed, 0 failed`.

**End-to-end harness** (two real demo terminals and a real server; see the lab assumptions in
[`ea/mt5/README.md`](../../ea/mt5/README.md#end-to-end-tests)):

```bash
uv run ea/mt5/e2e/run.py --list
uv run ea/mt5/e2e/run.py --env-file /path/to/env.sh --fast   # about 2.5 min, no restarts/cuts/faults
uv run ea/mt5/e2e/run.py --env-file /path/to/env.sh          # all scenarios, about 20 min
```

`--env-file` (or the `ADMIN_TOKEN` variable) supplies the admin token. The driver EA refuses to trade
on anything but a DEMO account.

## Further reading

- Design: [`docs/design/0001-copy-core.md`](../design/0001-copy-core.md)
- Scenario catalog (S01 to S53): [`docs/protocol/v4/scenarios/`](../protocol/v4/scenarios/)
- Server details and admin API: [`server/README.md`](../../server/README.md)
- EA details, inputs, journal and outbox: [`ea/mt5/README.md`](../../ea/mt5/README.md)

## Status and limits

- **Phase 1, work in progress.** The server is covered by an automated suite (SQLite and Postgres)
  and the EA by a contract test and the harness above. The EA README itself states the code needs
  compiling and the owner checklist run before any live use.
- **Demo-tested only.** Do not run it on a live account with money you cannot lose. There is no
  guarantee of copy timing, fills or slippage; the slave receives the master's state about every
  2 s and executes at its own broker's price.
- Copies **market positions** only (buy/sell). Pending orders are reported but not copied.
- Hedging and netting accounts are supported; on netting, symbols the copier manages are exclusive
  to it. Some link combinations (for example hedging master to netting slave with overlapping
  symbols) are rejected with `422 config_conflict`; see the design and the scenario catalog.
- The Phase 1 exit criterion (48 h on demo, one master, one hedging and one netting slave, with a
  forced restart and a network cut) is not yet recorded as done.
- **License:** [PolyForm Noncommercial 1.0.0](../../LICENSE.md). Commercial use needs a separate
  license. Contributions require the [CLA](../../CLA.md). See [CONTRIBUTING](../../CONTRIBUTING.md).

## Appendix: VNC and Wine

The lab used for the E2E harness runs MT5 under Wine in containers with a VNC desktop (the
`mt5wine:vnc` image). You do not need that to try TradeMirror on Windows.

- A terminal inside a container reaches the host server through the container bridge address
  (`172.17.0.1` on default Docker), not `localhost`. The lab forwards the EA's
  `http://127.0.0.1:8099` to the host with a small TCP forwarder in each container; add the URL the
  EA actually uses to the WebRequest list.
- Use VNC to click through the *Tools > Options* dialog and to attach the EA the first time.
- Close terminals gracefully (`wine taskkill /im terminal64.exe`) so they save their profile.
