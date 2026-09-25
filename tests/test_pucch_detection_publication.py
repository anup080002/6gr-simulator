"""Declared publication fixtures, not a detector-qualification campaign."""
import csv
import io
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as materializer


@pytest.mark.parametrize("fields,bucket", [
    ({"DetectionOutcome": "detected", "UCIContentMatch": 0, "BitErrors": 5,
      "PUCCHDecodeOk": 1, "Status": "FAIL"}, "Detected; payload incorrect"),
    ({"DetectionOutcome": "detected", "BitErrors": 2}, "Detected; payload incorrect"),
    ({"DetectionOutcome": "detected", "CRCPass": 0}, "Detected; decode failure"),
    ({"DetectionOutcome": "detected", "UCIContentMatch": 1}, "Decoded/observed"),
    ({"DetectionOutcome": "unavailable", "DTXFlag": 1}, "Unavailable"),
    ({"DetectionMetricValid": 0, "DTXFlag": 1}, "Unavailable"),
    ({"DetectionOutcome": "dtx", "DTXFlag": 1}, "DTX"),
    ({"DetectionOutcome": "dtx", "DTXFlag": 1, "MissedDetection": 1}, "Missed detection"),
    ({"DetectionOutcome": "detected", "FalseAlarmFlag": 1}, "False alarm"),
    ({"DetectionAttempted": 0, "DTXFlag": 1}, "Detection not attempted"),
    ({"Status": "PASS", "UCIContentMatch": 1}, "Unavailable"),
    ({"Status": "FAIL", "UCIContentMatch": 0}, "Unavailable"),
])
def test_presence_is_separate_from_payload_scoring(fields, bucket):
    row = dict(Slot=34, UEID=1, DetectionAttempted=1)
    row.update(fields)
    raw = materializer._encode_dict_rows(list(row), [row])
    path = "air_interface/csv/pucch_trials.csv"
    existing = {path: {"artifact_id": 1, "logical_path": path}}
    out = materializer._pucch_dtx_chart_materialization(
        "PUCCH DTX statistics", existing, lambda _: raw, 1)
    assert out is not None and out["source_row_count"] == 1
    exported = list(csv.DictReader(io.StringIO(out["csv_bytes"].decode("utf-8"))))
    assert exported[0]["dtx_bucket"] == bucket
    assert exported[0]["detection_outcome"] == str(fields.get("DetectionOutcome", ""))
    if "BitErrors" in fields:
        assert float(exported[0]["bit_errors"]) == fields["BitErrors"]
