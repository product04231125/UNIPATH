"""Request-local deadline shared by retrieval and generation HTTP calls."""

import time
from contextlib import contextmanager
from contextvars import ContextVar

_DEADLINE: ContextVar[float | None] = ContextVar("rag_deadline", default=None)


@contextmanager
def request_budget(seconds: float = 15):
    previous = _DEADLINE.get()
    deadline = time.monotonic() + seconds
    token = _DEADLINE.set(min(previous, deadline) if previous is not None else deadline)
    try:
        yield
    finally:
        _DEADLINE.reset(token)


def remaining_timeout(limit: float) -> float:
    deadline = _DEADLINE.get()
    remaining = min(limit, deadline - time.monotonic()) if deadline is not None else limit
    if remaining <= 0:
        raise TimeoutError("RAG request budget exhausted")
    return remaining
