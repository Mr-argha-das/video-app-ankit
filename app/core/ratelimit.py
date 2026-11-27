"""Simple in-memory sliding-window rate limiter.

Keyed by (endpoint, identifier) — identifier can be a mobile number, IP or
user id. Keeps timestamps of recent hits in a dict and prunes old ones on each
check. Good enough for a single server; replace with Redis for multi-node.
"""
import time
from collections import defaultdict
from typing import Dict, List

from fastapi import HTTPException, status

# (endpoint, identifier) -> [timestamps]
_hits: Dict[str, List[float]] = defaultdict(list)


def _now() -> float:
    return time.time()


def check_rate(
    endpoint: str,
    identifier: str,
    limit: int,
    window_seconds: int,
) -> None:
    """Raise HTTP 429 if `identifier` has exceeded `limit` hits in the window."""
    key = f"{endpoint}:{identifier}"
    now = _now()
    window_start = now - window_seconds

    hits = [t for t in _hits[key] if t >= window_start]
    if len(hits) >= limit:
        retry_after = int(window_start + window_seconds - now) + 1
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Too many requests. Try again in {retry_after}s.",
            headers={"Retry-After": str(max(retry_after, 1))},
        )

    hits.append(now)
    _hits[key] = hits


def client_ip(request) -> str:
    """Best-effort real client IP (honors X-Forwarded-For behind a proxy)."""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return getattr(request.client, "host", "unknown") if request.client else "unknown"
