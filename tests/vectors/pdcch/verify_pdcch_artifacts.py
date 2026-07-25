#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,hashlib,json,math,sys,tempfile
from pathlib import Path
try:
 from PIL import Image,ImageDraw,ImageStat
except ImportError as e: raise SystemExit('Pillow required') from e
HERE=Path(__file__).resolve().parent

def truth(v): return str(v).strip().upper() in {'1','TRUE','YES','PASS'}
def finite(v):
 try:x=float(str(v).strip())
 except:return None
 return x if math.isfinite(x) else None
def integer(v):
 x=finite(v);return int(x) if x is not None and abs(x-round(x))<1e-9 else None
def digest(p):
 h=hashlib.sha256();
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def readcsv(p):
 with p.open(newline='',encoding='utf-8-sig') as f:raw=list(csv.reader(f))
 if not raw:return [],[],['empty']
 h=raw[0];err=[]
 if len(h)!=len(set(h)):err.append('duplicate_header')
 rows=[]
 for i,r in enumerate(raw[1:],2):
  if len(r)!=len(h):err.append(f'nonrectangular:{i}')
  else:rows.append(dict(zip(h,r)))
 if not rows:err.append('no_rows')
 return h,rows,err
def contracts(name):
 with (HERE/name).open(newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))
def source_hash(root,names):
 h=hashlib.sha256()
 for n in sorted(names):
  p=root/n
  if not p.exists():return ''
  h.update(n.encode());h.update(digest(p).encode())
 return h.hexdigest()

def verify(root):
 fail=[];parsed={}; cc=contracts('desired_pdcch_csv_contract.csv');ic=contracts('desired_pdcch_image_contract.csv')
 for c in cc:
  p=root/c['FileName'];req=[x for x in c['RequiredColumns'].split('|') if x]
  if not p.exists():fail.append('missing_csv:'+p.name);continue
  h,rows,err=readcsv(p);parsed[p.name]=rows;fail += [p.name+':'+e for e in err]
  miss=[x for x in req if x not in h]
  if miss:fail.append(p.name+':missing_columns:'+','.join(miss));continue
  if len(rows)<int(c['MinRows']):fail.append(p.name+':too_few_rows')
  keys=[x for x in c['PrimaryKey'].split('|') if x];seen=set()
  for i,r in enumerate(rows,2):
   k=tuple(r.get(x,'') for x in keys)
   if k in seen:fail.append(p.name+':duplicate_key:'+str(k))
   seen.add(k)
   if 'Status' in r and str(r['Status']).upper()!='PASS':fail.append(p.name+f':nonpass:{i}')
 # technical fail-closed checks
 for i,r in enumerate(parsed.get('pdcch_dci_roundtrip.csv',[]),2):
  if integer(r.get('FieldMismatchCount'))!=0:fail.append(f'dci_roundtrip:mismatch:{i}')
  for f in ['LengthMismatchRejected','MissingFieldRejected','OutOfRangeRejected','UnexpectedFieldRejected']:
   if not truth(r.get(f)):fail.append(f'dci_roundtrip:not_rejected:{f}:{i}')
 for i,r in enumerate(parsed.get('pdcch_crc_scrambling.csv',[]),2):
  if not truth(r.get('CRCCheckPassed')) or not truth(r.get('WrongRNTICheckPassed')) or integer(r.get('MismatchCount'))!=0:fail.append(f'crc_scrambling:{i}')
 for i,r in enumerate(parsed.get('pdcch_polar_coding.csv',[]),2):
  if integer(r.get('RoundTripBitErrors'))!=0 or integer(r.get('IndependentMismatchCount'))!=0:fail.append(f'polar:{i}')
  al=integer(r.get('AggregationLevel'));E=integer(r.get('E'))
  if al not in {1,2,4,8,16} or E!=108*al:fail.append(f'polar_E:{i}')
 for i,r in enumerate(parsed.get('pdcch_coreset_mapping.csv',[]),2):
  if integer(r.get('REGCount'))!=6 or integer(r.get('UniqueREGCount'))!=6 or integer(r.get('MismatchCount'))!=0:fail.append(f'coreset_mapping:{i}')
 for i,r in enumerate(parsed.get('pdcch_re_ownership.csv',[]),2):
  if integer(r.get('CollisionCount'))!=0:fail.append(f're_collision:{i}')
 for i,r in enumerate(parsed.get('pdcch_dmrs_matrix.csv',[]),2):
  if integer(r.get('IndependentMismatchCount'))!=0:fail.append(f'dmrs_mismatch:{i}')
  if integer(r.get('DMRSRECount')) is None or integer(r.get('DMRSRECount'))<=0:fail.append(f'dmrs_re_count:{i}')
  if integer(r.get('CInit')) is None:fail.append(f'dmrs_cinit:{i}')
  if len(r.get('SequenceSHA256',''))!=64 or len(r.get('IndexSHA256',''))!=64:fail.append(f'dmrs_hash:{i}')
 for i,r in enumerate(parsed.get('pdcch_candidate_enumeration.csv',[]),2):
  if integer(r.get('FormulaMismatchCount'))!=0:fail.append(f'candidate_formula:{i}')
  al=integer(r.get('AggregationLevel'));fc=integer(r.get('FirstCCE'))
  if al not in {1,2,4,8,16} or fc is None or fc%al:fail.append(f'candidate_alignment:{i}')
 for i,r in enumerate(parsed.get('pdcch_blind_trials.csv',[]),2):
  if truth(r.get('KnownLocationUsed')) or truth(r.get('OracleTimingUsed')):fail.append(f'blind_oracle_used:{i}')
  signal=truth(r.get('SignalPresent'));correct=truth(r.get('CorrectDetection'));fa=truth(r.get('FalseAlarm'))
  if not signal and truth(r.get('GrantCreated','false')):fail.append(f'no_signal_grant:{i}')
  if fa and truth(r.get('CRCCheckPassed')):fail.append(f'false_alarm_crc_pass:{i}')
 for i,r in enumerate(parsed.get('pdcch_detection_curve.csv',[]),2):
  if truth(r.get('Incomplete')):fail.append(f'incomplete_curve:{i}')
  for f in ['Trials','DetectionProbability','DetectionCILower','DetectionCIUpper','FalseAlarmProbability','FalseAlarmCIUpper']:
   if finite(r.get(f)) is None:fail.append(f'curve_nonfinite:{f}:{i}')
 for i,r in enumerate(parsed.get('pdcch_type0_css.csv',[]),2):
  if integer(r.get('MismatchCount'))!=0:fail.append(f'type0_mismatch:{i}')
 for i,r in enumerate(parsed.get('pdcch_grant_authority.csv',[]),2):
  if truth(r.get('ConfiguredOracleMutation')) and r.get('ObservedEffect')!='UNCHANGED':fail.append(f'oracle_mutation_effect:{i}')
  if truth(r.get('DecodedBitsMutation')) and r.get('ObservedEffect')=='UNCHANGED':fail.append(f'decoded_mutation_no_effect:{i}')
  if not truth(r.get('CRCCheckPassed')) and truth(r.get('AssignmentCreated')):fail.append(f'crc_fail_assignment:{i}')
 for i,r in enumerate(parsed.get('pdcch_negative_tests.csv',[]),2):
  if not truth(r.get('Passed')) or truth(r.get('WaveformGenerated')) or truth(r.get('GrantCreated')) or truth(r.get('StateChanged')):fail.append(f'negative_case:{i}')
 required_families={'dci_schema_size','dci_pack_parse','crc24c_rnti_mask','pdcch_scrambling','qpsk','polar_coding_rate_matching','coreset_reg_cce_mapping','pdcch_dmrs','search_space_monitoring','candidate_enumeration','type0_css','grant_authority'}
 observed=set()
 for i,r in enumerate(parsed.get('pdcch_independent_vector_results.csv',[]),2):
  observed.add(r.get('VectorFamily',''))
  if integer(r.get('MismatchCount'))!=0:fail.append(f'oracle_mismatch:{i}')
  if any(x in r.get('OracleClass','').lower() for x in ['same_toolbox','self_consistency','same_implementation']):fail.append(f'nonindependent_oracle:{i}')
  if len(r.get('OracleArtifactSHA256',''))!=64:fail.append(f'oracle_hash:{i}')
 if required_families-observed:fail.append('missing_oracle_families:'+','.join(sorted(required_families-observed)))
 for i,r in enumerate(parsed.get('pdcch_test_summary.csv',[]),2):
  if truth(r.get('Mandatory')):
   if not truth(r.get('Executed')) or integer(r.get('Failed'))!=0 or integer(r.get('Skipped'))!=0 or integer(r.get('Blocked'))!=0 or not truth(r.get('Passed')):fail.append(f'mandatory_test_not_passed:{i}')
 audit={r.get('ImageFile',''):r for r in parsed.get('pdcch_image_semantic_audit.csv',[])}
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
 cc=contracts('desired_pdcch_csv_contract.csv');ic=contracts('desired_pdcch_image_contract.csv')
 with tempfile.TemporaryDirectory() as td:
  root=Path(td);pending_audit=None
  for c in cc:
   cols=c['RequiredColumns'].split('|');rows=[]
   if c['FileName']=='pdcch_image_semantic_audit.csv':pending_audit=(c,cols);continue
   count=max(int(c['MinRows']),1)
   for i in range(count):
    r={x:'1' for x in cols}
    if 'Status' in r:r['Status']='PASS'
    if 'RunID' in r:r['RunID']='SYN'
    if 'CaseID' in r:r['CaseID']=f'C{i}'
    for k in c['PrimaryKey'].split('|'):r[k]=f'{k}_{i}'
    if c['FileName']=='pdcch_dci_roundtrip.csv':r.update(FieldMismatchCount='0',LengthMismatchRejected='true',MissingFieldRejected='true',OutOfRangeRejected='true',UnexpectedFieldRejected='true')
    elif c['FileName']=='pdcch_crc_scrambling.csv':r.update(CRCCheckPassed='true',WrongRNTICheckPassed='true',MismatchCount='0')
    elif c['FileName']=='pdcch_polar_coding.csv':r.update(AggregationLevel='1',E='108',RoundTripBitErrors='0',IndependentMismatchCount='0')
    elif c['FileName']=='pdcch_coreset_mapping.csv':r.update(REGCount='6',UniqueREGCount='6',MismatchCount='0')
    elif c['FileName']=='pdcch_re_ownership.csv':r.update(CollisionCount='0')
    elif c['FileName']=='pdcch_dmrs_matrix.csv':r.update(NumerologyMu='0',Slot='0',Symbol='0',NID='42',CInit='42',CORESETID='1',PrecoderGranularity='allContiguousRBs',AttemptedPRBs='0|1',DMRSRECount='6',SequenceSHA256='a'*64,IndexSHA256='b'*64,IndependentMismatchCount='0')
    elif c['FileName']=='pdcch_candidate_enumeration.csv':r.update(AggregationLevel='1',FirstCCE=str(i),FormulaMismatchCount='0')
    elif c['FileName']=='pdcch_blind_trials.csv':r.update(SignalPresent='true',CorrectDetection='true',FalseAlarm='false',KnownLocationUsed='false',OracleTimingUsed='false',CRCCheckPassed='true')
    elif c['FileName']=='pdcch_detection_curve.csv':r.update(Trials='1000',DetectionProbability='0.99',DetectionCILower='0.98',DetectionCIUpper='1',FalseAlarmProbability='0',FalseAlarmCIUpper='0.003',Incomplete='false')
    elif c['FileName']=='pdcch_type0_css.csv':r.update(MismatchCount='0')
    elif c['FileName']=='pdcch_grant_authority.csv':r.update(CRCCheckPassed='true',ConfiguredOracleMutation='false',DecodedBitsMutation='true',AssignmentCreated='true',ObservedEffect='CHANGED')
    elif c['FileName']=='pdcch_negative_tests.csv':r.update(Passed='true',WaveformGenerated='false',GrantCreated='false',StateChanged='false')
    elif c['FileName']=='pdcch_independent_vector_results.csv':
     fam=['dci_schema_size','dci_pack_parse','crc24c_rnti_mask','pdcch_scrambling','qpsk','polar_coding_rate_matching','coreset_reg_cce_mapping','pdcch_dmrs','search_space_monitoring','candidate_enumeration','type0_css','grant_authority']
     r.update(VectorFamily=fam[i%len(fam)],VectorID=f'V{i}',OracleClass='pure_spec',OracleArtifactSHA256='a'*64,MismatchCount='0',MaxAbsError='0',Tolerance='0')
    elif c['FileName']=='pdcch_test_summary.csv':r.update(Mandatory='true',Executed='true',Passed='true',Failed='0',Skipped='0',Blocked='0')
    rows.append(r)
   write(root/c['FileName'],cols,rows)
  sem=[];semcols=pending_audit[1]
  for idx,c in enumerate(ic):
   w=max(1000,int(c['MinWidth']));h=max(650,int(c['MinHeight']));im=Image.new('RGB',(w,h),'white');d=ImageDraw.Draw(im);d.rectangle((40,40,w-40,h-50),outline='black',width=3)
   for j in range(80):d.ellipse((60+j*(w-120)//80,60+((j*37+idx*19)%(h-140)),64+j*(w-120)//80,64+((j*37+idx*19)%(h-140))),fill='black')
   im.save(root/c['ImageFile']);src=[x for x in c['SourceCSV'].split('|') if x]
   sem.append(dict(ImageFile=c['ImageFile'],SourceCSV=c['SourceCSV'],Width=w,Height=h,AxesCount=c['MinAxesCount'],SeriesCount=c['MinSeriesCount'],FinitePointCount=c['MinFinitePointCount'],ExpectedTitleToken=c['ExpectedTitleToken'],ActualTitle='Synthetic '+c['ExpectedTitleToken'],ExpectedXLabel=c['ExpectedXLabel'],ActualXLabel=c['ExpectedXLabel'],ExpectedYLabel=c['ExpectedYLabel'],ActualYLabel=c['ExpectedYLabel'],SourceCSV_SHA256=source_hash(root,src),PNG_SHA256=digest(root/c['ImageFile']),Status='PASS'))
  write(root/'pdcch_image_semantic_audit.csv',semcols,sem)
  good=verify(root);sem[0]['PNG_SHA256']='0'*64;write(root/'pdcch_image_semantic_audit.csv',semcols,sem);bad=verify(root)
  print('selftest',good,bad);return 0 if good==0 and bad==2 else 3
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('output_dir',nargs='?',type=Path);ap.add_argument('--self-test',action='store_true');a=ap.parse_args();raise SystemExit(selftest() if a.self_test else verify(a.output_dir))
