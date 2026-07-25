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
 fail=[];parsed={};cc=contracts('desired_mimo_csv_contract.csv');ic=contracts('desired_mimo_image_contract.csv')
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
 # technical fail-closed checks
 for i,r in enumerate(parsed.get('mimo_run_manifest.csv',[]),2):
  if not truth(r.get('Strict')):fail.append(f'manifest_not_strict:{i}')
  for k in ['GitCommit','MATLABVersion','ToolboxVersion','SpecProfile','SeedList','VectorManifestSHA256']:
   if not r.get(k,'').strip():fail.append(f'manifest_missing_{k}:{i}')
 for i,r in enumerate(parsed.get('mimo_capability_resolution.csv',[]),2):
  if truth(r.get('ParametersMutated')):fail.append(f'capability_mutated:{i}')
  if truth(r.get('Supported'))!=truth(r.get('ExpectedSupported')):fail.append(f'capability_mismatch:{i}')
  if not truth(r.get('ExpectedSupported')) and not truth(r.get('PlanningRejected')):fail.append(f'unsupported_not_rejected:{i}')
 for i,r in enumerate(parsed.get('mimo_antenna_panel.csv',[]),2):
  if integer(r.get('IndependentMismatchCount'))!=0:fail.append(f'antenna_mismatch:{i}')
  for k in ['XLambda','YLambda','ZLambda','SteeringReal','SteeringImag']:
   if finite(r.get(k)) is None:fail.append(f'antenna_nonfinite_{k}:{i}')
 for i,r in enumerate(parsed.get('mimo_port_mapping.csv',[]),2):
  if not truth(r.get('Bijective')) or integer(r.get('IndependentMismatchCount'))!=0:fail.append(f'port_mapping:{i}')
 for i,r in enumerate(parsed.get('mimo_codebook_candidates.csv',[]),2):
  if truth(r.get('GenericDFTApproximationUsed')):fail.append(f'generic_dft:{i}')
  if len(r.get('MatrixSHA256',''))!=64:fail.append(f'codebook_hash:{i}')
  if finite(r.get('FrobeniusPower')) is None or abs(float(r['FrobeniusPower'])-1)>1e-6:fail.append(f'codebook_power:{i}')
  if finite(r.get('OrthogonalityError')) is None or float(r['OrthogonalityError'])>1e-6:fail.append(f'codebook_orthogonality:{i}')
 for i,r in enumerate(parsed.get('mimo_codebook_vector_results.csv',[]),2):
  if integer(r.get('IndependentMismatchCount'))!=0 or finite(r.get('AbsoluteError')) is None or float(r['AbsoluteError'])>1e-10:fail.append(f'codebook_vector:{i}')
  if abs(float(r['ExpectedReal'])-float(r['ActualReal']))>1e-10 or abs(float(r['ExpectedImag'])-float(r['ActualImag']))>1e-10:fail.append(f'codebook_value:{i}')
 for i,r in enumerate(parsed.get('mimo_csi_report_config.csv',[]),2):
  if not r.get('ConfigurationProvenance','').strip():fail.append(f'csi_config_provenance:{i}')
  if r.get('UCIChannel') not in {'PUCCH','PUSCH'}:fail.append(f'csi_uci_channel:{i}')
 for i,r in enumerate(parsed.get('mimo_csi_part1_part2.csv',[]),2):
  if integer(r.get('BitErrors'))!=0 or not truth(r.get('CRCPassed')) or not truth(r.get('SeparateEncoding')) or truth(r.get('CustomContainerUsed')):fail.append(f'csi_part:{i}')
  if integer(r.get('InformationBits')) is None or integer(r.get('DecodedBits'))!=integer(r.get('InformationBits')):fail.append(f'csi_length:{i}')
 for i,r in enumerate(parsed.get('mimo_csi_bit_ownership.csv',[]),2):
  if integer(r.get('OwnerCount'))!=1 or truth(r.get('Mismatch')) or r.get('Field')!=r.get('ExpectedOwner'):fail.append(f'csi_owner:{i}')
 for i,r in enumerate(parsed.get('mimo_ri_pmi_selection.csv',[]),2):
  if integer(r.get('SelectedRI'))!=integer(r.get('ExpectedRI')) or integer(r.get('SelectedPMI'))!=integer(r.get('ExpectedPMI')):fail.append(f'ri_pmi:{i}')
  if r.get('SelectedMatrixSHA256')!=r.get('ExpectedMatrixSHA256') or integer(r.get('IndependentMismatchCount'))!=0:fail.append(f'ri_pmi_hash:{i}')
  if truth(r.get('ConfiguredSNRUsed')) or truth(r.get('SVDThresholdUsed')):fail.append(f'ri_pmi_shortcut:{i}')
 for i,r in enumerate(parsed.get('mimo_cqi_li_cri_selection.csv',[]),2):
  if any(integer(r.get(a))!=integer(r.get(b)) for a,b in [('CQI','ExpectedCQI'),('LI','ExpectedLI'),('CRI','ExpectedCRI')]) or integer(r.get('IndependentMismatchCount'))!=0:fail.append(f'cqi_li_cri:{i}')
 for i,r in enumerate(parsed.get('mimo_measurement_state.csv',[]),2):
  if truth(r.get('ConfiguredOracleUsed')) or not truth(r.get('Valid')):fail.append(f'measurement_oracle_or_invalid:{i}')
  if integer(r.get('AgeSlots')) is None or integer(r.get('MaxAgeSlots')) is None or integer(r['AgeSlots'])>integer(r['MaxAgeSlots']):fail.append(f'measurement_age:{i}')
  if not r.get('MeasurementProvenance','').startswith('measured_'):fail.append(f'measurement_provenance:{i}')
 for i,r in enumerate(parsed.get('mimo_precoder_selection.csv',[]),2):
  if truth(r.get('ConfiguredOverrideUsed')) or truth(r.get('FallbackUsed')):fail.append(f'precoder_selection_shortcut:{i}')
  if len(r.get('MatrixSHA256',''))!=64 or integer(r.get('MatrixRows')) is None or integer(r.get('MatrixColumns'))!=integer(r.get('Rank')):fail.append(f'precoder_selection_matrix:{i}')
 for i,r in enumerate(parsed.get('mimo_precoder_application.csv',[]),2):
  if r.get('SelectedMatrixSHA256')!=r.get('AppliedMatrixSHA256') or truth(r.get('MatrixRegenerated')):fail.append(f'precoder_apply_digest:{i}')
  if r.get('Orientation')!='Nport_by_Nlayer':fail.append(f'precoder_orientation:{i}')
  if finite(r.get('PowerErrorDB')) is None or abs(float(r['PowerErrorDB']))>.05:fail.append(f'precoder_power:{i}')
 for i,r in enumerate(parsed.get('mimo_rank_port_trials.csv',[]),2):
  ranks=[integer(r.get(x)) for x in ['ConfiguredRank','SelectedRank','ScheduledRank','AppliedRank','DecodedRank']]
  if None in ranks or len(set(ranks))!=1 or truth(r.get('RankCollapsed')):fail.append(f'rank_collapse:{i}')
  if r.get('ConfiguredLogicalPorts')!=r.get('AppliedLogicalPorts') or truth(r.get('PortCollapsed')):fail.append(f'port_collapse:{i}')
  if not truth(r.get('TBCRC0')) or (integer(r.get('Codewords'))==2 and not truth(r.get('TBCRC1'))):fail.append(f'tb_crc:{i}')
 for i,r in enumerate(parsed.get('mimo_per_layer_metrics.csv',[]),2):
  if not truth(r.get('Finite')):fail.append(f'layer_nonfinite:{i}')
  for k in ['MeasuredSINRDB','EVMPercent','BER','BLER','PostEQNoiseVariance','ConditionNumber']:
   if finite(r.get(k)) is None:fail.append(f'layer_{k}:{i}')
 for i,r in enumerate(parsed.get('mimo_covariance_estimation.csv',[]),2):
  if not truth(r.get('Available')) or not truth(r.get('Valid')):fail.append(f'cov_unavailable:{i}')
  if integer(r.get('SampleCount')) is None or integer(r['SampleCount'])<integer(r.get('MinSamples')):fail.append(f'cov_samples:{i}')
  if integer(r.get('AgeSlots')) is None or integer(r['AgeSlots'])>integer(r.get('MaxAgeSlots')):fail.append(f'cov_age:{i}')
  if finite(r.get('HermitianError')) is None or float(r['HermitianError'])>1e-8 or finite(r.get('MinEigenvalue')) is None or float(r['MinEigenvalue'])<-1e-10:fail.append(f'cov_psd:{i}')
 for i,r in enumerate(parsed.get('mimo_receiver_comparison.csv',[]),2):
  if r.get('RequestedReceiver')!=r.get('AppliedReceiver') or truth(r.get('FallbackUsed')):fail.append(f'receiver_fallback:{i}')
  if not truth(r.get('TBCRC')) or finite(r.get('MeasuredSINRDB')) is None:fail.append(f'receiver_result:{i}')
 for i,r in enumerate(parsed.get('mimo_srs_ul_decisions.csv',[]),2):
  if truth(r.get('ConfiguredOverrideUsed')) or not truth(r.get('Authoritative')):fail.append(f'srs_authority:{i}')
  if len({r.get('SelectionMatrixSHA256'),r.get('SchedulerMatrixSHA256'),r.get('AppliedMatrixSHA256')})!=1:fail.append(f'srs_digest:{i}')
 for i,r in enumerate(parsed.get('mimo_mu_mimo_trials.csv',[]),2):
  if not truth(r.get('TBCRC')) or not truth(r.get('SchedulerAccounted')) or finite(r.get('MeasuredSINRDB')) is None:fail.append(f'mu_trial:{i}')
  if finite(r.get('MeasuredPowerDBM')) is None or abs(float(r['MeasuredPowerDBM'])-float(r['RequestedPowerDBM']))>.05:fail.append(f'mu_power:{i}')
 for i,r in enumerate(parsed.get('mimo_multitrp_trials.csv',[]),2):
  if not truth(r.get('TBCRC')) or not truth(r.get('ValidCoherence')):fail.append(f'trp_trial:{i}')
 for i,r in enumerate(parsed.get('mimo_hybrid_beamforming_trials.csv',[]),2):
  if integer(r.get('NStreams')) is None or integer(r['NStreams'])>integer(r.get('NRFChains')):fail.append(f'hybrid_rfchains:{i}')
  if finite(r.get('ConstantModulusError')) is None or float(r['ConstantModulusError'])>1e-8:fail.append(f'hybrid_modulus:{i}')
 for i,r in enumerate(parsed.get('mimo_beam_management_events.csv',[]),2):
  if truth(r.get('GeometryOracleUsed')):fail.append(f'beam_oracle:{i}')
  if not r.get('MeasuredResourceID','').strip():fail.append(f'beam_measurement:{i}')
 for i,r in enumerate(parsed.get('mimo_bler_curve.csv',[]),2):
  if truth(r.get('Incomplete')):fail.append(f'bler_incomplete:{i}')
  for k in ['Trials','BlockErrors','BLER','CILower','CIUpper','MeanGoodputMbps','MeanSINRDB']:
   if finite(r.get(k)) is None:fail.append(f'bler_{k}:{i}')
 for i,r in enumerate(parsed.get('mimo_negative_tests.csv',[]),2):
  if not truth(r.get('Passed')) or truth(r.get('WaveformGenerated')) or truth(r.get('StateChanged')) or truth(r.get('GrantCreated')):fail.append(f'negative:{i}')
  if r.get('ActualError')!=r.get('ExpectedError'):fail.append(f'negative_error:{i}')
 required={'antenna_array','port_mapping','typeI_2port','typeI_single_panel','typeI_multi_panel','typeII','csi_part1_part2','ri_pmi_objective','precoder_application','covariance','srs_tpmi','mu_mimo','multi_trp','hybrid','beam_state'}
 seen=set()
 for i,r in enumerate(parsed.get('mimo_independent_vector_results.csv',[]),2):
  seen.add(r.get('VectorFamily',''))
  if integer(r.get('MismatchCount'))!=0 or finite(r.get('MaxAbsoluteError')) is None:fail.append(f'oracle_mismatch:{i}')
  if any(x in r.get('OracleClass','').lower() for x in ['same_toolbox','self_consistency','same_implementation']):fail.append(f'nonindependent_oracle:{i}')
  if len(r.get('OracleArtifactSHA256',''))!=64:fail.append(f'oracle_hash:{i}')
 if required-seen:fail.append('missing_oracle_families:'+','.join(sorted(required-seen)))
 for i,r in enumerate(parsed.get('mimo_test_summary.csv',[]),2):
  if truth(r.get('Mandatory')) and (not truth(r.get('Executed')) or not truth(r.get('Passed')) or integer(r.get('Failed'))!=0 or integer(r.get('Skipped'))!=0 or integer(r.get('Blocked'))!=0):fail.append(f'mandatory_test:{i}')
 # Images and semantic audit.
 audit={r.get('ImageFile',''):r for r in parsed.get('mimo_image_semantic_audit.csv',[])}
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
 cc=contracts('desired_mimo_csv_contract.csv');ic=contracts('desired_mimo_image_contract.csv')
 oracle_fams=['antenna_array','port_mapping','typeI_2port','typeI_single_panel','typeI_multi_panel','typeII','csi_part1_part2','ri_pmi_objective','precoder_application','covariance','srs_tpmi','mu_mimo','multi_trp','hybrid','beam_state']
 with tempfile.TemporaryDirectory() as td:
  root=Path(td);pending=None
  for c in cc:
   cols=c['RequiredColumns'].split('|');fn=c['FileName']
   if fn=='mimo_image_semantic_audit.csv':pending=(c,cols);continue
   rs=[];n=max(1,int(c['MinRows']))
   for i in range(n):
    r={x:'1' for x in cols}
    for k in c['PrimaryKey'].split('|'):r[k]=f'{k}_{i}'
    if 'RunID' in r:r['RunID']='SYN'
    if 'Status' in r:r['Status']='PASS'
    if fn=='mimo_run_manifest.csv':r.update(GitCommit='abc',MATLABVersion='R2025b',ToolboxVersion='25.2',SpecProfile='rel18',SeedList='11|23',VectorManifestSHA256='a'*64,Strict='true')
    elif fn=='mimo_capability_resolution.csv':r.update(Supported='true',ExpectedSupported='true',ParametersMutated='false',PlanningRejected='false')
    elif fn=='mimo_antenna_panel.csv':r.update(XLambda='0',YLambda='0',ZLambda='0',SteeringReal='1',SteeringImag='0',IndependentMismatchCount='0')
    elif fn=='mimo_port_mapping.csv':r.update(Bijective='true',IndependentMismatchCount='0')
    elif fn=='mimo_codebook_candidates.csv':r.update(MatrixSHA256='a'*64,FrobeniusPower='1',OrthogonalityError='0',GenericDFTApproximationUsed='false')
    elif fn=='mimo_codebook_vector_results.csv':r.update(ExpectedReal='1',ExpectedImag='0',ActualReal='1',ActualImag='0',AbsoluteError='0',MatrixSHA256='a'*64,IndependentMismatchCount='0')
    elif fn=='mimo_csi_report_config.csv':r.update(UCIChannel='PUCCH',ConfigurationProvenance='rrc_decoded_context')
    elif fn=='mimo_csi_part1_part2.csv':r.update(InformationBits='10',EncodedBits='20',DecodedBits='10',BitErrors='0',CRCPassed='true',SeparateEncoding='true',CustomContainerUsed='false')
    elif fn=='mimo_csi_bit_ownership.csv':r.update(Field='RI',ExpectedOwner='RI',OwnerCount='1',Mismatch='false')
    elif fn=='mimo_ri_pmi_selection.csv':r.update(CandidateRank='1',CandidatePMI='0',SelectedRI='1',SelectedPMI='0',ExpectedRI='1',ExpectedPMI='0',SelectedMatrixSHA256='a'*64,ExpectedMatrixSHA256='a'*64,ConfiguredSNRUsed='false',SVDThresholdUsed='false',IndependentMismatchCount='0')
    elif fn=='mimo_cqi_li_cri_selection.csv':r.update(CQI='4',ExpectedCQI='4',LI='0',ExpectedLI='0',CRI='0',ExpectedCRI='0',IndependentMismatchCount='0')
    elif fn=='mimo_measurement_state.csv':r.update(AgeSlots='0',MaxAgeSlots='10',MeasuredSINRDB='10',NoiseVariance='.1',ChannelEstimateSHA256='a'*64,MeasurementProvenance='measured_csirs_runtime',ConfiguredOracleUsed='false',Valid='true')
    elif fn=='mimo_precoder_selection.csv':r.update(Rank='1',MatrixSHA256='a'*64,MatrixRows='4',MatrixColumns='1',ConfiguredOverrideUsed='false',FallbackUsed='false')
    elif fn=='mimo_precoder_application.csv':r.update(Rank='1',SelectedMatrixSHA256='a'*64,AppliedMatrixSHA256='a'*64,MatrixRegenerated='false',RequestedPowerDBM='0',MeasuredPowerDBM='0',PowerErrorDB='0',Orientation='Nport_by_Nlayer')
    elif fn=='mimo_rank_port_trials.csv':r.update(ConfiguredRank='1',SelectedRank='1',ScheduledRank='1',AppliedRank='1',DecodedRank='1',ConfiguredLogicalPorts='3000',AppliedLogicalPorts='3000',RankCollapsed='false',PortCollapsed='false',Codewords='1',TBCRC0='true',TBCRC1='true')
    elif fn=='mimo_per_layer_metrics.csv':r.update(MeasuredSINRDB='10',EVMPercent='1',BER='0',BLER='0',PostEQNoiseVariance='.1',ConditionNumber='1',Finite='true')
    elif fn=='mimo_covariance_estimation.csv':r.update(SampleCount='32',MinSamples='8',AgeSlots='0',MaxAgeSlots='10',HermitianError='0',MinEigenvalue='1',ConditionNumber='1',ShrinkageFactor='.1',HeldOutError='.1',Available='true',Valid='true')
    elif fn=='mimo_receiver_comparison.csv':r.update(Receiver='IRC',RequestedReceiver='IRC',AppliedReceiver='IRC',FallbackUsed='false',MeasuredSINRDB='10',EVMPercent='1',BLER='0',TBCRC='true')
    elif fn=='mimo_srs_ul_decisions.csv':r.update(AgeSlots='0',SelectionMatrixSHA256='a'*64,SchedulerMatrixSHA256='a'*64,AppliedMatrixSHA256='a'*64,ConfiguredOverrideUsed='false',Authoritative='true')
    elif fn=='mimo_mu_mimo_trials.csv':r.update(NumUE='2',RequestedPowerDBM='0',MeasuredPowerDBM='0',MeasuredSINRDB='10',TBCRC='true',BLER='0',SchedulerAccounted='true')
    elif fn=='mimo_multitrp_trials.csv':r.update(TimingOffsetSamples='0',PhaseErrorDeg='0',PowerDBM='0',PrecoderSHA256='a'*64,ChannelSHA256='b'*64,CombinedSINRDB='10',TBCRC='true',ValidCoherence='true')
    elif fn=='mimo_hybrid_beamforming_trials.csv':r.update(Nant='64',NRFChains='4',NStreams='2',ConstantModulusError='0',MeasuredPowerDBM='0',EVMPercent='1',BLER='0')
    elif fn=='mimo_beam_management_events.csv':r.update(MeasuredResourceID='CSI-RS-1',MeasuredRSRPDBM='-80',MeasuredSINRDB='10',GeometryOracleUsed='false')
    elif fn=='mimo_bler_curve.csv':r.update(Trials='1000',BlockErrors='100',BLER='.1',CILower='.08',CIUpper='.12',MeanGoodputMbps='100',MeanSINRDB='10',Incomplete='false',StopReason='criteria_met')
    elif fn=='mimo_negative_tests.csv':r.update(FaultType='bad',ExpectedError='sixgr:mimo:X',ActualError='sixgr:mimo:X',WaveformGenerated='false',StateChanged='false',GrantCreated='false',Passed='true')
    elif fn=='mimo_independent_vector_results.csv':r.update(VectorFamily=oracle_fams[i%len(oracle_fams)],OracleClass='pure_spec_math',OracleImplementation='python_independent',OracleVersion='1',OracleArtifactSHA256='a'*64,Cases='1',MismatchCount='0',MaxAbsoluteError='0')
    elif fn=='mimo_test_summary.csv':r.update(Mandatory='true',Executed='true',Passed='true',Total='1',Failed='0',Skipped='0',Blocked='0',DurationSeconds='1')
    rs.append(r)
   write(root/fn,cols,rs)
  audits=[]
  for c in ic:
   p=root/c['ImageFile'];im=Image.new('RGB',(1000,700),'white');d=ImageDraw.Draw(im);d.line((10,10,990,690),fill='black',width=5);d.line((10,690,990,10),fill='black',width=3);im.save(p)
   audits.append({'RunID':'SYN','ImageFile':p.name,'SourceCSV':c['SourceCSV'],'SourceCSV_SHA256':source_hash(root,c['SourceCSV'].split('|')),'PNG_SHA256':digest(p),'Width':'1000','Height':'700','AxesCount':'1','SeriesCount':str(max(2,int(c['MinSeriesCount']))),'FinitePointCount':str(max(20,int(c['MinFinitePointCount']))),'ActualTitle':c['ExpectedTitleToken'],'ActualXLabel':c['ExpectedXLabel'],'ActualYLabel':c['ExpectedYLabel'],'Status':'PASS'})
  write(root/'mimo_image_semantic_audit.csv',pending[1],audits)
  ok=verify(root)
  _,ar,_=readcsv(root/'mimo_image_semantic_audit.csv');ar[0]['PNG_SHA256']='0'*64;write(root/'mimo_image_semantic_audit.csv',pending[1],ar)
  bad=verify(root);print(json.dumps({'valid_exit':ok,'corrupt_exit':bad},indent=2));return 0 if ok==0 and bad==2 else 3
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('root',nargs='?',type=Path);p.add_argument('--self-test',action='store_true');a=p.parse_args();sys.exit(selftest() if a.self_test else verify(a.root))
