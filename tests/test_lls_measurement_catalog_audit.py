import csv
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))
from audit_lls_measurement_catalog import audit

CATALOG = ROOT / "simulator/configs/validation/lls_evaluation_measurements.tsv"
MAPPING = ROOT / "simulator/configs/validation/lls_evaluation_evidence_map.json"


def write_csv(path, fields, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def test_all_requested_records_retained_with_no_invented_measurement(tmp_path):
    rows = audit(CATALOG, MAPPING, tmp_path)
    assert len(rows) == len({r["RecordID"] for r in rows}) == 117
    assert all(r["CoverageStatus"] == "requested_evidence_not_established" for r in rows)
    assert all(r["ScientificValidation"] == "not_verified_by_presence_audit" for r in rows)
    assert not list(tmp_path.rglob("*"))  # audit cannot write missing evidence


def test_candidates_do_not_imply_measurement_or_png_completion(tmp_path):
    path = tmp_path / "air_interface/csv/pucch_trials.csv"
    write_csv(path, ["Slot", "Status"], [{"Slot": 35, "Status": "PASS"}])
    before = path.read_bytes()
    rows = audit(CATALOG, MAPPING, tmp_path)
    uci = next(r for r in rows if r["Measurement"] == "Uplink control information block error rate")
    assert uci["CoverageStatus"] == "candidate_evidence_requires_mapping"
    assert json.loads(uci["CandidateEvidenceJSON"])[0]["rows"] == 1
    assert json.loads(uci["NamedCSVDetailsJSON"]) == []
    assert json.loads(uci["NamedPNGPathsJSON"]) == []
    assert path.read_bytes() == before


def test_named_file_does_not_establish_schema_or_scientific_correctness(tmp_path):
    write_csv(tmp_path / "AI_10_2_1_evm.csv", ["EVM"], [{"EVM": 0}])
    rows = audit(CATALOG, MAPPING, tmp_path)
    evm = next(r for r in rows if r["RecordID"] == "AI_10_2_1_evm")
    assert evm["CoverageStatus"] == "named_export_present_unverified"
    assert evm["ScientificValidation"] == "not_verified_by_presence_audit"
    assert "reference_symbol_iq" in json.loads(evm["NamedCSVDetailsJSON"])[0]["missing_proposed_fields"]


def test_empty_file_does_not_count_as_measurement(tmp_path):
    write_csv(tmp_path / "AI_10_2_1_evm.csv", ["EVM"], [])
    row = next(r for r in audit(CATALOG, MAPPING, tmp_path) if r["RecordID"] == "AI_10_2_1_evm")
    assert row["CoverageStatus"] == "requested_evidence_not_established"
    assert json.loads(row["NamedCSVDetailsJSON"])[0]["state"] == "empty"


def test_gnb_srs_does_not_substitute_for_ue_cli(tmp_path):
    write_csv(tmp_path / "air_interface/csv/srs_trials.csv", ["RSRP"], [{"RSRP": -90}])
    rows = audit(CATALOG, MAPPING, tmp_path)
    cli = [r for r in rows if r["Measurement"] in (
        "Sounding reference signal received power", "Cross-link interference received signal strength indicator")]
    assert cli and all(r["CoverageStatus"] == "requested_evidence_not_established" for r in cli)


def test_mapping_implementation_paths_exist():
    mapping = json.loads(MAPPING.read_text())
    for group in mapping["groups"]:
        for producer in group["producers"]:
            assert (ROOT / producer).is_file(), producer


def test_nonexistent_run_rejected(tmp_path):
    with pytest.raises(ValueError, match="Run folder does not exist"):
        audit(CATALOG, MAPPING, tmp_path / "absent")
