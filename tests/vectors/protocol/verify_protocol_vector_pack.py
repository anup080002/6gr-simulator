#!/usr/bin/env python3
from __future__ import annotations
import csv,hashlib,json,math,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent

def rows(p):
 with p.open(newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def truth(v):return str(v).strip().lower() in {'1','true','yes','pass'}
fail=[]
m=json.loads((HERE/'independent_vector_manifest.json').read_text())
for x in m['files']:
 p=HERE/x['path']
 if not p.exists():fail.append('missing:'+x['path']);continue
 if sha(p)!=x['sha256']:fail.append('sha:'+x['path'])
 if len(rows(p))!=int(x['rows']):fail.append('rows:'+x['path'])
# RLC UM/AM header structure.
for x in rows(HERE/'protocol_rlc_um_header_vectors.csv'):
 if truth(x['ExpectedValid']) and len(bytes.fromhex(x['HeaderHex']))!=int(x['HeaderBytes']):fail.append('um_len:'+x['CaseID'])
 if truth(x['ExpectedValid']) and int(x['SI']) in (2,3) and x['SO']=='':fail.append('um_so:'+x['CaseID'])
for x in rows(HERE/'protocol_rlc_am_header_vectors.csv'):
 if truth(x['ExpectedValid']) and len(bytes.fromhex(x['HeaderHex']))!=int(x['HeaderBytes']):fail.append('am_len:'+x['CaseID'])
 if truth(x['ExpectedValid']) and (int(x['HeaderHex'][:2],16)&0x80)==0:fail.append('am_dc:'+x['CaseID'])
# STATUS lengths byte aligned and feature fields consistent.
for x in rows(HERE/'protocol_rlc_status_vectors.csv'):
 if int(x['ExpectedBits'])%8 or int(x['ExpectedBytes'])*8!=int(x['ExpectedBits']):fail.append('status_len:'+x['CaseID'])
 if truth(x['RequiresE2']) and int(x['NACKCount'])==0:fail.append('status_e2:'+x['CaseID'])
# PDCP COUNT and headers.
for x in rows(HERE/'protocol_pdcp_count_vectors.csv'):
 if int(x['COUNT'])!=(int(x['HFN'])<<int(x['SNBits']))|int(x['SN']):fail.append('count:'+x['CaseID'])
for x in rows(HERE/'protocol_pdcp_header_vectors.csv'):
 if truth(x['ExpectedValid']) and len(bytes.fromhex(x['HeaderHex']))!=int(x['HeaderBytes']):fail.append('pdcp_header:'+x['CaseID'])
# Security outputs present and correctly sized.
for x in rows(HERE/'protocol_pdcp_security_vectors.csv'):
 if x['Algorithm']=='128-NEA2' and len(x['ExpectedHex'])!=len(x['MessageHex']):fail.append('nea2:'+x['CaseID'])
 if x['Algorithm']=='128-NIA2' and len(x['ExpectedMACIHex'])!=8:fail.append('nia2:'+x['CaseID'])
# SDAP exact top bits.
for x in rows(HERE/'protocol_sdap_header_vectors.csv'):
 if not truth(x['ExpectedValid']):continue
 b=int(x['HeaderHex'],16);q=int(x['QFI'])
 if (b&0x3f)!=q:fail.append('sdap_qfi:'+x['CaseID'])
 if x['Direction']=='DL' and ((b>>7)&1)!=int(x['RDI']):fail.append('sdap_rdi:'+x['CaseID'])
 if x['Direction']=='UL' and ((b>>7)&1)!=int(x['DC']):fail.append('sdap_dc:'+x['CaseID'])
# RRC state transitions, bearer atomicity and lineage.
valid={(x['FromState'],x['Event']):x['ToState'] for x in rows(HERE/'protocol_rrc_state_transition_vectors.csv') if truth(x['ExpectedValid'])}
if not valid:fail.append('rrc_transition_empty')
for x in rows(HERE/'protocol_lineage_vectors.csv'):
 if int(x['SegmentOffset'])<0 or int(x['SegmentBytes'])<=0:fail.append('lineage_segment:'+x['LineageID'])
for pid in {x['PacketID'] for x in rows(HERE/'protocol_lineage_vectors.csv')}:
 q=[x for x in rows(HERE/'protocol_lineage_vectors.csv') if x['PacketID']==pid]
 if sum(int(x['SegmentBytes']) for x in q)!=int(q[0]['PacketBytes']):fail.append('lineage_conservation:'+pid)
# Traffic deterministic ordering.
by={}
for x in rows(HERE/'protocol_traffic_arrival_vectors.csv'):
 by.setdefault(x['FlowID'],[]).append(float(x['ArrivalTime_ms']))
for f,t in by.items():
 if t!=sorted(t):fail.append('traffic_order:'+f)
# Impact matrix and pairs.
fams=rows(HERE/'protocol_impact_analysis_families.csv');exp=rows(HERE/'protocol_impact_experiment_matrix.csv');rules=rows(HERE/'protocol_impact_acceptance_rules.csv')
if len(fams)!=64:fail.append('family_count')
if len(exp)!=768:fail.append('experiment_count')
if len(rules)!=96:fail.append('rule_count')
for f in fams:
 q=[x for x in exp if x['FamilyID']==f['FamilyID']]
 if len(q)!=12:fail.append('family_rows:'+f['FamilyID'])
 for p in {x['PairID'] for x in q}:
  z=[x for x in q if x['PairID']==p]
  if {x['Variant'] for x in z}!={'baseline','treatment'}:fail.append('pair_variant:'+p)
  if len({(x['Seed'],x['PayloadID'],x['ChannelRealizationID'],x['NoiseRealizationID'],x['SNR_dB']) for x in z})!=1:fail.append('pair_identity:'+p)
cap=rows(HERE/'protocol_capability_profile_matrix.csv')
if not any(truth(x['Supported']) for x in cap) or not any(not truth(x['Supported']) for x in cap):fail.append('capability_mix')
print(json.dumps({'manifest_files':len(m['files']),'vector_rows':sum(int(x['rows']) for x in m['files']),'impact_families':len(fams),'impact_experiments':len(exp),'acceptance_rules':len(rules),'failures':fail},indent=2))
sys.exit(0 if not fail else 2)
