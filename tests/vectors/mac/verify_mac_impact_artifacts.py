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
 h=raw[0];out=[];err=[]
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
 fail=[];parsed={};cc=contracts('desired_mac_impact_csv_contract.csv');ic=contracts('desired_mac_impact_image_contract.csv')
 for c in cc:
  p=root/c['FileName'];req=c['RequiredColumns'].split('|')
  if not p.exists():fail.append('missing_csv:'+p.name);continue
  h,rs,err=readcsv(p);parsed[p.name]=rs;fail += [p.name+':'+e for e in err]
  miss=[x for x in req if x not in h]
  if miss:fail.append(p.name+':missing_columns:'+','.join(miss));continue
  if len(rs)<int(c['MinRows']):fail.append(p.name+':too_few_rows')
  seen=set()
  for i,r in enumerate(rs,2):
   k=tuple(r.get(x,'') for x in c['PrimaryKey'].split('|'))
   if k in seen:fail.append(p.name+':duplicate_key:'+repr(k))
   seen.add(k)
   if 'Status' in r and r['Status'].upper()!='PASS':fail.append(p.name+':nonpass:'+str(i))
 ops=parsed.get('mac_impact_operating_points.csv',[])
 if len(ops)<768:fail.append('operating_point_count')
 for i,r in enumerate(ops,2):
  if truth(r.get('Incomplete')) or r.get('StopReason') not in {'criteria_met','exact_vector_complete','complete'}:fail.append('incomplete:'+str(i))
  for k in ['BLER','CILower','CIUpper','MeanLatency_ms','MeanGoodputMbps','MeanFairness','MeanRuntime_ms']:
   if finite(r.get(k)) is None:fail.append('nonfinite:'+k+':'+str(i))
 rules=parsed.get('mac_impact_rule_evaluation.csv',[])
 if len(rules)<96:fail.append('rule_count')
 for i,r in enumerate(rules,2):
  if r.get('Result')!='PASS':fail.append('rule_fail:'+str(i))
 summary=parsed.get('mac_impact_summary.csv',[])
 if len(summary)<64:fail.append('summary_count')
 for i,r in enumerate(summary,2):
  if integer(r.get('ExperimentsComplete'))!=integer(r.get('ExperimentsExpected')) or integer(r.get('RulesFailed'))!=0 or integer(r.get('IncompletePoints'))!=0:fail.append('family_incomplete:'+str(i))
 for i,r in enumerate(parsed.get('mac_impact_lineage.csv',[]),2):
  if any(integer(r.get(k))!=0 for k in ['OrphanNodes','UnownedBytes','DuplicateDeliveredBytes','ConservationErrorBytes','GoodputAccountingErrorBits']):fail.append('lineage:'+str(i))
 audit={r.get('ImageFile',''):r for r in parsed.get('mac_impact_image_semantic_audit.csv',[])}
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
  if a.get('SourceCSV_SHA256')!=source_hash(root,c['SourceCSV'].split('|')):fail.append('source_hash_mismatch:'+name)
  if integer(a.get('AxesCount')) is None or integer(a['AxesCount'])<int(c['MinAxesCount']):fail.append('axes:'+name)
  if integer(a.get('SeriesCount')) is None or integer(a['SeriesCount'])<int(c['MinSeriesCount']):fail.append('series:'+name)
  if integer(a.get('FinitePointCount')) is None or integer(a['FinitePointCount'])<int(c['MinFinitePointCount']):fail.append('points:'+name)
  if c['ExpectedTitleToken'].lower() not in a.get('ActualTitle','').lower():fail.append('title:'+name)
  if ' '.join(c['ExpectedXLabel'].split())!=' '.join(a.get('ActualXLabel','').split()):fail.append('xlabel:'+name)
  if ' '.join(c['ExpectedYLabel'].split())!=' '.join(a.get('ActualYLabel','').split()):fail.append('ylabel:'+name)
 print(json.dumps({'required_csvs':len(cc),'required_pngs':len(ic),'operating_points':len(ops),'rules':len(rules),'failures':fail},indent=2))
 return 0 if not fail else 2
def write(path,cols,rs):
 with path.open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,fieldnames=cols);w.writeheader();w.writerows(rs)
def selftest():
 cc=contracts('desired_mac_impact_csv_contract.csv');ic=contracts('desired_mac_impact_image_contract.csv')
 with tempfile.TemporaryDirectory() as td:
  root=Path(td);pending=None
  for c in cc:
   cols=c['RequiredColumns'].split('|');fn=c['FileName']
   if fn=='mac_impact_image_semantic_audit.csv':pending=cols;continue
   n=max(1,int(c['MinRows']));rs=[]
   for i in range(n):
    r={x:'1' for x in cols}
    for k in c['PrimaryKey'].split('|'):r[k]=f'{k}_{i}'
    if 'RunID' in r:r['RunID']='SYN'
    if 'Status' in r:r['Status']='PASS'
    if fn=='mac_impact_operating_points.csv':r.update(Incomplete='false',StopReason='criteria_met',BLER='.1',CILower='.08',CIUpper='.12',MeanLatency_ms='5',MeanGoodputMbps='10',MeanFairness='.9',MeanRuntime_ms='1')
    elif fn=='mac_impact_rule_evaluation.csv':r.update(Result='PASS',ObservedValue='0',EvidenceRows='10')
    elif fn=='mac_impact_summary.csv':r.update(ExperimentsExpected='12',ExperimentsComplete='12',RulesPassed='1',RulesFailed='0',IncompletePoints='0')
    elif fn=='mac_impact_lineage.csv':r.update(OrphanNodes='0',UnownedBytes='0',DuplicateDeliveredBytes='0',ConservationErrorBytes='0',GoodputAccountingErrorBits='0')
    rs.append(r)
   write(root/fn,cols,rs)
  audits=[]
  for c in ic:
   p=root/c['ImageFile'];im=Image.new('RGB',(1000,700),'white');d=ImageDraw.Draw(im);d.line((10,10,990,690),fill='black',width=5);d.line((10,690,990,10),fill='black',width=3);im.save(p)
   audits.append({'RunID':'SYN','ImageFile':p.name,'SourceCSV':c['SourceCSV'],'SourceCSV_SHA256':source_hash(root,c['SourceCSV'].split('|')),'PNG_SHA256':digest(p),'Width':'1000','Height':'700','AxesCount':'1','SeriesCount':'3','FinitePointCount':'30','ActualTitle':c['ExpectedTitleToken'],'ActualXLabel':c['ExpectedXLabel'],'ActualYLabel':c['ExpectedYLabel'],'Status':'PASS'})
  write(root/'mac_impact_image_semantic_audit.csv',pending,audits)
  ok=verify(root)
  h,ar,_=readcsv(root/'mac_impact_image_semantic_audit.csv');ar[0]['PNG_SHA256']='0'*64;write(root/'mac_impact_image_semantic_audit.csv',h,ar)
  bad=verify(root);print(json.dumps({'valid_exit':ok,'corrupt_exit':bad},indent=2));return 0 if ok==0 and bad==2 else 3
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('root',nargs='?',type=Path);p.add_argument('--self-test',action='store_true');a=p.parse_args();sys.exit(selftest() if a.self_test else verify(a.root))
