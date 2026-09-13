"""SINR limit metadata must survive both CSV derivation and visible plots."""
import csv
import io
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m


CHARTS = ["throughput vs SINR", "PUSCH BLER vs measured SINR"]
FIELDS = [("PostEqSINR_dB", "PostEqSINR"), ("MeasuredTrialSINR_dB", "MeasuredTrialSINR"),
          ("MeasuredSINR_dB", "SINR"), ("MeasuredWidebandSINR_dB", "MeasuredWidebandSINR")]


def render(name, rows):
    columns = list(dict.fromkeys(k for row in rows for k in row))
    stream = io.StringIO()
    writer = csv.DictWriter(stream, fieldnames=columns)
    writer.writeheader()
    writer.writerows(rows)
    payload = stream.getvalue().encode()
    result = m._specialized_chart_materialization(name,
        {"air_interface/csv/ul_pusch_trials.csv": {"artifact_id": 1}}, lambda _: payload, 1)
    return result, list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))


def trial(field="PostEqSINR_dB", stem="PostEqSINR", status="OK_dynamic_range_limited"):
    return {"Direction": "UL", "UEIndex": 1, "Slot": 10, "Frame": 1,
            "CRCPass": 1, "Throughput_Mbps": 2.152, "Goodput_Mbps": 2.152,
            "TruthStatus": "real_lls_evidence", field: 45,
            stem + "Source": "actual_receiver_estimate", stem + "ValueStatus": status,
            stem + "NAReason": "raw estimate 60.08 dB limited to trusted 45 dB",
            stem + "ValueRole": "measured_post_equalization_scheduling_input",
            stem + "MeasurementDomain": "post_equalization_layer_domain",
            "PostEqSINRRawEqualizer_dB": 60.08}


def prefix(name):
    return "sinr" if name == CHARTS[0] else "x"


@pytest.mark.parametrize("name", CHARTS)
@pytest.mark.parametrize("field,stem", FIELDS)
def test_limited_metadata_and_visible_warning(name, field, stem):
    source = trial(field, stem)
    result, rows = render(name, [source])
    r, p = rows[0], prefix(name)
    assert float(r["sinr_db" if p == "sinr" else "x_value"]) == 45
    assert r[p + "_value_status"] == source[stem + "ValueStatus"]
    assert r[p + "_value_reason"] == source[stem + "NAReason"]
    assert r[p + "_value_role"] == source[stem + "ValueRole"]
    assert r[p + "_measurement_domain"] == source[stem + "MeasurementDomain"]
    assert r[p + "_is_limited"] == "True"
    raw = r[p + "_raw_equalizer_db"]
    assert float(raw) == 60.08 if field == "PostEqSINR_dB" else raw == ""
    assert b"Limited values are not raw estimates" in result["img_bytes"]
    assert b"includes limited values" in result["img_bytes"]
    assert b"limited]" in result["img_bytes"]


@pytest.mark.parametrize("name", CHARTS)
def test_actual_limited_capture_keeps_the_plotted_coordinate(name):
    source = Path.cwd() / "docs/lls/evidence_20260913/projected_ul_late_uci_capture_01/air_interface/csv/ul_pusch_trials.csv"
    original = list(csv.DictReader(source.read_text().splitlines()))
    result, rows = render(name, original)
    p = prefix(name)
    assert rows[0][p + "_value_status"] == "OK_dynamic_range_limited"
    assert rows[0][p + "_value_reason"] == original[0]["PostEqSINRNAReason"]
    assert float(rows[0][p + "_raw_equalizer_db"]) == float(original[0]["PostEqSINRRawEqualizer_dB"])
    assert float(rows[0]["sinr_db" if p == "sinr" else "x_value"]) == 45
    assert b"Limited SINR values: 1" in result["img_bytes"]


@pytest.mark.parametrize("name", CHARTS)
@pytest.mark.parametrize("status", ["OK", "", "available"])
def test_unlimited_and_legacy_metadata_not_fabricated(name, status):
    source = trial(status=status)
    source.pop("PostEqSINRRawEqualizer_dB")
    source["PostEqSINRNAReason"] = ""
    result, rows = render(name, [source])
    p = prefix(name)
    assert rows[0][p + "_is_limited"] == "False"
    assert rows[0][p + "_raw_equalizer_db"] == ""
    assert rows[0][p + "_value_status"] == status
    assert b"includes limited values" not in result["img_bytes"]


@pytest.mark.parametrize("name", CHARTS)
@pytest.mark.parametrize("marker", ["fallback", "synthetic", "proxy", "invalid", "unavailable", "unverified"])
def test_rejected_preferred_value_not_rescued_by_numeric_alias(name, marker):
    source = trial(status=marker)
    source.update(MeasuredSINR_dB=12, SINRSource="actual_receiver_alias")
    result, _ = render(name, [source])
    assert result["csv_status"] == "unavailable_exact_reason"
    assert b"includes limited values" not in result["img_bytes"]


@pytest.mark.parametrize("name", CHARTS)
def test_mixed_rows_preserve_separate_limited_series(name):
    limited, normal = trial(), trial(status="OK")
    normal.update(Slot=11, PostEqSINR_dB=20, PostEqSINRNAReason="")
    result, rows = render(name, [limited, normal])
    assert [r[prefix(name) + "_is_limited"] for r in rows] == ["True", "False"]
    assert b"Limited SINR values: 1" in result["img_bytes"]


@pytest.mark.parametrize("name", CHARTS)
def test_configured_snr_and_raw_estimate_are_not_coordinate_substitutes(name):
    source = trial()
    source.pop("PostEqSINR_dB")
    source.update(ConfiguredSNR_dB=45, SNR_dB=45, EVM_rms=0.001)
    result, _ = render(name, [source])
    assert result["csv_status"] == "unavailable_exact_reason"


def test_snr_chart_does_not_inherit_unused_sinr_limit():
    source = trial()
    source.update(AppliedAWGNSNR_dB=60, AppliedAWGNSNRSource="actual_noise_calibration")
    result, rows = render("throughput vs SNR", [source])
    assert float(rows[0]["x_value"]) == 60
    assert "x_is_limited" not in rows[0]
    assert b"includes limited values" not in result["img_bytes"]


@pytest.mark.parametrize("name", CHARTS)
def test_generic_source_alias_cannot_hide_proxy_provenance(name):
    source = trial(status="OK")
    source.pop("PostEqSINRSource")
    source["SINRSource"] = "evm_proxy"
    result, _ = render(name, [source])
    assert result["csv_status"] == "unavailable_exact_reason"


@pytest.mark.parametrize("name", CHARTS)
def test_selected_alternative_owns_its_metadata(name):
    source = trial()
    source.update(PostEqSINR_dB="NaN", MeasuredTrialSINR_dB=12,
                  MeasuredTrialSINRSource="actual_trial_receiver",
                  MeasuredTrialSINRValueStatus="OK", MeasuredTrialSINRNAReason="")
    result, rows = render(name, [source])
    p = prefix(name)
    assert rows[0][p + "_value_status"] == "OK"
    assert rows[0][p + "_value_reason"] == ""
    assert rows[0][p + "_raw_equalizer_db"] == ""
    assert b"includes limited values" not in result["img_bytes"]
