"""Issue short-lived WebGUI test credentials without logging secrets."""

from __future__ import annotations

import json
import os
import secrets
import tempfile
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


class CredentialSetupError(RuntimeError):
    """A typed secure-test credential setup failure."""


@dataclass(frozen=True)
class IssuedCredential:
    username: str
    password_file: Path
    expires_utc: datetime
    role: str

    def child_environment(self) -> dict[str, str]:
        return {
            "SIXGR_WEBGUI_TEST_USERNAME": self.username,
            "SIXGR_WEBGUI_TEST_PASSWORD_FILE": str(self.password_file),
        }


def issue(
    *,
    directory: Path | None = None,
    ttl_seconds: int = 900,
    role: str = "Operator",
) -> IssuedCredential:
    if ttl_seconds < 30:
        raise CredentialSetupError("credential TTL must be at least 30 seconds")
    if role not in {"Operator", "Viewer"}:
        raise CredentialSetupError("credential role must be Operator or Viewer")
    configured_root = os.environ.get(
        "SIXGR_WEBGUI_TEST_CREDENTIAL_DIR", ""
    ).strip()
    root = directory or (
        Path(configured_root)
        if configured_root
        else Path(tempfile.mkdtemp(prefix="sixgr-webgui-credential-"))
    )
    root.mkdir(parents=True, exist_ok=True)
    try:
        root.chmod(0o700)
    except OSError:
        pass
    username = "phase18-" + secrets.token_hex(8)
    password = secrets.token_urlsafe(48)
    expires = datetime.now(timezone.utc) + timedelta(seconds=ttl_seconds)
    path = root / f"credential-{username}.json"
    payload = {
        "schema_version": "sixgr-webgui-test-credential/v1",
        "username": username,
        "password": password,
        "role": role,
        "expires_utc": expires.isoformat(),
        "revoked": False,
    }
    descriptor = os.open(
        path,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL,
        0o600,
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
    except Exception:
        path.unlink(missing_ok=True)
        raise
    try:
        path.chmod(0o600)
    except OSError:
        pass
    return IssuedCredential(username, path, expires, role)


def load(path: Path, *, expected_username: str = "") -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CredentialSetupError("credential file is unavailable or invalid") from exc
    required = {"username", "password", "role", "expires_utc", "revoked"}
    if not required.issubset(payload):
        raise CredentialSetupError("credential file lacks required fields")
    if expected_username and payload["username"] != expected_username:
        raise CredentialSetupError("credential username does not match")
    if bool(payload["revoked"]):
        raise CredentialSetupError("credential has been revoked")
    try:
        expiry = datetime.fromisoformat(str(payload["expires_utc"]))
    except ValueError as exc:
        raise CredentialSetupError("credential expiry is invalid") from exc
    if expiry.tzinfo is None:
        raise CredentialSetupError("credential expiry must include a timezone")
    if expiry <= datetime.now(timezone.utc):
        raise CredentialSetupError("credential has expired")
    if not str(payload["password"]):
        raise CredentialSetupError("credential password is empty")
    return payload


def revoke(credential: IssuedCredential | Path) -> None:
    path = (
        credential.password_file
        if isinstance(credential, IssuedCredential)
        else credential
    )
    if path.exists():
        try:
            size = path.stat().st_size
            with path.open("r+b", buffering=0) as handle:
                handle.write(secrets.token_bytes(max(size, 1)))
                handle.flush()
                os.fsync(handle.fileno())
        finally:
            path.unlink(missing_ok=True)
    try:
        path.parent.rmdir()
    except OSError:
        pass


def redact(text: str, secrets_to_remove: list[str]) -> str:
    redacted = text
    for secret in secrets_to_remove:
        if secret:
            redacted = redacted.replace(secret, "[REDACTED]")
    return redacted
