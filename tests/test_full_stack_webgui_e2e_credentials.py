from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "tools"))

from webgui_test_credential_broker import (  # noqa: E402
    CredentialSetupError,
    issue,
    load,
    redact,
    revoke,
)
sys.path.insert(0, str(REPO_ROOT / "apps"))
import lls_web_dashboard as dashboard  # noqa: E402

pytestmark = pytest.mark.webgui_unit


def test_ephemeral_credential_is_file_backed_and_revocable(
    tmp_path: Path,
) -> None:
    credential = issue(directory=tmp_path / "private", ttl_seconds=60)
    payload = load(
        credential.password_file,
        expected_username=credential.username,
    )
    assert payload["role"] == "Operator"
    assert payload["password"] not in repr(credential)
    environment = credential.child_environment()
    assert "PASSWORD" not in environment.get(
        "SIXGR_WEBGUI_TEST_USERNAME", ""
    )
    assert "SIXGR_WEBGUI_TEST_PASSWORD" not in environment
    revoke(credential)
    assert not credential.password_file.exists()
    with pytest.raises(CredentialSetupError, match="unavailable"):
        load(credential.password_file)


def test_expired_and_viewer_credentials_fail_closed(tmp_path: Path) -> None:
    credential = issue(directory=tmp_path / "expired", ttl_seconds=60)
    payload = json.loads(
        credential.password_file.read_text(encoding="utf-8")
    )
    payload["expires_utc"] = (
        datetime.now(timezone.utc) - timedelta(seconds=1)
    ).isoformat()
    credential.password_file.write_text(
        json.dumps(payload), encoding="utf-8"
    )
    with pytest.raises(CredentialSetupError, match="expired"):
        load(credential.password_file)
    revoke(credential)

    viewer = issue(
        directory=tmp_path / "viewer",
        ttl_seconds=60,
        role="Viewer",
    )
    viewer_payload = load(viewer.password_file)
    assert viewer_payload["role"] == "Viewer"
    assert not dashboard.user_profile_can_mutate(viewer_payload)
    assert not dashboard.operator_authorized_for_route(
        viewer_payload, "/run/stop"
    )
    assert not dashboard.operator_authorized_for_route(
        viewer_payload, "/admin/delete-run"
    )
    revoke(viewer)


def test_secret_redaction_removes_password_and_token(tmp_path: Path) -> None:
    credential = issue(directory=tmp_path / "redaction", ttl_seconds=60)
    payload = load(credential.password_file)
    token = "session-" + str(payload["password"])[:12]
    raw = f"password={payload['password']} authorization={token}"
    sanitized = redact(raw, [str(payload["password"]), token])
    assert str(payload["password"]) not in sanitized
    assert token not in sanitized
    assert sanitized.count("[REDACTED]") == 2
    revoke(credential)


def test_dashboard_resolves_and_revokes_ephemeral_operator(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = tmp_path / "server-credentials"
    monkeypatch.setenv("SIXGR_WEBGUI_TEST_CREDENTIAL_DIR", str(root))
    credential = issue(directory=root, ttl_seconds=60)
    payload = load(credential.password_file)
    profile = dashboard.resolve_dashboard_login_profile(
        credential.username, str(payload["password"])
    )
    assert profile is not None
    assert dashboard.user_profile_can_mutate(profile)
    assert dashboard.operator_authorized_for_route(profile, "/run")
    assert not dashboard.resolve_dashboard_login_profile(
        credential.username, "wrong-password"
    )
    revoke(credential)
    assert dashboard.clone_user_profile(credential.username) is None
