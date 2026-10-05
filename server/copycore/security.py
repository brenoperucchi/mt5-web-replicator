"""Token and enrollment-code primitives (D8). Secrets are only ever stored as HMAC digests."""

from __future__ import annotations

import hashlib
import hmac
import logging
import re
import secrets

TOKEN_PREFIX = "cct_"  # noqa: S105
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # base32-like, no 0/O/1/I
CODE_LENGTH = 10


def hmac_hex(pepper: str, value: str) -> str:
    return hmac.new(pepper.encode(), value.encode(), hashlib.sha256).hexdigest()


def new_token() -> str:
    return TOKEN_PREFIX + secrets.token_urlsafe(32)


def new_enroll_code() -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))


def normalize_code(code: str) -> str:
    return re.sub(r"[\s-]", "", code).upper()


def normalize_server(name: str) -> str:
    """Normalized broker server name used for identity comparisons."""
    return re.sub(r"\s+", " ", name.strip()).lower()


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


_REDACT_PATTERNS = (
    re.compile(r"(?i)(authorization\s*[:=]\s*)(bearer\s+)?\S+"),
    re.compile(r'(?i)("?(?:new_token|token|code)"?\s*[:=]\s*"?)[^",\s}]+'),
    re.compile(re.escape(TOKEN_PREFIX) + r"[A-Za-z0-9_\-]+"),
)


def redact(text: str) -> str:
    for pat in _REDACT_PATTERNS:
        text = pat.sub(lambda m: (m.group(1) if m.groups() else "") + "[REDACTED]", text)
    return text


class RedactingFilter(logging.Filter):
    """Redacts `token`, `new_token`, `Authorization` and token-shaped strings from log records (D8.6)."""

    def filter(self, record: logging.LogRecord) -> bool:
        try:
            msg = record.getMessage()
        except Exception:  # noqa: BLE001
            return True
        red = redact(msg)
        if red != msg:
            record.msg, record.args = red, None
        return True


def install_log_redaction() -> None:
    flt = RedactingFilter()
    for name in ("", "copycore", "uvicorn", "uvicorn.access", "uvicorn.error"):
        logger = logging.getLogger(name)
        if not any(isinstance(f, RedactingFilter) for f in logger.filters):
            logger.addFilter(flt)
