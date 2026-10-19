from __future__ import annotations

import csv
import io
import sys
import tracemalloc
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m
import lls_radio_measurement_plots as radio
from test_lls_radio_measurement_plots import control_pairs, csv_records


class MemoryIdentityReference:
    def __init__(self):
        self.seen = set()

    def add(self, key):
        if key in self.seen:
            return False
        self.seen.add(key)
        return True


def file_fetch(path):
    opened = []

    def fetch(_):
        raise AssertionError("The local control-EVM path must not read the entire source into bytes.")

    def open_binary(_):
        stream = path.open("rb")
        opened.append(stream)
        return stream

    fetch.open_artifact_binary = open_binary
    return fetch, opened


@pytest.mark.parametrize("signal,name", [("PRACH", "PRACH EVM"), ("SSS", "SSB EVM"), ("CSI-RS", "CSI-RS EVM")])
def test_control_evm_stream_matches_exact_in_memory_reference(tmp_path, signal, name):
    records = list(csv.DictReader(io.StringIO(control_pairs(signal).decode())))
    # Retain the same occasion on different sweep points and interleaved ports.
    records = [dict(row, SweepPointIndex=point, ConfiguredSNR_dB=snr, PortIndex=port)
               for point, snr in [(1, 40), (2, -10)] for row in records for port in [0, 1]]
    path = tmp_path / "pairs.csv"
    path.write_bytes(csv_records(records))
    logical = radio.CONTROL_EVM[name][1]
    existing = {logical: {"artifact_id": 1}}
    _, decoded = m._decode_csv_dicts(path.read_bytes())
    expected = radio._control_evm_rows(m, name, 7, logical, decoded, MemoryIdentityReference())
    fetch, opened = file_fetch(path)
    actual = radio._control_evm(m, name, existing, fetch, 7)
    assert actual == expected
    assert opened and all(stream.closed for stream in opened)
    legacy = radio._control_evm(m, name, existing, lambda _: path.read_bytes(), 7)
    assert legacy == expected


def test_large_stream_has_all_samples_and_bounded_python_memory(tmp_path):
    row = next(csv.DictReader(io.StringIO(control_pairs("CSI-RS").decode())))
    path = tmp_path / "wideband_pairs.csv"
    count = 50_000
    with path.open("w", newline="", encoding="utf-8") as out:
        writer = csv.DictWriter(out, list(row))
        writer.writeheader()
        for index in range(count):
            writer.writerow(dict(row, SampleIndex=index))
    fetch, opened = file_fetch(path)
    logical = radio.CONTROL_EVM["CSI-RS EVM"][1]
    tracemalloc.start()
    try:
        actual = radio._control_evm(m, "CSI-RS EVM", {logical: {"artifact_id": 1}}, fetch, 7)
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    output = list(csv.DictReader(io.StringIO(actual["csv_bytes"].decode())))
    assert len(output) == 1 and int(output[0]["sample_count"]) == count
    ref = float(row["ReferenceReal"])**2 + float(row["ReferenceImag"])**2
    err = ((float(row["MeasuredReal"])-float(row["ReferenceReal"]))**2 +
           (float(row["MeasuredImag"])-float(row["ReferenceImag"]))**2)
    assert float(output[0]["reference_energy"]) == pytest.approx(ref*count)
    assert float(output[0]["error_energy"]) == pytest.approx(err*count)
    assert peak < 8*1024*1024, f"Per-sample data retained in Python: peak={peak}"
    assert all(stream.closed for stream in opened)
    print(f"CONTROL_EVM_STREAM_MEMORY rows={count} source_bytes={path.stat().st_size} python_peak_bytes={peak}")
    # A duplicate arbitrarily late in the file must still reject the artifact.
    with path.open("a", newline="", encoding="utf-8") as out:
        csv.DictWriter(out, list(row)).writerow(dict(row, SampleIndex=0))
    bad = radio._control_evm(m, "CSI-RS EVM", {logical: {"artifact_id": 1}}, fetch, 7)
    assert bad["csv_status"] == "unavailable_exact_reason" and "Duplicate" in bad["note"]


@pytest.mark.parametrize("first", [b"a,b\n", b"status\nsource_artifact_present_but_empty\n"])
def test_stream_source_precedence_and_long_quoted_fields(first):
    canonical = radio.CONTROL_EVM["CSI-RS EVM"][1]
    generic = "air_interface/csv/control_evm_samples.csv"
    row = next(csv.DictReader(io.StringIO(control_pairs("CSI-RS").decode())))
    row["AuditDetail"] = "x"*200_000 + "\nquoted,tail"
    data = {1: first, 2: csv_records([row])}
    old_limit = csv.field_size_limit()
    with m._first_available_csv_stream({canonical: {"artifact_id": 1}, generic: {"artifact_id": 2}},
                                       data.__getitem__, [canonical, generic]) as (path, rows):
        assert path == generic
        assert list(rows)[0]["AuditDetail"] == row["AuditDetail"]
    assert csv.field_size_limit() == old_limit


def test_filesystem_adapter_exposes_stream_without_read_bytes(tmp_path, monkeypatch):
    path = tmp_path / "paired.csv"
    path.write_bytes(control_pairs("CSI-RS"))
    def inspect(run, artifacts, **kwargs):
        fetch = kwargs["fetch_artifact_bytes"]
        with fetch.open_artifact_binary(1) as source:
            assert source.read(10) == path.read_bytes()[:10]
        return {"stream_available": True}
    monkeypatch.setattr(m, "materialize_run_contract_artifacts", inspect)
    result = m.materialize_filesystem_run_contract_artifacts({"run_id": 1},
        [{"artifact_id": 1, "filesystem_path": str(path)}])
    assert result["stream_available"]
