#!/usr/bin/env python3
from __future__ import annotations
import csv,hashlib,json,math,sys
from pathlib import Path
root=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parent

def rows(p):
    with open(p,encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def sha(p):
    h=hashlib.sha256();
    with open(p,'rb') as f:
        for c in iter(lambda:f.read(1024*1024),b''):h.update(c)
    return h.hexdigest()
fail=[];checks=0
def ck(c,m):
    global checks;checks+=1
    if not c:fail.append(m)
manifest=json.loads((root/'independent_vector_manifest.json').read_text())
for a in manifest['Artifacts']:
    p=root/a['FileName'];ck(p.is_file(),'missing:'+a['FileName'])
    if p.is_file():
        ck(sha(p)==a['SHA256'],'hash:'+a['FileName'])
        ck(len(rows(p))==a['Rows'],'rows:'+a['FileName'])
# analytical invariants
for r in rows(root/'expected_waveform_wola_coefficients.csv'):
    ck(abs(float(r['SumSquares'])-1)<=1e-12,'wola:'+r['VectorID'])
for r in rows(root/'expected_waveform_papr_analytical.csv'):
    ck(math.isfinite(float(r['ExpectedPAPR_dB'])),'papr:'+r['VectorID'])
for r in rows(root/'waveform_dft_size_test_vectors.csv'):
    n=int(r['M']); q=n
    for p in (2,3,5):
        while q%p==0:q//=p
    ck((q==1)==(r['Allowed'].lower()=='true'),'dft_size:'+r['M'])
for r in rows(root/'waveform_capability_profile_matrix.csv'):
    ck(r['ExpectedOutcome'] in {'EXECUTE','REJECT'},'capability:'+r['ProfileID']+':'+r['Feature'])
imp=rows(root/'waveform_impact_experiment_matrix.csv');ck(len(imp)==768,'impact_rows')
by={}
for r in imp:by.setdefault(r['PairID'],[]).append(r)
ck(len(by)==384 and all(len(v)==2 and {x['Arm'] for x in v}=={'BASELINE','TREATMENT'} for v in by.values()),'impact_pairs')
print(json.dumps({'Checks':checks,'Passed':checks-len(fail),'Failed':len(fail),'Failures':fail},indent=2));sys.exit(0 if not fail else 2)
