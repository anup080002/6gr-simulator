#!/usr/bin/env python3
from __future__ import annotations
import argparse, csv, hashlib, json, math, sys, tempfile
from pathlib import Path
try:
    from PIL import Image, ImageDraw
except ImportError as exc:
    raise SystemExit("Pillow is required") from exc

HERE=Path(__file__).resolve().parent

def truth(v): return str(v).strip().upper() in {"1","TRUE","YES","PASS"}
def finite(v):
    try: x=float(str(v).strip())
    except Exception: return None
    return x if math.isfinite(x) else None
def integer(v):
    x=finite(v)
    return int(round(x)) if x is not None and abs(x-round(x))<1e-9 else None
def sha256(path):
    h=hashlib.sha256()
    with Path(path).open("rb") as f:
        for b in iter(lambda:f.read(1024*1024),b""): h.update(b)
    return h.hexdigest()
def contracts(name):
    with (HERE/name).open(newline="",encoding="utf-8-sig") as f: return list(csv.DictReader(f))
def read_csv(path):
    with Path(path).open(newline="",encoding="utf-8-sig") as f: raw=list(csv.reader(f))
    if not raw:return [],[],["empty"]
    h=raw[0];err=[];rows=[]
    if len(h)!=len(set(h)):err.append("duplicate_header")
    for i,r in enumerate(raw[1:],2):
        if len(r)!=len(h):err.append(f"nonrectangular:{i}")
        else:rows.append(dict(zip(h,r)))
    if not rows:err.append("no_rows")
    return h,rows,err
def source_hash(root,names):
    h=hashlib.sha256()
    for name in sorted(n for n in names if n):
        p=Path(root)/name
        if not p.exists():return ""
        h.update(name.encode());h.update(sha256(p).encode())
    return h.hexdigest()

def verify(root):
    root=Path(root);fail=[];parsed={}
    cc=contracts("desired_initial_access_impact_csv_contract.csv")
    ic=contracts("desired_initial_access_impact_image_contract.csv")
    for c in cc:
        p=root/c["FileName"]; req=[x for x in c["RequiredColumns"].split("|") if x]
        if not p.exists():fail.append("missing_csv:"+p.name);continue
        h,rs,err=read_csv(p);parsed[p.name]=rs;fail.extend(p.name+":"+e for e in err)
        miss=[x for x in req if x not in h]
        if miss:fail.append(p.name+":missing_columns:"+",".join(miss));continue
        if len(rs)<int(c["MinRows"]):fail.append(p.name+":too_few_rows")
        keys=[x for x in c["PrimaryKey"].split("|") if x];seen=set()
        for i,r in enumerate(rs,2):
            k=tuple(r.get(x,"") for x in keys)
            if k in seen:fail.append(p.name+":duplicate_key:"+repr(k))
            seen.add(k)
            if "Status" in r and r["Status"].strip().upper()!="PASS":fail.append(p.name+f":nonpass:{i}")

    matrix=contracts("initial_access_impact_experiment_matrix.csv")
    expected_ids={r["ExperimentID"] for r in matrix}
    raw=parsed.get("initial_access_impact_raw_trials.csv",[])
    observed_ids={r.get("ExperimentID","") for r in raw}
    missing_ids=expected_ids-observed_ids
    if missing_ids:fail.append("missing_experiment_ids:"+str(len(missing_ids)))
    if len(expected_ids)!=720:fail.append("matrix_not_720")

    # Pairing invariant: baseline/treatment share all declared pair identifiers except factor value.
    by_pair={}
    for r in matrix:by_pair.setdefault(r["PairID"],[]).append(r)
    for pid,rr in by_pair.items():
        if {r["Variant"] for r in rr}!={"baseline","treatment"}:fail.append("bad_pair_variants:"+pid)
        keys=["Seed","TrialSetID","PayloadSetID","ChannelRealizationID","NoiseRealizationID","InitialStateID","Factor"]
        for k in keys:
            if len({r[k] for r in rr})!=1:fail.append("pairing_mismatch:"+pid+":"+k)

    # Raw trial dependency/proxy checks.
    for i,r in enumerate(raw,2):
        if r.get("DependencyState") in {"proxy","synthetic_substitute","configured_oracle"}:
            fail.append(f"proxy_dependency:{i}")
        for field in ("Latency_ms","Runtime_ms","PeakMemory_MB"):
            if finite(r.get(field)) is None:fail.append(f"raw_nonfinite:{field}:{i}")

    for i,r in enumerate(parsed.get("initial_access_impact_operating_points.csv",[]),2):
        if truth(r.get("Incomplete")):fail.append(f"impact_incomplete:{i}")
        for field in ("Trials","Errors","Probability","CILower","CIUpper","ConfidenceLevel"):
            if finite(r.get(field)) is None:fail.append(f"op_nonfinite:{field}:{i}")
        lo=finite(r.get("CILower"));hi=finite(r.get("CIUpper"));p=finite(r.get("Probability"))
        if None not in (lo,hi,p) and not (0<=lo<=p<=hi<=1):fail.append(f"op_ci_order:{i}")

    for i,r in enumerate(parsed.get("initial_access_impact_pairwise_effects.csv",[]),2):
        for field in ("BaselineValue","TreatmentValue","Effect","CILower","CIUpper","PValue","AdjustedPValue","EffectSize","PracticalThreshold"):
            if finite(r.get(field)) is None:fail.append(f"effect_nonfinite:{field}:{i}")
        b=finite(r.get("BaselineValue"));t=finite(r.get("TreatmentValue"));e=finite(r.get("Effect"))
        if None not in (b,t,e) and abs((t-b)-e)>1e-9:fail.append(f"effect_sign:{i}")
        if r.get("Conclusion") not in {"beneficial","harmful","equivalent","no_detectable_effect","inconclusive","hard_pass","hard_fail"}:
            fail.append(f"effect_conclusion:{i}")

    rule_rows=parsed.get("initial_access_impact_rule_evaluation.csv",[])
    expected_rules={r["RuleID"] for r in contracts("initial_access_impact_acceptance_rules.csv")}
    got_rules={r.get("RuleID","") for r in rule_rows}
    if expected_rules-got_rules:fail.append("missing_rules:"+str(len(expected_rules-got_rules)))
    for i,r in enumerate(rule_rows,2):
        if r.get("Conclusion") not in {"PASS","pass","hard_pass","statistically_valid","diagnostic_valid"}:
            fail.append(f"rule_not_pass:{i}")
        if integer(r.get("EvidenceRows")) is None or integer(r.get("EvidenceRows"))<=0:fail.append(f"rule_no_evidence:{i}")

    # Domain-specific required fields finite.
    domain_files={
        "initial_access_impact_ssb.csv":["AcquisitionProbability","AcquisitionLatency_ms","BCHBLER","Runtime_ms"],
        "initial_access_impact_type0_sib1.csv":["PDCCHDetectionProbability","SIB1BLER","Latency_ms","OverheadRE"],
        "initial_access_impact_prach.csv":["DetectionProbability","FalseAlarmProbability","TimingRMSE_samples","CollisionProbability"],
        "initial_access_impact_beam.csv":["ReselectionLatency_ms","WrongBeamRate","AccessSuccessProbability"],
        "initial_access_impact_power.csv":["AppliedPower_dBm","ClippingProbability","EnergyPerAccess_mJ"],
        "initial_access_impact_contention.csv":["CollisionProbability","CaptureProbability","MeanAttempts","P95Latency_ms"],
        "initial_access_impact_rrc.csv":["RequestBLER","SetupBLER","SetupCompleteBLER","ConnectedProbability","Latency_ms"],
        "initial_access_impact_runtime.csv":["Runtime_ms","PeakMemory_MB","WaveformSamples"],
    }
    for fn,fields in domain_files.items():
        for i,r in enumerate(parsed.get(fn,[]),2):
            for field in fields:
                if finite(r.get(field)) is None:fail.append(f"{fn}:nonfinite:{field}:{i}")

    summaries=parsed.get("initial_access_impact_summary.csv",[])
    if len({r.get("FamilyID","") for r in summaries})<60:fail.append("summary_missing_families")
    for i,r in enumerate(summaries,2):
        if integer(r.get("ExperimentsCompleted"))!=integer(r.get("ExperimentsExpected")):fail.append(f"summary_incomplete:{i}")
        if not truth(r.get("PairsComplete")) or not truth(r.get("HardRulesPassed")):fail.append(f"summary_pair_or_hard:{i}")
        if r.get("DependencyStatus") not in {"ready","implemented","complete"}:fail.append(f"summary_dependency:{i}")

    # Images.
    audits={r.get("ImageFile",""):r for r in parsed.get("initial_access_impact_image_semantic_audit.csv",[])}
    for c in ic:
        name=c["ImageFile"];p=root/name
        if not p.exists():fail.append("missing_png:"+name);continue
        try:
            with Image.open(p) as im:
                im.load();w,h=im.size;ext=im.convert("L").getextrema()
                if w<int(c["MinWidth"]) or h<int(c["MinHeight"]):fail.append("png_dimensions:"+name)
                if ext[0]==ext[1]:fail.append("png_blank:"+name)
        except Exception as exc:
            fail.append("png_decode:"+name+":"+type(exc).__name__);continue
        a=audits.get(name)
        if not a:fail.append("missing_image_audit:"+name);continue
        if a.get("PNG_SHA256")!=sha256(p):fail.append("png_hash_mismatch:"+name)
        src=[x for x in c["SourceCSVFiles"].split("|") if x]
        if a.get("SourceCSVSHA256")!=source_hash(root,src):fail.append("source_hash_mismatch:"+name)
        if integer(a.get("Width"))!=w or integer(a.get("Height"))!=h:fail.append("recorded_dimensions:"+name)
        if integer(a.get("AxesCount")) is None or integer(a["AxesCount"])<int(c["MinAxes"]):fail.append("axes:"+name)
        if integer(a.get("SeriesCount")) is None or integer(a["SeriesCount"])<int(c["MinSeries"]):fail.append("series:"+name)
        if integer(a.get("FinitePointCount")) is None or integer(a["FinitePointCount"])<int(c["MinFinitePoints"]):fail.append("points:"+name)
        if not truth(a.get("SemanticCheck")):fail.append("semantic:"+name)
    return fail

def default_value(c,i):
    low=c.lower()
    if c=="Status":return "PASS"
    if c in {"Success","PairsComplete","HardRulesPassed","SemanticCheck"}:return "true"
    if "sha256" in low or low.endswith("digest"):return "0"*64
    if c=="Variant":return "baseline" if i%2==0 else "treatment"
    if c=="Wave":return "A"
    if c=="DependencyState" or c=="DependencyStatus":return "ready"
    if c=="Incomplete":return "false"
    if c=="StopReason":return "target_met"
    if c=="ConfidenceLevel":return "0.95"
    if c in {"Trials","EvidenceRows","ExperimentsExpected","ExperimentsCompleted"}:return "100"
    if c=="Errors":return "1"
    if c in {"Probability","CILower","CIUpper","PValue","AdjustedPValue","EffectSize","PracticalThreshold","BaselineValue","TreatmentValue","Effect"}:
        vals={"Probability":"0.5","CILower":"0.4","CIUpper":"0.6","PValue":"0.01","AdjustedPValue":"0.02","EffectSize":"0.5","PracticalThreshold":"0.1","BaselineValue":"1","TreatmentValue":"2","Effect":"1"}
        return vals[c]
    if c=="Conclusion":return "hard_pass"
    if c=="StatisticalConclusion":return "statistically_valid"
    if c=="PracticalConclusion":return "beneficial"
    if c=="RuleClass":return "HARD"
    if c=="Operator":return "equals"
    if c=="Threshold":return "PASS"
    if c in {"RequestBLER","SetupBLER","SetupCompleteBLER","BCHBLER","SIB1BLER","FalseAlarmProbability","CollisionProbability","WrongBeamRate","ClippingProbability"}:return "0.01"
    if c in {"AcquisitionProbability","PDCCHDetectionProbability","DetectionProbability","AccessSuccessProbability","ConnectedProbability","CaptureProbability"}:return "0.99"
    if c=="ArtifactDigest":return "0"*64
    return str(i+1)

def build_synthetic(root):
    root.mkdir(parents=True,exist_ok=True)
    cc=contracts("desired_initial_access_impact_csv_contract.csv")
    matrix=contracts("initial_access_impact_experiment_matrix.csv")
    rules=contracts("initial_access_impact_acceptance_rules.csv")
    for c in cc:
        if c["FileName"]=="initial_access_impact_image_semantic_audit.csv":continue
        cols=[x for x in c["RequiredColumns"].split("|") if x]
        count=int(c["MinRows"]);rs=[]
        for i in range(count):
            r={x:default_value(x,i) for x in cols}
            for k in c["PrimaryKey"].split("|"):
                if k:r[k]=f"{k}_{i}"
            fn=c["FileName"]
            if fn=="initial_access_impact_raw_trials.csv":
                m=matrix[i%len(matrix)]
                r.update({k:m[k] for k in ["ExperimentID","FamilyID","PairID","Variant","Seed","Factor","FactorValue","Wave","DependencyState"]})
                r["TrialID"]=f"trial{i}";r["Status"]="PASS";r["Success"]="true"
            elif fn=="initial_access_impact_rule_evaluation.csv":
                q=rules[i%len(rules)]
                r.update({"RuleID":q["RuleID"],"FamilyID":q["FamilyID"],"RuleClass":q["RuleClass"],"Metric":q["Metric"],"Operator":q["Operator"],"Threshold":q["Threshold"],"Observed":"PASS","EvidenceRows":"10","Conclusion":"hard_pass","Status":"PASS"})
            elif fn=="initial_access_impact_pairwise_effects.csv":
                r["BaselineValue"]="1";r["TreatmentValue"]="2";r["Effect"]="1";r["CILower"]="0.5";r["CIUpper"]="1.5";r["PValue"]="0.01";r["AdjustedPValue"]="0.02";r["EffectSize"]="0.5";r["PracticalThreshold"]="0.1";r["Conclusion"]="beneficial"
            elif fn=="initial_access_impact_operating_points.csv":
                r["Trials"]="100";r["Errors"]="10";r["Probability"]="0.1";r["CILower"]="0.05";r["CIUpper"]="0.18";r["ConfidenceLevel"]="0.95";r["Incomplete"]="false"
            elif fn=="initial_access_impact_summary.csv":
                r["FamilyID"]=f"F{(i%60)+1:02d}";r["ExperimentsExpected"]="12";r["ExperimentsCompleted"]="12";r["PairsComplete"]="true";r["HardRulesPassed"]="true";r["DependencyStatus"]="ready"
            rs.append(r)
        with (root/c["FileName"]).open("w",newline="",encoding="utf-8") as f:
            w=csv.DictWriter(f,fieldnames=cols);w.writeheader();w.writerows(rs)
    ic=contracts("desired_initial_access_impact_image_contract.csv");meta=[]
    for i,c in enumerate(ic):
        p=root/c["ImageFile"];im=Image.new("RGB",(1000,700),"white");d=ImageDraw.Draw(im)
        d.rectangle((50,50,950,650),outline="black",width=3);d.line((80,620,900,100+i*2),fill="black",width=4);d.text((80,80),c["ExpectedTitleTokens"],fill="black");im.save(p)
        src=[x for x in c["SourceCSVFiles"].split("|") if x]
        meta.append({"ImageFile":c["ImageFile"],"SourceCSVFiles":c["SourceCSVFiles"],"SourceCSVSHA256":source_hash(root,src),"PNG_SHA256":sha256(p),"Width":1000,"Height":700,"AxesCount":1,"SeriesCount":1,"FinitePointCount":100,"Title":c["ExpectedTitleTokens"],"XLabel":c["ExpectedXLabelTokens"],"YLabel":c["ExpectedYLabelTokens"],"SemanticCheck":"true","Status":"PASS"})
    cols=[x for x in next(c for c in cc if c["FileName"]=="initial_access_impact_image_semantic_audit.csv")["RequiredColumns"].split("|") if x]
    with (root/"initial_access_impact_image_semantic_audit.csv").open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=cols);w.writeheader();w.writerows(meta)

def main():
    p=argparse.ArgumentParser();p.add_argument("root",nargs="?");p.add_argument("--self-test",action="store_true");a=p.parse_args()
    if a.self_test:
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);build_synthetic(root);valid=verify(root)
            target=root/contracts("desired_initial_access_impact_image_contract.csv")[0]["ImageFile"]
            with Image.open(target) as im:
                d=ImageDraw.Draw(im);d.rectangle((0,0,20,20),fill="red");im.save(target)
            corrupt=verify(root)
            result={"valid_failures":valid,"corrupt_failure_count":len(corrupt),"corruption_detected":any("png_hash_mismatch" in x for x in corrupt)}
            print(json.dumps(result,indent=2));sys.exit(0 if not valid and result["corruption_detected"] else 2)
    if not a.root:p.error("root required unless --self-test")
    fail=verify(Path(a.root));print(json.dumps({"root":a.root,"failure_count":len(fail),"failures":fail},indent=2));sys.exit(0 if not fail else 2)
if __name__=="__main__":main()
