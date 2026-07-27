#!/usr/bin/env python3
from __future__ import annotations
import csv, hashlib, json, sys
from pathlib import Path
from PIL import Image
import yaml

root=Path(sys.argv[1] if len(sys.argv)>1 else Path(__file__).resolve().parent)
fail=[]; checks=0
required=[
'CODEX_PROMPT_15_WEBGUI_SECURITY_OPERATIONS_ARCHITECTURE_WITH_DASHBOARD.md','webgui_security_operations_12_findings.csv','current_webgui_static_audit.csv','webgui_source_change_map.csv','webgui_implementation_task_graph.csv','webgui_test_plan.csv','webgui_role_permission_matrix.csv','webgui_route_authorization_matrix.csv','webgui_deployment_profiles.yaml','webgui_security_policy.yaml','webgui_yaml_ui_mapping_contract.csv','webgui_parameter_coverage_summary.csv','dashboard_visual_reference_catalog.csv','dashboard_dut_visualization_catalog.csv','dashboard_artifact_registry.csv','dashboard_artifact_manifest_schema.json','webgui_api_contract.json','webgui_yaml_roundtrip_test_vectors.csv','webgui_security_negative_test_vectors.csv','webgui_run_quota_test_vectors.csv','webgui_artifact_gallery_test_vectors.csv','webgui_decommission_manifest.csv','DASHBOARD_INFORMATION_ARCHITECTURE.md','DASHBOARD_WIREFRAME.html']
for name in required:
 checks+=1
 if not (root/name).is_file(): fail.append('missing:'+name)

def rows(name):
 with (root/name).open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
for name,minimum in [('webgui_security_operations_12_findings.csv',12),('webgui_test_plan.csv',45),('webgui_yaml_ui_mapping_contract.csv',500),('dashboard_artifact_registry.csv',800),('dashboard_dut_visualization_catalog.csv',70),('webgui_artifact_gallery_test_vectors.csv',800)]:
 checks+=1
 try:
  n=len(rows(name))
  if n<minimum: fail.append(f'row_count:{name}:{n}<{minimum}')
 except Exception as e: fail.append(f'csv:{name}:{e}')
checks+=1
try:
 data=json.loads((root/'dashboard_artifact_manifest_schema.json').read_text())
 if data.get('type')!='object':fail.append('manifest_schema_type')
except Exception as e:fail.append('manifest_schema:'+str(e))
for name in ['webgui_deployment_profiles.yaml','webgui_security_policy.yaml']:
 checks+=1
 try: yaml.safe_load((root/name).read_text())
 except Exception as e: fail.append('yaml:'+name+':'+str(e))
for row in rows('dashboard_visual_reference_catalog.csv'):
 p=root/'visual_references'/row['FileName'];checks+=1
 if not p.is_file(): fail.append('visual_missing:'+row['FileName']);continue
 try:
  with Image.open(p) as im: im.verify()
  h=hashlib.sha256(p.read_bytes()).hexdigest()
  if h!=row['SHA256']:fail.append('visual_hash:'+row['FileName'])
 except Exception as e:fail.append('visual_decode:'+row['FileName']+':'+str(e))
# Core policy checks.
findings=rows('webgui_security_operations_12_findings.csv'); checks+=1
if {r['FindingID'] for r in findings}!={f'WEB-{i:03d}' for i in range(1,13)}:fail.append('finding_ids')
perms=rows('webgui_role_permission_matrix.csv'); checks+=1
if not any(r['Permission']=='run:delete_any' and r['Admin']=='allow' and r['Viewer']=='deny' for r in perms):fail.append('permission_matrix')
art=rows('dashboard_artifact_registry.csv'); checks+=1
if len({r['ArtifactID'] for r in art})!=len(art):fail.append('duplicate_artifact_id')
params=rows('webgui_yaml_ui_mapping_contract.csv'); checks+=1
if len({r['ParameterPath'] for r in params})!=len(params):fail.append('duplicate_parameter_path')
print(json.dumps({'root':str(root),'checks':checks,'failures':fail,'passed':checks-len(fail)},indent=2))
sys.exit(2 if fail else 0)
