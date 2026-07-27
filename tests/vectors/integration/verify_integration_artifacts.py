#!/usr/bin/env python3
from __future__ import annotations
import csv, hashlib, json, math, sys
from pathlib import Path
try:
    from PIL import Image
except Exception:
    Image=None

out = Path(sys.argv[1]) if len(sys.argv)>1 else Path('artifacts/integration')
contract_root = Path(sys.argv[2]) if len(sys.argv)>2 else Path(__file__).resolve().parent

def sha256(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for c in iter(lambda:f.read(1024*1024),b''): h.update(c)
    return h.hexdigest()

def read_contract(name):
    with (contract_root/name).open(encoding='utf-8',newline='') as f:
        return list(csv.DictReader(f))

def csv_rows(p):
    with p.open(encoding='utf-8-sig',newline='') as f:
        return list(csv.DictReader(f))

checks=[]
def add(name,ok,detail=''):
    checks.append((name,bool(ok),detail))

csv_contract=read_contract('desired_integration_csv_contract.csv')
img_contract=read_contract('desired_integration_image_contract.csv')
for c in csv_contract:
    p=out/c['Artifact']
    add('csv_exists:'+c['Artifact'],p.is_file())
    if not p.is_file(): continue
    try:
        rows=csv_rows(p)
        add('csv_minrows:'+c['Artifact'],len(rows)>=int(c['MinRows']),str(len(rows)))
        cols=set(rows[0].keys()) if rows else set()
        req=[x for x in c['RequiredColumns'].split(';') if x]
        add('csv_columns:'+c['Artifact'],all(x in cols for x in req),','.join(sorted(set(req)-cols)))
        pk=[x for x in c['PrimaryKey'].split(';') if x]
        if rows and pk and all(x in cols for x in pk):
            keys=[tuple(r.get(x,'') for x in pk) for r in rows]
            add('csv_unique:'+c['Artifact'],len(keys)==len(set(keys)),str(len(keys)-len(set(keys))))
        status_bad=[r for r in rows if 'Status' in r and str(r['Status']).upper() not in {'PASS','OK','COMPLETE','CENSORED_COMPLETE','NOT_APPLICABLE'}]
        add('csv_status:'+c['Artifact'],not status_bad,str(len(status_bad)))
    except Exception as e:
        add('csv_parse:'+c['Artifact'],False,repr(e))

# image audit index if available
img_audit={}
audit_path=out/'reports/csv/integration_image_semantic_audit.csv'
if audit_path.is_file():
    try:
        for r in csv_rows(audit_path): img_audit[r.get('Image','')]=r
    except Exception: pass
for c in img_contract:
    p=out/c['Artifact']; src=out/c['SourceCSV']
    add('png_exists:'+c['Artifact'],p.is_file())
    add('png_source_exists:'+c['Artifact'],src.is_file())
    if not p.is_file(): continue
    if Image is None:
        add('png_pillow:'+c['Artifact'],False,'Pillow unavailable')
        continue
    try:
        with Image.open(p) as im:
            im.verify()
        with Image.open(p) as im:
            w,h=im.size
            add('png_dimensions:'+c['Artifact'],w>=int(c['MinWidth']) and h>=int(c['MinHeight']),f'{w}x{h}')
        ar=img_audit.get(c['Artifact']) or img_audit.get(Path(c['Artifact']).name)
        add('png_audit_row:'+c['Artifact'],ar is not None)
        if ar:
            add('png_hash:'+c['Artifact'],ar.get('PNG_SHA256','')==sha256(p))
            if src.is_file(): add('png_source_hash:'+c['Artifact'],ar.get('SourceSHA256','')==sha256(src))
            add('png_semantic_status:'+c['Artifact'],ar.get('Status','').upper() in {'PASS','OK'})
    except Exception as e:
        add('png_decode:'+c['Artifact'],False,repr(e))

# global hard checks
summary_path=out/'reports/csv/integration_test_summary.csv'
if summary_path.is_file():
    try:
        rs=csv_rows(summary_path)
        for r in rs:
            add('no_failed_tests',int(float(r.get('Failed','0'))) == 0)
            add('no_skipped_tests',int(float(r.get('Skipped','0'))) == 0)
            add('no_blocked_tests',int(float(r.get('Blocked','0'))) == 0)
    except Exception as e: add('summary_parse',False,repr(e))
acc_path=out/'reports/csv/integration_acceptance_results.csv'
if acc_path.is_file():
    try:
        rs=csv_rows(acc_path)
        add('acceptance_rule_count',len(rs)>=120,str(len(rs)))
        add('all_acceptance_pass',all(r.get('Status','').upper() in {'PASS','OK','NOT_APPLICABLE'} for r in rs))
    except Exception as e: add('acceptance_parse',False,repr(e))

failed=[x for x in checks if not x[1]]
for name,ok,detail in checks:
    print(('PASS' if ok else 'FAIL'),name,detail)
print(json.dumps({'checks':len(checks),'passed':len(checks)-len(failed),'failed':len(failed),'output':str(out)},indent=2))
sys.exit(0 if not failed else 2)
