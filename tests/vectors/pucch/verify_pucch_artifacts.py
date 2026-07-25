#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,hashlib,json,math,sys,tempfile
from pathlib import Path
try:
 from PIL import Image,ImageDraw,ImageStat
except ImportError as e: raise SystemExit('Pillow required') from e
HERE=Path(__file__).resolve().parent

def truth(v):return str(v).strip().upper() in {'1','TRUE','YES','PASS'}
def finite(v):
 try:x=float(str(v).strip())
 except:return None
 return x if math.isfinite(x) else None
def integer(v):
 x=finite(v);return int(x) if x is not None and abs(x-round(x))<1e-9 else None
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def readcsv(p):
 with p.open(newline='',encoding='utf-8-sig') as f:raw=list(csv.reader(f))
 if not raw:return [],[],['empty']
 h=raw[0];err=[];out=[]
 if len(h)!=len(set(h)):err.append('duplicate_header')
 for i,r in enumerate(raw[1:],2):
  if len(r)!=len(h):err.append(f'nonrectangular:{i}')
  else:out.append(dict(zip(h,r)))
 if not out:err.append('no_rows')
 return h,out,err
def contracts(name):
 with (HERE/name).open(newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))
def source_hash(root,names):
 h=hashlib.sha256()
 for n in sorted(filter(None,names)):
  p=root/n
  if not p.exists():return ''
  h.update(n.encode());h.update(digest(p).encode())
 return h.hexdigest()

def verify(root):
 fail=[];parsed={};cc=contracts('desired_pucch_csv_contract.csv');ic=contracts('desired_pucch_image_contract.csv')
 for c in cc:
  p=root/c['FileName'];req=[x for x in c['RequiredColumns'].split('|') if x]
  if not p.exists():fail.append('missing_csv:'+p.name);continue
  h,rs,err=readcsv(p);parsed[p.name]=rs;fail += [p.name+':'+e for e in err]
  miss=[x for x in req if x not in h]
  if miss:fail.append(p.name+':missing_columns:'+','.join(miss));continue
  if len(rs)<int(c['MinRows']):fail.append(p.name+':too_few_rows')
  keys=[x for x in c['PrimaryKey'].split('|') if x];seen=set()
  for i,r in enumerate(rs,2):
   k=tuple(r.get(x,'') for x in keys)
   if k in seen:fail.append(p.name+':duplicate_key:'+repr(k))
   seen.add(k)
   if 'Status' in r and r['Status'].upper()!='PASS':fail.append(p.name+f':nonpass:{i}')
 # fail-closed technical checks
 for i,r in enumerate(parsed.get('pucch_uci_report_resolution.csv',[]),2):
  if not r.get('ReportProvenance','').strip():fail.append(f'report_provenance:{i}')
 for i,r in enumerate(parsed.get('pucch_uci_serialization.csv',[]),2):
  if truth(r.get('Mismatch')):fail.append(f'uci_serialization_mismatch:{i}')
  if r.get('BitOwner') not in {'HARQ_ACK','SR','CSI_PART1','CSI_PART2','PADDING'}:fail.append(f'uci_unknown_owner:{i}')
 for i,r in enumerate(parsed.get('pucch_uci_coding.csv',[]),2):
  A=integer(r.get('A'));crc=integer(r.get('CRCBits'))
  if A is None or crc is None:fail.append(f'coding_nonfinite:{i}');continue
  if A<=11 and crc!=0:fail.append(f'coding_crc_small:{i}')
  if 12<=A<=19 and crc!=6:fail.append(f'coding_crc6:{i}')
  if A>=20 and crc!=11:fail.append(f'coding_crc11:{i}')
  if integer(r.get('RoundTripBitErrors'))!=0 or integer(r.get('IndependentMismatchCount'))!=0:fail.append(f'coding_mismatch:{i}')
 for i,r in enumerate(parsed.get('pucch_resource_set_selection.csv',[]),2):
  if integer(r.get('SelectionMismatchCount'))!=0 or truth(r.get('DefaultOrHashUsed')):fail.append(f'resource_set:{i}')
  if not r.get('RRCConfigurationEpoch','').strip():fail.append(f'resource_epoch:{i}')
 for i,r in enumerate(parsed.get('pucch_resource_indicator_selection.csv',[]),2):
  if integer(r.get('MismatchCount'))!=0:fail.append(f'pri_mismatch:{i}')
 for i,r in enumerate(parsed.get('pucch_format_matrix.csv',[]),2):
  if truth(r.get('ParameterMutated')):fail.append(f'format_parameter_mutated:{i}')
  if truth(r.get('Valid'))!=truth(r.get('ExpectedValid')):fail.append(f'format_validity:{i}')
 for i,r in enumerate(parsed.get('pucch_resource_mapping.csv',[]),2):
  if integer(r.get('CollisionCount')) not in {0}:fail.append(f're_mapping_collision:{i}')
  if len(r.get('IndexDigest',''))!=64:fail.append(f're_index_hash:{i}')
 for i,r in enumerate(parsed.get('pucch_dmrs_sequence.csv',[]),2):
  if integer(r.get('IndependentMismatchCount'))!=0:fail.append(f'dmrs_mismatch:{i}')
  if len(r.get('SequenceSHA256',''))!=64 or len(r.get('IndexSHA256',''))!=64:fail.append(f'dmrs_hash:{i}')
 for i,r in enumerate(parsed.get('pucch_harq_codebook.csv',[]),2):
  if truth(r.get('Mismatch')):fail.append(f'harq_codebook:{i}')
 for i,r in enumerate(parsed.get('pucch_sr_events.csv',[]),2):
  if truth(r.get('Mismatch')):fail.append(f'sr_mismatch:{i}')
 for i,r in enumerate(parsed.get('pucch_csi_reports.csv',[]),2):
  if truth(r.get('Mismatch')):fail.append(f'csi_mismatch:{i}')
 for i,r in enumerate(parsed.get('pucch_timing_k1_tdd.csv',[]),2):
  if truth(r.get('SymbolShiftApplied')):fail.append(f'timing_shift:{i}')
  if integer(r.get('DueSlot'))!=integer(r.get('ExpectedDueSlot')) or truth(r.get('Legal'))!=truth(r.get('ExpectedLegal')):fail.append(f'timing_mismatch:{i}')
  if r.get('K1Source') not in {'decoded_dci','rrc_dl_DataToUL_ACK','sps_activation_context'}:fail.append(f'timing_source:{i}')
 for i,r in enumerate(parsed.get('pucch_collision_resolution.csv',[]),2):
  if truth(r.get('UnresolvedCollision')) or r.get('ResolutionAction')!=r.get('ExpectedAction'):fail.append(f'collision:{i}')
 for i,r in enumerate(parsed.get('pucch_power_control.csv',[]),2):
  if finite(r.get('PowerError_dB')) is None or abs(float(r['PowerError_dB']))>0.05:fail.append(f'power_reconcile:{i}')
 for i,r in enumerate(parsed.get('pucch_spatial_relation.csv',[]),2):
  if integer(r.get('MismatchCount'))!=0 or r.get('SelectedBeamID')!=r.get('AppliedBeamID'):fail.append(f'spatial:{i}')
 for i,r in enumerate(parsed.get('pucch_receiver_metrics.csv',[]),2):
  if truth(r.get('OraclePayloadBitsUsed')):fail.append(f'receiver_oracle:{i}')
  if finite(r.get('MeasuredSINR_dB')) is None:fail.append(f'receiver_sinr:{i}')
 for i,r in enumerate(parsed.get('pucch_bler_curve.csv',[]),2):
  if truth(r.get('Incomplete')):fail.append(f'bler_incomplete:{i}')
  for f in ['Trials','BlockErrors','BLER','CILower','CIUpper']:
   if finite(r.get(f)) is None:fail.append(f'bler_nonfinite:{f}:{i}')
 for i,r in enumerate(parsed.get('pucch_false_alarm_trials.csv',[]),2):
  if truth(r.get('Incomplete')):fail.append(f'false_alarm_incomplete:{i}')
  if finite(r.get('CIUpper')) is None:fail.append(f'false_alarm_ci:{i}')
 for i,r in enumerate(parsed.get('pucch_negative_tests.csv',[]),2):
  if not truth(r.get('Passed')) or truth(r.get('StateChanged')) or truth(r.get('GrantCreated')):fail.append(f'negative:{i}')
  if r.get('FaultType')!='no_signal' and truth(r.get('WaveformGenerated')):fail.append(f'negative_waveform:{i}')
 required={'uci_report_serialization','uci_coding','harq_ack_codebook','sr_state','csi_report','resource_set_selection','resource_indicator','format_mapping','dmrs','hopping_repetition','k1_tdd','power_control','spatial_relation'}
 seen=set()
 for i,r in enumerate(parsed.get('pucch_independent_vector_results.csv',[]),2):
  seen.add(r.get('VectorFamily',''))
  if integer(r.get('MismatchCount'))!=0:fail.append(f'oracle_mismatch:{i}')
  if any(x in r.get('OracleClass','').lower() for x in ['same_toolbox','self_consistency','same_implementation']):fail.append(f'nonindependent_oracle:{i}')
  if len(r.get('OracleArtifactSHA256',''))!=64:fail.append(f'oracle_hash:{i}')
 if required-seen:fail.append('missing_oracle_families:'+','.join(sorted(required-seen)))
 for i,r in enumerate(parsed.get('pucch_test_summary.csv',[]),2):
  if truth(r.get('Mandatory')) and (not truth(r.get('Executed')) or not truth(r.get('Passed')) or integer(r.get('Failed'))!=0 or integer(r.get('Skipped'))!=0 or integer(r.get('Blocked'))!=0):fail.append(f'mandatory_test:{i}')
 audit={r.get('ImageFile',''):r for r in parsed.get('pucch_image_semantic_audit.csv',[])}
 for c in ic:
  p=root/c['ImageFile'];name=p.name
  if not p.exists():fail.append('missing_png:'+name);continue
  try:
   with Image.open(p) as im:im.load();w,h=im.size;var=ImageStat.Stat(im.convert('L')).var[0]
  except Exception as e:fail.append('bad_png:'+name+':'+str(e));continue
  if w<int(c['MinWidth']) or h<int(c['MinHeight']):fail.append('small_png:'+name)
  if var<1.0:fail.append('blank_png:'+name)
  a=audit.get(name)
  if not a:fail.append('missing_image_audit:'+name);continue
  if a.get('PNG_SHA256')!=digest(p):fail.append('png_hash_mismatch:'+name)
  src=[x for x in c['SourceCSV'].split('|') if x]
  if a.get('SourceCSV_SHA256')!=source_hash(root,src):fail.append('source_hash_mismatch:'+name)
  if integer(a.get('AxesCount')) is None or integer(a.get('AxesCount'))<int(c['MinAxesCount']):fail.append('axes:'+name)
  if integer(a.get('SeriesCount')) is None or integer(a.get('SeriesCount'))<int(c['MinSeriesCount']):fail.append('series:'+name)
  if integer(a.get('FinitePointCount')) is None or integer(a.get('FinitePointCount'))<int(c['MinFinitePointCount']):fail.append('points:'+name)
  if c['ExpectedTitleToken'].lower() not in a.get('ActualTitle','').lower():fail.append('title:'+name)
  if ' '.join(c['ExpectedXLabel'].split())!=' '.join(a.get('ActualXLabel','').split()):fail.append('xlabel:'+name)
  if ' '.join(c['ExpectedYLabel'].split())!=' '.join(a.get('ActualYLabel','').split()):fail.append('ylabel:'+name)
 print(json.dumps({'required_csvs':len(cc),'required_pngs':len(ic),'failures':fail},indent=2))
 return 0 if not fail else 2

def write(path,cols,rows):
 with path.open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,fieldnames=cols);w.writeheader();w.writerows(rows)
def selftest():
 cc=contracts('desired_pucch_csv_contract.csv');ic=contracts('desired_pucch_image_contract.csv')
 with tempfile.TemporaryDirectory() as td:
  root=Path(td);pending=None
  for c in cc:
   cols=c['RequiredColumns'].split('|')
   if c['FileName']=='pucch_image_semantic_audit.csv':pending=(c,cols);continue
   rs=[]
   for i in range(max(1,int(c['MinRows']))):
    r={x:'1' for x in cols}
    for k in c['PrimaryKey'].split('|'):r[k]=f'{k}_{i}'
    if 'Status' in r:r['Status']='PASS'
    if 'RunID' in r:r['RunID']='SYN'
    fn=c['FileName']
    if fn=='pucch_uci_report_resolution.csv':r.update(ReportProvenance='decoded_context')
    elif fn=='pucch_uci_serialization.csv':r.update(BitOwner='HARQ_ACK',Mismatch='false')
    elif fn=='pucch_uci_coding.csv':r.update(A='12',CRCBits='6',RoundTripBitErrors='0',IndependentMismatchCount='0')
    elif fn=='pucch_resource_set_selection.csv':r.update(SelectionMismatchCount='0',DefaultOrHashUsed='false',RRCConfigurationEpoch='1')
    elif fn=='pucch_resource_indicator_selection.csv':r.update(MismatchCount='0')
    elif fn=='pucch_format_matrix.csv':r.update(ParameterMutated='false',Valid='true',ExpectedValid='true')
    elif fn=='pucch_resource_mapping.csv':r.update(CollisionCount='0',IndexDigest='a'*64)
    elif fn=='pucch_dmrs_sequence.csv':r.update(IndependentMismatchCount='0',SequenceSHA256='a'*64,IndexSHA256='b'*64)
    elif fn=='pucch_harq_codebook.csv':r.update(Mismatch='false')
    elif fn=='pucch_sr_events.csv':r.update(Mismatch='false')
    elif fn=='pucch_csi_reports.csv':r.update(Mismatch='false')
    elif fn=='pucch_timing_k1_tdd.csv':r.update(SymbolShiftApplied='false',DueSlot='4',ExpectedDueSlot='4',Legal='true',ExpectedLegal='true',K1Source='decoded_dci')
    elif fn=='pucch_collision_resolution.csv':r.update(UnresolvedCollision='false',ResolutionAction='OK',ExpectedAction='OK')
    elif fn=='pucch_power_control.csv':r.update(PowerError_dB='0')
    elif fn=='pucch_spatial_relation.csv':r.update(MismatchCount='0',SelectedBeamID='B1',AppliedBeamID='B1')
    elif fn=='pucch_receiver_metrics.csv':r.update(OraclePayloadBitsUsed='false',MeasuredSINR_dB='10')
    elif fn=='pucch_bler_curve.csv':r.update(Incomplete='false',Trials='100',BlockErrors='10',BLER='.1',CILower='.05',CIUpper='.15')
    elif fn=='pucch_false_alarm_trials.csv':r.update(Incomplete='false',CIUpper='.01')
    elif fn=='pucch_negative_tests.csv':r.update(Passed='true',StateChanged='false',GrantCreated='false',WaveformGenerated='false',FaultType='wrong_length')
    elif fn=='pucch_independent_vector_results.csv':
     fam=['uci_report_serialization','uci_coding','harq_ack_codebook','sr_state','csi_report','resource_set_selection','resource_indicator','format_mapping','dmrs','hopping_repetition','k1_tdd','power_control','spatial_relation'][i%13]
     r.update(VectorFamily=fam,OracleClass='pure_spec',OracleArtifactSHA256='c'*64,MismatchCount='0')
    elif fn=='pucch_test_summary.csv':r.update(Mandatory='true',Executed='true',Passed='true',Failed='0',Skipped='0',Blocked='0')
    rs.append(r)
   write(root/c['FileName'],cols,rs)
  audits=[]
  for c in ic:
   p=root/c['ImageFile'];im=Image.new('RGB',(1000,700),'white');d=ImageDraw.Draw(im);d.line((10,10,990,690),fill='black',width=5);d.text((40,40),c['ExpectedTitleToken'],fill='black');im.save(p)
   audits.append({'RunID':'SYN','ImageFile':p.name,'SourceCSV':c['SourceCSV'],'SourceCSV_SHA256':source_hash(root,c['SourceCSV'].split('|')),'PNG_SHA256':digest(p),'Width':'1000','Height':'700','AxesCount':c['MinAxesCount'],'SeriesCount':c['MinSeriesCount'],'FinitePointCount':c['MinFinitePointCount'],'ActualTitle':c['ExpectedTitleToken'],'ActualXLabel':c['ExpectedXLabel'],'ActualYLabel':c['ExpectedYLabel'],'Status':'PASS'})
  write(root/'pucch_image_semantic_audit.csv',pending[1],audits)
  ok=verify(root)
  # corruption test
  rows_a=list(csv.DictReader((root/'pucch_image_semantic_audit.csv').open()))
  rows_a[0]['PNG_SHA256']='0'*64
  write(root/'pucch_image_semantic_audit.csv',pending[1],rows_a)
  bad=verify(root)
  print(json.dumps({'valid_exit':ok,'corrupt_exit':bad},indent=2))
  return 0 if ok==0 and bad==2 else 3
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('root',nargs='?',type=Path);p.add_argument('--self-test',action='store_true');a=p.parse_args()
 sys.exit(selftest() if a.self_test else verify(a.root))
