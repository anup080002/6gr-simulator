#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,json,re,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent

def main(root:Path)->int:
 rows=list(csv.DictReader((HERE/'current_pucch_static_audit.csv').open(encoding='utf-8-sig')))
 out=[];fail=[]
 for r in rows:
  p=root/r['File'];text=p.read_text(encoding='utf-8',errors='replace') if p.exists() else ''
  try:found=re.search(r['Pattern'],text,re.I|re.M|re.S) is not None
  except re.error as e:found=False;fail.append(f"bad_regex:{r['CheckID']}:{e}")
  expected=r['ExpectedDetected'].strip().lower()=='true'
  result='PASS' if found==expected else 'FAIL'
  if result!='PASS':fail.append(r['CheckID'])
  out.append({'CheckID':r['CheckID'],'Classification':r['Classification'],'File':r['File'],'Detected':found,'ExpectedDetected':expected,'Result':result,'Description':r['Description']})
 print(json.dumps({'checks':len(out),'defects_detected':sum(x['Classification']!='FOUNDATION' and x['Detected'] for x in out),'foundations_detected':sum(x['Classification']=='FOUNDATION' and x['Detected'] for x in out),'failures':fail},indent=2))
 return 0 if not fail else 2
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('repository_root',type=Path);a=ap.parse_args();sys.exit(main(a.repository_root))
