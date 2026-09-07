"""Generated-codec round trips and fail-closed boundaries, not external vectors."""
import copy
import csv
import json
from pathlib import Path

import pytest

from tools.initial_access import nr_sib1_codec as codec
from tools.initial_access import sib1_common_control as control


def semantic():
    path = Path(__file__).parent / "vectors/initial_access/sib1_release18_uper_vectors.csv"
    with path.open() as handle:
        s = json.loads(next(csv.DictReader(handle))["SemanticJSON"])
    s["pdcch_config_common"] = {
        "commonControlResourceSet": {
            "controlResourceSetId": 1, "frequencyDomainResources": "1111" + "0" * 41,
            "duration": 2, "cce_REG_MappingType": "nonInterleaved",
            "precoderGranularity": "sameAsREG-bundle"},
        "commonSearchSpaceList": [{
            "searchSpaceId": 1, "controlResourceSetId": 1,
            "monitoringSlotPeriodicityAndOffset": {"periodicity": "sl1", "offset": 0},
            "monitoringSymbolsWithinSlot": "10000000000000", "nrofCandidates": [0, 0, 1, 0, 0],
            "searchSpaceType": "common"}], "ra_SearchSpace": 1}
    return s


@pytest.mark.parametrize("interleaved", [False, True])
@pytest.mark.parametrize("period,offset", [("sl1", 0), ("sl20", 3)])
def test_actual_uper_control_and_bwp(interleaved, period, offset):
    s = semantic()
    common = s["pdcch_config_common"]
    c = common["commonControlResourceSet"]
    if interleaved:
        c.update(cce_REG_MappingType="interleaved", reg_BundleSize="n6", interleaverSize="n2", shiftIndex=7)
    ss = common["commonSearchSpaceList"][0]
    ss["monitoringSlotPeriodicityAndOffset"] = {"periodicity": period, "offset": offset}
    s.update(initial_ul_bwp_riv=275 * 51 + 7, initial_ul_bwp_scs_khz=15,
             initial_dl_bwp_riv=275 * 47 + 12, initial_dl_bwp_scs_khz=30)
    payload = codec.CODEC.to_uper(codec.bounded_object(s))
    codec.CODEC.from_uper(payload)
    result = codec.semantic_from_object(codec.CODEC.get_val())
    assert result["pdcch_config_common"] == common
    assert result["initial_ul_bwp_riv"] == s["initial_ul_bwp_riv"]
    assert result["initial_ul_bwp_scs_khz"] == 15
    assert result["cell_identity"] == 17
    result["preamble_format"] = s["preamble_format"]
    assert codec.CODEC.to_uper(codec.bounded_object(result)) == payload


def test_absent_control_stays_absent():
    s = semantic()
    del s["pdcch_config_common"]
    value = codec.bounded_object(s)
    assert "pdcch_config_common" not in codec.semantic_from_object(value)


@pytest.mark.parametrize("offset", [None, "n0", "n25600", "n39936"])
def test_timing_offset_actual_uper_presence_and_value(offset):
    s = semantic()
    if offset is not None:
        s["n_timing_advance_offset"] = offset
    payload = codec.CODEC.to_uper(codec.bounded_object(s))
    codec.CODEC.from_uper(payload)
    raw = codec.CODEC.get_val()
    serving = raw["message"][1][1]["servingCellConfigCommon"]
    assert ("n-TimingAdvanceOffset" in serving) == (offset is not None)
    recovered = codec.semantic_from_object(raw)
    assert ("n_timing_advance_offset" in recovered) == (offset is not None)
    if offset is not None:
        assert serving["n-TimingAdvanceOffset"] == recovered["n_timing_advance_offset"] == offset
    assert codec.CODEC.to_uper(codec.bounded_object(recovered)) == payload


@pytest.mark.parametrize("offset", ["", "n13792", "spare1", 0, 25600, None])
def test_invalid_present_timing_offset_rejected(offset):
    s = semantic()
    s["n_timing_advance_offset"] = offset
    with pytest.raises(ValueError, match="n-TimingAdvanceOffset"):
        codec.bounded_object(s)


def test_unrepresented_ul_carrier_is_rejected_not_replaced_with_dl():
    value = codec.bounded_object(semantic())
    ul = value["message"][1][1]["servingCellConfigCommon"]["uplinkConfigCommon"]
    ul["frequencyInfoUL"]["scs-SpecificCarrierList"][0]["carrierBandwidth"] = 100
    with pytest.raises(ValueError, match="losslessly"):
        codec.semantic_from_object(value)


def test_independent_generator_non_octet_bit_strings():
    import asn1tools
    from tools.initial_access.generate_release18_sib1_vectors import bits
    independent = asn1tools.compile_string("Test DEFINITIONS ::= BEGIN Identity ::= BIT STRING (SIZE (36)) END", "uper")
    for value in (1, 17, (1 << 36) - 2):
        payload = independent.encode("Identity", bits(value, 36))
        recovered, width = independent.decode("Identity", payload)
        assert width == 36 and int.from_bytes(recovered, "big") >> 4 == value


@pytest.mark.parametrize("mutation", ["unknown", "bad_bitmap", "fractional", "bad_offset", "other_format"])
def test_invalid_or_unsupported_control_is_not_silently_dropped(mutation):
    s = copy.deepcopy(semantic()["pdcch_config_common"])
    ss = s["commonSearchSpaceList"][0]
    if mutation == "unknown": s["invented"] = 1
    if mutation == "bad_bitmap": ss["monitoringSymbolsWithinSlot"] = "10"
    if mutation == "fractional": ss["nrofCandidates"][0] = 1.1
    if mutation == "bad_offset": ss["monitoringSlotPeriodicityAndOffset"]["offset"] = 1
    if mutation == "other_format": ss["searchSpaceType"] = "ue-Specific"
    with pytest.raises(ValueError):
        control.to_asn1(s)
