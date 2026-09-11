#!/usr/bin/env python3
"""Bounded Release-18 NR SIB1 UPER codec used by the MATLAB production path.

The runtime implementation is pycrate's generated NR RRC codec. Independent
acceptance vectors are generated with asn1tools from the official 3GPP
V18.9.0 ASN.1 source; those vectors are intentionally not produced here.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
from typing import Any

from pycrate_asn1dir import RRCNR
if __package__:
    from . import sib1_common_control
else:
    import sib1_common_control


CODEC = RRCNR.NR_RRC_Definitions.BCCH_DL_SCH_Message
VERSION = importlib.metadata.version("pycrate")
PROFILE = "3gpp_ts38331_v18_bounded_fr1_sib1"


def bounded_object(semantic: dict[str, Any]) -> dict[str, Any]:
    mcc = [int(x) for x in str(semantic["mcc"])]
    mnc = [int(x) for x in str(semantic["mnc"])]
    if len(mcc) != 3 or len(mnc) not in (2, 3):
        raise ValueError("PLMN MCC/MNC digit lengths are invalid")
    scs = f"kHz{int(semantic['subcarrier_spacing_khz'])}"
    bandwidth = int(semantic["carrier_bandwidth_rb"])
    if not 1 <= bandwidth <= 275:
        raise ValueError("carrier bandwidth must be in [1,275] RB")
    if bandwidth - 1 <= 275 // 2:
        riv = 275 * (bandwidth - 1)
    else:
        riv = 275 * (275 - bandwidth + 1) + 274
    if "root_sequence_choice" in semantic:
        root_choice = semantic["root_sequence_choice"]
        if root_choice not in {"l839", "l139"}:
            raise ValueError("unsupported PRACH root-sequence choice")
    else:
        fmt = str(semantic["preamble_format"]).upper()
        root_choice = "l839" if fmt in {"0", "1", "2", "3"} else "l139"
    root_max = 837 if root_choice == "l839" else 137
    root = int(semantic["root_sequence_index"])
    if not 0 <= root <= root_max:
        raise ValueError(f"{root_choice} root index is out of range")
    rach = {
        "rach-ConfigGeneric": {
            "prach-ConfigurationIndex": int(semantic["prach_configuration_index"]),
            "msg1-FDM": str(semantic["msg1_fdm"]),
            "msg1-FrequencyStart": int(semantic["msg1_frequency_start"]),
            "zeroCorrelationZoneConfig": int(semantic["zero_correlation_zone"]),
            "preambleReceivedTargetPower": int(
                semantic["preamble_received_target_power_dbm"]
            ),
            "preambleTransMax": str(semantic["preamble_trans_max"]),
            "powerRampingStep": str(semantic["power_ramping_step"]),
            "ra-ResponseWindow": str(semantic["ra_response_window"]),
        },
        "ssb-perRACH-OccasionAndCB-PreamblesPerSSB": (
            str(semantic["ssb_per_rach_choice"]),
            str(semantic["cb_preambles_per_ssb"]),
        ),
        "ra-ContentionResolutionTimer": str(
            semantic["contention_resolution_timer"]
        ),
        "prach-RootSequenceIndex": (root_choice, root),
        "restrictedSetConfig": str(semantic["restricted_set_config"]),
    }
    if root_choice == "l139":
        rach["msg1-SubcarrierSpacing"] = (
            f"kHz{int(float(semantic['msg1_subcarrier_spacing_khz']))}"
        )
    preamble_count = int(semantic["num_preambles"])
    if preamble_count != 64:
        if not 1 <= preamble_count <= 63:
            raise ValueError("totalNumberOfRA-Preambles must be in [1,63] or 64")
        rach["totalNumberOfRA-Preambles"] = preamble_count

    si_mapping = [{"type": str(semantic["mapped_sib_type"])}]
    message = {
        "message": (
            "c1",
            (
                "systemInformationBlockType1",
                {
                    "cellSelectionInfo": {
                        "q-RxLevMin": int(semantic["q_rx_lev_min"]),
                        "q-QualMin": int(semantic["q_qual_min"]),
                    },
                    "cellAccessRelatedInfo": {
                        "plmn-IdentityInfoList": [
                            {
                                "plmn-IdentityList": [
                                    {"mcc": mcc, "mnc": mnc}
                                ],
                                "trackingAreaCode": (
                                    int(semantic["tracking_area_code"]),
                                    24,
                                ),
                                "cellIdentity": (
                                    int(semantic["cell_identity"]),
                                    36,
                                ),
                                "cellReservedForOperatorUse": str(
                                    semantic["cell_reserved"]
                                ),
                            }
                        ]
                    },
                    "si-SchedulingInfo": {
                        "schedulingInfoList": [
                            {
                                "si-BroadcastStatus": str(
                                    semantic["si_broadcast_status"]
                                ),
                                "si-Periodicity": str(
                                    semantic["si_periodicity"]
                                ),
                                "sib-MappingInfo": si_mapping,
                            }
                        ],
                        "si-WindowLength": str(semantic["si_window_length"]),
                    },
                    "servingCellConfigCommon": {
                        "downlinkConfigCommon": {
                            "frequencyInfoDL": {
                                "frequencyBandList": [
                                    {
                                        "freqBandIndicatorNR": int(
                                            semantic["band"]
                                        )
                                    }
                                ],
                                "offsetToPointA": int(
                                    semantic["offset_to_point_a"]
                                ),
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
                                    "locationAndBandwidth": riv,
                                    "subcarrierSpacing": scs,
                                }
                            },
                            "bcch-Config": {
                                "modificationPeriodCoeff": str(
                                    semantic["modification_period_coeff"]
                                )
                            },
                            "pcch-Config": {
                                "defaultPagingCycle": str(
                                    semantic["default_paging_cycle"]
                                ),
                                "nAndPagingFrameOffset": (
                                    str(semantic["paging_frame_choice"]),
                                    int(semantic["paging_frame_offset"]),
                                ),
                                "ns": str(semantic["paging_ns"]),
                            },
                        },
                        "uplinkConfigCommon": {
                            "frequencyInfoUL": {
                                "frequencyBandList": [
                                    {
                                        "freqBandIndicatorNR": int(
                                            semantic["band"]
                                        )
                                    }
                                ],
                                "absoluteFrequencyPointA": int(
                                    semantic["absolute_frequency_point_a"]
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
                                    "locationAndBandwidth": riv,
                                    "subcarrierSpacing": scs,
                                },
                                "rach-ConfigCommon": ("setup", rach),
                            },
                            "timeAlignmentTimerCommon": str(
                                semantic["time_alignment_timer"]
                            ),
                        },
                        "ssb-PositionsInBurst": {
                            "inOneGroup": (
                                int(str(semantic["ssb_positions_in_burst"]), 2),
                                8,
                            )
                        },
                        "ssb-PeriodicityServingCell": str(
                            semantic["ssb_periodicity"]
                        ),
                        "ss-PBCH-BlockPower": int(
                            semantic["ss_pbch_block_power_dbm"]
                        ),
                    },
                    "ue-TimersAndConstants": {
                        "t300": str(semantic["t300"]),
                        "t301": str(semantic["t301"]),
                        "t310": str(semantic["t310"]),
                        "n310": str(semantic["n310"]),
                        "t311": str(semantic["t311"]),
                        "n311": str(semantic["n311"]),
                        "t319": str(semantic["t319"]),
                    },
                },
            ),
        )
    }
    serving = message["message"][1][1]["servingCellConfigCommon"]
    if "n_timing_advance_offset" in semantic:
        offset = semantic["n_timing_advance_offset"]
        if offset not in ("n0", "n25600", "n39936"):
            raise ValueError("n-TimingAdvanceOffset requires n0, n25600 or n39936")
        serving["n-TimingAdvanceOffset"] = offset
    for direction, common, bwp in (("dl", "downlinkConfigCommon", "initialDownlinkBWP"),
                                   ("ul", "uplinkConfigCommon", "initialUplinkBWP")):
        generic = serving[common][bwp]["genericParameters"]
        if f"initial_{direction}_bwp_riv" in semantic:
            generic["locationAndBandwidth"] = sib1_common_control._integer(semantic[f"initial_{direction}_bwp_riv"])
            generic["subcarrierSpacing"] = f"kHz{sib1_common_control._integer(semantic[f'initial_{direction}_bwp_scs_khz'])}"
        if semantic.get(f"initial_{direction}_bwp_cyclic_prefix", "normal") == "extended":
            generic["cyclicPrefix"] = "extended"
        elif semantic.get(f"initial_{direction}_bwp_cyclic_prefix", "normal") != "normal":
            raise ValueError("unsupported BWP cyclic prefix")
    if "pdcch_config_common" in semantic:
        serving["downlinkConfigCommon"]["initialDownlinkBWP"]["pdcch-ConfigCommon"] = (
            "setup", sib1_common_control.to_asn1(semantic["pdcch_config_common"]))
    if "pucch_config_common" in semantic:
        spec = semantic["pucch_config_common"]
        allowed = {
            "pucch_ResourceCommon", "pucch_GroupHopping", "hoppingId", "p0_nominal"
        }
        unknown = set(spec) - allowed
        if unknown:
            raise ValueError(
                "unsupported bounded pucch-ConfigCommon field(s): "
                + ", ".join(sorted(unknown))
            )
        hopping = str(spec["pucch_GroupHopping"])
        if hopping not in {"neither", "enable", "disable"}:
            raise ValueError("unsupported pucch-GroupHopping value")
        common: dict[str, Any] = {"pucch-GroupHopping": hopping}
        for semantic_name, asn1_name, lower, upper in (
            ("pucch_ResourceCommon", "pucch-ResourceCommon", 0, 15),
            ("hoppingId", "hoppingId", 0, 1023),
            ("p0_nominal", "p0-nominal", -202, 24),
        ):
            if semantic_name in spec:
                number = int(spec[semantic_name])
                if number != spec[semantic_name] or not lower <= number <= upper:
                    raise ValueError(f"{semantic_name} is out of range")
                common[asn1_name] = number
        serving["uplinkConfigCommon"]["initialUplinkBWP"]["pucch-ConfigCommon"] = (
            "setup", common
        )
    return message


def semantic_from_object(value: dict[str, Any]) -> dict[str, Any]:
    choice, inner = value["message"]
    if choice != "c1" or inner[0] != "systemInformationBlockType1":
        raise ValueError("BCCH-DL-SCH message is not SIB1")
    sib = inner[1]
    cell = sib["cellAccessRelatedInfo"]["plmn-IdentityInfoList"][0]
    plmn = cell["plmn-IdentityList"][0]
    serving = sib["servingCellConfigCommon"]
    dl = serving["downlinkConfigCommon"]
    ul = serving["uplinkConfigCommon"]
    dl_carrier = dl["frequencyInfoDL"]["scs-SpecificCarrierList"][0]
    rach = ul["initialUplinkBWP"]["rach-ConfigCommon"]
    if rach[0] != "setup":
        raise ValueError("rach-ConfigCommon is not setup")
    rach = rach[1]
    generic = rach["rach-ConfigGeneric"]
    root_choice, root_index = rach["prach-RootSequenceIndex"]
    si = sib["si-SchedulingInfo"]
    schedule = si["schedulingInfoList"][0]
    mapped = schedule["sib-MappingInfo"][0]["type"]
    ssb_bits = serving["ssb-PositionsInBurst"]["inOneGroup"]
    semantic = {
        "mcc": "".join(str(x) for x in plmn["mcc"]),
        "mnc": "".join(str(x) for x in plmn["mnc"]),
        "tracking_area_code": int(cell["trackingAreaCode"][0]),
        "cell_identity": int(cell["cellIdentity"][0]),
        "cell_reserved": cell["cellReservedForOperatorUse"],
        "q_rx_lev_min": int(sib["cellSelectionInfo"]["q-RxLevMin"]),
        "q_qual_min": int(sib["cellSelectionInfo"]["q-QualMin"]),
        "band": int(dl["frequencyInfoDL"]["frequencyBandList"][0]["freqBandIndicatorNR"]),
        "offset_to_point_a": int(dl["frequencyInfoDL"]["offsetToPointA"]),
        "subcarrier_spacing_khz": int(
            str(dl_carrier["subcarrierSpacing"]).replace("kHz", "")
        ),
        "carrier_bandwidth_rb": int(dl_carrier["carrierBandwidth"]),
        "absolute_frequency_point_a": int(
            ul["frequencyInfoUL"]["absoluteFrequencyPointA"]
        ),
        "prach_configuration_index": int(
            generic["prach-ConfigurationIndex"]
        ),
        "msg1_fdm": generic["msg1-FDM"],
        "msg1_frequency_start": int(generic["msg1-FrequencyStart"]),
        "zero_correlation_zone": int(
            generic["zeroCorrelationZoneConfig"]
        ),
        "preamble_received_target_power_dbm": int(
            generic["preambleReceivedTargetPower"]
        ),
        "preamble_trans_max": generic["preambleTransMax"],
        "power_ramping_step": generic["powerRampingStep"],
        "ra_response_window": generic["ra-ResponseWindow"],
        "ssb_per_rach_choice": rach[
            "ssb-perRACH-OccasionAndCB-PreamblesPerSSB"
        ][0],
        "cb_preambles_per_ssb": rach[
            "ssb-perRACH-OccasionAndCB-PreamblesPerSSB"
        ][1],
        "contention_resolution_timer": rach[
            "ra-ContentionResolutionTimer"
        ],
        "root_sequence_choice": root_choice,
        "root_sequence_index": int(root_index),
        "msg1_subcarrier_spacing_khz": (
            float(str(rach["msg1-SubcarrierSpacing"]).replace("kHz", ""))
            if "msg1-SubcarrierSpacing" in rach
            else (5.0 if generic["prach-ConfigurationIndex"] in range(48, 64) else 1.25)
        ),
        "restricted_set_config": rach["restrictedSetConfig"],
        "num_preambles": int(rach.get("totalNumberOfRA-Preambles", 64)),
        "si_broadcast_status": schedule["si-BroadcastStatus"],
        "si_periodicity": schedule["si-Periodicity"],
        "mapped_sib_type": mapped,
        "si_window_length": si["si-WindowLength"],
        "modification_period_coeff": dl["bcch-Config"][
            "modificationPeriodCoeff"
        ],
        "default_paging_cycle": dl["pcch-Config"]["defaultPagingCycle"],
        "paging_frame_choice": dl["pcch-Config"][
            "nAndPagingFrameOffset"
        ][0],
        "paging_frame_offset": int(
            dl["pcch-Config"]["nAndPagingFrameOffset"][1]
        ),
        "paging_ns": dl["pcch-Config"]["ns"],
        "time_alignment_timer": ul["timeAlignmentTimerCommon"],
        "ssb_positions_in_burst": format(int(ssb_bits[0]), "08b"),
        "ssb_periodicity": serving["ssb-PeriodicityServingCell"],
        "ss_pbch_block_power_dbm": int(serving["ss-PBCH-BlockPower"]),
        **{key: value for key, value in sib["ue-TimersAndConstants"].items()},
    }
    for direction, common, bwp in (("dl", dl, "initialDownlinkBWP"),
                                   ("ul", ul, "initialUplinkBWP")):
        generic_bwp = common[bwp]["genericParameters"]
        semantic[f"initial_{direction}_bwp_riv"] = generic_bwp["locationAndBandwidth"]
        semantic[f"initial_{direction}_bwp_scs_khz"] = int(generic_bwp["subcarrierSpacing"].replace("kHz", ""))
        semantic[f"initial_{direction}_bwp_cyclic_prefix"] = generic_bwp.get("cyclicPrefix", "normal")
    if "n-TimingAdvanceOffset" in serving:
        semantic["n_timing_advance_offset"] = serving["n-TimingAdvanceOffset"]
    if "pdcch-ConfigCommon" in dl["initialDownlinkBWP"]:
        kind, common_control = dl["initialDownlinkBWP"]["pdcch-ConfigCommon"]
        if kind != "setup":
            raise ValueError("bounded SIB1 requires setup, not release, for present PDCCH-ConfigCommon")
        semantic["pdcch_config_common"] = sib1_common_control.from_asn1(common_control)
    if "pucch-ConfigCommon" in ul["initialUplinkBWP"]:
        kind, common_control = ul["initialUplinkBWP"]["pucch-ConfigCommon"]
        if kind != "setup":
            raise ValueError("bounded SIB1 requires setup, not release, for present PUCCH-ConfigCommon")
        if any(name in common_control for name in (
                "nrofPRBs", "intra-SlotFH-r17", "pucch-ResourceCommonRedCap-r17",
                "additionalPRBOffset-r17")):
            raise ValueError("unsupported extension in bounded pucch-ConfigCommon")
        mapped = {"pucch_GroupHopping": common_control["pucch-GroupHopping"]}
        for asn1_name, semantic_name in (
            ("pucch-ResourceCommon", "pucch_ResourceCommon"),
            ("hoppingId", "hoppingId"),
            ("p0-nominal", "p0_nominal"),
        ):
            if asn1_name in common_control:
                mapped[semantic_name] = int(common_control[asn1_name])
        semantic["pucch_config_common"] = mapped
    # This codec does not yet carry these optional IEs into the MATLAB tree.
    # Reject them rather than report a silently truncated decode as complete.
    if "pdsch-ConfigCommon" in dl["initialDownlinkBWP"] or \
            "pusch-ConfigCommon" in ul["initialUplinkBWP"]:
        raise ValueError("unsupported common PDSCH/PUSCH IE in bounded SIB1")
    if bounded_object(semantic) != value:
        raise ValueError("decoded SIB1 contains fields not represented losslessly by the bounded semantic profile")
    return semantic


def envelope(
    payload: bytes,
    semantic: dict[str, Any],
    *,
    transport_num_bits: int | None = None,
) -> dict[str, Any]:
    result = {
        "profile": PROFILE,
        "codec": "pycrate_asn1dir.RRCNR",
        "codec_version": VERSION,
        "uper_hex": payload.hex().upper(),
        "num_bits": len(payload) * 8,
        "sha256": hashlib.sha256(payload).hexdigest(),
        "semantic": semantic,
    }
    if transport_num_bits is None:
        transport_num_bits = len(payload) * 8
    result["transport_num_bits"] = transport_num_bits
    result["transport_padding_bits"] = transport_num_bits - len(payload) * 8
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("encode", "decode"))
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    source = json.loads(args.input.read_text(encoding="utf-8"))
    if args.operation == "encode":
        semantic = source["semantic"]
        payload = CODEC.to_uper(bounded_object(semantic))
        transport_num_bits = len(payload) * 8
    else:
        transport_payload = bytes.fromhex(str(source["uper_hex"]))
        CODEC.from_uper(transport_payload)
        semantic = semantic_from_object(CODEC.get_val())
        payload = CODEC.to_uper()
        trailing = transport_payload[len(payload) :]
        if (
            transport_payload[: len(payload)] != payload
            or any(byte != 0 for byte in trailing)
        ):
            raise ValueError(
                "UPER payload is not canonical or has nonzero "
                "transport-block padding"
            )
        transport_num_bits = len(transport_payload) * 8
    args.output.write_text(
        json.dumps(
            envelope(
                payload,
                semantic,
                transport_num_bits=transport_num_bits,
            ),
            sort_keys=True,
        ),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
