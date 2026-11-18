"""Optional Vertex Gemini REST adapter; model/project/region are explicitly supplied."""

import json
import logging
import random
import re
import time

from .contracts import NotConfigured, ProviderFailure
from .transport import Transport


def adc_token():
    # Optional dependencies only when making an authorized external request.
    import google.auth
    from google.auth.transport.requests import Request

    credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    credentials.refresh(Request())
    return credentials.token


UNAVAILABLE = "Model response unavailable or invalid"
# Vertex finishReason values are short upper-case enum names (MAX_TOKENS, SAFETY, ...).
FINISH = re.compile(r"[A-Z_]{1,40}")
# Vertex answers 429 when shared capacity or quota is momentarily exhausted. Retry once, only
# when the rejection came back quickly, so a call never waits much longer than its own timeout.
RETRY_REASON = "http_429"
RETRY_WINDOW_SECONDS = 5
RETRY_DELAY_SECONDS = (1.0, 2.0)
logger = logging.getLogger(__name__)


class VertexJSON:
    def __init__(
        self,
        project,
        location,
        model,
        *,
        token_provider=adc_token,
        transport=None,
        sleep=time.sleep,
    ):
        for value in (project, location, model):
            if not isinstance(value, str) or not re.fullmatch(
                r"[a-zA-Z0-9][a-zA-Z0-9.-]{0,100}", value
            ):
                raise ValueError("Explicit Vertex project, location and model ID required")
        host = (
            "aiplatform.googleapis.com"
            if location == "global"
            else f"{location}-aiplatform.googleapis.com"
        )
        self.url = f"https://{host}/v1/projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent"
        self.model = model
        self.tokens = token_provider
        self.transport = transport or Transport()
        self.sleep = sleep

    def generate(self, instruction, payload):
        # Fail before ADC token refresh when network is disabled.
        if isinstance(self.transport, Transport) and not self.transport.allow_network:
            raise NotConfigured("Vertex network disabled")
        body = {
            "systemInstruction": {"parts": [{"text": instruction}]},
            "contents": [
                {"role": "user", "parts": [{"text": json.dumps(payload, ensure_ascii=False)}]}
            ],
            "generationConfig": {
                "temperature": 0,
                "maxOutputTokens": 8192,
                "responseMimeType": "application/json",
            },
        }
        if self.model == "gemini-3.8-flash":
            del body["generationConfig"]["temperature"]
        raw = self.request(json.dumps(body, ensure_ascii=False).encode())
        try:
            candidate = json.loads(raw)["candidates"][0]
        except Exception:
            raise ProviderFailure(UNAVAILABLE, "model_no_candidate") from None
        finish = candidate.get("finishReason")
        if finish != "STOP":
            code = (
                finish.lower() if isinstance(finish, str) and FINISH.fullmatch(finish) else "other"
            )
            raise ProviderFailure(UNAVAILABLE, "model_incomplete_" + code)
        try:
            text = "".join(
                part.get("text", "")
                for part in candidate["content"]["parts"]
                if not part.get("thought", False)
            )
            result = json.loads(text)
        except Exception:
            raise ProviderFailure(UNAVAILABLE, "model_invalid_json") from None
        if not isinstance(result, dict):
            raise ProviderFailure(UNAVAILABLE, "model_invalid_json")
        return result

    def request(self, data):
        # One generic message for callers; the reason code says which step failed.
        started = time.monotonic()
        for attempt in (1, 2):
            try:
                return self.transport.request(
                    self.url,
                    headers={
                        "Authorization": "Bearer " + self.tokens(),
                        "Content-Type": "application/json",
                    },
                    body=data,
                )
            except ProviderFailure as error:
                quick = time.monotonic() - started <= RETRY_WINDOW_SECONDS
                if attempt == 1 and error.reason == RETRY_REASON and quick:
                    logger.warning("Vertex call throttled (%s); retrying once", error.reason)
                    self.sleep(random.uniform(*RETRY_DELAY_SECONDS))
                    continue
                raise ProviderFailure(UNAVAILABLE, "model_" + error.reason) from None
            except Exception:
                raise ProviderFailure(UNAVAILABLE, "model_auth_or_request") from None
