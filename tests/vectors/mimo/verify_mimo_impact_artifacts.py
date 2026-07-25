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
def contract(name):
 with (HERE/name).open(newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))
def source_hash(root,names):
 h=hashlib.sha256()
 for n in sorted(filter(None,names)):
  p=root/n
  if not p.exists():return ''
  h.update(n.encode());h.update(digest(p).encode())
 return h.hexdigest()

def verify(root:Path):
 fail=[];parsed={};cc=contract('desired_mimo_impact_csv_contract.csv');ic=contract('desired_mimo_impact_image_contract.csv');exp=contract('mimo_impact_experiment_matrix.csv');rules=contract('mimo_impact_acceptance_rules.csv')
 expmap={r['ExperimentID']:r for r in exp};expids=set(expmap);ruleids={r['RuleID'] for r in rules};rulemap={r['RuleID']:r for r in rules}
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
   if r.get('Status','PASS').upper()!='PASS':fail.append(p.name+f':nonpass:{i}')
 raw=parsed.get('mimo_impact_raw_trials.csv',[]);ops=parsed.get('mimo_impact_operating_points.csv',[])
 rawids={r.get('ExperimentID') for r in raw};opids={r.get('ExperimentID') for r in ops}
 if expids-rawids:fail.append('missing_raw_experiments:'+str(len(expids-rawids)))
 if expids-opids:fail.append('missing_operating_points:'+str(len(expids-opids)))
 # Check experiment metadata and pair identities.
 for i,r in enumerate(raw,2):
  q=expmap.get(r.get('ExperimentID'))
  if not q:fail.append(f'unknown_experiment:{i}');continue
  for k,actual in [('FamilyID',r.get('FamilyID')),('PairID',r.get('PairID')),('Variant',r.get('Variant')),('FactorName',r.get('FactorName')),('FactorValue',r.get('FactorValue')),('Seed',r.get('Seed')),('PayloadID',r.get('PayloadID')),('ChannelRealizationID',r.get('ChannelRealizationID')),('NoiseRealizationID',r.get('NoiseRealizationID'))]:
   if str(q[k])!=str(actual):fail.append(f'experiment_metadata_{k}:{i}')
  for k in ['SNRDB','MeasuredSINRDB','EVMPercent','GoodputMbps','RuntimeMs','MemoryMB']:
   if finite(r.get(k)) is None:fail.append(f'raw_nonfinite_{k}:{i}')
 # Every paired baseline/treatment must share all controlled identities.
 for pid in {r['PairID'] for r in exp}:
  q=[r for r in raw if r.get('PairID')==pid]
  if {r.get('Variant') for r in q}!={'baseline','treatment'}:fail.append('pair_variants:'+pid);continue
  for key in ['Seed','PayloadID','ChannelRealizationID','NoiseRealizationID','SNRDB']:
   if len({r.get(key) for r in q})!=1:fail.append('pair_control_'+key+':'+pid)
 for i,r in enumerate(ops,2):
  if truth(r.get('Incomplete')):fail.append(f'op_incomplete:{i}')
  for k in ['Trials','BlockErrors','BitErrors','BLER','BLERCILower','BLERCIUpper','MeanSINRDB','MeanEVMPercent','MeanGoodputMbps','MeanRuntimeMs','MeanMemoryMB']:
   if finite(r.get(k)) is None:fail.append(f'op_nonfinite_{k}:{i}')
  if finite(r.get('BLER')) is not None and not 0<=float(r['BLER'])<=1:fail.append(f'op_bler_range:{i}')
 effects=parsed.get('mimo_impact_pairwise_effects.csv',[])
 for i,r in enumerate(effects,2):
  vals={k:finite(r.get(k)) for k in ['BaselineValue','TreatmentValue','AbsoluteEffect','CILower','CIUpper','PValue','AdjustedPValue','EffectSize','PracticalMargin']}
  if any(v is None for v in vals.values()):fail.append(f'effect_nonfinite:{i}');continue
  if abs((vals['TreatmentValue']-vals['BaselineValue'])-vals['AbsoluteEffect'])>1e-9:fail.append(f'effect_sign:{i}')
  if vals['AdjustedPValue']+1e-12<vals['PValue']:fail.append(f'holm:{i}')
  if r.get('Conclusion') not in {'beneficial','harmful','equivalent','inconclusive','correctness_gate'}:fail.append(f'effect_conclusion:{i}')
 evals=parsed.get('mimo_impact_rule_evaluation.csv',[])
 if ruleids-{r.get('RuleID') for r in evals}:fail.append('missing_rules:'+str(len(ruleids-{r.get('RuleID') for r in evals})))
 for i,r in enumerate(evals,2):
  q=rulemap.get(r.get('RuleID'))
  if not q:fail.append(f'unknown_rule:{i}');continue
  if q['Severity']=='HARD' and not truth(r.get('Passed')):fail.append(f'hard_rule:{i}')
  if finite(r.get('ObservedValue')) is None:fail.append(f'rule_nonfinite:{i}')
 # Domain-specific impact outputs.
 for i,r in enumerate(parsed.get('mimo_impact_codebook_ri_pmi.csv',[]),2):
  if integer(r.get('SelectedRI'))!=integer(r.get('ExpectedRI')) or integer(r.get('SelectedPMI'))!=integer(r.get('ExpectedPMI')):fail.append(f'impact_ri_pmi:{i}')
  if finite(r.get('PMIAccuracy')) is None:fail.append(f'impact_pmi_acc:{i}')
 for i,r in enumerate(parsed.get('mimo_impact_csi_feedback.csv',[]),2):
  for k in ['Part1Bits','Part2Bits','OmittedPart2Bits','ReportAgeSlots','CQIError','PMIError','GoodputMbps']:
   if finite(r.get(k)) is None:fail.append(f'impact_csi_{k}:{i}')
 for i,r in enumerate(parsed.get('mimo_impact_high_rank.csv',[]),2):
  if truth(r.get('RankCollapsed')):fail.append(f'impact_rank_collapse:{i}')
  for k in ['MeasuredSINRDB','EVMPercent','BLER','GoodputMbps']:
   if finite(r.get(k)) is None:fail.append(f'impact_rank_{k}:{i}')
 for i,r in enumerate(parsed.get('mimo_impact_covariance_receiver.csv',[]),2):
  if truth(r.get('FallbackUsed')):fail.append(f'impact_receiver_fallback:{i}')
  if finite(r.get('MinEigenvalue')) is None or float(r['MinEigenvalue'])<-1e-10:fail.append(f'impact_cov_psd:{i}')
 for i,r in enumerate(parsed.get('mimo_impact_srs_ul.csv',[]),2):
  if r.get('SelectedTPMI')!=r.get('AppliedTPMI'):fail.append(f'impact_srs_apply:{i}')
 for i,r in enumerate(parsed.get('mimo_impact_mu_mimo.csv',[]),2):
  for k in ['MeasuredSINRDB','BLER','GoodputMbps','Fairness']:
   if finite(r.get(k)) is None:fail.append(f'impact_mu_{k}:{i}')
 for i,r in enumerate(parsed.get('mimo_impact_multitrp.csv',[]),2):
  for k in ['TimingMismatchFractionCP','PhaseMismatchDeg','PowerDeltaDB','CombinedSINRDB','BLER','CoherentGainDB']:
   if finite(r.get(k)) is None:fail.append(f'impact_trp_{k}:{i}')
 for i,r in enumerate(parsed.get('mimo_impact_hybrid.csv',[]),2):
  if integer(r.get('NStreams')) is None or integer(r['NStreams'])>integer(r.get('NRFChains')):fail.append(f'impact_hybrid_rf:{i}')
 for i,r in enumerate(parsed.get('mimo_impact_beam_management.csv',[]),2):
  for k in ['MobilityKMH','ReportDelaySlots','BeamSwitches','WrongBeamSlots','OutageProbability','RecoveryLatencySlots','GoodputMbps']:
   if finite(r.get(k)) is None:fail.append(f'impact_beam_{k}:{i}')
 # Summary: 12 experiments and six complete pairs per family; no hard failures/blocks.
 summaries=parsed.get('mimo_impact_summary.csv',[]);fids={r['FamilyID'] for r in contract('mimo_impact_analysis_families.csv')}
 if fids-{r.get('FamilyID') for r in summaries}:fail.append('missing_family_summaries')
 for i,r in enumerate(summaries,2):
  if integer(r.get('ExperimentsExpected'))!=12 or integer(r.get('ExperimentsExecuted'))!=12 or integer(r.get('PairsExpected'))!=6 or integer(r.get('PairsComplete'))!=6:fail.append(f'summary_counts:{i}')
  if integer(r.get('HardRulesFailed'))!=0 or integer(r.get('BlockedCount'))!=0:fail.append(f'summary_fail:{i}')
 # Images.
 audit={r.get('ImageFile',''):r for r in parsed.get('mimo_impact_image_semantic_audit.csv',[])}
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
  if integer(a.get('AxesCount')) is None or integer(a['AxesCount'])<int(c['MinAxesCount']):fail.append('axes:'+name)
  if integer(a.get('SeriesCount')) is None or integer(a['SeriesCount'])<int(c['MinSeriesCount']):fail.append('series:'+name)
  if integer(a.get('FinitePointCount')) is None or integer(a['FinitePointCount'])<int(c['MinFinitePointCount']):fail.append('points:'+name)
  if c['ExpectedTitleToken'].lower() not in a.get('ActualTitle','').lower():fail.append('title:'+name)
  if a.get('ActualXLabel')!=c['ExpectedXLabel'] or a.get('ActualYLabel')!=c['ExpectedYLabel']:fail.append('labels:'+name)
 print(json.dumps({'experiments_expected':len(expids),'rules_expected':len(ruleids),'required_csvs':len(cc),'required_pngs':len(ic),'failures':fail},indent=2))
 return 0 if not fail else 2

def write(p,cols,rs):
 with p.open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,fieldnames=cols);w.writeheader();w.writerows(rs)
def selftest():
 cc=contract('desired_mimo_impact_csv_contract.csv');ic=contract('desired_mimo_impact_image_contract.csv');exp=contract('mimo_impact_experiment_matrix.csv');rules=contract('mimo_impact_acceptance_rules.csv');families=contract('mimo_impact_analysis_families.csv')
 with tempfile.TemporaryDirectory() as td:
  root=Path(td);pending=None
  for c in cc:
   cols=c['RequiredColumns'].split('|');fn=c['FileName']
   if fn=='mimo_impact_image_semantic_audit.csv':pending=(c,cols);continue
   rs=[];n=max(1,int(c['MinRows']))
   for i in range(n):
    r={x:'1' for x in cols}
    for k in c['PrimaryKey'].split('|'):r[k]=f'{k}_{i}'
    if 'RunID' in r:r['RunID']='SYN'
    if 'Status' in r:r['Status']='PASS'
    if fn=='mimo_impact_run_manifest.csv':r.update(GitCommit='abc',MATLABVersion='R2025b',ToolboxVersion='25.2',SeedList='11|23',ExperimentMatrixSHA256='a'*64,ConfidenceLevel='.95')
    elif fn=='mimo_impact_raw_trials.csv':
     q=exp[i%len(exp)];r.update(ExperimentID=q['ExperimentID'],FamilyID=q['FamilyID'],PairID=q['PairID'],Variant=q['Variant'],FactorName=q['FactorName'],FactorValue=q['FactorValue'],Seed=q['Seed'],TrialIndex='0',PayloadID=q['PayloadID'],ChannelRealizationID=q['ChannelRealizationID'],NoiseRealizationID=q['NoiseRealizationID'],Profile=q['Profile'],Channel=q['Channel'],SNRDB=q['SNR_dB'],BlockError='0',BitErrors='0',RI='1',PMI='0',MeasuredSINRDB='10',EVMPercent='1',GoodputMbps='100',RuntimeMs='1',MemoryMB='1')
    elif fn=='mimo_impact_operating_points.csv':
     q=exp[i%len(exp)];r.update(ExperimentID=q['ExperimentID'],FamilyID=q['FamilyID'],PairID=q['PairID'],Variant=q['Variant'],Trials='1000',BlockErrors='100',BitErrors='10',BLER='.1',BLERCILower='.08',BLERCIUpper='.12',MeanSINRDB='10',MeanEVMPercent='1',MeanGoodputMbps='100',MeanRuntimeMs='1',MeanMemoryMB='1',Incomplete='false',StopReason='criteria_met')
    elif fn=='mimo_impact_pairwise_effects.csv':r.update(FamilyID=families[i%len(families)]['FamilyID'],PairID=f'PAIR_{i}',Metric='goodput',BaselineValue='1',TreatmentValue='2',AbsoluteEffect='1',RelativeEffect='1',CILower='.5',CIUpper='1.5',PValue='.01',AdjustedPValue='.02',EffectSize='1',PracticalMargin='.1',Conclusion='beneficial')
    elif fn=='mimo_impact_rule_evaluation.csv':
     q=rules[i%len(rules)];r.update(RuleID=q['RuleID'],FamilyID=q['FamilyID'],Severity=q['Severity'],Metric=q['Metric'],ObservedValue='1',Threshold='0',Passed='true',EvidenceCSV='x.csv')
    elif fn=='mimo_impact_codebook_ri_pmi.csv':r.update(SelectedRI='1',ExpectedRI='1',SelectedPMI='0',ExpectedPMI='0',PMIAccuracy='1',FeedbackBits='10')
    elif fn=='mimo_impact_csi_feedback.csv':r.update(Part1Bits='10',Part2Bits='5',OmittedPart2Bits='0',ReportAgeSlots='0',CQIError='0',PMIError='0',GoodputMbps='100')
    elif fn=='mimo_impact_high_rank.csv':r.update(Rank='4',Layer='1',MeasuredSINRDB='10',EVMPercent='1',BLER='.1',GoodputMbps='100',RankCollapsed='false')
    elif fn=='mimo_impact_covariance_receiver.csv':r.update(Receiver='IRC',Samples='32',AgeSlots='0',ConditionNumber='2',MinEigenvalue='1',ShrinkageFactor='.1',MeasuredSINRDB='10',BLER='.1',FallbackUsed='false')
    elif fn=='mimo_impact_srs_ul.csv':r.update(SRSAgeSlots='0',SoundedBandwidthRB='100',SelectedRI='2',SelectedTPMI='3',AppliedTPMI='3',TPMIAccuracy='1',MeasuredSINRDB='10',BLER='.1')
    elif fn=='mimo_impact_mu_mimo.csv':r.update(NumUE='2',AngularSeparationDeg='45',PowerDeltaDB='0',MeasuredSINRDB='10',BLER='.1',GoodputMbps='100',Fairness='.9')
    elif fn=='mimo_impact_multitrp.csv':r.update(Mode='CJT',TimingMismatchFractionCP='0',PhaseMismatchDeg='0',PowerDeltaDB='0',CombinedSINRDB='13',BLER='.05',CoherentGainDB='3')
    elif fn=='mimo_impact_hybrid.csv':r.update(Nant='64',NRFChains='4',NStreams='2',PhaseBits='4',BandwidthMHz='400',SquintLossDB='1',ArrayGainDB='18',EVMPercent='2',BLER='.1')
    elif fn=='mimo_impact_beam_management.csv':r.update(MobilityKMH='60',Blockage='false',ReportDelaySlots='2',BeamSwitches='1',WrongBeamSlots='0',OutageProbability='.01',RecoveryLatencySlots='4',GoodputMbps='100')
    elif fn=='mimo_impact_summary.csv':r.update(FamilyID=families[i%len(families)]['FamilyID'],ExperimentsExpected='12',ExperimentsExecuted='12',PairsExpected='6',PairsComplete='6',HardRulesFailed='0',StatisticalRulesInconclusive='0',BlockedCount='0')
    rs.append(r)
   write(root/fn,cols,rs)
  audits=[]
  for c in ic:
   p=root/c['ImageFile'];im=Image.new('RGB',(1000,700),'white');d=ImageDraw.Draw(im);d.line((10,10,990,690),fill='black',width=5);d.line((10,690,990,10),fill='black',width=3);im.save(p)
   audits.append({'RunID':'SYN','ImageFile':p.name,'SourceCSV':c['SourceCSV'],'SourceCSV_SHA256':source_hash(root,c['SourceCSV'].split('|')),'PNG_SHA256':digest(p),'Width':'1000','Height':'700','AxesCount':'1','SeriesCount':'2','FinitePointCount':'20','ActualTitle':c['ExpectedTitleToken'],'ActualXLabel':c['ExpectedXLabel'],'ActualYLabel':c['ExpectedYLabel'],'Status':'PASS'})
  write(root/'mimo_impact_image_semantic_audit.csv',pending[1],audits)
  ok=verify(root)
  _,ar,_=readcsv(root/'mimo_impact_image_semantic_audit.csv');ar[0]['PNG_SHA256']='0'*64;write(root/'mimo_impact_image_semantic_audit.csv',pending[1],ar)
  bad=verify(root);print(json.dumps({'valid_exit':ok,'corrupt_exit':bad},indent=2));return 0 if ok==0 and bad==2 else 3
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('root',nargs='?',type=Path);p.add_argument('--self-test',action='store_true');a=p.parse_args();sys.exit(selftest() if a.self_test else verify(a.root))
