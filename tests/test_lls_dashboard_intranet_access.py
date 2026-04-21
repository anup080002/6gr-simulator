from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    start_text = (REPO_ROOT / "apps" / "start_lls_web_dashboard.ps1").read_text(encoding="utf-8")
    assert '0.0.0.0' in start_text
    assert '62906' in start_text
    assert 'New-NetFirewallRule' in start_text
    assert '--host' in start_text
    assert '--port' in start_text


if __name__ == "__main__":
    main()
