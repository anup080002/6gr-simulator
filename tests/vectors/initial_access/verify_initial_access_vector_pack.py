#!/usr/bin/env python3
from __future__ import annotations
import csv, hashlib, json, math, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

def rows(name: str):
    with (HERE / name).open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))

def truth(value) -> bool:
    return str(value).strip().lower() in {"1","true","yes","pass"}

def split_ints(value: str):
    return [int(x) for x in str(value).split("|") if str(x) != ""]

failures = []

manifest = json.loads((HERE / "independent_vector_manifest.json").read_text(encoding="utf-8"))
for item in manifest["files"]:
    p = HERE / item["path"]
    if not p.exists():
        failures.append("manifest_missing:" + item["path"])
        continue
    if sha256(p) != item["sha256"]:
        failures.append("manifest_sha256:" + item["path"])
    try:
        rc = len(rows(item["path"]))
    except Exception as exc:
        failures.append("manifest_csv_parse:" + item["path"] + ":" + type(exc).__name__)
        continue
    if rc != int(item["rows"]):
        failures.append("manifest_rows:" + item["path"])

# SSB case and candidate arithmetic.
cases = {r["CaseID"]: r for r in rows("ssb_case_lmax_test_vectors.csv")}
expected_cases = rows("expected_ssb_case_lmax.csv")
for out in expected_cases:
    inp = cases[out["CaseID"]]
    if truth(inp["ExpectedValid"]):
        case = inp["DeclaredSSBCase"]
        lmax = int(inp["RequestedLmax"])
        if case == "A":
            base, nmax = [2,8], (1 if lmax == 4 else 3)
            cand = [b + 14*n for n in range(nmax+1) for b in base]
        elif case == "B":
            base, nmax = [4,8,16,20], (0 if lmax == 4 else 1)
            cand = [b + 28*n for n in range(nmax+1) for b in base]
        elif case == "C":
            base, nmax = [2,8], (1 if lmax == 4 else 3)
            cand = [b + 14*n for n in range(nmax+1) for b in base]
        else:
            failures.append("ssb_case_unknown:" + out["CaseID"])
            continue
        if split_ints(out["CandidateSymbols0Based"]) != cand:
            failures.append("ssb_candidate_symbols:" + out["CaseID"])
        if int(out["ResolvedLmax"]) != len(cand):
            failures.append("ssb_lmax:" + out["CaseID"])
    else:
        if out["ExpectedStatus"] != "REJECT":
            failures.append("ssb_negative_status:" + out["CaseID"])

# Exact SS/PBCH resource ownership and counts.
owners = rows("expected_ssb_re_ownership.csv")
by_case = {}
for r in owners:
    by_case.setdefault(r["CaseID"], []).append(r)
for case_id, rr in by_case.items():
    if len(rr) != 960:
        failures.append("ssb_re_total:" + case_id)
    counts = {}
    seen = set()
    for r in rr:
        key = (int(r["Symbol0"]), int(r["Subcarrier0"]))
        if key in seen:
            failures.append("ssb_re_duplicate:" + case_id)
        seen.add(key)
        counts[r["Owner"]] = counts.get(r["Owner"], 0) + 1
    required = {"PSS":127,"SSS":127,"PBCH":432,"PBCH_DMRS":144,"ZERO":130}
    if counts != required:
        failures.append("ssb_re_counts:" + case_id + ":" + repr(counts))

# MIB field lengths and semantic concatenation.
mib_in = {r["CaseID"]: r for r in rows("pbch_mib_test_vectors.csv")}
for out in rows("expected_mib_semantics.csv"):
    inp = mib_in[out["CaseID"]]
    if truth(inp["ExpectedValid"]):
        bits = out["MIBInformationBits23"]
        if len(bits) != 23:
            failures.append("mib_length:" + out["CaseID"])
        expected = (
            format(int(inp["SystemFrameNumberMSB6"]), "06b")
            + ("0" if inp["SubCarrierSpacingCommon"] == "scs15or60" else "1")
            + format(int(inp["SSBSubcarrierOffset"]), "04b")
            + ("0" if inp["DMRSTypeAPosition"] == "pos2" else "1")
            + format(int(inp["PDCCHConfigSIB1"]), "08b")
            + ("0" if inp["CellBarred"] == "barred" else "1")
            + ("0" if inp["IntraFreqReselection"] == "allowed" else "1")
            + "0"
        )
        if bits != expected:
            failures.append("mib_bits:" + out["CaseID"])

# Type-0 vector floor row counts.
type0_expected = {
    "ia_type0_coreset0_test_vectors.csv":268,
    "ia_expected_type0_monitoring_tables.csv":64,
    "ia_type0_pattern23_monitoring_test_vectors.csv":80,
    "ia_expected_type0_gscn_offset_vectors.csv":40,
}
for name, count in type0_expected.items():
    if len(rows(name)) != count:
        failures.append("type0_rows:" + name)

# SIB1 semantic hashes.
sib_in = {r["CaseID"]: r for r in rows("sib1_asn1_semantic_test_vectors.csv")}
for out in rows("expected_sib1_semantics.csv"):
    inp = sib_in[out["CaseID"]]
    if truth(out["ExpectedValid"]):
        got = hashlib.sha256(inp["SemanticJSON"].encode("utf-8")).hexdigest()
        if got != out["ExpectedSemanticSHA256"]:
            failures.append("sib1_semantic_hash:" + out["CaseID"])

# Exhaustive PRACH index inputs.
idx_rows = rows("prach_configuration_index_sweep.csv")
if len(idx_rows) != 512:
    failures.append("prach_index_count")
for duplex in ("FDD","TDD"):
    got = sorted(int(r["PRACHConfigurationIndex"]) for r in idx_rows if r["DuplexMode"] == duplex)
    if got != list(range(256)):
        failures.append("prach_index_coverage:" + duplex)

# RA-RNTI formula.
ra_in = {r["CaseID"]: r for r in rows("ra_rnti_test_vectors.csv")}
for out in rows("expected_ra_rnti.csv"):
    r = ra_in[out["CaseID"]]
    expected = 1 + int(r["s_id"]) + 14*int(r["t_id"]) + 14*80*int(r["f_id"]) + 14*80*8*int(r["ul_carrier_id"])
    if int(out["ExpectedRARNTI"]) != expected:
        failures.append("ra_rnti:" + out["CaseID"])

# Generic PRACH occasion arithmetic floor.
occasion_in = {r["CaseID"]: r for r in rows("prach_occasion_pattern_test_vectors.csv")}
for out in rows("expected_prach_occasion_floor.csv"):
    r = occasion_in[out["CaseID"]]
    residues = split_ints(r["AllowedFrameResidues"])
    subframes = split_ints(r["AllowedSubframes"])
    starts = split_ints(r["StartingSymbols"])
    applicable = int(r["Frame"]) % int(r["FramePeriodX"]) in residues and int(r["Subframe"]) in subframes
    count = len(starts) * int(r["NumFDM"]) if applicable else 0
    if truth(out["Applicable"]) != applicable or int(out["ExpectedNumOccasions"]) != count:
        failures.append("prach_occasion:" + out["CaseID"])

# Sequential SSB-to-RO arithmetic floor.
assoc_in = {r["CaseID"]: r for r in rows("ssb_to_ro_association_test_vectors.csv")}
for out in rows("expected_ssb_to_ro_association_floor.csv"):
    r = assoc_in[out["CaseID"]]
    num, den, ssb = int(r["SSBsPerRONumerator"]), int(r["SSBsPerRODenominator"]), int(r["SSBOrdinal0"])
    if num >= den:
        ratio = num // den
        ros = [ssb // ratio]
        pos = ssb % ratio
    else:
        ratio = den // num
        ros = list(range(ssb*ratio, ssb*ratio+ratio))
        pos = 0
    if split_ints(out["ExpectedROOrdinals0"]) != ros or int(out["ExpectedSSBPositionWithinRO0"]) != pos:
        failures.append("ssb_ro:" + out["CaseID"])

# Power-ramping arithmetic.
pwr_in = {r["CaseID"]: r for r in rows("ra_power_ramping_test_vectors.csv")}
for out in rows("expected_ra_power_ramping.csv"):
    r = pwr_in[out["CaseID"]]
    requested = float(r["PreambleReceivedTargetPower_dBm"]) + float(r["DeltaPreamble_dB"]) + (int(r["PreamblePowerRampingCounter"])-1)*float(r["PowerRampingStep_dB"]) + float(r["MeasuredPathloss_dB"])
    applied = min(requested, float(r["PCMAX_dBm"]))
    if abs(float(out["ExpectedRequestedTxPower_dBm"]) - requested) > 1e-9 or abs(float(out["ExpectedAppliedTxPower_dBm"]) - applied) > 1e-9:
        failures.append("ra_power:" + out["CaseID"])

# Timer/backoff arithmetic.
tm_in = {r["CaseID"]: r for r in rows("ra_timer_backoff_test_vectors.csv")}
for out in rows("expected_ra_timer_backoff.csv"):
    r = tm_in[out["CaseID"]]
    start = int(r["PRACHOccasionEndSlot"]) + 1
    last = start + int(r["RAResponseWindow_slots"]) - 1
    expiry = int(r["Msg3CompletionSlot"]) + math.ceil(float(r["ContentionResolutionTimer_ms"]) / float(r["SlotDuration_ms"]))
    backoff = math.floor(float(r["UniformDraw0to1"]) * float(r["BackoffIndicator_ms"]) / float(r["SlotDuration_ms"])) if float(r["BackoffIndicator_ms"]) > 0 else 0
    if (int(out["ExpectedResponseWindowStartSlot"]), int(out["ExpectedResponseWindowLastSlot"]), int(out["ExpectedContentionExpirySlotExclusive"]), int(out["ExpectedBackoffSlots"])) != (start,last,expiry,backoff):
        failures.append("ra_timer:" + out["CaseID"])

# RRC connected-state invariant.
for out in rows("expected_rrc_setup_transition.csv"):
    if truth(out["ExpectedRRCConnected"]) != (out["ExpectedFinalUEState"] == "CONNECTED" and out["ExpectedFinalGNBState"] == "CONNECTED"):
        failures.append("rrc_connected:" + out["CaseID"])

# Impact matrix/pairing/rules exactness.
experiments = rows("initial_access_impact_experiment_matrix.csv")
families = rows("initial_access_impact_analysis_families.csv")
rules = rows("initial_access_impact_acceptance_rules.csv")
if len(families) != 60:
    failures.append("impact_family_count")
if len(experiments) != 720:
    failures.append("impact_experiment_count")
if len(rules) != 90:
    failures.append("impact_rule_count")
for family_id in {r["FamilyID"] for r in experiments}:
    rr = [r for r in experiments if r["FamilyID"] == family_id]
    if len(rr) != 12:
        failures.append("impact_family_rows:" + family_id)
    for pair_id in {r["PairID"] for r in rr}:
        variants = {r["Variant"] for r in rr if r["PairID"] == pair_id}
        if variants != {"baseline","treatment"}:
            failures.append("impact_pair:" + pair_id)

# Output-contract counts.
if len(rows("desired_initial_access_csv_contract.csv")) != 31:
    failures.append("base_csv_contract_count")
if len(rows("desired_initial_access_image_contract.csv")) != 20:
    failures.append("base_image_contract_count")
if len(rows("desired_initial_access_impact_csv_contract.csv")) != 16:
    failures.append("impact_csv_contract_count")
if len(rows("desired_initial_access_impact_image_contract.csv")) != 30:
    failures.append("impact_image_contract_count")

summary = {
    "manifest_files": len(manifest["files"]),
    "manifest_rows": sum(int(x["rows"]) for x in manifest["files"]),
    "impact_families": len(families),
    "impact_experiments": len(experiments),
    "acceptance_rules": len(rules),
    "failures": failures,
}
print(json.dumps(summary, indent=2))
sys.exit(0 if not failures else 2)
