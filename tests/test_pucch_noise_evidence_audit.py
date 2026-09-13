"""Mutation coverage for aggregation/provenance; synthetic digests are test-only."""
import hashlib
import sys
from pathlib import Path

import h5py
import pytest
from scipy.io import loadmat

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from audit_pucch_noise_evidence import audit_rows, export_audit, read_csv, sha256

RETAINED = Path(__file__).resolve().parents[1] / "docs/lls/evidence_20260913/pucch_baseline_noise_rf_01"


@pytest.fixture
def inputs():
    trials = read_csv(RETAINED / "noise_trials.csv")
    # The original artifact is direct-Toolbox evidence, not canonical-receiver
    # evidence. Add fake provenance only in this in-memory structural fixture.
    for index, row in enumerate(trials):
        row["ReceiverImplementation"] = "canonical_pucch_receiver"
        for field in ("ReceptionAssignmentDigest", "ReceiverContextDigest"):
            row[field] = hashlib.sha256(f"test-only-{field}-{index}".encode()).hexdigest()
    config = loadmat(RETAINED / "configuration.mat", simplify_cells=True)
    with h5py.File(RETAINED / "noise_observations.mat", "r") as iq:
        shape = iq["IQ"].shape
    return [trials, read_csv(RETAINED / "noise_summary.csv"), config, trials[0]["IQSHA256"], shape]


def test_recomputed_statistics_keep_failed_two_bit_reference(inputs):
    result = audit_rows(*inputs)
    assert [(r["FalseDetections"], r["FalseACKBits"]) for r in result] == [(8, 2), (16, 12)]
    assert result[0]["EmpiricalFractionMeetsLimit"] == 1
    assert result[1]["EmpiricalFractionMeetsLimit"] == 0


@pytest.mark.parametrize("field,value", [
    ("SignalPresent", "1"), ("Detected", "1"), ("Detected", "2"),
    ("FalseACKBits", "1"), ("FalseACKBits", "-1"), ("FalseACKBits", "1.5"),
    ("DetectionMetric", "NaN"), ("DetectionMetric", "-0.1"),
    ("DetectionThreshold", "0.1"), ("DetectionThresholdSource", "guessed"),
    ("IQSHA256", "0" * 64), ("IQFirstRow", "2"), ("IQRowCount", "0"),
    ("AbsoluteSlot0", "-1"), ("StartSample", "0"), ("EndSampleExclusive", "0"),
    ("HARQBits", "3"), ("Occasion", "0"), ("ReceiveBranches", "1"),
    ("Source", "conformance"), ("TimingSource", "acquired"),
    ("ReceiverImplementation", "toolbox_direct"), ("ReceptionAssignmentDigest", ""),
    ("ReceiverContextDigest", "not-a-hash"), ("InjectedSampleNoiseVariance", "0"),
])
def test_bad_trial_fields_rejected(inputs, field, value):
    inputs[0][0][field] = value
    with pytest.raises(ValueError):
        audit_rows(*inputs)


@pytest.mark.parametrize("field,value", [
    ("NoiseOccasions", "511"), ("ACKBitDenominator", "1024"), ("FalseACKBits", "0"),
    ("FalseDetections", "0"), ("DTXToACKBitFraction", "0"), ("OccasionsWithFalseACK", "0"),
    ("AnyACKUpperBoundUnderIIDOccasionAssumption", "0.00390625"),
    ("ConfidenceAlpha", "0.1"), ("Requirement", "0.02"),
    ("QualificationStatus", "conformance_pass"), ("EmpiricalFractionMeetsLimit", "2"),
])
def test_bad_summary_fields_rejected(inputs, field, value):
    inputs[1][0][field] = value
    with pytest.raises(ValueError):
        audit_rows(*inputs)


def test_failed_two_bit_limit_cannot_be_relabelled_pass(inputs):
    inputs[1][1]["EmpiricalFractionMeetsLimit"] = "1"
    with pytest.raises(ValueError, match="EmpiricalFractionMeetsLimit"):
        audit_rows(*inputs)


def test_dropped_trial_rejected(inputs):
    inputs[0].pop()
    with pytest.raises(ValueError, match="Trial count"):
        audit_rows(*inputs)


def test_duplicate_trial_rejected(inputs):
    inputs[0][1] = dict(inputs[0][0])
    with pytest.raises(ValueError, match="Duplicate"):
        audit_rows(*inputs)


def test_hypotheses_must_share_observation(inputs):
    inputs[0][1]["NoiseStreamSeed"] = "1"
    with pytest.raises(ValueError, match="share one physical observation"):
        audit_rows(*inputs)


def test_assignment_digest_must_identify_observation_context(inputs):
    inputs[0][1]["ReceptionAssignmentDigest"] = inputs[0][0]["ReceptionAssignmentDigest"]
    with pytest.raises(ValueError, match="Reused"):
        audit_rows(*inputs)


def test_truncated_iq_rejected(inputs):
    inputs[4] = (inputs[4][0], inputs[4][1] - 1)
    with pytest.raises(ValueError, match="IQ dimensions"):
        audit_rows(*inputs)


def test_invalid_config_bit_count_is_not_truncated(inputs):
    inputs[2]["v"]["harq_bit_counts"] = [1.5, 2]
    with pytest.raises(ValueError, match="Noninteger"):
        audit_rows(*inputs)


def test_original_direct_toolbox_evidence_is_not_canonical_evidence(inputs):
    inputs[0] = read_csv(RETAINED / "noise_trials.csv")
    with pytest.raises(ValueError, match="canonical receiver"):
        audit_rows(*inputs)


def test_review_cannot_replace_source():
    with pytest.raises(ValueError, match="separate"):
        export_audit(RETAINED, RETAINED)


def test_review_cannot_overwrite_existing_output(tmp_path):
    with pytest.raises(ValueError, match="already exists"):
        export_audit(RETAINED, tmp_path)


def test_actual_canonical_evidence_exports_source_bound_review(tmp_path):
    source = RETAINED.parent / "pucch_canonical_receiver_noise_01"
    output = tmp_path / "review"
    report = export_audit(source, output)
    assert report["source_sha256"]["noise_observations.mat"] == sha256(source / "noise_observations.mat")
    assert report["summary"][1]["EmpiricalFractionMeetsLimit"] == 0
    assert report["summary"][1]["FalseACKBits"] == 12
    for name, digest in report["output_sha256"].items():
        assert sha256(output / name) == digest
