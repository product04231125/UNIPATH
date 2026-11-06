"""Explicit network opt-in; bounded response, no redirect, no secret-bearing errors."""

from urllib.request import HTTPRedirectHandler, Request, build_opener

from .contracts import NotConfigured


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Transport:
    def __init__(self, *, allow_network=False, timeout=15):
        self.allow_network = allow_network
        self.timeout = timeout

    def request(self, url, *, headers=None, body=None):
        if not self.allow_network:
            raise NotConfigured("Network disabled")
        try:
            request = Request(url, headers=headers or {}, data=body)
            with build_opener(NoRedirect()).open(request, timeout=self.timeout) as response:
                data = response.read(2_000_001)
            if len(data) > 2_000_000:
                raise ValueError("Response too large")
            return data
        except Exception:
            raise RuntimeError("External provider request failed") from None
