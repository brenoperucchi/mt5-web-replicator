"""Config-time link/map validation (design 5.3 config time, 5.4 contract size, 7.1).

Every check returns a reason string (or None); callers turn it into `422 config_conflict`
(admin) or into `enabled=false` + `link.disabled_conflict` (enroll revalidation).
"""

from __future__ import annotations

from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Account, CopyGroup, CopyLink, Event, SymbolMap, SymbolSpec
from .symbols import resolve_symbol


def identity(a: Account) -> tuple[str, int]:
    return (a.broker_server_norm, a.login)


def margin_conflict(master: Account, slave: Account) -> str | None:
    """OD1: a hedging master cannot feed a netting slave in Phase 1."""
    if master.margin_mode == "hedging" and slave.margin_mode == "netting":
        return "hedging master cannot copy to a netting slave (Phase 1)"
    return None


def creates_cycle(s: Session, master: Account, slave: Account, exclude_link_id: int | None = None) -> bool:
    """True if `master` (by broker server + login) is reachable from `slave` through enabled links."""
    target = identity(master)
    if identity(slave) == target:
        return True
    edges: dict[tuple[str, int], set[tuple[str, int]]] = {}
    rows = s.execute(select(CopyLink.id, CopyLink.master_id, CopyLink.slave_id).where(CopyLink.enabled.is_(True)))
    accts = {a.id: a for a in s.scalars(select(Account))}
    for link_id, mid, sid in rows:
        if link_id == exclude_link_id or mid not in accts or sid not in accts:
            continue
        edges.setdefault(identity(accts[mid]), set()).add(identity(accts[sid]))
    seen, stack = set(), [identity(slave)]
    while stack:
        node = stack.pop()
        if node == target:
            return True
        if node in seen:
            continue
        seen.add(node)
        stack.extend(edges.get(node, ()))
    return False


def netting_overlap(s: Session, slave: Account, *, extra: tuple[CopyLink, CopyGroup] | None = None,
                    exclude_link_id: int | None = None) -> str | None:
    """Several enabled links to one netting slave need disjoint explicit symbol filters (after maps)."""
    if slave.margin_mode != "netting":
        return None
    pairs = [(lk, g) for lk, g in s.execute(
        select(CopyLink, CopyGroup).join(CopyGroup, CopyLink.group_id == CopyGroup.id).where(
            CopyLink.slave_id == slave.id, CopyLink.enabled.is_(True), CopyGroup.enabled.is_(True))).all()
        if lk.id != exclude_link_id and (extra is None or lk.id != extra[0].id)]
    if extra is not None:
        pairs.append(extra)
    return overlap_reason(s, slave, pairs)


def overlap_reason(s: Session, slave: Account, pairs: list[tuple[CopyLink, CopyGroup]]) -> str | None:
    if len(pairs) <= 1:
        return None
    seen: dict[str, int] = {}
    for lk, g in pairs:
        if not g.symbol_filter:
            return "several links to a netting slave need explicit, disjoint symbol filters"
        for sym in g.symbol_filter:
            local = resolve_symbol(s, slave.id, sym)
            if local in seen and seen[local] != lk.id:
                return f"symbol {local!r} is copied by more than one link to this netting slave"
            seen[local] = lk.id
    return None


def contract_size_conflict(s: Session, link: CopyLink, master: Account, slave: Account) -> str | None:
    """A map used by the link whose master/slave contract sizes differ needs `allow_contract_size_diff`."""
    if link.allow_contract_size_diff:
        return None
    maps = s.scalars(select(SymbolMap).where((SymbolMap.slave_id == slave.id) | SymbolMap.slave_id.is_(None)))
    for master_symbol in {m.master_symbol for m in maps}:
        local = resolve_symbol(s, slave.id, master_symbol)
        mspec = s.get(SymbolSpec, (master.id, master_symbol))
        sspec = s.get(SymbolSpec, (slave.id, local))
        if (mspec and sspec and mspec.contract_size and sspec.contract_size
                and Decimal(mspec.contract_size) != Decimal(sspec.contract_size)):
            return (f"contract size differs for {master_symbol}->{local} "
                    f"({mspec.contract_size} vs {sspec.contract_size}); set allow_contract_size_diff")
    return None


def link_problem(s: Session, link: CopyLink, group: CopyGroup, *, check_overlap: bool = True) -> str | None:
    master, slave = s.get(Account, link.master_id), s.get(Account, link.slave_id)
    if master is None or slave is None:
        return "unknown account"
    if master.role != "master" or slave.role != "slave":
        return "link must go from a master account to a slave account"
    if (reason := margin_conflict(master, slave)) is not None:
        return reason
    if not link.enabled:
        return None
    if creates_cycle(s, master, slave, exclude_link_id=link.id):
        return "copy cycle: the master is reachable from the slave through enabled links"
    if check_overlap and (reason := netting_overlap(s, slave, extra=(link, group))) is not None:
        return reason
    return contract_size_conflict(s, link, master, slave)


def revalidate_account_links(s: Session, acct: Account) -> list[int]:
    """On enroll (margin_mode known): disable conflicting links and emit `link.disabled_conflict` (S10)."""
    col = CopyLink.slave_id if acct.role == "slave" else CopyLink.master_id
    disabled = []
    rows = s.execute(select(CopyLink, CopyGroup).join(CopyGroup, CopyLink.group_id == CopyGroup.id)
                     .where(col == acct.id, CopyLink.enabled.is_(True)).order_by(CopyLink.id)).all()
    kept: dict[int, list[tuple[CopyLink, CopyGroup]]] = {}
    for link, group in rows:
        master, slave = s.get(Account, link.master_id), s.get(Account, link.slave_id)
        reason = margin_conflict(master, slave)
        if reason is None and slave.margin_mode == "netting":
            # Overlap among this account's links: older links win, newer conflicting ones are disabled.
            reason = overlap_reason(s, slave, [*kept.get(slave.id, []), (link, group)])
        if reason is None:
            kept.setdefault(slave.id, []).append((link, group))
        else:
            link.enabled = False
            link.disabled_reason = reason
            s.flush()
            s.add(Event(type="link.disabled_conflict", payload={"link_id": link.id, "reason": reason}))
            disabled.append(link.id)
    return disabled
