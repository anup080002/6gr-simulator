import io
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
WEBGUI_IMPLEMENTATION = REPO_ROOT / "apps" / "lls_web_dashboard.py"
WEBGUI_LAUNCHER = REPO_ROOT / "apps" / "start_lls_web_dashboard.ps1"
WEBGUI_REQUIREMENTS = REPO_ROOT / "apps" / "requirements-webgui.txt"
WEBGUI_ENV_EXAMPLE = REPO_ROOT / "apps" / ".env.example"
RETIRED_WEBGUI_ROOT = REPO_ROOT / "webgui"
RETIRED_EDGE_LAUNCHER = REPO_ROOT / "apps" / "start_lls_dashboard_edge_stack.ps1"

sys.path.insert(0, str(REPO_ROOT / "apps"))
import lls_web_dashboard as dash  # noqa: E402


def _wsgi_get(path: str) -> tuple[str, list[tuple[str, str]], str]:
    status_holder: dict[str, object] = {}

    def start_response(status: str, headers: list[tuple[str, str]]) -> None:
        status_holder["status"] = status
        status_holder["headers"] = headers

    body = b"".join(
        dash.dashboard_wsgi_app(
            {
                "REQUEST_METHOD": "GET",
                "PATH_INFO": path,
                "QUERY_STRING": "",
                "SERVER_PROTOCOL": "HTTP/1.1",
                "REMOTE_ADDR": "127.0.0.1",
                "REMOTE_PORT": "54321",
                "wsgi.input": io.BytesIO(b""),
                "CONTENT_LENGTH": "0",
                "CONTENT_TYPE": "",
            },
            start_response,
        )
    ).decode("utf-8", errors="replace")
    return (
        str(status_holder.get("status") or ""),
        list(status_holder.get("headers") or []),
        body,
    )


def test_repository_retains_one_webgui_implementation_and_launcher() -> None:
    assert WEBGUI_IMPLEMENTATION.is_file()
    assert WEBGUI_LAUNCHER.is_file()
    assert WEBGUI_REQUIREMENTS.is_file()
    assert WEBGUI_ENV_EXAMPLE.is_file()
    assert not RETIRED_WEBGUI_ROOT.exists()
    assert not RETIRED_EDGE_LAUNCHER.exists()

    launcher_text = WEBGUI_LAUNCHER.read_text(encoding="utf-8")
    assert "lls_web_dashboard.py" in launcher_text
    assert "requirements-webgui.txt" in launcher_text
    assert "5173" not in launcher_text
    assert "8000" not in launcher_text

    env_keys = {
        line.split("=", 1)[0].strip()
        for line in WEBGUI_ENV_EXAMPLE.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#") and "=" in line
    }
    assert {
        "MYSQL_HOST",
        "MYSQL_PORT",
        "MYSQL_USER",
        "MYSQL_PASSWORD",
        "MYSQL_DATABASE",
        "MYSQL_CONNECT_TIMEOUT",
        "SIXGR_DASHBOARD_HOST",
        "SIXGR_DASHBOARD_PORT",
        "SIXGR_DASHBOARD_SERVER",
        "SIXGR_DASHBOARD_THREADS",
    }.issubset(env_keys)
    assert {
        "HOST",
        "PORT",
        "RELOAD",
        "FRONTEND_ORIGINS",
        "MAX_CONCURRENT_RUNS",
    }.isdisjoint(env_keys)

    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    assert r".\apps\start_lls_web_dashboard.ps1" in readme
    assert "http://127.0.0.1:62906/" in readme
    assert "only `apps/lls_web_dashboard.py`" in readme


def test_profile_redirects_into_the_single_product_gui(monkeypatch) -> None:
    monkeypatch.setattr(dash, "DEFAULT_DASHBOARD_AUTH_MODE", "open")

    status, headers, body = _wsgi_get("/profile")

    assert status.startswith("303")
    assert dict(headers).get("Location") == "/home"
    assert body == ""


def test_protected_login_uses_the_compact_product_shell(monkeypatch) -> None:
    monkeypatch.setattr(dash, "DEFAULT_DASHBOARD_AUTH_MODE", "login")
    monkeypatch.setattr(
        dash,
        "USER_PROFILES",
        {
            "operator": {
                "username": "operator",
                "display_name": "Operator",
                "role": "Operator",
                "password": "not-used-by-this-render-test",
            }
        },
    )

    status, _headers, page = _wsgi_get("/login")

    assert status.startswith("200")
    assert page.lower().count("<!doctype html>") == 1
    assert page.count('<div class="app-shell" data-product-shell>') == 1
    assert page.count('<aside class="sidebar">') == 1
    assert page.count('<main id="productMain">') == 1
    assert '<form class="access-form" method="post" action="/login">' in page
    assert "<iframe" not in page.lower()
    assert "6G LLS Real-Time Console" not in page
    assert "Direct MySQL-backed monitoring" not in page
