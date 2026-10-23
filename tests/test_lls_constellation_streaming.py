"""Exact data-plane publication without retaining every CSV row in RAM."""
import csv
import io
from pathlib import Path
import sys
import tracemalloc

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))
import lls_contract_materializer as m


PATH = "air_interface/csv/dl_constellation_samples.csv"


def fixture_rows(count):
    # Explicit rendering fixture, not a PHY measurement or qualification run.
    for index in range(count):
        yield dict(Direction="DL", UEIndex=1, Frame=1, Slot=41, LayerIndex=1,
                   CodewordIndex=0, SampleIndex=index+1, Modulation="QPSK",
                   SweepPointIndex=index % 2 + 1, SNR_dB=40-10*(index % 2),
                   RawEqualizedReal=(index % 17)/10, RawEqualizedImag=-.2,
                   ReceivedReal=(index % 17)/5, ReceivedImag=-.4,
                   ReferenceSymbolReal=1 if index % 4 < 2 else -1,
                   ReferenceSymbolImag=1 if index % 2 else -1)


def streaming_fetch(path):
    opened = []
    def fetch(_):
        raise AssertionError("Data constellation must stream its input, not load the full CSV")
    def opener(_):
        stream = path.open("rb")
        opened.append(stream)
        return stream
    fetch.open_artifact_binary = opener
    return fetch, opened


@pytest.mark.parametrize("chart", ["post-equalization constellation", "pre-equalization constellation",
    "constellation per layer", "constellation per codeword", "constellation per modulation order",
    "symbol decision error histogram"])
def test_stream_matches_byte_source_and_closes_inputs(tmp_path, chart):
    records = list(fixture_rows(1100))
    payload = m._encode_dict_rows(list(records[0]), records)
    source = tmp_path / "samples.csv"
    source.write_bytes(payload)
    expected = m._runtime_constellation_chart(chart, {PATH: {"artifact_id": 1}}, lambda _: payload, 7)
    fetch, opened = streaming_fetch(source)
    actual = m._runtime_constellation_chart(chart, {PATH: {"artifact_id": 1}}, fetch, 7)
    assert actual == expected
    assert actual["source_row_count"] == 1100
    assert opened and all(s.closed for s in opened)


def test_large_constellation_memory_excludes_python_row_population(tmp_path):
    source = tmp_path / "samples.csv"
    count = 20_000
    with source.open("w", newline="", encoding="utf-8") as stream:
        rows = fixture_rows(count)
        first = next(rows)
        writer = csv.DictWriter(stream, list(first))
        writer.writeheader()
        writer.writerow(first)
        writer.writerows(rows)
    fetch, opened = streaming_fetch(source)
    tracemalloc.start()
    try:
        result = m._runtime_constellation_chart("post-equalization constellation",
                                               {PATH: {"artifact_id": 1}}, fetch, 7)
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    # Expanded lossless metadata may cross the real file-spill threshold.
    # Exercise either supported payload without materializing a second copy
    # of the complete CSV. Keep the original memory ceiling and exact rows.
    payload = result["csv_file"] if "csv_file" in result else result["csv_bytes"]
    size = m._payload_size(payload)
    assert peak < 2*size+8*1024*1024, (peak, size)
    with m._payload_reader(payload) as binary:
        source_text = io.TextIOWrapper(binary, encoding="utf-8", newline="")
        try:
            plotted = csv.DictReader(source_text)
            for actual, expected in zip(plotted, fixture_rows(count), strict=True):
                assert float(actual["x_value"]) == expected["RawEqualizedReal"]
                assert int(actual["sample_index"]) == expected["SampleIndex"]
                assert int(actual["sweep_point_index"]) == expected["SweepPointIndex"]
        finally:
            source_text.detach()  # The payload reader owns verification and lifetime.
    assert result["source_row_count"] == count
    assert all(s.closed for s in opened)
    print(f"CONSTELLATION_STREAM rows={count} output_bytes={size} python_peak={peak}")


def test_reference_caption_is_a_cap_not_fake_qpsk_cardinality():
    records = list(fixture_rows(8))
    payload = m._encode_dict_rows(list(records[0]), records)
    result = m._runtime_constellation_chart("post-equalization constellation",
                                           {PATH: {"artifact_id": 1}}, lambda _: payload, 7)
    assert b"Preview: up to 256 unique references/panel" in result["img_bytes"]


def test_late_invalid_sample_rejected_and_source_closed(tmp_path):
    records = list(fixture_rows(1000))
    records[-1]["RawEqualizedReal"] = "NaN"
    source = tmp_path / "invalid.csv"
    source.write_bytes(m._encode_dict_rows(list(records[0]), records))
    fetch, opened = streaming_fetch(source)
    with pytest.raises(ValueError, match="finite receiver samples"):
        m._runtime_constellation_chart("post-equalization constellation", {PATH: {"artifact_id": 1}}, fetch, 7)
    assert opened and all(s.closed for s in opened)


@pytest.mark.parametrize("chart", ["PDSCH EVM per symbol", "EVM per subcarrier", "EVM per layer"])
def test_profile_stream_preserves_exact_complete_capture(tmp_path, chart):
    from test_lls_evm_profiles import full_capture_payload
    payload = full_capture_payload()
    source = tmp_path / "pairs.csv"
    source.write_bytes(payload)
    expected = m._runtime_evm_profile_chart(chart, {PATH: {"artifact_id": 1}}, lambda _: payload, 7)
    fetch, opened = streaming_fetch(source)
    assert m._runtime_evm_profile_chart(chart, {PATH: {"artifact_id": 1}}, fetch, 7) == expected
    assert expected["source_row_count"] == 2
    assert opened and all(s.closed for s in opened)


def test_full_profile_memory_and_late_duplicate_guard(tmp_path):
    from test_lls_evm_profiles import full_capture_payload
    row = next(csv.DictReader(io.StringIO(full_capture_payload().decode())))
    count = 30_000
    source = tmp_path / "pairs.csv"
    row.update(ObservationSymbolCount=str(count), CapturedSymbolCount=str(count))
    with source.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, list(row))
        writer.writeheader()
        for index in range(1, count+1):
            writer.writerow(dict(row, SampleIndex=index, SubcarrierIndex=index))
    fetch, opened = streaming_fetch(source)
    tracemalloc.start()
    try:
        result = m._runtime_evm_profile_chart("PDSCH EVM per symbol", {PATH: {"artifact_id": 1}}, fetch, 7)
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    assert result["source_row_count"] == count
    assert peak < 8*1024*1024, peak
    assert all(s.closed for s in opened)
    print(f"DATA_EVM_STREAM rows={count} python_peak={peak}")
    with source.open("a", newline="", encoding="utf-8") as stream:
        csv.DictWriter(stream, list(row)).writerow(dict(row, SampleIndex=1, SubcarrierIndex=1))
    assert m._runtime_evm_profile_chart("PDSCH EVM per symbol", {PATH: {"artifact_id": 1}}, fetch, 7) is None
    assert all(s.closed for s in opened)
