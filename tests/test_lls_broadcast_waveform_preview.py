"""Waveform publication must not erase outage capture identity or invent data."""
import csv
import io
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m


@pytest.mark.parametrize("name", ["Tx waveform", "Rx waveform", "magnitude vs sample",
                                 "phase vs sample", "power vs sample"])
def test_broadcast_branches_and_observations_remain_separate(name):
    source = "reports/csv/live_waveform_preview.csv"
    rows = [dict(Time_s=slot * .001 + i * 1e-6, SampleIndex=i+1,
                 TxReal=1, TxImag=2, TxMagnitude=5**.5,
                 RxReal=branch*.25, RxImag=-1, RxMagnitude=(1+(branch*.25)**2)**.5,
                 ObservationKind="broadcast_window", Direction="DL", Slot=slot,
                 UEIndex=1, ServingCell=1, TxAntennaIndex=branch, RxAntennaIndex=branch,
                 TxPlane="shared_transmitter_output_after_rf", RxPlane="broadcast_receiver_input",
                 Source="completed_shared_waveform_observation_buffers",
                 EvidenceScope="shared_broadcast_observation_not_data_constellation")
            for slot in (1, 21) for branch in (1, 2) for i in range(3)]
    payload = m._encode_dict_rows(list(rows[0]), rows)
    result = m._specialized_chart_materialization(name, {source: {"artifact_id": 1}}, lambda _: payload, 7)
    assert result is not None
    actual = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode("utf-8-sig"))))
    assert {r["ObservationKind"] for r in actual} == {"broadcast_window"}
    assert {(r["Slot"], r["RxAntennaIndex"]) for r in actual} == {("1", "1"), ("1", "2"), ("21", "1"), ("21", "2")}
    # Each line is one metric for one physical observation/branch, not a
    # zigzag joining all antennas or observations into one invented waveform.
    for trace in {r["series_name"] for r in actual}:
        points = [r for r in actual if r["series_name"] == trace]
        assert len(points) == 3
    assert b"broadcast_window" in result["img_bytes"]
    absent = m._specialized_chart_materialization(
        "post-equalization constellation", {source: {"artifact_id": 1}}, lambda _: payload, 7)
    assert absent["source_row_count"] == 0
    assert absent["csv_status"] == "unavailable_exact_reason"
    assert b"No captured receiver equalized samples" in absent["csv_bytes"]
