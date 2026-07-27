#!/usr/bin/env python3
from __future__ import annotations
import csv, json, hashlib, sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv)>1 else Path(__file__).resolve().parent)
checks=[]
def add(name, ok, detail=''):
    checks.append((name,bool(ok),detail))

def rows(path):
    with path.open(encoding='utf-8',newline='') as f:
        return list(csv.DictReader(f))

required=[
'integration_32_findings.csv','integration_architecture_contract.yaml','integration_mode_contract.yaml',
'integration_state_ownership_matrix.csv','integration_interface_contract.csv','integration_actual_run_matrix.csv',
'integration_cross_mode_equivalence_vectors.csv','integration_negative_test_vectors.csv','integration_acceptance_rules.csv',
'integration_matlab_test_plan.csv','desired_integration_csv_contract.csv','desired_integration_image_contract.csv',
'integration_dashboard_visualization_catalog.csv','verify_integration_artifacts.py','CODEX_PROMPT_16_END_TO_END_TWO_MODE_INTEGRATION_WITH_ACTUAL_RUNS.md'
]
for f in required:
    add('exists:'+f,(root/f).is_file())
try:
    add('findings_count',len(rows(root/'integration_32_findings.csv'))==32)
    add('rules_count',len(rows(root/'integration_acceptance_rules.csv'))==120)
    add('tests_count',len(rows(root/'integration_matlab_test_plan.csv'))==100)
    add('cross_vectors',len(rows(root/'integration_cross_mode_equivalence_vectors.csv'))>=64)
    add('negative_vectors',len(rows(root/'integration_negative_test_vectors.csv'))>=60)
    add('run_matrix',len(rows(root/'integration_actual_run_matrix.csv'))>=20)
    csv_contract=rows(root/'desired_integration_csv_contract.csv')
    img_contract=rows(root/'desired_integration_image_contract.csv')
    add('csv_contract_unique',len({r['Artifact'] for r in csv_contract})==len(csv_contract),str(len(csv_contract)))
    add('image_contract_unique',len({r['Artifact'] for r in img_contract})==len(img_contract),str(len(img_contract)))
    add('dashboard_covers_images',len(rows(root/'integration_dashboard_visualization_catalog.csv'))==len(img_contract))
except Exception as e:
    add('table_validation',False,repr(e))

failed=[c for c in checks if not c[1]]
for name,ok,detail in checks:
    print(('PASS' if ok else 'FAIL'),name,detail)
print(json.dumps({'checks':len(checks),'passed':len(checks)-len(failed),'failed':len(failed)},indent=2))
sys.exit(0 if not failed else 2)
