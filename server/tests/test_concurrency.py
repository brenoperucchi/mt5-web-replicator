"""Two snapshots of the same master at the same time are serialized: no duplicate fan-out
(design 8 concurrency test, reduced; D6 BEGIN IMMEDIATE on SQLite / account row lock on Postgres)."""

from __future__ import annotations

import threading
import uuid

from fastapi.testclient import TestClient
from sqlalchemy import func, select

from copycore.models import Command, Copy, MasterPosition

from .conftest import bearer
from .copyhelpers import pos


def test_concurrent_snapshots_no_duplicate_fan_out(cp, app):
    master = cp.account("master", 500)
    g = cp.group(master["id"])
    slaves = [cp.account("slave", 600 + i) for i in range(3)]
    for sl in slaves:
        cp.link(g["id"], sl["id"])
    cp.session(master["token"])
    rounds, n_threads = 5, 4
    statuses: list[int] = []
    errors: list[BaseException] = []
    for rnd in range(rounds):
        positions = [pos(100 + i) for i in range(rnd + 1)]
        bodies = [cp.snapshot_body(master, positions, seq=rnd * n_threads + t + 1) for t in range(n_threads)]
        barrier = threading.Barrier(n_threads)

        def worker(body, barrier=barrier):
            try:
                with TestClient(app) as c:
                    barrier.wait()
                    r = c.post("/v4/master/snapshot", json=body,
                               headers={**bearer(master["token"]), "Idempotency-Key": str(uuid.uuid4())})
                    statuses.append(r.status_code)
            except BaseException as exc:  # noqa: BLE001
                errors.append(exc)

        threads = [threading.Thread(target=worker, args=(b,)) for b in bodies]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
    assert errors == [] and set(statuses) == {200}
    with app.state.sessionmaker() as s:
        assert s.scalar(select(func.count()).select_from(MasterPosition)) == rounds
        assert s.scalar(select(func.count()).select_from(Copy)) == rounds * len(slaves)
        assert s.scalar(select(func.count()).select_from(Command)) == rounds * len(slaves)
