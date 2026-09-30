"""lowey-mcp --public: the MCP server on this laptop's own public IP, over HTTPS, with no tunnel or relay service.

1. Finds the public IP (router via UPnP, else a what's-my-IP lookup; `--ip` overrides, IPv6 works too).
2. Opens ports 80 and 443 on the router with UPnP when the router allows it; otherwise prints what to forward once.
3. Gets a free Let's Encrypt certificate for that IP (answered on port 80) and renews it while running (they last ~6 days).
4. Serves https://<ip>/<secret>/mcp. The secret path is the lock; Hesham still approves every change on the iPad.
"""
from __future__ import annotations

import http.server
import ipaddress
import pathlib
import re
import socket
import threading
import time
import urllib.request

from . import acme

TLS_DIR = pathlib.Path.home() / ".lowey" / "tls"
RENEW_BEFORE_HOURS = 48


# -- Network ----------------------------------------------------------------------------------------------------------

def lan_ip() -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.connect(("192.0.2.1", 9))  # no packet is sent; this just picks the outgoing interface
        return probe.getsockname()[0]


class Upnp:
    """Just enough UPnP IGD to read the WAN address and forward ports."""

    def __init__(self) -> None:
        self.control: tuple[str, str] | None = None
        search = ("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\n"
                  "ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n").encode()
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(3)
            sock.sendto(search, ("239.255.255.250", 1900))
            try:
                data, _ = sock.recvfrom(4096)
            except OSError:
                return
        location = re.search(rb"(?i)location:\s*(\S+)", data)
        if not location:
            return
        url = location.group(1).decode()
        try:
            xml = urllib.request.urlopen(url, timeout=3).read().decode(errors="replace")
        except OSError:
            return
        found = re.search(r"<serviceType>(urn:schemas-upnp-org:service:WAN(?:IP|PPP)Connection:\d)</serviceType>.*?"
                          r"<controlURL>([^<]+)</controlURL>", xml, re.S)
        if found:
            base = re.match(r"https?://[^/]+", url).group(0)  # type: ignore[union-attr]
            control = found.group(2)
            self.control = (found.group(1), control if control.startswith("http") else base + "/" + control.lstrip("/"))

    def _call(self, action: str, arguments: str = "") -> str:
        assert self.control
        service, url = self.control
        body = (f'<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
                f's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:{action} xmlns:u="{service}">'
                f"{arguments}</u:{action}></s:Body></s:Envelope>")
        request = urllib.request.Request(url, body.encode(), {"Content-Type": 'text/xml; charset="utf-8"',
                                                              "SOAPAction": f'"{service}#{action}"'})
        return urllib.request.urlopen(request, timeout=5).read().decode(errors="replace")

    def external_ip(self) -> str | None:
        try:
            found = re.search(r"<NewExternalIPAddress>([^<]+)", self._call("GetExternalIPAddress"))
            return found.group(1) if found else None
        except OSError:
            return None

    def forward(self, port: int, to_ip: str) -> bool:
        try:
            self._call("AddPortMapping",
                       f"<NewRemoteHost></NewRemoteHost><NewExternalPort>{port}</NewExternalPort><NewProtocol>TCP</NewProtocol>"
                       f"<NewInternalPort>{port}</NewInternalPort><NewInternalClient>{to_ip}</NewInternalClient>"
                       "<NewEnabled>1</NewEnabled><NewPortMappingDescription>lowey-mcp</NewPortMappingDescription>"
                       "<NewLeaseDuration>0</NewLeaseDuration>")
            return True
        except OSError:
            return False


def public_ip(upnp: Upnp) -> str:
    return (upnp.external_ip() if upnp.control else None) or \
        urllib.request.urlopen("https://api.ipify.org", timeout=10).read().decode().strip()


def dual_stack_socket(port: int) -> socket.socket:
    """One listening socket for IPv4 and IPv6 (Windows makes IPv6 sockets v6-only by default)."""
    sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("::", port))
    sock.listen(128)
    return sock


# -- Port 80: ACME challenges -----------------------------------------------------------------------------------------

def serve_challenges(challenges: dict[str, str]) -> None:
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            token = self.path.removeprefix("/.well-known/acme-challenge/")
            answer = challenges.get(token) if self.path.startswith("/.well-known/acme-challenge/") else None
            self.send_response(200 if answer else 404)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write((answer or "").encode())

        def log_message(self, *args) -> None:  # quiet
            pass

    server = http.server.ThreadingHTTPServer(("", 80), Handler, bind_and_activate=False)
    server.socket.close()
    server.socket = dual_stack_socket(80)
    threading.Thread(target=server.serve_forever, daemon=True).start()


# -- Certificate ------------------------------------------------------------------------------------------------------

def ensure_certificate(ip: str, challenges: dict[str, str], staging: bool) -> tuple[pathlib.Path, pathlib.Path]:
    folder = TLS_DIR / ("staging" if staging else "production") / ip.replace(":", "_")
    key, cert = folder / "key.pem", folder / "cert.pem"
    if acme.expires_in(cert).total_seconds() > RENEW_BEFORE_HOURS * 3600:
        return key, cert
    print(f"  Getting a Let's Encrypt certificate for {ip}{' (staging)' if staging else ''}...", flush=True)
    client = acme.Acme(TLS_DIR / f"account-{'staging' if staging else 'production'}.pem",
                       acme.STAGING if staging else acme.PRODUCTION)
    client.issue_ip_certificate(ip, challenges, key, cert)
    print(f"  Certificate ready (valid {acme.expires_in(cert).days} days, renewed automatically).", flush=True)
    return key, cert


def url_for(ip: str, port: int, path: str) -> str:
    host = f"[{ip}]" if ipaddress.ip_address(ip).version == 6 else ip
    return f"https://{host}{'' if port == 443 else f':{port}'}{path}"


# -- Serving ----------------------------------------------------------------------------------------------------------

def serve(mcp, *, path: str, port: int, ip: str | None, staging: bool) -> None:
    import uvicorn
    from mcp.server.transport_security import TransportSecuritySettings

    upnp = Upnp()
    ip = ip or public_ip(upnp)
    local = lan_ip()
    if ipaddress.ip_address(ip).version == 4:
        if upnp.control and all(upnp.forward(p, local) for p in (80, port)):
            print(f"  Router: ports 80 and {port} forwarded to this laptop ({local}) via UPnP.", flush=True)
        else:
            print(f"  Router: couldn't open ports automatically (UPnP is off or refused). Once, in the router settings, forward\n"
                  f"          TCP 80 and TCP {port} to {local}   (Freebox: http://mafreebox.freebox.fr > Settings > Port "
                  f"forwarding, or turn on UPnP IGD there and this becomes automatic).", flush=True)
    else:
        print("  Using IPv6: no port forwarding, but the router's IPv6 firewall must allow incoming 80 and "
              f"{port} (Freebox: IPv6 firewall off).", flush=True)
    print("  Windows may ask to allow Python through the firewall: allow it.", flush=True)

    challenges: dict[str, str] = {}
    serve_challenges(challenges)
    try:
        key, cert = ensure_certificate(ip, challenges, staging)
    except acme.AcmeError as error:
        raise SystemExit(f"\n  Let's Encrypt couldn't reach http://{ip}:80 from the internet: {error}\n"
                         "  Check the port forwarding (or IPv6 firewall) above, then run again.") from None

    app = mcp.streamable_http_app(streamable_http_path=path, stateless_http=True,
                                  transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False))
    config = uvicorn.Config(app, ssl_keyfile=str(key), ssl_certfile=str(cert), log_level="warning")
    config.load()

    def renew() -> None:
        while True:
            time.sleep(3600)
            try:
                new_key, new_cert = ensure_certificate(ip, challenges, staging)
                config.ssl.load_cert_chain(str(new_cert), str(new_key))  # new connections get the new certificate
            except Exception as error:  # noqa: BLE001 - keep serving the old one and try again in an hour
                print(f"  Renewal failed, will retry: {error}", flush=True)

    threading.Thread(target=renew, daemon=True).start()
    print(f"\n  Public MCP URL (claude.ai > Settings > Connectors > Add custom connector):\n    {url_for(ip, port, path)}\n"
          "  Keep this window open. Ctrl+C stops it.\n", flush=True)
    uvicorn.Server(config).run(sockets=[dual_stack_socket(port)])
