"""A minimal ACME client: a free Let's Encrypt certificate for a bare IP address (http-01, "shortlived" profile).

Let's Encrypt issues IP certificates only as short-lived ones (about 6 days), so the caller renews them while it runs.
Challenges are answered by whoever serves `challenges` on port 80 (see public.py).
"""
from __future__ import annotations

import base64
import datetime
import hashlib
import ipaddress
import json
import pathlib
import time
import urllib.error
import urllib.request
from typing import Any

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

PRODUCTION = "https://acme-v02.api.letsencrypt.org/directory"
STAGING = "https://acme-staging-v02.api.letsencrypt.org/directory"


class AcmeError(RuntimeError):
    pass


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _load_or_create_key(path: pathlib.Path) -> ec.EllipticCurvePrivateKey:
    if path.exists():
        return serialization.load_pem_private_key(path.read_bytes(), None)  # type: ignore[return-value]
    key = ec.generate_private_key(ec.SECP256R1())
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    return key


class Acme:
    def __init__(self, account_key: pathlib.Path, directory: str = PRODUCTION):
        self.key = _load_or_create_key(account_key)
        numbers = self.key.public_key().public_numbers()
        self.jwk = {"crv": "P-256", "kty": "EC", "x": b64(numbers.x.to_bytes(32, "big")), "y": b64(numbers.y.to_bytes(32, "big"))}
        self.thumbprint = b64(hashlib.sha256(json.dumps(self.jwk, sort_keys=True, separators=(",", ":")).encode()).digest())
        self.directory = json.loads(urllib.request.urlopen(directory, timeout=20).read())
        self.kid: str | None = None
        self.nonce: str | None = None

    def _new_nonce(self) -> str:
        request = urllib.request.Request(self.directory["newNonce"], method="HEAD")
        return urllib.request.urlopen(request, timeout=20).headers["Replay-Nonce"]

    def post(self, url: str, payload: Any | None, accept: str = "application/json") -> tuple[Any, Any]:
        """Signed POST (payload None = POST-as-GET). Returns (body, headers); retries once on badNonce."""
        for attempt in range(3):
            protected = {"alg": "ES256", "nonce": self.nonce or self._new_nonce(), "url": url}
            protected.update({"kid": self.kid} if self.kid else {"jwk": self.jwk})
            body64 = "" if payload is None else b64(json.dumps(payload).encode())
            signing_input = f"{b64(json.dumps(protected).encode())}.{body64}".encode()
            r, s = decode_dss_signature(self.key.sign(signing_input, ec.ECDSA(hashes.SHA256())))
            jws = {"protected": signing_input.decode().split(".")[0], "payload": body64,
                   "signature": b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))}
            request = urllib.request.Request(url, json.dumps(jws).encode(),
                                             {"Content-Type": "application/jose+json", "Accept": accept, "User-Agent": "lowey-mcp"})
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    self.nonce = response.headers.get("Replay-Nonce")
                    raw = response.read()
                    body = raw.decode() if accept != "application/json" else (json.loads(raw) if raw else {})
                    return body, response.headers
            except urllib.error.HTTPError as error:
                self.nonce = error.headers.get("Replay-Nonce")
                problem = json.loads(error.read() or b"{}")
                if problem.get("type", "").endswith("badNonce") and attempt < 2:
                    continue
                raise AcmeError(f"{problem.get('type', error.code)}: {problem.get('detail', '')}") from None
        raise AcmeError("too many bad nonces")

    def _poll(self, url: str, done: set[str], seconds: int = 90) -> dict[str, Any]:
        deadline = time.time() + seconds
        while True:
            body, _ = self.post(url, None)
            if body["status"] in done:
                return body
            if body["status"] == "invalid" or time.time() > deadline:
                detail = next((c.get("error", {}).get("detail") for c in body.get("challenges", []) if c.get("error")), None)
                raise AcmeError(detail or body.get("error", {}).get("detail") or f"stuck at '{body['status']}'")
            time.sleep(2)

    def issue_ip_certificate(self, ip: str, challenges: dict[str, str], key_path: pathlib.Path, cert_path: pathlib.Path) -> None:
        """Proves control of `ip` over http-01 (challenges[token] = key authorization, served on port 80) and saves the cert."""
        if self.kid is None:
            _, headers = self.post(self.directory["newAccount"], {"termsOfServiceAgreed": True})
            self.kid = headers["Location"]
        order, headers = self.post(self.directory["newOrder"],
                                   {"identifiers": [{"type": "ip", "value": ip}], "profile": "shortlived"})
        order_url = headers["Location"]
        for authz_url in order["authorizations"]:
            authz, _ = self.post(authz_url, None)
            if authz["status"] == "valid":
                continue
            challenge = next(c for c in authz["challenges"] if c["type"] == "http-01")
            challenges[challenge["token"]] = f"{challenge['token']}.{self.thumbprint}"
            self.post(challenge["url"], {})
            try:
                self._poll(authz_url, {"valid"})
            finally:
                challenges.pop(challenge["token"], None)
        cert_key = ec.generate_private_key(ec.SECP256R1())
        csr = (x509.CertificateSigningRequestBuilder().subject_name(x509.Name([]))
               .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address(ip))]), critical=False)
               .sign(cert_key, hashes.SHA256()))
        self.post(order["finalize"], {"csr": b64(csr.public_bytes(serialization.Encoding.DER))})
        order = self._poll(order_url, {"valid"})
        chain, _ = self.post(order["certificate"], None, accept="application/pem-certificate-chain")
        key_path.parent.mkdir(parents=True, exist_ok=True)
        key_path.write_bytes(cert_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                                    serialization.NoEncryption()))
        cert_path.write_text(chain, encoding="utf-8")


def expires_in(cert_path: pathlib.Path) -> datetime.timedelta:
    """Time left on a saved certificate (zero if there is none)."""
    if not cert_path.exists():
        return datetime.timedelta(0)
    cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
    return cert.not_valid_after_utc - datetime.datetime.now(datetime.timezone.utc)
