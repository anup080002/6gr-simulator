#!/usr/bin/env python3
from __future__ import annotations
import csv,hashlib,json,sys
from pathlib import Path
from PIL import Image,ImageStat
root=Path(sys.argv[1]); pack=Path(__file__).resolve().parent
def rows(p):
    with open(p,encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def sha(p):
    h=hashlib.sha256();
    with open(p,'rb') as f:
        for c in iter(lambda:f.read(1024*1024),b''):h.update(c)
    return h.hexdigest()
def truth(v):return str(v).strip().lower() in {'1','true','yes','pass'}
fail=[];checks=0
def ck(c,m):
    global checks;checks+=1
    if c:print('PASS',m)
    else:print('FAIL',m);fail.append(m)
loaded={}
for c in rows(pack/'desired_rf_csv_contract.csv'):
    p=root/c['FileName'];ck(p.is_file(),'csv_exists:'+c['FileName'])
    if not p.is_file():continue
    rr=rows(p);loaded[c['FileName']]=rr; got=set(rr[0]) if rr else set()
    ck(set(c['RequiredColumns'].split(';')).issubset(got),'csv_columns:'+c['FileName']);ck(len(rr)>=int(c['MinimumRows']),'csv_rows:'+c['FileName'])
    if rr and 'Status' in rr[0]:ck(all(str(r['Status']).upper()=='PASS' for r in rr),'csv_status:'+c['FileName'])
if 'rf_profile_resolution.csv' in loaded:ck(all(r['ExpectedOutcome']==r['ActualOutcome'] for r in loaded['rf_profile_resolution.csv']),'profile_resolution')
if 'rf_reference_plane_power.csv' in loaded:ck(all(abs(float(r['Error_dB']))<=.05 for r in loaded['rf_reference_plane_power.csv']),'power_closure')
if 'rf_cfo_acquisition.csv' in loaded:ck(all(abs(float(r['Error_Hz']))<=max(1e-6,abs(float(r['TrueCFO_Hz']))*.001) and not truth(r['FalseLock']) for r in loaded['rf_cfo_acquisition.csv']),'cfo_acquisition')
if 'rf_sco_resampler.csv' in loaded:ck(all(abs(float(r['Error_samples']))<=.05 and float(r['AliasPower_dBc'])<=-60 for r in loaded['rf_sco_resampler.csv']),'sco_resampling')
if 'rf_dpd_validation.csv' in loaded:ck(all(float(r['EVMAfter_pct'])<=float(r['EVMBefore_pct']) and float(r['ACLRAfter_dB'])>=float(r['ACLRBefore_dB']) for r in loaded['rf_dpd_validation.csv']),'dpd_holdout')
if 'rf_ul_power_control.csv' in loaded:ck(all(abs(float(r['AppliedPower_dBm'])-float(r['MeasuredPower_dBm']))<=.05 for r in loaded['rf_ul_power_control.csv']),'power_control_waveform')
if 'rf_negative_tests.csv' in loaded:ck(all(r['ExpectedError']==r['ActualError'] and not truth(r['WaveformGenerated']) and not truth(r['StateMutation']) for r in loaded['rf_negative_tests.csv']),'negative_tests')
if 'rf_test_summary.csv' in loaded:ck(all(int(float(r['Failed']))==0 and int(float(r['Skipped']))==0 and int(float(r['Blocked']))==0 and int(float(r['IncompletePoints']))==0 for r in loaded['rf_test_summary.csv']),'mandatory_tests_complete')
audit={r['ImageFile']:r for r in loaded.get('rf_image_semantic_audit.csv',[])}
for c in rows(pack/'desired_rf_image_contract.csv'):
    p=root/c['ImageFile'];ck(p.is_file(),'png_exists:'+c['ImageFile'])
    if not p.is_file():continue
    try:im=Image.open(p).convert('RGB');w,h=im.size;nb=max(ImageStat.Stat(im).var)>0.1
    except Exception:w=h=0;nb=False
    ck(w>=int(c['MinimumWidth']) and h>=int(c['MinimumHeight']),'png_dimensions:'+c['ImageFile']);ck(nb,'png_nonblank:'+c['ImageFile'])
    a=audit.get(c['ImageFile']);ck(a is not None,'png_audit:'+c['ImageFile'])
    if a:
        ck(a['SourceCSV']==c['SourceCSV'] and a['SourceCSVSHA256']==sha(root/c['SourceCSV']),'source_hash:'+c['ImageFile']);ck(a['PNGSHA256']==sha(p),'png_hash:'+c['ImageFile']);ck(int(a['Width'])==w and int(a['Height'])==h,'png_metadata:'+c['ImageFile']);ck(c['ExpectedTitle'].lower() in a['Title'].lower(),'png_title:'+c['ImageFile']);ck(int(a['AxesCount'])>=int(c['MinimumAxes']) and int(a['SeriesCount'])>=int(c['MinimumSeries']) and int(a['FinitePointCount'])>=int(c['MinimumFinitePoints']),'png_semantics:'+c['ImageFile'])
print(json.dumps({'Checks':checks,'Passed':checks-len(fail),'Failed':len(fail),'Failures':fail},indent=2));sys.exit(0 if not fail else 2)
