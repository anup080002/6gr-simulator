from __future__ import annotations

import io
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "apps"))

import lls_web_dashboard as dash  # noqa: E402


def main() -> None:
    assert dash.resolve_server_backend("threading") == "threading"
    assert dash.resolve_server_backend("auto") in {"threading", "waitress"}

    status_holder: dict[str, object] = {}

    def start_response(status: str, headers: list[tuple[str, str]]) -> None:
        status_holder["status"] = status
        status_holder["headers"] = headers

    environ = {
        "REQUEST_METHOD": "GET",
        "PATH_INFO": "/login",
        "QUERY_STRING": "",
        "SERVER_PROTOCOL": "HTTP/1.1",
        "REMOTE_ADDR": "127.0.0.1",
        "REMOTE_PORT": "54321",
        "wsgi.input": io.BytesIO(b""),
        "CONTENT_LENGTH": "0",
        "CONTENT_TYPE": "",
    }
    body = b"".join(dash.dashboard_wsgi_app(environ, start_response)).decode("utf-8", errors="replace")
    status = str(status_holder.get("status", ""))
    if dash.auth_mode_open():
        assert status.startswith("303")
        assert ("/home" in str(status_holder.get("headers", "")))
    else:
        assert status.startswith("200")
        assert "Sign in" in body or "Sign In" in body

    nginx_template = (REPO_ROOT / "apps" / "deploy" / "nginx" / "lls_dashboard_proxy_cache.conf.template").read_text(encoding="utf-8")
    assert "proxy_cache_path" in nginx_template
    assert "location /artifact/" in nginx_template
    assert "__BACKEND_PORT__" in nginx_template
    assert "__FRONTEND_PORT__" in nginx_template

    stack_script = (REPO_ROOT / "apps" / "start_lls_dashboard_edge_stack.ps1").read_text(encoding="utf-8")
    assert "start_lls_web_dashboard.ps1" in stack_script
    assert "nginx.exe" in stack_script
    assert "proxy_cache" in nginx_template

    dashboard_text = (REPO_ROOT / "apps" / "lls_web_dashboard.py").read_text(encoding="utf-8")
    assert 'target="_blank" rel="noopener noreferrer"' in dashboard_text
    assert "Open In New Tab" in dashboard_text
    assert "function waveformArtifactPanel()" in dashboard_text
    assert "dashboard_wsgi_app" in dashboard_text


if __name__ == "__main__":
    main()
