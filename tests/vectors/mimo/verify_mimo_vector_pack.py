#!/usr/bin/env python3
from __future__ import annotations
import csv,hashlib,json,math,sys
from pathlib import Path
import numpy as np
HERE=Path(__file__).resolve().parent

def rows(p):
 with p.open(newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def truth(v):return str(v).strip().upper() in {'TRUE','PASS','YES','1'}
def parse_complex(s):return complex(str(s).replace('i','j'))
def parse_matrix(s):
 return np.array([[parse_complex(x) for x in row.split(',')] for row in str(s).split(';')],complex)
def cstr(z,nd=12):return f'{z.real:.{nd}g}{z.imag:+.{nd}g}j'
def cmatrix(M):return ';'.join(','.join(cstr(complex(x)) for x in row) for row in np.asarray(M))
def shatxt(s):return hashlib.sha256(s.encode()).hexdigest()
fail=[]
manifest=json.loads((HERE/'independent_vector_manifest.json').read_text())
for x in manifest['files']:
 p=HERE/x['path']
 if not p.exists():fail.append('missing:'+x['path']);continue
 if sha(p)!=x['sha256']:fail.append('sha:'+x['path'])
 if len(rows(p))!=int(x['rows']):fail.append('rows:'+x['path'])

# Exact TS 38.214 two-port floor.
s2=math.sqrt(2)
expected={
 ('R1',0):np.array([[1],[1]],complex)/s2,
 ('R1',1):np.array([[1],[1j]],complex)/s2,
 ('R1',2):np.array([[1],[-1]],complex)/s2,
 ('R1',3):np.array([[1],[-1j]],complex)/s2,
 ('R2',0):np.array([[1,1],[1,-1]],complex)/2,
 ('R2',1):np.array([[1,1],[1j,-1j]],complex)/2,
}
cb=rows(HERE/'expected_typeI_2port_codebook.csv')
for (rk,idx),W in expected.items():
 rr=[r for r in cb if r['CaseID']==f'2P_{rk}_{idx}']
 if len(rr)!=W.size:fail.append(f'cb2_count:{rk}:{idx}');continue
 A=np.zeros_like(W)
 for r in rr:A[int(r['Port']),int(r['Layer'])]=float(r['Real'])+1j*float(r['Imag'])
 if not np.allclose(A,W,rtol=0,atol=1e-13):fail.append(f'cb2_value:{rk}:{idx}')
 if not all(r['MatrixSHA256']==shatxt(cmatrix(W)) for r in rr):fail.append(f'cb2_hash:{rk}:{idx}')
 if abs(np.linalg.norm(A,'fro')**2-1)>1e-12:fail.append(f'cb2_power:{rk}:{idx}')

# Array response vector norm for every case.
arr=rows(HERE/'expected_antenna_array_response.csv')
for cid in {r['CaseID'] for r in arr}:
 v=np.array([float(r['Real'])+1j*float(r['Imag']) for r in sorted((x for x in arr if x['CaseID']==cid),key=lambda x:int(x['Element']))])
 if abs(np.linalg.norm(v)-1)>1e-12:fail.append('array_norm:'+cid)

# Port mapping validity.
for r in rows(HERE/'mimo_port_mapping_test_vectors.csv'):
 lp=r['LogicalPorts'].split('|') if r['LogicalPorts'] else []
 pe=r['PhysicalElements'].split('|') if r['PhysicalElements'] else []
 bij=len(lp)==len(pe)==len(set(lp))==len(set(pe))
 if truth(r['ExpectedValid']) and not bij:fail.append('port_expected_valid:'+r['CaseID'])
 if not truth(r['ExpectedValid']) and not r['ExpectedError']:fail.append('port_missing_error:'+r['CaseID'])

# CSI Part1/Part2 simple-floor ownership.
schema={r['CaseID']:r for r in rows(HERE/'mimo_csi_report_schema_test_vectors.csv')}
own=rows(HERE/'expected_csi_bit_ownership_floor.csv')
for cid,r in schema.items():
 if str(r['Part1Bits']).isdigit():
  for part in [1,2]:
   n=int(r[f'Part{part}Bits']);q=[x for x in own if x['CaseID']==cid and int(x['Part'])==part]
   if len(q)!=n:fail.append(f'csi_bits:{cid}:{part}')
   if len({int(x['BitIndex']) for x in q})!=n:fail.append(f'csi_duplicate:{cid}:{part}')
 if truth(r['ExpectedValid']) and not truth(r['SeparateEncoding']):fail.append('csi_encoding:'+cid)

# Independent exhaustive RI/PMI objective selection.
metric=rows(HERE/'mimo_ri_pmi_metric_test_vectors.csv');sel={r['CaseID']:r for r in rows(HERE/'expected_mimo_ri_pmi_selection.csv')}
for cid,s in sel.items():
 q=[r for r in metric if r['CaseID']==cid]
 if not q:fail.append('metric_missing:'+cid);continue
 best=max(q,key=lambda r:float(r['MetricValue']))
 if int(best['Rank'])!=int(s['ExpectedRI']) or int(best['PMI'])!=int(s['ExpectedPMI']):fail.append('metric_selection:'+cid)
 if best['CandidateMatrixSHA256']!=s['ExpectedPrecoderSHA256']:fail.append('metric_hash:'+cid)

# Covariance validity floor.
for r in rows(HERE/'mimo_covariance_test_vectors.csv'):
 R=parse_matrix(r['Matrix']);herm=np.allclose(R,R.conj().T,atol=1e-10);mine=float(np.linalg.eigvalsh((R+R.conj().T)/2).min())
 valid=herm and mine>=-1e-10 and int(r['Samples'])>=int(r['MinSamples']) and int(r['AgeSlots'])<=int(r['MaxAgeSlots'])
 if truth(r['ExpectedValid'])!=valid:fail.append('cov_validity:'+r['CaseID'])

# Precoder dimensions, orientation and power floor.
for r in rows(HERE/'mimo_precoder_application_test_vectors.csv'):
 W=parse_matrix(r['Matrix'])
 if r['ExpectedStatus']=='PASS':
  if W.shape!=(int(r['NPorts']),int(r['Rank'])):fail.append('prec_dims:'+r['CaseID'])
  if abs(np.linalg.norm(W,'fro')**2-float(r['ExpectedMatrixFroPower']))>1e-8:fail.append('prec_power:'+r['CaseID'])
  if r['MatrixSHA256']!=shatxt(cmatrix(W)):fail.append('prec_hash:'+r['CaseID'])
 else:
  if not r.get('ExpectedError'):fail.append('prec_neg_error:'+r['CaseID'])

# SRS authority rule floor.
for r in rows(HERE/'mimo_srs_authority_test_vectors.csv'):
 valid=int(r['AgeSlots'])<=8 and float(r['SNRdB'])>=-3
 if truth(r['ExpectedValid'])!=valid:fail.append('srs_validity:'+r['CaseID'])
 if valid and not truth(r['DecisionAuthoritative']):fail.append('srs_authority:'+r['CaseID'])

# Multi-user and multi-TRP structural rules.
for r in rows(HERE/'mimo_mu_mimo_test_vectors.csv'):
 valid=r['DMRSDesign']=='orthogonal' and not (int(r['NumUE'])==4 and float(r['AngularSeparationDeg'])==0)
 if truth(r['ExpectedValid'])!=valid:fail.append('mu_validity:'+r['CaseID'])
for r in rows(HERE/'mimo_multitrp_test_vectors.csv'):
 valid=r['Mode']=='NCJT' or (float(r['TimingMismatchFractionCP'])<=.1 and float(r['PhaseMismatchDeg'])<=15)
 if truth(r['ExpectedValid'])!=valid:fail.append('trp_validity:'+r['CaseID'])
for r in rows(HERE/'mimo_hybrid_beamforming_test_vectors.csv'):
 valid=int(r['NStreams'])<=int(r['NRFChains'])<=int(r['Nant'])
 if truth(r['ExpectedValid'])!=valid:fail.append('hybrid_validity:'+r['CaseID'])

# Beam state machine exact bounded edges.
valid_edges={'IDLE':{'P1_MEASURING'},'P1_MEASURING':{'P1_REPORTED'},'P1_REPORTED':{'TCI_PENDING'},'TCI_PENDING':{'TCI_ACTIVE'},'TCI_ACTIVE':{'P2_REFINING','DATA_ACTIVE','BEAM_FAILURE_DETECTED'},'P2_REFINING':{'TCI_PENDING','DATA_ACTIVE'},'DATA_ACTIVE':{'P2_REFINING','BEAM_FAILURE_DETECTED'},'BEAM_FAILURE_DETECTED':{'BFR_RA'},'BFR_RA':{'RECOVERED'},'RECOVERED':{'TCI_ACTIVE','DATA_ACTIVE'}}
for r in rows(HERE/'mimo_beam_state_transition_vectors.csv'):
 valid=r['ToState'] in valid_edges.get(r['FromState'],set())
 if truth(r['ExpectedValid'])!=valid:fail.append('beam_edge:'+r['CaseID'])

# Impact matrix and pairing completeness.
fams=rows(HERE/'mimo_impact_analysis_families.csv');exp=rows(HERE/'mimo_impact_experiment_matrix.csv');rules=rows(HERE/'mimo_impact_acceptance_rules.csv')
if len(fams)!=64:fail.append('family_count')
if len(exp)!=768:fail.append('experiment_count')
if len(rules)!=96:fail.append('rule_count')
for f in fams:
 q=[r for r in exp if r['FamilyID']==f['FamilyID']]
 if len(q)!=12:fail.append('family_experiments:'+f['FamilyID'])
 for pid in {x['PairID'] for x in q}:
  z=[x for x in q if x['PairID']==pid]
  if {x['Variant'] for x in z}!={'baseline','treatment'}:fail.append('pair_variants:'+pid)
  if len({(x['Seed'],x['PayloadID'],x['ChannelRealizationID'],x['NoiseRealizationID'],x['SNR_dB']) for x in z})!=1:fail.append('pair_identity:'+pid)

print(json.dumps({'manifest_files':len(manifest['files']),'vector_rows':sum(int(x['rows']) for x in manifest['files']),'impact_families':len(fams),'impact_experiments':len(exp),'acceptance_rules':len(rules),'failures':fail},indent=2))
sys.exit(0 if not fail else 2)
