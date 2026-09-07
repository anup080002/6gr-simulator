"""Lossless bounded PDCCH-ConfigCommon mapping, TS 38.331.

No CORESET, search-space, or RA monitoring policy is supplied by this module.
Absent optional IEs remain absent. Unsupported IEs fail instead of vanishing
when the MATLAB UE reconstructs the decoded message.
"""
from __future__ import annotations


def _keys(value, allowed):
    extra = set(value) - set(allowed)
    if extra:
        raise ValueError(f"unsupported PDCCH-ConfigCommon fields: {sorted(extra)}")


def _bitmap(value, width):
    if not isinstance(value, str) or len(value) != width or set(value) - {"0", "1"}:
        raise ValueError(f"expected a {width}-bit binary string")
    return int(value, 2), width


def _integer(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or int(value) != value:
        raise ValueError("control configuration requires an integer")
    return int(value)


def to_asn1(s):
    _keys(s, ("controlResourceSetZero", "searchSpaceZero", "commonControlResourceSet",
              "commonSearchSpaceList", "ra_SearchSpace"))
    out = {}
    for name in ("controlResourceSetZero", "searchSpaceZero", "ra_SearchSpace"):
        if name in s:
            out[name.replace("ra_SearchSpace", "ra-SearchSpace")] = _integer(s[name])
    if "commonControlResourceSet" in s:
        c = s["commonControlResourceSet"]
        _keys(c, ("controlResourceSetId", "frequencyDomainResources", "duration",
                  "cce_REG_MappingType", "precoderGranularity", "reg_BundleSize",
                  "interleaverSize", "shiftIndex", "pdcch_DMRS_ScramblingID"))
        mapping = c["cce_REG_MappingType"]
        if mapping == "nonInterleaved":
            if any(k in c for k in ("reg_BundleSize", "interleaverSize", "shiftIndex")):
                raise ValueError("nonInterleaved CORESET cannot contain interleaver fields")
            choice = (mapping, 0)
        elif mapping == "interleaved":
            body = {"reg-BundleSize": c["reg_BundleSize"], "interleaverSize": c["interleaverSize"]}
            if "shiftIndex" in c:
                body["shiftIndex"] = _integer(c["shiftIndex"])
            choice = (mapping, body)
        else:
            raise ValueError("unsupported CCE-REG mapping choice")
        coreset = {
            "controlResourceSetId": _integer(c["controlResourceSetId"]),
            "frequencyDomainResources": _bitmap(c["frequencyDomainResources"], 45),
            "duration": _integer(c["duration"]),
            "cce-REG-MappingType": choice,
            "precoderGranularity": c["precoderGranularity"],
        }
        if "pdcch_DMRS_ScramblingID" in c:
            coreset["pdcch-DMRS-ScramblingID"] = _integer(c["pdcch_DMRS_ScramblingID"])
        out["commonControlResourceSet"] = coreset
    if "commonSearchSpaceList" in s:
        items = s["commonSearchSpaceList"]
        if isinstance(items, dict):  # MATLAB serializes a singleton struct as an object.
            items = [items]
        spaces = []
        for item in items:
            _keys(item, ("searchSpaceId", "controlResourceSetId", "monitoringSlotPeriodicityAndOffset",
                         "duration", "monitoringSymbolsWithinSlot", "nrofCandidates", "searchSpaceType"))
            p = item["monitoringSlotPeriodicityAndOffset"]
            _keys(p, ("periodicity", "offset"))
            offset = _integer(p["offset"])
            if p["periodicity"] == "sl1" and offset != 0:
                raise ValueError("sl1 has no nonzero monitoring offset")
            if item["searchSpaceType"] != "common":
                raise ValueError("bounded common search space supports DCI 0_0/1_0 only")
            candidates = item["nrofCandidates"]
            if len(candidates) != 5:
                raise ValueError("nrofCandidates requires counts at AL 1,2,4,8,16")
            space = {
                "searchSpaceId": _integer(item["searchSpaceId"]),
                "controlResourceSetId": _integer(item["controlResourceSetId"]),
                "monitoringSlotPeriodicityAndOffset": (p["periodicity"], offset),
                "monitoringSymbolsWithinSlot": _bitmap(item["monitoringSymbolsWithinSlot"], 14),
                "nrofCandidates": {f"aggregationLevel{al}": f"n{_integer(n)}"
                                   for al, n in zip((1, 2, 4, 8, 16), candidates)},
                "searchSpaceType": ("common", {"dci-Format0-0-AndFormat1-0": {}}),
            }
            if "duration" in item:
                space["duration"] = _integer(item["duration"])
            spaces.append(space)
        out["commonSearchSpaceList"] = spaces
    return out


def from_asn1(value):
    _keys(value, ("controlResourceSetZero", "searchSpaceZero", "commonControlResourceSet",
                  "commonSearchSpaceList", "ra-SearchSpace"))
    s = {}
    for name in ("controlResourceSetZero", "searchSpaceZero", "ra-SearchSpace"):
        if name in value:
            s[name.replace("ra-SearchSpace", "ra_SearchSpace")] = value[name]
    if "commonControlResourceSet" in value:
        c = value["commonControlResourceSet"]
        _keys(c, ("controlResourceSetId", "frequencyDomainResources", "duration",
                  "cce-REG-MappingType", "precoderGranularity", "pdcch-DMRS-ScramblingID"))
        mapping, body = c["cce-REG-MappingType"]
        coreset = {
            "controlResourceSetId": c["controlResourceSetId"],
            "frequencyDomainResources": format(c["frequencyDomainResources"][0], "045b"),
            "duration": c["duration"], "cce_REG_MappingType": mapping,
            "precoderGranularity": c["precoderGranularity"],
        }
        if mapping == "interleaved":
            _keys(body, ("reg-BundleSize", "interleaverSize", "shiftIndex"))
            coreset.update({k.replace("reg-BundleSize", "reg_BundleSize"): v for k, v in body.items()})
        if "pdcch-DMRS-ScramblingID" in c:
            coreset["pdcch_DMRS_ScramblingID"] = c["pdcch-DMRS-ScramblingID"]
        s["commonControlResourceSet"] = coreset
    if "commonSearchSpaceList" in value:
        spaces = []
        for item in value["commonSearchSpaceList"]:
            _keys(item, ("searchSpaceId", "controlResourceSetId", "monitoringSlotPeriodicityAndOffset",
                         "duration", "monitoringSymbolsWithinSlot", "nrofCandidates", "searchSpaceType"))
            kind, formats = item["searchSpaceType"]
            if kind != "common" or formats != {"dci-Format0-0-AndFormat1-0": {}}:
                raise ValueError("unsupported common search-space DCI formats")
            period, offset = item["monitoringSlotPeriodicityAndOffset"]
            space = {
                "searchSpaceId": item["searchSpaceId"],
                "controlResourceSetId": item["controlResourceSetId"],
                "monitoringSlotPeriodicityAndOffset": {"periodicity": period, "offset": offset},
                "monitoringSymbolsWithinSlot": format(item["monitoringSymbolsWithinSlot"][0], "014b"),
                "nrofCandidates": [int(item["nrofCandidates"][f"aggregationLevel{al}"][1:])
                                   for al in (1, 2, 4, 8, 16)],
                "searchSpaceType": "common",
            }
            if "duration" in item:
                space["duration"] = item["duration"]
            spaces.append(space)
        s["commonSearchSpaceList"] = spaces
    # Verify supported fields/choices survive our boundary without substitution.
    if to_asn1(s) != value:
        raise ValueError("PDCCH-ConfigCommon cannot be represented losslessly")
    return s
