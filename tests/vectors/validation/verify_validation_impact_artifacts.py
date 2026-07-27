#!/usr/bin/env python3
from __future__ import annotations
import csv, hashlib, json, shutil, sys, tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageStat

PACK=Path(__file__).resolve().parent
CSV_CONTRACT=PACK/"desired_validation_impact_csv_contract.csv"
IMG_CONTRACT=PACK/"desired_validation_impact_image_contract.csv"
AUDIT_NAME="validation_impact_image_semantic_audit.csv"

def read_csv(path):
    with open(path,encoding="utf-8-sig",newline="") as f:return list(csv.DictReader(f))
def sha(path):
    h=hashlib.sha256()
    with open(path,"rb") as f:
        for c in iter(lambda:f.read(1024*1024),b""):h.update(c)
    return h.hexdigest()
def write_csv(path,fields,rows):
    path.parent.mkdir(parents=True,exist_ok=True)
    with open(path,"w",encoding="utf-8",newline="") as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(rows)

def verify(out):
    out=Path(out); fail=[]; checks=0
    def ck(c,m):
        nonlocal checks
        checks+=1
        if not c:fail.append(m)
    cc=read_csv(CSV_CONTRACT)
    for c in cc:
        p=out/c["FileName"];ck(p.is_file(),"missing_csv:"+c["FileName"])
        if not p.is_file():continue
        rr=read_csv(p); req=c["RequiredColumns"].split(";")
        fields=set(rr[0].keys()) if rr else set()
        ck(set(req).issubset(fields),"columns:"+c["FileName"])
        ck(len(rr)>=int(c["MinimumRows"]),"rows:"+c["FileName"])
        for r in rr:
            for key,val in r.items():
                if key.lower()=="status":
                    ck(str(val).upper() not in {"FAIL","FAILED","BLOCKED","SKIPPED_REQUIRED","INCOMPLETE"},"status:"+c["FileName"])
    audit_path=out/AUDIT_NAME
    audit={r["ImageFile"]:r for r in read_csv(audit_path)} if audit_path.is_file() else {}
    ic=read_csv(IMG_CONTRACT)
    for c in ic:
        p=out/c["ImageFile"];ck(p.is_file(),"missing_png:"+c["ImageFile"])
        if not p.is_file():continue
        try:
            im=Image.open(p);im.load()
            ck(im.width>=int(c["MinimumWidth"]) and im.height>=int(c["MinimumHeight"]),"dimensions:"+c["ImageFile"])
            stat=ImageStat.Stat(im.convert("L"));ck(stat.var[0]>0,"blank:"+c["ImageFile"])
        except Exception as e:
            ck(False,"decode:"+c["ImageFile"]+":"+str(e));continue
        ck(c["ImageFile"] in audit,"audit_row:"+c["ImageFile"])
        if c["ImageFile"] in audit:
            a=audit[c["ImageFile"]]
            src=out/c["SourceCSV"]
            ck(a.get("SourceCSV")==c["SourceCSV"],"audit_source:"+c["ImageFile"])
            ck(src.is_file() and a.get("SourceCSVSHA256")==sha(src),"source_hash:"+c["ImageFile"])
            ck(a.get("ImageSHA256")==sha(p),"png_hash:"+c["ImageFile"])
            ck(int(float(a.get("Width","0"))) == im.width and int(float(a.get("Height","0")))==im.height,"audit_dimensions:"+c["ImageFile"])
            ck(int(float(a.get("Axes","0")))>=int(c["MinimumAxes"]),"axes:"+c["ImageFile"])
            ck(int(float(a.get("Series","0")))>=int(c["MinimumSeries"]),"series:"+c["ImageFile"])
            ck(int(float(a.get("FinitePoints","0")))>=int(c["MinimumFinitePoints"]),"finite_points:"+c["ImageFile"])
            ck(a.get("ActualTitle")==c["ExpectedTitle"],"title:"+c["ImageFile"])
            ck(a.get("ActualXLabel")==c["ExpectedXLabel"],"xlabel:"+c["ImageFile"])
            ck(a.get("ActualYLabel")==c["ExpectedYLabel"],"ylabel:"+c["ImageFile"])
    result={"Checks":checks,"Passed":checks-len(fail),"Failed":len(fail),"Failures":fail}
    print(json.dumps(result,indent=2));return 0 if not fail else 2

def make_synthetic(out):
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    contracts=read_csv(CSV_CONTRACT)
    for c in contracts:
        fields=c["RequiredColumns"].split(";"); n=int(c["MinimumRows"])
        rr=[]
        for i in range(n):
            row={f:("PASS" if f=="Status" else str(i+1)) for f in fields}
            if "PointStatus" in row:row["PointStatus"]="COMPLETE"
            if "StopReason" in row:row["StopReason"]="MIN_ERRORS_AND_CI_MET"
            if "ExpectedOutcome" in row:row["ExpectedOutcome"]="EXECUTE"
            if "ActualOutcome" in row:row["ActualOutcome"]="EXECUTE"
            if "Executed" in row:row["Executed"]="true"
            if "Passed" in row:row["Passed"]="true"
            if "Skipped" in row:row["Skipped"]="false"
            if "Blocked" in row:row["Blocked"]="false"
            rr.append(row)
        write_csv(out/c["FileName"],fields,rr)
    audit_rows=[]
    for c in read_csv(IMG_CONTRACT):
        p=out/c["ImageFile"];im=Image.new("RGB",(1000,700),"white");d=ImageDraw.Draw(im)
        d.rectangle((60,60,940,640),outline="black",width=3)
        for i in range(10):d.line((80+i*80,600-i*40,120+i*80,560-i*35),fill="black",width=2)
        d.text((80,80),c["ExpectedTitle"],fill="black");im.save(p)
        src=out/c["SourceCSV"]
        audit_rows.append({
            "ImageFile":c["ImageFile"],"SourceCSV":c["SourceCSV"],"SourceCSVSHA256":sha(src),
            "ImageSHA256":sha(p),"Width":1000,"Height":700,"Axes":1,"Series":2,
            "FinitePoints":max(10,int(c["MinimumFinitePoints"])),"ActualTitle":c["ExpectedTitle"],
            "ActualXLabel":c["ExpectedXLabel"],"ActualYLabel":c["ExpectedYLabel"],"Status":"PASS"})
    audit_contract=next(c for c in contracts if c["FileName"]==AUDIT_NAME)
    fields=audit_contract["RequiredColumns"].split(";")
    normalized=[]
    for a in audit_rows:normalized.append({f:a.get(f,"PASS" if f=="Status" else "") for f in fields})
    write_csv(out/AUDIT_NAME,fields,normalized)

if __name__=="__main__":
    if len(sys.argv)>1 and sys.argv[1]=="--self-test":
        td=Path(tempfile.mkdtemp(prefix="sixgr_validation_artifact_test_"))
        valid=td/"valid";make_synthetic(valid);ec1=verify(valid)
        ar=read_csv(valid/AUDIT_NAME);ar[0]["ImageSHA256"]="0"*64
        write_csv(valid/AUDIT_NAME,list(ar[0].keys()),ar)
        ec2=verify(valid)
        print(json.dumps({"ValidExit":ec1,"CorruptExit":ec2},indent=2))
        shutil.rmtree(td,ignore_errors=True)
        sys.exit(0 if ec1==0 and ec2==2 else 2)
    if len(sys.argv)<2:
        print("usage: verifier.py OUTPUT_DIR or --self-test",file=sys.stderr);sys.exit(2)
    sys.exit(verify(sys.argv[1]))
