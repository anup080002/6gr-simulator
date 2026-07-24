#!/usr/bin/env python3
"""Run non-MATLAB checks available for the PDSCH/DL-SCH Codex pack.

These checks validate vector integrity, mathematical invariants, source-visible
shortcuts, required-artifact presence, and the fail-closed verifier. They do
not claim to execute or validate the MATLAB PHY chain.
"""
from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = Path('/mnt/data/6gr_src/6GR Simulator_v2_clean_main')

spec = importlib.util.spec_from_file_location('pdsch_vectors', ROOT/'generate_pdsch_independent_vectors.py')
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

results: list[dict[str, object]] = []

def add(check: str, passed: bool, evidence: str, blocked: bool = False) -> None:
    status = 'BLOCKED' if blocked else ('PASS' if passed else 'FAIL')
    results.append({'CheckID': f'LIM-{len(results)+1:03d}', 'Check': check,
                    'Status': status, 'Evidence': evidence})

def csv_rows(name: str) -> list[dict[str,str]]:
    with (ROOT/name).open(newline='',encoding='utf-8-sig') as f:
        return list(csv.DictReader(f))

# Manifest and hashes.
proc = subprocess.run([sys.executable, str(ROOT/'verify_pdsch_vector_pack.py')], capture_output=True, text=True)
add('independent vector manifest and SHA-256', proc.returncode == 0, proc.stdout.strip().replace('\n',' | '))

# Full constellation normalization, independently enumerating all symbols.
for name,(qm,_) in mod.QAM_INFO.items():
    bits=[]
    for value in range(2**qm):
        bits.extend([(value >> (qm-1-i)) & 1 for i in range(qm)])
    symbols=mod.qam_modulate(bits,name)
    mean=sum(abs(x)**2 for x in symbols)/len(symbols)
    add(f'{name} full-constellation mean energy', abs(mean-1.0) < 1e-12, f'mean={mean:.16g}; symbols={len(symbols)}')

# CRC append-and-divide-zero invariant with a separate division pass.
def divide_zero(block, poly_name):
    exps=mod.CRC_POLY_EXPONENTS[poly_name]
    degree=max(exps)
    poly=[1 if p in exps else 0 for p in range(degree,-1,-1)]
    work=list(map(int,block))
    for i in range(len(work)-degree):
        if work[i]:
            for j,v in enumerate(poly): work[i+j]^=v
    return all(v==0 for v in work[-degree:])
crc_rows=csv_rows('expected_pdsch_tb_crc_vectors.csv')
crc_ok=0
for row in crc_rows:
    payload=[int(x) for x in row['InputBits']]
    crc=[int(x) for x in row['ExpectedCRCBits']]
    if divide_zero(payload+crc,row['CRCType']): crc_ok+=1
add('all supplied TB CRC vectors divide to zero', crc_ok==len(crc_rows), f'{crc_ok}/{len(crc_rows)}')

# Scrambling fields and q dependence.
scr=csv_rows('expected_pdsch_scrambling_vectors.csv')
scr_good=all(len(r['GoldBits'])==len(r['ScrambledBits']) and int(r['GoldOnes'])==r['GoldBits'].count('1') for r in scr)
add('scrambling vector lengths and ones counts', scr_good, f'rows={len(scr)}')
inputs=csv_rows('pdsch_scrambling_test_vectors.csv')
q_pairs={}
for i,r in enumerate(inputs):
    key=(r['RNTI'],r['DataScramblingIdentityNID'],r['Length'])
    q_pairs.setdefault(key,[]).append(scr[i]['GoldBits'])
q_diff=all(len(set(v))==len(v) for v in q_pairs.values() if len(v)>1)
add('codeword index changes Gold sequence where paired', q_diff, f'paired_keys={sum(len(v)>1 for v in q_pairs.values())}')

# Layer conservation and coverage.
layer_inputs={r['CaseID']:r for r in csv_rows('pdsch_layer_mapping_test_vectors.csv') if r['ExpectedStatus']=='PASS'}
layer_out=csv_rows('expected_pdsch_layer_mapping.csv')
layer_ok=True
for cid,inp in layer_inputs.items():
    expected_layers=int(inp['Rank'])
    rows=[r for r in layer_out if r['CaseID']==cid and r['Status']=='PASS']
    layer_ok &= len(rows)==expected_layers
    for cw in range(int(inp['NumCodewords'])):
        src=inp[f'Codeword{cw}Symbols'].split('|') if inp.get(f'Codeword{cw}Symbols') else []
        mapped=[]
        for r in rows:
            if int(r['SourceCodeword'])==cw and r['ExpectedSymbols']:
                mapped.extend(r['ExpectedSymbols'].split('|'))
        layer_ok &= sorted(mapped,key=int)==sorted(src,key=int)
add('rank 1-8 codeword-to-layer conservation', bool(layer_ok), f'valid_cases={len(layer_inputs)}; output_rows={len(layer_out)}')

# TBS structural invariants.
tbs=[r for r in csv_rows('expected_pdsch_tbs_basegraph.csv') if r['Status']=='PASS']
tbs_ok=all(int(r['TBS'])>=24 and int(r['TBS'])%8==0 and int(r['BaseGraph']) in (1,2) and int(r['TBCRCLength']) in (16,24) for r in tbs)
add('TBS/base-graph/CRC structural invariants', tbs_ok, f'valid_rows={len(tbs)}')

# DMRS positions must be contained in allocations for passing rows.
dmrs_in={r['CaseID']:r for r in csv_rows('pdsch_dmrs_test_vectors.csv')}
dmrs_out=csv_rows('expected_pdsch_dmrs_symbol_positions.csv')
dmrs_ok=True
for r in dmrs_out:
    if r['Status']!='PASS': continue
    x=dmrs_in[r['CaseID']]
    start=int(x['PDSCHStartSymbol']); end=start+int(x['PDSCHDurationLd'])
    positions=[int(v) for v in r['ExpectedDMRSSymbols'].split('|') if v!='']
    dmrs_ok &= len(positions)==int(r['ExpectedDMRSSymbolCount']) and all(start<=p<end for p in positions)
add('DM-RS passing positions contained in PDSCH allocation', bool(dmrs_ok), f'rows={len(dmrs_out)}')

ports=csv_rows('expected_pdsch_dmrs_port_table.csv')
port_ok=True
for r in ports:
    config_type=int(r['DMRSConfigurationType']); length=int(r['DMRSLength'])
    enhanced=r['DMRSMultiplexing']=='enhanced'; port=int(r['DMRSPortSetValue'])
    valid=set(mod.valid_dmrs_port_indices(config_type,length,enhanced))
    if r['ExpectedStatus']=='PASS':
        wf,wt=mod.dmrs_port_weights(config_type,port)
        group,delta=mod.dmrs_group_delta(config_type,port)
        port_ok &= port in valid
        port_ok &= 1000+port==int(r['PhysicalAntennaPort'])
        port_ok &= r['SupportedLPrime']==('0|1' if length==2 else '0')
        port_ok &= int(float(r['CDMGroupLambda']))==group and int(float(r['Delta']))==delta
        port_ok &= r['WF']==mod.num_text(wf) and r['WT']==mod.num_text(wt)
    else:
        port_ok &= port not in valid
add('DM-RS port capability, non-contiguous enhanced sets, OCC weights and deltas', bool(port_ok), f'rows={len(ports)}; valid={sum(r["ExpectedStatus"]=="PASS" for r in ports)}; invalid={sum(r["ExpectedStatus"]=="ERROR" for r in ports)}')

# Reserved union arithmetic.
res=csv_rows('expected_pdsch_reserved_re_union.csv')
res_ok=all(int(r['DataRECount'])+int(r['ReservedUnionCount'])==int(r['AllocationRECount']) for r in res if r['Status']=='PASS')
add('reserved-RE union partitions allocation', res_ok, f'rows={len(res)}')

# Assignment vectors must have no unsupported invented 1_3 format.
assign=csv_rows('pdsch_scheduling_assignment_test_vectors.csv')
formats=sorted(set(r['DCIFormat'] for r in assign if r['DCIFormat']))
add('assignment vectors limited to declared DCI 1_0/1_1/1_2', set(formats)<= {'1_0','1_1','1_2'}, f'formats={formats}')
sps=[r for r in assign if r['Profile']=='sps_strict']
sps_required_errors={
    'SPSNotActivated', 'SPSReleased', 'NotSPSOccasion',
    'SPSActivationDCICRCFailed', 'SPSActivationDCIRNTIMismatch'
}
sps_pass=[r for r in sps if r['ExpectedStatus']=='PASS']
sps_errors={r['ExpectedError'] for r in sps if r['ExpectedStatus']=='ERROR'}
sps_ok=(len(sps)==6 and len(sps_pass)==1 and
        all(r['SPSActivationDCIId'] for r in sps) and
        sps_required_errors <= sps_errors and
        sps_pass[0].get('SPSActivationDCICRCPass')=='1' and
        sps_pass[0].get('SPSActivationDCIRNTIMatch')=='1' and
        any(r['ExpectedError']=='SPSActivationDCICRCFailed' and r.get('SPSActivationDCICRCPass')=='0' for r in sps) and
        any(r['ExpectedError']=='SPSActivationDCIRNTIMismatch' and r.get('SPSActivationDCIRNTIMatch')=='0' for r in sps))
add('downlink SPS vectors require activation context and exact occasion', bool(sps_ok), f'sps_rows={len(sps)}; pass={sum(r["ExpectedStatus"]=="PASS" for r in sps)}')

# Coverage spans rank and mapping and marks high-rank enhanced where basic port capacity is insufficient.
cov=csv_rows('pdsch_declared_coverage_matrix.csv')
ranks=sorted(set(int(r['Rank']) for r in cov)); mappings=sorted(set(r['MappingType'] for r in cov))
high_ok=all(r['DMRSMultiplexing']=='enhanced' for r in cov if int(r['Rank']) > len(mod.valid_dmrs_port_indices(int(r['DMRSConfigurationType']),int(r['DMRSLength']),False)))
cov_ports_ok=True
for r in cov:
    valid=set(mod.valid_dmrs_port_indices(int(r['DMRSConfigurationType']),int(r['DMRSLength']),r['DMRSMultiplexing']=='enhanced'))
    selected={int(x) for x in r['DMRSPortSet'].split('|') if x!=''}
    cov_ports_ok &= len(selected)==int(r['Rank']) and selected <= valid
add('declared coverage rank 1-8 and mapping A/B', ranks==list(range(1,9)) and mappings==['A','B'], f'ranks={ranks}; mappings={mappings}')
add('high-rank coverage requests enhanced DM-RS when needed', high_ok, f'rows={len(cov)}')
add('coverage matrix selects only supported DM-RS ports', bool(cov_ports_ok), f'rows={len(cov)}')

# HARQ NDI remains stable for retransmissions and toggles only for new data.
harq=csv_rows('pdsch_harq_test_vectors.csv')
rv_rows=sorted([r for r in harq if r['CaseID'].startswith('HARQ-RV-')],key=lambda r:int(r['TransmissionIndex']))
new_row=next(r for r in harq if r['CaseID']=='HARQ-NEW-001')
harq_ndi_ok=(len(rv_rows)==4 and len({r['NDI'] for r in rv_rows})==1 and
             rv_rows[0]['NewData']=='1' and all(r['NewData']=='0' for r in rv_rows[1:]) and
             new_row['NewData']=='1' and new_row['NDI']!=rv_rows[-1]['NDI'])
add('HARQ NDI is stable for retransmissions and toggles for new data', bool(harq_ndi_ok), f'rv_ndi={[r["NDI"] for r in rv_rows]}; new_ndi={new_row["NDI"]}')

# Static source audit expected current failure count.
static=csv_rows('current_pdsch_static_audit.csv')
fail=sum(r['Status']=='FAIL' for r in static); passed=sum(r['Status']=='PASS' for r in static)
add('current source-visible shortcut audit executed', len(static)==29, f'checks={len(static)}; fail={fail}; pass={passed}')

# Existing required artifacts and PNG integrity.
presence=csv_rows('existing_pdsch_artifact_presence_audit.csv')
missing=sum(r['Status']=='MISSING' for r in presence)
add('existing required PDSCH phase artifact presence checked', len(presence)==24, f'present={len(presence)-missing}; missing={missing}')
imgs=csv_rows('existing_pdsch_image_integrity_audit.csv')
imgpass=sum(r['Status']=='PASS' for r in imgs)
add('existing repository PNG decode/nonblank check', imgpass==len(imgs), f'passed={imgpass}; total={len(imgs)}; PDSCH-specific-required=0')

# Verifier positive and intentional corruption detection.
vp=subprocess.run([sys.executable,str(ROOT/'verify_pdsch_artifacts.py'),'--self-test'],capture_output=True,text=True)
add('artifact verifier positive and corruption self-test', vp.returncode==0, vp.stdout.strip().replace('\n',' | '))

# Python compilation.
pyfiles=list(ROOT.glob('*.py'))
cp=subprocess.run([sys.executable,'-m','py_compile',*[str(x) for x in pyfiles]],capture_output=True,text=True)
add('pack Python files compile', cp.returncode==0, f'files={len(pyfiles)}; stderr={cp.stderr.strip()}')

# MATLAB/Octave availability.
import shutil
matlab=shutil.which('matlab'); octave=shutil.which('octave')
add('MATLAB runtime available for real PHY execution', matlab is not None, f'matlab={matlab}; octave={octave}; absence means MATLAB tests remain BLOCKED', blocked=matlab is None)

# Write outputs.
fields=['CheckID','Check','Status','Evidence']
with (ROOT/'limited_pdsch_test_results.csv').open('w',newline='',encoding='utf-8') as f:
    w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(results)
summary={
    'checks':len(results),
    'passed':sum(r['Status']=='PASS' for r in results),
    'failed':sum(r['Status']=='FAIL' for r in results),
    'blocked':sum(r['Status']=='BLOCKED' for r in results),
    'matlab_available':matlab is not None,
    'octave_available':octave is not None,
    'static_checks':len(static),
    'static_shortcuts_detected':fail,
    'static_existing_capabilities_detected':passed,
    'required_phase_artifacts':len(presence),
    'required_phase_artifacts_present':len(presence)-missing,
    'existing_pngs_checked':len(imgs),
    'existing_pngs_decodable_nonblank':imgpass,
    'note':'Python/static/vector checks do not execute the MATLAB PDSCH/DL-SCH PHY chain.'
}
(ROOT/'limited_test_summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
print(json.dumps(summary,indent=2))
# MATLAB absence is expected in this environment; return nonzero only for another failed check.
real_fail=[r for r in results if r['Status']=='FAIL']
raise SystemExit(0 if not real_fail else 2)
