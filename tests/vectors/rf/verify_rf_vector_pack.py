#!/usr/bin/env python3
from __future__ import annotations
import csv, hashlib, json, math, sys
from pathlib import Path
root=Path(sys.argv[1] if len(sys.argv)>1 else Path(__file__).resolve().parent)
def rows(name):
    with open(root/name,encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def sha(p):
    h=hashlib.sha256();
    with open(p,'rb') as f:
        for c in iter(lambda:f.read(1024*1024),b''):h.update(c)
    return h.hexdigest()
fail=[]; checks=0
def ck(c,m):
    global checks; checks+=1
    if c: print('PASS',m)
    else: print('FAIL',m); fail.append(m)
manifest=json.loads((root/'independent_vector_manifest.json').read_text())
for e in manifest['Files']:
    p=root/e['File']; ck(p.is_file(),'manifest_exists:'+e['File'])
    if p.is_file():
        ck(sha(p)==e['SHA256'],'manifest_hash:'+e['File'])
        rr=rows(e['File']); ck(len(rr)==e['Rows'],'manifest_rows:'+e['File'])
ck(len(rows('rf_capability_profile_matrix.csv'))==210,'capability_rows')
ck(len(rows('rf_impact_analysis_families.csv'))==64,'impact_families')
ck(len(rows('rf_impact_experiment_matrix.csv'))==768,'impact_experiments')
ck(len(rows('rf_impact_acceptance_rules.csv'))==96,'impact_rules')
# CFO exact
for r,e in zip(rows('rf_cfo_tracking_test_vectors.csv'),rows('expected_rf_cfo_analytical.csv')):
    fs=float(r['SampleRate_Hz']); cfo=float(r['CFO_Hz']); n=int(r['SampleCount']); p0=float(r['InitialPhase_rad'])
    ck(abs((p0+2*math.pi*cfo*(n-1)/fs)-float(e['ExpectedFinalPhase_rad']))<1e-9,'cfo:'+r['CaseID'])
# IQ exact
for r,e in zip(rows('rf_iq_dc_test_vectors.csv'),rows('expected_rf_iq_analytical.csv')):
    g=10**(float(r['GainImbalance_dB'])/20); ph=math.radians(float(r['PhaseImbalance_deg']))
    a=.5*(1+g*complex(math.cos(-ph),math.sin(-ph))); b=.5*(1-g*complex(math.cos(ph),math.sin(ph)))
    ck(abs(a.real-float(e['AlphaReal']))<1e-10 and abs(b.real-float(e['BetaReal']))<1e-10,'iq:'+r['CaseID'])
# Friis
for r,e in zip(rows('rf_noise_figure_test_vectors.csv'),rows('expected_rf_noise_figure_analytical.csv')):
    G1=10**(float(r['Stage1Gain_dB'])/10); F1=10**(float(r['Stage1NF_dB'])/10); F2=10**(float(r['Stage2NF_dB'])/10)
    nf=10*math.log10(F1+(F2-1)/G1); ck(abs(nf-float(e['ExpectedCascadeNF_dB']))<1e-9,'nf:'+r['CaseID'])
# power control includes 2^mu term
for r,e in zip(rows('rf_ul_power_control_test_vectors.csv'),rows('expected_rf_ul_power_control_analytical.csv')):
    bw=0 if r['Channel']=='PRACH' else 10*math.log10((2**int(r['Mu']))*int(r['MRB']))
    req=float(r['P0_dBm'])+bw+float(r['Alpha'])*float(r['Pathloss_dB'])+float(r['DeltaTF_dB'])+float(r['TPC_dB'])
    ck(abs(req-float(e['ExpectedRequestedPower_dBm']))<1e-9,'pc:'+r['CaseID'])
# controlled pairs
ex=rows('rf_impact_experiment_matrix.csv')
by={}
for r in ex:by.setdefault(r['PairID'],[]).append(r)
ck(len(by)==384 and all(len(v)==2 and {x['Role'] for x in v}=={'baseline','treatment'} for v in by.values()),'impact_pairs')
print(json.dumps({'Checks':checks,'Passed':checks-len(fail),'Failed':len(fail),'Failures':fail},indent=2))
sys.exit(0 if not fail else 2)
