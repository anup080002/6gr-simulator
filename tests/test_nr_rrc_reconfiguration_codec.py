from test_nr_rrc_security_codec import c,pack
import pytest,copy,hashlib

def semantic():
 return dict(transaction_id=2,cell_group_id=0,drb_id=1,lcid=4,
  pdcp=dict(sn_size_ul="len12bits",sn_size_dl="len18bits",discard_timer="ms100",t_reordering="ms40",integrity_protection=False),
  sdap=dict(pdu_session=1,qfi=9,header_ul="present",header_dl="present",default_drb=True),
  rlc_am=dict(sn_size_ul="size12",sn_size_dl="size18",t_poll_retransmit="ms45",poll_pdu="p16",poll_byte="kB25",max_retx_threshold="t8",t_reassembly="ms35",t_status_prohibit="ms10"),
  logical_channel=dict(priority=3,prioritised_bit_rate="kBps8",bucket_size_duration="ms100",logical_channel_group=1,scheduling_request_id=0,logical_channel_sr_mask=False,logical_channel_sr_delay_timer_applied=False))
@pytest.mark.parametrize("t",range(4))
def test_lossless_nested_configuration(t):
 s=semantic();s["transaction_id"]=t
 out=c.execute("encode",dict(message_kind="reconfiguration",semantic=s))
 received=c.execute("decode",dict(message_kind="reconfiguration",uper_hex=out["uper_hex"]))
 assert received["semantic"]==s
 n=received["nested_configuration"]
 assert n["mcg_location"]=="rrcReconfiguration.nonCriticalExtension.masterCellGroup"
 assert n["master_cell_group_sha256"]==hashlib.sha256(bytes.fromhex(n["master_cell_group_uper_hex"])).hexdigest()
 assert n["new_drb_setup_only"] and not n["drb_integrity_protection_field_present"]
 assert n["master_cell_group"]["rlc-BearerToAddModList"][0]["servedRadioBearer"]==("drb-Identity",1)
 assert n["radio_bearer_config"]["drb-ToAddModList"][0]["pdcp-Config"]["drb"]["pdcp-SN-SizeDL"]=="len18bits"
 with pytest.raises(ValueError):c.execute("decode",dict(message_kind="reconfiguration",uper_hex=out["uper_hex"]+"00"))
@pytest.mark.parametrize("t",range(4))
def test_complete_independent_root_bits(t):
 expected=pack("0"+"0001"+format(t,"02b")+"0"+"00")
 out=c.execute("encode",dict(message_kind="reconfiguration_complete",semantic=dict(transaction_id=t)))
 assert out["uper_hex"]==expected
 assert c.execute("decode",dict(message_kind="reconfiguration_complete",uper_hex=expected))["semantic"]==dict(transaction_id=t)
@pytest.mark.parametrize("mutation",["integrity","release","phy","missing_sn","other_drb"])
def test_unsupported_received_fields_rejected(mutation):
 codec,value=c.object_for("reconfiguration",semantic());body=value["message"][1][1]["criticalExtensions"][1]
 if mutation=="integrity":body["radioBearerConfig"]["drb-ToAddModList"][0]["pdcp-Config"]["drb"]["integrityProtection"]="enabled"
 elif mutation=="release":body["radioBearerConfig"]["drb-ToReleaseList"]=[2]
 elif mutation=="missing_sn":del body["radioBearerConfig"]["drb-ToAddModList"][0]["pdcp-Config"]["drb"]["pdcp-SN-SizeUL"]
 elif mutation=="other_drb":
  d=copy.deepcopy(body["radioBearerConfig"]["drb-ToAddModList"][0]);d["drb-Identity"]=2;body["radioBearerConfig"]["drb-ToAddModList"].append(d)
 else:
  group,_=c.contained_group(body["nonCriticalExtension"]["masterCellGroup"]);group["rlc-BearerToReleaseList"]=[5]
  body["nonCriticalExtension"]["masterCellGroup"]=c.M.CellGroupConfig.to_uper(group)
 wire=codec.to_uper(value).hex().upper()
 with pytest.raises(ValueError):c.execute("decode",dict(message_kind="reconfiguration",uper_hex=wire))
