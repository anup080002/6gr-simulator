#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,hashlib,json,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent

def digest(p):
 h=hashlib.sha256();
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def rows(p):
 with p.open(newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))
def main():
 m=json.loads((HERE/'independent_vector_manifest.json').read_text());fail=[]
 for x in m['Files']:
  p=HERE/x['FileName']
  if not p.exists():fail.append('missing:'+x['FileName']);continue
  if digest(p)!=x['SHA256']:fail.append('sha256:'+x['FileName'])
  if len(rows(p))!=int(x['RowCount']):fail.append('rowcount:'+x['FileName'])
 if not m.get('GeneratedWithoutMATLAB'):fail.append('manifest_not_independent')
 print(json.dumps({'files':len(m['Files']),'failures':fail},indent=2))
 return 0 if not fail else 2
if __name__=='__main__':raise SystemExit(main())
