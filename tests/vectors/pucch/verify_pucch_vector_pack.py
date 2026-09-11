#!/usr/bin/env python3
from __future__ import annotations
import csv,hashlib,json,math,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent

def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def rows(p):
 with p.open(newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))
def truth(v):return str(v).lower() in {'1','true','yes','pass'}
fail=[]
m=json.loads((HERE/'independent_vector_manifest.json').read_text())
for x in m['files']:
 p=HERE/x['path']
 if not p.exists():fail.append('missing:'+x['path']);continue
 if sha(p)!=x['sha256']:fail.append('sha:'+x['path'])
 if len(rows(p))!=int(x['rows']):fail.append('rows:'+x['path'])
# UCI serialization invariants
inp={r['CaseID']:r for r in rows(HERE/'pucch_uci_report_test_vectors.csv')}
for r in rows(HERE/'expected_pucch_uci_serialization.csv'):
 q=inp[r['CaseID']];s1=q['HARQACKBits']+q['SRBits']+q['CSIPart1Bits'];s2=q['CSIPart2Bits']
 if truth(q['TwoPartCSI']) and len(s2)<3:s2=s2+'0'*(3-len(s2))
 if r['Sequence1Bits']!=s1 or r['Sequence2Bits']!=s2:fail.append('uci_order:'+r['CaseID'])
# Coding boundaries
for r in rows(HERE/'expected_pucch_uci_coding_plan.csv'):
 A=int(next(x['A'] for x in rows(HERE/'pucch_uci_coding_test_vectors.csv') if x['CaseID']==r['CaseID']))
 if A<=11 and int(r['CRCBits'])!=0:fail.append('crc_small:'+r['CaseID'])
 if 12<=A<=19 and int(r['CRCBits'])!=6:fail.append('crc6:'+r['CaseID'])
 if 20<=A<=1706 and int(r['CRCBits'])!=11:fail.append('crc11:'+r['CaseID'])
# Format table floor
for i,o in zip(rows(HERE/'pucch_format_matrix_test_vectors.csv'),rows(HERE/'expected_pucch_format_validation.csv')):
 if i['CaseID']!=o['CaseID']:fail.append('format_pair')
 fmt=int(i['Format']);ns=int(i['NumSymbols']);b=int(i['UCIBits'])
 lenok=(fmt==0 and 1<=ns<=2) or (fmt==1 and 4<=ns<=14) or (fmt==2 and 1<=ns<=2) or (fmt in [3,4] and 4<=ns<=14)
 bitok=(b<=2 if fmt<=1 else b>2) and 0<b<=1706
 if truth(o['ExpectedValid'])!=(lenok and bitok):
  # Additional resource constraints may only make a tuple invalid, never rescue bad length/payload.
  if truth(o['ExpectedValid']):fail.append('format_validity:'+i['CaseID'])
# SR arithmetic
imap={r['CaseID']:r for r in rows(HERE/'pucch_sr_test_vectors.csv')}
for r in rows(HERE/'expected_pucch_sr_occasion.csv'):
 q=imap[r['CaseID']];slot=int(q['AbsoluteSlot']);period=int(q['PeriodSlots']);off=int(q['OffsetSlots'])
 occasion=slot>=off and (slot-off)%period==0
 if truth(r['IsSROccasion'])!=occasion:fail.append('sr:'+r['CaseID'])
# K1 no-shift invariant
for r in rows(HERE/'expected_pucch_timing_resolution.csv'):
 if truth(r['SymbolShiftAllowed']):fail.append('k1_shift:'+r['CaseID'])
# TS 38.213 V18.8.0 9.2.3: independent resource-list partition arithmetic.
# Build all eight groups rather than calling/copying the MATLAB resolver.
pri_inputs={r['CaseID']:r for r in rows(HERE/'pucch_resource_indicator_test_vectors.csv')}
for r in rows(HERE/'expected_pucch_resource_indicator_selection.csv'):
 q=pri_inputs[r['CaseID']]
 size,pri,width=int(q['ResourceListSize']),int(q['PRIValue']),int(q['PRIFieldWidth'])
 formula=int(q['ResourceSetID'])==0 and size>8
 valid=(size>0 and 0<=width<=3 and 0<=pri<2**width and truth(q['RequiresSet0CCEFormula'])==formula)
 ordinal=None
 if valid and formula:
  first,total=int(q['FirstCCE']),int(q['NumCCE'])
  valid=0<=first<total
  if valid:
   groups=[size//8+int(group<size%8) for group in range(8)]
   ordinal=sum(groups[:pri])+(first*groups[pri])//total+1
 elif valid:
  valid=pri<size
  if valid:ordinal=pri+1
 if truth(r['ExpectedValid'])!=valid:fail.append('pri_validity:'+r['CaseID'])
 if valid and r['ExpectedOrdinal']!=str(ordinal):fail.append('pri_ordinal:'+r['CaseID'])
# Power arithmetic
pmap={r['CaseID']:r for r in rows(HERE/'pucch_power_control_test_vectors.csv')}
for r in rows(HERE/'expected_pucch_power_control.csv'):
 q=pmap[r['CaseID']];mu=int(q['Mu']);mrb=int(q['MRB'])
 exp=min(float(q['PCMAXdBm']),float(q['P0dBm'])+10*math.log10((2**mu)*mrb)+float(q['PathlossdB'])+float(q['DeltaFdB'])+float(q['DeltaTFdB'])+float(q['ClosedLoopAdjustmentdB']))
 if abs(exp-float(r['ExpectedTransmitPowerdBm']))>1e-8:fail.append('power:'+r['CaseID'])
# Impact matrix exactness
exp=rows(HERE/'pucch_impact_experiment_matrix.csv')
if len(exp)!=600:fail.append('impact_count')
for fid in {r['FamilyID'] for r in exp}:
 x=[r for r in exp if r['FamilyID']==fid]
 if len(x)!=12:fail.append('family_count:'+fid)
 for pid in {r['PairID'] for r in x}:
  if {r['Variant'] for r in x if r['PairID']==pid}!={'baseline','treatment'}:fail.append('pair:'+pid)
print(json.dumps({'manifest_files':len(m['files']),'vector_rows':sum(int(x['rows']) for x in m['files']),'failures':fail},indent=2))
sys.exit(0 if not fail else 2)
