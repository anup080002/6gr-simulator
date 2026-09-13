"""Audit retained receiver-noise evidence; never qualify a detector or run PHY.

Read the run's saved configuration, CSVs and IQ. Write a new, separate review
directory only after validation succeeds. A failed empirical reference remains
a failure in the plot/report; successful auditing is not conformance evidence.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
from pathlib import Path

import h5py
import numpy as np
from scipy.io import loadmat
from scipy.special import betaincinv


SCOPE = "component_only_no_conformance_or_ACK_miss_qualification"
SOURCE_FILES = ("configuration.mat", "noise_trials.csv", "noise_summary.csv", "noise_observations.mat")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(row, key, *, integer=False):
    try:
        value = float(row[key])
    except (KeyError, ValueError, TypeError) as error:
        raise ValueError(f"Missing/invalid numeric field {key}") from error
    require(math.isfinite(value), f"Nonfinite {key}")
    if integer:
        require(value == int(value), f"Noninteger {key}")
        return int(value)
    return value


def close(actual, expected, field):
    require(math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-14), f"Mismatch {field}")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_csv(path):
    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        require(reader.fieldnames is not None and len(set(reader.fieldnames)) == len(reader.fieldnames),
                f"Missing/duplicate columns: {path.name}")
        rows = list(reader)
        require(all(None not in row and all(value is not None for value in row.values()) for row in rows),
                f"Malformed rows: {path.name}")
        return rows


def audit_rows(trials, summaries, config, iq_hash, iq_shape):
    """Check exported statistics and provenance structure, not decoded IQ bits."""
    v, resource = config["v"], config["resource"]
    n = number(v, "noise_occasions", integer=True)
    bits_set = tuple(number({"bits": value}, "bits", integer=True) for value in np.atleast_1d(v["harq_bit_counts"]))
    require(n > 0 and len(bits_set) > 0 and len(set(bits_set)) == len(bits_set) and set(bits_set) <= {1, 2},
            "Unsupported/invalid noise fixture dimensions")
    require(number(resource, "format", integer=True) == 0, "This audit requires Format 0")
    symbols = number(resource, "nrof_symbols", integer=True)
    require(symbols in (1, 2), "Invalid Format-0 symbol count")
    key = f"detection_threshold_format0_{'one' if symbols == 1 else 'two'}_symbol{'s' if symbols == 2 else ''}"
    threshold = number(config["cfg"]["phy"]["pucch"]["receiverDetectionThresholds"], key)
    nr = number(config, "nr", integer=True)
    alpha, limit = number(v, "confidence_alpha"), number(v, "dtx_to_ack_requirement")
    require(nr > 0 and 0 < alpha < 1 and 0 <= limit <= 1 and 0 <= threshold <= 1,
            "Invalid saved receiver/reference configuration")
    require(len(trials) == n * len(bits_set), "Trial count differs from saved configuration")
    require(len(summaries) == len(bits_set), "Summary count differs from saved configuration")
    grouped, paired, digests = {bits: [] for bits in bits_set}, {}, set()
    paired_fields = ("AbsoluteSlot0", "StartSample", "EndSampleExclusive", "IQFirstRow", "IQRowCount",
                     "ReceiveBranches", "NoiseStreamSeed", "InjectedSampleNoiseVariance",
                     "ConfiguredReferenceEsN0_dB", "RFAppliedStageCount")
    for row in trials:
        occasion, bits = number(row, "Occasion", integer=True), number(row, "HARQBits", integer=True)
        require(1 <= occasion <= n and bits in bits_set, "Unexpected occasion/bit-count identity")
        identity = occasion, bits
        require(identity not in paired, "Duplicate occasion/bit-count identity")
        paired[identity] = row
        require(number(row, "SignalPresent", integer=True) == 0, "Signal-present row in noise evidence")
        require(number(row, "ReceiveBranches", integer=True) == nr, "Receiver dimensions differ from configuration")
        detected, ack = number(row, "Detected", integer=True), number(row, "FalseACKBits", integer=True)
        require(detected in (0, 1) and 0 <= ack <= bits and (detected or ack == 0),
                "Invalid detection/false-ACK counts")
        metric = number(row, "DetectionMetric")
        require(metric >= 0, "Negative detection metric")
        close(number(row, "DetectionThreshold"), threshold, "configured threshold")
        require(detected == int(metric >= threshold), "Detection disagrees with metric/threshold")
        require(row["DetectionThresholdSource"] == "yaml.pucch." + key, "Wrong threshold source")
        require(row["IQSHA256"] == iq_hash, "IQ hash mismatch")
        require(row["Source"] == v["evidence_scope"] and
                row["TimingSource"] == "prescribed_slot_window_not_acquired_sync", "Wrong component scope/timing")
        require(row.get("ReceiverImplementation") == "canonical_pucch_receiver", "Missing canonical receiver provenance")
        for field in ("ReceptionAssignmentDigest", "ReceiverContextDigest"):
            value = row.get(field, "")
            require(re.fullmatch("[0-9a-f]{64}", value) is not None, f"Invalid {field}")
            require((field, value) not in digests, f"Reused {field}")
            digests.add((field, value))
        require(number(row, "InjectedSampleNoiseVariance") > 0, "Missing injected noise variance")
        for field in ("AbsoluteSlot0", "StartSample", "NoiseStreamSeed", "RFAppliedStageCount"):
            require(number(row, field, integer=True) >= 0, f"Negative {field}")
        grouped[bits].append(row)
    next_iq, previous_end, previous_slot = 1, 0, -1
    for occasion in range(1, n + 1):
        rows = [paired[(occasion, bits)] for bits in bits_set]
        first = rows[0]
        for row in rows[1:]:
            require(all(number(row, field) == number(first, field) for field in paired_fields),
                    "Bit-count hypotheses do not share one physical observation")
        start = number(first, "StartSample", integer=True)
        end = number(first, "EndSampleExclusive", integer=True)
        count = number(first, "IQRowCount", integer=True)
        slot = number(first, "AbsoluteSlot0", integer=True)
        require(count > 0 and end - start == count and start >= previous_end and slot > previous_slot,
                "Invalid/overlapping physical observation windows")
        require(number(first, "IQFirstRow", integer=True) == next_iq, "Noncontiguous retained IQ indexing")
        next_iq += count
        previous_end, previous_slot = end, slot
    require(tuple(iq_shape) == (nr, next_iq - 1), "Retained MATLAB IQ dimensions/count differ from trials")
    result, summary_bits = [], set()
    for row in summaries:
        bits = number(row, "HARQBits", integer=True)
        require(bits in grouped and bits not in summary_bits, "Invalid/duplicate summary identity")
        summary_bits.add(bits)
        group = grouped[bits]
        acks = sum(number(t, "FalseACKBits", integer=True) for t in group)
        detections = sum(number(t, "Detected", integer=True) for t in group)
        any_ack = sum(number(t, "FalseACKBits", integer=True) > 0 for t in group)
        expected = dict(NoiseOccasions=n, ReceiveBranches=nr, FalseDetections=detections,
                        FalseACKBits=acks, ACKBitDenominator=n * bits, OccasionsWithFalseACK=any_ack,
                        EmpiricalFractionMeetsLimit=int(acks / (n * bits) <= limit))
        for field, value in expected.items():
            require(number(row, field, integer=True) == value, f"Summary mismatch {field}")
        upper = 1.0 if any_ack == n else float(betaincinv(any_ack + 1, n - any_ack, 1 - alpha))
        for field, value in dict(DTXToACKBitFraction=acks / (n * bits), ConfidenceAlpha=alpha,
                                 Requirement=limit, AnyACKUpperBoundUnderIIDOccasionAssumption=upper).items():
            close(number(row, field), value, field)
        require(row["QualificationStatus"] == SCOPE, "Overstated qualification scope")
        result.append(dict(HARQBits=bits, **expected, DTXToACKBitFraction=acks / (n * bits),
                           Requirement=limit, AnyACKUpperBoundUnderIIDOccasionAssumption=upper,
                           ConfidenceAlpha=alpha, QualificationStatus=SCOPE))
    return sorted(result, key=lambda row: row["HARQBits"])


def export_audit(run_root, output_root):
    run_root, output_root = Path(run_root).resolve(strict=True), Path(output_root).resolve()
    require(run_root != output_root and run_root not in output_root.parents and output_root not in run_root.parents,
            "Review must be separate from the retained run")
    require(not output_root.exists(), "Review directory already exists; refusing overwrite")
    hashes = {name: sha256(run_root / name) for name in SOURCE_FILES}
    config = loadmat(run_root / "configuration.mat", simplify_cells=True)
    trials, summaries = read_csv(run_root / "noise_trials.csv"), read_csv(run_root / "noise_summary.csv")
    with h5py.File(run_root / "noise_observations.mat", "r") as iq:
        shape = iq["IQ"].shape
        require(iq["IQ"].dtype.names == ("real", "imag"), "Expected retained complex MATLAB IQ")
        for start in range(0, shape[1], 65536):
            chunk = iq["IQ"][:, start:start + 65536]
            require(np.isfinite(chunk["real"]).all() and np.isfinite(chunk["imag"]).all(), "Nonfinite retained IQ")
    recomputed = audit_rows(trials, summaries, config, hashes["noise_observations.mat"], shape)
    # All calculations and checks precede the first output write.
    import matplotlib
    matplotlib.use("Agg")
    from matplotlib import pyplot as plt
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.5), layout="constrained")
    for row in recomputed:
        bits = row["HARQBits"]
        metrics = sorted(number(t, "DetectionMetric") for t in trials if number(t, "HARQBits", integer=True) == bits)
        axes[0].step(metrics, np.arange(1, len(metrics) + 1) / len(metrics), where="post", label=f"{bits}-bit hypothesis")
    threshold = number(trials[0], "DetectionThreshold")
    axes[0].axvline(threshold, color="black", linestyle="--", label=f"Configured threshold {threshold:g}")
    axes[0].set(xlabel="Retained detector metric", ylabel="Empirical cumulative fraction", ylim=(0, 1.03))
    axes[0].legend(fontsize=8)
    fractions = [100 * row["DTXToACKBitFraction"] for row in recomputed]
    bars = axes[1].bar([f'{row["HARQBits"]}-bit' for row in recomputed], fractions,
                       color=["#2878a0" if row["EmpiricalFractionMeetsLimit"] else "#c74440" for row in recomputed])
    axes[1].bar_label(bars, labels=[f'{row["FalseACKBits"]}/{row["ACKBitDenominator"]}\n{fraction:.6f}%'
                                  for row, fraction in zip(recomputed, fractions)], padding=4)
    limit = 100 * recomputed[0]["Requirement"]
    axes[1].axhline(limit, color="black", linestyle="--", label=f"Configured empirical reference {limit:g}%")
    axes[1].set(ylabel="False-ACK bits / available bit positions (%)", ylim=(0, max(fractions + [limit]) * 1.35))
    axes[1].legend(loc="lower right", fontsize=8)
    fig.suptitle("Canonical PUCCH receiver: retained noise/RF component\nNot conformance or signal-present ACK-miss qualification", fontsize=11)
    output_root.mkdir(parents=True, exist_ok=False)
    try:
        fig.savefig(output_root / "noise_detector_audit.png", dpi=150)
    finally:
        plt.close(fig)
    with (output_root / "recomputed_summary.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(recomputed[0]))
        writer.writeheader()
        writer.writerows(recomputed)
    report = dict(source_run=str(run_root), source_sha256=hashes,
                  audit_kind="retained_noise_csv_aggregation_and_iq_integrity_not_new_phy_execution",
                  auditor_sha256=sha256(Path(__file__)), summary=recomputed,
                  limitations=["Does not re-decode retained IQ or verify cryptographic assignment contents.",
                               "Checks consistency with the saved configuration, not full YAML inheritance.",
                               "IID bound is on occasions with any false ACK, not individual ACK bits.",
                               "Empirical reference checks are not conformance or ACK-miss qualification."],
                  output_sha256={name: sha256(output_root / name) for name in ("noise_detector_audit.png", "recomputed_summary.csv")})
    (output_root / "audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root", type=Path)
    parser.add_argument("output_root", type=Path)
    args = parser.parse_args()
    print(json.dumps(export_audit(args.run_root, args.output_root), indent=2))
