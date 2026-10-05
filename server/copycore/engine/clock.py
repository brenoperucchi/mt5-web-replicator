"""Server runtime clock for close detection (design 5.6, C4).

Absence and mass-guard timers use the server **monotonic** clock inside a **server epoch** (a new
value at every process start). An elapsed time measured in an earlier epoch is never reused: after
a restart the counters start again. Wall-clock time (`taken_at`) is never used for these timers.
"""

from __future__ import annotations

import time
import uuid


class Clock:
    def __init__(self) -> None:
        self.epoch = "e_" + uuid.uuid4().hex

    def monotonic(self) -> float:
        return time.monotonic()


class FakeClock(Clock):
    """Test clock: `advance()` moves the monotonic time; `restart()` simulates a new server process."""

    def __init__(self, start: float = 1000.0) -> None:
        super().__init__()
        self.t = start

    def monotonic(self) -> float:
        return self.t

    def advance(self, seconds: float) -> None:
        self.t += seconds

    def restart(self, start: float = 0.0) -> None:
        """Host reboot / process restart: new epoch, and the monotonic origin may go back."""
        self.epoch = "e_" + uuid.uuid4().hex
        self.t = start
