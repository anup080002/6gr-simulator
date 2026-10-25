"""Lossless TDD-UL-DL-ConfigCommon wire mapping; no host direction fallback.

The production generated RRC codec remains pinned separately. This module
checks the represented IE shape and wire ranges, not waveform reception or
PRACH validity. Runtime numerology/time-map checks belong to the MATLAB owner.
"""
from __future__ import annotations

import math


_PERIODS = {"ms0p5", "ms0p625", "ms1", "ms1p25", "ms2", "ms2p5", "ms5", "ms10"}
_SCS = {"kHz15", "kHz30", "kHz60", "kHz120", "kHz240", "kHz480", "kHz960"}
_PERIOD = "dl_UL_TransmissionPeriodicity"
_EXTENSION = "dl_UL_TransmissionPeriodicity_v1530"
_COUNTS = {"nrofDownlinkSlots": 320, "nrofDownlinkSymbols": 13,
           "nrofUplinkSlots": 320, "nrofUplinkSymbols": 13}
_NAMES = {_PERIOD: "dl-UL-TransmissionPeriodicity",
          _EXTENSION: "dl-UL-TransmissionPeriodicity-v1530"}


def _shape(value, required, optional=()):
    if not isinstance(value, dict) or not set(required) <= value.keys():
        raise ValueError("TDD common IE requires its original mandatory fields")
    if set(value) - set(required) - set(optional):
        raise ValueError("unsupported TDD common IE fields")


def _enum(value, allowed):
    if not isinstance(value, str) or value not in allowed:
        raise ValueError("invalid original TDD common enum")
    return value


def _pattern(value):
    _shape(value, {_PERIOD, *_COUNTS}, {_EXTENSION})
    out = {_NAMES[_PERIOD]: _enum(value[_PERIOD], _PERIODS)}
    for name, upper in _COUNTS.items():
        number = value[name]
        if (isinstance(number, bool) or not isinstance(number, (int, float))
                or not math.isfinite(number) or int(number) != number
                or not 0 <= number <= upper):
            raise ValueError("invalid original TDD common integer")
        out[name] = int(number)
    if _EXTENSION in value:
        out[_NAMES[_EXTENSION]] = _enum(value[_EXTENSION], {"ms3", "ms4"})
    return out


def to_asn1(value):
    _shape(value, {"referenceSubcarrierSpacing", "pattern1"}, {"pattern2"})
    out = {"referenceSubcarrierSpacing": _enum(value["referenceSubcarrierSpacing"], _SCS),
           "pattern1": _pattern(value["pattern1"])}
    if "pattern2" in value:
        out["pattern2"] = _pattern(value["pattern2"])
    return out


def from_asn1(value):
    _shape(value, {"referenceSubcarrierSpacing", "pattern1"}, {"pattern2"})
    out = {"referenceSubcarrierSpacing": value["referenceSubcarrierSpacing"]}
    reverse = {wire: semantic for semantic, wire in _NAMES.items()}
    for name in ("pattern1", "pattern2"):
        if name in value:
            pattern = value[name]
            if not isinstance(pattern, dict):
                raise ValueError("TDD pattern must be an original IE object")
            out[name] = {reverse.get(key, key): item for key, item in pattern.items()}
    if to_asn1(out) != value:
        raise ValueError("TDD common IE cannot be represented losslessly")
    return out
