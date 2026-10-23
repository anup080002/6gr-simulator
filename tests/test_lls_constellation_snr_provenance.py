"""Declared rendering fixtures only; these rows are not native PHY evidence."""
import csv
import io
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))
import lls_contract_materializer as m

PATH = "air_interface/csv/ul_constellation_samples.csv"


def _row(**fields):
    return {"Direction": "UL", "Modulation": "QPSK", "LayerIndex": 1, "CodewordIndex": 0,
            "RawEqualizedReal": .25, "RawEqualizedImag": -.75,
            "ReferenceSymbolReal": .5, "ReferenceSymbolImag": -.5,
            "CaptureScope": "paired_sample_preview", **fields}


def _render(rows, chart="post-equalization constellation"):
    columns = list(dict.fromkeys(key for row in rows for key in row))
    payload = m._encode_dict_rows(columns, rows)
    result = m._specialized_chart_materialization(chart, {PATH: {"artifact_id": 1}}, lambda _: payload,
                                                  "declared_snr_caption_fixture")
    plotted = list(csv.DictReader(io.StringIO(result["csv_bytes"].decode())))
    svg = ET.fromstring(result["img_bytes"])
    text = re.sub(r"\s+", " ", " ".join(svg.itertext()))
    return result, plotted, svg, text


@pytest.mark.parametrize("chart", ["post-equalization constellation", "constellation per layer",
                                  "symbol decision error histogram"])
@pytest.mark.parametrize("field,role,label,configured", [
    ("ConfiguredSNR_dB", "configured_parameter", "Configured SNR=45.0 dB", "45.0"),
    ("SNR_dB", "unspecified_source_column", "Source SNR_dB=45.0 dB (role not retained)", ""),
    ("snr_db", "unspecified_source_column", "Source snr_db=45.0 dB (role not retained)", ""),
])
def test_constellation_caption_retains_source_role(chart, field, role, label, configured):
    _, plotted, _, text = _render([_row(**{field: 45})], chart)
    assert len(plotted) == 1
    row = plotted[0]
    assert row["snr_source_field"] == field and row["snr_value_role"] == role
    assert row["snr_source_value_db"] == "45.0" and row["configured_snr_db"] == configured
    assert label in text
    assert not re.search(r"(?<!Configured )\bSNR=45", text)
    assert not any(key.startswith("applied_noise") or key.startswith("measured_snr") for key in row)


@pytest.mark.parametrize("chart", ["post-equalization constellation", "symbol decision error histogram"])
def test_same_value_with_different_source_roles_never_pools(chart):
    result, plotted, svg, text = _render([
        _row(ConfiguredSNR_dB=45), _row(SNR_dB=45), _row(snr_db=45)], chart)
    assert len(plotted) == result["source_row_count"] == 3
    assert len({row["cohort_domain_scope_identity"] for row in plotted}) == 3
    for row in plotted:
        assert row["snr_source_value_db"] == "45.0"
        assert float(row.get("x_value", row.get("EqualizedReal"))) == .25
    assert "Configured SNR=45.0 dB" in text and "Source SNR_dB=45.0 dB" in text
    if chart == "post-equalization constellation":
        panels = [rect for rect in svg.findall("{http://www.w3.org/2000/svg}rect")
                  if rect.get("width") == "320"]
        assert len(panels) == 3
        assert "not an applied/measured noise claim" in text
    else:
        assert all(row["population_sample_count"] == "1" and row["bin_count"] == "1" for row in plotted)


def test_explicit_configured_value_wins_without_relabeling_other_noise_planes():
    _, rows, _, text = _render([_row(ConfiguredSNR_dB=12, SNR_dB=45, AppliedNoiseSNR_dB=7,
                                    MeasuredSINR_dB=3)])
    assert rows[0]["snr_source_field"] == "ConfiguredSNR_dB"
    assert rows[0]["snr_source_value_db"] == rows[0]["configured_snr_db"] == "12.0"
    assert "Configured SNR=12.0 dB" in text and "45.0 dB" not in text


@pytest.mark.parametrize("explicit", ["", "NaN"])
def test_nonfinite_configured_column_does_not_lend_its_role_to_a_legacy_value(explicit):
    _, rows, _, text = _render([_row(ConfiguredSNR_dB=explicit, SNR_dB=45)])
    assert rows[0]["configured_snr_db"] == ""
    assert rows[0]["snr_source_field"] == "SNR_dB"
    assert rows[0]["snr_value_role"] == "unspecified_source_column"
    assert "Configured SNR=" not in text and "role not retained" in text


def test_absent_snr_does_not_gain_an_operating_point_or_decoder_noise_inference():
    _, rows, _, text = _render([_row(SuppliedDecoderNoiseVariance=1e-9)])
    assert rows[0]["snr_source_value_db"] == rows[0]["snr_source_field"] == ""
    assert rows[0]["snr_value_role"] == "unavailable"
    assert rows[0]["configured_snr_db"] == ""
    assert "SNR=" not in text and "Source SNR" not in text
