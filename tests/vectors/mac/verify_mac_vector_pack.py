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
def truth(v):return str(v).strip().upper() in {'TRUE','PASS','YES','1'}
def num(v):
 try:return float(str(v).strip())
 except:return None
fail=[]
manifest=json.loads((HERE/'independent_vector_manifest.json').read_text())
for x in manifest['files']:
 p=HERE/x['path']
 if not p.exists():fail.append('missing:'+x['path']);continue
 if sha(p)!=x['sha256']:fail.append('sha:'+x['path'])
 if len(rows(p))!=int(x['rows']):fail.append('rows:'+x['path'])

# Exact BSR tables.
for name,count in [('expected_bsr_5bit_table.csv',32),('expected_bsr_8bit_table.csv',256),('expected_refined_bsr_8bit_table.csv',256)]:
 r=rows(HERE/name)
 if len(r)!=count or {int(x['Index']) for x in r}!=set(range(count)):fail.append('table_indices:'+name)
for name in ['expected_bsr_5bit_table.csv','expected_bsr_8bit_table.csv','expected_refined_bsr_8bit_table.csv']:
 r=rows(HERE/name);prev=-math.inf
 for x in r:
  if truth(x['Reserved']):continue
  up=num(x['UpperInclusive'])
  if up is not None:
   if up<prev:fail.append('table_nonmonotonic:'+name+':'+x['Index'])
   prev=up
r5=rows(HERE/'expected_bsr_5bit_table.csv')
if r5[0]['UpperInclusive']!='0' or r5[30]['UpperInclusive']!='150000' or r5[31]['Relation']!='GT':fail.append('bsr5_boundaries')
r8=rows(HERE/'expected_bsr_8bit_table.csv')
if r8[254]['Relation']!='GT' or not truth(r8[255]['Reserved']):fail.append('bsr8_tail')
rr=rows(HERE/'expected_refined_bsr_8bit_table.csv')
if rr[0]['LowerExclusive']!='4751' or rr[0]['UpperInclusive']!='5000' or rr[255]['UpperInclusive']!='750000':fail.append('refined_boundaries')

# Exact PH and PCMAX mapping floors.
ph=rows(HERE/'expected_phr_mapping.csv');pc=rows(HERE/'expected_pcmax_mapping.csv')
if len(ph)!=64 or ph[0]['Relation']!='LT' or ph[54]['LowerInclusive']!='21' or ph[55]['LowerInclusive']!='22' or ph[63]['Relation']!='GE':fail.append('ph_mapping')
if len(pc)!=64 or pc[0]['UpperExclusive']!='-29' or pc[1]['LowerInclusive']!='-29' or pc[62]['LowerInclusive']!='32' or pc[63]['LowerInclusive']!='33':fail.append('pcmax_mapping')

# HARQ bounded state machine.
valid={'IDLE':{'RESERVE_NEW':'NEW_DATA_RESERVED'},'NEW_DATA_RESERVED':{'COMMIT_GRANT':'TX_SCHEDULED','CANCEL_GRANT':'IDLE'},'TX_SCHEDULED':{'PHY_TX':'TX_TRANSMITTED','CANCEL_BEFORE_TX':'IDLE'},'TX_TRANSMITTED':{'START_FEEDBACK_WAIT':'AWAITING_FEEDBACK'},'AWAITING_FEEDBACK':{'ACK':'ACKED_DELIVERED','NACK':'RETX_PENDING','DTX':'RETX_PENDING','MAX_RETX':'DROPPED','TA_EXPIRED':'FLUSHED','RRC_RESET':'FLUSHED'},'RETX_PENDING':{'COMMIT_RETX':'RETX_SCHEDULED','MAX_RETX':'DROPPED','RRC_RESET':'FLUSHED'},'RETX_SCHEDULED':{'PHY_TX':'TX_TRANSMITTED','CANCEL_RETX':'RETX_PENDING'},'ACKED_DELIVERED':{'RELEASE':'IDLE'},'DROPPED':{'RELEASE':'IDLE'},'FLUSHED':{'RELEASE':'IDLE'}}
for x in rows(HERE/'mac_harq_state_transition_vectors.csv'):
 ok=x['Event'] in valid.get(x['FromState'],{})
 if truth(x['ExpectedValid'])!=ok:fail.append('harq_valid:'+x['CaseID'])
 if ok and x['ToState']!=valid[x['FromState']][x['Event']]:fail.append('harq_to:'+x['CaseID'])

# Timing and TDD arithmetic.
for x in rows(HERE/'mac_timing_k0_k1_k2_vectors.csv'):
 base=int(x['PDCCHSlot'])
 if int(x['PDSCHSlot'])!=base+int(x['K0']) or int(x['PUCCHSlot'])!=base+int(x['K0'])+int(x['K1']) or int(x['PUSCHSlot'])!=base+int(x['K2']):fail.append('timing:'+x['CaseID'])
for x in rows(HERE/'mac_tdd_eligibility_vectors.csv'):
 seg=x['Segment'];req=x['RequestedDirection']
 ok=all(c in ('D','F') for c in seg) if req=='DL' else all(c in ('U','F') for c in seg) if req=='UL' else all(c=='F' for c in seg)
 if truth(x['ExpectedLegal'])!=ok:fail.append('tdd:'+x['CaseID'])

# Soft-buffer provenance: only all matching fields may combine.
for x in rows(HERE/'mac_soft_buffer_provenance_vectors.csv'):
 ok=all(truth(x[k]) for k in ['SameTB','SameCodeword','SameCodingLayout','SameMotherCodePositions','SameServingCell','SameNDIEpoch'])
 if truth(x['ExpectedCombine'])!=ok:fail.append('soft:'+x['CaseID'])

# Exact PHR index calculations.
def phidx(v):
 if v<-32:return 0
 if v<22:return int(math.floor(v))+33
 if v<38:return 55+int((v-22)//2)
 return 63
def pcidx(v):
 if v<-29:return 0
 if v<33:return int(math.floor(v))+30
 return 63
for x in rows(HERE/'mac_phr_trigger_timer_vectors.csv'):
 if int(x['ExpectedPHIndex'])!=phidx(float(x['PH_dB'])) or int(x['ExpectedPCMAXIndex'])!=pcidx(float(x['PCMAX_dBm'])):fail.append('phr_index:'+x['CaseID'])

# LCP Bj floor.
for x in rows(HERE/'mac_lcp_test_vectors.csv'):
 pbr=float(x['PrioritizedBitRate_kBps']);prev=float(x['PreviousBj_Bytes']);bsd=float(x['BucketSizeDuration_ms']);dt=float(x['Elapsed_ms'])
 if pbr<0:expected='INF'
 else:expected=min(pbr*bsd,prev+pbr*dt)
 if expected=='INF':
  if x['ExpectedBj_Bytes']!='INF':fail.append('lcp_inf:'+x['CaseID'])
 elif abs(float(x['ExpectedBj_Bytes'])-expected)>1e-9:fail.append('lcp_bj:'+x['CaseID'])

# PDU header floor.
for x in rows(HERE/'mac_pdu_subheader_test_vectors.csv'):
 expected=1 if x['SizeType'] in {'fixed','implicit'} else (2 if int(x['PayloadLength'])<256 else 3)
 if int(x['ExpectedHeaderBytes'])!=expected:fail.append('pdu_header:'+x['CaseID'])

# Scheduler metric floor.
for x in rows(HERE/'mac_scheduler_policy_test_vectors.csv'):
 inst=float(x['InstantRate']);avg=float(x['AverageRate']);hol=float(x['HoLDelay_ms']);pdb=float(x['PDB_ms']);prio=float(x['Priority']);ue=int(x['UEID']);seed=int(x['Seed']);n=int(x['NumUE'])
 if x['Policy']=='RR':m=(ue+seed)%n
 elif x['Policy']=='PF':m=inst/avg
 elif x['Policy']=='QoS-PF':m=(inst/avg)*(1+hol/max(1,pdb))*(9-prio)
 else:m=-max(0,pdb-hol)
 if abs(float(x['ExpectedMetric'])-m)>1e-9:fail.append('sched_metric:'+x['CaseID'])

# Packet segment conservation.
lin=rows(HERE/'mac_packet_lineage_test_vectors.csv')
for pid in {x['PacketID'] for x in lin}:
 q=[x for x in lin if x['PacketID']==pid]
 if sum(int(x['SegmentBytes']) for x in q)!=int(q[0]['PacketBytes']):fail.append('packet_conservation:'+pid)
 if sorted(int(x['SegmentOffset']) for x in q)!=[sum(int(y['SegmentBytes']) for y in q[:i]) for i in range(len(q))]:fail.append('segment_offsets:'+pid)

# Impact matrix and pairing.
fams=rows(HERE/'mac_impact_analysis_families.csv');exp=rows(HERE/'mac_impact_experiment_matrix.csv');rules=rows(HERE/'mac_impact_acceptance_rules.csv')
if len(fams)!=64:fail.append('family_count')
if len(exp)!=768:fail.append('experiment_count')
if len(rules)!=96:fail.append('rule_count')
for f in fams:
 q=[x for x in exp if x['FamilyID']==f['FamilyID']]
 if len(q)!=12:fail.append('family_experiments:'+f['FamilyID'])
 for pid in {x['PairID'] for x in q}:
  z=[x for x in q if x['PairID']==pid]
  if {x['Variant'] for x in z}!={'baseline','treatment'}:fail.append('pair_variants:'+pid)
  ident={(x['Seed'],x['PayloadID'],x['ChannelRealizationID'],x['NoiseRealizationID'],x['SNR_dB']) for x in z}
  if len(ident)!=1:fail.append('pair_identity:'+pid)

cap=rows(HERE/'mac_capability_profile_matrix.csv')
if not any(truth(x['Supported']) for x in cap) or not any(not truth(x['Supported']) for x in cap):fail.append('capability_supported_unsupported')

print(json.dumps({'manifest_files':len(manifest['files']),'vector_rows':sum(int(x['rows']) for x in manifest['files']),'impact_families':len(fams),'impact_experiments':len(exp),'acceptance_rules':len(rules),'failures':fail},indent=2))
sys.exit(0 if not fail else 2)
