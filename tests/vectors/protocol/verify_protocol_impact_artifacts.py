#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,hashlib,json,math,sys,tempfile
from pathlib import Path
from PIL import Image,ImageDraw,ImageStat
HERE=Path(__file__).resolve().parent
CSV_CONTRACT='desired_protocol_impact_csv_contract.csv';IMG_CONTRACT='desired_protocol_impact_image_contract.csv';AUDIT='protocol_impact_image_semantic_audit.csv'
def truth(v):return str(v).strip().lower() in {'1','true','yes','pass'}
def integer(v):
 try:x=float(str(v));return int(round(x)) if math.isfinite(x) and abs(x-round(x))<1e-9 else None
 except:return None
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def readcsv(p):
 with p.open(newline='',encoding='utf-8-sig') as f:r=list(csv.reader(f))
 if not r:return [],[],['empty']
 h=r[0];out=[];e=[]
 for i,x in enumerate(r[1:],2):
  if len(x)!=len(h):e.append('nonrectangular:'+str(i))
  else:out.append(dict(zip(h,x)))
 if not out:e.append('no_rows')
 return h,out,e
def contracts(fn):
 with (HERE/fn).open(newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))
def source_hash(root,names):
 h=hashlib.sha256()
 for n in sorted(filter(None,names)):
  p=root/n
  if not p.exists():return ''
  h.update(n.encode());h.update(digest(p).encode())
 return h.hexdigest()
def verify(root):
 fail=[];parsed={};cc=contracts(CSV_CONTRACT);ic=contracts(IMG_CONTRACT)
 for c in cc:
  p=root/c['FileName'];req=c['RequiredColumns'].split('|')
  if not p.exists():fail.append('missing_csv:'+p.name);continue
  h,rs,e=readcsv(p);parsed[p.name]=rs;fail += [p.name+':'+x for x in e]
  miss=[x for x in req if x not in h]
  if miss:fail.append(p.name+':missing:'+','.join(miss));continue
  if len(rs)<int(c['MinRows']):fail.append(p.name+':too_few_rows')
  seen=set()
  for i,r in enumerate(rs,2):
   k=tuple(r.get(x,'') for x in c['PrimaryKey'].split('|'))
   if k in seen:fail.append(p.name+':duplicate:'+repr(k))
   seen.add(k)
   if 'Status' in r and r['Status'].upper()!='PASS':fail.append(p.name+':nonpass:'+str(i))
 # Impact gates.
 expected=len(list(csv.DictReader((HERE/'protocol_impact_experiment_matrix.csv').open(encoding='utf-8-sig'))))
 if len(parsed.get('protocol_impact_operating_points.csv',[]))<expected:fail.append('impact_points_missing')
 for i,r in enumerate(parsed.get('protocol_impact_operating_points.csv',[]),2):
  if truth(r.get('Incomplete')) or r.get('StopReason')!='criteria_met':fail.append('incomplete:'+str(i))
 for i,r in enumerate(parsed.get('protocol_impact_rule_evaluation.csv',[]),2):
  if r.get('RuleClass')=='HARD_CORRECTNESS' and r.get('Result')!='PASS':fail.append('hard_rule:'+str(i))
 for i,r in enumerate(parsed.get('protocol_impact_lineage.csv',[]),2):
  if any(integer(r.get(x))!=0 for x in ['OrphanNodes','UnownedBytes','DuplicateDeliveredBytes','ConservationErrorBytes','GoodputAccountingErrorBits']):fail.append('impact_lineage:'+str(i))
 for i,r in enumerate(parsed.get('protocol_impact_summary.csv',[]),2):
  if integer(r.get('ExperimentsComplete'))!=integer(r.get('ExperimentsExpected')) or integer(r.get('RulesFailed'))!=0 or integer(r.get('IncompletePoints'))!=0 or integer(r.get('HardFailures'))!=0:fail.append('impact_summary:'+str(i))
 audit={r.get('ImageFile',''):r for r in parsed.get(AUDIT,[])}
 for c in ic:
  p=root/c['ImageFile'];n=p.name
  if not p.exists():fail.append('missing_png:'+n);continue
  try:
   with Image.open(p) as im:im.load();w,h=im.size;var=ImageStat.Stat(im.convert('L')).var[0]
  except Exception as e:fail.append('bad_png:'+n+':'+str(e));continue
  if w<int(c['MinWidth']) or h<int(c['MinHeight']):fail.append('small_png:'+n)
  if var<1:fail.append('blank_png:'+n)
  a=audit.get(n)
  if not a:fail.append('missing_audit:'+n);continue
  if a.get('PNG_SHA256')!=digest(p):fail.append('png_hash_mismatch:'+n)
  if a.get('SourceCSV_SHA256')!=source_hash(root,c['SourceCSV'].split('|')):fail.append('source_hash_mismatch:'+n)
  if integer(a.get('AxesCount'))<int(c['MinAxesCount']):fail.append('axes:'+n)
  if integer(a.get('SeriesCount'))<int(c['MinSeriesCount']):fail.append('series:'+n)
  if integer(a.get('FinitePointCount'))<int(c['MinFinitePointCount']):fail.append('points:'+n)
  if c['ExpectedTitleToken'].lower() not in a.get('ActualTitle','').lower():fail.append('title:'+n)
 print(json.dumps({'required_csvs':len(cc),'required_pngs':len(ic),'failures':fail},indent=2));return 0 if not fail else 2
def write(p,cols,rs):
 with p.open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,fieldnames=cols);w.writeheader();w.writerows(rs)
def selftest():
 cc=contracts(CSV_CONTRACT);ic=contracts(IMG_CONTRACT);oracles=[]
 with tempfile.TemporaryDirectory() as td:
  root=Path(td);pending=None;seq=0
  for c in cc:
   cols=c['RequiredColumns'].split('|');fn=c['FileName']
   if fn==AUDIT:pending=cols;continue
   rs=[]
   for i in range(max(1,int(c['MinRows']))):
    r={x:'1' for x in cols}
    for k in c['PrimaryKey'].split('|'):r[k]=f'{k}_{i}'
    if 'RunID' in r:r['RunID']='SYN'
    if 'Status' in r:r['Status']='PASS'
    if 'EventSequence' in r:seq+=1;r['EventSequence']=str(seq)
    for k in ['PayloadSHA256','EncodedSHA256','DecodedSHA256','DecodedTreeSHA256','IndependentVectorSHA256','ParentSHA256','NodeSHA256','OracleArtifactSHA256']:
     if k in r:r[k]='a'*64
    if 'MismatchCount' in r:r['MismatchCount']='0'
    if fn=='pdcp_security_results.csv':r.update(ExpectedHex='AA',ActualHex='AA',MismatchCount='0')
    if fn=='radio_bearer_config.csv':r.update(RRCValidated='true',RLCCommitted='true',PDCPCommitted='true',SDAPCommitted='true',MACCommitted='true',Atomic='true')
    if fn=='protocol_conservation.csv':r.update(UnownedBytes='0',DuplicateDeliveredBytes='0',EquationErrorBytes='0')
    if fn=='protocol_negative_tests.csv':r.update(ExpectedError='sixgr:protocol:X',ActualError='sixgr:protocol:X',StateChanged='false',PDUProduced='false',DeliveryCounted='false',Passed='true')
    if fn=='protocol_independent_vector_results.csv':r.update(VectorFamily=oracles[i%len(oracles)],OracleClass='pure_spec_math',OracleImplementation='python',OracleVersion='1',OracleArtifactSHA256='a'*64,Cases='1',MismatchCount='0',MaxAbsoluteError='0')
    if fn=='protocol_impact_operating_points.csv':r.update(Incomplete='false',StopReason='criteria_met',Trials='100',Packets='1000',Errors='10',DeliveryRate='0.99',CILower='0.98',CIUpper='1',MeanLatency_ms='5',P95Latency_ms='8',MeanGoodput_Mbps='10',MeanRuntime_ms='1')
    if fn=='protocol_impact_rule_evaluation.csv':r.update(RuleClass='HARD_CORRECTNESS',Result='PASS',EvidenceRows='10')
    if fn=='protocol_impact_lineage.csv':r.update(OrphanNodes='0',UnownedBytes='0',DuplicateDeliveredBytes='0',ConservationErrorBytes='0',GoodputAccountingErrorBits='0')
    if fn=='protocol_impact_summary.csv':r.update(ExperimentsExpected='768',ExperimentsComplete='768',RulesPassed='96',RulesFailed='0',IncompletePoints='0',HardFailures='0')
    rs.append(r)
   write(root/fn,cols,rs)
  audits=[]
  for c in ic:
   p=root/c['ImageFile'];im=Image.new('RGB',(1000,700),'white');d=ImageDraw.Draw(im);d.line((10,10,990,690),fill='black',width=5);im.save(p)
   audits.append({'RunID':'SYN','ImageFile':p.name,'SourceCSV':c['SourceCSV'],'SourceCSV_SHA256':source_hash(root,c['SourceCSV'].split('|')),'PNG_SHA256':digest(p),'Width':'1000','Height':'700','AxesCount':'1','SeriesCount':str(max(3,int(c['MinSeriesCount']))),'FinitePointCount':str(max(30,int(c['MinFinitePointCount']))),'ActualTitle':c['ExpectedTitleToken'],'ActualXLabel':c['ExpectedXLabel'],'ActualYLabel':c['ExpectedYLabel'],'Status':'PASS'})
  write(root/AUDIT,pending,audits);ok=verify(root)
  h,r,_=readcsv(root/AUDIT);r[0]['PNG_SHA256']='0'*64;write(root/AUDIT,h,r);bad=verify(root)
  print(json.dumps({'valid_exit':ok,'corrupt_exit':bad},indent=2));return 0 if ok==0 and bad==2 else 3
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('root',nargs='?',type=Path);p.add_argument('--self-test',action='store_true');a=p.parse_args();sys.exit(selftest() if a.self_test else verify(a.root))
