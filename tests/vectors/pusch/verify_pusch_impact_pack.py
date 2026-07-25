#!/usr/bin/env python3
from __future__ import annotations
import csv, json, hashlib, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent

def rows(name):
    with (HERE/name).open(newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))

def main():
    fam=rows('pusch_impact_analysis_families.csv'); exp=rows('pusch_impact_experiment_matrix.csv'); pairing=rows('pusch_impact_pairing_contract.csv'); rules=rows('pusch_impact_acceptance_rules.csv')
    floor=rows('expected_pusch_impact_analytical_floor.csv'); cc=rows('desired_pusch_impact_csv_contract.csv'); ic=rows('desired_pusch_impact_image_contract.csv')
    failures=[]
    fids={r['FamilyID'] for r in fam}; rids={r['RuleID'] for r in rules}; eids=[]
    if len(fids)!=len(fam):failures.append('duplicate_family_id')
    pfids={r['FamilyID'] for r in pairing}
    if len(pairing)!=len(fam) or pfids!=fids:failures.append('pairing_contract_family_mismatch')
    for r in exp:
        eids.append(r['ExperimentID'])
        if not r.get('DesignCell'):failures.append('missing_design_cell:'+r['ExperimentID'])
        if not r.get('PairID'):failures.append('missing_pair_id:'+r['ExperimentID'])
        if r['FamilyID'] not in fids:failures.append('unknown_experiment_family:'+r['ExperimentID'])
        for rid in [x for x in r['RuleIDs'].split('|') if x]:
            if rid not in rids:failures.append('unknown_rule:'+r['ExperimentID']+':'+rid)
        try:
            if not 0<float(r['ConfidenceLevel'])<1:failures.append('bad_confidence:'+r['ExperimentID'])
            if int(float(r['MaxTBs']))<int(float(r['MinTBs'])):failures.append('max_less_than_min:'+r['ExperimentID'])
            json.loads(r['ParameterOverridesJSON'])
        except Exception as e:failures.append('bad_experiment_field:'+r['ExperimentID']+':'+str(e))
    if len(eids)!=len(set(eids)):failures.append('duplicate_experiment_id')
    variants_by_family={fid:set() for fid in fids}
    for r in exp: variants_by_family[r['FamilyID']].add(r['Variant'])
    for pr in pairing:
        if pr['DesignType'] in {'paired_baseline_treatment','multi_level_sweep','scenario_benchmark'} and 'baseline' not in variants_by_family.get(pr['FamilyID'],set()):
            failures.append('missing_explicit_baseline:'+pr['FamilyID'])
        if pr['UnpairedFallback'].strip().upper().startswith('PROHIBITED') is False:
            failures.append('unsafe_unpaired_fallback:'+pr['FamilyID'])
    for r in rules:
        if r['FamilyID'] not in fids:failures.append('unknown_rule_family:'+r['RuleID'])
        if r['Severity'] not in {'HARD','STATISTICAL','DIAGNOSTIC'}:failures.append('bad_rule_severity:'+r['RuleID'])
    for r in floor:
        if r['FamilyID'] not in fids or r['RuleID'] not in rids:failures.append('bad_floor_reference:'+r['OracleCaseID'])
        try:json.loads(r['InputJSON'])
        except Exception:failures.append('bad_floor_json:'+r['OracleCaseID'])
    if len({r['FileName'] for r in cc})!=len(cc):failures.append('duplicate_csv_contract')
    if len({r['ImageFile'] for r in ic})!=len(ic):failures.append('duplicate_image_contract')
    required={'F01','F05','F08','F13','F17','F21','F23','F26','F28','F33','F38','F40','F43','F51','F52'}
    missing=required-fids
    if missing:failures.append('missing_required_families:'+','.join(sorted(missing)))
    print(json.dumps({'families':len(fam),'experiments':len(exp),'pairing_contracts':len(pairing),'rules':len(rules),'analytical_floor':len(floor),'csv_contracts':len(cc),'image_contracts':len(ic),'failures':failures},indent=2))
    return 0 if not failures else 2
if __name__=='__main__':raise SystemExit(main())
