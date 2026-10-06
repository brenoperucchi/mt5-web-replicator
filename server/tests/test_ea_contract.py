"""TradeMirror EA (ea/mt5) against the real v4 contract (design 4.3-4.6, D3 "EA v4 struct names").

MQL cannot be compiled or run in CI, so the EA side is checked three ways:

1. Static: every JSON key the MQL builders write is a field of the server's Pydantic model for that
   route (a misspelled key would be silently ignored), every required field is written, every route
   the EA calls exists, and every key the executor reads from a command is one the server sends.
2. Wire fixtures (`ea/mt5/tests/fixtures/*.json`, byte-for-byte the shapes the builders emit) are
   posted to the real app through a full copy cycle; the server must accept them and reach the
   expected copy states.
3. The fault-injecting proxy used for the live demo tests (S01, S24-S26) behaves as documented.
"""

from __future__ import annotations

import json
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from copycore.routers.v4 import ConfirmIn, EnrollIn
from copycore.routers.v4_copy import PositionIn, ResultIn, SessionIn, SnapshotIn, SymbolSpecIn

from .conftest import admin_headers, bearer
from .copyhelpers import SERVER, deal, pos
from .test_results import copy_of, setup

ROOT = Path(__file__).resolve().parents[2]
EA = ROOT / "ea" / "mt5"
INC = EA / "Include" / "TradeMirror"
FIXTURES = EA / "tests" / "fixtures"

WRITER = re.compile(r'\bw\.(?:Str|Int|Num|Bool|Null|Raw|IntOrNull|NumOrNull|BeginArr|BeginObj)\("([a-z_]+)"')
READER = re.compile(r'\b(?:j|c\.j|cj)\.(?:Str|Long|Dbl|Bool|Get|Has)\("([a-z_]+)"')


def mql(name: str) -> str:
    return (INC / name).read_text(encoding="utf-8")


def function_body(src: str, signature: str) -> str:
    """Text of the first `{...}` block after `signature` (brace matched)."""
    start = src.index(signature)
    i = src.index("{", start)
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return src[i:j + 1]
    raise AssertionError(f"unbalanced braces after {signature}")


def written(file: str, *signatures: str) -> set[str]:
    src = mql(file)
    keys: set[str] = set()
    for sig in signatures:
        keys |= set(WRITER.findall(function_body(src, sig)))
    return keys


def required(model) -> set[str]:
    return {k for k, f in model.model_fields.items() if f.is_required()}


# --- 1. static contract ----------------------------------------------------------------------------

def test_enroll_session_confirm_bodies_match_models():
    assert written("Client.mqh", "void              DoEnroll(void)") == set(EnrollIn.model_fields)
    assert written("Client.mqh", "void              DoSession(void)") == set(SessionIn.model_fields)
    assert written("Client.mqh", "void              DoConfirm(void)") == set(ConfirmIn.model_fields)


def test_snapshot_body_matches_models():
    top = written("Broker.mqh", "string TmBuildSnapshot(") | {"history"}
    top |= written("Broker.mqh", "void TmWritePositions(") & {"positions"}
    top |= written("Broker.mqh", "void TmWritePending(") & {"pending"}
    assert top <= set(SnapshotIn.model_fields), top - set(SnapshotIn.model_fields)
    assert required(SnapshotIn) <= top
    position = written("Broker.mqh", "void TmWritePositions(") - {"positions"}
    assert position <= set(PositionIn.model_fields), position - set(PositionIn.model_fields)
    assert required(PositionIn) <= position
    history = written("Broker.mqh", "bool TmWriteHistory(") - {"history"}
    # keys read by the close detection / reconciliation (reconcile.py _Deal, master.py)
    assert {"deal", "order", "position_id", "entry", "reason", "symbol", "volume", "price", "profit",
            "commission", "swap", "magic", "comment", "time_msc"} <= history


def test_symbol_spec_body_matches_model():
    keys = written("Broker.mqh", "void TmWriteSymbolSpec(") | written("Broker.mqh", "void TmWriteFillingModes(")
    assert keys == set(SymbolSpecIn.model_fields)


def test_result_bodies_use_only_server_fields():
    keys = written("Executor.mqh", "string            ResultJson(", "void              InProgress(")
    assert keys <= set(ResultIn.model_fields), keys - set(ResultIn.model_fields)
    assert required(ResultIn) <= keys


def test_ea_status_and_error_codes_are_known_to_the_server():
    from copycore.engine.results import OPEN_CANCEL_CODES, OPEN_SKIP_CODES, RESULT_STATUSES

    src = mql("Executor.mqh")
    statuses = set(re.findall(r'(?:Confirm|ConfirmSimple)\(e, "([a-z_]+)"', src))
    statuses |= set(re.findall(r'ResultJson\(\w+, "([a-z_]+)"', src)) | {"in_progress", "uncertain", "closed",
                                                                        "done_partial"}
    assert statuses <= set(RESULT_STATUSES), statuses - set(RESULT_STATUSES)
    # the codes with a dedicated server meaning are spelled exactly as the server expects
    for code in OPEN_SKIP_CODES | OPEN_CANCEL_CODES | {"position_not_found", "unmanaged_position_on_symbol"}:
        assert f'"{code}"' in src, code


def test_every_ea_route_exists(app):
    src = mql("Client.mqh")
    paths = {p.split("?")[0] for p in re.findall(r'"(/v4/[a-z_/]+(?:\?[a-z=]+)?)"', src)}
    served = set(app.openapi()["paths"])
    # /v4/logs is not implemented by the server yet (server README "Not in PR 5"); the EA disables
    # log upload on 404/413 and never depends on it.
    assert paths - served == {"/v4/logs"}


def test_rotate_restart_query_is_supported():
    assert '"/v4/token/rotate?restart=true"' in mql("Client.mqh")


# --- 2. wire fixtures through a real copy cycle ----------------------------------------------------

def render(name: str, **values) -> dict:
    text = (FIXTURES / name).read_text(encoding="utf-8")
    for k, v in values.items():
        text = text.replace(f'"{{{{#{k}}}}}"', json.dumps(v)).replace(f"{{{{{k}}}}}", str(v))
    assert "{{" not in text, f"unfilled placeholder in {name}: {text}"
    return json.loads(text)


def post(cp, path, token, body, method="post", expect=200):
    r = getattr(cp.c, method)(path, json=body, headers={**bearer(token), "Idempotency-Key": f"k-{time.time_ns()}"})
    assert r.status_code == expect, r.text
    return r.json() if r.content else None


def now_ms() -> int:
    return int(time.time() * 1000)


def ea_session(cp, acct, login):
    body = render("session.json", now=now_ms())
    s = post(cp, "/v4/session", acct["token"], body, expect=201)
    acct["session"], acct["seq"], acct["login_"] = s, 0, login
    return s


def ea_snapshot(cp, acct, fixture, route, **values):
    acct["seq"] += 1
    s = acct["session"]
    body = render(fixture, session_id=s["session_id"], epoch=s["epoch"], seq=acct["seq"], now=now_ms(),
                  login=acct["login"], server=SERVER, **values)
    return post(cp, route, acct["token"], body)


def ea_results(cp, acct, fixture, cmd, **values):
    body = render(fixture, command_id=cmd["command_id"], attempt_id=cmd["attempt_id"], copy_id=cmd["copy_id"],
                  now=now_ms(), **values)
    return post(cp, "/v4/slave/results", acct["token"], body)


def test_enroll_and_symbols_fixtures(cp, api):
    acct = api.create_account(SERVER, 4401, "slave")
    code = api.issue_code(acct["id"])
    body = render("enroll.json", code=code, server=SERVER, login=4401, role="slave")
    r = cp.c.post("/v4/enroll", json=body, headers={"Idempotency-Key": "enroll-1"})
    assert r.status_code == 201, r.text
    token = r.json()["token"]
    acct.update(token=token, login=4401)
    ea_session(cp, acct, 4401)
    assert post(cp, "/v4/symbols", token, render("symbols.json"), method="put", expect=204) is None


def test_full_cycle_with_ea_fixtures(cp, app):
    master, (sl,) = setup(cp)
    ea_session(cp, master, master["login"])
    ea_session(cp, sl, sl["login"])
    out = ea_snapshot(cp, master, "master_snapshot.json", "/v4/master/snapshot", position_id=1, deal=5001)
    assert out["accepted"] is True

    (o,) = cp.poll(sl)["commands"]
    assert o["action"] == "open" and o["comment"] == f"c{o['copy_id']}-1"
    assert ea_results(cp, sl, "results_in_progress.json", o)["applied"] == 1
    assert ea_results(cp, sl, "results_open_done.json", o, order=81, deal=91, position_id=7001)["applied"] == 1
    assert copy_of(cp, o["copy_id"])["state"] == "open"
    # outbox replay after a restart (S01): same attempt again is a duplicate, never an error
    again = ea_results(cp, sl, "results_open_done.json", o, order=81, deal=91, position_id=7001)
    assert again["duplicates"] == 1 and again["unknown"] == []

    snap = ea_snapshot(cp, sl, "slave_snapshot.json", "/v4/slave/snapshot", position_id=7001, deal=91, order=81,
                       magic=o["magic"], comment=o["comment"])
    assert snap["accepted"] is True

    # partial reduction (S13/S31 shape) → close_partial done
    cp.snapshot(master, [pos(1, volume=0.4)], history=[deal(5101, 1, "out", volume=0.6)])
    (cpart,) = cp.poll(sl)["commands"]
    assert cpart["action"] == "close_partial"
    ea_results(cp, sl, "results_close_partial_done.json", cpart, order=82, deal=92, position_id=7001)
    assert copy_of(cp, o["copy_id"])["state"] == "open"

    # SL/TP modify → notmodify
    cp.snapshot(master, [pos(1, volume=0.4, sl=1.0)])
    (m,) = cp.poll(sl)["commands"]
    assert m["action"] == "modify"
    assert ea_results(cp, sl, "results_modify_notmodify.json", m, position_id=7001)["applied"] == 1

    # master close → close done
    cp.close_master(master, 1)
    (close,) = cp.poll(sl)["commands"]
    assert close["action"] == "close" and close["position_id"] == 7001
    ea_results(cp, sl, "results_in_progress.json", close)
    ea_results(cp, sl, "results_close_done.json", close, order=83, deal=93, position_id=7001)
    assert copy_of(cp, o["copy_id"])["state"] == "closed"


def test_failed_uncertain_and_cancel_fixtures(cp, app):
    master, (sl,) = setup(cp)
    ea_session(cp, sl, sl["login"])
    cp.snapshot(master, [pos(1), pos(2), pos(3), pos(4)])
    o1, o2, o3, o4 = sorted(cp.poll(sl)["commands"], key=lambda c: c["copy_id"])
    ea_results(cp, sl, "results_open_failed_price_guard.json", o1)
    assert copy_of(cp, o1["copy_id"])["state"] == "skipped"            # S20
    ea_results(cp, sl, "results_open_uncertain.json", o2)
    assert copy_of(cp, o2["copy_id"])["state"] == "uncertain"          # S04
    # master closes 3 and 4 after their opens were delivered → cancel
    cp.close_master(master, 3, 4, keep=[pos(1), pos(2)])
    cancels = {c["copy_id"]: c for c in cp.poll(sl)["commands"] if c["action"] == "cancel"}
    assert set(cancels) == {o3["copy_id"], o4["copy_id"]}
    assert cancels[o3["copy_id"]]["open_command_id"] == o3["command_id"]
    ea_results(cp, sl, "results_cancel_closed.json", cancels[o3["copy_id"]], order=84, deal=94, position_id=7003)
    assert copy_of(cp, o3["copy_id"])["state"] == "closed"            # S05
    ea_results(cp, sl, "results_cancel_not_executed.json", cancels[o4["copy_id"]])
    assert copy_of(cp, o4["copy_id"])["state"] == "cancelled"


def test_resolve_command_keys_and_fixture(cp, app):
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    (o,) = cp.poll(sl)["commands"]
    ea_results(cp, sl, "results_open_uncertain.json", o)
    r = cp.c.post(f"/admin/copies/{o['copy_id']}/resolve", json={"resolution": "executed", "position_id": 7001},
                  headers=admin_headers())
    assert r.status_code == 200, r.text
    (rc,) = [c for c in cp.poll(sl)["commands"] if c["action"] == "resolve"]
    assert {"resolves_command_id", "resolves_attempt_id", "resolution", "position_id"} <= set(rc)
    assert (rc["resolves_command_id"], rc["resolves_attempt_id"]) == (o["command_id"], o["attempt_id"])
    assert ea_results(cp, sl, "results_resolve_done.json", rc)["applied"] == 1


def test_executor_reads_only_keys_the_server_sends(cp, app):
    """Every key CExecutor reads from a command exists in some command the server issues."""
    master, (sl,) = setup(cp)
    seen: set[str] = set()
    cp.snapshot(master, [pos(1), pos(2)])
    opens = cp.poll(sl)["commands"]
    for c in opens:
        seen |= set(c)
    o1, o2 = sorted(opens, key=lambda c: c["copy_id"])
    cp.results(sl, [{"command_id": o1["command_id"], "attempt_id": o1["attempt_id"], "copy_id": o1["copy_id"],
                     "status": "done", "position_id": 7001, "volume": 1.0, "price": 1.1}])
    cp.snapshot(master, [pos(1, volume=0.5, sl=1.0), pos(2)])
    for c in cp.poll(sl)["commands"]:
        seen |= set(c)
    cp.close_master(master, 1, 2)
    for c in cp.poll(sl)["commands"]:
        seen |= set(c)
    read = set(READER.findall(mql("Executor.mqh")))
    # resolve keys are checked in test_resolve_command_keys_and_fixture; superseded tombstones carry
    # only command_id/action (4.5)
    read -= {"resolves_command_id", "resolves_attempt_id", "resolution", "residual_volume"}
    assert read <= seen, read - seen


# --- 3. fault proxy --------------------------------------------------------------------------------

@pytest.fixture
def proxy(client):
    sys.path.insert(0, str(EA / "tests"))
    import fault_proxy as fp

    def forward(method, path, headers, body):
        r = client.request(method, path, content=body, headers=headers)
        return r.status_code, dict(r.headers), r.content

    state = fp.ProxyState(faults=fp.Faults())
    server = fp.serve(state, forward, port=0)
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    yield state, f"http://127.0.0.1:{server.server_address[1]}"
    server.shutdown()
    server.server_close()


def call(url, method, path, token=None, body=None, key=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if key:
        headers["Idempotency-Key"] = key
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url + path, data=data, method=method, headers=headers)  # noqa: S310
    try:
        with urllib.request.urlopen(req, timeout=5) as r:  # noqa: S310 - local test server
            return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


def test_proxy_drops_enroll_reply_and_validates(proxy, api):
    """S26 through the proxy: the first enroll is processed but its reply lost; the retry (same
    code, same key) enrolls again and the first token is dead."""
    state, url = proxy
    acct = api.create_account(SERVER, 4501, "slave")
    code = api.issue_code(acct["id"])
    state.faults.drop_enroll = 1
    body = render("enroll.json", code=code, server=SERVER, login=4501, role="slave")
    with pytest.raises((urllib.error.URLError, ConnectionError, OSError)):
        call(url, "POST", "/v4/enroll", body=body, key="e-1")
    status, _, raw = call(url, "POST", "/v4/enroll", body=body, key="e-1")
    assert status == 201
    token = json.loads(raw)["token"]
    assert call(url, "GET", "/v4/config", token=token)[0] == 200
    assert state.violations == []
    # a malformed body is reported as a contract violation
    call(url, "POST", "/v4/session", token=token, body={"boot_nonce": "x", "taken_at": 1, "bogus": 1}, key="s-1")
    assert any("bogus" in v for v in state.violations)


def test_proxy_rate_limit_and_lost_results(proxy, cp):
    """S24 / S01 through the proxy: 429 + Retry-After on one route only; a results post forwarded but
    its reply dropped is applied once and its replay is a duplicate."""
    state, url = proxy
    master, (sl,) = setup(cp)
    cp.snapshot(master, [pos(1)])
    state.faults.rate_limit = {"/v4/slave/results": 3600}
    status, headers, _ = call(url, "POST", "/v4/slave/results", token=sl["token"], body={"results": []}, key="r-0")
    assert status == 429 and headers.get("Retry-After") == "3600"
    status, _, raw = call(url, "GET", "/v4/slave/commands", token=sl["token"])
    assert status == 200                                  # other routes continue
    (o,) = json.loads(raw)["commands"]
    state.faults.rate_limit = {}
    state.faults.drop_results = 1
    body = render("results_open_done.json", command_id=o["command_id"], attempt_id=o["attempt_id"],
                  copy_id=o["copy_id"], now=now_ms(), order=1, deal=2, position_id=7001)
    with pytest.raises((urllib.error.URLError, ConnectionError, OSError)):
        call(url, "POST", "/v4/slave/results", token=sl["token"], body=body, key="r-1")
    assert copy_of(cp, o["copy_id"])["state"] == "open"   # applied although the reply was lost
    status, _, raw = call(url, "POST", "/v4/slave/results", token=sl["token"], body=body, key="r-1")
    assert status == 200                                   # same key → stored response replayed
    assert state.violations == []
