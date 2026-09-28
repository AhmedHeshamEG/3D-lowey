"""Talks to the 3D-lowey Bridge on the iPad (local network only).

The iPad shows its address and a 6-digit code (scene menu → "AI & laptop bridge…").
`lowey-link pair <ip:port> <code>` stores a token in ~/.lowey/config.json; everything else reuses it.
Environment overrides: LOWEY_HOST (e.g. 192.168.1.20:7717), LOWEY_TOKEN.
"""
from __future__ import annotations

import json
import os
import pathlib
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

CONFIG = pathlib.Path(os.environ.get("LOWEY_CONFIG", pathlib.Path.home() / ".lowey" / "config.json"))
DEFAULT_PORT = 7717


class BridgeError(RuntimeError):
    """The iPad answered with an error (the message says what to fix)."""


def load_config() -> dict[str, str]:
    config: dict[str, str] = {}
    if CONFIG.exists():
        config.update(json.loads(CONFIG.read_text(encoding="utf-8")))
    if os.environ.get("LOWEY_HOST"):
        config["host"] = os.environ["LOWEY_HOST"]
    if os.environ.get("LOWEY_TOKEN"):
        config["token"] = os.environ["LOWEY_TOKEN"]
    return config


def save_config(config: dict[str, str]) -> None:
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    CONFIG.write_text(json.dumps(config, indent=2), encoding="utf-8")


def normalize_host(host: str) -> str:
    host = host.strip().removeprefix("http://").rstrip("/")
    return host if ":" in host else f"{host}:{DEFAULT_PORT}"


class Bridge:
    def __init__(self, host: str | None = None, token: str | None = None, timeout: float = 200):
        config = load_config()
        self.host = normalize_host(host or config.get("host") or "")
        self.token = token or config.get("token")
        self.timeout = timeout
        if not self.host or self.host.startswith(":"):
            raise BridgeError("No iPad yet. Run: lowey-link pair <ipad-address> <code>")

    # -- plumbing -------------------------------------------------------------------------------------------------
    def request(self, method: str, path: str, body: bytes | None = None, query: dict[str, Any] | None = None,
                content_type: str = "application/json") -> tuple[bytes, str]:
        url = f"http://{self.host}{path}"
        if query:
            url += "?" + urllib.parse.urlencode({k: v for k, v in query.items() if v is not None})
        request = urllib.request.Request(url, data=body, method=method)
        request.add_header("Content-Type", content_type)
        request.add_header("X-Lowey-Client", os.environ.get("LOWEY_CLIENT", "Claude (lowey-mcp)"))
        if self.token:
            request.add_header("Authorization", f"Bearer {self.token}")
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return response.read(), response.headers.get("Content-Type", "")
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")
            try:
                detail = json.loads(detail).get("error", detail)
            except json.JSONDecodeError:
                pass
            raise BridgeError(f"{error.code}: {detail}") from None
        except urllib.error.URLError as error:
            raise BridgeError(f"Can't reach the iPad at {self.host} ({error.reason}). Is the bridge on, same Wi-Fi?") from None

    def get(self, path: str, **query: Any) -> Any:
        data, kind = self.request("GET", path, query=query or None)
        return json.loads(data) if "json" in kind else data.decode("utf-8")

    def post(self, path: str, payload: Any = None, **query: Any) -> Any:
        body = json.dumps(payload).encode("utf-8") if payload is not None else b"{}"
        data, kind = self.request("POST", path, body=body, query=query or None)
        return json.loads(data) if "json" in kind else data

    # -- API --------------------------------------------------------------------------------------------------------
    def pair(self, code: str) -> str:
        reply = self.post("/v1/pair", {"code": code})
        self.token = reply["token"]
        return self.token

    def status(self) -> dict:
        return self.get("/v1/status")

    def scene(self, depth: int = 2) -> dict:
        return self.get("/v1/scene", depth=depth)

    def look(self) -> dict:
        return self.get("/v1/look")

    def assets(self, query: str = "", limit: int = 40) -> list:
        return self.get("/v1/assets", q=query, limit=limit)

    def transcript(self) -> dict:
        return self.get("/v1/transcript")

    def actions_reference(self) -> str:
        return self.get("/v1/actions")

    def script(self, title: str, actions: list[dict], dry_run: bool = False) -> dict:
        return self.post("/v1/script", {"version": 2, "title": title, "actions": actions}, dryRun="1" if dry_run else None)

    def snapshot(self, framing: str = "16:9", long_side: int = 1280, camera: bool = True, time: float | None = None) -> bytes:
        payload: dict[str, Any] = {"framing": framing, "longSide": long_side, "camera": camera}
        if time is not None:
            payload["time"] = time
        data, _ = self.request("POST", "/v1/snapshot", body=json.dumps(payload).encode())
        return data

    def undo(self) -> dict:
        return self.post("/v1/undo")

    def renders(self) -> list[str]:
        return self.get("/v1/renders")

    def download_render(self, name: str) -> bytes:
        data, _ = self.request("GET", "/v1/renders/" + urllib.parse.quote(name))
        return data

    def import_file(self, path: pathlib.Path) -> dict:
        data, _ = self.request("POST", "/v1/library/import", body=path.read_bytes(), query={"name": path.name},
                               content_type="application/octet-stream")
        return json.loads(data)

    def import_audio(self, path: pathlib.Path, role: str = "voiceover") -> dict:
        data, _ = self.request("POST", "/v1/audio/import", body=path.read_bytes(), query={"name": path.name, "role": role},
                               content_type="application/octet-stream")
        return json.loads(data)


def describe(reply: dict) -> str:
    """A script reply as a few short lines (keeps tool results small)."""
    lines = []
    lines.append(("Applied. " if reply.get("applied") else "Not applied. ") + reply.get("message", ""))
    lines += [f"- {line}" for line in reply.get("preview", [])]
    created = reply.get("created") or {}
    if created:
        lines.append("Named: " + ", ".join(sorted(created)))
    return "\n".join(lines)
