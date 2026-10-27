"""Lossless base PUSCH-ConfigCommon; TS 38.331 V18.8.0 pp983–984,990–991.

This validates represented ASN.1 operands. It does not install a grant, infer
an absent list, or claim physical reception. Extensions remain fail-closed.
"""
from typing import Any

_FIELDS = {
    "groupHoppingEnabledTransformPrecoding": "groupHoppingEnabledTransformPrecoding",
    "pusch_TimeDomainAllocationList": "pusch-TimeDomainAllocationList",
    "msg3_DeltaPreamble": "msg3-DeltaPreamble",
    "p0_NominalWithGrant": "p0-NominalWithGrant",
}


def _integer(value: Any, lower: int, upper: int, name: str) -> int:
    if type(value) is not int or not lower <= value <= upper:
        raise ValueError(f"{name} requires an integer in [{lower},{upper}]")
    return value


def to_asn1(value: dict[str, Any]) -> dict[str, Any]:
    if type(value) is not dict or set(value) - set(_FIELDS):
        raise ValueError("unsupported PUSCH-ConfigCommon fields")
    result: dict[str, Any] = {}
    for key, raw in value.items():
        name = _FIELDS[key]
        if key == "groupHoppingEnabledTransformPrecoding":
            if raw != "enabled":
                raise ValueError("groupHoppingEnabledTransformPrecoding must be enabled or absent")
            result[name] = raw
        elif key == "msg3_DeltaPreamble":
            result[name] = _integer(raw, -1, 6, key)
        elif key == "p0_NominalWithGrant":
            result[name] = _integer(raw, -202, 24, key)
            if raw % 2:
                raise ValueError("p0-NominalWithGrant permits only even dBm values")
        else:
            # MATLAB JSON encodes a singleton struct array as an object.
            rows = [raw] if type(raw) is dict else raw
            if type(rows) is not list or not 1 <= len(rows) <= 16:
                raise ValueError("pusch-TimeDomainAllocationList requires 1..16 rows")
            result[name] = []
            for row in rows:
                if type(row) is not dict or set(row) - {"k2", "mappingType", "startSymbolAndLength"}:
                    raise ValueError("unsupported PUSCH time-domain row fields")
                if row.get("mappingType") not in {"typeA", "typeB"}:
                    raise ValueError("PUSCH mappingType requires typeA/typeB")
                out = {"mappingType": row["mappingType"], "startSymbolAndLength":
                       _integer(row.get("startSymbolAndLength"), 0, 127, "startSymbolAndLength")}
                if "k2" in row:
                    out["k2"] = _integer(row["k2"], 0, 32, "k2")
                result[name].append(out)
    return result


def from_asn1(value: dict[str, Any]) -> dict[str, Any]:
    if type(value) is not dict or set(value) - set(_FIELDS.values()):
        raise ValueError("unsupported received PUSCH-ConfigCommon fields")
    inverse = {wire: semantic for semantic, wire in _FIELDS.items()}
    result = {inverse[key]: raw for key, raw in value.items()}
    if to_asn1(result) != value:
        raise ValueError("PUSCH-ConfigCommon cannot be represented losslessly")
    return result
