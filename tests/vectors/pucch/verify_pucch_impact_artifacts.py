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
 x=finite(v);return int(x) if x is not None and abs(x-round(x))<1e-9 else None
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def rows(p):
 with p.open(newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))
def rawcsv(p):
 with p.open(newline='',encoding='utf-8-sig') as f:x=list(csv.reader(f))
 if not x:return [],[],['empty']
 h=x[0];out=[];err=[]
 for i,r in enumerate(x[1:],2):
  if len(r)!=len(h):err.append(f'nonrectangular:{i}')
  else:out.append(dict(zip(h,r)))
 if not out:err.append('no_rows')
 return h,out,err
def contract(name):return rows(HERE/name)
def source_hash(root,names):
 h=hashlib.sha256()
 for n in sorted(filter(None,names)):
  p=root/n
  if not p.exists():return ''
  h.update(n.encode());h.update(digest(p).encode())
 return h.hexdigest()
def verify(root):
 fail=[];parsed={};cc=contract('desired_pucch_impact_csv_contract.csv');ic=contract('desired_pucch_impact_image_contract.csv');exp=contract('pucch_impact_experiment_matrix.csv');rules=contract('pucch_impact_acceptance_rules.csv')
 expids={r['ExperimentID'] for r in exp};ruleids={r['RuleID'] for r in rules}
 for c in cc:
  p=root/c['FileName'];req=c['RequiredColumns'].split('|')
  if not p.exists():fail.append('missing_csv:'+p.name);continue
  h,rs,err=rawcsv(p);parsed[p.name]=rs;fail += [p.name+':'+e for e in err]
  if any(x not in h for x in req):fail.append(p.name+':missing_columns')
  if len(rs)<int(c['MinRows']):fail.append(p.name+':too_few_rows')
  seen=set();keys=c['PrimaryKey'].split('|')
  for i,r in enumerate(rs,2):
   k=tuple(r.get(x,'') for x in keys)
   if k in seen:fail.append(p.name+':duplicate:'+repr(k))
   seen.add(k)
   if 'Status' in r and r['Status'].upper()!='PASS':fail.append(p.name+f':nonpass:{i}')
 man=parsed.get('pucch_impact_run_manifest.csv',[])
 for i,r in enumerate(man,2):
  for f in ['GitCommit','MATLABVersion','ToolboxVersion','SeedList','ExperimentMatrixSHA256']:
   if not r.get(f,'').strip():fail.append(f'manifest:{f}:{i}')
 raw=parsed.get('pucch_impact_raw_trials.csv',[]);pv={}
 inputmap={r['ExperimentID']:r for r in exp}
 for i,r in enumerate(raw,2):
  if r.get('ExperimentID') not in expids:fail.append(f'unknown_experiment:{i}')
  q=inputmap.get(r.get('ExperimentID',''))
  if q:
   for f in ['FamilyID','PairID','Variant','FactorName','FactorValue','BaselineFactorValue','PayloadID','Channel','SNR_dB']:
    if r.get(f)!=q.get(f):fail.append(f'experiment_mismatch:{f}:{i}')
  for f in ['MeasuredSINR_dB','EVMPercent','TransmitPowerdBm','RuntimeMs','MemoryMB']:
   if finite(r.get(f)) is None:fail.append(f'raw_nonfinite:{f}:{i}')
  key=(r.get('FamilyID'),r.get('PairID'),r.get('Seed'),r.get('TrialIndex'))
  pv.setdefault(key,set()).add(r.get('Variant'))
 for k,v in pv.items():
  if v!={'baseline','treatment'}:fail.append('incomplete_pair:'+repr(k))
 ops=parsed.get('pucch_impact_operating_points.csv',[])
 done={r.get('ExperimentID') for r in ops}
 if expids-done:fail.append('missing_experiments:'+str(len(expids-done)))
 for i,r in enumerate(ops,2):
  if truth(r.get('Incomplete')):fail.append(f'incomplete:{i}')
  for f in ['Trials','BlockErrors','BLER','BLERCILower','BLERCIUpper','FalseAlarmProbability','FalseAlarmCIUpper','MeanSINR_dB','MeanEVMPercent','MeanPowerdBm','MeanRuntimeMs','MeanMemoryMB']:
   if finite(r.get(f)) is None:fail.append(f'op_nonfinite:{f}:{i}')
 evals=parsed.get('pucch_impact_rule_evaluation.csv',[])
 if ruleids-{r.get('RuleID') for r in evals}:fail.append('missing_rules')
 rulemap={r['RuleID']:r for r in rules}
 for i,r in enumerate(evals,2):
  q=rulemap.get(r.get('RuleID',''))
  if not q:fail.append(f'unknown_rule:{i}');continue
  if q['Severity']=='HARD' and not truth(r.get('Passed')):fail.append(f'hard_rule:{i}')
  if finite(r.get('ObservedValue')) is None:fail.append(f'rule_nonfinite:{i}')
 for i,r in enumerate(parsed.get('pucch_impact_pairwise_effects.csv',[]),2):
  vals={f:finite(r.get(f)) for f in ['BaselineValue','TreatmentValue','AbsoluteEffect','CILower','CIUpper','PValue','AdjustedPValue','EffectSize']}
  if any(v is None for v in vals.values()):fail.append(f'effect_nonfinite:{i}');continue
  if abs((vals['TreatmentValue']-vals['BaselineValue'])-vals['AbsoluteEffect'])>1e-9:fail.append(f'effect_sign:{i}')
  if vals['AdjustedPValue']+1e-12<vals['PValue']:fail.append(f'holm:{i}')
 for i,r in enumerate(parsed.get('pucch_impact_summary.csv',[]),2):
  if integer(r.get('ExperimentsExecuted'))!=integer(r.get('ExperimentsExpected')):fail.append(f'summary_experiments:{i}')
  if integer(r.get('HardRulesFailed'))!=0 or integer(r.get('BlockedCount'))!=0:fail.append(f'summary_fail:{i}')
 audit={r.get('ImageFile',''):r for r in parsed.get('pucch_impact_image_semantic_audit.csv',[])}
 for c in ic:
  p=root/c['ImageFile'];name=p.name
  if not p.exists():fail.append('missing_png:'+name);continue
  try:
   with Image.open(p) as im:im.load();w,h=im.size;var=ImageStat.Stat(im.convert('L')).var[0]
  except Exception as e:fail.append('bad_png:'+name+':'+str(e));continue
  if w<int(c['MinWidth']) or h<int(c['MinHeight']) or var<1:fail.append('image_structure:'+name)
  a=audit.get(name)
  if not a:fail.append('missing_audit:'+name);continue
  if a.get('PNG_SHA256')!=digest(p):fail.append('png_hash_mismatch:'+name)
  if a.get('SourceCSV_SHA256')!=source_hash(root,c['SourceCSV'].split('|')):fail.append('source_hash_mismatch:'+name)
  if c['ExpectedTitleToken'].lower() not in a.get('ActualTitle','').lower():fail.append('title:'+name)
  if a.get('ActualXLabel')!=c['ExpectedXLabel'] or a.get('ActualYLabel')!=c['ExpectedYLabel']:fail.append('labels:'+name)
 print(json.dumps({'experiments_expected':len(expids),'rules_expected':len(ruleids),'required_csvs':len(cc),'required_pngs':len(ic),'failures':fail},indent=2))
 return 0 if not fail else 2

def write(p,cols,rs):
 with p.open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,fieldnames=cols);w.writeheader();w.writerows(rs)
def selftest():
 cc=contract('desired_pucch_impact_csv_contract.csv');ic=contract('desired_pucch_impact_image_contract.csv');exp=contract('pucch_impact_experiment_matrix.csv');rules=contract('pucch_impact_acceptance_rules.csv')
 with tempfile.TemporaryDirectory() as td:
  root=Path(td);pending=None
  for c in cc:
   cols=c['RequiredColumns'].split('|')
   if c['FileName']=='pucch_impact_image_semantic_audit.csv':pending=(c,cols);continue
   rs=[];n=max(1,int(c['MinRows']))
   for i in range(n):
    r={x:'1' for x in cols};fn=c['FileName']
    for k in c['PrimaryKey'].split('|'):r[k]=f'{k}_{i}'
    if 'RunID' in r:r['RunID']='SYN'
    if 'Status' in r:r['Status']='PASS'
    if fn=='pucch_impact_run_manifest.csv':r.update(GitCommit='abc',MATLABVersion='R2025b',ToolboxVersion='25.2',SeedList='11|23',ExperimentMatrixSHA256='a'*64,ConfidenceLevel='.95')
    elif fn=='pucch_impact_raw_trials.csv':
     q=exp[i%len(exp)];r.update({k:q[k] for k in ['ExperimentID','FamilyID','PairID','Variant','FactorName','FactorValue','BaselineFactorValue','PayloadID','Channel','SNR_dB']});r.update(Seed='11',TrialIndex=str(i//len(exp)),ChannelRealizationID='C',NoiseRealizationID='N',MeasuredSINR_dB='1',EVMPercent='1',TransmitPowerdBm='0',RuntimeMs='1',MemoryMB='1')
    elif fn=='pucch_impact_operating_points.csv':
     q=exp[i%len(exp)];r.update(ExperimentID=q['ExperimentID'],FamilyID=q['FamilyID'],PairID=q['PairID'],Variant=q['Variant'],Trials='100',BlockErrors='10',BitErrors='1',FalseAlarms='0',BLER='.1',BLERCILower='.05',BLERCIUpper='.15',FalseAlarmProbability='0',FalseAlarmCIUpper='.03',MeanSINR_dB='1',MeanEVMPercent='1',MeanPowerdBm='0',MeanRuntimeMs='1',MeanMemoryMB='1',Incomplete='false')
    elif fn=='pucch_impact_pairwise_effects.csv':r.update(BaselineValue='1',TreatmentValue='2',AbsoluteEffect='1',RelativeEffect='1',CILower='.5',CIUpper='1.5',PValue='.01',AdjustedPValue='.02',EffectSize='1')
    elif fn=='pucch_impact_rule_evaluation.csv':
     q=rules[i%len(rules)];r.update(RuleID=q['RuleID'],FamilyID=q['FamilyID'],Severity=q['Severity'],ObservedValue='1',Passed='true',EvidenceCSV='x.csv')
    elif fn=='pucch_impact_summary.csv':r.update(ExperimentsExpected='12',ExperimentsExecuted='12',HardRulesFailed='0',BlockedCount='0')
    rs.append(r)
   write(root/c['FileName'],cols,rs)
  audits=[]
  def sh(names):
   h=hashlib.sha256()
   for n in sorted(names):h.update(n.encode());h.update(digest(root/n).encode())
   return h.hexdigest()
  for c in ic:
   p=root/c['ImageFile'];im=Image.new('RGB',(1000,700),'white');d=ImageDraw.Draw(im);d.line((10,10,990,690),fill='black',width=5);im.save(p)
   audits.append({'RunID':'SYN','ImageFile':p.name,'SourceCSV':c['SourceCSV'],'SourceCSV_SHA256':sh(c['SourceCSV'].split('|')),'PNG_SHA256':digest(p),'Width':'1000','Height':'700','AxesCount':'1','SeriesCount':'2','FinitePointCount':'10','ActualTitle':c['ExpectedTitleToken'],'ActualXLabel':c['ExpectedXLabel'],'ActualYLabel':c['ExpectedYLabel'],'Status':'PASS'})
  write(root/'pucch_impact_image_semantic_audit.csv',pending[1],audits)
  ok=verify(root)
  ar=rows(root/'pucch_impact_image_semantic_audit.csv');ar[0]['PNG_SHA256']='0'*64;write(root/'pucch_impact_image_semantic_audit.csv',pending[1],ar)
  bad=verify(root);print(json.dumps({'valid_exit':ok,'corrupt_exit':bad},indent=2));return 0 if ok==0 and bad==2 else 3
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('root',nargs='?',type=Path);p.add_argument('--self-test',action='store_true');a=p.parse_args();sys.exit(selftest() if a.self_test else verify(a.root))
