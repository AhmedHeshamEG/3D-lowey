"""Talks to the 3D-lowey Bridge on the iPad (local network only; the bridge is off until it's turned on there).

On the iPad: Bridge ▸ Pair a laptop shows a one-time 6-digit code for a few minutes. `lowey-link pair <code>` finds the
iPad on the network (or `lowey-link pair <ip:port> <code>`), trades the code for a token and keeps it in
~/.lowey/config.json; everything else sends that token. The iPad lists paired laptops and can revoke them. If the iPad's
address changed (Wi-Fi gave it a new one), the client finds it again by Bonjour and remembers the new address.
Environment overrides: LOWEY_HOST (e.g. 192.168.1.20:7717), LOWEY_TOKEN.
"""
from __future__ import annotations

import http.client
import json
import os
import pathlib
import socket
import struct
import time
import urllib.parse
from typing import Any

CONFIG = pathlib.Path(os.environ.get("LOWEY_CONFIG", pathlib.Path.home() / ".lowey" / "config.json"))
DEFAULT_PORT = 7717
SERVICE = b"_hmm._tcp.local"
APP = "lowey"
# Connecting to an iPad on the same Wi-Fi takes milliseconds; if it hasn't answered in this long it isn't there
# (asleep, bridge off, new address). Replies can take much longer: a script waits for Hesham's OK on the iPad.
CONNECT_TIMEOUT = 2.5


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


def discover(timeout: float = 3.0) -> list[str]:
    """iPads with the 3D-lowey bridge on, as "ip:port": devices answering Bonjour for hmm-kit's `_hmm._tcp` whose
    `/v1/hello` says they are 3D-lowey (other hmm apps share the service type). Standard library only."""
    return [host for host in _mdns_hosts(timeout) if _is_lowey(host)]


def _mdns_hosts(timeout: float) -> list[str]:
    """One mDNS question for `_hmm._tcp` asking for a direct answer, repeated until something answers or `timeout`."""
    labels = b"".join(bytes([len(part)]) + part for part in SERVICE.split(b".")) + b"\0"
    # Header (id 0, one question), then PTR, class IN with the "answer me directly" bit.
    query = struct.pack(">HHHHHH", 0, 0, 1, 0, 0, 0) + labels + struct.pack(">HH", 12, 0x8001)
    found: list[str] = []
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    try:
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 255)
        sock.settimeout(0.4)
        sock.bind(("", 0))
        deadline = time.time() + timeout
        while time.time() < deadline:
            sock.sendto(query, ("224.0.0.251", 5353))
            try:
                while True:
                    data, (ip, _) = sock.recvfrom(9000)
                    address = f"{ip}:{DEFAULT_PORT}"
                    if b"_hmm" in data and address not in found:
                        found.append(address)
            except (socket.timeout, TimeoutError):
                pass
            if found:
                break
    except OSError:
        return found
    finally:
        sock.close()
    return found


def hello(host: str) -> dict:
    """What a bridge says about itself before pairing (app, version, device, whether a code is showing)."""
    name, _, port = normalize_host(host).rpartition(":")
    connection = http.client.HTTPConnection(name.strip("[]"), int(port), timeout=CONNECT_TIMEOUT)
    try:
        connection.request("GET", "/v1/hello")
        response = connection.getresponse()
        return json.loads(response.read()) if response.status == 200 else {}
    finally:
        connection.close()


def _is_lowey(host: str) -> bool:
    try:
        return hello(host).get("app") == APP
    except (OSError, ValueError):
        return False


def save_config(config: dict[str, str]) -> None:
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    CONFIG.write_text(json.dumps(config, indent=2), encoding="utf-8")


def normalize_host(host: str) -> str:
    host = host.strip().removeprefix("http://").rstrip("/")
    return host if ":" in host else f"{host}:{DEFAULT_PORT}"


class Bridge:
    def __init__(self, host: str | None = None, token: str | None = None, timeout: float = 200):
        config = load_config()
        # Only an address from the config may be looked up again (one given explicitly is used as is).
        self.rediscover = host is None and not os.environ.get("LOWEY_HOST")
        self.host = normalize_host(host or config.get("host") or "")
        self.token = token or config.get("token")
        self.timeout = timeout
        if not self.host or self.host.startswith(":"):
            raise BridgeError("No iPad yet. Run: hmm-bridge pair")

    # -- plumbing -------------------------------------------------------------------------------------------------
    def request(self, method: str, path: str, body: bytes | None = None, query: dict[str, Any] | None = None,
                content_type: str = "application/json") -> tuple[bytes, str]:
        target = path
        if query:
            target += "?" + urllib.parse.urlencode({k: v for k, v in query.items() if v is not None})
        try:
            status, data, kind = self._send(method, target, body, content_type)
        except OSError as error:
            if not (self.rediscover and self._find_again()):
                raise BridgeError(f"Can't reach the iPad at {self.host} ({error}). Is 3D-lowey open with the bridge on, "
                                  "on the same Wi-Fi?") from None
            try:
                status, data, kind = self._send(method, target, body, content_type)
            except OSError as again:
                raise BridgeError(f"Can't reach the iPad at {self.host} ({again}).") from None
        if status >= 400:
            detail = data.decode("utf-8", "replace")
            try:
                detail = json.loads(detail).get("error", detail)
            except (json.JSONDecodeError, AttributeError):
                pass
            raise BridgeError(f"{status}: {detail}")
        return data, kind

    def _send(self, method: str, target: str, body: bytes | None, content_type: str) -> tuple[int, bytes, str]:
        """One request on a plain socket: no proxy lookups (slow on Windows), a short connect, a long wait for the reply."""
        name, _, port = self.host.rpartition(":")
        connection = http.client.HTTPConnection(name.strip("[]"), int(port), timeout=CONNECT_TIMEOUT)
        try:
            connection.connect()
            connection.sock.settimeout(self.timeout)
            headers = {"Content-Type": content_type, "X-Lowey-Client": os.environ.get("LOWEY_CLIENT", "Claude (hmm-bridge)")}
            if self.token:
                headers["Authorization"] = f"Bearer {self.token}"
            connection.request(method, target, body=body, headers=headers)
            response = connection.getresponse()
            return response.status, response.read(), response.getheader("Content-Type", "")
        finally:
            connection.close()

    def _find_again(self) -> bool:
        """The saved address didn't answer: ask Bonjour where the iPad is now and remember it."""
        found = [host for host in discover(timeout=1.5) if host != self.host]
        if not found:
            return False
        self.host = found[0]
        config = load_config()
        config["host"] = self.host
        save_config(config)
        return True

    def get(self, path: str, **query: Any) -> Any:
        data, kind = self.request("GET", path, query=query or None)
        return json.loads(data) if "json" in kind else data.decode("utf-8")

    def post(self, path: str, payload: Any = None, **query: Any) -> Any:
        body = json.dumps(payload).encode("utf-8") if payload is not None else b"{}"
        data, kind = self.request("POST", path, body=body, query=query or None)
        return json.loads(data) if "json" in kind else data

    # -- API --------------------------------------------------------------------------------------------------------
    def pair(self, code: str, client: str | None = None) -> str:
        """Trades the one-time code shown on the iPad for this laptop's token (named so the iPad can list and revoke it)."""
        reply = self.post("/v1/pair", {"code": code, "client": client or socket.gethostname() or "A laptop"})
        self.token = reply["token"]
        return self.token

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

    # -- MCP v2 (the 16 tools) -------------------------------------------------------------------------------
    def status(self) -> dict:
        return self.get("/v2/status")

    def read_project(self) -> dict:
        return self.get("/v2/project")

    def transcript(self) -> dict:
        return self.get("/v2/transcript")

    def actions(self) -> str:
        return self.get("/v2/actions")

    def find_assets(self, query: str = "", set_name: str | None = None, limit: int = 12) -> list:
        return self.get("/v2/assets", q=query, set=set_name, limit=limit)

    def thumbnail(self, asset_id: str) -> bytes:
        data, _ = self.request("GET", "/v2/thumbnail", query={"id": asset_id})
        return data

    def build(self, actions: list[dict], title: str | None = None, dry_run: bool = False, views: list[str] | None = None,
              subject: str | None = None) -> dict:
        """Scene Script v3: one batch = one Proposal = one undo step. The reply has the diff and an observe of the result."""
        payload: dict[str, Any] = {"title": title or "From Claude", "actions": actions, "dry_run": dry_run}
        if views:
            payload["views"] = views
        if subject:
            payload["subject"] = subject
        return self.post("/v2/build", payload)

    def observe(self, time: float | None = None, views: list[str] | None = None, framing: str | None = None,
                subject: str | None = None, long_side: int = 1280) -> dict:
        payload = {"time": time, "views": views, "framing": framing, "subject": subject, "long_side": long_side}
        return self.post("/v2/observe", {k: v for k, v in payload.items() if v is not None})

    def contact_sheet(self, start: float | None = None, end: float | None = None, frames: int = 6, subject: str | None = None) -> dict:
        payload = {"from": start, "to": end, "frames": frames, "subject": subject}
        return self.post("/v2/contact_sheet", {k: v for k, v in payload.items() if v is not None})

    def commit(self, proposal_id: str | None = None, action: str = "commit", steps: int = 1) -> dict:
        payload: dict[str, Any] = {"action": action}
        if action == "commit":
            payload["proposal_id"] = proposal_id
        else:
            payload["steps"] = steps
        return self.post("/v2/commit", payload)

    def new_scene(self, name: str) -> dict:
        """A fresh scene in the open project, opened (the evals harness starts each brief this way)."""
        return self.post("/v2/scenes/new", {"name": name})

    def add_media(self, path: pathlib.Path, at: float | None = None, placement: str = "card") -> dict:
        """A picture or video (a clip, a Manim render) into the open scene, playing from `at` seconds.
        placement "card": a thin card standing in the 3D world; "overlay": flat over the frame (transparent graphics)."""
        query: dict[str, Any] = {"name": path.name, "as": placement, "at": at}
        data, _ = self.request("POST", "/v2/media", body=path.read_bytes(), query=query, content_type="application/octet-stream")
        return json.loads(data)


def describe_build(reply: dict) -> str:
    """A build reply in a few lines: applied or not, the diff, what the observe says (keeps tool results small)."""
    lines = [("Applied. " if reply.get("applied") else "Not applied. ") + reply.get("message", "")]
    if reply.get("proposal_id"):
        lines.append(f"proposal_id: {reply['proposal_id']}")
    lines += [f"- {line}" for line in reply.get("diff", [])]
    lines += [f"  · {line}" for line in reply.get("report", [])[:12]]
    observe = reply.get("observe") or {}
    if observe.get("summary"):
        lines.append("Observe: " + observe["summary"])
    return "\n".join(lines)
