"""Optional HTTP adapters; no model, endpoint, credential or network enabled by default."""

import http.client
import json
import math
import time
from typing import Protocol
from urllib.parse import urlsplit

from .budget import remaining_timeout
from .contracts import GeneratedAnswer, GroundingRequest
from .embeddings import unit_vector

ANSWER_SCHEMA = {
    "type": "object",
    "properties": {
        "answer": {"type": "string"},
        "citation_ids": {"type": "array", "items": {"type": "string"}},
        "insufficient_evidence": {"type": "boolean"},
    },
    "required": ["answer", "citation_ids", "insufficient_evidence"],
    "additionalProperties": False,
}


class ProviderError(ValueError):
    """Safe public diagnostic without provider bodies, questions or credentials."""


class InvalidGeneratorOutput(ValueError):
    pass


def strict_json(text: str) -> object:
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError("Duplicate JSON key")
            result[key] = value
        return result

    def invalid_constant(value):
        raise ValueError("Non-finite JSON number")

    return json.loads(text, object_pairs_hook=pairs, parse_constant=invalid_constant)


class JsonTransport(Protocol):
    identity: str

    def post(self, path: str, payload: dict) -> dict: ...


class HttpJsonTransport:
    """One bounded request, no retries, redirects or environment proxy forwarding."""

    def __init__(
        self,
        base_url: str,
        *,
        api_key: str | None = None,
        timeout_seconds: float = 12,
        allow_network: bool = False,
    ):
        url = urlsplit(base_url)
        local = url.hostname in ("localhost", "127.0.0.1", "::1")
        if (
            url.scheme not in ("https", "http")
            or not url.hostname
            or (url.scheme == "http" and not local)
            or url.username
            or url.password
            or url.query
            or url.fragment
            or any(c.isspace() for c in base_url)
        ):
            raise ValueError("Use HTTPS, or HTTP on loopback, without credentials/query/fragment")
        if (
            type(timeout_seconds) not in (int, float)
            or not math.isfinite(timeout_seconds)
            or not 0 < timeout_seconds <= 15
        ):
            raise ValueError("Provider timeout must be between 0 and 15 seconds")
        self.identity = base_url.rstrip("/")
        self._url = url
        self._key = api_key
        self.timeout = timeout_seconds
        self.allow_network = allow_network

    def post(self, path: str, payload: dict) -> dict:
        if not self.allow_network:
            raise ProviderError("Network is disabled; explicitly enable a configured provider")
        connection = None
        try:
            body = json.dumps(payload, ensure_ascii=False, allow_nan=False).encode()
            if len(body) > 256_000:
                raise ValueError("Request exceeds budget")
            if not path.startswith("/") or "?" in path or "#" in path:
                raise ValueError("Invalid endpoint path")
            factory = (
                http.client.HTTPSConnection
                if self._url.scheme == "https"
                else http.client.HTTPConnection
            )
            timeout = remaining_timeout(self.timeout)
            connection = factory(self._url.hostname, self._url.port, timeout=timeout)
            headers = {"Content-Type": "application/json", "Accept": "application/json"}
            if self._key:
                headers["Authorization"] = "Bearer " + self._key
            deadline = time.monotonic() + timeout
            connection.request("POST", self._url.path.rstrip("/") + path, body, headers)
            socket = connection.sock
            if socket:
                socket.settimeout(remaining_timeout(deadline - time.monotonic()))
            response = connection.getresponse()
            if response.status != 200:
                raise ValueError("Provider rejected request")
            parts, size = [], 0
            while True:
                remaining = remaining_timeout(deadline - time.monotonic())
                if remaining <= 0:
                    raise TimeoutError
                # read1 allows the deadline to be checked between socket reads.
                if socket:
                    socket.settimeout(remaining)
                part = response.read1(min(65536, 1_000_001 - size))
                if not part:
                    break
                parts.append(part)
                size += len(part)
                if size > 1_000_000:
                    raise ValueError("Provider response exceeds budget")
            remaining_timeout(deadline - time.monotonic())
            data = strict_json(b"".join(parts).decode("utf-8"))
            if not isinstance(data, dict):
                raise ValueError("Invalid provider response")
            return data
        except Exception:
            raise ProviderError("Provider request failed or exceeded its limits") from None
        finally:
            if connection:
                connection.close()


def parse_answer(text: str) -> GeneratedAnswer:
    try:
        if not isinstance(text, str) or len(text) > 32_000:
            raise ValueError
        data = strict_json(text)
        if not isinstance(data, dict) or set(data) != set(ANSWER_SCHEMA["required"]):
            raise ValueError
        if (
            not isinstance(data["answer"], str)
            or len(data["answer"]) > 8000
            or type(data["insufficient_evidence"]) is not bool
            or not isinstance(data["citation_ids"], list)
            or len(data["citation_ids"]) > 64
            or any(not isinstance(i, str) for i in data["citation_ids"])
        ):
            raise ValueError
        if data["insufficient_evidence"]:
            if data["answer"].strip() or data["citation_ids"]:
                raise ValueError
        elif not data["answer"].strip() or not data["citation_ids"]:
            raise ValueError
        return GeneratedAnswer(**data)
    except (ValueError, TypeError, KeyError):
        raise InvalidGeneratorOutput("Generator returned invalid structured output") from None


def validate_config(dialect: str, model: str):
    if dialect not in ("ollama", "openai-compatible"):
        raise ValueError("Unsupported provider dialect")
    if not isinstance(model, str) or not model.strip():
        raise ValueError("Explicit model name required")


class HttpAnswerGenerator:
    """Ollama chat or OpenAI-compatible Chat Completions with strict structured output."""

    def __init__(self, transport: JsonTransport, *, dialect: str, model: str):
        validate_config(dialect, model)
        self.transport, self.dialect, self.model = transport, dialect, model

    def generate(self, request: GroundingRequest) -> GeneratedAnswer:
        user = json.dumps(
            {
                "question": request.question,
                "context": request.context,
                "evidence": request.evidence,
            },
            ensure_ascii=False,
        )
        if len(user) > 48_000:
            raise ProviderError("Evidence exceeds the configured budget; it was not truncated")
        messages = [
            {
                "role": "system",
                "content": request.system_instruction + "\n"
                "JSON 스키마를 준수한다. 근거 부족이면 answer는 빈 문자열, "
                "citation_ids는 빈 배열이다.",
            },
            {"role": "user", "content": user},
        ]
        payload = {"model": self.model, "messages": messages, "stream": False}
        if self.dialect == "ollama":
            payload.update(format=ANSWER_SCHEMA, options={"temperature": 0, "num_predict": 1024})
            data = self.transport.post("/api/chat", payload)
            if data.get("done") is not True or data.get("done_reason") not in (None, "stop"):
                raise InvalidGeneratorOutput("Incomplete generation")
            message = data.get("message", {})
        else:
            payload.update(
                response_format={
                    "type": "json_schema",
                    "json_schema": {
                        "name": "school_answer",
                        "strict": True,
                        "schema": ANSWER_SCHEMA,
                    },
                },
                max_completion_tokens=1024,
                store=False,
            )
            data = self.transport.post("/chat/completions", payload)
            choices = data.get("choices")
            if (
                not isinstance(choices, list)
                or len(choices) != 1
                or choices[0].get("finish_reason") != "stop"
            ):
                raise InvalidGeneratorOutput("Incomplete generation")
            message = choices[0].get("message", {})
        if not isinstance(message, dict) or message.get("refusal") or message.get("tool_calls"):
            raise InvalidGeneratorOutput("Unsupported generator response")
        return parse_answer(message.get("content"))


class HttpEmbeddingProvider:
    def __init__(self, transport: JsonTransport, *, dialect: str, model: str):
        validate_config(dialect, model)
        self.transport, self.dialect, self.model = transport, dialect, model

    @property
    def model_id(self) -> str:
        return f"{self.dialect}:{self.transport.identity}:{self.model}"

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        result = []
        for start in range(0, len(texts), 16):
            batch = texts[start : start + 16]
            if any(not isinstance(t, str) or not t.strip() or len(t) > 16_000 for t in batch):
                raise ProviderError("Embedding text exceeds budget or is empty")
            payload = {"model": self.model, "input": batch}
            if self.dialect == "ollama":
                payload["truncate"] = False
                vectors = self.transport.post("/api/embed", payload).get("embeddings")
            else:
                payload["encoding_format"] = "float"
                data = self.transport.post("/embeddings", payload).get("data")
                if (
                    not isinstance(data, list)
                    or len(data) != len(batch)
                    or any(not isinstance(d, dict) or type(d.get("index")) is not int for d in data)
                    or {d["index"] for d in data} != set(range(len(batch)))
                ):
                    raise ProviderError("Invalid embedding indices")
                vectors = [d.get("embedding") for d in sorted(data, key=lambda d: d["index"])]
            if not isinstance(vectors, list) or len(vectors) != len(batch):
                raise ProviderError("Invalid embedding count")
            try:
                for vector in vectors:
                    if not isinstance(vector, list):
                        raise ValueError
                    result.append(unit_vector(vector, len(result[0]) if result else None))
            except (ValueError, TypeError):
                raise ProviderError("Invalid embedding vectors") from None
        return result

    def embed_query(self, text: str) -> list[float]:
        return self.embed_documents([text])[0]
