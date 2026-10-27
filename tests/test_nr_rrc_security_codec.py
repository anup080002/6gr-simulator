import importlib.util
from pathlib import Path
import pytest
spec=importlib.util.spec_from_file_location("draft",Path(__file__).resolve().parents[1]/"tools"/"initial_access"/"nr_rrc_access_codec.py")
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
def pack(bits):
 bits+="0"*((-len(bits))%8)
 return int(bits,2).to_bytes(len(bits)//8,"big").hex().upper()
@pytest.mark.parametrize("t",range(4))
@pytest.mark.parametrize("kind,index",[("security_mode_command",4),("security_mode_complete",5),("security_mode_failure",6)])
def test_original_bits(t,kind,index):
 s={"transaction_id":t};bits="0"+format(index,"04b")+format(t,"02b")+"0"+"00"
 if kind=="security_mode_command":
  s.update(ciphering_algorithm="nea0",integrity_algorithm="nia2")
  # SecurityConfigSMC extension0; SecurityAlgorithmConfig ext0,present1;
  # cipher enum root extension0,index000; integrity root extension0,index010.
  bits+="0"+"01"+"0000"+"0010"
 out=c.execute("encode",dict(message_kind=kind,semantic=s))
 assert out["uper_hex"]==pack(bits)
 assert c.execute("decode",dict(message_kind=kind,uper_hex=pack(bits)))["semantic"]==s
 with pytest.raises(ValueError):c.execute("decode",dict(message_kind=kind,uper_hex=pack(bits)+"00"))
@pytest.mark.parametrize("cipher,integrity",[("nea1","nia2"),("nea0","nia0"),("nea0","nia3")])
def test_unimplemented_security_rejected(cipher,integrity):
 with pytest.raises(ValueError): c.execute("encode",dict(message_kind="security_mode_command",semantic=dict(transaction_id=0,ciphering_algorithm=cipher,integrity_algorithm=integrity)))
def test_failure_has_no_fabricated_cause():
 with pytest.raises(ValueError):c.execute("encode",dict(message_kind="security_mode_failure",semantic=dict(transaction_id=0,cause="integrity_failure")))
