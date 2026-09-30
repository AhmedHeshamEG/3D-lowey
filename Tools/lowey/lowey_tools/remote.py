"""lowey-mcp over HTTP: a local URL for MCP clients on this laptop, or a tunnelled public one (see public.py for direct HTTPS).

  lowey-mcp --http              http://127.0.0.1:8765/mcp (localhost only)
  lowey-mcp --tunnel            the same server behind a Cloudflare quick tunnel: https://<random>.trycloudflare.com/<secret>/mcp
  lowey-mcp --own-tunnel        public mode behind a tunnel you run yourself (named Cloudflare tunnel, ngrok…)

The iPad bridge stays LAN-only; the laptop is the one talking to it. The public URL is guarded by a secret path segment
(kept in ~/.lowey/config.json as "mcp_secret"; `--new-secret` rotates it) and Hesham still approves every change on the iPad.
"""
from __future__ import annotations

import os
import pathlib
import re
import secrets
import shutil
import subprocess
import sys
import threading

from .client import load_config, save_config

DEFAULT_HTTP_PORT = 8765
QUICK_TUNNEL = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")


def mcp_secret(rotate: bool = False) -> str:
    config = load_config()
    if rotate or not config.get("mcp_secret"):
        config["mcp_secret"] = secrets.token_urlsafe(18)
        save_config(config)
    return config["mcp_secret"]


def find_cloudflared() -> str | None:
    candidates = [
        os.environ.get("LOWEY_CLOUDFLARED"),
        shutil.which("cloudflared"),
        r"C:\Program Files (x86)\cloudflared\cloudflared.exe",
        r"C:\Program Files\cloudflared\cloudflared.exe",
        str(pathlib.Path.home() / ".lowey/bin/cloudflared.exe"),
        str(pathlib.Path.home() / "AppData/Local/Microsoft/WinGet/Links/cloudflared.exe"),
    ]
    return next((path for path in candidates if path and pathlib.Path(path).is_file()), None)


def start_tunnel(port: int, path: str) -> subprocess.Popen[str]:
    """Starts a Cloudflare quick tunnel (no account needed) and prints the public URL once it is up."""
    binary = find_cloudflared()
    if binary is None:
        sys.exit("cloudflared not found. Install it (winget install Cloudflare.cloudflared), put cloudflared.exe in ~/.lowey/bin, or set LOWEY_CLOUDFLARED")
    tunnel = subprocess.Popen(
        [binary, "tunnel", "--no-autoupdate", "--url", f"http://127.0.0.1:{port}"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
    )

    def watch() -> None:
        announced = False
        for line in tunnel.stdout or []:
            match = QUICK_TUNNEL.search(line)
            if match and not announced:
                announced = True
                print(f"\n  Public MCP URL (claude.ai > Settings > Connectors > Add custom connector):\n"
                      f"    {match.group(0)}{path}\n", flush=True)
            elif "ERR" in line:
                print(f"  cloudflared: {line.strip()}", flush=True)
        if not announced:
            print("  cloudflared exited before the tunnel came up.", flush=True)

    threading.Thread(target=watch, daemon=True).start()
    return tunnel


def serve(mcp, *, port: int, public: bool, rotate_secret: bool, own_tunnel: bool = False) -> None:
    import anyio
    from mcp.server.transport_security import TransportSecuritySettings

    if public:
        path = f"/{mcp_secret(rotate_secret)}/mcp"
        # The tunnel's Host header is *.trycloudflare.com, so the localhost-only check can't apply; the secret path guards it.
        security = TransportSecuritySettings(enable_dns_rebinding_protection=False)
    else:
        path = "/mcp"
        security = None  # the SDK turns on DNS-rebinding protection for 127.0.0.1

    print(f"  Local MCP URL:  http://127.0.0.1:{port}{path}", flush=True)
    if own_tunnel:
        print(f"  Point your tunnel at http://127.0.0.1:{port}; the connector URL is https://<your tunnel host>{path}", flush=True)
    tunnel = start_tunnel(port, path) if public and not own_tunnel else None
    try:
        anyio.run(lambda: mcp.run_streamable_http_async(
            host="127.0.0.1", port=port, streamable_http_path=path, stateless_http=True, transport_security=security,
        ))
    except KeyboardInterrupt:
        pass
    finally:
        if tunnel:
            tunnel.terminate()
