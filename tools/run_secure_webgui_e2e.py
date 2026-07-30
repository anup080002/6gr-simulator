"""Run the Phase-18 Playwright shard with a revocable file credential."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from webgui_test_credential_broker import (
    CredentialSetupError,
    issue,
    load,
    redact,
    revoke,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--run-tag", default="")
    parser.add_argument(
        "--target", default="tests/test_full_stack_webgui_e2e.py"
    )
    args = parser.parse_args()
    credential_root = os.environ.get(
        "SIXGR_WEBGUI_TEST_CREDENTIAL_DIR", ""
    ).strip()
    if not credential_root:
        raise CredentialSetupError(
            "SIXGR_WEBGUI_TEST_CREDENTIAL_DIR must be shared with the "
            "secured dashboard process"
        )
    credential = issue(directory=Path(credential_root))
    password = ""
    try:
        payload = load(
            credential.password_file,
            expected_username=credential.username,
        )
        password = str(payload["password"])
        environment = os.environ.copy()
        environment.update(credential.child_environment())
        environment["SIXGR_WEBGUI_BASE_URL"] = args.base_url
        if args.run_tag:
            environment["SIXGR_WEBGUI_RUN_TAG"] = args.run_tag
        completed = subprocess.run(
            [sys.executable, "-m", "pytest", "-q", args.target],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
            env=environment,
        )
        sys.stdout.write(redact(completed.stdout, [password]))
        return completed.returncode
    finally:
        revoke(credential)


if __name__ == "__main__":
    raise SystemExit(main())
