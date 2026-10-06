# TradeMirror EA for MetaTrader 5 (protocol v4, Phase 1)

TradeMirror is the MT5 client of the Copy Server in [`server/`](../../server/README.md). It
implements design [`docs/design/0001-copy-core.md`](../../docs/design/0001-copy-core.md) §4
(protocol v4) and the EA journal/outbox of §4.6. The Python package stays `copycore`.

One EA, two roles, set by the `Role` input:

- **Master** publishes its positions and recent deals (`POST /v4/master/snapshot`, about every 2 s
  and right after any trade event).
- **Slave** polls commands (`GET /v4/slave/commands`), executes them with a durable journal,
  posts results from a durable outbox (`POST /v4/slave/results`) and reports its own snapshot
  (`POST /v4/slave/snapshot`, every 10 s and after every execution).

Phase 1 copies market positions only (buy/sell). Pending orders are reported but not copied.

> **Status: not compiled yet.** This code was written without MetaEditor. Compile it and run the
> checklist at the end before using it on a live account.

## Files

```
ea/mt5/
├── Experts/
│   ├── TradeMirror.mq5            # the EA (master or slave)
│   ├── TradeMirrorSelfTest.mq5    # client tests for the Strategy Tester (fake server injected)
│   └── TradeMirrorE2EDriver.mq5   # test driver for the end-to-end suite (demo only)
├── Include/TradeMirror/
│   ├── Client.mqh                 # v4 client: routes, fair scheduling, retries, session, enroll, rotation, drain
│   ├── Executor.mqh               # slave command executor: pre-send evidence, journal states, results
│   ├── Journal.mqh                # durable command journal (JSONL, compacted with temp file + FileMove)
│   ├── Outbox.mqh                 # durable results outbox
│   ├── TokenStore.mqh             # per-terminal token file (atomic writes, pending rotation token)
│   ├── Broker.mqh                 # snapshots, symbol specs, evidence lookups (positions, orders, deals)
│   ├── Transport.mqh              # ITransport + WebRequest implementation
│   ├── TestTransport.mqh          # in-memory fake v4 server (self-test only)
│   ├── Json.mqh                   # JSON reader/writer (64-bit ids kept as text)
│   └── Util.mqh                   # log, clocks, UUIDs, atomic file helpers
└── tests/
    ├── fault_proxy.py             # fault-injecting proxy for live demo tests against the real server
    └── fixtures/*.json            # request bodies exactly as the EA builds them (checked in CI)
```

## Install

1. In MetaTrader 5: *File > Open Data Folder*. Copy `ea/mt5/Include/TradeMirror` to
   `MQL5\Include\TradeMirror` and the two files of `ea/mt5/Experts` to `MQL5\Experts`.
2. Open `TradeMirror.mq5` in MetaEditor and compile (F7). Do the same for
   `TradeMirrorSelfTest.mq5`.
3. *Tools > Options > Expert Advisors*: tick **Allow algorithmic trading** and
   **Allow WebRequest for listed URL**, and add the server URL exactly as in the `ServerUrl` input
   (for example `https://copy.example.com`). Without it every call fails with error 4014/4060 and
   the EA shows an alert telling you so.

The EA refuses `http://` URLs except `http://localhost` and `http://127.0.0.1` (§6.3).

## Enroll

1. In the Copy Server admin (`/ui`, or `POST /admin/accounts`) create the account with the broker
   server name, login and role, then generate an **enrollment code** (valid 15 minutes, one use).
2. Attach `TradeMirror` to any chart of that terminal with:

   | Input | Value |
   |---|---|
   | `ServerUrl` | the server URL (no trailing slash needed) |
   | `Role` | Master or Slave, as created in the admin |
   | `EnrollCode` | the code |

3. The EA calls `POST /v4/enroll`, writes the token to
   `MQL5\Files\TradeMirror\copy_token_<server>_<login>_<role>.dat` (terminal-local, written
   through a temp file and `FileMove`) and starts a session. The code is consumed on the first
   authenticated call. If the enroll reply is lost, the EA retries with the same code and gets a
   fresh token (the earlier one dies).
4. Links, multipliers, symbol maps and magic numbers are configured in the admin; the EA has no
   copy settings of its own and trades exactly the symbol and volume it receives.

Re-enrolling (new terminal, revoked token, lost file): generate a new code, set `EnrollCode` and
`ForceReEnroll=true`, then set `ForceReEnroll` back to false. A token file for another login is
ignored automatically.

Token rotation runs every `TokenRotateDays` (default 30, 0 = never) in two steps: the new token is
written to disk before `POST /v4/token/confirm` revokes the old one. A lost rotate reply is
recovered through `409 rotation_pending` and `rotate?restart=true`.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `ServerUrl` | `http://127.0.0.1:8099` | Copy Server base URL (a local server by default; use https for a remote one) |
| `Role` | Slave | Master or Slave |
| `EnrollCode` | empty | one-time enrollment code |
| `ForceReEnroll` | false | enroll even when a token file exists |
| `TokenRotateDays` | 30 | automatic token rotation period (0 = off) |
| `VerboseLog` | false | debug lines in the Experts log |
| `AlertPopups` | true | alerts as terminal pop-ups (always printed to the log) |

## How it behaves

**Scheduling (§4.2).** One `OnTimer` tick per second. Each tick first runs local work (journal
recovery, then `close`/`close_partial`/`cancel`/`resolve`, then `open`/`modify`) and then makes
**at most one HTTP call** (5 s timeout), picked by a fair rotation of the due routes. Results get
at most every other slot while a backlog exists. Nothing sleeps and nothing retries inside a call.

**Retries.** 429, 5xx, timeouts and network errors share one budget per request: 6 attempts and
60 s, backoff 1/2/4/8/16 s with jitter. `Retry-After` delays only that route. When the budget runs
out, state requests (snapshots, config, polls, symbols) are dropped and replaced by fresh state;
results are never dropped and keep retrying every 16 s with one chart alert.

| Answer | EA behavior |
|---|---|
| 401 | stops trading and all calls except enroll; chart shows "re-enroll" |
| 403 | no new opens; polls `/v4/config` every 5 min |
| 404 | alert (server version mismatch); route retried in 5 min |
| 409 `stale_session` | stops snapshots and alerts; a new session starts only on EA reload or a config mode change (§5.6) |
| 409 `account_mismatch` | snapshots stop; alert |
| 400/413/422 | alert; results stay in the outbox and are retried every 5 min |

**Snapshots** are sent only while `TERMINAL_CONNECTED` is true, the terminal is logged into the
token's account and `HistorySelect` returned. Every attempt carries a fresh `seq` of the current
server-issued session. History: deals since the last accepted snapshot, at least the last 30
(more when the server sets `send_history`).

**Journal (§4.6).** `MQL5\Files\TradeMirror\journal_<server>_<login>_<role>.jsonl`, one line per
state change of a `(command_id, attempt_id)`, flushed before the next step; compacted at start.

1. A re-delivered attempt that is `confirmed` re-sends its stored result; it never trades again.
2. Pre-send evidence: `open` looks for the comment `c<copy_id>` with the command magic in positions,
   orders and history deals (persisted order/deal ids first); `close` checks the position by
   `position_id` and its exit deals; `close_partial` compares the volume with `residual_volume`;
   `cancel` closes the open's position if it exists, and answers `not_executed` only when the open
   never left the terminal.
3. `prepared` (flushed) → `sent` (flushed, `in_progress` queued) → `OrderSend` → order/deal/request
   ids persisted at once (also from `OnTradeTransaction`) → `confirmed`.
4. A definitive broker reject is `failed` with the retcode name as `error_code`. A timeout or a
   restart while `sent` makes the entry `uncertain`; it is re-checked for 20 s (ids first, then the
   comment). With no conclusive evidence it becomes `suspended`, the result is `uncertain` and a
   chart alert fires. No evidence is never reported as "not executed".
5. Suspension is per copy: other copies keep trading. A suspended entry is re-checked about every
   10 s and is settled by later broker evidence or by the operator's `resolve` command (admin:
   copies → resolve).
6. Opens are refused with `failed` when the account is in drain (`drain`), the price moved more
   than `max_entry_deviation_points` from the master (`price_out_of_range`), the symbol is missing
   (`symbol_not_found`), or a netting symbol already holds a position the copier does not own
   (`unmanaged_position_on_symbol`). An open past `expires_at` is answered `expired`.

The outbox (`outbox_<server>_<login>_<role>.jsonl`) holds every result until a 2xx; batches carry
at most 50 results and keep their `Idempotency-Key` until acknowledged.

Netting accounts: symbols the copier manages are exclusive to it (§5.8a). Do not trade them by hand
or with other EAs on the slave.

## Tests

**Strategy Tester (no network).** `TradeMirrorSelfTest` runs the real client against an injected
fake server (`TestTransport.mqh`) and real tester trades. It covers S01-S05 (journal and outbox,
with crash seams before/after `OrderSend`) and S24-S26 (429 with a huge `Retry-After`, lost rotate
reply, lost enroll reply). Run it on a hedging account, any liquid symbol, "Every tick", one day.
The tester journal prints `PASS`/`FAIL` lines; the optimization criterion (`OnTester`) is the number
of failed checks, 0 when green.

**Contract (CI).** `server/tests/test_ea_contract.py` checks the MQL sources against the server's
Pydantic models (every key the EA writes exists, every required field is written, every route
exists, every command key the executor reads is sent by the server) and posts the
`tests/fixtures` bodies through a full copy cycle on the real app.

**Live (demo accounts).** Run the server and the fault proxy, point a demo EA at the proxy:

```bash
cd server && ENV=development uv run uvicorn copycore.app:create_app --factory --port 8000
# from the repo root, one fault at a time:
uv run --project server python ea/mt5/tests/fault_proxy.py --upstream http://127.0.0.1:8000 --port 8080 --drop-results 1
```

`ServerUrl=http://localhost:8080` and add `http://localhost:8080` to the WebRequest list. The proxy
validates every EA request against the server models and prints any violation. Faults:
`--drop-results N` (S01), `--drop-enroll 1` (S26), `--drop-rotate 1` (S25),
`--rate-limit /v4/slave/results=3600` (S24), `--fail-all-for 120` (network cut). The proxy must run
where the terminal can reach it (on Windows, or in the same Wine prefix host).

## End-to-end tests

`ea/mt5/e2e/run.py` runs the live demo checks (most of the checklist below and the feasible §8
scenarios) with one command against two real terminals and a real Copy Server.

- `Experts/TradeMirrorE2EDriver.mq5` is a small test EA that trades on command. It runs next to
  `TradeMirror` in both terminals (its own chart), reads one JSON file per command from
  `MQL5\Files\TradeMirrorE2E\cmd\`, writes the reply to `...\ack\` (temp file + `FileMove`, a command
  with an existing ack is never executed twice) and writes `status.json` (account, positions with
  ticket/comment/volume/SL/TP/magic, recent deals) every second. It refuses every trade unless the
  account is DEMO. Ops: `open`, `modify`, `close`, `close_partial`, `close_all`, `ping`.
- The runner writes the command files straight into the bind-mounted Wine prefixes and checks the
  result through the admin API (`/admin/copies`, `/admin/commands`, `/admin/events`,
  `/admin/orphans`) and the slave's `status.json`. Every scenario ends by flattening both accounts
  (master first, so the copier closes its copies) and waiting until the link has no exposure.

Assumed setup (the `mt5wine:vnc` lab): the master and slave terminals run in podman containers
`mt5-trademirror` and `mt5-trademirror-slave`, each with `/home/mt5/.mt5/tm_forward.py` forwarding
the EA's `http://127.0.0.1:8099` to the server on the host (`172.17.0.1:8099`). Network cuts stop
that forwarder; the fault scenarios point it at `tests/fault_proxy.py` on `172.17.0.1:8098`; the
restart scenarios hard-kill `terminal64.exe` (the container exits) and start the container again.
All paths, containers, ids and symbols are options (`--help`) or `E2E_*` environment variables.

One-time setup, per terminal (master and slave):

1. Copy `Experts/TradeMirrorE2EDriver.mq5` to `MQL5\Experts` and compile it (0 errors, 0 warnings).
2. Open a second chart (any symbol) and attach `TradeMirrorE2EDriver` with default inputs; on the
   *Common* tab tick **Allow Algo Trading**. AutoTrading must be on.
   Headless alternative: close the terminal gracefully (`wine taskkill /im terminal64.exe` inside the
   container, so it saves its profile), add a `chartNN.chr` copied from the TradeMirror chart with
   the `<expert>` block replaced by `name=TradeMirrorE2EDriver`, `path=Experts\TradeMirrorE2EDriver.ex5`,
   `expertmode=5`, list it in `order.wnd`, start the container again and restart the forwarder.
3. Check `MQL5\Files\TradeMirrorE2E\status.json` is rewritten every second.

The server needs the master and slave enrolled with one enabled link (`lot_mode=master`,
`magic_mode=same`, `copy_sl_tp=true`), with both `TradeMirror` EAs running.

Run (from the repository root):

```bash
uv run ea/mt5/e2e/run.py --list
uv run ea/mt5/e2e/run.py --env-file /path/to/env.sh          # all scenarios (~20 min)
uv run ea/mt5/e2e/run.py --env-file /path/to/env.sh --fast   # no restarts/cuts/faults (~2.5 min)
uv run ea/mt5/e2e/run.py --env-file /path/to/env.sh full_close sltp_modify
```

`--env-file` (or `ADMIN_TOKEN`) gives the admin token. `server_restart` also needs
`E2E_SERVER_RESTART_CMD`, a shell command that starts the server again (the runner stops the
process matching `--server-match` first); without it the scenario is skipped. The output is a
PASS/FAIL table; a JSON report with the server events of each scenario goes to `ea/mt5/e2e/out/`.
Exit code 0 when all ran scenarios passed, 1 on any failure, 2 when preconditions fail (server
health, enrolled accounts, link settings, drivers alive and on DEMO, AutoTrading on).

| Scenario | Covers |
|---|---|
| `open_copy`, `sell_side`, `full_close` | open/close mirrored, side, volume, magic, one entry deal |
| `sltp_modify` | SL/TP mirrored twice |
| `partial_close` | hedging partial closes (S13) |
| `multi_symbol` | three symbols at once, close-all |
| `manual_untouched` | a manual slave position is never touched or adopted |
| `slave_restart_mid_open` | terminal killed right after delivery: no second position (S02/S03) |
| `slave_restart_while_open` | restart with an open copy: no duplicate, close still works |
| `network_cut_during_close` | slave offline across the master close (S07, shorter) |
| `network_cut_during_open` | slave offline when the master opens |
| `server_restart` | server restart with an open copy (S43, partial) |
| `fault_drop_results` | lost results reply (S01) |
| `fault_rate_limit_results` | 429 with a huge `Retry-After` on results (S24) |
| `fault_server_down` | 503 for 45 s around an open |

## Owner checklist before merge

MetaEditor:

- [ ] `TradeMirror.mq5` and `TradeMirrorSelfTest.mq5` compile with 0 errors; review the warnings
      (implicit conversions, unused variables).

Strategy Tester (`TradeMirrorSelfTest`, hedging account, EURUSD, Every tick, 1 day):

- [ ] Journal ends with `TradeMirror self-test: N passed, 0 failed`; no `FAIL` lines.
- [ ] `OnTester` result is 0.

Demo, two terminals (one master, one hedging slave) against a local server:

- [ ] Enroll both with codes from `/ui`; token files appear in `MQL5\Files\TradeMirror`; the codes
      cannot be reused.
- [ ] Open/modify SL-TP/partial close/close on the master: the slave mirrors each step; the copy
      ends `closed` in `/ui`.
- [ ] Remove the slave EA right after an open is delivered, re-attach: no second position.
- [ ] `fault_proxy.py --drop-results 1`: one position, copy `open`, outbox empties.
- [ ] `fault_proxy.py --rate-limit /v4/slave/results=3600`: slave keeps polling and executing;
      results arrive after the proxy restarts without the flag.
- [ ] `--drop-enroll 1` and `--drop-rotate 1` (set `TokenRotateDays=1` and edit `issued_ms` to 0
      in the token file to force a rotation): EA recovers, old token rejected afterwards.
- [ ] Suspend the slave account in the admin while a copy is open: `mode: drain`, the master's
      close is still executed, then the EA shows "BLOCKED by server".
- [ ] Netting slave: a manual position on a copied symbol makes the open fail with
      `unmanaged_position_on_symbol` and an alert.
- [ ] Disconnect the network for 2 minutes during a master close: the close executes on return.
- [ ] The proxy reported 0 contract violations.

Then the Phase 1 exit run of §8: 48 h demo, one master, one hedging and one netting slave, one
forced EA restart and one network cut, zero orphan copies in `/ui`.
