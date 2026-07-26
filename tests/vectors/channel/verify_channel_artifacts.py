#!/usr/bin/env python3
from __future__ import annotations
import csv, hashlib, json, sys
from pathlib import Path
from PIL import Image, ImageStat
def rows(p):
    with open(p,encoding="utf-8-sig",newline="") as f: return list(csv.DictReader(f))
def sha(p):
    h=hashlib.sha256()
    with open(p,"rb") as f:
        for c in iter(lambda:f.read(1024*1024),b""): h.update(c)
    return h.hexdigest()
def truth(v): return str(v).strip().lower() in {"1","true","yes","pass"}
root=Path(sys.argv[1]); pack=Path(__file__).resolve().parent
fail=[]; checks=0
def ck(c,m):
    global checks
    checks+=1
    if c: print("PASS",m)
    else: print("FAIL",m); fail.append(m)
loaded={}
for c in rows(pack/"desired_channel_csv_contract.csv"):
    p=root/c["FileName"]; ck(p.is_file(),"csv_exists:"+c["FileName"])
    if not p.is_file(): continue
    rr=rows(p); loaded[c["FileName"]]=rr
    got=set(rr[0].keys()) if rr else set()
    ck(set(c["RequiredColumns"].split(";")).issubset(got),"csv_columns:"+c["FileName"])
    ck(len(rr)>=int(c["MinimumRows"]),"csv_rows:"+c["FileName"])
    if rr and "Status" in rr[0]: ck(all(str(r["Status"]).upper()=="PASS" for r in rr),"csv_status:"+c["FileName"])
if "channel_profile_resolution.csv" in loaded:
    ck(all(r["ExpectedOutcome"]==r["ActualOutcome"] for r in loaded["channel_profile_resolution.csv"]),"capability_expected_actual")
if "channel_geometry_provenance.csv" in loaded:
    banned={"CONFIGURED","RECONSTRUCTED","MODEL_BACKFILL","CONFIGURED_ORACLE"}
    mandatory={"Distance3D_m","PropagationDelay_s","SignedDoppler_Hz","Pathloss_dB","LOSState"}
    rr=[r for r in loaded["channel_geometry_provenance.csv"] if r["FieldName"] in mandatory]
    ck(bool(rr) and all(truth(r["Observed"]) and r["ProvenanceClass"].upper() not in banned for r in rr),"observed_geometry_provenance")
if "channel_pathloss_trials.csv" in loaded:
    ck(all(abs(float(r["Error_dB"]))<=1e-6 for r in loaded["channel_pathloss_trials.csv"]),"pathloss_exact")
if "channel_o2i_trials.csv" in loaded:
    ck(all(abs(float(r["Error_dB"]))<=1e-6 for r in loaded["channel_o2i_trials.csv"]),"o2i_exact")
if "channel_oxygen_absorption.csv" in loaded:
    ck(all(abs(float(r["Error_dB"]))<=1e-6 for r in loaded["channel_oxygen_absorption.csv"]),"oxygen_exact")
if "channel_doppler_phase.csv" in loaded:
    ck(all(abs(float(r["ExpectedDoppler_Hz"])-float(r["ActualDoppler_Hz"]))<=1e-6 and abs(float(r["ExpectedPhase_rad"])-float(r["ActualPhase_rad"]))<=1e-5 for r in loaded["channel_doppler_phase.csv"]),"doppler_phase_exact")
if "channel_absolute_power_ledger.csv" in loaded:
    ck(all(abs(float(r["Error_dB"]))<=0.05 for r in loaded["channel_absolute_power_ledger.csv"]),"absolute_power_reconciliation")
if "channel_noise_ledger.csv" in loaded:
    ck(all(abs(float(r["Error_dB"]))<=0.05 for r in loaded["channel_noise_ledger.csv"]),"noise_reconciliation")
if "channel_raytracing_contract.csv" in loaded:
    ck(all(truth(r["Reproducible"]) and len(r["SceneSHA256"])==64 and len(r["ResultSHA256"])==64 for r in loaded["channel_raytracing_contract.csv"]),"raytracing_contract")
if "channel_negative_tests.csv" in loaded:
    ck(all(r["ExpectedError"]==r["ActualError"] and not truth(r["WaveformGenerated"]) and not truth(r["StateMutation"]) for r in loaded["channel_negative_tests.csv"]),"negative_fail_closed")
if "channel_test_summary.csv" in loaded:
    ck(all(int(float(r["Failed"]))==0 and int(float(r["Skipped"]))==0 and int(float(r["Blocked"]))==0 and int(float(r["IncompletePoints"]))==0 for r in loaded["channel_test_summary.csv"]),"mandatory_tests_complete")
audit={r["ImageFile"]:r for r in loaded.get("channel_image_semantic_audit.csv",[])}
for c in rows(pack/"desired_channel_image_contract.csv"):
    p=root/c["ImageFile"]; ck(p.is_file(),"png_exists:"+c["ImageFile"])
    if not p.is_file(): continue
    try:
        im=Image.open(p).convert("RGB"); w,h=im.size; nonblank=max(ImageStat.Stat(im).var)>0.1
    except Exception: w=h=0; nonblank=False
    ck(w>=int(c["MinimumWidth"]) and h>=int(c["MinimumHeight"]),"png_dimensions:"+c["ImageFile"])
    ck(nonblank,"png_nonblank:"+c["ImageFile"])
    a=audit.get(c["ImageFile"]); ck(a is not None,"png_audit_row:"+c["ImageFile"])
    if a:
        ck(a["SourceCSV"]==c["SourceCSV"] and a["SourceCSVSHA256"]==sha(root/c["SourceCSV"]),"source_hash:"+c["ImageFile"])
        ck(a["PNGSHA256"]==sha(p),"png_hash:"+c["ImageFile"])
        ck(int(a["Width"])==w and int(a["Height"])==h,"png_metadata:"+c["ImageFile"])
        ck(c["ExpectedTitle"].lower() in a["Title"].lower(),"png_title:"+c["ImageFile"])
        ck(int(a["AxesCount"])>=int(c["MinimumAxes"]) and int(a["SeriesCount"])>=int(c["MinimumSeries"]) and int(a["FinitePointCount"])>=int(c["MinimumFinitePoints"]),"png_semantics:"+c["ImageFile"])
print(json.dumps({"Checks":checks,"Passed":checks-len(fail),"Failed":len(fail),"Failures":fail},indent=2))
sys.exit(0 if not fail else 2)
