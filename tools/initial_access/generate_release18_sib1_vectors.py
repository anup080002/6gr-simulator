#!/usr/bin/env python3
"""Generate independent NR SIB1 UPER vectors with official ASN.1 + asn1tools."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
from typing import Any

import asn1tools


# 3GPP publishes the raw ASN.1 module in 38331-i90.zip.  The raw module
# contains parameterized ASN.1 that asn1tools cannot compile directly, so the
# generator consumes the deterministic expanded module while recording the
# hash of the unmodified official module in every reference row.
OFFICIAL_SCHEMA_SHA256 = (
    "29e55635561822bf625d9170f050552d65047c334a3c0a8a47797c8df1985db5"
)
COMPILE_SCHEMA_SHA256 = (
    "e1171504285f07df8e46d1b7b950baaf1333ab5706a6731f62d8fcf6c744b4d1"
)
ARCHIVE_SHA256 = "8089df60eeb3bc2a223cc13d32f2ed709f89e5124f771d6cf6d81ed52fbbb7f6"
SOURCE_URL = "https://www.3gpp.org/ftp/Specs/archive/38_series/38.331/38331-i90.zip"


def bits(value: int, width: int) -> tuple[bytes, int]:
    return value.to_bytes((width + 7) // 8, "big"), width


def object_from_semantic(s: dict[str, Any]) -> dict[str, Any]:
    scs = f"kHz{int(s['subcarrier_spacing_khz'])}"
    bandwidth = int(s["carrier_bandwidth_rb"])
    fmt = str(s["preamble_format"]).upper()
    root_choice = "l839" if fmt in {"0", "1", "2", "3"} else "l139"
    generic = {
        "prach-ConfigurationIndex": int(s["prach_configuration_index"]),
        "msg1-FDM": s["msg1_fdm"],
        "msg1-FrequencyStart": int(s["msg1_frequency_start"]),
        "zeroCorrelationZoneConfig": int(s["zero_correlation_zone"]),
        "preambleReceivedTargetPower": int(
            s["preamble_received_target_power_dbm"]
        ),
        "preambleTransMax": s["preamble_trans_max"],
        "powerRampingStep": s["power_ramping_step"],
        "ra-ResponseWindow": s["ra_response_window"],
    }
    rach: dict[str, Any] = {
        "rach-ConfigGeneric": generic,
        "ssb-perRACH-OccasionAndCB-PreamblesPerSSB": (
            s["ssb_per_rach_choice"],
            s["cb_preambles_per_ssb"],
        ),
        "ra-ContentionResolutionTimer": s["contention_resolution_timer"],
        "prach-RootSequenceIndex": (
            root_choice,
            int(s["root_sequence_index"]),
        ),
        "restrictedSetConfig": s["restricted_set_config"],
    }
    if root_choice == "l139":
        rach["msg1-SubcarrierSpacing"] = (
            f"kHz{int(float(s['msg1_subcarrier_spacing_khz']))}"
        )
    if int(s["num_preambles"]) != 64:
        rach["totalNumberOfRA-Preambles"] = int(s["num_preambles"])
    sib = {
        "cellSelectionInfo": {
            "q-RxLevMin": int(s["q_rx_lev_min"]),
            "q-QualMin": int(s["q_qual_min"]),
        },
        "cellAccessRelatedInfo": {
            "plmn-IdentityInfoList": [
                {
                    "plmn-IdentityList": [
                        {
                            "mcc": [int(x) for x in s["mcc"]],
                            "mnc": [int(x) for x in s["mnc"]],
                        }
                    ],
                    "trackingAreaCode": bits(int(s["tracking_area_code"]), 24),
                    "cellIdentity": bits(int(s["cell_identity"]), 36),
                    "cellReservedForOperatorUse": s["cell_reserved"],
                }
            ]
        },
        "si-SchedulingInfo": {
            "schedulingInfoList": [
                {
                    "si-BroadcastStatus": s["si_broadcast_status"],
                    "si-Periodicity": s["si_periodicity"],
                    "sib-MappingInfo": [{"type": s["mapped_sib_type"]}],
                }
            ],
            "si-WindowLength": s["si_window_length"],
        },
        "servingCellConfigCommon": {
            "downlinkConfigCommon": {
                "frequencyInfoDL": {
                    "frequencyBandList": [
                        {"freqBandIndicatorNR": int(s["band"])}
                    ],
                    "offsetToPointA": int(s["offset_to_point_a"]),
                    "scs-SpecificCarrierList": [
                        {
                            "offsetToCarrier": 0,
                            "subcarrierSpacing": scs,
                            "carrierBandwidth": bandwidth,
                        }
                    ],
                },
                "initialDownlinkBWP": {
                    "genericParameters": {
                        "locationAndBandwidth": 275 * (bandwidth - 1),
                        "subcarrierSpacing": scs,
                    }
                },
                "bcch-Config": {
                    "modificationPeriodCoeff": s[
                        "modification_period_coeff"
                    ]
                },
                "pcch-Config": {
                    "defaultPagingCycle": s["default_paging_cycle"],
                    "nAndPagingFrameOffset": (
                        s["paging_frame_choice"],
                        None
                        if s["paging_frame_choice"] == "oneT"
                        else int(s["paging_frame_offset"]),
                    ),
                    "ns": s["paging_ns"],
                },
            },
            "uplinkConfigCommon": {
                "frequencyInfoUL": {
                    "frequencyBandList": [
                        {"freqBandIndicatorNR": int(s["band"])}
                    ],
                    "absoluteFrequencyPointA": int(
                        s["absolute_frequency_point_a"]
                    ),
                    "scs-SpecificCarrierList": [
                        {
                            "offsetToCarrier": 0,
                            "subcarrierSpacing": scs,
                            "carrierBandwidth": bandwidth,
                        }
                    ],
                },
                "initialUplinkBWP": {
                    "genericParameters": {
                        "locationAndBandwidth": 275 * (bandwidth - 1),
                        "subcarrierSpacing": scs,
                    },
                    "rach-ConfigCommon": ("setup", rach),
                },
                "timeAlignmentTimerCommon": s["time_alignment_timer"],
            },
            "ssb-PositionsInBurst": {
                "inOneGroup": bits(int(s["ssb_positions_in_burst"], 2), 8)
            },
            "ssb-PeriodicityServingCell": s["ssb_periodicity"],
            "ss-PBCH-BlockPower": int(s["ss_pbch_block_power_dbm"]),
        },
        "ue-TimersAndConstants": {
            key: s[key]
            for key in ("t300", "t301", "t310", "n310", "t311", "n311", "t319")
        },
    }
    return {"message": ("c1", ("systemInformationBlockType1", sib))}


def baseline() -> dict[str, Any]:
    return {
        "mcc": "001",
        "mnc": "01",
        "tracking_area_code": 1,
        "cell_identity": 17,
        "cell_reserved": "notReserved",
        "q_rx_lev_min": -70,
        "q_qual_min": -20,
        "band": 78,
        "offset_to_point_a": 0,
        "subcarrier_spacing_khz": 30,
        "carrier_bandwidth_rb": 51,
        "absolute_frequency_point_a": 666667,
        "prach_configuration_index": 16,
        "preamble_format": "0",
        "msg1_fdm": "one",
        "msg1_frequency_start": 0,
        "zero_correlation_zone": 8,
        "preamble_received_target_power_dbm": -100,
        "preamble_trans_max": "n10",
        "power_ramping_step": "dB2",
        "ra_response_window": "sl8",
        "ssb_per_rach_choice": "one",
        "cb_preambles_per_ssb": "n64",
        "contention_resolution_timer": "sf64",
        "root_sequence_index": 1,
        "msg1_subcarrier_spacing_khz": 1.25,
        "restricted_set_config": "unrestrictedSet",
        "num_preambles": 64,
        "si_broadcast_status": "broadcasting",
        "si_periodicity": "rf16",
        "mapped_sib_type": "sibType2",
        "si_window_length": "s20",
        "modification_period_coeff": "n2",
        "default_paging_cycle": "rf128",
        "paging_frame_choice": "oneT",
        "paging_frame_offset": 0,
        "paging_ns": "one",
        "time_alignment_timer": "infinity",
        "ssb_positions_in_burst": "10000000",
        "ssb_periodicity": "ms20",
        "ss_pbch_block_power_dbm": -25,
        "t300": "ms200",
        "t301": "ms200",
        "t310": "ms100",
        "n310": "n1",
        "t311": "ms1000",
        "n311": "n1",
        "t319": "ms200",
    }


def variants() -> list[tuple[str, str, dict[str, Any]]]:
    one = baseline()
    two = baseline() | {
        "band": 3,
        "subcarrier_spacing_khz": 15,
        "carrier_bandwidth_rb": 106,
        "absolute_frequency_point_a": 368500,
        "prach_configuration_index": 100,
        "preamble_format": "A1",
        "msg1_subcarrier_spacing_khz": 15,
        "ssb_periodicity": "ms10",
    }
    three = baseline() | {"restricted_set_config": "restrictedSetTypeA"}
    four = baseline() | {"restricted_set_config": "restrictedSetTypeB"}
    five = baseline() | {
        "mnc": "001",
        "tracking_area_code": 0xFFFFFE,
        "cell_identity": (1 << 36) - 2,
        "carrier_bandwidth_rb": 106,
        "msg1_fdm": "eight",
        "msg1_frequency_start": 12,
        "num_preambles": 63,
        "preamble_trans_max": "n200",
        "power_ramping_step": "dB6",
        "ra_response_window": "sl80",
        "si_periodicity": "rf512",
        "si_window_length": "s160",
        "ssb_positions_in_burst": "11111111",
    }
    return [
        ("SIB1-UPER-001", "baseline_fr1_30khz", one),
        ("SIB1-UPER-002", "case_a_15khz", two),
        ("SIB1-UPER-003", "restricted_set_type_a", three),
        ("SIB1-UPER-004", "restricted_set_type_b", four),
        ("SIB1-UPER-005", "bounded_optional_load", five),
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("schema", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if (
        hashlib.sha256(args.schema.read_bytes()).hexdigest()
        != COMPILE_SCHEMA_SHA256
    ):
        raise RuntimeError("expanded official ASN.1 schema hash mismatch")
    codec = asn1tools.compile_files(str(args.schema), "uper")
    rows: list[dict[str, Any]] = []
    positives: list[bytes] = []
    for vector_id, purpose, semantic in variants():
        payload = codec.encode(
            "BCCH-DL-SCH-Message", object_from_semantic(semantic)
        )
        decoded = codec.decode("BCCH-DL-SCH-Message", payload)
        if codec.encode("BCCH-DL-SCH-Message", decoded) != payload:
            raise RuntimeError(f"noncanonical vector {vector_id}")
        positives.append(payload)
        rows.append(
            {
                "VectorID": vector_id,
                "Purpose": purpose,
                "ASN1Version": "3GPP TS 38.331 V18.9.0",
                "EncoderName": "asn1tools",
                "EncoderVersion": asn1tools.__version__,
                "SchemaSHA256": OFFICIAL_SCHEMA_SHA256,
                "CompileSchemaSHA256": COMPILE_SCHEMA_SHA256,
                "SchemaTransformation": "asn1tools_parse_parameterized_types",
                "SemanticJSON": json.dumps(
                    semantic, sort_keys=True, separators=(",", ":")
                ),
                "UPERHex": payload.hex().upper(),
                "NumBits": len(payload) * 8,
                "SHA256": hashlib.sha256(payload).hexdigest(),
                "ExpectedBehavior": "ACCEPT",
                "ExpectedError": "",
                "SourceArchiveSHA256": ARCHIVE_SHA256,
                "SourceURL": SOURCE_URL,
                "SelfConsistencyOnly": "false",
            }
        )
    mutations = [
        ("SIB1-UPER-006", "truncated_payload", positives[0][:-1]),
        ("SIB1-UPER-007", "invalid_constrained_payload", b"\xff\xff"),
        (
            "SIB1-UPER-008",
            "unknown_extension_marker",
            bytes([positives[0][0] | 0x80]) + positives[0][1:],
        ),
    ]
    for vector_id, purpose, payload in mutations:
        rows.append(
            {
                "VectorID": vector_id,
                "Purpose": purpose,
                "ASN1Version": "3GPP TS 38.331 V18.9.0",
                "EncoderName": "asn1tools_mutation",
                "EncoderVersion": asn1tools.__version__,
                "SchemaSHA256": OFFICIAL_SCHEMA_SHA256,
                "CompileSchemaSHA256": COMPILE_SCHEMA_SHA256,
                "SchemaTransformation": "asn1tools_parse_parameterized_types",
                "SemanticJSON": "",
                "UPERHex": payload.hex().upper(),
                "NumBits": len(payload) * 8,
                "SHA256": hashlib.sha256(payload).hexdigest(),
                "ExpectedBehavior": "REJECT",
                "ExpectedError": "sixgr:rrc:asn1:DecodeFailed",
                "SourceArchiveSHA256": ARCHIVE_SHA256,
                "SourceURL": SOURCE_URL,
                "SelfConsistencyOnly": "false",
            }
        )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(
        f"wrote {len(rows)} vectors; "
        f"sha256={hashlib.sha256(args.output.read_bytes()).hexdigest()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
