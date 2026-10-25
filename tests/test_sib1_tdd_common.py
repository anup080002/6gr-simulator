"""Actual generated-codec TDD round trips, not waveform/PRACH qualification."""
import copy
import csv
import json
from pathlib import Path

import pytest

from tools.initial_access import nr_sib1_codec as codec
from tools.initial_access import sib1_tdd_common as tdd


def semantic():
    path = Path(__file__).parent / "vectors/initial_access/sib1_release18_uper_vectors.csv"
    with path.open() as handle:
        return json.loads(next(csv.DictReader(handle))["SemanticJSON"])


def pattern(period="ms2p5", d=3, ds=10, u=1, us=2):
    return dict(dl_UL_TransmissionPeriodicity=period, nrofDownlinkSlots=d,
                nrofDownlinkSymbols=ds, nrofUplinkSlots=u, nrofUplinkSymbols=us)


def roundtrip(s):
    original = copy.deepcopy(s)
    raw = codec.bounded_object(s)
    payload = codec.CODEC.to_uper(raw)
    codec.CODEC.from_uper(payload)
    decoded = codec.CODEC.get_val()
    assert decoded == raw
    result = codec.semantic_from_object(decoded)
    assert codec.CODEC.to_uper(codec.bounded_object(result)) == payload
    assert s == original
    return result, decoded["message"][1][1]["servingCellConfigCommon"]


@pytest.mark.parametrize("period", ["ms0p5", "ms0p625", "ms1", "ms1p25", "ms2", "ms2p5", "ms5", "ms10"])
@pytest.mark.parametrize("scs", ["kHz15", "kHz30", "kHz60"])
def test_actual_wire_period_and_reference_preserved(period, scs):
    # This tests ASN.1 wire ranges only. MATLAB additionally rejects
    # nonintegral slots, overbooked patterns and incompatible BWP clocks.
    s = semantic()
    ie = dict(referenceSubcarrierSpacing=scs, pattern1=pattern(period, 0, 0, 0, 0))
    s["tdd_ul_dl_config_common"] = ie
    recovered, raw = roundtrip(s)
    assert recovered["tdd_ul_dl_config_common"] == ie
    assert raw["tdd-UL-DL-ConfigurationCommon"] == tdd.to_asn1(ie)


@pytest.mark.parametrize("base", ["ms0p5", "ms10"])
@pytest.mark.parametrize("extension", ["ms3", "ms4"])
def test_actual_extension_retains_original_base_and_pattern2(base, extension):
    s = semantic()
    p = pattern(base, 3, 0, 0, 0)
    p["dl_UL_TransmissionPeriodicity_v1530"] = extension
    ie = dict(referenceSubcarrierSpacing="kHz15", pattern1=p,
              pattern2=pattern("ms2", 0, 0, 2, 0))
    s["tdd_ul_dl_config_common"] = ie
    recovered, raw = roundtrip(s)
    assert recovered["tdd_ul_dl_config_common"] == ie
    actual = raw["tdd-UL-DL-ConfigurationCommon"]["pattern1"]
    assert actual["dl-UL-TransmissionPeriodicity"] == base
    assert actual["dl-UL-TransmissionPeriodicity-v1530"] == extension


def test_actual_absence_and_independent_legacy_bytes_unchanged():
    s = semantic()
    recovered, raw = roundtrip(s)
    assert "tdd_ul_dl_config_common" not in recovered
    assert "tdd-UL-DL-ConfigurationCommon" not in raw
    path = Path(__file__).parent / "vectors/initial_access/sib1_release18_uper_vectors.csv"
    with path.open() as handle:
        row = next(csv.DictReader(handle))
    # Existing official-schema independent vector remains byte-identical.
    assert codec.CODEC.to_uper(codec.bounded_object(s)).hex().upper() == row["UPERHex"].upper()


@pytest.mark.parametrize("value", [True, False, None, "3", 0.5, -1, 321, float("nan"), float("inf"), [3]])
def test_invalid_original_count_is_not_coerced(value):
    ie = dict(referenceSubcarrierSpacing="kHz30", pattern1=pattern())
    ie["pattern1"]["nrofDownlinkSlots"] = value
    with pytest.raises(ValueError):
        tdd.to_asn1(ie)


@pytest.mark.parametrize("value", [None, {}, [], True])
def test_present_empty_or_malformed_ie_is_not_absence(value):
    s = semantic()
    s["tdd_ul_dl_config_common"] = value
    with pytest.raises(ValueError):
        codec.bounded_object(s)


def test_unknown_fields_and_malformed_extensions_rejected_both_directions():
    ie = dict(referenceSubcarrierSpacing="kHz30", pattern1=pattern())
    for path in ((), ("pattern1",)):
        bad = copy.deepcopy(ie)
        target = bad if not path else bad[path[0]]
        target["invented"] = 1
        with pytest.raises(ValueError, match="unsupported"):
            tdd.to_asn1(bad)
    raw = tdd.to_asn1(ie)
    raw["pattern1"]["future-extension"] = 1
    with pytest.raises(ValueError, match="unsupported"):
        tdd.from_asn1(raw)
    for bad in ("ms5", True, 3):
        ie["pattern1"]["dl_UL_TransmissionPeriodicity_v1530"] = bad
        with pytest.raises(ValueError):
            tdd.to_asn1(ie)
