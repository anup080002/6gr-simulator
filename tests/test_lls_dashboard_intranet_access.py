from __future__ import annotations

from pathlib import Path
import sys


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    start_text = (REPO_ROOT / "apps" / "start_lls_web_dashboard.ps1").read_text(encoding="utf-8")
    assert 'else { "127.0.0.1" }' in start_text
    assert '$BindHost' in start_text, "Explicit intranet binding must remain configurable."
    assert '62906' in start_text
    assert 'New-NetFirewallRule' in start_text
    assert '--host' in start_text
    assert '--port' in start_text
    local_url, intranet_url, _ = dash.resolve_dashboard_urls("0.0.0.0", 62906, "10.64.253.106")
    assert local_url == "http://127.0.0.1:62906/"
    assert intranet_url == "http://10.64.253.106:62906/"
    assert dash.dashboard_browser_url("0.0.0.0", local_url, intranet_url, "10.64.253.106") == intranet_url
    assert dash.dashboard_browser_url("127.0.0.1", local_url, intranet_url, "") == local_url
    assert dash.dashboard_url_for_host("http://10.64.253.106:62906", 62906) == "http://10.64.253.106:62906/"


if __name__ == "__main__":
    main()
