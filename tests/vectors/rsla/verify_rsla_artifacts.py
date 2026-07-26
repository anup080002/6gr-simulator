#!/usr/bin/env python3
from __future__ import annotations
import csv, hashlib, json, sys
from pathlib import Path
from PIL import Image, ImageStat

def rows(p):
    with open(p,encoding='utf-8-sig',newline='') as f: return list(csv.DictReader(f))
def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for c in iter(lambda:f.read(1024*1024),b''): h.update(c)
    return h.hexdigest()
def truth(v): return str(v).strip().lower() in {'1','true','yes','pass'}
root=Path(sys.argv[1]); pack=Path(__file__).resolve().parent
fail=[]; checks=0
def ck(cond,msg):
    global checks
    checks+=1
    if not cond: fail.append(msg); print('FAIL',msg)
    else: print('PASS',msg)
contract=rows(pack/'desired_rsla_csv_contract.csv')
loaded={}
for c in contract:
    p=root/c['FileName']; ck(p.is_file(),'csv_exists:'+c['FileName'])
    if not p.is_file(): continue
    rr=rows(p); loaded[c['FileName']]=rr
    req=set(c['RequiredColumns'].split(';')); got=set(rr[0].keys()) if rr else set()
    ck(req.issubset(got),'csv_columns:'+c['FileName'])
    ck(len(rr)>=int(c['MinimumRows']),'csv_rows:'+c['FileName'])
    if rr and 'Status' in rr[0]: ck(all(str(x['Status']).upper()=='PASS' for x in rr),'csv_status:'+c['FileName'])
# Special semantic checks
if 'rsla_capability_resolution.csv' in loaded:
    ck(all(r['ExpectedSupported']==r['ActualSupported'] for r in loaded['rsla_capability_resolution.csv']),'capability_expected_actual')
if 'rsla_collision_resolution.csv' in loaded:
    ck(all(r['ExpectedDisposition']==r['ActualDisposition'] for r in loaded['rsla_collision_resolution.csv']),'collision_expected_actual')
if 'rsla_srs_scheduler_consumption.csv' in loaded:
    ck(all((not truth(r['Valid'])) or r['SelectedPrecoderSHA256']==r['AppliedPrecoderSHA256'] for r in loaded['rsla_srs_scheduler_consumption.csv']),'srs_selected_applied_digest')
if 'rsla_csi_bit_ownership.csv' in loaded:
    ck(all(r['DecodedBit']==r['ExpectedBit'] for r in loaded['rsla_csi_bit_ownership.csv']),'csi_bits_exact')
if 'rsla_ptrs_tracking.csv' in loaded:
    ck(all(float(r['EVMAfterPercent'])<=float(r['EVMBeforePercent'])+1e-9 for r in loaded['rsla_ptrs_tracking.csv']),'ptrs_evm_nonworsening')
if 'rsla_trs_tracking.csv' in loaded:
    ck(all(truth(r['CorrectionApplied']) for r in loaded['rsla_trs_tracking.csv']),'tracking_correction_applied')
if 'rsla_link_adaptation_decisions.csv' in loaded:
    bad={'CONFIGURED_SNR','CONFIGURED_CQI','CONFIGURED_MCS','LAB_DEFAULT','FALLBACK'}
    ck(all(r['DecisionSource'].upper() not in bad for r in loaded['rsla_link_adaptation_decisions.csv']),'measured_decision_source')
if 'rsla_cqi_mcs_calibration.csv' in loaded:
    ck(all(r['DatasetID'] and r['ProfileKey'] and r['DatasetSHA256'] and 'lab' not in r['DatasetID'].lower() for r in loaded['rsla_cqi_mcs_calibration.csv']),'calibration_provenance')
if 'rsla_effective_sinr_calibration.csv' in loaded:
    ck(all(r['DatasetID'] and r['DatasetSHA256'] and str(r['ParameterValue']) not in {'','1.5_fallback'} for r in loaded['rsla_effective_sinr_calibration.csv']),'effective_sinr_calibration')
if 'rsla_bootstrap_transition.csv' in loaded:
    ck(all(not (truth(r['BootstrapUsed']) and truth(r['TransitionedToMeasured'])) for r in loaded['rsla_bootstrap_transition.csv']),'bootstrap_measured_separation')
if 'rsla_olla_convergence.csv' in loaded:
    ck(all(truth(r['Converged']) for r in loaded['rsla_olla_convergence.csv']),'olla_converged')
if 'rsla_negative_tests.csv' in loaded:
    ck(all(r['ExpectedError']==r['ActualError'] and not truth(r['WaveformGenerated']) and not truth(r['SchedulerStateChanged']) and not truth(r['MeasurementStateChanged']) for r in loaded['rsla_negative_tests.csv']),'negative_fail_closed')
if 'rsla_test_summary.csv' in loaded:
    ck(all(int(float(r['Failed']))==0 and int(float(r['Skipped']))==0 and int(float(r['Blocked']))==0 and int(float(r['IncompletePoints']))==0 for r in loaded['rsla_test_summary.csv']),'mandatory_tests_complete')
# Images and semantic audit
audit={r['ImageFile']:r for r in loaded.get('rsla_image_semantic_audit.csv',[])}
for c in rows(pack/'desired_rsla_image_contract.csv'):
    p=root/c['ImageFile']; ck(p.is_file(),'png_exists:'+c['ImageFile'])
    if not p.is_file(): continue
    try:
        im=Image.open(p).convert('RGB'); w,h=im.size; stat=ImageStat.Stat(im)
        nonblank=max(stat.var)>0.1
    except Exception:
        w=h=0; nonblank=False
    ck(w>=int(c['MinimumWidth']) and h>=int(c['MinimumHeight']),'png_dimensions:'+c['ImageFile'])
    ck(nonblank,'png_nonblank:'+c['ImageFile'])
    a=audit.get(c['ImageFile']); ck(a is not None,'png_audit_row:'+c['ImageFile'])
    if a:
        src=root/c['SourceCSV']
        ck(a['SourceCSV']==c['SourceCSV'] and a['SourceCSVSHA256']==sha(src),'source_hash:'+c['ImageFile'])
        ck(a['PNGSHA256']==sha(p),'png_hash:'+c['ImageFile'])
        ck(int(a['Width'])==w and int(a['Height'])==h,'png_metadata:'+c['ImageFile'])
        ck(c['ExpectedTitle'].lower() in a['Title'].lower(),'png_title:'+c['ImageFile'])
        ck(int(a['AxesCount'])>=int(c['MinimumAxes']) and int(a['SeriesCount'])>=int(c['MinimumSeries']) and int(a['FinitePointCount'])>=int(c['MinimumFinitePoints']),'png_semantics:'+c['ImageFile'])
print(json.dumps({'Checks':checks,'Passed':checks-len(fail),'Failed':len(fail),'Failures':fail},indent=2))
sys.exit(0 if not fail else 2)
