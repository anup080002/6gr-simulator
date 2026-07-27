#!/usr/bin/env python3
from __future__ import annotations
import csv, hashlib, json, math, sys
from pathlib import Path
from statistics import NormalDist
try:
    from scipy.stats import beta
except Exception:
    beta = None

root = Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parent
fail=[]; checks=0
def ck(cond,msg):
    global checks
    checks += 1
    if not cond: fail.append(msg)
def rows(name):
    with open(root/name,encoding="utf-8-sig",newline="") as f:
        return list(csv.DictReader(f))
def sha(path):
    h=hashlib.sha256()
    with open(path,"rb") as f:
        for c in iter(lambda:f.read(1024*1024),b""): h.update(c)
    return h.hexdigest()
def wilson(k,n,cl):
    z=NormalDist().inv_cdf(1-(1-cl)/2); p=k/n; den=1+z*z/n
    c=(p+z*z/(2*n))/den
    h=z*math.sqrt(p*(1-p)/n+z*z/(4*n*n))/den
    return max(0,c-h),min(1,c+h)
def cp_two(k,n,cl):
    if beta is None: return None
    a=1-cl
    lo=0.0 if k==0 else float(beta.ppf(a/2,k,n-k+1))
    hi=1.0 if k==n else float(beta.ppf(1-a/2,k+1,n-k))
    return lo,hi
def cp_upper(k,n,cl):
    if beta is None: return None
    return 1.0 if k==n else float(beta.ppf(cl,k+1,n-k))
def close(a,b,tol=2e-12):
    return abs(a-b)<=tol*max(1,abs(a),abs(b))

manifest=json.loads((root/"independent_vector_manifest.json").read_text(encoding="utf-8"))
for a in manifest["Artifacts"]:
    p=root/a["FileName"]; ck(p.is_file(),"missing:"+a["FileName"])
    if p.is_file():
        ck(sha(p)==a["SHA256"],"hash:"+a["FileName"])
        ck(len(rows(a["FileName"]))==a["Rows"],"rows:"+a["FileName"])

for r in rows("validation_binomial_interval_test_vectors.csv"):
    k=int(r["SuccessCount"]); n=int(r["TrialCount"]); cl=float(r["ConfidenceLevel"])
    if r["Method"]=="WILSON_TWO_SIDED": lo,hi=wilson(k,n,cl)
    else:
        got=cp_two(k,n,cl); ck(got is not None,"scipy_required_cp_two"); 
        if got is None: continue
        lo,hi=got
    ck(close(lo,float(r["ExpectedLower"])),"interval_lo:"+r["VectorID"])
    ck(close(hi,float(r["ExpectedUpper"])),"interval_hi:"+r["VectorID"])

for r in rows("validation_zero_error_upper_bound_vectors.csv"):
    got=cp_upper(0,int(r["TrialCount"]),float(r["ConfidenceLevel"]))
    ck(got is not None,"scipy_required_cp_upper")
    if got is not None: ck(close(got,float(r["ExpectedUpper"])),"zero_upper:"+r["VectorID"])

valid_status=set(json.loads(json.dumps(__import__("yaml").safe_load((root/"validation_enums.yaml").read_text())))["PointStatus"])
valid_reason=set(__import__("yaml").safe_load((root/"validation_enums.yaml").read_text())["StopReason"])
for r in rows("validation_status_stop_reason_vectors.csv"):
    if r["ExpectedAction"]=="ACCEPT_CANONICAL" and r["TokenKind"]=="POINT_STATUS":
        ck(r["InputToken"] in valid_status,"status_enum:"+r["InputToken"])
    if r["ExpectedAction"]=="ACCEPT_CANONICAL" and r["TokenKind"]=="STOP_REASON":
        ck(r["InputToken"] in valid_reason,"reason_enum:"+r["InputToken"])

for r in rows("validation_sequential_stopping_vectors.csv"):
    ck(r["ExpectedStatus"] in valid_status,"seq_status:"+r["VectorID"])
    ck(r["ExpectedStopReason"] in valid_reason,"seq_reason:"+r["VectorID"])
    ck(float(r["LookConfidenceLevel"])>=float(r["NominalConfidenceLevel"]),"seq_alpha:"+r["VectorID"])

for r in rows("validation_provenance_dag_vectors.csv"):
    allowed=r["ExpectedAllowed"].lower()=="true"
    same_root=r["ExpectedRootID"]==r["AppliedRootID"]
    if same_root and r["ExpectedProvenance"] not in {"OBSERVED_RUNTIME_STATE","DERIVED_FROM_OBSERVED_RUNTIME_STATE","DECODED_RECEIVER_STATE"}:
        ck(not allowed,"prov_circular:"+r["CaseID"])

for r in rows("validation_oracle_registry_vectors.csv"):
    qualifying=r["OracleType"] in {"PURE_MATH","FROZEN_EXTERNAL_VECTOR","ANALYTICAL_INVARIANT","STATISTICAL_DISTRIBUTION"}
    ck((r["ExpectedQualifiesForMandatoryGate"].lower()=="true")==qualifying,"oracle:"+r["OracleID"])

for r in rows("validation_multiseed_aggregation_vectors.csv"):
    if r["ExpectedStatus"]=="PASS":
        ck(int(r["UniqueDrops"])>=int(r["RequiredMinDrops"]),"drops:"+r["AggregationID"])
        ck(int(r["UniqueSeeds"])==int(r["InputRows"]),"seeds:"+r["AggregationID"])

for r in rows("validation_parallel_merge_expected.csv"):
    if r["ExpectedStatus"]=="PASS": ck(int(r["ExpectedConflictCount"])==0,"merge:"+r["CampaignID"])
    else: ck(int(r["ExpectedConflictCount"])>0,"merge_conflict:"+r["CampaignID"])

for r in rows("validation_calibration_catalog_vectors.csv"):
    ck(float(r["HoldoutPredictionError"])<=float(r["MaxAllowedHoldoutError"]),"cal:"+r["CalibrationID"])


for r in rows("validation_reference_dataset_vectors.csv"):
    independent=r["IndependentOfDUT"].lower()=="true" and r["ReferenceSHA256"]!=r["DUTSHA256"]
    if r["ExpectedStatus"]=="PASS": ck(independent and r["Freshness"]=="FRESH","reference:"+r["CaseID"])
for r in rows("validation_measured_sinr_vectors.csv"):
    qualifying=r["ProvenanceClass"] in {"OBSERVED_RUNTIME_STATE","DERIVED_FROM_OBSERVED_RUNTIME_STATE","DECODED_RECEIVER_STATE"} and int(r["SampleCount"])>=1
    if r["ExpectedStatus"]=="PASS": ck(qualifying,"sinr:"+r["CaseID"])
for r in rows("validation_seed_partition_vectors.csv"):
    ck(r["Status"]=="PASS","seed_status:"+r["TaskID"])
seedrows=rows("validation_seed_partition_vectors.csv")
ck(len({r["TaskID"] for r in seedrows})==len(seedrows),"seed_task_unique")
ck(len({(r["CampaignID"],r["Seed"],r["Substream"]) for r in seedrows})==len(seedrows),"seed_tuple_unique")
for r in rows("validation_publication_gate_vectors.csv"):
    allok=all(r[k].lower()=="true" for k in ["SchemaOK","OracleOK","ProvenanceOK","StatisticsOK","CanonicalScenariosOK","RequiredTestsOK","ArtifactsOK","ArchiveOK"])
    ck((r["ExpectedStatus"]=="PASS")==allok,"publication:"+r["CaseID"])

cap=rows("validation_capability_profile_matrix.csv")
ck(len(cap)==168,"capability_rows")
ck(all(r["ExpectedOutcome"] in {"EXECUTE","REJECT"} for r in cap),"capability_outcomes")
imp=rows("validation_impact_experiment_matrix.csv"); ck(len(imp)==768,"impact_rows")
by={}
for r in imp: by.setdefault(r["PairID"],[]).append(r)
ck(len(by)==384,"impact_pairs")
ck(all(len(v)==2 and {x["Arm"] for x in v}=={"BASELINE","TREATMENT"} and len({x["Seed"] for x in v})==1 for v in by.values()),"impact_pair_contract")
ck(len(rows("validation_impact_analysis_families.csv"))==64,"impact_families")
ck(len(rows("validation_impact_acceptance_rules.csv"))==96,"impact_rules")
print(json.dumps({"Checks":checks,"Passed":checks-len(fail),"Failed":len(fail),"Failures":fail},indent=2))
sys.exit(0 if not fail else 2)
