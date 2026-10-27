"""Strict base NR RRC access UPER bridge for the explicitly selected profile.

Base message/IE subset inspected in TS38.331 V18.8.0. Generated codec is
pycrate's installed RRCNR module; independent base-grammar tests cover the supported root fields. No claim about NAS validity, dedicated DRB/PHY setup or complete NR interoperability.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path

from pycrate_asn1dir import RRCNR
from pycrate_asn1rt.err import ASN1PERDecodeErr
from pycrate_core.charpy import CharpyErr


class NRProfileViolation(ValueError):
    """Explicit supported-subset/domain rejection; not an internal failure."""

M = RRCNR.NR_RRC_Definitions
PROFILE = "nr_rrc_access_base_srb1_uper_v1"
TX_CAUSES = {"emergency", "highPriorityAccess", "mt-Access", "mo-Signalling",
          "mo-Data", "mo-VoiceCall", "mo-VideoCall", "mo-SMS",
          "mps-PriorityAccess", "mcs-PriorityAccess"}
CAUSES = TX_CAUSES | {f"spare{k}" for k in range(1, 7)}


def fields(value, required):
    if type(value) is not dict or set(value) != set(required):
        raise NRProfileViolation(f"require exactly {required}; unsupported fields are not discarded")
    return value


def integer(value, lo, hi):
    # MATLAB jsonencode may serialize an exactly integral double with a
    # decimal point/exponent. JSON has one numeric domain; retain that exact
    # integer value without accepting booleans, strings or truncating a
    # fractional operand. All supported fields are at most 39 bits, below
    # the exact IEEE-754 integer limit.
    if type(value) not in (int, float) or not lo <= value <= hi or \
            not math.isfinite(value) or value != math.trunc(value):
        raise NRProfileViolation(f"require original integer in [{lo},{hi}]")
    return int(value)


def octets(value):
    if type(value) is not str or not value or len(value) % 2 or any(c not in "0123456789ABCDEF" for c in value):
        raise NRProfileViolation("require nonempty original uppercase even-length hex octets")
    return bytes.fromhex(value)



def boolean(value):
    if type(value) is not bool: raise NRProfileViolation("require original boolean")
    return value


def reconfiguration_tree(s):
    fields(s,{"transaction_id","cell_group_id","drb_id","lcid","pdcp","sdap","rlc_am","logical_channel"})
    integer(s["transaction_id"],0,3)
    if integer(s["cell_group_id"],0,3)!=0: raise NRProfileViolation("only MCG0 bearer-only setup supported")
    drb=integer(s["drb_id"],1,32);lcid=integer(s["lcid"],4,32)
    p=fields(s["pdcp"],{"sn_size_ul","sn_size_dl","discard_timer","t_reordering","integrity_protection"})
    if boolean(p["integrity_protection"]): raise NRProfileViolation("selected DRB integrity is explicitly disabled; SRB security remains separate")
    for key in ("sn_size_ul","sn_size_dl"):
        if p[key] not in ("len12bits","len18bits"): raise NRProfileViolation("unsupported PDCP SN size")
    if p["discard_timer"] not in ("ms10","ms20","ms30","ms40","ms50","ms60","ms75","ms100","ms150","ms200","ms250","ms300","ms500","ms750","ms1500","infinity"):
        raise NRProfileViolation("unsupported pinned DRB discard timer")
    # Other root enum values are validated by the generated codec; spare and
    # extensions are explicitly rejected by the strict semantic domain.
    for key in ("t_reordering",):
        if type(p[key]) is not str or not p[key].startswith("ms") or not p[key][2:].isdigit(): raise NRProfileViolation("require nonspare original reordering timer")
    a=fields(s["sdap"],{"pdu_session","qfi","header_ul","header_dl","default_drb"})
    if a["header_ul"] not in ("present","absent") or a["header_dl"] not in ("present","absent"): raise NRProfileViolation("unsupported SDAP header")
    if boolean(a["default_drb"]) and a["header_ul"]!="present": raise NRProfileViolation("default DRB requires UL SDAP header")
    sdap={"pdu-Session":integer(a["pdu_session"],0,255),"sdap-HeaderDL":a["header_dl"],"sdap-HeaderUL":a["header_ul"],"defaultDRB":a["default_drb"],"mappedQoS-FlowsToAdd":[integer(a["qfi"],0,63)]}
    pdcp={"drb":{"discardTimer":p["discard_timer"],"pdcp-SN-SizeUL":p["sn_size_ul"],"pdcp-SN-SizeDL":p["sn_size_dl"],"headerCompression":("notUsed",0)},"t-Reordering":p["t_reordering"]}
    rb={"drb-ToAddModList":[{"cnAssociation":("sdap-Config",sdap),"drb-Identity":drb,"pdcp-Config":pdcp}]}
    r=fields(s["rlc_am"],{"sn_size_ul","sn_size_dl","t_poll_retransmit","poll_pdu","poll_byte","max_retx_threshold","t_reassembly","t_status_prohibit"})
    for key,value in r.items():
        if type(value) is not str or "spare" in value: raise NRProfileViolation("require original supported RLC enum")
    if r["sn_size_ul"] not in ("size12","size18") or r["sn_size_dl"] not in ("size12","size18"): raise NRProfileViolation("unsupported AM SN size")
    rlc=("am",{"ul-AM-RLC":{"sn-FieldLength":r["sn_size_ul"],"t-PollRetransmit":r["t_poll_retransmit"],"pollPDU":r["poll_pdu"],"pollByte":r["poll_byte"],"maxRetxThreshold":r["max_retx_threshold"]},"dl-AM-RLC":{"sn-FieldLength":r["sn_size_dl"],"t-Reassembly":r["t_reassembly"],"t-StatusProhibit":r["t_status_prohibit"]}})
    l=fields(s["logical_channel"],{"priority","prioritised_bit_rate","bucket_size_duration","logical_channel_group","scheduling_request_id","logical_channel_sr_mask","logical_channel_sr_delay_timer_applied"})
    for key in ("prioritised_bit_rate","bucket_size_duration"):
        if type(l[key]) is not str or "spare" in l[key]: raise NRProfileViolation("require original logical-channel enum")
    logical={"ul-SpecificParameters":{"priority":integer(l["priority"],1,16),"prioritisedBitRate":l["prioritised_bit_rate"],"bucketSizeDuration":l["bucket_size_duration"],"logicalChannelGroup":integer(l["logical_channel_group"],0,7),"schedulingRequestID":integer(l["scheduling_request_id"],0,7),"logicalChannelSR-Mask":boolean(l["logical_channel_sr_mask"]),"logicalChannelSR-DelayTimerApplied":boolean(l["logical_channel_sr_delay_timer_applied"])}}
    group={"cellGroupId":0,"rlc-BearerToAddModList":[{"logicalChannelIdentity":lcid,"servedRadioBearer":("drb-Identity",drb),"rlc-Config":rlc,"mac-LogicalChannelConfig":logical}]}
    return rb,group


def contained_group(value):
    if type(value) is bytes:
        original=value;M.CellGroupConfig.from_uper(value);group=M.CellGroupConfig.get_val()
        if M.CellGroupConfig.to_uper(group)!=original: raise NRProfileViolation("noncanonical contained MCG")
    elif type(value) is tuple and value[0]=="CellGroupConfig":
        group=value[1];original=M.CellGroupConfig.to_uper(group)
    else: raise NRProfileViolation("unsupported original contained MCG")
    return group,original


def reconfiguration_semantic(transaction,body):
    fields(body,{"radioBearerConfig","nonCriticalExtension"})
    ext=fields(body["nonCriticalExtension"],{"masterCellGroup"})
    group,_=contained_group(ext["masterCellGroup"])
    fields(group,{"cellGroupId","rlc-BearerToAddModList"})
    rb=fields(body["radioBearerConfig"],{"drb-ToAddModList"})
    if len(rb["drb-ToAddModList"])!=1 or len(group["rlc-BearerToAddModList"])!=1: raise NRProfileViolation("exactly one original DRB/RLC mapping supported")
    d=fields(rb["drb-ToAddModList"][0],{"cnAssociation","drb-Identity","pdcp-Config"})
    if d["cnAssociation"][0]!="sdap-Config": raise NRProfileViolation("require original SDAP association")
    a=fields(d["cnAssociation"][1],{"pdu-Session","sdap-HeaderDL","sdap-HeaderUL","defaultDRB","mappedQoS-FlowsToAdd"})
    if len(a["mappedQoS-FlowsToAdd"])!=1: raise NRProfileViolation("single QFI mapping only")
    p=fields(d["pdcp-Config"],{"drb","t-Reordering"});dr=fields(p["drb"],{"discardTimer","pdcp-SN-SizeUL","pdcp-SN-SizeDL","headerCompression"})
    if dr["headerCompression"]!=("notUsed",0): raise NRProfileViolation("ROHC unsupported")
    b=fields(group["rlc-BearerToAddModList"][0],{"logicalChannelIdentity","servedRadioBearer","rlc-Config","mac-LogicalChannelConfig"})
    if b["servedRadioBearer"]!=("drb-Identity",d["drb-Identity"]) or b["rlc-Config"][0]!="am": raise NRProfileViolation("original DRB/RLC mapping differs")
    r=fields(b["rlc-Config"][1],{"ul-AM-RLC","dl-AM-RLC"})
    u=fields(r["ul-AM-RLC"],{"sn-FieldLength","t-PollRetransmit","pollPDU","pollByte","maxRetxThreshold"});v=fields(r["dl-AM-RLC"],{"sn-FieldLength","t-Reassembly","t-StatusProhibit"})
    l=fields(fields(b["mac-LogicalChannelConfig"],{"ul-SpecificParameters"})["ul-SpecificParameters"],{"priority","prioritisedBitRate","bucketSizeDuration","logicalChannelGroup","schedulingRequestID","logicalChannelSR-Mask","logicalChannelSR-DelayTimerApplied"})
    s={"transaction_id":transaction,"cell_group_id":group["cellGroupId"],"drb_id":d["drb-Identity"],"lcid":b["logicalChannelIdentity"],
       "pdcp":{"sn_size_ul":dr["pdcp-SN-SizeUL"],"sn_size_dl":dr["pdcp-SN-SizeDL"],"discard_timer":dr["discardTimer"],"t_reordering":p["t-Reordering"],"integrity_protection":False},
       "sdap":{"pdu_session":a["pdu-Session"],"qfi":a["mappedQoS-FlowsToAdd"][0],"header_ul":a["sdap-HeaderUL"],"header_dl":a["sdap-HeaderDL"],"default_drb":a["defaultDRB"]},
       "rlc_am":{"sn_size_ul":u["sn-FieldLength"],"sn_size_dl":v["sn-FieldLength"],"t_poll_retransmit":u["t-PollRetransmit"],"poll_pdu":u["pollPDU"],"poll_byte":u["pollByte"],"max_retx_threshold":u["maxRetxThreshold"],"t_reassembly":v["t-Reassembly"],"t_status_prohibit":v["t-StatusProhibit"]},
       "logical_channel":{"priority":l["priority"],"prioritised_bit_rate":l["prioritisedBitRate"],"bucket_size_duration":l["bucketSizeDuration"],"logical_channel_group":l["logicalChannelGroup"],"scheduling_request_id":l["schedulingRequestID"],"logical_channel_sr_mask":l["logicalChannelSR-Mask"],"logical_channel_sr_delay_timer_applied":l["logicalChannelSR-DelayTimerApplied"]}}
    rb_check,group_check=reconfiguration_tree(s)
    if rb_check!=rb or group_check!=group: raise NRProfileViolation("received nested configuration was not retained losslessly")
    return s


def object_for(kind, semantic):
    if kind == "setup_request":
        s = fields(semantic, {"identity_type", "identity_value", "establishment_cause"})
        if s["identity_type"] not in {"randomValue", "ng-5G-S-TMSI-Part1"} or s["establishment_cause"] not in CAUSES:
            raise NRProfileViolation("unsupported original UE identity or establishment cause")
        value = {"rrcSetupRequest": {"ue-Identity": (s["identity_type"], (integer(s["identity_value"], 0, 2**39-1), 39)),
                                     "establishmentCause": s["establishment_cause"], "spare": (0, 1)}}
        return M.UL_CCCH_Message, {"message": ("c1", ("rrcSetupRequest", value))}
    if kind == "setup":
        s = fields(semantic, {"transaction_id", "cell_group_id", "srb1_lcid"})
        transaction = integer(s["transaction_id"], 0, 3)
        if integer(s["cell_group_id"], 0, 3) != 0 or integer(s["srb1_lcid"], 1, 32) != 1:
            raise NRProfileViolation("this profile supports only MCG0 / default SRB1 LCID1")
        group = {"cellGroupId": 0, "rlc-BearerToAddModList": [
            {"logicalChannelIdentity": 1, "servedRadioBearer": ("srb-Identity", 1)}]}
        group_wire = M.CellGroupConfig.to_uper(group)
        value = {"rrc-TransactionIdentifier": transaction, "criticalExtensions": ("rrcSetup", {
            "radioBearerConfig": {"srb-ToAddModList": [{"srb-Identity": 1}]}, "masterCellGroup": group_wire})}
        return M.DL_CCCH_Message, {"message": ("c1", ("rrcSetup", value))}
    if kind == "setup_complete":
        s = fields(semantic, {"transaction_id", "selected_plmn_identity", "dedicated_nas_hex"})
        value = {"rrc-TransactionIdentifier": integer(s["transaction_id"], 0, 3),
                 "criticalExtensions": ("rrcSetupComplete", {
                     "selectedPLMN-Identity": integer(s["selected_plmn_identity"], 1, 12),
                     "dedicatedNAS-Message": octets(s["dedicated_nas_hex"])})}
        return M.UL_DCCH_Message, {"message": ("c1", ("rrcSetupComplete", value))}
    if kind in {"security_mode_command", "security_mode_complete", "security_mode_failure"}:
        expected = {"security_mode_command": "securityModeCommand", "security_mode_complete": "securityModeComplete",
                    "security_mode_failure": "securityModeFailure"}[kind]
        if kind == "security_mode_command":
            s = fields(semantic, {"transaction_id", "ciphering_algorithm", "integrity_algorithm"})
            if s["ciphering_algorithm"] != "nea0" or s["integrity_algorithm"] != "nia2":
                raise NRProfileViolation("selected security profile requires NEA0 and NIA2; no normal-service NIA0")
            body = {"securityConfigSMC": {"securityAlgorithmConfig": {
                "cipheringAlgorithm": s["ciphering_algorithm"], "integrityProtAlgorithm": s["integrity_algorithm"]}}}
            codec = M.DL_DCCH_Message
        else:
            s = fields(semantic, {"transaction_id"}); body = {}; codec = M.UL_DCCH_Message
        value = {"rrc-TransactionIdentifier": integer(s["transaction_id"], 0, 3),
                 "criticalExtensions": (expected, body)}
        return codec, {"message": ("c1", (expected, value))}
    if kind == "reconfiguration":
        rb,group=reconfiguration_tree(semantic)
        body={"radioBearerConfig":rb,"nonCriticalExtension":{"masterCellGroup":M.CellGroupConfig.to_uper(group)}}
        value={"rrc-TransactionIdentifier":integer(semantic["transaction_id"],0,3),"criticalExtensions":("rrcReconfiguration",body)}
        return M.DL_DCCH_Message,{"message":("c1",("rrcReconfiguration",value))}
    if kind == "reconfiguration_complete":
        fields(semantic,{"transaction_id"})
        value={"rrc-TransactionIdentifier":integer(semantic["transaction_id"],0,3),"criticalExtensions":("rrcReconfigurationComplete",{})}
        return M.UL_DCCH_Message,{"message":("c1",("rrcReconfigurationComplete",value))}
    raise NRProfileViolation("unsupported message kind")


def semantic_for(kind, value):
    fields(value, {"message"})
    outer, message = value["message"]
    expected = {"setup_request": "rrcSetupRequest", "setup": "rrcSetup", "setup_complete": "rrcSetupComplete",
        "security_mode_command": "securityModeCommand", "security_mode_complete": "securityModeComplete",
        "security_mode_failure": "securityModeFailure", "reconfiguration":"rrcReconfiguration",
        "reconfiguration_complete":"rrcReconfigurationComplete"}[kind]
    if outer != "c1" or message[0] != expected:
        raise NRProfileViolation("wrong original RRC message choice")
    value = message[1]
    if kind == "setup_request":
        fields(value, {"rrcSetupRequest"})
        r = fields(value["rrcSetupRequest"], {"ue-Identity", "establishmentCause", "spare"})
        choice, identity = r["ue-Identity"]
        if identity[1] != 39 or r["spare"][1] != 1:
            raise NRProfileViolation("invalid original request identity width/spare")
        s = {"identity_type": choice, "identity_value": identity[0], "establishment_cause": r["establishmentCause"]}
    else:
        fields(value, {"rrc-TransactionIdentifier", "criticalExtensions"})
        extension, body = value["criticalExtensions"]
        if extension != expected:
            raise NRProfileViolation("unsupported critical extension")
        if kind == "setup":
            fields(body, {"radioBearerConfig", "masterCellGroup"})
            if body["radioBearerConfig"] != {"srb-ToAddModList": [{"srb-Identity": 1}]}:
                raise NRProfileViolation("unsupported received SRB/DRB/security configuration")
            group = body["masterCellGroup"]
            if type(group) is bytes:
                M.CellGroupConfig.from_uper(group)
                group = M.CellGroupConfig.get_val()
            elif type(group) is tuple and group[0] == "CellGroupConfig":
                group = group[1]
            else:
                raise NRProfileViolation("unsupported contained masterCellGroup")
            expected_group = {"cellGroupId": 0, "rlc-BearerToAddModList": [
                {"logicalChannelIdentity": 1, "servedRadioBearer": ("srb-Identity", 1)}]}
            if group != expected_group:
                raise NRProfileViolation("unsupported received CellGroupConfig; do not ignore dedicated configuration")
            s = {"transaction_id": value["rrc-TransactionIdentifier"], "cell_group_id": 0, "srb1_lcid": 1}
        elif kind == "reconfiguration":
            s=reconfiguration_semantic(value["rrc-TransactionIdentifier"],body)
        elif kind == "reconfiguration_complete":
            fields(body,set());s={"transaction_id":value["rrc-TransactionIdentifier"]}
        elif kind == "security_mode_command":
            fields(body, {"securityConfigSMC"})
            fields(body["securityConfigSMC"], {"securityAlgorithmConfig"})
            algorithms = fields(body["securityConfigSMC"]["securityAlgorithmConfig"],
                                {"cipheringAlgorithm", "integrityProtAlgorithm"})
            s = {"transaction_id": value["rrc-TransactionIdentifier"],
                 "ciphering_algorithm": algorithms["cipheringAlgorithm"],
                 "integrity_algorithm": algorithms["integrityProtAlgorithm"]}
        elif kind in {"security_mode_complete", "security_mode_failure"}:
            fields(body, set()); s = {"transaction_id": value["rrc-TransactionIdentifier"]}
        else:
            fields(body, {"selectedPLMN-Identity", "dedicatedNAS-Message"})
            s = {"transaction_id": value["rrc-TransactionIdentifier"],
                 "selected_plmn_identity": body["selectedPLMN-Identity"],
                 "dedicated_nas_hex": body["dedicatedNAS-Message"].hex().upper()}
    object_for(kind, s)  # same strict value domain as the actual encoder
    return s


def inspect_received(data):
    """Classify only original byte decoding/profile outcomes.

    Wrong API kinds, invalid hex, environment failures, encoding failures,
    unexpected ValueError/TypeError/KeyError and source bugs remain fatal.
    """
    kind = data["message_kind"]
    codec = {"setup_request": M.UL_CCCH_Message, "setup": M.DL_CCCH_Message,
             "setup_complete": M.UL_DCCH_Message, "security_mode_command": M.DL_DCCH_Message,
             "security_mode_complete": M.UL_DCCH_Message, "security_mode_failure": M.UL_DCCH_Message,
             "reconfiguration": M.DL_DCCH_Message, "reconfiguration_complete": M.UL_DCCH_Message}[kind]
    wire = octets(data["uper_hex"])
    profile = PROFILE if kind in {"setup_request", "setup", "setup_complete"} else "nr_rrc_rel18_security_new_drb_uper_v1"
    result = {"contract_version": "original_received_RRC_inspection/v1", "accepted": False,
              "codec": "pycrate_asn1dir.RRCNR", "codec_version": importlib.metadata.version("pycrate"),
              "profile": profile, "message_kind": kind, "uper_hex": wire.hex().upper(),
              "num_bits": 8 * len(wire), "sha256": hashlib.sha256(wire).hexdigest(),
              "status": "", "rejection_class": "", "rejection_message": "",
              "decoded": {}, "physical_reception_proved": False,
              "scope": "original_UPER_decode_and_supported_profile_only_not_NR_message_validity_certificate"}
    try:
        codec.from_uper(wire)
    except (ASN1PERDecodeErr, CharpyErr) as error:
        result.update(status="received_UPER_decode_rejected", rejection_class=type(error).__name__,
                      rejection_message=str(error))
        return result
    original = codec.get_val()
    try:
        semantic_for(kind, original)
    except (ASN1PERDecodeErr, CharpyErr) as error:
        result.update(status="received_UPER_decode_rejected", rejection_class=type(error).__name__,
                      rejection_message=str(error))
        return result
    except NRProfileViolation as error:
        result.update(status="received_message_outside_supported_profile", rejection_class=type(error).__name__,
                      rejection_message=str(error))
        return result
    if codec.to_uper(original) != wire:
        result.update(status="received_noncanonical_or_trailing_octets", rejection_class="OriginalOctetExtent",
                      rejection_message="The supported codec cannot consume these complete original octets exactly.")
        return result
    # Strict decode is performed on these same original octets, without any
    # catch here: unexpected internal or environment faults still propagate.
    result["decoded"] = execute("decode", {"message_kind": kind, "uper_hex": wire.hex().upper()})
    result.update(accepted=True, status="received_supported_message_decoded")
    return result


def execute(operation, data):
    if operation == "inspect_received":
        return inspect_received(data)
    kind = data["message_kind"]
    if operation == "encode":
        if kind == "setup_request" and data["semantic"].get("establishment_cause") not in TX_CAUSES:
            raise NRProfileViolation("transmitted request needs a supported establishment cause")
        codec, value = object_for(kind, data["semantic"])
        wire = codec.to_uper(value)
        codec.from_uper(wire)
        semantic = semantic_for(kind, codec.get_val())
    elif operation == "decode":
        wire = octets(data["uper_hex"])
        codec = {"setup_request": M.UL_CCCH_Message, "setup": M.DL_CCCH_Message,
                 "setup_complete": M.UL_DCCH_Message, "security_mode_command": M.DL_DCCH_Message,
                 "security_mode_complete": M.UL_DCCH_Message, "security_mode_failure": M.UL_DCCH_Message, "reconfiguration":M.DL_DCCH_Message,
                 "reconfiguration_complete":M.UL_DCCH_Message}[kind]
        codec.from_uper(wire)
        semantic = semantic_for(kind, codec.get_val())
        original_value = codec.get_val()
        if codec.to_uper(original_value) != wire:
            raise NRProfileViolation("trailing, unsupported, or noncanonical RRC bytes cannot be silently consumed")
    else:
        raise NRProfileViolation("operation must be encode/decode")
    if kind == "setup_request" and len(wire) != 6:
        raise NRProfileViolation("base RRCSetupRequest must occupy the original 48-bit UL-CCCH")
    nested={}
    if kind=="reconfiguration":
        # Original tree has already passed exact supported-field validation.
        body=codec.get_val()["message"][1][1]["criticalExtensions"][1]
        group,group_wire=contained_group(body["nonCriticalExtension"]["masterCellGroup"])
        nested={"radio_bearer_config":body["radioBearerConfig"],"master_cell_group":group,
                "master_cell_group_uper_hex":group_wire.hex().upper(),
                "master_cell_group_sha256":hashlib.sha256(group_wire).hexdigest(),
                "radio_bearer_config_canonical_uper_hex":M.RadioBearerConfig.to_uper(body["radioBearerConfig"]).hex().upper(),
                "radio_bearer_config_canonical_sha256":hashlib.sha256(M.RadioBearerConfig.to_uper(body["radioBearerConfig"])).hexdigest(),
                "mcg_location":"rrcReconfiguration.nonCriticalExtension.masterCellGroup",
                "new_drb_setup_only":True,"drb_integrity_protection_field_present":False,
                "required_pdcp_optional_fields_present":True}
    profile=PROFILE if kind in {"setup_request","setup","setup_complete"} else "nr_rrc_rel18_security_new_drb_uper_v1"
    return {"profile": profile, "codec": "pycrate_asn1dir.RRCNR", "codec_version": importlib.metadata.version("pycrate"),
            "message_kind": kind, "uper_hex": wire.hex().upper(), "num_bits": len(wire)*8,
            "sha256": hashlib.sha256(wire).hexdigest(), "semantic": semantic,
            "scope": "release_pinned_NR_RRC_UPER_not_MAC_transport_received_activation_or_NAS_validity",
            "standards_reference": "TS38.331_V18.8.0",
            "security_activated": False, "physical_reception_proved": False,"nested_configuration":nested}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=["encode", "decode", "inspect_received"])
    parser.add_argument("input")
    parser.add_argument("output")
    args = parser.parse_args()
    result = execute(args.operation, json.loads(Path(args.input).read_text(encoding="utf-8-sig")))
    Path(args.output).write_text(json.dumps(result, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
