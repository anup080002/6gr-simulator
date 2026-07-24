#!/usr/bin/env python3
"""Verify the supplied independent PDSCH/DL-SCH vector pack."""
from __future__ import annotations
import csv, hashlib, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "independent_vector_manifest.json"

def sha256(path: Path) -> str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1<<20), b''): h.update(b)
    return h.hexdigest()

def row_count(path: Path) -> int:
    with path.open(newline='',encoding='utf-8-sig') as f:
        return sum(1 for _ in csv.DictReader(f))

def main() -> int:
    m=json.loads(MANIFEST.read_text(encoding='utf-8'))
    failures=[]
    gen=ROOT/m['generator']
    if not gen.is_file(): failures.append(f"missing_generator:{gen.name}")
    elif sha256(gen)!=m['generator_sha256']: failures.append('generator_sha256_mismatch')
    for item in m['files']:
        p=ROOT/item['name']
        if not p.is_file():
            failures.append(f"missing:{p.name}"); continue
        if sha256(p)!=item['sha256']: failures.append(f"sha256_mismatch:{p.name}")
        if row_count(p)!=int(item['rows']): failures.append(f"row_count_mismatch:{p.name}")
    audit=ROOT/'expected_output_integrity_audit.csv'
    if not audit.is_file(): failures.append('missing:expected_output_integrity_audit.csv')
    elif sha256(audit)!=m['integrity_audit_sha256']: failures.append('integrity_audit_sha256_mismatch')
    print(f"PDSCH vector-pack verification: {len(m['files'])-sum(x.startswith(('missing:','sha256_mismatch:','row_count_mismatch:')) for x in failures)} files checked, {len(failures)} failures")
    for failure in failures: print('FAIL',failure)
    return 0 if not failures else 2

if __name__=='__main__':
    raise SystemExit(main())
