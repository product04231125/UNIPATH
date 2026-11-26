"""Explicit network opt-in; bounded response, no redirect, no secret-bearing errors."""

import socket
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener

from .contracts import NotConfigured, ProviderFailure

FAILED = "External provider request failed"


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
        # Only the HTTP status or failure kind is kept; bodies and URLs may carry secrets.
        try:
            request = Request(url, headers=headers or {}, data=body)
            with build_opener(NoRedirect()).open(request, timeout=self.timeout) as response:
                data = response.read(2_000_001)
        except HTTPError as error:
            raise ProviderFailure(FAILED, f"http_{error.code}") from None
        except TimeoutError:
            raise ProviderFailure(FAILED, "timeout") from None
        except URLError as error:
            timed_out = isinstance(error.reason, (TimeoutError, socket.timeout))
            raise ProviderFailure(FAILED, "timeout" if timed_out else "network") from None
        except Exception:
            raise ProviderFailure(FAILED, "request_failed") from None
        if len(data) > 2_000_000:
            raise ProviderFailure(FAILED, "response_too_large")
        return data
