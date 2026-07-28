#!/usr/bin/env python3
from __future__ import annotations
import argparse, csv, hashlib, os, re, sys
from pathlib import Path
try:
    from PIL import Image, ImageStat
except Exception as e:
    print(f"Pillow import failed: {e}", file=sys.stderr); sys.exit(2)

def sha256(p:Path)->str:
    h=hashlib.sha256()
    with p.open('rb') as f:
        for c in iter(lambda:f.read(1024*1024), b''): h.update(c)
    return h.hexdigest()

def read_csv(p:Path):
    with p.open(newline='',encoding='utf-8-sig') as f:
        r=csv.DictReader(f); rows=list(r); return r.fieldnames or [], rows

def required_cols(s):
    return [x.strip() for x in re.split(r'[|;]', s or '') if x.strip()]

def find_file(root:Path, name:str):
    hits=list(root.rglob(name))
    return hits[0] if len(hits)==1 else (hits[0] if hits else None)

def boolv(v): return str(v).strip().lower() in {'true','1','yes','pass','valid'}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('artifact_dir', type=Path)
    ap.add_argument('contract_dir', type=Path)
    ap.add_argument('--preset', choices=['comprehensive_smoke','deep_acceptance'], default='comprehensive_smoke')
    args=ap.parse_args()
    failures=[]; checks=0
    regp=args.contract_dir/'full_stack_required_artifact_registry.csv'
    if not regp.exists(): failures.append(f'missing contract {regp}'); print('\n'.join(failures)); return 2
    _, registry=read_csv(regp)
    reqflag='RequiredInComprehensiveSmoke' if args.preset=='comprehensive_smoke' else 'RequiredInDeepAcceptance'

    # Core consolidated evidence.
    core=['full_stack_run_manifest.csv','full_stack_config_binding.csv','full_stack_subcase_status.csv','full_stack_component_coverage_results.csv','full_stack_value_correctness_results.csv','full_stack_acceptance_results.csv','full_stack_artifact_manifest.csv','full_stack_webgui_publication.csv','full_stack_regression_summary.csv']
    for n in core:
        checks+=1
        if not find_file(args.artifact_dir,n): failures.append(f'missing core artifact:{n}')

    manifest_path=find_file(args.artifact_dir,'full_stack_artifact_manifest.csv')
    manifest_by_name={}
    if manifest_path:
        hdr,mrows=read_csv(manifest_path)
        for r in mrows:
            if r.get('FileName'): manifest_by_name[r['FileName']]=r
        if len({r.get('ArtifactID') for r in mrows}) != len(mrows): failures.append('duplicate ArtifactID in manifest')
        for r in mrows:
            if boolv(r.get('Placeholder')): failures.append(f"placeholder artifact:{r.get('FileName')}")

    for spec in registry:
        if not boolv(spec.get(reqflag)): continue
        name=spec['FileName']; kind=spec['ArtifactType']; checks+=1
        p=find_file(args.artifact_dir,name)
        if not p:
            failures.append(f'missing required {kind}:{name}'); continue
        mr=manifest_by_name.get(name)
        if not mr:
            failures.append(f'missing manifest row:{name}')
        else:
            if mr.get('SHA256') and sha256(p)!=mr.get('SHA256'): failures.append(f'hash mismatch:{name}')
            if not boolv(mr.get('WebGUIPublished')): failures.append(f'not published in WebGUI:{name}')
            if str(mr.get('Validity','')).upper() not in {'VALID','PASS'}: failures.append(f'invalid manifest status:{name}')
        if kind=='CSV':
            try: hdr,rows=read_csv(p)
            except Exception as e: failures.append(f'csv parse:{name}:{e}'); continue
            missing=[c for c in required_cols(spec.get('RequiredColumns')) if c not in hdr]
            if missing: failures.append(f'csv missing columns:{name}:{missing[:8]}')
            if len(rows)<int(float(spec.get('MinimumRows') or 1)): failures.append(f'csv rows:{name}:{len(rows)}')
            pk=required_cols(spec.get('PrimaryKey'))
            if pk and all(c in hdr for c in pk):
                keys=[tuple(r.get(c,'') for c in pk) for r in rows]
                if len(keys)!=len(set(keys)): failures.append(f'duplicate primary key:{name}')
        elif kind=='PNG':
            try:
                im=Image.open(p); im.load()
                w,h=im.size
                if w<int(float(spec.get('MinimumWidth') or 900)) or h<int(float(spec.get('MinimumHeight') or 600)): failures.append(f'png dimensions:{name}:{w}x{h}')
                stat=ImageStat.Stat(im.convert('L'))
                if not stat.var or stat.var[0] < 1e-6: failures.append(f'blank png:{name}')
            except Exception as e: failures.append(f'png decode:{name}:{e}')
            for src in required_cols(spec.get('SourceCSV')):
                if src and not find_file(args.artifact_dir,src): failures.append(f'png source missing:{name}:{src}')

    # exact config binding
    p=find_file(args.artifact_dir,'full_stack_config_binding.csv')
    if p:
        _,rows=read_csv(p)
        if not rows: failures.append('empty config binding')
        else:
            r=rows[0]
            checks+=1
            if r.get('ResolvedYAMLSHA256')!=r.get('ExecutedYAMLSHA256'): failures.append('resolved/executed YAML hash mismatch')
            if str(r.get('UnknownKeyCount','0')) not in {'0','0.0'}: failures.append('unknown YAML keys')
            if str(r.get('DroppedKeyCount','0')) not in {'0','0.0'}: failures.append('dropped YAML keys')

    # mandatory status tables
    for name, reqcol in [('full_stack_subcase_status.csv','Mandatory'),('full_stack_component_coverage_results.csv','Mandatory'),('full_stack_value_correctness_results.csv','Required'),('full_stack_acceptance_results.csv','Required')]:
        p=find_file(args.artifact_dir,name)
        if not p: continue
        _,rows=read_csv(p)
        for r in rows:
            if boolv(r.get(reqcol)) and str(r.get('Status','')).upper()!='PASS': failures.append(f"required row failed:{name}:{r.get('SubcaseID') or r.get('ComponentID') or r.get('CheckID') or r.get('RuleID')}")

    # regression zero fail/skip/block
    p=find_file(args.artifact_dir,'full_stack_regression_summary.csv')
    if p:
        _,rows=read_csv(p)
        for r in rows:
            for c in ['FailedTests','SkippedTests','BlockedTests']:
                try:
                    if int(float(r.get(c,0)))!=0: failures.append(f'regression {c}:{r.get("Suite")}')
                except Exception: failures.append(f'bad regression count:{c}:{r.get("Suite")}')

    print(f'Preset: {args.preset}')
    print(f'Checks: {checks}')
    print(f'Failures: {len(failures)}')
    for f in failures[:300]: print('FAIL',f)
    return 0 if not failures else 2

if __name__=='__main__': sys.exit(main())
