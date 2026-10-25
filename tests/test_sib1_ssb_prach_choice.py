"""Actual SIB1 UPER CHOICE round trips; no PHY/RO-association claim.

The wire domains below are pinned to TS 38.331 V18.8.0 RACH-ConfigCommon.
The repository's independent full-message vectors retain their original
V18.9.0 source/version. No scenario or association policy is changed here.
"""
import copy
import csv
import json
from pathlib import Path

import pytest

from tools.initial_access import nr_sib1_codec as codec


CHOICE_FIELD = "ssb-perRACH-OccasionAndCB-PreamblesPerSSB"
ENUM_MAX = {"oneEighth": 64, "oneFourth": 64, "oneHalf": 64,
            "one": 64, "two": 32}
INTEGER_MAX = {"four": 16, "eight": 8, "sixteen": 4}
VALID_CASES = [(choice, f"n{n}") for choice, maximum in ENUM_MAX.items()
               for n in range(4, maximum + 1, 4)]
VALID_CASES += [(choice, n) for choice, maximum in INTEGER_MAX.items()
                for n in range(1, maximum + 1)]


def vector_rows():
    path = Path(__file__).parent / "vectors/initial_access/sib1_release18_uper_vectors.csv"
    with path.open() as handle:
        return list(csv.DictReader(handle))


def semantic():
    return json.loads(vector_rows()[0]["SemanticJSON"])


def rach(raw):
    return raw["message"][1][1]["servingCellConfigCommon"][
        "uplinkConfigCommon"]["initialUplinkBWP"]["rach-ConfigCommon"][1]


def roundtrip(s):
    original = copy.deepcopy(s)
    raw = codec.bounded_object(s)
    payload = codec.CODEC.to_uper(raw)
    codec.CODEC.from_uper(payload)
    decoded = copy.deepcopy(codec.CODEC.get_val())
    assert decoded == raw
    recovered = codec.semantic_from_object(decoded)
    assert codec.CODEC.to_uper(codec.bounded_object(recovered)) == payload
    assert s == original
    return recovered, decoded, payload


@pytest.mark.parametrize("choice,count", VALID_CASES)
def test_every_valid_asn1_choice_value_roundtrips(choice, count):
    s = semantic()
    s.update(ssb_per_rach_choice=choice, cb_preambles_per_ssb=count)
    result, raw, _ = roundtrip(s)
    assert rach(raw)[CHOICE_FIELD] == (choice, count)
    assert type(rach(raw)[CHOICE_FIELD][1]) is type(count)
    assert result["ssb_per_rach_choice"] == choice
    assert result["cb_preambles_per_ssb"] == count
    assert type(result["cb_preambles_per_ssb"]) is type(count)


@pytest.mark.parametrize("choice,count", [
    (choice, n) for choice, maximum in INTEGER_MAX.items()
    for n in range(1, maximum + 1)])
def test_matlab_decimal_text_uses_integer_wire_arm(choice, count):
    s = semantic()
    s.update(ssb_per_rach_choice=choice, cb_preambles_per_ssb=str(count))
    result, raw, payload = roundtrip(s)
    assert rach(raw)[CHOICE_FIELD] == (choice, count)
    assert type(result["cb_preambles_per_ssb"]) is int
    s["cb_preambles_per_ssb"] = count
    assert codec.CODEC.to_uper(codec.bounded_object(s)) == payload


@pytest.mark.parametrize("choice", tuple(ENUM_MAX))
@pytest.mark.parametrize("bad", [None, True, 4, 4.0, "4", "n0", "n1", "n5",
                                  "n68", "n04", "N4", " n4", "n4 ", [], {}])
def test_enum_arm_rejects_wrong_type_and_domain(choice, bad):
    s = semantic()
    s.update(ssb_per_rach_choice=choice, cb_preambles_per_ssb=bad)
    with pytest.raises(ValueError, match="CB-preambles-per-SSB"):
        codec.bounded_object(s)


@pytest.mark.parametrize("choice,maximum", tuple(INTEGER_MAX.items()))
@pytest.mark.parametrize("bad", [None, True, False, 1.0, 1.5, float("nan"),
                                  float("inf"), 0, -1, "0", "-1", "n4", "04",
                                  " 4", "4 ", "+4", "4.0", "4e0", "\u0664", [], {}])
def test_integer_arm_rejects_coercion_and_invalid_domain(choice, maximum, bad):
    s = semantic()
    s.update(ssb_per_rach_choice=choice, cb_preambles_per_ssb=bad)
    with pytest.raises(ValueError, match="CB-preambles-per-SSB"):
        codec.bounded_object(s)


@pytest.mark.parametrize("choice", tuple(ENUM_MAX) + tuple(INTEGER_MAX))
def test_original_choice_specific_upper_bound(choice):
    s = semantic()
    maximum = ENUM_MAX.get(choice, INTEGER_MAX.get(choice))
    invalid = (f"n{maximum + 4}" if choice in ENUM_MAX else maximum + 1)
    s.update(ssb_per_rach_choice=choice, cb_preambles_per_ssb=invalid)
    with pytest.raises(ValueError, match="CB-preambles-per-SSB"):
        codec.bounded_object(s)
    if choice in INTEGER_MAX:
        s["cb_preambles_per_ssb"] = str(invalid)
        with pytest.raises(ValueError, match="CB-preambles-per-SSB"):
            codec.bounded_object(s)


@pytest.mark.parametrize("bad", [None, True, 4, "Four", "4", "zero", "", [], {}])
def test_unknown_or_coerced_choice_rejected(bad):
    s = semantic()
    s["ssb_per_rach_choice"] = bad
    with pytest.raises(ValueError, match="ssb-perRACH"):
        codec.bounded_object(s)


@pytest.mark.parametrize("bad", [("four", "4"), ("four", True), ("four", 4.0),
                                  ("four", 17), ("two", "n36"), ("one", 4),
                                  ["one", "n64"], (), ("one",), None])
def test_decoded_choice_not_retyped_or_repaired(bad):
    raw = codec.bounded_object(semantic())
    rach(raw)[CHOICE_FIELD] = bad
    with pytest.raises(ValueError):
        codec.semantic_from_object(raw)


@pytest.mark.parametrize("choice", tuple(ENUM_MAX) + tuple(INTEGER_MAX))
def test_choice_preserves_original_tdd_extension_and_pattern2(choice):
    s = semantic()
    pattern = dict(dl_UL_TransmissionPeriodicity="ms10", nrofDownlinkSlots=1,
                   nrofDownlinkSymbols=0, nrofUplinkSlots=1, nrofUplinkSymbols=0)
    s["tdd_ul_dl_config_common"] = dict(
        referenceSubcarrierSpacing="kHz30", pattern1=dict(pattern),
        pattern2=dict(pattern, dl_UL_TransmissionPeriodicity="ms2"))
    s["tdd_ul_dl_config_common"]["pattern1"]["dl_UL_TransmissionPeriodicity_v1530"] = "ms3"
    s.update(ssb_per_rach_choice=choice,
             cb_preambles_per_ssb="n4" if choice in ENUM_MAX else "1")
    recovered, _, _ = roundtrip(s)
    assert recovered["tdd_ul_dl_config_common"] == s["tdd_ul_dl_config_common"]


def test_all_independent_full_message_vectors_stay_byte_identical():
    rows = vector_rows()
    positive = [row for row in rows if row["ExpectedBehavior"] == "ACCEPT"]
    assert positive
    # The same catalog also has intentionally malformed/rejected payloads,
    # which have no SemanticJSON and are not encoding references.
    assert all(row["ExpectedBehavior"] in {"ACCEPT", "REJECT"} for row in rows)
    for row in positive:
        s = json.loads(row["SemanticJSON"])
        recovered, raw, payload = roundtrip(s)
        assert payload.hex().upper() == row["UPERHex"].upper()
        assert recovered["ssb_per_rach_choice"] == s["ssb_per_rach_choice"]
        assert recovered["cb_preambles_per_ssb"] == s["cb_preambles_per_ssb"]
        assert rach(raw)[CHOICE_FIELD] == (s["ssb_per_rach_choice"], s["cb_preambles_per_ssb"])
