"""Read-only checks of observed UL evidence, not PHY qualification.

Accepts complete CSV bytes atomically published by the running simulator.
Receipts record those bytes; observations from different files need not be
from the same live checkpoint. No missing waveform/measurement is invented.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path


def number(row: dict, name: str) -> float | None:
    try:
        value = float(row.get(name, ""))
        return value if math.isfinite(value) else None
    except (TypeError, ValueError):
        return None


def flag(row: dict, name: str) -> bool | None:
    value = str(row.get(name, "")).strip().lower()
    return {"1": True, "true": True, "0": False, "false": False}.get(value)


def audit_rows(channel: str, rows: list[dict]) -> list[dict]:
    checks = []

    def check(index, row, name, passed, detail):
        checks.append(dict(Channel=channel, CSVRow=index + 2,
                           Slot=row.get("Slot", ""), Check=name,
                           Passed=bool(passed), Detail=detail))

    for index, row in enumerate(rows):
        if channel == "SRS" and flag(row, "SRSRuntimeEvidenceUsable") is True:
            provenance = str(row.get("RuntimeEvidenceSource", "")).strip().lower()
            available_source = provenance not in ("", "nan", "unavailable") and not provenance.startswith(
                ("not_emitted_by_active_", "not_recorded_by_active_", "field_not_emitted_by_active_"))
            check(index, row, "usable_srs_runtime_provenance", available_source,
                  "Usable runtime SRS requires its actual producer provenance, not a missing-field token.")
        if channel == "SRS" and row.get("RuntimeTransportMode") == "shared_physical_stream_SRS_received_completion":
            start, end, fs, completion = [number(row, name) for name in (
                "ObservationStartSample", "ObservationEndSampleExclusive", "ObservationSampleRateHz",
                "ObservationCompletionTime_s")]
            clock_ok = all(value is not None for value in (start, end, fs, completion))
            clock_ok = clock_ok and fs > 0 and 0 <= start < end and start == int(start) and end == int(end)
            check(index, row, "shared_srs_observation_clock", clock_ok and
                  math.isclose(completion, end / fs, rel_tol=0, abs_tol=1e-12),
                  "Actual completed capture must retain integral sample bounds and its exact completion time.")
            if flag(row, "RuntimeStateUpdated") is True:
                delivery = number(row, "ObservationDeliveryTime_s")
                check(index, row, "shared_srs_no_future_delivery", clock_ok and delivery is not None and
                      completion <= delivery + 1e-12,
                      "Scheduler consumption cannot precede completed actual SRS observation.")
        expected = str(row.get("UCIExpectedBitVector", "")).strip()
        decoded = str(row.get("UCIDecodedBitVector", "")).strip()
        errors = str(row.get("UCIBitErrorVector", "")).strip()
        # NaN denotes unavailable evidence, not a bit string.
        expected = "" if expected.lower() == "nan" else expected
        decoded = "" if decoded.lower() == "nan" else decoded
        errors = "" if errors.lower() == "nan" else errors
        if expected or decoded or errors:
            binary = all(set(bits) <= {"0", "1"} for bits in (expected, decoded, errors))
            check(index, row, "uci_binary_vectors", binary,
                  "Expected/decoded/error evidence must be literal binary strings.")
            for field, bits in (("ExpectedBitCount", expected), ("DecodedBitCount", decoded),
                                ("PUCCHExpectedBitCount", expected), ("PUCCHDecodedBitCount", decoded)):
                if field in row:
                    check(index, row, field + "_closure", number(row, field) == len(bits),
                          f"Published count={row[field]}; vector length={len(bits)}.")
            if expected and decoded and binary:
                match = expected == decoded
                if "UCIContentMatch" in row:
                    check(index, row, "uci_content_match_closure", flag(row, "UCIContentMatch") == match,
                          "Content equality is checked independently of CRC applicability.")
                if errors:
                    xor = "".join(str(int(a) ^ int(b)) for a, b in zip(expected, decoded))
                    check(index, row, "uci_error_vector_closure",
                          len(expected) == len(decoded) and errors == xor,
                          "Published error vector must match bit-by-bit XOR, including leading zeroes.")
            if channel == "PUCCH" and flag(row, "PUCCHDecodeOk") is True:
                check(index, row, "successful_pucch_has_complete_payload",
                      bool(expected) and len(expected) == len(decoded),
                      "A successful receive requires a complete decoded payload, not only a status label.")
        elif channel == "PUCCH" and flag(row, "PUCCHDecodeOk") is True:
            check(index, row, "successful_pucch_has_complete_payload", False,
                  "Successful PUCCH has no retained UCI bit vectors.")

        if "UCICRCBitCount" in row and number(row, "UCICRCBitCount") is not None:
            crc_bits = number(row, "UCICRCBitCount")
            check(index, row, "uci_crc_applicability", flag(row, "UCICRCApplicable") == (crc_bits > 0),
                  f"Published UCI CRC length={crc_bits}; applicability must agree.")
        # PUSCH TB CRC is independent of UCI CRC and must not be conflated.
        if channel == "PUCCH" and flag(row, "CRCApplicable") is False:
            check(index, row, "nonapplicable_pucch_crc_not_passed", number(row, "CRCPass") is None,
                  "Nonapplicable CRC must remain unavailable, not a numeric pass/fail.")
        # Union-schema exports contain empty generic fields alongside the
        # populated channel-specific source. Empty/NaN is not authoritative.
        source = next((str(row.get(name, "")).strip() for name in
                       ("TimingEstimateSource", "SRSReceiveTimingSource")
                       if str(row.get(name, "")).strip().lower() not in ("", "nan")), "")
        correction = number(row, "AppliedTimingCorrectionSamples")
        if correction is None:
            correction = number(row, "AppliedTimingCorrection_samples")
        if source.startswith("received_") and correction is not None and correction != 0:
            check(index, row, "measured_timing_application_flag", flag(row, "TimingEstimateUsed") is True,
                  f"Received-reference timing applied {correction} samples; application flag must agree.")
    return checks


def audit_run(run_root: Path) -> dict:
    checks, sources, coverage = [], [], {}
    for channel, stem in (("PRACH", "prach"), ("PUCCH", "pucch"),
                          ("PUSCH", "ul_pusch"), ("SRS", "srs")):
        relative = Path("air_interface/csv") / (stem + "_trials.csv")
        path = run_root / relative
        if not path.is_file():
            coverage[channel] = dict(State="not_observed", Rows=0)
            continue
        content = path.read_bytes()
        reader = csv.DictReader(io.StringIO(content.decode("utf-8-sig")))
        if not reader.fieldnames or not any(reader.fieldnames):
            coverage[channel] = dict(State="missing_schema", Rows=0)
            checks.append(dict(Channel=channel, CSVRow=1, Slot="", Check="csv_schema",
                               Passed=False, Detail="Published CSV has no header."))
            rows = []
        else:
            rows = list(reader)
            coverage[channel] = dict(State="observed" if rows else "not_observed", Rows=len(rows))
            checks.extend(audit_rows(channel, rows))
        sources.append(dict(Path=relative.as_posix(), SHA256=hashlib.sha256(content).hexdigest(),
                            Bytes=len(content), Rows=len(rows)))
    return dict(Scope="observed_uplink_evidence_consistency_not_phy_qualification",
                CrossFileAtomicCheckpoint=False, RunRoot=str(run_root.resolve()),
                Coverage=coverage, Sources=sources, Checks=checks,
                FailedChecks=sum(not item["Passed"] for item in checks),
                UnobservedChannels=[key for key, value in coverage.items() if value["State"] != "observed"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit_run(args.run_root)
    # Immutable audit receipt: never overwrite an earlier observed checkpoint.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2, allow_nan=False)
        handle.write("\n")
    print(json.dumps({key: result[key] for key in ("Coverage", "FailedChecks", "UnobservedChannels")}))
    return 1 if result["FailedChecks"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
