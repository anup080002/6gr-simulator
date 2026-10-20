"""Declared publication fixtures, not receiver or channel qualification."""
import csv
import io
from pathlib import Path
import sys
import tracemalloc
import gc

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m

PATH = "reports/csv/phy_signal_diagnostic_source.csv"
ARTIFACTS = {PATH: {"artifact_id": 1}}


def grid_rows(count):
    for i in range(count):
        row = dict(SnapshotID="fixture", Panel="channel_estimate_grid",
            Series="receiver_hest_exact_tensor", Direction="UL", UEIndex=1, CellID=1,
            SFN=0, Slot=15, PointIndex=i+1, SubcarrierIndex=i % 16,
            OFDMSymbolIndex=(i // 16) % 14, RxPortIndex0Based=i // 224, TxPortIndex0Based=0,
            IValue=1, QValue=.1, Magnitude_dB=.0432137378, Phase_deg=5.710593,
            GridSHA256="fixture_not_physical", truth_status="real_lls_evidence",
            SourceArtifact="runtime_phy_arrays_same_trial", Status="available")
        row.update({f"UnrelatedColumn{j}": "retained, quoted" for j in range(60)})
        yield row


def write_source(path, rows):
    rows = iter(rows)
    first = next(rows)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, list(first))
        writer.writeheader()
        writer.writerow(first)
        writer.writerows(rows)


def fetcher(path):
    opened = []
    def fetch(_):
        raise AssertionError("The reader must use the streaming opener, not full CSV bytes")
    def opener(_):
        stream = path.open("rb")
        opened.append(stream)
        return stream
    fetch.open_artifact_binary = opener
    return fetch, opened


@pytest.mark.parametrize("chart", ["channel magnitude heatmap", "channel phase heatmap",
                                 "channel heatmap artifact links"])
def test_heatmap_exact_all_port_csv_and_stream_equivalence(tmp_path, chart):
    path = tmp_path / "source.csv"
    records = list(grid_rows(1000))
    # Exact zeros and undefined phases remain in the full plotted CSV.
    records[-1].update(IValue=0, QValue=0, Magnitude_dB="-Inf", Phase_deg="NaN")
    write_source(path, records)
    expected = m._runtime_phy_signal_diagnostic_chart(chart, ARTIFACTS, lambda _: path.read_bytes(), 8)
    fetch, opened = fetcher(path)
    actual = m._runtime_phy_signal_diagnostic_chart(chart, ARTIFACTS, fetch, 8)
    assert actual == expected
    assert actual["source_row_count"] == 1000
    rows = list(csv.DictReader(io.StringIO(actual["csv_bytes"].decode())))
    assert len(rows) == 1000 and rows[-1]["magnitude_db"] == "-Inf"
    assert rows[-1]["phase_deg"] == "NaN"
    assert {r["rx_port_index_0based"] for r in rows} == {"0", "1", "2", "3", "4"}
    assert opened and all(s.closed for s in opened)


def test_late_invalid_selected_row_rejected(tmp_path):
    path = tmp_path / "source.csv"
    rows = list(grid_rows(2000))
    rows[-1]["truth_status"] = "proxy"
    write_source(path, rows)
    fetch, opened = fetcher(path)
    with pytest.raises(ValueError, match="truth_status"):
        m._runtime_phy_signal_diagnostic_chart("channel phase heatmap", ARTIFACTS, fetch, 8)
    assert all(s.closed for s in opened)


def test_source_change_between_passes_rejected(tmp_path):
    first, second = tmp_path / "first.csv", tmp_path / "second.csv"
    rows = list(grid_rows(600))
    write_source(first, rows)
    rows[-1]["IValue"] = .7
    write_source(second, rows)
    calls = []
    def fetch(_):
        raise AssertionError("must stream")
    def opener(_):
        stream = (first if not calls else second).open("rb")
        calls.append(stream)
        return stream
    fetch.open_artifact_binary = opener
    with pytest.raises(ValueError, match="changed during two-pass"):
        m._runtime_phy_signal_diagnostic_chart("channel magnitude heatmap", ARTIFACTS, fetch, 8)
    assert len(calls) == 2 and all(s.closed for s in calls)


def test_large_heatmap_memory_excludes_wide_source_rows(tmp_path):
    path = tmp_path / "large.csv"
    write_source(path, grid_rows(12000))
    fetch, opened = fetcher(path)
    tracemalloc.start()
    try:
        result = m._runtime_phy_signal_diagnostic_chart("channel phase heatmap", ARTIFACTS, fetch, 8)
        finalized = m._finalize_chart_materialization_result(result)
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    assert result["source_row_count"] == 12000
    assert peak < 3*len(finalized["csv_bytes"])+8*1024*1024, (peak, len(result["csv_bytes"]))
    assert all(row["source_mapping_status"] == "exact" for row in
               csv.DictReader(io.StringIO(finalized["csv_bytes"].decode())))
    assert all(s.closed for s in opened)
    print(f"PHY_STREAM rows=12000 csv_bytes={len(result['csv_bytes'])} peak={peak}")


@pytest.mark.parametrize("chart,panel,series", [("Tx waveform", "time_domain", "tx"),
                                               ("PSD", "spectrum", "tx")])
def test_small_panels_do_not_import_unrelated_grid(tmp_path, chart, panel, series):
    path = tmp_path / "panels.csv"
    records = list(grid_rows(100))
    for i in range(4):
        row = dict(records[0], Panel=panel, Series=series, XValue=i, YValue=-i,
                   SampleRate_Hz=122880000)
        # Use the same wide schema on all rows.
        records.append(row)
    for row in records:
        row.setdefault("XValue", "")
        row.setdefault("YValue", "")
        row.setdefault("SampleRate_Hz", "")
    write_source(path, records)
    fetch, opened = fetcher(path)
    func = m._runtime_spectral_chart if chart == "PSD" else m._runtime_phy_signal_diagnostic_chart
    result = func(chart, ARTIFACTS, fetch, 8)
    assert result and result["source_row_count"] == 4
    assert all(s.closed for s in opened)


@pytest.mark.parametrize("existing", [True, False])
def test_streaming_finalizer_preserves_canonical_bytes(existing):
    header = ["value", "quoted"] + (["source_mapping_status"] if existing else [])
    rows = [["1", 'two, "quoted"\nlines'], ["2", "other"]]
    if existing:
        rows[0].append("")
        rows[1].append("invalid")
    payload = m._encode_csv(header, rows)
    expected = m._encode_csv(header if existing else header+["source_mapping_status"],
        [rows[0][:2]+["exact"], rows[1][:2]+["invalid" if existing else "exact"]])
    assert m._ensure_source_mapping_status_csv(payload, "exact") == expected


def test_publication_index_keeps_files_not_all_payloads(tmp_path):
    index = m._FilesystemPublicationIndex()
    tracemalloc.start()
    try:
        for i in range(12):
            data = bytes([i]) * (2*1024*1024)
            path = tmp_path / f"artifact_{i}.csv"
            path.write_bytes(data)
            index.register(i, path, data)
        del data
        gc.collect()
        current, _ = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    assert current < 1024*1024, current  # 24 MiB on disk must not stay cached.
    assert index.read(11) == bytes([11]) * (2*1024*1024)
    path.write_bytes(bytes([10]) * (2*1024*1024))  # Same byte count, different content.
    with pytest.raises(ValueError, match="changed before reuse"):
        index.read(11)
    print(f"PUBLICATION_INDEX persisted_bytes={24*1024*1024} retained_python_bytes={current}")


def test_publication_index_rejects_missing_or_unwritten_payload(tmp_path):
    index = m._FilesystemPublicationIndex()
    path = tmp_path / "artifact.csv"
    with pytest.raises(ValueError, match="complete persisted"):
        index.register(1, path, b"a")
    path.write_bytes(b"b")
    with pytest.raises(ValueError, match="changed before reuse"):
        index.register(1, path, b"a")
    assert 1 not in index


def test_publication_changed_while_reader_open_is_rejected(tmp_path):
    index = m._FilesystemPublicationIndex()
    path = tmp_path / "changing.csv"
    path.write_bytes(b"original")
    index.register(1, path, b"original")
    reader = index.open(1)
    assert reader.read(1) == b"o"
    path.write_bytes(b"modified")
    with pytest.raises(ValueError, match="during read"):
        reader.close()
    assert reader.closed
