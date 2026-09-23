"""Exact captured planes, including valid flat/single-tap AWGN evidence."""
import csv
import io
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as materializer


SOURCE = "reports/csv/phy_signal_diagnostic_source.csv"


def row(panel, **values):
    return dict(SnapshotID="dl31", Panel=panel, Series="rx1_tx1",
                Direction="DL", Slot=31, PointIndex=1, RxAntennaIndex=1,
                XValue=0, IValue=1, QValue=0, Magnitude_dB=0, Phase_deg=0,
                GridSHA256="executed_tensor_hash", Status="available",
                truth_status="real_lls_evidence",
                SourceArtifact="runtime_phy_arrays_same_trial", **values)


def chart(name, rows):
    header = list(dict.fromkeys(key for r in rows for key in r))
    payload = materializer._encode_dict_rows(header, rows)
    return materializer._runtime_phy_signal_diagnostic_chart(
        name, {SOURCE: {"artifact_id": 1}}, lambda _: payload, 77)


def decoded(result):
    return list(csv.DictReader(io.StringIO(result["csv_bytes"].decode("utf-8-sig"))))


@pytest.mark.parametrize("name,panel", [
    ("true H(tau) if available", "true_channel_impulse_response"),
    ("channel impulse response", "true_channel_impulse_response"),
    ("tap power profile", "true_channel_impulse_response"),
    ("true H(f) if available", "true_channel_frequency_response"),
])
def test_executed_single_tap_awgn_is_not_a_missing_trend(name, panel):
    rows = [row(panel)]
    if "frequency" in panel:
        rows = [dict(rows[0], XValue=x) for x in (-15000, 0, 15000)]
    result = chart(name, rows)
    assert result is not None
    assert result["source_mapping_status"] == "exact"
    assert result["source_row_count"] == len(rows)
    assert b"visual_gate=" not in result["img_bytes"]
    assert b"<circle" in result["img_bytes"]
    assert {r["tensor_sha256"] for r in decoded(result)} == {"executed_tensor_hash"}


def test_tap_power_is_complex_magnitude_squared_without_normalization():
    source = row("true_channel_impulse_response")
    result = chart("tap power profile", [dict(source, IValue=0.3, QValue=0.4),
                                         dict(source, XValue=1e-7, IValue=0, QValue=0)])
    assert result is not None
    assert [float(r["power_linear"]) for r in decoded(result)] == [0.25, 0.0]
    assert b"visual_gate=" not in result["img_bytes"]


def test_pre_equalization_uses_only_its_own_plane_and_keeps_links_separate():
    pre = row("pre_equalization_re_cloud")
    rows = [dict(pre, IValue=-0.7, QValue=-0.8),
            dict(pre, SnapshotID="ul35", Direction="UL", Slot=35, IValue=0.2, QValue=0.3),
            row("post_equalization_constellation"),
            dict(pre, Status="unavailable", IValue=999)]
    result = chart("pre-equalization constellation", rows)
    assert result is not None
    actual = decoded(result)
    assert [(float(r["i_value"]), float(r["q_value"])) for r in actual] == [(-0.7, -0.8), (0.2, 0.3)]
    assert {r["snapshot_id"] for r in actual} == {"dl31", "ul35"}
    assert {r["direction"] for r in actual} == {"DL", "UL"}
    assert {r["plane"] for r in actual} == {"pre_equalization_re_cloud"}
    assert {r["rx_antenna_index"] for r in actual} == {"1"}
    assert "layer_index" not in actual[0]  # Antenna-domain samples are not demixed layers.
    assert b"visual_gate=" not in result["img_bytes"]


@pytest.mark.parametrize("name", ["pre-equalization constellation", "channel impulse response",
                                  "tap power profile", "true H(tau) if available",
                                  "true H(f) if available"])
def test_wrong_plane_or_proxy_never_supplies_required_chart(name):
    assert chart(name, [row("post_equalization_constellation")]) is None
    panels = ("pre_equalization_re_cloud", "true_channel_impulse_response",
              "true_channel_frequency_response")
    assert chart(name, [dict(row(p), truth_status="fast_proxy") for p in panels]) is None


def test_generic_zero_trend_guard_is_not_relaxed():
    reason, _ = materializer._dataset_low_information_reason(
        {"mode": "line", "points": [[0, 0], [1, 0], [2, 0]]})
    assert reason == "all_zero_metric_values"
