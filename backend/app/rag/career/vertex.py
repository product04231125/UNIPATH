"""Optional Vertex Gemini REST adapter; model/project/region are explicitly supplied."""

import json
import re

from .contracts import NotConfigured
from .transport import Transport


def adc_token():
    # Optional dependencies only when making an authorized external request.
    import google.auth
    from google.auth.transport.requests import Request

    credentials, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    credentials.refresh(Request())
    return credentials.token


class VertexJSON:
    def __init__(self, project, location, model, *, token_provider=adc_token, transport=None):
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
        self.tokens = token_provider
        self.transport = transport or Transport()

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
        try:
            raw = self.transport.request(
                self.url,
                headers={
                    "Authorization": "Bearer " + self.tokens(),
                    "Content-Type": "application/json",
                },
                body=json.dumps(body, ensure_ascii=False).encode(),
            )
            candidate = json.loads(raw)["candidates"][0]
            if candidate.get("finishReason") != "STOP":
                raise ValueError("Incomplete model output")
            text = "".join(
                part.get("text", "")
                for part in candidate["content"]["parts"]
                if not part.get("thought", False)
            )
            result = json.loads(text)
            if not isinstance(result, dict):
                raise ValueError("Expected JSON object")
            return result
        except Exception:
            raise RuntimeError("Model response unavailable or invalid") from None
