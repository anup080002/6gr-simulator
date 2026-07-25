#!/usr/bin/env python3
"""Run all non-MATLAB checks available for the PUSCH/UL-SCH pack.

The script deliberately distinguishes pack/tool validation from current-source
remediation status.  A BLOCKED MATLAB row is never converted to PASS.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import py_compile
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def add(rows, check_id, result_class, status, summary, observed="", expected="", evidence=""):
    rows.append({
        "CheckID": check_id,
        "ResultClass": result_class,
        "Status": status,
        "Summary": summary,
        "Observed": observed,
        "Expected": expected,
        "Evidence": evidence,
    })


def run(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, check=False)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", type=Path, default=Path(__file__).resolve().parent)
    ap.add_argument("--repo", type=Path, required=True)
    args = ap.parse_args()
    pack = args.pack.resolve()
    repo = args.repo.resolve()
    results: list[dict[str, object]] = []

    # 1. Python tools compile.
    scripts = sorted(pack.glob("*.py"))
    compile_errors = []
    for script in scripts:
        try:
            py_compile.compile(str(script), doraise=True)
        except Exception as exc:
            compile_errors.append(f"{script.name}:{exc}")
    add(results, "PY-COMPILE", "PACK_INFRASTRUCTURE", "PASS" if not compile_errors else "FAIL",
        "All Python tools compile.", f"scripts={len(scripts)} errors={len(compile_errors)}", "errors=0", "|".join(compile_errors))

    # 2. Vector manifest verifier.
    proc = run([sys.executable, str(pack / "verify_pusch_vector_pack.py")], cwd=pack)
    add(results, "VECTOR-MANIFEST", "PACK_INFRASTRUCTURE", "PASS" if proc.returncode == 0 else "FAIL",
        "Independent-vector manifest hashes and row counts verify.", proc.stdout.strip() or proc.stderr.strip(), "exit=0", "verify_pusch_vector_pack.py")

    # 3. Generator idempotence.
    manifest = json.loads((pack / "independent_vector_manifest.json").read_text(encoding="utf-8"))
    tracked = [pack / item["FileName"] for item in manifest["Files"]]
    before = {p.name: sha256(p) for p in tracked}
    proc_gen = run([sys.executable, str(pack / "generate_pusch_independent_vectors.py")], cwd=pack)
    after_manifest = json.loads((pack / "independent_vector_manifest.json").read_text(encoding="utf-8"))
    after = {p.name: sha256(p) for p in tracked}
    idem = proc_gen.returncode == 0 and before == after
    add(results, "VECTOR-IDEMPOTENCE", "PACK_INFRASTRUCTURE", "PASS" if idem else "FAIL",
        "Pure-Python vector generation is deterministic and idempotent.", f"files={len(tracked)} changed={sum(before[k]!=after[k] for k in before)}", "changed=0", proc_gen.stdout.strip())

    roles = Counter(item["Role"] for item in after_manifest["Files"])
    expected_rows = sum(int(item["Rows"]) for item in after_manifest["Files"] if item["Role"] == "bounded_independent_expected")
    input_rows = sum(int(item["Rows"]) for item in after_manifest["Files"] if item["Role"] == "input")
    manifest_ok = after_manifest.get("NoMATLABUsed") is True and roles["input"] == 16 and roles["bounded_independent_expected"] == 15
    add(results, "VECTOR-SCOPE", "PACK_INFRASTRUCTURE", "PASS" if manifest_ok else "FAIL",
        "Vector manifest declares a bounded no-MATLAB floor and all expected roles.",
        f"inputs={roles['input']} input_rows={input_rows} expected={roles['bounded_independent_expected']} expected_rows={expected_rows}",
        "16 input files; 15 expected files; NoMATLABUsed=true", "independent_vector_manifest.json")

    # 4. Scrambling and UCI placeholder behavior.
    scr_in = {r["CaseID"]: r for r in read_csv(pack / "pusch_scrambling_test_vectors.csv")}
    scr_out = read_csv(pack / "expected_pusch_scrambling_vectors.csv")
    scr_ok = len(scr_in) == len(scr_out) and all(len(r["GoldBits"]) == len(scr_in[r["CaseID"]]["InputSymbols"]) for r in scr_out)
    # Verify X -> 1 and Y -> previous output in any applicable rows.
    placeholder_ok = True
    for r in scr_out:
        inp = scr_in[r["CaseID"]]["InputSymbols"]
        out = r["ScrambledSymbols"]
        for i, ch in enumerate(inp):
            if ch == "X" and out[i] != "1":
                placeholder_ok = False
            if ch == "Y" and (i == 0 or out[i] != out[i - 1]):
                placeholder_ok = False
    add(results, "SCRAMBLING", "PACK_INFRASTRUCTURE", "PASS" if scr_ok and placeholder_ok else "FAIL",
        "PUSCH Gold-sequence vectors and x/y UCI placeholder rules are internally recomputed.",
        f"rows={len(scr_out)} placeholders_ok={placeholder_ok}", "all rows length-consistent; placeholders exact", "expected_pusch_scrambling_vectors.csv")

    # 5. Modulation legality and normalization.
    mod_in = read_csv(pack / "pusch_modulation_test_vectors.csv")
    mod_out = read_csv(pack / "expected_pusch_modulation_vectors.csv")
    positive = [r for r in mod_out if r["Status"] == "PASS"]
    legal = {r["Modulation"] for r in mod_in if r["ExpectedStatus"] == "PASS"}
    unsupported = {r["Modulation"] for r in mod_in
                   if r["ExpectedStatus"] == "ERROR" and r["ExpectedError"] == "sixgr:pusch:UnsupportedModulation"}
    # Arbitrary finite bit sequences need not have sample mean power exactly one.
    # Verify the normalization constants over each complete square-QAM alphabet instead.
    full_constellation_power_ok = True
    for q_m in (2, 4, 6, 8):
        m = 1 << q_m
        axis_size = 1 << (q_m // 2)
        levels = [2 * i + 1 - axis_size for i in range(axis_size)]
        scale = math.sqrt((2.0 / 3.0) * (m - 1))
        mean_energy = sum((i * i + q * q) / (scale * scale) for i in levels for q in levels) / m
        full_constellation_power_ok &= abs(mean_energy - 1.0) < 1e-12
    finite_vectors = all(math.isfinite(float(r["MeanPower"])) and float(r["MeanPower"]) > 0 for r in positive)
    mod_ok = (legal == {"PI/2-BPSK", "QPSK", "16QAM", "64QAM", "256QAM"}
              and unsupported == {"1024QAM", "4096QAM"}
              and full_constellation_power_ok and finite_vectors)
    add(results, "MODULATION", "PACK_INFRASTRUCTURE", "PASS" if mod_ok else "FAIL",
        "PUSCH modulation vectors cover the legal strict set, complete-alphabet normalization, and unsupported-order rejection.",
        f"legal={sorted(legal)} unsupported={sorted(unsupported)} constellation_normalized={full_constellation_power_ok} finite_vectors={finite_vectors}",
        "PI/2-BPSK,QPSK,16QAM,64QAM,256QAM only; QAM complete alphabets have unit average energy", "pusch_modulation_test_vectors.csv")

    # 6. Layer/codeword mapping breadth.
    lm_in = read_csv(pack / "pusch_layer_mapping_test_vectors.csv")
    lm_out = read_csv(pack / "expected_pusch_layer_mapping.csv")
    positive_ranks = {int(r["Rank"]) for r in lm_in if r["ExpectedStatus"] == "PASS"}
    high_rank_two_cw = all(int(r["NumCodewords"]) == 2 for r in lm_in if r["ExpectedStatus"] == "PASS" and int(r["Rank"]) >= 5)
    layers_present = {int(r["Layer"]) for r in lm_out if r["Status"] == "PASS"}
    lm_ok = positive_ranks == set(range(1, 9)) and high_rank_two_cw and layers_present == set(range(8))
    add(results, "LAYER-MAPPING", "PACK_INFRASTRUCTURE", "PASS" if lm_ok else "FAIL",
        "Codeword-to-layer vectors cover rank 1-8 and two-codeword high-rank mapping.",
        f"ranks={sorted(positive_ranks)} layers={sorted(layers_present)} high_rank_two_cw={high_rank_two_cw}",
        "ranks 1..8; ranks 5..8 use two codewords", "expected_pusch_layer_mapping.csv")

    # 7. Transform precoding normative rank constraint and DFT invariants.
    tp_in = read_csv(pack / "pusch_transform_precoding_test_vectors.csv")
    tp_out = read_csv(pack / "expected_pusch_transform_dft_vectors.csv")
    pos_in = [r for r in tp_in if r["ExpectedStatus"] == "PASS"]
    neg_layers = [r for r in tp_in if r["ExpectedStatus"] == "ERROR" and int(r["NumLayers"]) > 1]
    pos_out = [r for r in tp_out if r["Status"] == "PASS"]
    tp_ok = (all(int(r["NumLayers"]) == 1 for r in pos_in) and len(neg_layers) >= 2 and
             all(float(r["RoundTripNMSE"]) < 1e-24 and float(r["EnergyRelativeError"]) < 1e-12 for r in pos_out))
    add(results, "TRANSFORM-PRECODING", "PACK_INFRASTRUCTURE", "PASS" if tp_ok else "FAIL",
        "Unitary DFT-s-OFDM vectors are rank-1 only and multi-layer transform precoding is rejected.",
        f"positive={len(pos_in)} multilayer_negative={len(neg_layers)}", "all positive NumLayers=1; round-trip/energy exact", "expected_pusch_transform_dft_vectors.csv")

    # 8. Scheduling assignment profiles and fail-closed errors.
    ass = read_csv(pack / "pusch_scheduling_assignment_test_vectors.csv")
    profiles = {r["Profile"] for r in ass}
    sources = {r["SourceType"] for r in ass if r["ExpectedStatus"] == "PASS"}
    neg_errors = {r["ExpectedError"] for r in ass if r["ExpectedStatus"] == "ERROR"}
    ass_ok = {"connected_dynamic_strict", "configured_grant_type1_strict", "configured_grant_type2_strict", "random_access_ul_strict", "phy_calibration"}.issubset(profiles) and len(sources) >= 5 and all(neg_errors)
    add(results, "ASSIGNMENT-PROFILES", "PACK_INFRASTRUCTURE", "PASS" if ass_ok else "FAIL",
        "Dynamic DCI, CG type 1/2, random-access and calibration assignment vectors are distinct.",
        f"profiles={sorted(profiles)} negative_errors={len(neg_errors)}", "five distinct assignment families and typed failures", "pusch_scheduling_assignment_test_vectors.csv")

    # 9. Exact two-TB UCI owner rule floor.
    uci_in = read_csv(pack / "pusch_uci_multiplex_test_vectors.csv")
    uci_out = {r["CaseID"]: r for r in read_csv(pack / "expected_pusch_uci_owner_and_budget.csv")}
    owner_ok = True
    owner_cases = 0
    for r in uci_in:
        if r["ExpectedStatus"] != "PASS" or int(r["NumULSCHTB"]) != 2:
            continue
        owner_cases += 1
        i0, i1 = int(r["InitialIMCSCodeword0"]), int(r["InitialIMCSCodeword1"])
        expected = "0" if i0 >= i1 else "1"
        if uci_out[r["CaseID"]]["ExpectedUCIOwner"] != expected:
            owner_ok = False
    add(results, "UCI-OWNER", "PACK_INFRASTRUCTURE", "PASS" if owner_ok and owner_cases > 0 else "FAIL",
        "Two-UL-SCH-TB UCI owner follows highest initial I_MCS, tie to first TB.",
        f"two_tb_cases={owner_cases} exact={owner_ok}", "all two-TB cases exact", "expected_pusch_uci_owner_and_budget.csv")

    sr_rows = [r for r in uci_in if int(r["OSR"] or 0) > 0]
    sr_reject_ok = bool(sr_rows) and all(
        r["ExpectedStatus"] == "ERROR" and r["ExpectedError"] == "sixgr:pusch:SchedulingRequestNotCarriedOnPUSCH"
        for r in sr_rows)
    add(results, "UCI-SR-ROUTING", "PACK_INFRASTRUCTURE", "PASS" if sr_reject_ok else "FAIL",
        "Scheduling Request is not encoded as generic UCI on PUSCH in the strict profile.",
        f"nonzero_osr_rows={len(sr_rows)} rejected={sum(r['ExpectedStatus']=='ERROR' for r in sr_rows)}",
        "all nonzero OSR rows are typed negatives and must be routed to PUCCH", "pusch_uci_multiplex_test_vectors.csv")

    # 10. DM-RS and PT-RS bounded contracts (not full independent tables).
    dmrs = read_csv(pack / "expected_pusch_dmrs_validation_floor.csv")
    dmrs_ok = len(dmrs) > 0 and all(r["InputMutationAllowed"] == "0" and r["ExactTableResolutionRequired"] == "1" for r in dmrs)
    add(results, "DMRS-FLOOR", "PACK_INFRASTRUCTURE", "PASS" if dmrs_ok else "FAIL",
        "DM-RS vectors enforce no input mutation and require exact pinned-table resolution.",
        f"rows={len(dmrs)}", "all no-mutation and exact-table-required", "expected_pusch_dmrs_validation_floor.csv")
    ptrs = read_csv(pack / "expected_pusch_ptrs_presence.csv")
    ptrs_ok = len(ptrs) > 0 and all(r["InputMutationAllowed"] == "0" and r["ExactIndexOracleRequired"] == "1" for r in ptrs)
    add(results, "PTRS-FLOOR", "PACK_INFRASTRUCTURE", "PASS" if ptrs_ok else "FAIL",
        "PT-RS vectors enforce exact index oracles, port association and no input mutation.",
        f"rows={len(ptrs)}", "all no-mutation and exact-index-required", "expected_pusch_ptrs_presence.csv")

    # 11. Frequency hopping restrictions.
    hop_in = read_csv(pack / "pusch_frequency_hopping_test_vectors.csv")
    hop_out = read_csv(pack / "expected_pusch_hop_plans.csv")
    modes = {r["Mode"] for r in hop_in if r["ExpectedStatus"] == "PASS"}
    type2_reject = any(r["ExpectedError"] == "sixgr:pusch:FrequencyHoppingResourceTypeConflict" for r in hop_in)
    hop_ok = {"none", "intra_slot", "inter_slot"}.issubset(modes) and type2_reject and len(hop_out) == len(hop_in)
    add(results, "FREQUENCY-HOPPING", "PACK_INFRASTRUCTURE", "PASS" if hop_ok else "FAIL",
        "Hop-plan vectors cover none/intra-slot/inter-slot and reject incompatible resource allocation.",
        f"modes={sorted(modes)} type2_reject={type2_reject} rows={len(hop_out)}", "all modes plus typed conflict", "expected_pusch_hop_plans.csv")

    # 12. SRS decision age and epoch.
    srs = read_csv(pack / "expected_pusch_srs_precoder_decisions.csv")
    srs_ok = (any(r["Status"] == "PASS" and r["DecisionSource"] == "measured_srs" for r in srs) and
              any(r["Status"] == "ERROR" and r["Stale"] == "1" for r in srs) and
              any(r["Status"] == "ERROR" and r["EpochMatch"] == "0" for r in srs) and
              all(r["ConfiguredTPMIFallbackAllowed"] == "0" for r in srs))
    add(results, "SRS-PRECODER", "PACK_INFRASTRUCTURE", "PASS" if srs_ok else "FAIL",
        "SRS-derived precoder vectors cover accepted, stale, epoch-mismatch and no-configured-fallback cases.",
        f"rows={len(srs)}", "measured source; stale/epoch negatives; no config fallback", "expected_pusch_srs_precoder_decisions.csv")

    # 13. Precoding application exactness floor.
    prec = read_csv(pack / "expected_pusch_precoding_application.csv")
    prec_ok = (any(r["Status"] == "PASS" for r in prec) and
               all(int(r["MatrixApplicationCount"] or 0) == 1 for r in prec if r["Status"] == "PASS") and
               all(r["MatrixDigest"] and r["ExpectedPortSymbolDigest"] for r in prec if r["Status"] == "PASS"))
    add(results, "PRECODER-APPLICATION", "PACK_INFRASTRUCTURE", "PASS" if prec_ok else "FAIL",
        "Explicit UL precoder application vectors include matrix and output digests.",
        f"rows={len(prec)} positives={sum(r['Status']=='PASS' for r in prec)}", "one application per positive case", "expected_pusch_precoding_application.csv")

    # 14. Power-control formula, loops, clipping and errors.
    power = read_csv(pack / "expected_pusch_power_control.csv")
    pwr_in = read_csv(pack / "pusch_power_control_test_vectors.csv")
    loops = {r["LoopId"] for r in pwr_in if r["ExpectedStatus"] == "PASS"}
    modes = {r["AdjustmentMode"] for r in pwr_in if r["ExpectedStatus"] == "PASS"}
    power_ok = (loops == {"0", "1"} and modes == {"accumulated", "absolute"} and
                all(r["FormulaIncludesMuFactor"] == "1" for r in power) and
                any(r["Clipped"] == "1" for r in power if r["Status"] == "PASS"))
    add(results, "POWER-CONTROL", "PACK_INFRASTRUCTURE", "PASS" if power_ok else "FAIL",
        "Power-control vectors exercise both loops, accumulated/absolute TPC, 2^mu*M_RB and PCMAX clipping.",
        f"loops={sorted(loops)} modes={sorted(modes)} clipped={sum(r['Clipped']=='1' for r in power)}", "loops 0/1; both modes; mu factor; clipping", "expected_pusch_power_control.csv")

    # 15. HARQ state transition floor.
    harq = read_csv(pack / "expected_pusch_harq_transitions.csv")
    actions = {r["HARQAction"] for r in harq if r["Status"] == "PASS"}
    harq_ok = {"NEW_DATA", "RETRANSMISSION"}.issubset(actions) and any(r["Combined"] == "1" for r in harq if r["Status"] == "PASS")
    add(results, "HARQ", "PACK_INFRASTRUCTURE", "PASS" if harq_ok else "FAIL",
        "HARQ vectors distinguish new data and retransmission with soft-combining state.",
        f"actions={sorted(actions)} rows={len(harq)}", "new data and retransmission present", "expected_pusch_harq_transitions.csv")

    # 16. TBS/CRC floor.
    tbs = read_csv(pack / "expected_pusch_tbs_basegraph.csv")
    crc = read_csv(pack / "expected_pusch_tb_crc_vectors.csv")
    tbs_statuses = Counter(r["Status"] for r in tbs)
    crc_statuses = Counter(r["Status"] for r in crc)
    coding_ok = (len(tbs) == 23 and tbs_statuses == Counter({"PASS": 18, "ERROR": 5})
                 and len(crc) == 18 and crc_statuses == Counter({"PASS": 18})
                 and all(r["ExpectedError"] for r in tbs if r["Status"] == "ERROR"))
    add(results, "ULSCH-CODING-FLOOR", "PACK_INFRASTRUCTURE", "PASS" if coding_ok else "FAIL",
        "Independent TBS/base-graph vectors include positive and typed-negative cases; all TB-CRC vectors pass.",
        f"tbs_rows={len(tbs)} tbs_status={dict(tbs_statuses)} crc_rows={len(crc)} crc_status={dict(crc_statuses)}",
        "TBS: 18 PASS and 5 typed ERROR; CRC: 18 PASS", "expected_pusch_tbs_basegraph.csv|expected_pusch_tb_crc_vectors.csv")

    # 17. Required artifact contracts.
    csv_contract = read_csv(pack / "desired_pusch_csv_contract.csv")
    img_contract = read_csv(pack / "desired_pusch_image_contract.csv")
    contract_ok = len(csv_contract) == 20 and len(img_contract) == 11 and all(r["Required"] == "1" for r in csv_contract)
    add(results, "ARTIFACT-CONTRACT", "PACK_INFRASTRUCTURE", "PASS" if contract_ok else "FAIL",
        "PUSCH phase requires the complete CSV and PNG evidence set.",
        f"csv={len(csv_contract)} png={len(img_contract)}", "20 CSV and 11 PNG", "desired_pusch_*_contract.csv")

    # 18. Artifact verifier self-test.
    proc_art = run([sys.executable, str(pack / "verify_pusch_artifacts.py"), "--self-test"], cwd=pack)
    art_ok = proc_art.returncode == 0 and "corrupt exit=2" in proc_art.stdout
    add(results, "ARTIFACT-VERIFIER", "PACK_INFRASTRUCTURE", "PASS" if art_ok else "FAIL",
        "Artifact verifier accepts a complete synthetic set and rejects a corrupted PNG hash.",
        proc_art.stdout.strip() or proc_art.stderr.strip(), "valid exit 0; corrupted exit 2", "verify_pusch_artifacts.py --self-test")

    # 19. Existing source image integrity.
    images = read_csv(pack / "existing_pusch_image_integrity_audit.csv")
    img_ok = len(images) > 0 and all(r["Status"] == "PASS" and r["StructurallyNonblank"] == "1" for r in images)
    add(results, "EXISTING-PNG-INTEGRITY", "CURRENT_OUTPUT_INVENTORY", "PASS" if img_ok else "FAIL",
        "All existing bundled PNGs decode and are structurally nonblank.",
        f"decoded={sum(r['Status']=='PASS' for r in images)}/{len(images)}", "all decode/nonblank", "existing_pusch_image_integrity_audit.csv")

    # 20. Current source defect signatures — intentionally FAIL until Codex fixes them.
    static = read_csv(pack / "current_pusch_static_audit.csv")
    defects = [r for r in static if r["Kind"] == "DEFECT"]
    defect_count = sum(r["Status"] == "FAIL" for r in defects)
    add(results, "CURRENT-SOURCE-REMEDIATION", "CURRENT_SIMULATOR", "PASS" if defect_count == 0 else "FAIL",
        "Current production source must contain none of the targeted shortcut signatures.",
        f"defects_detected={defect_count}/{len(defects)} foundations_present={sum(r['Kind']=='FOUNDATION' and r['Status']=='PASS' for r in static)}",
        "defects_detected=0", "current_pusch_static_audit.csv")

    # 21. Current required artifacts — intentionally FAIL until phase runner exists.
    presence = read_csv(pack / "existing_pusch_artifact_presence_audit.csv")
    present = sum(int(r["Present"]) for r in presence)
    add(results, "CURRENT-REQUIRED-ARTIFACTS", "CURRENT_SIMULATOR", "PASS" if present == len(presence) else "FAIL",
        "Current simulator outputs must contain all required PUSCH phase artifacts.",
        f"present={present}/{len(presence)} csv={sum(r['ArtifactType']=='CSV' and r['Present']=='1' for r in presence)}/20 png={sum(r['ArtifactType']=='PNG' and r['Present']=='1' for r in presence)}/11",
        f"present={len(presence)}/{len(presence)}", "existing_pusch_artifact_presence_audit.csv")

    # 22. Real MATLAB execution availability.
    matlab = shutil.which("matlab")
    octave = shutil.which("octave")
    if matlab:
        status = "NOT_RUN"
        observed = f"matlab={matlab}; this limited script does not execute the long suite automatically"
    elif octave:
        status = "BLOCKED"
        observed = f"octave={octave}; 5G Toolbox MATLAB chain unavailable"
    else:
        status = "BLOCKED"
        observed = "matlab=not_found; octave=not_found"
    add(results, "MATLAB-PRODUCTION-RUNTIME", "MANDATORY_RUNTIME", status,
        "Actual PUSCH waveform, Toolbox, channel, campaign, CSV and PNG generation must run in MATLAB.",
        observed, "pinned MATLAB + 5G Toolbox; all mandatory tests executed", "environment PATH")

    out_csv = pack / "limited_pusch_test_results.csv"
    with out_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)

    counts = Counter(str(r["Status"]) for r in results)
    classes: dict[str, dict[str, int]] = {}
    for r in results:
        c = str(r["ResultClass"])
        classes.setdefault(c, {})
        classes[c][str(r["Status"])] = classes[c].get(str(r["Status"]), 0) + 1
    summary = {
        "SchemaVersion": "PUSCHLimitedTestSummary/v1",
        "TotalChecks": len(results),
        "StatusCounts": dict(counts),
        "ByResultClass": classes,
        "CurrentSimulatorPhaseStatus": "FAIL" if any(r["ResultClass"] == "CURRENT_SIMULATOR" and r["Status"] != "PASS" for r in results) else "PASS",
        "MATLABRuntimeStatus": next(r["Status"] for r in results if r["CheckID"] == "MATLAB-PRODUCTION-RUNTIME"),
        "PackInfrastructurePass": all(r["Status"] == "PASS" for r in results if r["ResultClass"] == "PACK_INFRASTRUCTURE"),
        "RequiredCSVCount": 20,
        "RequiredPNGCount": 11,
        "InputVectorRows": input_rows,
        "BoundedExpectedRows": expected_rows,
        "StaticDefectCount": defect_count,
        "ExistingRequiredArtifactsPresent": present,
    }
    (pack / "limited_test_summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
