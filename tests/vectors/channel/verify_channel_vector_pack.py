#!/usr/bin/env python3
from __future__ import annotations
import csv, json, hashlib, math, sys
from pathlib import Path

def rows(p):
    with open(p,encoding="utf-8-sig",newline="") as f: return list(csv.DictReader(f))
def sha(p):
    h=hashlib.sha256()
    with open(p,"rb") as f:
        for c in iter(lambda:f.read(1024*1024),b""): h.update(c)
    return h.hexdigest()
root=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parent
fail=[]; checks=0
def ck(c,m):
    global checks
    checks+=1
    if c: print("PASS",m)
    else: print("FAIL",m); fail.append(m)

man=json.loads((root/"independent_vector_manifest.json").read_text(encoding="utf-8"))
for e in man["Files"]:
    p=root/e["FileName"]; ck(p.is_file(),"manifest_exists:"+e["FileName"])
    if p.is_file():
        ck(sha(p)==e["SHA256"],"manifest_hash:"+e["FileName"])
        ck(len(rows(p))==int(e["Rows"]),"manifest_rows:"+e["FileName"])
ck(man.get("GeneratedWithoutMATLAB") is True,"manifest_independence_flag")

geo=rows(root/"expected_geometry_kinematics.csv")
ck(len(geo)>=300,"geometry_vector_count")
ck(all(float(r["Distance3D_m"])>0 and float(r["PropagationDelay_s"])>0 for r in geo),"geometry_positive_distance_delay")
ck(all(abs(float(r["PhaseIncrement_rad"])-2*math.pi*float(r["SignedDoppler_Hz"])*
                 float(next(x["Dt_s"] for x in rows(root/"channel_geometry_state_test_vectors.csv") if x["CaseID"]==r["CaseID"])))<1e-8 for r in geo[:100]),
   "geometry_doppler_phase_relation")

pl=rows(root/"expected_channel_pathloss.csv")
ck(sum(r["ExpectedStatus"]=="PASS" for r in pl)>=300,"pathloss_exact_floor_count")
ck(all((r["ExpectedStatus"]!="PASS") or math.isfinite(float(r["ExpectedPathloss_dB"])) for r in pl),"pathloss_finite")

los=rows(root/"expected_channel_los_probability.csv")
ck(all((r["ExpectedStatus"]!="PASS") or 0<=float(r["ExpectedPLOS"])<=1 for r in los),"los_probability_bounds")

o2i=rows(root/"expected_channel_o2i_loss.csv")
ck(any(abs(float(r["IRRGlassLoss_dB"])-(25.4+0.11*float(next(x["Fc_GHz"] for x in rows(root/"channel_o2i_material_test_vectors.csv") if x["CaseID"]==r["CaseID"]))))<1e-9 for r in o2i),"o2i_rel19_irr_coefficients")

oxy_in={r["CaseID"]:r for r in rows(root/"channel_oxygen_absorption_test_vectors.csv")}
oxy=rows(root/"expected_channel_oxygen_absorption.csv")
ck(any(abs(float(r["SpecificAttenuation_dB_per_km"])-15)<1e-12 and abs(float(oxy_in[r["CaseID"]]["Fc_GHz"])-60)<1e-12 for r in oxy),"oxygen_60ghz_15dbkm")
ck(all(float(r["SpecificAttenuation_dB_per_km"])==0 for r in oxy if float(oxy_in[r["CaseID"]]["Fc_GHz"])<=52 or float(oxy_in[r["CaseID"]]["Fc_GHz"])>=68),"oxygen_zero_outside_line_floor")

arr=rows(root/"expected_channel_array_response.csv")
ck(len(arr)>=10000,"array_vector_count")
ck(all(abs(float(r["Magnitude"])-1)<1e-10 for r in arr),"array_unit_magnitude")

tdl=rows(root/"expected_tdl_spatial_correlation.csv")
ck(all(float(r["MinEigenvalue"])>=-1e-10 for r in tdl),"tdl_correlation_psd")

wrap=rows(root/"expected_wraparound_topology.csv")
per={}
for r in wrap: per[r["CaseID"]]=per.get(r["CaseID"],0)+1
ck(all(v==57 for v in per.values()),"hex_19site_3sector_count")

drops=rows(root/"expected_channel_ue_drop_coordinates.csv")
ck(len(drops)>=6000 and all(math.isfinite(float(r["X_m"])) and math.isfinite(float(r["Y_m"])) for r in drops),"drop_vectors_finite")

inter=rows(root/"expected_interference_superposition.csv")
ck(len(inter)>=6000 and all(float(r["ExpectedPower"])>=0 for r in inter),"interference_superposition_vectors")

mob=rows(root/"expected_mobility_doppler_phase.csv")
ck(len(mob)>=14000,"mobility_vector_count")
ck(any(float(r["SignedDoppler_Hz"])>0 for r in mob) and any(float(r["SignedDoppler_Hz"])<0 for r in mob),"signed_doppler_both_directions")

pwr_in={r["CaseID"]:r for r in rows(root/"channel_absolute_power_test_vectors.csv")}
pwr=rows(root/"expected_absolute_power_ledger.csv")
def calc(r):
    x=pwr_in[r["CaseID"]]
    return (float(x["TxPower_dBm"])+float(x["TxGain_dBi"])+float(x["RxGain_dBi"])
            -float(x["Pathloss_dB"])-float(x["ShadowFading_dB"])-float(x["O2ILoss_dB"])
            -float(x["OxygenLoss_dB"])-float(x["ImplementationLoss_dB"]))
ck(all(abs(calc(r)-float(r["ExpectedRxPower_dBm"]))<1e-10 for r in pwr),"absolute_power_equation")

caps=rows(root/"channel_capability_profile_matrix.csv")
ck(len(caps)>=250 and all(r["PlanningOutcome"] in {"EXECUTE","REJECT"} for r in caps),"capability_matrix_complete")

exps=rows(root/"channel_impact_experiment_matrix.csv")
ck(len(exps)==768,"impact_experiments_768")
groups={}
for r in exps: groups.setdefault((r["FamilyID"],r["PairID"],r["Seed"]),[]).append(r)
ck(len(groups)==384 and all(len(g)==2 and {x["Arm"] for x in g}=={"BASELINE","TREATMENT"} for g in groups.values()),"impact_pair_integrity")
ck(len(rows(root/"channel_impact_acceptance_rules.csv"))==96,"impact_rules_96")
ck(len(rows(root/"desired_channel_csv_contract.csv"))==32 and len(rows(root/"desired_channel_image_contract.csv"))==22,"base_contract_counts")
ck(len(rows(root/"desired_channel_impact_csv_contract.csv"))==16 and len(rows(root/"desired_channel_impact_image_contract.csv"))==30,"impact_contract_counts")

print(json.dumps({"Checks":checks,"Passed":checks-len(fail),"Failed":len(fail),"Failures":fail},indent=2))
sys.exit(0 if not fail else 2)
