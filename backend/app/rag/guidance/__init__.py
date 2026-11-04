"""Offline click-based academic guidance. No HTTP, database or model dependency."""

from .service import catalog, respond

__all__ = ["catalog", "respond"]
