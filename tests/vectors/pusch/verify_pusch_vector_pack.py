#!/usr/bin/env python3
"""Verify the PUSCH independent-vector manifest and CSV row counts."""
from __future__ import annotations
import csv, hashlib, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
def sha(path):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(1024*1024),b""):h.update(b)
    return h.hexdigest()
def rows(path):
    with path.open(newline="",encoding="utf-8-sig") as f:return max(0,sum(1 for _ in csv.reader(f))-1)
def main():
    m=json.loads((ROOT/"independent_vector_manifest.json").read_text(encoding="utf-8"))
    failures=[]
    for item in m["Files"]:
        p=ROOT/item["FileName"]
        if not p.is_file():failures.append(f"missing:{p.name}");continue
        if sha(p)!=item["SHA256"]:failures.append(f"hash:{p.name}")
        if rows(p)!=int(item["Rows"]):failures.append(f"rows:{p.name}")
    if m.get("GeneratorSHA256")!=sha(ROOT/m["Generator"]):failures.append("generator_hash")
    print(f"files={len(m['Files'])} failures={len(failures)}")
    for x in failures:print(x)
    return 2 if failures else 0
if __name__=="__main__":raise SystemExit(main())
