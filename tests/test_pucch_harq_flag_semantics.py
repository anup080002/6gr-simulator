"""Reject contradictory HARQ flags without confusing DTX with decoded NACK."""

import csv
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from lls_csv_semantics import _audit_control_table


def audit(**changes):
    row = {
        "ExpectedBitCount": "2", "DecodedBitCount": "2",
        "UCIExpectedBitVector": "10", "UCIDecodedBitVector": "10",
        "FalseAck": "0", "FalseNack": "0", "DTXFlag": "0",
        "DetectionMetric": "0.420294752122787",
    }
    row.update(changes)
    checks = _audit_control_table("air_interface/csv/pucch_trials.csv", list(row), [row])
    return next(check for check in checks if check.check_id == "harq_error_flag_consistency")


def test_matching_received_bits_have_no_false_harq_flags():
    assert audit().passed


@pytest.mark.parametrize("flag", ["FalseAck", "FalseNack"])
def test_matching_bit_vectors_cannot_claim_false_ack_or_nack(flag):
    result = audit(**{flag: "1"})
    assert not result.passed
    assert "matched_uci_has_" + flag in result.details


@pytest.mark.parametrize("flag", ["FalseAck", "FalseNack"])
def test_receiver_dtx_cannot_claim_a_decoded_harq_error(flag):
    result = audit(DTXFlag="1", UCIDecodedBitVector="", DecodedBitCount="0", **{flag: "1"})
    assert not result.passed
    assert "receiver_dtx_has_" + flag in result.details


@pytest.mark.parametrize("flag", ["FalseAck", "FalseNack"])
def test_mismatched_bits_can_have_real_false_harq_flags(flag):
    assert audit(UCIDecodedBitVector="01", **{flag: "1"}).passed


def test_dtx_without_decoded_bits_is_not_automatically_false_nack():
    assert audit(DTXFlag="1", UCIDecodedBitVector="", DecodedBitCount="0").passed


@pytest.mark.parametrize("value", ["", "NaN", "2", "-1", "unknown"])
def test_invalid_exported_harq_boolean_fails(value):
    assert not audit(FalseAck=value).passed


def test_no_payload_does_not_create_a_matching_payload_claim():
    assert audit(UCIExpectedBitVector="", UCIDecodedBitVector="", DTXFlag="0").passed


def test_retained_shared_waveform_row_passes_but_corrupted_flags_fail():
    path = Path(__file__).resolve().parents[1] / (
        "docs/lls/evidence_20260913/pucch_baseline_signal_04/received_pucch_trials.csv"
    )
    with path.open(newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == 1
    row = rows[0]
    assert row["UCIExpectedBitVector"] == row["UCIDecodedBitVector"] == "10"
    assert audit(**row).passed
    for flag in ("FalseAck", "FalseNack"):
        changed = dict(row, **{flag: "1"})
        assert not audit(**changed).passed
