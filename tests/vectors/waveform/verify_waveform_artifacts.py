#!/usr/bin/env python3
from __future__ import annotations
import csv,hashlib,json,sys
from pathlib import Path
from PIL import Image,ImageStat
root=Path(sys.argv[1]);pack=Path(__file__).resolve().parent

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
    if c: print('PASS',m)
    else: print('FAIL',m);fail.append(m)
loaded={}
for c in rows(pack/'desired_waveform_csv_contract.csv'):
    p=root/c['FileName'];ck(p.is_file(),'csv_exists:'+c['FileName'])
    if not p.is_file():continue
    rr=rows(p);loaded[c['FileName']]=rr; got=set(rr[0]) if rr else set()
    ck(set(c['RequiredColumns'].split(';')).issubset(got),'csv_columns:'+c['FileName']);ck(len(rr)>=int(c['MinimumRows']),'csv_rows:'+c['FileName'])
    if rr and 'Status' in rr[0]:ck(all(str(r['Status']).upper()=='PASS' for r in rr),'csv_status:'+c['FileName'])
if 'waveform_profile_resolution.csv' in loaded:ck(all(r['ExpectedOutcome']==r['ActualOutcome'] for r in loaded['waveform_profile_resolution.csv']),'profile_resolution')
if 'waveform_power_ledger.csv' in loaded:ck(all(abs(float(r['Error_dB']))<=.01 for r in loaded['waveform_power_ledger.csv']),'power_closure')
if 'waveform_parseval.csv' in loaded:ck(all(abs(float(r['RelativeError']))<=1e-10 for r in loaded['waveform_parseval.csv']),'parseval')
if 'waveform_ofdm_roundtrip.csv' in loaded:ck(all(float(r['NMSE'])<=1e-10 and float(r['EVM_pct'])<=1e-4 and int(float(r['BitErrors']))==0 for r in loaded['waveform_ofdm_roundtrip.csv']),'ofdm_roundtrip')
if 'waveform_stream_continuity.csv' in loaded:ck(all(int(float(r['SampleCountExpected']))==int(float(r['SampleCountActual'])) and float(r['NMSE'])<=1e-12 for r in loaded['waveform_stream_continuity.csv']),'stream_continuity')
if 'waveform_transform_precoding.csv' in loaded:ck(all(abs(float(r['InputEnergy'])-float(r['OutputEnergy']))<=1e-10*max(1,abs(float(r['InputEnergy']))) and float(r['RoundTripNMSE'])<=1e-10 for r in loaded['waveform_transform_precoding.csv']),'transform_precoding')
if 'waveform_spectral_metrics.csv' in loaded:ck(all(abs(float(r['Error_dB']))<=.01 for r in loaded['waveform_spectral_metrics.csv']),'spectral_power')
if 'waveform_negative_tests.csv' in loaded:ck(all(r['ExpectedError']==r['ActualError'] and not truth(r['WaveformGenerated']) and not truth(r['StateMutation']) for r in loaded['waveform_negative_tests.csv']),'negative_tests')
if 'waveform_test_summary.csv' in loaded:ck(all(int(float(r['Failed']))==0 and int(float(r['Skipped']))==0 and int(float(r['Blocked']))==0 and int(float(r['IncompletePoints']))==0 for r in loaded['waveform_test_summary.csv']),'tests_complete')
audit={r['ImageFile']:r for r in loaded.get('waveform_image_semantic_audit.csv',[])}
for c in rows(pack/'desired_waveform_image_contract.csv'):
    p=root/c['ImageFile'];ck(p.is_file(),'png_exists:'+c['ImageFile'])
    if not p.is_file():continue
    try: im=Image.open(p).convert('RGB');w,h=im.size;nb=max(ImageStat.Stat(im).var)>0.1
    except Exception:w=h=0;nb=False
    ck(w>=int(c['MinimumWidth']) and h>=int(c['MinimumHeight']),'png_dimensions:'+c['ImageFile']);ck(nb,'png_nonblank:'+c['ImageFile'])
    a=audit.get(c['ImageFile']);ck(a is not None,'png_audit:'+c['ImageFile'])
    if a:
        ck(a['SourceCSV']==c['SourceCSV'] and a['SourceCSVSHA256']==sha(root/c['SourceCSV']),'source_hash:'+c['ImageFile']);ck(a['PNGSHA256']==sha(p),'png_hash:'+c['ImageFile']);ck(int(a['Width'])==w and int(a['Height'])==h,'png_metadata:'+c['ImageFile']);ck(c['ExpectedTitle'].lower() in a['Title'].lower(),'png_title:'+c['ImageFile']);ck(int(a['AxesCount'])>=int(c['MinimumAxes']) and int(a['SeriesCount'])>=int(c['MinimumSeries']) and int(a['FinitePointCount'])>=int(c['MinimumFinitePoints']),'png_semantics:'+c['ImageFile'])
print(json.dumps({'Checks':checks,'Passed':checks-len(fail),'Failed':len(fail),'Failures':fail},indent=2));sys.exit(0 if not fail else 2)
