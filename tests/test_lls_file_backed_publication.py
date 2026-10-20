"""Exercise the production file-backed CSV protocol, never synthetic PHY results."""
import csv
import hashlib
import io
import json
from pathlib import Path
import sys
import tracemalloc

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m
from test_lls_phy_diagnostic_streaming import grid_rows, write_source, fetcher, ARTIFACTS, PATH


def payload_bytes(result):
    return b"".join(m._payload_chunks(result["csv_file"])) if "csv_file" in result else result["csv_bytes"]


def test_file_and_byte_results_have_identical_csv_png_lineage(tmp_path, monkeypatch):
    source = tmp_path / "source.csv"
    write_source(source, grid_rows(1000))
    fetch, _ = fetcher(source)
    expected = m._finalize_chart_materialization_result(
        m._runtime_phy_signal_diagnostic_chart("channel phase heatmap", ARTIFACTS, fetch, 8))
    assert "csv_bytes" in expected
    monkeypatch.setattr(m, "CSV_MEMORY_LIMIT_BYTES", 1024)
    actual = m._finalize_chart_materialization_result(
        m._runtime_phy_signal_diagnostic_chart("channel phase heatmap", ARTIFACTS, fetch, 8))
    assert "csv_file" in actual and "csv_bytes" not in actual
    assert payload_bytes(actual) == expected["csv_bytes"]
    assert actual["img_bytes"] == expected["img_bytes"]
    png = m._rasterize_contract_png(actual["img_bytes"], source_mime_type="image/svg+xml")
    before = m._contract_plot_lineage_row("plot", "plot.png", "plot.csv", png, expected["csv_bytes"])
    after = m._contract_plot_lineage_row("plot", "plot.png", "plot.csv", png, actual["csv_file"])
    assert before == after
    m._write_file_if_possible(str(tmp_path), "published/plot.csv", actual["csv_file"])
    assert (tmp_path / "published/plot.csv").read_bytes() == expected["csv_bytes"]
    actual["csv_file"].close()


def test_corrupt_temporary_does_not_overwrite_published_artifact(tmp_path, monkeypatch):
    monkeypatch.setattr(m, "CSV_MEMORY_LIMIT_BYTES", 10)
    stream = m._csv_output_buffer()
    stream.write(b"sealed evidence,not a physical sample\n" * 100)
    payload = m._finish_csv_buffer(stream)
    target = tmp_path / "complete.csv"
    target.write_bytes(b"previous complete evidence\n")
    payload.stream.seek(0)
    payload.stream.write(b"changed")
    with pytest.raises(ValueError, match="Sealed CSV payload"):
        m._write_file_if_possible(str(tmp_path), "complete.csv", payload)
    assert target.read_bytes() == b"previous complete evidence\n"
    assert list(tmp_path.iterdir()) == [target]
    payload.close()


def test_file_backed_heatmap_and_finalization_are_memory_bounded(tmp_path, monkeypatch):
    source = tmp_path / "large.csv"
    write_source(source, grid_rows(12000))
    fetch, _ = fetcher(source)
    monkeypatch.setattr(m, "CSV_MEMORY_LIMIT_BYTES", 65536)
    tracemalloc.start()
    try:
        result = m._finalize_chart_materialization_result(
            m._runtime_phy_signal_diagnostic_chart("channel phase heatmap", ARTIFACTS, fetch, 8))
        m._write_file_if_possible(str(tmp_path), "complete.csv", result["csv_file"])
        index = m._FilesystemPublicationIndex()
        index.register(1, tmp_path / "complete.csv", result["csv_file"])
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    assert result["source_row_count"] == 12000
    assert peak < 8*1024*1024, peak
    with (tmp_path / "complete.csv").open(newline="", encoding="utf-8") as stream:
        rows = csv.DictReader(stream)
        assert sum(row["source_mapping_status"] == "exact" for row in rows) == 12000
    print(f"FILE_CSV rows=12000 bytes={result['csv_file'].size} python_peak={peak}")
    result["csv_file"].close()


def test_complete_filesystem_materializer_accepts_file_backed_chart(tmp_path, monkeypatch):
    source = tmp_path / PATH
    source.parent.mkdir(parents=True)
    write_source(source, grid_rows(1000))
    spec = next(s for s in m._chart_specs() if s["chart_name"] == "channel phase heatmap")
    monkeypatch.setattr(m, "_chart_specs", lambda: [spec])
    monkeypatch.setattr(m, "_table_specs", lambda: [])
    monkeypatch.setattr(m, "CSV_MEMORY_LIMIT_BYTES", 1024)
    result = m.materialize_filesystem_run_contract_artifacts(
        {"run_id": 8, "run_folder": str(tmp_path), "status_text": "completed"},
        [dict(artifact_id=1, logical_path=PATH, filesystem_path=str(source),
              artifact_kind="table_csv", mime_type="text/csv")], force=True,
        feature_policy={"channel_snapshot_capture_enabled": True})
    assert result["coverage"]["charts_available"] == 1
    csv_path = tmp_path / m.chart_contract_csv_path(spec)
    with csv_path.open(newline="", encoding="utf-8") as stream:
        assert len(list(csv.DictReader(stream))) == 1000
    with (tmp_path / m.plot_lineage_logical_path()).open(newline="", encoding="utf-8") as stream:
        lineage = list(csv.DictReader(stream))
    assert lineage[0]["SourceCSV_SHA256"] == hashlib.sha256(csv_path.read_bytes()).hexdigest()
    # Reuse existing canonical charts without buffering their CSV again.
    image_path = tmp_path / m.chart_contract_image_path(spec)
    inventory = [dict(artifact_id=i, logical_path=p.relative_to(tmp_path).as_posix(),
                      filesystem_path=str(p), artifact_kind=kind, mime_type=mime)
                 for i, (p, kind, mime) in enumerate([
                     (source, "table_csv", "text/csv"), (csv_path, "table_csv", "text/csv"),
                     (image_path, "image_png", "image/png")], 1)]
    read_bytes = Path.read_bytes
    def reject_plotted_csv_buffer(path):
        if path.name == csv_path.name:
            raise AssertionError("Existing plotted CSV lineage must be streamed")
        return read_bytes(path)
    monkeypatch.setattr(Path, "read_bytes", reject_plotted_csv_buffer)
    reused = m.materialize_filesystem_run_contract_artifacts(
        {"run_id": 8, "run_folder": str(tmp_path), "status_text": "completed"}, inventory,
        feature_policy={"channel_snapshot_capture_enabled": True})
    assert reused["coverage"]["charts_available"] == 1


def test_database_writer_retains_every_chunk_and_commits_after_verification(monkeypatch):
    monkeypatch.setattr(m, "CSV_MEMORY_LIMIT_BYTES", 10)
    expected = b"declared serialization fixture,not PHY\n" * 50000
    stream = m._csv_output_buffer()
    stream.write(expected)
    payload = m._finish_csv_buffer(stream)

    class Connection:
        lastrowid = 19
        def __init__(self):
            self.calls, self.committed = [], False
        def __enter__(self):
            return self
        def __exit__(self, *_):
            return False
        def cursor(self, **_):
            return self
        def execute(self, query, args):
            self.calls.append((query, args))
        def fetchall(self):
            return []
        def commit(self):
            self.committed = True

    conn = Connection()
    assert m._store_artifact(lambda: conn, 1, "fixture.csv", "table_csv", "text/csv", payload, {}) == 19
    chunks = [args for query, args in conn.calls if "INSERT INTO sim_artifact_chunks" in query]
    assert conn.committed and len(chunks) > 1
    assert [item[1] for item in chunks] == list(range(1, len(chunks)+1))
    assert b"".join(item[2] for item in chunks) == expected
    assert max(len(item[2]) for item in chunks) <= 512*1024
    assert next(args[4] for query, args in conn.calls if "INSERT INTO sim_artifacts\n" in query) == len(expected)
    payload.stream.seek(0)
    payload.stream.write(b"corruption")
    failed = Connection()
    with pytest.raises(ValueError, match="Sealed CSV payload"):
        m._store_artifact(lambda: failed, 1, "fixture.csv", "table_csv", "text/csv", payload, {})
    assert not failed.committed
    payload.close()


def test_live_publisher_accepts_file_backed_chart(tmp_path, monkeypatch):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
    import publish_lls_live_csv_plots as live
    source = tmp_path / PATH
    source.parent.mkdir(parents=True)
    write_source(source, grid_rows(1000))
    monkeypatch.setattr(live, "CHARTS", ("channel phase heatmap",))
    monkeypatch.setattr(live, "SOURCES", (PATH,))
    monkeypatch.setattr(m, "CSV_MEMORY_LIMIT_BYTES", 1024)
    result = live.publish(tmp_path)
    manifest_path = live.io_path(Path(result["Manifest"]))
    manifest = json.loads(manifest_path.read_text())
    chart = manifest["charts"][0]
    assert chart["source_row_count"] == 1000
    assert chart["status"] == "measured_checkpoint"
    plotted = manifest_path.parent / chart["csv"]
    with live.io_path(plotted).open(newline="", encoding="utf-8") as stream:
        assert len(list(csv.DictReader(stream))) == 1000
    assert manifest["artifact_sha256"][chart["csv"]] == live.file_digest(plotted)
    assert live.publish(tmp_path)["Status"] == "unchanged_verified_snapshot"


def test_existing_alias_lineage_streams_full_csv(tmp_path, monkeypatch):
    from PIL import Image
    image_path = tmp_path / "reports/image/contract__fixture.png"
    csv_path = tmp_path / "reports/csv/contract__fixture.csv"
    image_path.parent.mkdir(parents=True)
    csv_path.parent.mkdir(parents=True)
    Image.new("RGB", (10, 10), "white").save(image_path)
    expected = b"serialization_fixture\n" * 10000
    csv_path.write_bytes(expected)
    read_bytes = Path.read_bytes
    def reject_csv_buffer(path):
        if path.suffix == ".csv":
            raise AssertionError("Lineage must stream full CSV, not buffer it")
        return read_bytes(path)
    monkeypatch.setattr(Path, "read_bytes", reject_csv_buffer)
    rows = []
    m._append_filesystem_contract_alias_lineage(str(tmp_path), rows)
    assert len(rows) == 1
    assert rows[0][3] == hashlib.sha256(expected).hexdigest()


@pytest.mark.parametrize("chart", ["post-equalization constellation", "pre-equalization constellation",
    "constellation per layer", "constellation per codeword", "constellation per modulation order",
    "symbol decision error histogram"])
def test_constellation_file_payload_preserves_complete_csv_and_plot(tmp_path, monkeypatch, chart):
    from test_lls_constellation_streaming import fixture_rows, streaming_fetch, PATH as constellation_path
    # Declared serialization fixture; not a new waveform measurement.
    records = list(fixture_rows(1100))
    source = tmp_path / "pairs.csv"
    source.write_bytes(m._encode_dict_rows(list(records[0]), records))
    fetch, opened = streaming_fetch(source)
    existing = {constellation_path: {"artifact_id": 1}}
    expected = m._finalize_chart_materialization_result(
        m._runtime_constellation_chart(chart, existing, fetch, 7))
    monkeypatch.setattr(m, "CSV_MEMORY_LIMIT_BYTES", 1024)
    raw_actual = m._runtime_constellation_chart(chart, existing, fetch, 7)
    # The later status-column finalizer already supports files. It must not
    # mask a complete byte allocation in this producer before that stage.
    assert "csv_file" in raw_actual and "csv_bytes" not in raw_actual
    try:
        actual = m._finalize_chart_materialization_result(raw_actual)
    finally:
        raw_actual["csv_file"].close()
    assert "csv_file" in actual and "csv_bytes" not in actual
    try:
        assert payload_bytes(actual) == expected["csv_bytes"]
        assert actual["img_bytes"] == expected["img_bytes"]
        assert actual["source_row_count"] == expected["source_row_count"] == 1100
        m._write_file_if_possible(str(tmp_path), "published/constellation.csv", actual["csv_file"])
        assert (tmp_path / "published/constellation.csv").read_bytes() == expected["csv_bytes"]
        png = m._rasterize_contract_png(actual["img_bytes"], source_mime_type="image/svg+xml")
        assert m._contract_plot_lineage_row("plot", "plot.png", "plot.csv", png, actual["csv_file"]) == (
            m._contract_plot_lineage_row("plot", "plot.png", "plot.csv", png, expected["csv_bytes"]))
        assert opened and all(stream.closed for stream in opened)
    finally:
        actual["csv_file"].close()


def test_large_constellation_output_uses_bounded_owned_storage(tmp_path, monkeypatch):
    from test_lls_constellation_streaming import fixture_rows, streaming_fetch, PATH as constellation_path
    source = tmp_path / "pairs.csv"
    count = 50000
    with source.open("w", newline="", encoding="utf-8") as stream:
        rows = fixture_rows(count)
        first = next(rows)
        writer = csv.DictWriter(stream, list(first))
        writer.writeheader()
        writer.writerow(first)
        writer.writerows(rows)
    fetch, opened = streaming_fetch(source)
    monkeypatch.setattr(m, "CSV_MEMORY_LIMIT_BYTES", 65536)
    tracemalloc.start()
    try:
        result = m._finalize_chart_materialization_result(m._runtime_constellation_chart(
            "post-equalization constellation", {constellation_path: {"artifact_id": 1}}, fetch, 7))
        assert "csv_file" in result and "csv_bytes" not in result
        m._write_file_if_possible(str(tmp_path), "complete.csv", result["csv_file"])
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    try:
        assert peak < 6*1024*1024, peak
        assert result["source_row_count"] == count
        with (tmp_path / "complete.csv").open(newline="", encoding="utf-8") as stream:
            for actual, expected in zip(csv.DictReader(stream), fixture_rows(count), strict=True):
                assert float(actual["x_value"]) == expected["RawEqualizedReal"]
                assert int(actual["sample_index"]) == expected["SampleIndex"]
                assert int(actual["sweep_point_index"]) == expected["SweepPointIndex"]
                assert actual["source_mapping_status"] == "exact"
        assert opened and all(stream.closed for stream in opened)
        print(f"FILE_CONSTELLATION rows={count} output_bytes={result['csv_file'].size} python_peak={peak}")
    finally:
        result["csv_file"].close()
