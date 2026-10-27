"""Actual UPER common-PUSCH preservation, plus independent base-IE encoding."""
import copy
import csv
import json
from pathlib import Path

import pytest
from pycrate_asn1dir import RRCNR

from tools.initial_access import nr_sib1_codec as codec
from tools.initial_access import sib1_pusch_common as common


def semantic():
    path = Path(__file__).parent / "vectors/initial_access/sib1_release18_uper_vectors.csv"
    with path.open() as handle:
        return json.loads(next(csv.DictReader(handle))["SemanticJSON"])


@pytest.mark.parametrize("value", [
    {}, {"msg3_DeltaPreamble": -1}, {"p0_NominalWithGrant": -202},
    {"groupHoppingEnabledTransformPrecoding": "enabled", "msg3_DeltaPreamble": 6,
     "p0_NominalWithGrant": 24, "pusch_TimeDomainAllocationList": [
         {"k2": 0, "mappingType": "typeA", "startSymbolAndLength": 0},
         {"k2": 32, "mappingType": "typeB", "startSymbolAndLength": 127},
         {"mappingType": "typeB", "startSymbolAndLength": 27}]},
])
def test_actual_sib1_uper_lossless(value):
    s = semantic()
    s["pusch_config_common"] = value
    wire = codec.CODEC.to_uper(codec.bounded_object(s))
    codec.CODEC.from_uper(wire)
    decoded = codec.semantic_from_object(codec.CODEC.get_val())
    assert decoded["pusch_config_common"] == value
    assert codec.CODEC.to_uper(codec.bounded_object(decoded)) == wire


def test_absent_common_and_absent_k2_are_not_filled():
    s = semantic()
    assert "pusch_config_common" not in codec.semantic_from_object(codec.bounded_object(s))
    value = {"pusch_TimeDomainAllocationList": {"mappingType": "typeA", "startSymbolAndLength": 27}}
    assert "k2" not in common.to_asn1(value)["pusch-TimeDomainAllocationList"][0]


@pytest.mark.parametrize("value", [
    {"unknown": 1}, {"msg3_DeltaPreamble": 7}, {"msg3_DeltaPreamble": True},
    {"p0_NominalWithGrant": -99}, {"p0_NominalWithGrant": -204},
    {"groupHoppingEnabledTransformPrecoding": "disabled"},
    {"pusch_TimeDomainAllocationList": []},
    *[{"pusch_TimeDomainAllocationList": [{"k2": k, "mappingType": "typeA", "startSymbolAndLength": 27}]} for k in (-1, 33, 1.5, True)],
    {"pusch_TimeDomainAllocationList": [{"mappingType": "typeC", "startSymbolAndLength": 27}]},
    {"pusch_TimeDomainAllocationList": [{"mappingType": "typeA", "startSymbolAndLength": 128}]},
    {"pusch_TimeDomainAllocationList": [{"mappingType": "typeA", "startSymbolAndLength": 27, "extendedK2": 1}]},
])
def test_invalid_or_unrepresented_operands_rejected(value):
    with pytest.raises(ValueError):
        common.to_asn1(value)


def test_received_release_or_extension_rejected():
    raw = codec.bounded_object(semantic())
    ul = raw["message"][1][1]["servingCellConfigCommon"]["uplinkConfigCommon"]["initialUplinkBWP"]
    ul["pusch-ConfigCommon"] = ("release", 0)
    with pytest.raises(ValueError, match="setup"):
        codec.semantic_from_object(raw)
    ul["pusch-ConfigCommon"] = ("setup", {"unknown-r99": 1})
    with pytest.raises(ValueError, match="unsupported received"):
        codec.semantic_from_object(raw)


def test_independent_base_ie_uper():
    import asn1tools
    # Exact base ASN.1 from pinned TS38.331 V18.8.0 pp983,990; independent
    # asn1tools encoder, not the production pycrate encoding algorithm.
    independent = asn1tools.compile_string("""Test DEFINITIONS AUTOMATIC TAGS ::= BEGIN
    PUSCH-ConfigCommon ::= SEQUENCE {
      groupHoppingEnabledTransformPrecoding ENUMERATED {enabled} OPTIONAL,
      pusch-TimeDomainAllocationList SEQUENCE (SIZE(1..16)) OF SEQUENCE {
        k2 INTEGER(0..32) OPTIONAL, mappingType ENUMERATED {typeA,typeB},
        startSymbolAndLength INTEGER(0..127)} OPTIONAL,
      msg3-DeltaPreamble INTEGER(-1..6) OPTIONAL,
      p0-NominalWithGrant INTEGER(-202..24) OPTIONAL, ... }
    END""", "uper")
    native = RRCNR.NR_RRC_Definitions.PUSCH_ConfigCommon
    values = [{}, {"msg3_DeltaPreamble": -1, "p0_NominalWithGrant": -100},
              {"pusch_TimeDomainAllocationList": [
                  {"k2": 4, "mappingType": "typeA", "startSymbolAndLength": 27},
                  {"mappingType": "typeB", "startSymbolAndLength": 42}]}]
    for value in values:
        raw = common.to_asn1(copy.deepcopy(value))
        expected = independent.encode("PUSCH-ConfigCommon", raw)
        assert native.to_uper(raw) == expected
        native.from_uper(expected)
        assert native.get_val() == raw
