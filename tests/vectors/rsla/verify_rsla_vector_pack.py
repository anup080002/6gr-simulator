#!/usr/bin/env python3
from __future__ import annotations
import csv, hashlib, json, math, sys
from pathlib import Path

def read_csv(p):
    with open(p,encoding='utf-8-sig',newline='') as f: return list(csv.DictReader(f))
def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for c in iter(lambda:f.read(1024*1024),b''): h.update(c)
    return h.hexdigest()
def fail(msg, failures): failures.append(msg); print('FAIL',msg)
def ok(msg): print('PASS',msg)
root=Path(sys.argv[1] if len(sys.argv)>1 else Path(__file__).parent)
failures=[]
manifest=json.loads((root/'independent_vector_manifest.json').read_text(encoding='utf-8'))
for item in manifest['files']:
    p=root/item['FileName']
    if not p.is_file(): fail('missing:'+item['FileName'],failures); continue
    if sha(p)!=item['SHA256']: fail('hash:'+item['FileName'],failures)
    rows=read_csv(p)
    if len(rows)!=item['Rows']: fail('rows:'+item['FileName'],failures)
if not failures: ok(f"manifest:{len(manifest['files'])} files")
# Counts
checks={'reference_signals_measurements_link_adaptation_18_findings.csv':18,'rsla_capability_profile_matrix.csv':180,'rsla_dmrs_test_vectors.csv':192,'rsla_srs_test_vectors.csv':162,'expected_rsla_measurement_analytical_vectors.csv':120,'rsla_impact_analysis_families.csv':64,'rsla_impact_experiment_matrix.csv':768,'rsla_impact_pairing_contract.csv':64,'rsla_impact_acceptance_rules.csv':96,'rsla_matlab_test_plan.csv':70}
for fn,n in checks.items():
    got=len(read_csv(root/fn))
    if got!=n: fail(f'count:{fn}:{got}!={n}',failures)
    else: ok(f'count:{fn}:{n}')
# Measurement formulas
for r in read_csv(root/'expected_rsla_measurement_analytical_vectors.csv'):
    q=r['Quantity']; rs=float(r['ReferenceSignalPowerW']); interf=float(r['InterferencePowerW']); noise=float(r['NoisePowerW']); rssi=float(r['RSSIPowerW']); nrb=int(r['NRB'])
    if q in {'SS-RSRP','CSI-RSRP','SRS-RSRP'}: exp=10*math.log10(rs)+30
    elif q in {'SS-RSRQ','CSI-RSRQ'}: exp=10*math.log10(nrb*rs/rssi)
    elif q in {'SS-SINR','CSI-SINR'}: exp=10*math.log10(rs/(interf+noise))
    else: exp=10*math.log10(rssi)+30
    if abs(exp-float(r['ExpectedValue']))>1e-7: fail('measurement_formula:'+r['CaseID'],failures); break
else: ok('measurement formulas')
# EESM formula
for r in read_csv(root/'expected_rsla_effective_sinr_vectors.csv'):
    if r['Method']!='EESM': continue
    beta=10**(float(r['BetaDb'])/10); vals=[10**(float(x)/10) for x in r['SINRPerREDb'].split(';')]
    ge=-beta*math.log(sum(math.exp(-g/beta) for g in vals)/len(vals))
    if abs(ge-float(r['ExpectedEffectiveSINRLinear']))>1e-9*max(1,ge): fail('eesm:'+r['CaseID'],failures); break
else: ok('EESM analytical floor')
# OLLA balance
for r in read_csv(root/'expected_rsla_olla_analytical_vectors.csv'):
    p=float(r['TargetBLER']); a=float(r['MuAckDb']); n=float(r['MuNackDb']); drift=(1-p)*(-a)+p*n
    if abs(drift)>1e-8: fail('olla_balance:'+r['CaseID'],failures); break
else: ok('OLLA target-drift balance')
# L3 filtering recurrence
state={}
for r in read_csv(root/'expected_rsla_l3_filter_vectors.csv'):
    key=r['CaseID']; x=float(r['InputValueDb']); a=float(r['A']); expected=float(r['ExpectedFilteredValueDb']); idx=int(r['SampleIndex'])
    calc=x if idx==0 else (1-a)*state[key]+a*x
    if abs(calc-expected)>1e-7: fail('filter:'+key+':'+str(idx),failures); break
    state[key]=calc
else: ok('L3 filter analytical floor')
# Impact pair integrity
rows=read_csv(root/'rsla_impact_experiment_matrix.csv'); groups={}
for r in rows: groups.setdefault((r['FamilyID'],r['PairID']),[]).append(r)
fields=['Seed','Trial','PayloadHash','ChannelHash','NoiseHash','TrafficHash','InitialStateHash','ConfigurationHashExceptFactor']
if len(groups)!=384: fail('impact_pair_count:'+str(len(groups)),failures)
else:
    for key,g in groups.items():
        if len(g)!=2 or {x['Arm'] for x in g}!={'BASELINE','TREATMENT'}: fail('pair_arms:'+str(key),failures); break
        if any(len({x[f] for x in g})!=1 for f in fields): fail('pair_invariants:'+str(key),failures); break
    else: ok('384 matched impact pairs')
print(json.dumps({'Passed':not failures,'FailureCount':len(failures),'Failures':failures},indent=2))
sys.exit(0 if not failures else 2)
