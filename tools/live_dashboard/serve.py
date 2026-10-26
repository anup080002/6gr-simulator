"""Serve live-dashboard repairs without changing a running gate's frozen sources.

The existing dashboard remains the source of run data, authentication, routes
and exports. This launcher adds browser refresh fixes and briefly shares the
expensive OS process inventory between requests. It never launches MATLAB.
"""
from __future__ import annotations

from functools import wraps
from pathlib import Path
import sys
import threading
import time


ROOT = Path(__file__).absolute().parents[2]
FRONTEND = Path(__file__).with_name("frontend.js")
MARKER = "\n  hydrateCurrentPage();\n  setInterval(() => {"
PATCH_MARKER = "/* SixGR live dashboard refresh repair v1 */"


def inject_frontend(page: bytes, javascript: str) -> bytes:
    text = page.decode("utf-8")
    if PATCH_MARKER in text:
        return page
    if text.count(MARKER) != 1:
        raise ValueError("Dashboard frontend changed: expected one hydration entry point")
    # Insert inside the existing closure so the repair uses the exact selected
    # run and UI state, rather than a second, independent polling/render loop.
    return text.replace(MARKER, "\n" + PATCH_MARKER + "\n" + javascript + MARKER).encode("utf-8")


def shared_process_probe(probe, *, ttl=3.0, clock=time.monotonic):
    """Reuse actual process observations for at most three seconds, never forever.

    The original run-specific command-line matching remains authoritative.
    One /api/runs request previously started about sixteen PowerShell probes.
    This cache does not cache or alter any measurement, run outcome or artifact.
    """
    lock = threading.Lock()
    cached = None
    deadline = 0.0

    @wraps(probe)
    def get():
        nonlocal cached, deadline
        with lock:
            if cached is None or clock() >= deadline:
                observed = tuple(probe())
                cached = observed
                deadline = clock() + ttl
            return list(cached)

    return get


def install(dashboard):
    if getattr(dashboard, "_live_refresh_repair_installed", False):
        return
    javascript = FRONTEND.read_text(encoding="utf-8")
    original_page = dashboard.build_product_frontend_page

    @wraps(original_page)
    def page(*args, **kwargs):
        return inject_frontend(original_page(*args, **kwargs), javascript)

    dashboard.build_product_frontend_page = page
    dashboard.matlab_process_command_lines = shared_process_probe(dashboard.matlab_process_command_lines)
    dashboard._live_refresh_repair_installed = True


def main():
    sys.path.insert(0, str(ROOT / "apps"))
    import lls_web_dashboard as dashboard
    install(dashboard)
    print("Live refresh repair enabled; original simulator and dashboard sources unchanged.", flush=True)
    return dashboard.main()


if __name__ == "__main__":
    raise SystemExit(main())
