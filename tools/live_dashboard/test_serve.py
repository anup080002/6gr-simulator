from concurrent.futures import ThreadPoolExecutor
import importlib.util
from pathlib import Path
import threading

import pytest

spec = importlib.util.spec_from_file_location("live_dashboard_serve", Path(__file__).with_name("serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)


def test_injection_is_inside_hydration_closure_and_idempotent():
    page = ("before" + serve.MARKER + "\nafter").encode()
    result = serve.inject_frontend(page, "const repair = true;")
    assert result.index(b"const repair") < result.index(b"hydrateCurrentPage();")
    assert serve.inject_frontend(result, "ignored") == result
    with pytest.raises(ValueError):
        serve.inject_frontend(b"changed frontend", "repair")
    with pytest.raises(ValueError):
        serve.inject_frontend(page + page, "repair")


def test_hydration_marker_matches_only_startup_not_navigation_calls():
    # Python normalizes the module's Windows newlines before creating its HTML string.
    original = (serve.ROOT / "apps/lls_web_dashboard.py").read_text(encoding="utf-8").encode()
    assert original.count(serve.MARKER.encode()) == 1
    assert serve.inject_frontend(original, "const repair = true;").count(serve.PATCH_MARKER.encode()) == 1


def test_process_inventory_reuses_observation_but_refreshes_after_expiry():
    now = [0.0]
    observations = [["MATLAB run A"], [], ["MATLAB run B"]]
    calls = []

    def probe():
        calls.append(True)
        return observations[len(calls) - 1]

    get = serve.shared_process_probe(probe, clock=lambda: now[0])
    first = get()
    first.append("must not contaminate cache")
    assert get() == ["MATLAB run A"]
    now[0] = 3.0
    assert get() == []
    now[0] = 6.0
    assert get() == ["MATLAB run B"]
    assert len(calls) == 3


def test_parallel_requests_share_one_actual_probe():
    calls = []
    barrier = threading.Barrier(8)

    def probe():
        calls.append(True)
        return ["actual process command"]

    get = serve.shared_process_probe(probe)

    def request(_):
        barrier.wait(timeout=5)
        return get()

    with ThreadPoolExecutor(max_workers=8) as pool:
        assert list(pool.map(request, range(8))) == [["actual process command"]] * 8
    assert len(calls) == 1


def test_exception_is_not_cached_as_a_process_observation():
    calls = []

    def probe():
        calls.append(True)
        if len(calls) == 1:
            raise OSError("declared probe failure")
        return []

    get = serve.shared_process_probe(probe)
    with pytest.raises(OSError):
        get()
    assert get() == []
    assert len(calls) == 2
