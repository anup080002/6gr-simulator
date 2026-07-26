#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,hashlib,json,math,sys,tempfile
from pathlib import Path
try:
 from PIL import Image,ImageDraw,ImageStat
except ImportError as e:raise SystemExit('Pillow required') from e
HERE=Path(__file__).resolve().parent

def truth(v):return str(v).strip().upper() in {'1','TRUE','YES','PASS'}
def finite(v):
 try:x=float(str(v).strip())
 except:return None
 return x if math.isfinite(x) else None
def integer(v):
 x=finite(v);return int(round(x)) if x is not None and abs(x-round(x))<1e-9 else None
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

def verify(root:Path):
 fail=[];parsed={};cc=contracts('desired_mac_csv_contract.csv');ic=contracts('desired_mac_image_contract.csv')
 for c in cc:
  p=root/c['FileName'];req=c['RequiredColumns'].split('|')
  if not p.exists():fail.append('missing_csv:'+p.name);continue
  h,rs,err=readcsv(p);parsed[p.name]=rs;fail += [p.name+':'+e for e in err]
  miss=[x for x in req if x not in h]
  if miss:fail.append(p.name+':missing_columns:'+','.join(miss));continue
  if len(rs)<int(c['MinRows']):fail.append(p.name+':too_few_rows')
  keys=c['PrimaryKey'].split('|');seen=set()
  for i,r in enumerate(rs,2):
   k=tuple(r.get(x,'') for x in keys)
   if k in seen:fail.append(p.name+':duplicate_key:'+repr(k))
   seen.add(k)
   if 'Status' in r and r['Status'].upper()!='PASS':fail.append(p.name+':nonpass:'+str(i))
 # Specialized correctness checks.
 seq=[integer(r.get('EventSequence')) for r in parsed.get('mac_event_log.csv',[])]
 if any(x is None for x in seq) or seq!=sorted(seq):fail.append('event_sequence_order')
 for fn in ['mac_bsr_table_results.csv','mac_phr_mapping_results.csv']:
  for i,r in enumerate(parsed.get(fn,[]),2):
   if integer(r.get('BoundaryMismatchCount'))!=0:fail.append(fn+':mismatch:'+str(i))
 for i,r in enumerate(parsed.get('mac_scheduler_grants.csv',[]),2):
  if not truth(r.get('Committed')) or not r.get('DecodedDCIEventID') or len(r.get('GrantSHA256',''))!=64:fail.append('grant_authority:'+str(i))
 for i,r in enumerate(parsed.get('mac_conservation_ledger.csv',[]),2):
  if any(integer(r.get(k))!=0 for k in ['UnownedBytes','DuplicateDeliveredBytes','EquationErrorBytes']):fail.append('conservation:'+str(i))
 for i,r in enumerate(parsed.get('mac_negative_tests.csv',[]),2):
  if r.get('ExpectedError')!=r.get('ActualError') or any(truth(r.get(k)) for k in ['HARQStateChanged','QueueStateChanged','WaveformGenerated','GrantCommitted','DeliveryCounted']) or not truth(r.get('Passed')):fail.append('negative:'+str(i))
 required={'bsr5','bsr8','bsr_refined','phr','pcmax','harq_state','harq_feedback','timing','tdd','soft_buffer','lcp','pdu','ta','scheduler','lineage'}
 seen=set()
 for i,r in enumerate(parsed.get('mac_independent_vector_results.csv',[]),2):
  seen.add(r.get('VectorFamily',''))
  if integer(r.get('MismatchCount'))!=0 or finite(r.get('MaxAbsoluteError')) is None:fail.append('oracle_mismatch:'+str(i))
  if any(x in r.get('OracleClass','').lower() for x in ['same_toolbox','self_consistency','same_implementation']):fail.append('nonindependent_oracle:'+str(i))
  if len(r.get('OracleArtifactSHA256',''))!=64:fail.append('oracle_hash:'+str(i))
 if required-seen:fail.append('missing_oracle_families:'+','.join(sorted(required-seen)))
 for i,r in enumerate(parsed.get('mac_test_summary.csv',[]),2):
  if truth(r.get('Mandatory')) and (not truth(r.get('Executed')) or not truth(r.get('Passed')) or integer(r.get('Failed'))!=0 or integer(r.get('Skipped'))!=0 or integer(r.get('Blocked'))!=0):fail.append('mandatory_test:'+str(i))
 for i,r in enumerate(parsed.get('mac_capability_resolution.csv',[]),2):
  expected=truth(r.get('ExpectedSupported'));actual=truth(r.get('ActualSupported'))
  if expected!=actual:fail.append('capability:'+str(i))
  if not expected and (not truth(r.get('PlanningRejected')) or truth(r.get('StateChanged'))):fail.append('capability_rejection:'+str(i))
 audit={r.get('ImageFile',''):r for r in parsed.get('mac_image_semantic_audit.csv',[])}
 for c in ic:
  p=root/c['ImageFile'];name=p.name
  if not p.exists():fail.append('missing_png:'+name);continue
  try:
   with Image.open(p) as im:im.load();w,h=im.size;var=ImageStat.Stat(im.convert('L')).var[0]
  except Exception as e:fail.append('bad_png:'+name+':'+str(e));continue
  if w<int(c['MinWidth']) or h<int(c['MinHeight']):fail.append('small_png:'+name)
  if var<1:fail.append('blank_png:'+name)
  a=audit.get(name)
  if not a:fail.append('missing_image_audit:'+name);continue
  if a.get('PNG_SHA256')!=digest(p):fail.append('png_hash_mismatch:'+name)
  src=c['SourceCSV'].split('|')
  if a.get('SourceCSV_SHA256')!=source_hash(root,src):fail.append('source_hash_mismatch:'+name)
  if integer(a.get('AxesCount')) is None or integer(a['AxesCount'])<int(c['MinAxesCount']):fail.append('axes:'+name)
  if integer(a.get('SeriesCount')) is None or integer(a['SeriesCount'])<int(c['MinSeriesCount']):fail.append('series:'+name)
  if integer(a.get('FinitePointCount')) is None or integer(a['FinitePointCount'])<int(c['MinFinitePointCount']):fail.append('points:'+name)
  if c['ExpectedTitleToken'].lower() not in a.get('ActualTitle','').lower():fail.append('title:'+name)
  if ' '.join(c['ExpectedXLabel'].split())!=' '.join(a.get('ActualXLabel','').split()):fail.append('xlabel:'+name)
  if ' '.join(c['ExpectedYLabel'].split())!=' '.join(a.get('ActualYLabel','').split()):fail.append('ylabel:'+name)
 print(json.dumps({'required_csvs':len(cc),'required_pngs':len(ic),'failures':fail},indent=2))
 return 0 if not fail else 2

def write(path,cols,rs):
 with path.open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,fieldnames=cols);w.writeheader();w.writerows(rs)
def selftest():
 cc=contracts('desired_mac_csv_contract.csv');ic=contracts('desired_mac_image_contract.csv');oracles=['bsr5','bsr8','bsr_refined','phr','pcmax','harq_state','harq_feedback','timing','tdd','soft_buffer','lcp','pdu','ta','scheduler','lineage']
 with tempfile.TemporaryDirectory() as td:
  root=Path(td);pending=None;eventseq=0
  for c in cc:
   cols=c['RequiredColumns'].split('|');fn=c['FileName']
   if fn=='mac_image_semantic_audit.csv':pending=(cols,c);continue
   n=max(1,int(c['MinRows']));rs=[]
   for i in range(n):
    r={x:'1' for x in cols}
    for k in c['PrimaryKey'].split('|'):r[k]=f'{k}_{i}'
    if 'RunID' in r:r['RunID']='SYN'
    if 'Status' in r:r['Status']='PASS'
    if 'EventSequence' in r:eventseq+=1;r['EventSequence']=str(eventseq)
    for k in ['PayloadSHA256','ProjectionSHA256','CodingLayoutSHA256','RateMatchSHA256','ReceiverSHA256','EncodedSHA256','DecodedSHA256','GrantSHA256','SnapshotSHA256','SHA256']:
     if k in r:r[k]='a'*64
    if fn=='mac_run_manifest.csv':r.update(GitCommit='abc',MATLABVersion='R2025b',ToolboxVersion='25.2',SpecProfile='rel18',SeedList='11|23',VectorManifestSHA256='a'*64,Strict='true')
    elif fn in ['mac_bsr_table_results.csv','mac_phr_mapping_results.csv']:r.update(BoundaryMismatchCount='0')
    elif fn=='mac_scheduler_grants.csv':r.update(DecodedDCIEventID='DCI1',Committed='true',GrantSHA256='a'*64)
    elif fn=='mac_conservation_ledger.csv':r.update(UnownedBytes='0',DuplicateDeliveredBytes='0',EquationErrorBytes='0')
    elif fn=='mac_negative_tests.csv':r.update(ExpectedError='sixgr:mac:X',ActualError='sixgr:mac:X',HARQStateChanged='false',QueueStateChanged='false',WaveformGenerated='false',GrantCommitted='false',DeliveryCounted='false',Passed='true')
    elif fn=='mac_independent_vector_results.csv':r.update(VectorFamily=oracles[i%len(oracles)],OracleClass='pure_spec_math',OracleImplementation='python_independent',OracleVersion='1',OracleArtifactSHA256='a'*64,Cases='1',MismatchCount='0',MaxAbsoluteError='0')
    elif fn=='mac_test_summary.csv':r.update(Mandatory='true',Executed='true',Passed='true',Total='1',Failed='0',Skipped='0',Blocked='0',DurationSeconds='1')
    elif fn=='mac_capability_resolution.csv':r.update(ExpectedSupported='true',ActualSupported='true',PlanningRejected='false',StateChanged='false')
    rs.append(r)
   write(root/fn,cols,rs)
  audits=[]
  for c in ic:
   p=root/c['ImageFile'];im=Image.new('RGB',(1000,700),'white');d=ImageDraw.Draw(im);d.line((10,10,990,690),fill='black',width=5);d.line((10,690,990,10),fill='black',width=3);im.save(p)
   audits.append({'RunID':'SYN','ImageFile':p.name,'SourceCSV':c['SourceCSV'],'SourceCSV_SHA256':source_hash(root,c['SourceCSV'].split('|')),'PNG_SHA256':digest(p),'Width':'1000','Height':'700','AxesCount':'1','SeriesCount':str(max(3,int(c['MinSeriesCount']))),'FinitePointCount':str(max(30,int(c['MinFinitePointCount']))),'ActualTitle':c['ExpectedTitleToken'],'ActualXLabel':c['ExpectedXLabel'],'ActualYLabel':c['ExpectedYLabel'],'Status':'PASS'})
  write(root/'mac_image_semantic_audit.csv',pending[0],audits)
  ok=verify(root)
  h,ar,_=readcsv(root/'mac_image_semantic_audit.csv');ar[0]['PNG_SHA256']='0'*64;write(root/'mac_image_semantic_audit.csv',h,ar)
  bad=verify(root);print(json.dumps({'valid_exit':ok,'corrupt_exit':bad},indent=2));return 0 if ok==0 and bad==2 else 3
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('root',nargs='?',type=Path);p.add_argument('--self-test',action='store_true');a=p.parse_args();sys.exit(selftest() if a.self_test else verify(a.root))
