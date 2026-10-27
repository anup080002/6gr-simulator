"""Independent base UPER bit-layout comparator from TS38.331 V18.8.0.
Only the present supported fields are encoded. Absent optional and extension
bits retain their normative root positions; this is not a generic ASN.1 codec.
"""
import importlib.util
from pathlib import Path
import json
import pytest
spec=importlib.util.spec_from_file_location("codec",Path(__file__).resolve().parents[1]/"tools"/"initial_access"/"nr_rrc_access_codec.py")
codec=importlib.util.module_from_spec(spec);spec.loader.exec_module(codec)
CAUSES=["emergency","highPriorityAccess","mt-Access","mo-Signalling","mo-Data","mo-VoiceCall","mo-VideoCall","mo-SMS","mps-PriorityAccess","mcs-PriorityAccess","spare6","spare5","spare4","spare3","spare2","spare1"]
def b(x,n): return format(x,f"0{n}b")
def pack(bits):
    bits += "0"*((-len(bits))%8)
    return int(bits,2).to_bytes(len(bits)//8,"big")
def length(n):
    if n<128: return b(n,8)
    if n<16384: return "10"+b(n,14)
    raise ValueError("fragmented test operands outside this comparator")
def req(s,spare=0):
    return pack("000"+b(s["identity_type"]=="randomValue",1)+b(s["identity_value"],39)+b(CAUSES.index(s["establishment_cause"]),4)+b(spare,1))
def encode_setup(s):
    # CellGroupConfig: root extension0,7 optional bits,cellGroupId2,
    # list length (1..32)5; RLC-BearerConfig ext0,4 options,LCID5,
    # servedRadioBearer choice1 and SRB-Identity(1..3)2.
    group=pack("0"+"1000000"+"00"+"00000"+"0"+"1000"+"00000"+"0"+"00")
    # RadioBearerConfig extension0+5options, list size1..2, SRB-ToAddMod
    # extension0+3options+identity2. No octet padding inside this sequence.
    bearer="0"+"10000"+"0"+"0"+"000"+"00"
    return pack("001"+b(s["transaction_id"],2)+"0"+"00"+bearer+length(len(group))+"".join(b(x,8) for x in group))
def complete(s):
    nas=bytes.fromhex(s["dedicated_nas_hex"])
    return pack("0"+b(2,4)+b(s["transaction_id"],2)+"0"+"000000"+b(s["selected_plmn_identity"]-1,4)+length(len(nas))+"".join(b(x,8) for x in nas))
def check(kind,s,f):
    original=f(s);out=codec.execute("encode",{"message_kind":kind,"semantic":s})
    assert out["uper_hex"]==original.hex().upper(),(kind,s,out["uper_hex"],original.hex())
    decoded=codec.execute("decode",{"message_kind":kind,"uper_hex":original.hex().upper()})
    assert decoded["semantic"]==s
    try: codec.execute("decode",{"message_kind":kind,"uper_hex":original.hex().upper()+"00"})
    except ValueError: pass
    else: raise AssertionError("trailing octets accepted")
def test_independent_base_uper():
    count=0
    for choice in ("randomValue","ng-5G-S-TMSI-Part1"):
     for identity in (0,1,7,255,2**38,2**39-1):
      for cause in CAUSES[:10]:
       s=dict(identity_type=choice,identity_value=identity,establishment_cause=cause);check("setup_request",s,req);count+=1
    for t in range(4):
     s=dict(transaction_id=t,cell_group_id=0,srb1_lcid=1);check("setup",s,encode_setup);count+=1
     for plmn in (1,6,12):
      for n in (1,3,127,128,255):
       s=dict(transaction_id=t,selected_plmn_identity=plmn,dedicated_nas_hex=bytes(x%256 for x in range(n)).hex().upper())
       check("setup_complete",s,complete);count+=1
    for cause in CAUSES:
     s=dict(identity_type="randomValue",identity_value=42,establishment_cause=cause)
     for spare in (0,1):
      decoded=codec.execute("decode",{"message_kind":"setup_request","uper_hex":req(s,spare).hex().upper()})
      assert decoded["semantic"]==s;count+=1
    print(json.dumps(dict(Ok=True,Cases=count,Reference="TS38.331 V18.8.0 base grammar",IndependentComparator="manually transcribed supported UPER root bits",NASValidation=False,RFExecutions=0)))


@pytest.mark.parametrize("identity", [0, 7, 2**38+7, 2**39-1])
def test_integral_json_numeric_identity_preserves_all_39_bits(identity):
    original=dict(identity_type="randomValue",identity_value=identity,
                  establishment_cause="mo-Signalling")
    semantic=dict(original,identity_value=float(identity))
    # Exercise the JSON boundary used by MATLAB, not merely the helper.
    message=json.loads(json.dumps({"message_kind":"setup_request","semantic":semantic}))
    out=codec.execute("encode",message)
    assert out["uper_hex"]==req(original).hex().upper()
    assert out["semantic"]==original
    assert type(out["semantic"]["identity_value"]) is int


@pytest.mark.parametrize("identity", [True,False,"7","274877906951",None,[],{},
    -1,2**39,10**400,7.5,float(2**38)+0.5,float("nan"),float("inf"),float("-inf")])
def test_invalid_json_identity_never_truncated_or_coerced(identity):
    semantic=dict(identity_type="randomValue",identity_value=identity,
                  establishment_cause="mo-Signalling")
    with pytest.raises(ValueError,match="require original integer"):
        codec.execute("encode",{"message_kind":"setup_request","semantic":semantic})
