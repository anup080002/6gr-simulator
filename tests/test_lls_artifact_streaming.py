"""Exact filesystem delivery of declared CSV fixtures; no PHY qualification."""
import hashlib
import io
from pathlib import Path
import sys
import tracemalloc

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_web_dashboard as d


def source(tmp_path, monkeypatch, repeats=2000):
    path = tmp_path / "measurements.csv"
    payload = b'Slot,Notes\n' + b'1,"retained\nlogical record"\n' * repeats
    path.write_bytes(payload)
    meta = dict(artifact_id=d.FILESYSTEM_ARTIFACT_ID_BASE + 1, logical_path="reports/csv/measurements.csv",
                filesystem_path=str(path), byte_size=1, mime_type="text/csv", created_utc="old")
    monkeypatch.setattr(d, "fetch_artifact_meta", lambda _: meta)
    monkeypatch.setattr(d, "filesystem_artifact_by_id", lambda _: meta)
    def reject_full_buffer(*_, **__):
        raise AssertionError("Filesystem CSV must not enter the whole-artifact byte cache")
    monkeypatch.setattr(d, "fetch_artifact_bytes", reject_full_buffer)
    monkeypatch.setattr(Path, "read_bytes", reject_full_buffer)
    d.load_cached_csv_preview.cache_clear()
    d.count_cached_csv_data_rows.cache_clear()
    return path, payload, meta


def test_preview_and_counts_stream_exact_logical_records(tmp_path, monkeypatch):
    _, _, meta = source(tmp_path, monkeypatch)
    assert d.count_csv_data_rows([meta], meta["logical_path"]) == 2000
    assert d.count_cached_csv_data_rows(meta["artifact_id"]) == 2000
    assert d.load_cached_csv_preview(meta["artifact_id"], 1) == (
        ["Slot", "Notes"], [["1", "retained\nlogical record"]])
    table = d.build_table_preview_payload(meta["artifact_id"])
    assert table["row_count"] == 2000
    assert len(table["rows"]) == min(2000, d.MAX_TABLE_PREVIEW_ROWS)


class HashSink:
    def __init__(self):
        self.digest, self.count, self.largest = hashlib.sha256(), 0, 0
    def write(self, data):
        self.digest.update(data)
        self.count += len(data)
        self.largest = max(self.largest, len(data))
        return len(data)


class Response:
    def __init__(self):
        self.headers, self.response_headers = {}, {}
        self.wfile = HashSink()
    def send_response(self, status):
        self.status = status
    def send_header(self, key, value):
        self.response_headers[key] = value
    def end_headers(self):
        pass


def test_raw_download_streams_all_bytes_and_actual_size(tmp_path, monkeypatch):
    _, payload, meta = source(tmp_path, monkeypatch, 300000)
    handler = Response()
    # Old metadata must not authorize a stale 304 for the current file.
    handler.headers["If-None-Match"] = d.artifact_etag(meta)
    d.DashboardHandler.respond_artifact(handler, meta["artifact_id"], download=True)
    assert handler.status == 200
    assert int(handler.response_headers["Content-Length"]) == len(payload)
    assert handler.wfile.count == len(payload)
    assert handler.wfile.digest.hexdigest() == hashlib.sha256(payload).hexdigest()
    assert handler.wfile.largest <= 1024*1024
    not_modified = Response()
    not_modified.headers["If-None-Match"] = handler.response_headers["ETag"]
    d.DashboardHandler.respond_artifact(not_modified, meta["artifact_id"], download=True)
    assert not_modified.status == 304 and not_modified.wfile.count == 0


def test_missing_file_cannot_use_old_cache_or_return_304(tmp_path, monkeypatch):
    path, _, meta = source(tmp_path, monkeypatch)
    path.unlink()  # Only this pytest-owned fixture.
    handler = Response()
    handler.headers["If-None-Match"] = d.artifact_etag(meta)
    with pytest.raises(FileNotFoundError):
        d.DashboardHandler.respond_artifact(handler, meta["artifact_id"], download=True)
    assert handler.wfile.count == 0


@pytest.mark.parametrize("method", ["GET", "HEAD"])
def test_wsgi_delivery_does_not_reassemble_full_body(tmp_path, monkeypatch, method):
    _, payload, meta = source(tmp_path, monkeypatch, 400000)
    monkeypatch.setattr(d.DashboardWSGIHandler, "do_GET",
        lambda self: self.respond_artifact(meta["artifact_id"], download=True))
    responses = []
    tracemalloc.start()
    try:
        handler = d.DashboardWSGIHandler({"REQUEST_METHOD": method},
            lambda status, headers: responses.append((status, dict(headers))))
        body = handler.dispatch()
        actual, size = hashlib.sha256(), 0
        for chunk in body:
            assert len(chunk) <= 1024*1024
            actual.update(chunk)
            size += len(chunk)
        if hasattr(body, "close"):
            body.close()
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    assert responses[0][0].startswith("200 ")
    assert int(responses[0][1]["Content-Length"]) == len(payload)
    assert size == (len(payload) if method == "GET" else 0)
    if method == "GET":
        assert actual.hexdigest() == hashlib.sha256(payload).hexdigest()
    assert peak < 6*1024*1024, peak
    assert handler.wfile.closed


def test_wsgi_client_disconnect_releases_spooled_body(tmp_path, monkeypatch):
    _, _, meta = source(tmp_path, monkeypatch, 400000)
    monkeypatch.setattr(d.DashboardWSGIHandler, "do_GET",
        lambda self: self.respond_artifact(meta["artifact_id"], download=True))
    handler = d.DashboardWSGIHandler({"REQUEST_METHOD": "GET"}, lambda *_: None)
    body = handler.dispatch()
    next(iter(body))
    body.close()
    assert handler.wfile.closed


def test_wsgi_changed_file_discards_partial_success_response(tmp_path, monkeypatch):
    path, _, meta = source(tmp_path, monkeypatch)
    monkeypatch.setattr(d.DashboardWSGIHandler, "do_GET",
        lambda self: self.respond_artifact(meta["artifact_id"], download=True))
    changed = []
    def mutate_once(_):
        if not changed:
            path.write_text("changed", encoding="utf-8")
            changed.append(True)
    monkeypatch.setattr(d.DashboardWSGIHandler, "end_headers", mutate_once)
    response = []
    body = d.dashboard_wsgi_app({"REQUEST_METHOD": "GET"},
        lambda status, headers: response.append((status, headers)))
    data = b"".join(body)
    assert response[0][0].startswith("500 ")
    assert len([v for k, v in response[0][1] if k.lower() == "content-length"]) == 1
    assert b"changed during download" in data
    assert b"retained" not in data


def test_threaded_failure_after_headers_closes_without_fake_success_body():
    handler = Response()
    handler._artifact_response_started = True
    handler.log_message = lambda *_: None
    d.DashboardHandler.respond_error(handler, 500, "changed artifact")
    assert handler.close_connection is True
    assert handler.wfile.count == 0
