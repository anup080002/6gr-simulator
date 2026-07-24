#!/usr/bin/env python3
"""Fail-closed verifier for the PDSCH/DL-SCH remediation artifacts.

The MATLAB phase runner must generate production-derived CSV files and PNG
figures in one output directory.  This script verifies file presence, CSV
schemas, primary-key uniqueness, numerical invariants, test completion, PNG
integrity, and MATLAB-recorded figure semantics.

It does not infer plot meaning from pixels.  Semantic checks use
pdsch_image_semantic_audit.csv, then bind those records to the actual source
CSV and PNG bytes with SHA-256.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import math
import os
import shutil
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

try:
    from PIL import Image, ImageDraw, ImageStat
except ImportError as exc:  # pragma: no cover
    raise SystemExit("Pillow is required: python -m pip install Pillow") from exc

HERE = Path(__file__).resolve().parent
CSV_CONTRACT_FILE = HERE / "desired_pdsch_csv_contract.csv"
IMAGE_CONTRACT_FILE = HERE / "desired_pdsch_image_contract.csv"


@dataclass(frozen=True)
class CsvContract:
    name: str
    columns: tuple[str, ...]
    key: tuple[str, ...]


@dataclass(frozen=True)
class ImageContract:
    name: str
    sources: tuple[str, ...]
    xlabel: str
    ylabel: str
    title_token: str
    min_axes: int
    min_series: int
    min_points: int
    min_width: int
    min_height: int


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def read_contracts() -> tuple[dict[str, CsvContract], dict[str, ImageContract]]:
    csv_contracts: dict[str, CsvContract] = {}
    with CSV_CONTRACT_FILE.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            if str(row.get("Required", "1")).strip() not in {"1", "true", "TRUE", "yes", "YES"}:
                continue
            name = str(row["FileName"]).strip()
            csv_contracts[name] = CsvContract(
                name,
                tuple(x.strip() for x in str(row["RequiredColumns"]).split("|") if x.strip()),
                tuple(x.strip() for x in str(row["PrimaryKey"]).split("|") if x.strip()),
            )
    image_contracts: dict[str, ImageContract] = {}
    with IMAGE_CONTRACT_FILE.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            name = str(row["ImageFile"]).strip()
            image_contracts[name] = ImageContract(
                name,
                tuple(x.strip() for x in str(row["SourceCSV"]).split("|") if x.strip()),
                str(row["ExpectedXLabel"]).strip(),
                str(row["ExpectedYLabel"]).strip(),
                str(row["ExpectedTitleToken"]).strip(),
                int(row["MinAxesCount"]),
                int(row["MinSeriesCount"]),
                int(row["MinFinitePointCount"]),
                int(row["MinWidth"]),
                int(row["MinHeight"]),
            )
    return csv_contracts, image_contracts


def finite(value: object) -> float | None:
    try:
        number = float(str(value).strip())
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def integer(value: object) -> int | None:
    number = finite(value)
    if number is None or abs(number - round(number)) > 1e-9:
        return None
    return int(round(number))


def truth(value: object) -> bool | None:
    token = str(value).strip().upper()
    if token in {"1", "TRUE", "YES", "Y", "PASS"}:
        return True
    if token in {"0", "FALSE", "NO", "N", "FAIL"}:
        return False
    return None


def norm_text(value: object) -> str:
    return " ".join(str(value).strip().split())


def read_rectangular_csv(path: Path) -> tuple[list[str], list[dict[str, str]], list[str]]:
    errors: list[str] = []
    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        raw = list(csv.reader(handle))
    if not raw:
        return [], [], ["empty_file"]
    header = raw[0]
    if not header or any(not str(x).strip() for x in header):
        errors.append("empty_header_name")
    if len(set(header)) != len(header):
        errors.append("duplicate_header_name")
    width = len(header)
    for line, values in enumerate(raw[1:], start=2):
        if len(values) != width:
            errors.append(f"nonrectangular_line:{line}:expected={width}:actual={len(values)}")
    if errors:
        return header, [], errors
    rows = [dict(zip(header, values, strict=True)) for values in raw[1:]]
    if not rows:
        errors.append("no_data_rows")
    return header, rows, errors


def duplicate_keys(rows: Iterable[dict[str, str]], fields: Sequence[str]) -> list[str]:
    seen: set[tuple[str, ...]] = set()
    dup: list[str] = []
    for line, row in enumerate(rows, start=2):
        key = tuple(str(row.get(field, "")) for field in fields)
        if key in seen:
            dup.append(f"line={line}:key={key}")
        seen.add(key)
    return dup


def result(name: str, kind: str, reasons: list[str], **extra: object) -> dict[str, object]:
    row: dict[str, object] = {
        "Artifact": name,
        "Type": kind,
        "Status": "PASS" if not reasons else "FAIL",
        "Reason": ";".join(reasons),
    }
    row.update(extra)
    return row


def require_nonnegative(row: dict[str, str], field: str, line: int, reasons: list[str]) -> float | None:
    value = finite(row.get(field, ""))
    if value is None or value < 0:
        reasons.append(f"invalid_nonnegative:{field}:line={line}:value={row.get(field, '')}")
        return None
    return value


def require_probability(row: dict[str, str], field: str, line: int, reasons: list[str]) -> float | None:
    value = finite(row.get(field, ""))
    if value is None or not 0 <= value <= 1:
        reasons.append(f"invalid_probability:{field}:line={line}:value={row.get(field, '')}")
        return None
    return value


def validate_specific_csv(name: str, rows: list[dict[str, str]], reasons: list[str]) -> None:
    if name == "pdsch_assignment_resolution.csv":
        for line, row in enumerate(rows, 2):
            profile = str(row.get("Profile", "")).lower()
            source = str(row.get("Source", "")).lower()
            created = truth(row.get("AssignmentCreated", ""))
            allowed = truth(row.get("WaveformAllowed", ""))
            if created is None or allowed is None:
                reasons.append(f"invalid_assignment_or_waveform_flag:line={line}")
                continue
            if allowed and not created:
                reasons.append(f"waveform_allowed_without_assignment:line={line}")
            if not created:
                if allowed:
                    reasons.append(f"rejected_assignment_generated_waveform:line={line}")
                if str(row.get("ErrorIdentifier", "")).strip() == "":
                    reasons.append(f"rejected_assignment_missing_error:line={line}")
                continue

            if str(row.get("ErrorIdentifier", "")).strip() != "":
                reasons.append(f"created_assignment_has_error:line={line}:error={row.get('ErrorIdentifier','')}")
            if not allowed:
                reasons.append(f"created_assignment_not_waveform_allowed:line={line}")

            if profile in {"connected_strict", "ra_si_strict"}:
                if not ("decoded" in source and ("ue" in source or "rrc" in source or "procedure" in source)):
                    reasons.append(f"strict_assignment_not_decoded_context:line={line}:source={source}")
                if str(row.get("DecodedDCIId", "")).strip() == "":
                    reasons.append(f"missing_decoded_dci_id:line={line}")
                if str(row.get("DCIFormat", "")).strip() == "":
                    reasons.append(f"missing_dci_format:line={line}")
                if truth(row.get("DCICRCPass", "")) is not True:
                    reasons.append(f"created_assignment_dci_crc_not_pass:line={line}")
                if truth(row.get("DCIRNTIMatch", "")) is not True:
                    reasons.append(f"created_assignment_rnti_not_match:line={line}")
            elif profile == "sps_strict":
                if not ("sps" in source and "activation" in source and ("rrc" in source or "context" in source)):
                    reasons.append(f"sps_assignment_not_activation_context:line={line}:source={source}")
                if str(row.get("SPSConfigID", "")).strip() == "":
                    reasons.append(f"missing_sps_config_id:line={line}")
                if str(row.get("SPSActivationDCIId", "")).strip() == "":
                    reasons.append(f"missing_sps_activation_dci_id:line={line}")
                if truth(row.get("SPSActivationDCICRCPass", "")) is not True:
                    reasons.append(f"sps_activation_dci_crc_not_pass:line={line}")
                if truth(row.get("SPSActivationDCIRNTIMatch", "")) is not True:
                    reasons.append(f"sps_activation_dci_rnti_not_match:line={line}")
                if integer(row.get("SPSConfigurationEpoch", "")) is None:
                    reasons.append(f"invalid_sps_configuration_epoch:line={line}")
                if truth(row.get("SPSActivated", "")) is not True:
                    reasons.append(f"sps_assignment_not_activated:line={line}")
                if truth(row.get("SPSReleased", "")) is not False:
                    reasons.append(f"sps_assignment_released_or_unknown:line={line}")
                if integer(row.get("SPSOccasionIndex", "")) is None:
                    reasons.append(f"invalid_sps_occasion_index:line={line}")
            elif profile == "phy_calibration":
                if "calibration" not in source:
                    reasons.append(f"calibration_assignment_wrong_source:line={line}:source={source}")
                if str(row.get("DecodedDCIId", "")).strip() != "":
                    reasons.append(f"calibration_assignment_has_decoded_dci:line={line}")
                if str(row.get("SPSActivationDCIId", "")).strip() != "":
                    reasons.append(f"calibration_assignment_has_sps_activation:line={line}")
            else:
                reasons.append(f"unknown_assignment_profile:line={line}:profile={profile}")

            for field in ("MCSIndex", "NDI", "RV", "HARQProcessID"):
                if integer(row.get(field, "")) is None:
                    reasons.append(f"invalid_integer:{field}:line={line}")

    elif name == "pdsch_resource_ownership.csv":
        owners: dict[tuple[str, ...], set[str]] = {}
        for line, row in enumerate(rows, 2):
            collisions = integer(row.get("CollisionCount", ""))
            if collisions != 0:
                reasons.append(f"resource_collision:line={line}:count={row.get('CollisionCount','')}")
            key = tuple(row.get(x, "") for x in ("CaseID", "Slot", "PRB", "Symbol", "Subcarrier"))
            owners.setdefault(key, set()).add(str(row.get("Owner", "")))
        for key, values in owners.items():
            if len(values) != 1:
                reasons.append(f"multiple_owners:key={key}:owners={sorted(values)}")

    elif name == "pdsch_re_mapping.csv":
        for line, row in enumerate(rows, 2):
            idx = integer(row.get("LinearIndex0Based", ""))
            if idx is None or idx < 0:
                reasons.append(f"invalid_zero_based_index:line={line}")
            if str(row.get("Domain", "")).upper() not in {"DATA", "DMRS", "PTRS", "RESERVED"}:
                reasons.append(f"invalid_domain:line={line}:value={row.get('Domain','')}")

    elif name == "pdsch_dmrs_matrix.csv":
        for line, row in enumerate(rows, 2):
            if str(row.get("MappingType", "")).upper() not in {"A", "B"}:
                reasons.append(f"invalid_mapping_type:line={line}")
            if integer(row.get("DMRSRECount", "")) in {None, 0}:
                reasons.append(f"invalid_dmrs_re_count:line={line}")
            mismatch = integer(row.get("IndexMismatchCount", ""))
            if mismatch != 0:
                reasons.append(f"dmrs_index_mismatch:line={line}:value={row.get('IndexMismatchCount','')}")
            nmse = finite(row.get("SequenceNMSE", ""))
            if nmse is None or nmse > 1e-12:
                reasons.append(f"dmrs_sequence_nmse:line={line}:value={row.get('SequenceNMSE','')}")

    elif name == "pdsch_ptrs_matrix.csv":
        for line, row in enumerate(rows, 2):
            expected = truth(row.get("ExpectedPresent", ""))
            count = integer(row.get("PTRSRECount", ""))
            if expected is None or count is None or count < 0:
                reasons.append(f"invalid_ptrs_presence_or_count:line={line}")
            elif expected and count == 0:
                reasons.append(f"expected_ptrs_missing:line={line}")
            before_cpe = finite(row.get("CPEBeforeDeg", ""))
            after_cpe = finite(row.get("CPEAfterDeg", ""))
            before_evm = finite(row.get("EVMBeforePercent", ""))
            after_evm = finite(row.get("EVMAfterPercent", ""))
            if None in {before_cpe, after_cpe, before_evm, after_evm}:
                reasons.append(f"invalid_ptrs_metrics:line={line}")
            elif expected and (abs(after_cpe) > abs(before_cpe) + 1e-9 or after_evm > before_evm + 1e-9):
                reasons.append(f"ptrs_did_not_improve_or_hold_metrics:line={line}")

    elif name == "pdsch_coding_chain.csv":
        for line, row in enumerate(rows, 2):
            tbs = integer(row.get("TBS", ""))
            g = integer(row.get("G", ""))
            rm = integer(row.get("RateMatchedBits", ""))
            if tbs is None or tbs <= 0:
                reasons.append(f"invalid_tbs:line={line}")
            if g is None or rm is None or g <= 0 or g != rm:
                reasons.append(f"g_rate_match_mismatch:line={line}:G={g}:RateMatchedBits={rm}")
            if integer(row.get("BaseGraph", "")) not in {1, 2}:
                reasons.append(f"invalid_base_graph:line={line}")
            if truth(row.get("CRCOK", "")) is not True:
                reasons.append(f"crc_not_ok:line={line}")

    elif name == "pdsch_independent_vector_results.csv":
        families: set[str] = set()
        for line, row in enumerate(rows, 2):
            families.add(str(row.get("VectorFamily", "")).strip().lower())
            mismatch = integer(row.get("MismatchCount", ""))
            err = finite(row.get("MaxAbsError", ""))
            tol = finite(row.get("Tolerance", ""))
            if mismatch != 0:
                reasons.append(f"independent_vector_mismatch:line={line}:count={row.get('MismatchCount','')}")
            if err is None or tol is None or err > tol + 1e-15:
                reasons.append(f"independent_vector_tolerance_failure:line={line}")
            expected = str(row.get("ExpectedDigest", "")).strip()
            actual = str(row.get("ActualDigest", "")).strip()
            if expected and actual and expected != actual:
                reasons.append(f"independent_vector_digest_mismatch:line={line}")
        required = {
            "scrambling", "modulation", "layer_mapping", "tbs", "tb_crc",
            "ldpc_segmentation", "ldpc_encoding", "rate_matching",
            "dmrs_positions", "dmrs_ports", "dmrs_sequence", "ptrs_indices",
            "reserved_re", "precoding_application", "harq_combining",
            "receiver_chain",
        }
        missing = sorted(required - families)
        if missing:
            reasons.append("missing_independent_vector_families:" + ",".join(missing))

    elif name == "pdsch_layer_codeword_map.csv":
        ranks: set[int] = set()
        for line, row in enumerate(rows, 2):
            rank = integer(row.get("Rank", ""))
            if rank is None or not 1 <= rank <= 8:
                reasons.append(f"invalid_rank:line={line}")
            else:
                ranks.add(rank)
            if integer(row.get("MismatchCount", "")) != 0:
                reasons.append(f"layer_mapping_mismatch:line={line}")
            mapped = integer(row.get("MappedSymbolCount", ""))
            if mapped is None or mapped <= 0:
                reasons.append(f"invalid_mapped_symbol_count:line={line}")
        if ranks != set(range(1, 9)):
            reasons.append(f"rank_coverage_incomplete:{sorted(ranks)}")

    elif name == "pdsch_precoding_application.csv":
        modes: set[str] = set()
        for line, row in enumerate(rows, 2):
            modes.add(str(row.get("Mode", "")).strip().lower())
            if str(row.get("MatrixDigest", "")) != str(row.get("AppliedMatrixDigest", "")):
                reasons.append(f"precoder_digest_mismatch:line={line}")
            if integer(row.get("TXApplicationCount", "")) in {None, 0}:
                reasons.append(f"tx_precoder_not_applied:line={line}")
            if integer(row.get("RXApplicationCount", "")) in {None, 0}:
                reasons.append(f"rx_precoder_not_applied:line={line}")
            power_error = finite(row.get("PowerRelativeError", ""))
            if power_error is None or power_error > 1e-8:
                reasons.append(f"precoding_power_error:line={line}:value={row.get('PowerRelativeError','')}")
        if not any("wideband" in x for x in modes):
            reasons.append("missing_wideband_precoding_case")
        if not any("prg" in x or "frequency" in x for x in modes):
            reasons.append("missing_frequency_selective_precoding_case")

    elif name == "pdsch_harq_trials.csv":
        by_proc_cw: dict[tuple[str, str, str], list[dict[str, str]]] = {}
        for line, row in enumerate(rows, 2):
            key = (row.get("CaseID", ""), row.get("HARQProcessID", ""), row.get("Codeword", ""))
            by_proc_cw.setdefault(key, []).append(row)
            if integer(row.get("RV", "")) not in {0, 1, 2, 3}:
                reasons.append(f"invalid_rv:line={line}")
        if not any(len(v) >= 2 for v in by_proc_cw.values()):
            reasons.append("no_multi_transmission_harq_case")
        if not any(truth(row.get("Combined", "")) is True for row in rows):
            reasons.append("no_soft_combining_observed")
        if not any(truth(row.get("TBCRCOK", "")) is True for row in rows):
            reasons.append("no_successful_harq_decode")

    elif name == "pdsch_receiver_metrics.csv":
        ranks: set[int] = set()
        for line, row in enumerate(rows, 2):
            rank = integer(row.get("Rank", ""))
            if rank is not None:
                ranks.add(rank)
            for field in ("MeasuredSINRdB", "EVMPercent", "ChannelEstimateNMSEdB"):
                if finite(row.get(field, "")) is None:
                    reasons.append(f"invalid_receiver_metric:{field}:line={line}")
            require_probability(row, "BER", line, reasons)
            require_probability(row, "BLER", line, reasons)
        if not ({1, 2, 4, 8} <= ranks):
            reasons.append(f"receiver_rank_coverage_missing:{sorted({1,2,4,8} - ranks)}")

    elif name == "pdsch_bler_curve.csv":
        campaign_points: dict[str, int] = {}
        canonical_stop = {"CI_AND_MIN_ERRORS_MET", "MAX_TB_CENSORED_BOUND_MET", "FIXED_TRIAL_BUDGET_COMPLETE"}
        for line, row in enumerate(rows, 2):
            campaign = str(row.get("CampaignID", ""))
            campaign_points[campaign] = campaign_points.get(campaign, 0) + 1
            trials = integer(row.get("Trials", ""))
            errors = integer(row.get("TBErrors", ""))
            bler = require_probability(row, "BLER", line, reasons)
            low = require_probability(row, "CILower", line, reasons)
            high = require_probability(row, "CIUpper", line, reasons)
            if trials is None or errors is None or trials <= 0 or errors < 0 or errors > trials:
                reasons.append(f"invalid_trial_counts:line={line}")
            elif bler is not None and abs(bler - errors / trials) > max(1e-12, 0.5 / trials):
                reasons.append(f"bler_count_mismatch:line={line}")
            if None not in {low, bler, high} and not (low <= bler <= high):
                reasons.append(f"ci_does_not_enclose_bler:line={line}")
            stop = str(row.get("StopReason", "")).strip().upper()
            if stop not in canonical_stop:
                reasons.append(f"noncanonical_or_incomplete_stop_reason:line={line}:value={stop}")
        for campaign, count in campaign_points.items():
            if count < 4:
                reasons.append(f"too_few_operating_points:campaign={campaign}:count={count}")

    elif name == "pdsch_negative_tests.csv":
        for line, row in enumerate(rows, 2):
            expected = str(row.get("ExpectedErrorIdentifier", "")).strip()
            actual = str(row.get("ActualErrorIdentifier", "")).strip()
            if not expected or expected != actual:
                reasons.append(f"negative_error_mismatch:line={line}:expected={expected}:actual={actual}")
            if truth(row.get("WaveformGenerated", "")) is not False:
                reasons.append(f"negative_case_generated_waveform:line={line}")

    elif name == "pdsch_test_summary.csv":
        for line, row in enumerate(rows, 2):
            total = integer(row.get("Total", ""))
            passed = integer(row.get("Passed", ""))
            failed = integer(row.get("Failed", ""))
            skipped = integer(row.get("Skipped", ""))
            blocked = integer(row.get("Blocked", ""))
            if None in {total, passed, failed, skipped, blocked} or total is None or total <= 0:
                reasons.append(f"invalid_test_summary_counts:line={line}")
            elif failed != 0 or skipped != 0 or blocked != 0 or passed != total:
                reasons.append(f"incomplete_or_failed_test_suite:line={line}:total={total}:passed={passed}:failed={failed}:skipped={skipped}:blocked={blocked}")


def verify_csvs(root: Path, contracts: dict[str, CsvContract]) -> tuple[list[dict[str, object]], dict[str, list[dict[str, str]]]]:
    results: list[dict[str, object]] = []
    parsed: dict[str, list[dict[str, str]]] = {}
    for name, contract in contracts.items():
        path = root / name
        reasons: list[str] = []
        if not path.is_file():
            results.append(result(name, "CSV", ["missing"]))
            continue
        try:
            header, rows, parse_errors = read_rectangular_csv(path)
            reasons.extend(parse_errors)
            missing = [field for field in contract.columns if field not in header]
            if missing:
                reasons.append("missing_columns:" + ",".join(missing))
            if rows and not missing:
                bad_status = [str(line) for line, row in enumerate(rows, 2)
                              if str(row.get("Status", "")).strip().upper() != "PASS"]
                if bad_status:
                    reasons.append("non_pass_rows:" + ",".join(bad_status[:50]))
                dup = duplicate_keys(rows, contract.key)
                if dup:
                    reasons.append("duplicate_primary_keys:" + "|".join(dup[:20]))
                validate_specific_csv(name, rows, reasons)
            results.append(result(name, "CSV", reasons, Rows=len(rows), Columns=len(header), Bytes=path.stat().st_size, SHA256=digest(path)))
            parsed[name] = rows
        except Exception as exc:  # pragma: no cover
            results.append(result(name, "CSV", [f"parse:{type(exc).__name__}:{exc}"]))
    return results, parsed


def nonblank_fraction(gray: Image.Image) -> float:
    histogram = gray.histogram()
    # Treat pixels darker than 250 as non-white content.
    return sum(histogram[:250]) / float(gray.width * gray.height)


def verify_pngs(root: Path, contracts: dict[str, ImageContract]) -> tuple[list[dict[str, object]], dict[str, dict[str, object]]]:
    results: list[dict[str, object]] = []
    metadata: dict[str, dict[str, object]] = {}
    for name, contract in contracts.items():
        path = root / name
        reasons: list[str] = []
        if not path.is_file():
            results.append(result(name, "PNG", ["missing"]))
            continue
        try:
            with Image.open(path) as image:
                image.load()
                width, height = image.size
                mode = image.mode
                gray = image.convert("L")
                stddev = float(ImageStat.Stat(gray).stddev[0])
                fraction = nonblank_fraction(gray)
            size = path.stat().st_size
            sha = digest(path)
            if width < contract.min_width or height < contract.min_height:
                reasons.append(f"dimensions_below_contract:{width}x{height}:minimum={contract.min_width}x{contract.min_height}")
            if size < 1000:
                reasons.append(f"file_too_small:{size}")
            if stddev <= 1.0:
                reasons.append(f"pixel_stddev_too_low:{stddev}")
            if fraction <= 0.001:
                reasons.append(f"nonblank_fraction_too_low:{fraction}")
            item = {"Width": width, "Height": height, "Mode": mode, "Bytes": size,
                    "PixelStdDev": stddev, "NonBlankFraction": fraction, "SHA256": sha}
            metadata[name] = item
            results.append(result(name, "PNG", reasons, **item))
        except Exception as exc:
            results.append(result(name, "PNG", [f"decode:{type(exc).__name__}:{exc}"]))
    return results, metadata


def expected_source_hash_text(root: Path, sources: Sequence[str]) -> str | None:
    if not all((root / source).is_file() for source in sources):
        return None
    if len(sources) == 1:
        return digest(root / sources[0])
    return "|".join(f"{source}={digest(root / source)}" for source in sources)


def verify_semantic_audit(root: Path, image_contracts: dict[str, ImageContract],
                          parsed: dict[str, list[dict[str, str]]],
                          png_meta: dict[str, dict[str, object]]) -> list[dict[str, object]]:
    name = "pdsch_image_semantic_audit.csv"
    rows = parsed.get(name, [])
    results: list[dict[str, object]] = []
    by_name: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_name.setdefault(str(row.get("ImageFile", "")).strip(), []).append(row)
    for image_name, contract in image_contracts.items():
        reasons: list[str] = []
        matches = by_name.get(image_name, [])
        if len(matches) != 1:
            reasons.append(f"semantic_row_count:{len(matches)}")
            results.append(result(image_name, "SEMANTIC", reasons))
            continue
        row = matches[0]
        meta = png_meta.get(image_name)
        if meta is None:
            reasons.append("png_metadata_unavailable")
        expected_source = "|".join(contract.sources)
        if str(row.get("SourceCSV", "")).strip() != expected_source:
            reasons.append(f"source_csv_contract_mismatch:expected={expected_source}:actual={row.get('SourceCSV','')}")
        expected_hash = expected_source_hash_text(root, contract.sources)
        if expected_hash is None:
            reasons.append("source_csv_missing_for_hash")
        elif str(row.get("SourceCSV_SHA256", "")).strip() != expected_hash:
            reasons.append("source_csv_hash_mismatch")
        if meta is not None:
            if str(row.get("PNG_SHA256", "")).strip() != str(meta["SHA256"]):
                reasons.append("png_hash_mismatch")
            if integer(row.get("Width", "")) != int(meta["Width"]) or integer(row.get("Height", "")) != int(meta["Height"]):
                reasons.append("recorded_dimensions_mismatch")
        axes = integer(row.get("AxesCount", ""))
        series = integer(row.get("SeriesCount", ""))
        points = integer(row.get("FinitePointCount", ""))
        if axes is None or axes < contract.min_axes:
            reasons.append(f"axes_below_contract:{axes}")
        if series is None or series < contract.min_series:
            reasons.append(f"series_below_contract:{series}")
        if points is None or points < contract.min_points:
            reasons.append(f"finite_points_below_contract:{points}")
        if norm_text(row.get("ExpectedXLabel", "")) != norm_text(contract.xlabel):
            reasons.append("recorded_expected_xlabel_mismatch")
        if norm_text(row.get("ExpectedYLabel", "")) != norm_text(contract.ylabel):
            reasons.append("recorded_expected_ylabel_mismatch")
        if norm_text(row.get("ActualXLabel", "")) != norm_text(contract.xlabel):
            reasons.append(f"actual_xlabel_mismatch:{row.get('ActualXLabel','')}")
        if norm_text(row.get("ActualYLabel", "")) != norm_text(contract.ylabel):
            reasons.append(f"actual_ylabel_mismatch:{row.get('ActualYLabel','')}")
        if norm_text(contract.title_token).lower() not in norm_text(row.get("ActualTitle", "")).lower():
            reasons.append(f"title_token_missing:{contract.title_token}")
        if norm_text(row.get("ExpectedTitleToken", "")) != norm_text(contract.title_token):
            reasons.append("recorded_expected_title_token_mismatch")
        if str(row.get("Status", "")).strip().upper() != "PASS":
            reasons.append("semantic_row_status_not_pass")
        results.append(result(image_name, "SEMANTIC", reasons))
    unknown = sorted(set(by_name) - set(image_contracts))
    if unknown:
        results.append(result(name, "SEMANTIC", ["unknown_image_rows:" + ",".join(unknown)]))
    return results


def write_results(path: Path, rows: list[dict[str, object]]) -> None:
    fields = ["Artifact", "Type", "Status", "Reason", "Rows", "Columns", "Width", "Height",
              "Mode", "Bytes", "PixelStdDev", "NonBlankFraction", "SHA256"]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def verify(root: Path, write_output: bool = True) -> tuple[int, list[dict[str, object]]]:
    csv_contracts, image_contracts = read_contracts()
    csv_results, parsed = verify_csvs(root, csv_contracts)
    png_results, png_meta = verify_pngs(root, image_contracts)
    semantic_results = verify_semantic_audit(root, image_contracts, parsed, png_meta)
    all_results = csv_results + png_results + semantic_results
    if write_output:
        write_results(root / "pdsch_artifact_verification.csv", all_results)
    failures = sum(1 for row in all_results if row["Status"] != "PASS")
    print(f"PDSCH artifact verification: {len(all_results) - failures} passed, {failures} failed")
    for row in all_results:
        if row["Status"] != "PASS":
            print(f"FAIL {row['Type']} {row['Artifact']}: {row['Reason']}")
    return (0 if failures == 0 else 2), all_results


# ---------------------------------------------------------------------------
# Verifier self-test.  This validates the verifier, not the simulator.
# ---------------------------------------------------------------------------
def write_csv(path: Path, columns: Sequence[str], rows: Sequence[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(columns), extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def base_row(columns: Sequence[str]) -> dict[str, object]:
    row: dict[str, object] = {column: "1" for column in columns}
    row["Status"] = "PASS"
    return row


def create_synthetic_csvs(root: Path, contracts: dict[str, CsvContract]) -> None:
    for name, contract in contracts.items():
        if name == "pdsch_image_semantic_audit.csv":
            continue
        rows: list[dict[str, object]] = []
        r = base_row(contract.columns)
        r[contract.key[0]] = "SYN-001"
        if name == "pdsch_assignment_resolution.csv":
            r.update(Profile="connected_strict", DecodedDCIId="DCI-SYN-001", DCIFormat="1_1", DCICRCPass=1,
                     DCIRNTIMatch=1, RNTIType="C-RNTI", Source="decoded_dci+ue_context", MCSIndex=10,
                     NDI=1, RV=0, HARQProcessID=3, AssignmentCreated=1, WaveformAllowed=1,
                     ErrorIdentifier="", SPSConfigID="", SPSActivationDCIId="", SPSConfigurationEpoch="",
                     SPSActivationDCICRCPass="", SPSActivationDCIRNTIMatch="", SPSActivated="",
                     SPSReleased="", SPSOccasionIndex="")
        elif name == "pdsch_resource_ownership.csv":
            r.update(CaseID="SYN-001", Slot=0, PRB=0, Symbol=2, Subcarrier=0, Owner="PDSCH_DATA", CollisionCount=0)
        elif name == "pdsch_re_mapping.csv":
            r.update(CaseID="SYN-001", Domain="DATA", Codeword=0, Layer=0, Port=0, PRB=0, Symbol=2, Subcarrier=0, LinearIndex0Based=0)
        elif name == "pdsch_dmrs_matrix.csv":
            r.update(MappingType="A", DMRSRECount=12, IndexMismatchCount=0, SequenceNMSE=0)
        elif name == "pdsch_ptrs_matrix.csv":
            r.update(ExpectedPresent=1, PTRSRECount=12, CPEBeforeDeg=8, CPEAfterDeg=1, EVMBeforePercent=10, EVMAfterPercent=2)
        elif name == "pdsch_coding_chain.csv":
            r.update(CaseID="SYN-001", Codeword=0, TBS=1024, BaseGraph=1, G=2048, RateMatchedBits=2048, CRCOK=1)
        elif name == "pdsch_independent_vector_results.csv":
            rows = []
            for idx, family in enumerate((
                "scrambling", "modulation", "layer_mapping", "tbs", "tb_crc",
                "ldpc_segmentation", "ldpc_encoding", "rate_matching",
                "dmrs_positions", "dmrs_ports", "dmrs_sequence", "ptrs_indices",
                "reserved_re", "precoding_application", "harq_combining",
                "receiver_chain",
            ), 1):
                q = base_row(contract.columns)
                q.update(VectorFamily=family, CaseID=f"SYN-{idx:03d}", ComparedField="all", ExpectedDigest="abc", ActualDigest="abc", MismatchCount=0, MaxAbsError=0, Tolerance=0)
                rows.append(q)
        elif name == "pdsch_layer_codeword_map.csv":
            rows = []
            for rank in range(1, 9):
                q = base_row(contract.columns)
                q.update(CaseID=f"SYN-R{rank}", Rank=rank, Codeword=0 if rank <= 4 else (rank % 2), Layer=rank-1, SourceSymbolCount=6, MappedSymbolCount=6, MismatchCount=0)
                rows.append(q)
        elif name == "pdsch_precoding_application.csv":
            rows = []
            for idx, mode in enumerate(("wideband", "per_prg"), 1):
                q = base_row(contract.columns)
                q.update(CaseID=f"SYN-P{idx}", Mode=mode, PRG=idx-1, SymbolGroup=0, MatrixDigest="abc", AppliedMatrixDigest="abc", TXApplicationCount=1, RXApplicationCount=1, PowerRelativeError=0)
                rows.append(q)
        elif name == "pdsch_harq_trials.csv":
            rows = []
            for tx, (rv, combined, ok) in enumerate(((0, 0, 0), (2, 1, 1)), 1):
                q = base_row(contract.columns)
                q.update(CaseID="SYN-HARQ", HARQProcessID=2, Codeword=0, TransmissionIndex=tx, NDI=1, RV=rv, Combined=combined, TBCRCOK=ok)
                rows.append(q)
        elif name == "pdsch_receiver_metrics.csv":
            rows = []
            for rank in (1, 2, 4, 8):
                for layer in range(rank):
                    q = base_row(contract.columns)
                    q.update(CaseID=f"SYN-RX{rank}", Rank=rank, Codeword=0 if rank <= 4 else int(layer >= rank//2), Layer=layer, MeasuredSINRdB=12-layer*0.2, EVMPercent=3, BER=0, BLER=0, TBCRCOK=1, ChannelEstimateNMSEdB=-25)
                    rows.append(q)
        elif name == "pdsch_bler_curve.csv":
            rows = []
            for idx, snr in enumerate((-2, 0, 2, 4), 1):
                trials = 1000
                errors = max(0, 400 - idx * 90)
                q = base_row(contract.columns)
                q.update(CampaignID="SYN-CAMP", OperatingPointID=f"OP-{idx}", SNRdB=snr, Trials=trials, TBErrors=errors, BLER=errors/trials, CILower=max(0, errors/trials-0.03), CIUpper=min(1, errors/trials+0.03), StopReason="CI_AND_MIN_ERRORS_MET")
                rows.append(q)
        elif name == "pdsch_negative_tests.csv":
            r.update(CaseID="SYN-NEG", ExpectedErrorIdentifier="sixgr:test:Expected", ActualErrorIdentifier="sixgr:test:Expected", WaveformGenerated=0)
        elif name == "pdsch_test_summary.csv":
            r.update(TestSuite="synthetic_verifier_self_test", Total=8, Passed=8, Failed=0, Skipped=0, Blocked=0)
        if not rows:
            rows = [r]
        write_csv(root / name, contract.columns, rows)


def create_synthetic_images(root: Path, contracts: dict[str, ImageContract]) -> None:
    for idx, contract in enumerate(contracts.values(), 1):
        width = max(1000, contract.min_width)
        height = max(650, contract.min_height)
        image = Image.new("RGB", (width, height), "white")
        draw = ImageDraw.Draw(image)
        draw.rectangle((80, 40, width - 40, height - 70), outline="black", width=3)
        for k in range(1, 15):
            x = 80 + k * (width - 120) // 16
            y = 70 + ((k * 47 + idx * 31) % (height - 180))
            draw.ellipse((x - 6, y - 6, x + 6, y + 6), fill="black")
            if k > 1:
                px = 80 + (k - 1) * (width - 120) // 16
                py = 70 + (((k - 1) * 47 + idx * 31) % (height - 180))
                draw.line((px, py, x, y), fill="black", width=3)
        image.save(root / contract.name)


def create_semantic_audit(root: Path, contracts: dict[str, ImageContract], csv_contract: CsvContract) -> None:
    rows: list[dict[str, object]] = []
    for contract in contracts.values():
        path = root / contract.name
        with Image.open(path) as image:
            width, height = image.size
        rows.append({
            "ImageFile": contract.name,
            "SourceCSV": "|".join(contract.sources),
            "Width": width,
            "Height": height,
            "AxesCount": contract.min_axes,
            "SeriesCount": contract.min_series,
            "FinitePointCount": contract.min_points,
            "ExpectedXLabel": contract.xlabel,
            "ActualXLabel": contract.xlabel,
            "ExpectedYLabel": contract.ylabel,
            "ActualYLabel": contract.ylabel,
            "ExpectedTitleToken": contract.title_token,
            "ActualTitle": f"Synthetic {contract.title_token} verification",
            "SourceCSV_SHA256": expected_source_hash_text(root, contract.sources),
            "PNG_SHA256": digest(path),
            "Status": "PASS",
        })
    write_csv(root / csv_contract.name, csv_contract.columns, rows)


def self_test() -> int:
    csv_contracts, image_contracts = read_contracts()
    with tempfile.TemporaryDirectory(prefix="pdsch-verifier-self-test-") as tmp:
        root = Path(tmp)
        create_synthetic_csvs(root, csv_contracts)
        create_synthetic_images(root, image_contracts)
        create_semantic_audit(root, image_contracts, csv_contracts["pdsch_image_semantic_audit.csv"])
        good_code, good_rows = verify(root, write_output=False)
        # Corrupt a recorded PNG digest without changing the image. The verifier
        # must reject this integrity failure.
        audit_path = root / "pdsch_image_semantic_audit.csv"
        header, rows, errors = read_rectangular_csv(audit_path)
        if errors or not rows:
            print("SELF-TEST setup failed")
            return 3
        rows[0]["PNG_SHA256"] = "0" * 64
        write_csv(audit_path, header, rows)
        bad_code, bad_rows = verify(root, write_output=False)
        bad_failures = [r for r in bad_rows if r["Status"] == "FAIL"]
        expected_detected = any("png_hash_mismatch" in str(r["Reason"]) for r in bad_failures)
        print(f"Verifier self-test valid set: exit={good_code}, checks={len(good_rows)}, failures={sum(r['Status']!='PASS' for r in good_rows)}")
        print(f"Verifier self-test corrupted hash: exit={bad_code}, checks={len(bad_rows)}, failures={len(bad_failures)}, detected={expected_detected}")
        return 0 if good_code == 0 and bad_code == 2 and expected_detected else 3


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", nargs="?", type=Path, help="Directory containing PDSCH phase artifacts")
    parser.add_argument("--self-test", action="store_true", help="Run the verifier's synthetic positive/negative self-test")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        return self_test()
    if args.output_dir is None:
        raise SystemExit("output_dir is required unless --self-test is used")
    root = args.output_dir.resolve()
    if not root.is_dir():
        print(f"Artifact directory not found: {root}", file=sys.stderr)
        return 2
    code, _ = verify(root)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
