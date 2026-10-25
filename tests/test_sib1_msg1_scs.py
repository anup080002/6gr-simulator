"""Actual UPER absence/presence and pinned-table derivation; no PHY claim."""
import copy
import csv
import json
import re
from pathlib import Path

import pytest

from tools.initial_access import nr_sib1_codec as codec


ROOT = Path(__file__).resolve().parents[1]
VECTORS = ROOT / "tests/vectors/initial_access"


def raw_sib1(band=78, index=16, root="l839", scs=1.25):
    with (VECTORS / "sib1_release18_uper_vectors.csv").open() as handle:
        semantic = json.loads(next(csv.DictReader(handle))["SemanticJSON"])
    semantic.update(band=band, prach_configuration_index=index,
                    root_sequence_choice=root, msg1_subcarrier_spacing_khz=scs)
    return codec.bounded_object(semantic)


def serving(raw):
    return raw["message"][1][1]["servingCellConfigCommon"]


def rach(raw):
    return serving(raw)["uplinkConfigCommon"]["initialUplinkBWP"]["rach-ConfigCommon"][1]


def wire_decode(raw):
    original = copy.deepcopy(raw)
    payload = codec.CODEC.to_uper(raw)
    codec.CODEC.from_uper(payload)
    decoded = copy.deepcopy(codec.CODEC.get_val())
    assert decoded == original
    result = codec.semantic_from_object(decoded)
    assert codec.CODEC.to_uper(codec.bounded_object(result)) == payload
    assert raw == original
    return result, decoded


def long_rows():
    with (VECTORS / "prach_release18_reference_catalog.csv").open() as handle:
        # The bounded wire profile carries only the base 0..255 field;
        # unpaired extension indices256..262 require a separate ASN.1 IE.
        return [r for r in csv.DictReader(handle)
                if r["PreambleFormat"] in {"0", "1", "2", "3"}
                and int(r["ConfigurationIndex"]) <= 255]


@pytest.mark.parametrize("row", long_rows(), ids=lambda r: r["DuplexContext"] + "_" + r["ConfigurationIndex"])
def test_all_long_indices_from_independent_pinned_catalog_actual_uper(row):
    band = 1 if row["DuplexContext"] == "FR1_PAIRED_SUL" else 40
    expected = 5.0 if row["PreambleFormat"] == "3" else 1.25
    assert row["SpecRelease"] == "3GPP TS 38.211 V18.8.0"
    raw = raw_sib1(band, int(row["ConfigurationIndex"]))
    assert "msg1-SubcarrierSpacing" not in rach(raw)
    result, decoded = wire_decode(raw)
    assert "msg1-SubcarrierSpacing" not in rach(decoded)
    assert result["msg1_subcarrier_spacing_khz"] == expected


@pytest.mark.parametrize("band", sorted(codec._FR1_PAIRED_BANDS | codec._FR1_UNPAIRED_BANDS))
def test_explicit_supported_band_registry(band):
    # Same index48 has different long formats in paired and unpaired tables.
    expected = 1.25 if band in codec._FR1_PAIRED_BANDS else 5.0
    result, _ = wire_decode(raw_sib1(band, 48))
    assert result["msg1_subcarrier_spacing_khz"] == expected


def test_band_registry_matches_existing_pinned_matlab_catalog():
    source = (ROOT / "+sixgr/+pdsch/PDSCH1024QAMApplicability.m").read_text(encoding="utf-8")
    for name, expected in (("fdd", codec._FR1_PAIRED_BANDS), ("tdd", codec._FR1_UNPAIRED_BANDS)):
        block = re.search(r"\b" + name + r"\s*=\s*\[(.*?)\];", source, re.S).group(1)
        assert {int(x) for x in re.findall(r'"n(\d+)"', block)} == expected


@pytest.mark.parametrize("band", [0, 4, 29, 67, 75, 76, 80, 81, 82, 83, 84, 86, 89, 95, 97, 98, 99, 110, 256, 257, 263])
def test_unknown_sdl_sul_fr2_absence_fails_after_actual_wire_decode(band):
    raw = raw_sib1(band if band else 1)
    if not band:
        # ASN.1 itself excludes band0; exercise the semantic boundary directly.
        serving(raw)["downlinkConfigCommon"]["frequencyInfoDL"]["frequencyBandList"][0]["freqBandIndicatorNR"] = 0
    else:
        payload = codec.CODEC.to_uper(raw)
        codec.CODEC.from_uper(payload)
        raw = copy.deepcopy(codec.CODEC.get_val())
    with pytest.raises(ValueError, match="supported FR1 paired/unpaired band"):
        codec.semantic_from_object(raw)


@pytest.mark.parametrize("band,index", [(1, 87), (1, 255), (40, 67), (40, 255)])
@pytest.mark.parametrize("root", ["l839", "l139"])
def test_absent_short_scs_never_defaults(band, index, root):
    raw = raw_sib1(band, index, root, 30)
    rach(raw).pop("msg1-SubcarrierSpacing", None)
    payload = codec.CODEC.to_uper(raw)
    codec.CODEC.from_uper(payload)
    with pytest.raises(ValueError, match="absent msg1-SubcarrierSpacing"):
        codec.semantic_from_object(codec.CODEC.get_val())


@pytest.mark.parametrize("scs", [15, 30, 60, 120])
def test_explicit_received_short_scs_unchanged(scs):
    result, decoded = wire_decode(raw_sib1(78, 157, "l139", scs))
    assert rach(decoded)["msg1-SubcarrierSpacing"] == f"kHz{scs}"
    assert result["msg1_subcarrier_spacing_khz"] == scs


@pytest.mark.parametrize("field,value", [("band", True), ("band", "40"), ("band", 40.0),
                                         ("index", True), ("index", "40"), ("index", 40.5),
                                         ("index", -1), ("index", float("nan"))])
def test_raw_derivation_operands_are_not_coerced(field, value):
    raw = raw_sib1()
    if field == "band":
        serving(raw)["downlinkConfigCommon"]["frequencyInfoDL"]["frequencyBandList"][0]["freqBandIndicatorNR"] = value
    else:
        rach(raw)["rach-ConfigGeneric"]["prach-ConfigurationIndex"] = value
    with pytest.raises(ValueError):
        codec.semantic_from_object(raw)


def test_different_ul_band_cannot_silently_use_dl_duplex():
    raw = raw_sib1(1, 48)
    serving(raw)["uplinkConfigCommon"]["frequencyInfoUL"]["frequencyBandList"][0]["freqBandIndicatorNR"] = 40
    with pytest.raises(ValueError, match="losslessly"):
        codec.semantic_from_object(raw)


@pytest.mark.parametrize("index", range(256, 263))
def test_extended_indices_cannot_be_substituted_into_base_wire_field(index):
    raw = raw_sib1(40, index)
    with pytest.raises(ValueError, match=r"base prach-ConfigurationIndex.*\[0,255\]"):
        codec.semantic_from_object(raw)
