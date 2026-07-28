#!/usr/bin/env python3
import csv,json,sys
from pathlib import Path
root=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parent
req=['CODEX_PROMPT_18_WEBGUI_SINGLE_SCENARIO_FULL_STACK_QUALIFICATION.md','lls_webgui_full_stack_sinr_geometry_qualification.yaml','full_stack_subcase_matrix.csv','full_stack_component_coverage_matrix.csv','full_stack_value_correctness_contract.csv','full_stack_negative_fault_injection_matrix.csv','full_stack_acceptance_rules.csv','full_stack_required_artifact_registry.csv','full_stack_webgui_page_contract.csv','full_stack_artifact_manifest_schema.json','verify_full_stack_qualification_artifacts.py','FULL_STACK_WEBGUI_RUN_GUIDE.md']
fail=[]
for n in req:
    if not (root/n).exists(): fail.append('missing:'+n)
def count(n):
    with (root/n).open(newline='',encoding='utf-8-sig') as f:return sum(1 for _ in csv.DictReader(f))
for n,minimum in [('full_stack_subcase_matrix.csv',25),('full_stack_component_coverage_matrix.csv',150),('full_stack_value_correctness_contract.csv',80),('full_stack_negative_fault_injection_matrix.csv',60),('full_stack_acceptance_rules.csv',150),('full_stack_required_artifact_registry.csv',700)]:
    if (root/n).exists() and count(n)<minimum: fail.append(f'low rows:{n}:{count(n)}')
try: json.loads((root/'full_stack_artifact_manifest_schema.json').read_text())
except Exception as e: fail.append('bad json schema:'+str(e))
print('Failures:',len(fail))
for x in fail:print('FAIL',x)
sys.exit(0 if not fail else 2)
