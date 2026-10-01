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
            raise BridgeError("No iPad yet. Run: lowey-link pair")

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
            headers = {"Content-Type": content_type, "X-Lowey-Client": os.environ.get("LOWEY_CLIENT", "Claude (lowey-mcp)")}
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

    def import_media(self, path: pathlib.Path, at: float | None = None, placement: str = "card") -> dict:
        """A picture or video (a clip, a Manim render) into the open scene, playing from `at` seconds.
        placement "card": a thin card standing in the 3D world; "overlay": flat over the frame (transparent graphics)."""
        query: dict[str, Any] = {"name": path.name, "as": placement}
        if at is not None:
            query["at"] = at
        data, _ = self.request("POST", "/v1/media/import", body=path.read_bytes(), query=query, content_type="application/octet-stream")
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
