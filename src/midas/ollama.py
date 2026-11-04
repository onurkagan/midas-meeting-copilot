"""A small client for the local Ollama API (https://github.com/ollama/ollama/blob/main/docs/api.md)."""

import json
import logging
from collections.abc import Iterator

import httpx

log = logging.getLogger("midas.ollama")
logging.getLogger("httpx").setLevel(logging.WARNING)


class OllamaError(Exception):
    """Something the user can act on, worded for the panel."""


class Ollama:
    def __init__(self, url: str, keep_alive: str = "30m"):
        self.url = url
        self.keep_alive = keep_alive
        self._capabilities: dict[str, list[str]] = {}

    def _client(self, read: float) -> httpx.Client:
        return httpx.Client(base_url=self.url, timeout=httpx.Timeout(read, connect=2.0))

    @property
    def _unreachable(self) -> str:
        return f"Can't reach Ollama at {self.url}. Open the Ollama app (or run `ollama serve`) and try again."

    def reachable(self) -> bool:
        try:
            with self._client(2.0) as client:
                return client.get("/api/version").status_code == 200
        except httpx.HTTPError:
            return False

    def capabilities(self, model: str) -> list[str]:
        """What the model can do ("completion", "thinking", "embedding"…). Older Ollama
        versions don't say; then it is taken to be a chat model."""
        if model not in self._capabilities:
            with self._client(10.0) as client:
                response = client.post("/api/show", json={"model": model})
            if response.status_code != 200:
                return ["completion"]  # e.g. not pulled yet: ask again next time
            self._capabilities[model] = response.json().get("capabilities") or ["completion"]
        return self._capabilities[model]

    def models(self) -> list[dict]:
        """Installed models that can chat, by name; embedding-only models are left out."""
        try:
            with self._client(5.0) as client:
                tags = client.get("/api/tags").json().get("models", [])
        except (httpx.HTTPError, ValueError) as error:
            raise OllamaError(self._unreachable) from error
        models = []
        for tag in tags:
            name = tag.get("name") or tag.get("model")
            try:
                if "completion" not in self.capabilities(name):
                    continue
            except (httpx.HTTPError, ValueError):
                pass
            details = tag.get("details") or {}
            models.append(
                {
                    "name": name,
                    "size": tag.get("size", 0),
                    "parameters": details.get("parameter_size", ""),
                    "quantization": details.get("quantization_level", ""),
                }
            )
        return sorted(models, key=lambda model: model["name"])

    def load(self, model: str):
        """Loads the model into memory ahead of the first answer."""
        try:
            with self._client(300.0) as client:
                self._check(client.post("/api/generate", json={"model": model, "keep_alive": self.keep_alive}), model)
        except httpx.ConnectError as error:
            raise OllamaError(self._unreachable) from error
        except httpx.TimeoutException as error:
            raise OllamaError(f"Ollama took too long to load {model}.") from error

    def chat(self, model: str, messages: list[dict], context: int) -> Iterator[str]:
        """Streams the reply, piece by piece."""
        payload = {
            "model": model,
            "messages": messages,
            "stream": True,
            "keep_alive": self.keep_alive,
            "options": {"num_ctx": context, "temperature": 0.3},
        }
        try:
            if "thinking" in self.capabilities(model):
                # A live answer can't wait for long reasoning. gpt-oss can only lower it.
                payload["think"] = "low" if model.startswith("gpt-oss") else False
            with self._client(300.0) as client, client.stream("POST", "/api/chat", json=payload) as response:
                if response.status_code != 200:
                    response.read()
                    self._check(response, model)
                for line in response.iter_lines():
                    if not line:
                        continue
                    data = json.loads(line)
                    if data.get("error"):
                        raise OllamaError(f"Ollama: {data['error']}")
                    if piece := (data.get("message") or {}).get("content"):
                        yield piece
                    if data.get("done"):
                        return
        except httpx.ConnectError as error:
            raise OllamaError(self._unreachable) from error
        except httpx.TimeoutException as error:
            raise OllamaError(f"{model} took too long to answer.") from error
        except (httpx.HTTPError, ValueError) as error:
            raise OllamaError(f"Ollama: {error}") from error

    def _check(self, response: httpx.Response, model: str):
        if response.status_code == 200:
            return
        if response.status_code == 404:
            raise OllamaError(f"{model} isn't installed in Ollama. Run `ollama pull {model}`, or pick another model in ⚙︎.")
        try:
            message = response.json().get("error", "")
        except ValueError:
            message = response.text
        raise OllamaError(f"Ollama: {message or f'HTTP {response.status_code}'}")
