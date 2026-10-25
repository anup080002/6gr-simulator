"""Declared CSV-shaped populations and executed dashboard selection; no PHY claim."""
import copy
import csv
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))
import lls_web_dashboard as dash


def source_rows():
    rows = []
    for index in range(8):
        quiet = index >= 4
        rows.append(dict(
            Slot=3, UEID=1, SSBIndex="NaN" if quiet else index,
            RequestedSSBOccasionIndex=index, SSBRequestedCandidateTransmitted=int(not quiet),
            BCHTransmittedBlockPopulationEligible=int(not quiet),
            SSBReceiverSearchScope="all_receiver_case_lmax_candidates_not_TX_active_bitmap",
            SSBReceiverSearchCandidateCount=8, SSBAcquisitionWindowSHA256="b" * 64,
            Status="FAIL" if quiet else "PASS", CRCPass="NaN" if quiet else 1,
            DetectionAttempted=1, PSSDetected=int(not quiet), SSSDetected=int(not quiet),
            DecodeAttempted=int(not quiet), BCHCRCValid=int(not quiet),
            MIBDecoded=int(not quiet), PBCHStrictReceiverEvidenceOk=int(not quiet),
            FalseAlarm=0, FalseAlarmSource="declared_fixture_original_decision",
            SS_RSRP_dBm="NaN" if quiet else -98.1,
            CFOCorrectionApplied_Hz="NaN" if quiet else 400.25,
        ))
    # Exercise the actual CSV textual boundary, not numeric-only dictionaries.
    stream = io.StringIO()
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
    stream.seek(0)
    return list(csv.DictReader(stream))


def js_partition(control, sweep):
    source = (ROOT / "apps/lls_web_dashboard.py").read_text(encoding="utf-8")
    lines = [line.strip() for line in source.splitlines()
             if line.strip().startswith(("const ssbBeamRows =", "const ssbQuietRows =", "const ssbSweepRows ="))]
    assert len(lines) == 3
    node = shutil.which("node") or "C:/ProgramData/anaconda3/Lib/site-packages/playwright/driver/node.exe"
    assert Path(node).is_file(), "Node is required to execute the actual dashboard partition"
    code = "const controlPreviews=" + json.dumps({"pbch_trials": control}) + ";\n"
    code += "const procedurePreviews=" + json.dumps({"ssb_sweep": sweep}) + ";\n"
    code += "\n".join(lines) + "\nconsole.log(JSON.stringify({ssbBeamRows,ssbQuietRows,ssbSweepRows}));"
    result = subprocess.run([node, "-e", code], text=True, capture_output=True, check=True, timeout=15)
    return json.loads(result.stdout)


def test_csv_roundtrip_and_actual_js_preserve_all_eight_original_candidates():
    raw = source_rows()
    original = copy.deepcopy(raw)
    control = dash.summarize_control_trial_preview_rows("pbch_trials", raw)
    sweep = dash.summarize_procedure_preview_rows("ssb_sweep", raw)
    split = js_partition(control, sweep)
    assert raw == original and len(control) == len(sweep) == 8
    assert [r["Requested SSB candidate (0-based)"] for r in split["ssbBeamRows"]] == list("0123")
    assert [r["Requested SSB candidate (0-based)"] for r in split["ssbQuietRows"]] == list("4567")
    assert len(split["ssbSweepRows"]) == 4
    assert split["ssbBeamRows"][0]["SS-RSRP (dBm)"] == "-98.1"
    assert split["ssbBeamRows"][0]["Applied CFO correction (Hz)"] == "400.25"


def test_transmitted_decode_failure_unknown_legacy_and_quiet_false_acceptance():
    raw = source_rows()
    raw[0].update(Status="FAIL", SSBIndex="NaN", CRCPass="0", SS_RSRP_dBm="NaN")
    raw[4].update(Status="PASS", SSBIndex="4", CRCPass="1", BCHCRCValid="1",
                  MIBDecoded="1", PBCHStrictReceiverEvidenceOk="1", FalseAlarm="1")
    legacy = dict(raw[5])
    for key in ("SSBRequestedCandidateTransmitted", "SSBAcquisitionWindowSHA256"):
        legacy.pop(key)
    raw.append(legacy)
    split = js_partition(dash.summarize_control_trial_preview_rows("pbch_trials", raw), [])
    assert len(split["ssbBeamRows"]) == 5
    assert split["ssbBeamRows"][0]["Status"] == "FAIL"
    assert split["ssbBeamRows"][-1]["SSB search population"] == "unknown_or_legacy"
    false_accept = split["ssbQuietRows"][0]
    assert false_accept["Original false alarm"] == "1"
    assert false_accept["Strict receiver evidence accepted"] == "1"
    assert false_accept["Raw BCH CRC valid"] == "1" and false_accept["Status"] == "PASS"


@pytest.mark.parametrize("field,value", [
    ("SSBRequestedCandidateTransmitted", "false"), ("SSBRequestedCandidateTransmitted", 2),
    ("SSBRequestedCandidateTransmitted", False), ("SSBRequestedCandidateTransmitted", None),
    ("RequestedSSBOccasionIndex", "NaN"), ("RequestedSSBOccasionIndex", -1),
    ("RequestedSSBOccasionIndex", 1.5), ("RequestedSSBOccasionIndex", [4]),
    ("SSBAcquisitionWindowSHA256", "invalid"), ("SSBReceiverSearchScope", "unknown"),
    ("BCHTransmittedBlockPopulationEligible", 1), ("BCHTransmittedBlockPopulationEligible", "NaN"),
])
def test_malformed_membership_is_not_hidden_as_quiet(field, value):
    row = source_rows()[4]
    row[field] = value
    assert dash.ssb_search_population_fields(row)["SSB search population"] == "unknown_or_legacy"


def test_every_primary_ssb_panel_uses_partition_and_quiet_outcomes_are_visible():
    source = (ROOT / "apps/lls_web_dashboard.py").read_text(encoding="utf-8")
    assert "recent(controlPreviews.pbch_trials)" not in source
    assert "recent(procedurePreviews.ssb_sweep)" not in source
    for key in ("ssb_pbch", "ssb_sync_timing", "ssb_measurements"):
        line = next(line for line in source.splitlines() if "id:'" + key + "'" in line)
        assert "recent(ssbBeamRows)" in line and "SSB search population" in line
    quiet = next(line for line in source.splitlines() if "id:'ssb_quiet_search'" in line)
    assert "recent(ssbQuietRows)" in quiet and "Original false alarm" in quiet
    assert "not an independent false-alarm probability estimate" in quiet
