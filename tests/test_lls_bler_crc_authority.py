"""Declared export fixtures, not PHY performance qualification."""
import csv
import io
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import lls_csv_semantics as semantics


@pytest.mark.parametrize("ul_crc,expected_sources,expected_samples", [
    ("0", "air_interface/csv/dl_pdsch_trials.csv|air_interface/csv/ul_pusch_trials.csv", 2),
    ("NaN", "air_interface/csv/dl_pdsch_trials.csv", 1),
])
def test_bler_sinr_lineage_names_every_contributing_direction(ul_crc, expected_sources, expected_samples):
    paths = ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"]
    payloads = {
        index: m._encode_csv(["Direction", "PostEqSINR_dB", "CRCPass"],
                            [[direction, 20, crc]])
        for index, (direction, crc) in enumerate([("DL", "1"), ("UL", ul_crc)])
    }
    existing = {path: dict(artifact_id=index, logical_path=path)
                for index, path in enumerate(paths)}
    result = m._specialized_chart_materialization("BLER vs SINR", existing, payloads.__getitem__, 1)
    assert result["source_table_path"] == expected_sources
    assert result["source_row_count"] == expected_samples
    rows = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert all(row["source_table_logical_path"] == expected_sources for row in rows)
    assert float(rows[0]["BLER"]) == (0.5 if ul_crc == "0" else 0.0)


def test_zero_bler_operating_point_has_visible_marker_without_error_floor():
    path = "air_interface/csv/dl_pdsch_trials.csv"
    payload = m._encode_csv(["Direction", "ConfiguredSNR_dB", "CRCPass"], [["DL", 20, 1]])
    result = m._configured_sweep_chart_materialization("dl_bler_vs_snr",
        {path: dict(artifact_id=1, logical_path=path)}, lambda _: payload, 1)
    rows = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert float(rows[0]["BLER"]) == 0.0
    svg = ET.fromstring(result["img_bytes"])
    markers = [node for node in svg.iter() if node.get("data-zero-bar-marker") == "true"]
    assert len(markers) == 1 and float(markers[0].get("r")) > 0
    # Marker is drawn at the exact zero-height bar endpoint, not an invented
    # positive BLER. The actual data rectangle retains height zero.
    bars = [node for node in svg.iter() if node.tag.endswith("rect")
            and node.get("fill") == "#0f766e" and node.get("opacity") == "0.88"]
    assert len(bars) == 1 and float(bars[0].get("height")) == 0
    assert float(markers[0].get("cy")) == float(bars[0].get("y"))


@pytest.mark.parametrize("token,expected", [
    ("1", 0.0), ("1.0", 0.0), ("true", 0.0), ("PASS", 0.0),
    ("0", 1.0), ("0.0", 1.0), ("false", 1.0), ("FAIL", 1.0),
    ("", None), ("NaN", None), ("unavailable", None), ("not_attempted", None),
    ("garbage", None), ("2", None), ("-1", None), ("0.5", None),
])
def test_transport_bler_requires_explicit_binary_crc(token, expected):
    assert m._trial_row_bler({"CRCPass": token}) == expected


def test_codeblock_fraction_cannot_replace_transport_block_crc():
    assert m._trial_row_bler({"CodeBlockBLER": "0.25"}) is None
    assert m._trial_row_bler({"CRCPass": "1", "CodeBlockBLER": "0.25"}) == 0


def test_sweep_denominator_excludes_absent_and_invalid_crc():
    rows = [dict(Direction="DL", ConfiguredSNR_dB=20, CRCPass=crc, CodeBlockBLER="0.25")
            for crc in ("1", "0", "", "NaN", "not_attempted", "2")]
    stream = io.StringIO()
    writer = csv.DictWriter(stream, list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
    path = "air_interface/csv/dl_pdsch_trials.csv"
    result = m._configured_sweep_chart_materialization("dl_bler_vs_snr",
        {path: dict(artifact_id=1, logical_path=path)}, lambda _: stream.getvalue().encode(), 1)
    assert result is not None
    actual = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert len(actual) == 1 and float(actual[0]["BLER"]) == 0.5
    assert result["source_row_count"] == 2


def test_semantic_audit_uses_observed_crc_population_not_all_rows():
    rows = [{"CRCPass": token} for token in ("1", "0", "NaN", "", "2", "-1")]
    bler, _, failures = semantics._raw_error_rates(rows)
    assert bler == 0.5 and failures == 1


def test_generic_pass_status_is_not_transport_crc_evidence():
    bler, _, failures = semantics._raw_error_rates([{"Status": "PASS"}])
    assert math.isnan(bler) and failures == 0


def test_missing_primary_crc_cannot_be_rescued_by_secondary_alias():
    bler, _, failures = semantics._raw_error_rates([
        {"CRCPass": "NaN", "TBCrcPass": "1"}])
    assert math.isnan(bler) and failures == 0


def test_crc_alias_and_decimal_binary_values_are_observations():
    bler, _, failures = semantics._raw_error_rates([
        {"TBCrcPass": "1.0"}, {"TBCrcPass": "0.0"}])
    assert bler == 0.5 and failures == 1


def test_partial_crc_population_cannot_qualify_a_measured_summary():
    raw = [dict(UEIndex="1", CRCPass=crc, BitErrors="0", BitsCompared="100",
                Throughput_Mbps="10") for crc in ("1", "0", "NaN")]
    row = dict(Direction="DL", UEIndex="1", N_Trials="3", SINR_min_dB="1",
               SINR_p5_dB="1", SINR_median_dB="2", SINR_p95_dB="3", SINR_max_dB="3",
               BLER_overall="0.5", BER_overall="0", Throughput_Mbps_mean="10",
               Goodput_Mbps_mean="5", OfferedThroughput_Mbps_mean="10",
               SourceArtifact="dl_pdsch_trials.csv")
    checks = semantics._audit_derived_link_table(
        "air_interface/csv/live_measured_sinr_summary.csv", list(row), [row],
        {"DL": raw, "UL": []})
    assert any(not check.passed and "crc_outcome_unavailable:1" in check.details
               for check in checks)


@pytest.mark.parametrize("errors,bits", [
    ("NaN", "100"), ("5", "NaN"), ("2", "1"), ("-1", "100"),
    ("0.5", "100"), ("0", "0"), ("Inf", "100"), ("0", "1.5"),
])
def test_ber_aggregates_only_paired_integer_receiver_observations(errors, bits):
    rows = [dict(BitErrors="0", BitsCompared="100"),
            dict(BitErrors="10", BitsCompared="100"),
            dict(BitErrors=errors, BitsCompared=bits)]
    _, ber, _ = semantics._raw_error_rates(rows)
    assert ber == 0.05


def test_unobserved_bit_errors_cannot_be_exported_as_zero_ber():
    _, ber, _ = semantics._raw_error_rates([dict(BitErrors="NaN", BitsCompared="100")])
    assert math.isnan(ber)


def test_ber_is_bit_weighted_not_average_of_trial_rates():
    _, ber, _ = semantics._raw_error_rates([
        dict(BitErrors="10", BitsCompared="100"), dict(BitErrors="30", BitsCompared="900")])
    assert ber == 0.04


@pytest.mark.parametrize("errors,bits", [("2", "1"), ("-1", "100"), ("0.5", "100"), ("0", "1.5")])
def test_browser_ber_rejects_impossible_bit_counts(errors, bits):
    assert m._trial_row_ber(dict(BitErrors=errors, BitsCompared=bits)) is None


def test_configured_sweep_ber_uses_compared_bits_not_mean_trial_ber():
    rows = [dict(Direction="DL", ConfiguredSNR_dB="20", BitErrors=errors, BitsCompared=bits)
            for errors, bits in [("10", "100"), ("30", "900"), ("NaN", "100")]]
    stream = io.StringIO()
    writer = csv.DictWriter(stream, list(rows[0])); writer.writeheader(); writer.writerows(rows)
    path = "air_interface/csv/dl_pdsch_trials.csv"
    result = m._configured_sweep_chart_materialization("dl_ber_vs_snr",
        {path: dict(artifact_id=1, logical_path=path)}, lambda _: stream.getvalue().encode(), 1)
    actual = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    assert len(actual) == 1 and float(actual[0]["BER"]) == 0.04
    assert float(actual[0]["BitsCompared"]) == 1000
    assert float(actual[0]["BitErrors"]) == 40
    assert result["source_row_count"] == 3
    assert int(actual[0]["ObservedTrialCount"]) == 2
    assert int(actual[0]["UnpairedTrialCount"]) == 1
