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
import json
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

HEX64 = "0123456789abcdef"

NEGATIVE_FAMILY_COUNTS = {
    "assignment_resolution": 16,
    "dmrs_symbol_configuration": 42,
    "dmrs_port_table": 18,
    "ptrs_presence": 3,
    "reserved_re_union": 3,
    "tbs_independent_scalar_input_contract": 5,
    "qam_modulation": 4,
    "codeword_layer_mapping": 4,
    "precoder_bundle": 6,
    "harq_transition": 5,
}

DECLARED_NEGATIVE_MINIMUM_COUNTS = {
    "no_signal": 16,
    "wrong_rnti": 16,
    "wrong_dmrs": 16,
    "wrong_rv": 16,
}

MANDATORY_INTEGRATION_NEGATIVES = {
    "integration_invalid_riv": "sixgr:pdsch:InvalidRIV",
    "integration_invalid_rbg_field": "sixgr:pdsch:InvalidRBGField",
    "integration_invalid_slot_direction": "sixgr:pdsch:InvalidSlotDirection",
    "integration_invalid_tdra": "sixgr:pdsch:InvalidTDRA",
    "integration_invalid_dmrs_type_a_position": "sixgr:pdsch:InvalidDMRSTypeAPosition",
    "integration_invalid_dmrs_configuration_type": "sixgr:pdsch:InvalidDMRSConfigurationType",
    "integration_invalid_dmrs_length": "sixgr:pdsch:InvalidDMRSLength",
    "integration_invalid_num_cdm_groups_without_data": "sixgr:pdsch:InvalidNumCDMGroupsWithoutData",
    "integration_missing_codeword_modulation": "sixgr:pdsch:MissingCodewordSpecificModulation",
    "integration_missing_codeword_mcs": "sixgr:pdsch:MissingCodewordSpecificMCS",
    "integration_reserved_mcs_entry": "sixgr:pdsch:ReservedMCSEntry",
    "integration_1024qam_capability_context": "sixgr:pdsch:UnsupportedMCSContext",
    "integration_1024qam_dci_context": "sixgr:pdsch:QAM1024DCIFormatNotAllowed",
    "integration_1024qam_frequency_context": "sixgr:pdsch:QAM1024FrequencyRangeNotAllowed",
    "integration_invalid_ptrs_port_association": "sixgr:pdsch:InvalidPTRSPortAssociation",
    "integration_resource_collision": "sixgr:pdsch:DataDMRSPTRSReservedCollision",
    "integration_stale_precoder_pmi": "sixgr:pdsch:PDSCHPrecoderBundle:StalePrecoderPMIContext",
    "integration_resource_outside_bwp": "sixgr:pdsch:ResourceOutsideBWP",
    "integration_inactive_tci_state": "sixgr:pdsch:TCIStateNotActivated",
    "integration_stale_precoder_tci": "sixgr:pdsch:StalePrecoderTCIContext",
    "integration_unsupported_multitrp_scheme": "sixgr:pdsch:UnsupportedMultiTRPScheme",
}

MANDATORY_NEGATIVE_IDENTIFIERS = {
    "sixgr:pdsch:MissingDecodedDCI",
    "sixgr:pdsch:DCICRCFailed",
    "sixgr:pdsch:DCIRNTIMismatch",
    "sixgr:pdsch:MissingActiveBWPContext",
    "sixgr:pdsch:InactiveServingCell",
    "sixgr:pdsch:StaleUEConfigurationEpoch",
    "sixgr:pdsch:ScheduledResourceUnavailable",
    "sixgr:pdsch:PDSCHModulator:UnsupportedNRModulation",
    "sixgr:pdsch:PDSCHModulator:MissingModulation",
    "sixgr:pdsch:PDSCHTBSScalarInputValidator:TargetCodeRateOutOfRange",
    "sixgr:pdsch:CodewordLayerMapper:RankOutOfRange",
    "sixgr:pdsch:CodewordLayerMapper:CodewordCountMismatch",
    "sixgr:pdsch:UnsupportedDMRSPositionCombination",
    "sixgr:pdsch:DMRSPortUnsupportedForConfiguration",
    "sixgr:pdsch:InvalidPTRSTimeDensity",
    "sixgr:pdsch:InvalidPTRSFrequencyDensity",
    "sixgr:pdsch:InvalidPTRSREOffset",
    "sixgr:pdsch:ReservedREOutsideAllocation",
    "sixgr:pdsch:NoPDSCHDataREAfterReservation",
    "sixgr:pdsch:PDSCHPrecoderBundle:PrecoderLayerDimensionMismatch",
    "sixgr:pdsch:PDSCHPrecoderBundle:IncompletePRGCoverage",
    "sixgr:pdsch:PDSCHPrecoderBundle:IncompleteSymbolGroupCoverage",
    "sixgr:pdsch:HARQTBIdentityMismatch",
    "sixgr:pdsch:HARQTBSMismatch",
    "sixgr:pdsch:HARQCodingLayoutMismatch",
    "sixgr:pdsch:RVOutOfRange",
    "sixgr:pdsch:PDSCHReceiver:NoReceivedSignal",
    *MANDATORY_INTEGRATION_NEGATIVES.values(),
}

BLER_CAMPAIGNS = {
    "BLER-AWGN-QPSK": ("AWGN", 1, "QPSK", 4),
    "BLER-AWGN-64QAM": ("AWGN", 1, "64QAM", 18),
    "BLER-TDL-R2-16QAM": ("TDL-A", 2, "16QAM", 10),
    "BLER-CDL-R4-64QAM": ("CDL-C", 4, "64QAM", 18),
    # R2026a/Release-18 QAM1024 table: 23 is the executed valid 1024QAM
    # entry; 27 is reserved and must never be reported as executed.
    "BLER-AWGN-1024QAM": ("AWGN", 1, "1024QAM", 23),
    "BLER-AWGN-HARQ-0231": ("AWGN", 1, "QPSK", 4),
    "BLER-AWGN-PTRS-PN": ("AWGN", 1, "256QAM", 25),
}

MANDATORY_MATLAB_SUITES = (
    "testPDSCHSchedulingAssignment",
    "testPDSCHSPSAssignment",
    "testPDSCHFDRAFromDecodedDCI",
    "testPDSCHTDRAFromDecodedDCI",
    "testPDSCHMCSResolver",
    "testPDSCHConfigMaterializerNoMutation",
    "testPDSCHDMRSSymbolPositionVectors",
    "testPDSCHDMRSPortTableVectors",
    "testPDSCHDMRSSequenceIndependent",
    "testPDSCHPTRSPresenceVectors",
    "testPDSCHPTRSIndicesIndependent",
    "testPDSCHPTRSPhaseNoiseBenefit",
    "testPDSCHReservedREUnionVectors",
    "testPDSCHResourceOwnershipMap",
    "testPDSCHTBSAndBaseGraphVectors",
    "testPDSCHTBCRCVectors",
    "testPDSCHCodeBlockSegmentationIndependent",
    "testPDSCHLDPCEncodingIndependent",
    "testPDSCHRateMatchingIndependent",
    "testPDSCHScramblingIndependentVectors",
    "testPDSCHModulationIndependentVectors",
    "testPDSCHLayerMappingIndependentVectors",
    "testPDSCHPrecoderBundleVectors",
    "testPDSCHPRGMatrixMultiplicationIndependent",
    "testPDSCHReceiverNoNoiseExact",
    "testPDSCHReceiverAWGN",
    "testPDSCHReceiverTDL",
    "testPDSCHReceiverCDL",
    "testPDSCHHARQTransitionVectors",
    "testPDSCHHARQPositionAwareCombining",
    "testPDSCHActiveBWPBinding",
    "testPDSCHCrossCarrierBinding",
    "testPDSCHTCIStateBinding",
    "testPDSCHTwoTRPTransmissionOccasions",
    "testPDSCHDeclaredCoverageMatrix",
    "testPDSCHArtifactGeneration",
    "testPDSCH6GR",
    "testPDSCH6GRMultiCodewordStudy",
    "testPDSCHCodewordLayerHighRank",
    "testPDSCHGrantDrivenTxExact",
    "testPDSCHLLRScalingConvention",
    "testPDSCHMultiPortPrecoding",
    "testPDSCHSISORegression",
    "testResourceAccountingExact",
    "testHARQTBContextInvariants",
    "testHARQSoftBufferPositionAware",
    "testCodingLayoutContracts",
    "testTransportBlockSizeExactness",
)

PROMPT_WORK_ITEM_SUITES = (
    "testPDSCH1024QAMRoundTrip",
    "testPDSCHDLSCHNoNoiseRoundTrip",
    "testPDSCHDMRSInvalidCombinations",
    "testPDSCHDMRSNoMutation",
    "testPDSCHExactGFromResourcePlan",
    "testPDSCHFrequencySelectivePrecoderEndToEnd",
    "testPDSCHHARQCombiningGain",
    "testPDSCHHARQNDIReset",
    "testPDSCHHARQRejectsWrongTB",
    "testPDSCHHARQRVSequence0231",
    "testPDSCHHARQTwoCodewords",
    "testPDSCHNoDataDMRSPTRSReservedOverlap",
    "testPDSCHPrecoderPowerConservation",
    "testPDSCHPRGDataDMRSPTRSConsistency",
    "testPDSCHPTRSPortAssociation",
    "testPDSCHQCLStatePropagation",
    "testPDSCHRank1To8NoNoiseRoundTrip",
    "testPDSCHRateMatchPatternIntegration",
    "testPDSCHReceiverLLRScalingConvention",
    "testPDSCHReceiverNoSignal",
    "testPDSCHReceiverWrongDMRSPort",
    "testPDSCHReceiverWrongPRGMap",
    "testPDSCHReceiverWrongRNTI",
    "testPDSCHReceiverWrongScramblingIdentity",
    "testPDSCHSoftDemodulationLLRSign",
    "testPDSCHTwoCodewordCoding",
)

REPOSITORY_EXTRA_SUITES = (
    "testCampaignPDSCHCalibrationBinding",
    "testPDSCHFadingHighRank",
    "testPDSCHBLERStopPolicy",
    "testPDSCHPhaseRunnerHonesty",
    "testPDSCHPhaseEvidenceMCSFailClosed",
    "testPDSCHStudyImmutableCodingPlans",
    "testPDSCHTwoCodewordHARQContext",
    "testMultiPortDMRSReceiverMetrics",
)

FINAL_TEST_SUITES = frozenset(
    MANDATORY_MATLAB_SUITES
    + PROMPT_WORK_ITEM_SUITES
    + REPOSITORY_EXTRA_SUITES)
PRE_ARTIFACT_TEST_SUITES = FINAL_TEST_SUITES - {
    "testPDSCHArtifactGeneration"}


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
    csv_contracts.update({
        "pdsch_declared_coverage_results.csv": CsvContract(
            "pdsch_declared_coverage_results.csv",
            (
                "CaseID", "TestKind", "Rank", "Modulation", "ChannelModel",
                "ProductionTXExecuted", "ProductionRXExecuted",
                "ExpectedStatus", "ActualStatus", "ErrorIdentifier", "Status",
                "ExecutionBackend", "ChannelEstimateScope", "ReceiverCRCPass",
                "EvidenceDetail",
            ),
            ("CaseID", "TestKind"),
        ),
        "pdsch_pairwise_cases.csv": CsvContract(
            "pdsch_pairwise_cases.csv",
            (
                "CaseID", "Rank", "NumCodewords", "MappingType",
                "DMRSConfigurationType", "DMRSLength",
                "DMRSAdditionalPosition", "DMRSMultiplexing", "PTRSEnabled",
                "Modulation", "RV", "RVSequence", "PrecodingMode",
                "NumerologyKHz", "PRBSet", "AllocationShape",
                "ReservationMode", "ReservationSourceCount",
                "ReservationOverlapMultiplicity", "ReservedRECount",
                "DeclaredChannelModel", "ExecutionChannelModel",
                "FadingTruthAnchorCaseID", "ProductionTXExecuted",
                "ProductionRXExecuted", "CRCPass", "GenerationPolicy",
                "PairUniverseDefinition", "RequiredPairCount",
                "CoveredPairCount", "MissingPairCount",
                "PairCoverageSHA256",
                "Status",
            ),
            ("CaseID",),
        ),
        "pdsch_no_noise_roundtrip.csv": CsvContract(
            "pdsch_no_noise_roundtrip.csv",
            (
                "CaseID", "Rank", "Modulation", "NumCodewords",
                "TransportBlockSize", "BitErrors", "CRCPass",
                "ExactStageLengths", "CollisionCount", "FiniteMetrics",
                "ProductionTXExecuted", "ProductionRXExecuted", "Status",
            ),
            ("CaseID",),
        ),
        "pdsch_phase_execution_summary.csv": CsvContract(
            "pdsch_phase_execution_summary.csv",
            (
                "Stage", "Source", "ExecutionMode", "RecordCount",
                "PassedCount", "FailedCount", "DurationSeconds",
                "ErrorIdentifier", "ErrorMessage", "Detail", "Status",
            ),
            ("Stage", "Source"),
        ),
    })
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
    image_contracts.update({
        "pdsch_pipeline_stage_dimensions.png": ImageContract(
            "pdsch_pipeline_stage_dimensions.png",
            ("pdsch_coding_chain.csv",),
            "Pipeline stage", "Bits",
            "PDSCH pipeline stage dimensions",
            1, 1, 5, 900, 600,
        ),
        "pdsch_independent_mismatch_overview.png": ImageContract(
            "pdsch_independent_mismatch_overview.png",
            ("pdsch_independent_vector_results.csv",),
            "Independent comparison", "Mismatch / error",
            "Independent-vector mismatch overview",
            1, 2, 8, 900, 600,
        ),
    })
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


def is_hex64(value: object) -> bool:
    token = str(value).strip().lower()
    return len(token) == 64 and all(char in HEX64 for char in token)


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
            if not is_hex64(row.get("SequenceDigest", "")):
                reasons.append(f"invalid_dmrs_sequence_digest:line={line}")

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
            if not str(row.get("OracleImplementation", "")).strip():
                reasons.append(
                    f"independent_oracle_implementation_blank:line={line}")
            if not str(row.get("OracleVersion", "")).strip():
                reasons.append(
                    f"independent_oracle_version_blank:line={line}")
            if not is_hex64(row.get("OracleArtifactSHA256", "")):
                reasons.append(
                    f"independent_oracle_hash_invalid:line={line}")
            if not is_hex64(expected) or not is_hex64(actual):
                reasons.append(
                    f"independent_result_digest_invalid:line={line}")
            elif expected != actual:
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
            matrix_digest = str(row.get("MatrixDigest", "")).strip()
            applied_digest = str(
                row.get("AppliedMatrixDigest", "")).strip()
            if not is_hex64(matrix_digest) or not is_hex64(applied_digest):
                reasons.append(f"precoder_digest_invalid:line={line}")
            elif matrix_digest != applied_digest:
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
            for field in (
                    "CodeBlockLayoutDigest", "SoftBufferInputDigest",
                    "SoftBufferOutputDigest"):
                if not is_hex64(row.get(field, "")):
                    reasons.append(
                        f"invalid_harq_digest:{field}:line={line}")
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
            confidence = require_probability(
                row, "ConfidenceLevel", line, reasons)
            half_width = require_nonnegative(
                row, "CIHalfWidth", line, reasons)
            min_errors = integer(row.get("MinErrorsRequired", ""))
            if trials is None or errors is None or trials < 4 or errors < 0 or errors > trials:
                reasons.append(f"invalid_trial_counts:line={line}")
            elif bler is not None and abs(bler - errors / trials) > max(1e-12, 0.5 / trials):
                reasons.append(f"bler_count_mismatch:line={line}")
            if None not in {low, bler, high} and not (low <= bler <= high):
                reasons.append(f"ci_does_not_enclose_bler:line={line}")
            if confidence is None or not 0 < confidence < 1:
                reasons.append(f"invalid_confidence_level:line={line}")
            if low is not None and high is not None \
                    and half_width is not None \
                    and abs(half_width - (high - low) / 2) > 1e-9:
                reasons.append(f"ci_half_width_mismatch:line={line}")
            if min_errors is None or min_errors < 1:
                reasons.append(f"invalid_min_errors_required:line={line}")
            stop = str(row.get("StopReason", "")).strip().upper()
            if stop not in canonical_stop:
                reasons.append(f"noncanonical_or_incomplete_stop_reason:line={line}:value={stop}")
            elif stop == "CI_AND_MIN_ERRORS_MET" \
                    and min_errors is not None \
                    and errors is not None and errors < min_errors:
                reasons.append(
                    f"stop_reason_min_errors_not_met:line={line}")
            expected = BLER_CAMPAIGNS.get(campaign)
            if expected is None:
                reasons.append(
                    f"unexpected_bler_campaign:line={line}:campaign={campaign}")
            else:
                channel, rank, modulation, mcs = expected
                if str(row.get("ChannelModel", "")).strip().upper() \
                        != channel:
                    reasons.append(
                        f"bler_channel_contract_mismatch:line={line}")
                if integer(row.get("Rank", "")) != rank:
                    reasons.append(
                        f"bler_rank_contract_mismatch:line={line}")
                if str(row.get("Modulation", "")).strip().upper() \
                        != modulation:
                    reasons.append(
                        f"bler_modulation_contract_mismatch:line={line}")
                if integer(row.get("MCSIndex", "")) != mcs:
                    reasons.append(
                        f"bler_mcs_contract_mismatch:line={line}")
        if set(campaign_points) != set(BLER_CAMPAIGNS):
            reasons.append(
                "bler_campaign_set_mismatch:missing="
                + ",".join(sorted(set(BLER_CAMPAIGNS) - set(campaign_points)))
                + ":unexpected="
                + ",".join(sorted(set(campaign_points) - set(BLER_CAMPAIGNS))))
        for campaign, count in campaign_points.items():
            if count != 4:
                reasons.append(
                    f"bler_operating_point_count:campaign={campaign}:"
                    f"expected=4:actual={count}")

    elif name == "pdsch_negative_tests.csv":
        family_counts: dict[str, int] = {}
        identifiers: set[str] = set()
        for line, row in enumerate(rows, 2):
            family = str(row.get("TestKind", "")).strip().lower()
            family_counts[family] = family_counts.get(family, 0) + 1
            expected = str(row.get("ExpectedErrorIdentifier", "")).strip()
            actual = str(row.get("ActualErrorIdentifier", "")).strip()
            identifiers.add(expected)
            if not expected or expected != actual:
                reasons.append(f"negative_error_mismatch:line={line}:expected={expected}:actual={actual}")
            if truth(row.get("WaveformGenerated", "")) is not False:
                reasons.append(f"negative_case_generated_waveform:line={line}")
        for family, floor in NEGATIVE_FAMILY_COUNTS.items():
            if family_counts.get(family, 0) < floor:
                reasons.append(
                    f"negative_family_below_floor:family={family}:"
                    f"required={floor}:actual={family_counts.get(family, 0)}")
        for family, floor in DECLARED_NEGATIVE_MINIMUM_COUNTS.items():
            if family_counts.get(family, 0) < floor:
                reasons.append(
                    f"declared_negative_below_floor:family={family}:"
                    f"required={floor}:actual={family_counts.get(family, 0)}")
        for family, identifier in MANDATORY_INTEGRATION_NEGATIVES.items():
            selected = [
                row for row in rows
                if str(row.get("TestKind", "")).strip().lower() == family
            ]
            if len(selected) != 1:
                reasons.append(
                    f"missing_mandatory_integration_negative:family={family}:"
                    f"actual={len(selected)}")
            elif (
                    str(selected[0].get(
                        "ExpectedErrorIdentifier", "")).strip() != identifier
                    or str(selected[0].get(
                        "ActualErrorIdentifier", "")).strip() != identifier):
                reasons.append(
                    f"integration_negative_identifier_mismatch:family={family}:"
                    f"required={identifier}")
        missing_identifiers = sorted(
            MANDATORY_NEGATIVE_IDENTIFIERS - identifiers)
        if missing_identifiers:
            reasons.append(
                "mandatory_negative_identifiers_missing:"
                + "|".join(missing_identifiers))

    elif name == "pdsch_test_summary.csv":
        suites: set[str] = set()
        for line, row in enumerate(rows, 2):
            suites.add(str(row.get("TestSuite", "")).strip())
            total = integer(row.get("Total", ""))
            passed = integer(row.get("Passed", ""))
            failed = integer(row.get("Failed", ""))
            skipped = integer(row.get("Skipped", ""))
            blocked = integer(row.get("Blocked", ""))
            if None in {total, passed, failed, skipped, blocked} or total is None or total <= 0:
                reasons.append(f"invalid_test_summary_counts:line={line}")
            elif failed != 0 or skipped != 0 or blocked != 0 or passed != total:
                reasons.append(f"incomplete_or_failed_test_suite:line={line}:total={total}:passed={passed}:failed={failed}:skipped={skipped}:blocked={blocked}")
        expected_suite_sets = (
            PRE_ARTIFACT_TEST_SUITES, FINAL_TEST_SUITES)
        if not any(suites == expected for expected in expected_suite_sets):
            nearest = min(
                expected_suite_sets,
                key=lambda expected: len(suites ^ expected))
            reasons.append(
                "test_suite_set_mismatch:missing="
                + ",".join(sorted(nearest - suites))
                + ":unexpected=" + ",".join(sorted(suites - nearest)))


    elif name == "pdsch_declared_coverage_results.csv":
        mandatory_kinds = {
            "positive", "no_signal", "wrong_rnti", "wrong_dmrs",
            "wrong_rv", "reserved_re", "impairment",
        }
        production_backend_by_kind = {
            "positive": "canonical_pdsch_tx_channel_rx",
            "no_signal": "canonical_receiver_input_validation",
            "wrong_rnti": "canonical_assignment_validation",
            "wrong_dmrs": "canonical_dmrs_configuration_validation",
            "wrong_rv": "canonical_dlsch_coding_plan_validation",
            "reserved_re": "canonical_pdsch_tx_channel_rx",
            "impairment": "canonical_pdsch_tx_channel_rx",
        }
        by_case: dict[str, set[str]] = {}
        if len(rows) != 16 * len(mandatory_kinds):
            reasons.append(f"declared_coverage_row_count:{len(rows)}")
        for line, row in enumerate(rows, 2):
            case_id = str(row.get("CaseID", "")).strip()
            kind = str(row.get("TestKind", "")).strip().lower()
            by_case.setdefault(case_id, set()).add(kind)
            if kind not in mandatory_kinds:
                reasons.append(
                    f"unknown_declared_test_kind:line={line}:kind={kind}")
            if str(row.get("ExpectedStatus", "")).strip().upper() != "PASS" \
                    or str(row.get("ActualStatus", "")).strip().upper() != "PASS":
                reasons.append(
                    f"declared_expected_actual_status_mismatch:line={line}")
            backend = str(row.get("ExecutionBackend", "")).strip().lower()
            if backend != production_backend_by_kind.get(kind) \
                    or any(token in backend for token in (
                        "proxy", "fallback", "synthetic")):
                reasons.append(
                    f"declared_nonproduction_backend:line={line}:"
                    f"backend={backend}")
            tx = truth(row.get("ProductionTXExecuted", ""))
            rx = truth(row.get("ProductionRXExecuted", ""))
            if kind in {"positive", "reserved_re", "impairment"}:
                if tx is not True or rx is not True:
                    reasons.append(
                        f"declared_missing_tx_rx_execution:line={line}:"
                        f"kind={kind}")
            elif kind == "no_signal":
                if tx is not False or rx is not True:
                    reasons.append(
                        f"declared_no_signal_execution_mismatch:line={line}")
            elif kind.startswith("wrong_"):
                if tx is not False or rx is not False:
                    reasons.append(
                        f"declared_pre_tx_negative_generated_chain:"
                        f"line={line}:kind={kind}")
            channel = str(row.get("ChannelModel", "")).strip().upper()
            scope = str(row.get("ChannelEstimateScope", "")).strip().lower()
            if channel.startswith(("TDL", "CDL")) and kind in {
                    "positive", "reserved_re", "impairment"}:
                if scope != (
                        "dmrs_backed_resource_selective_"
                        "effective_layer_channel"):
                    reasons.append(
                        f"declared_fading_scope_not_resource_selective:"
                        f"line={line}:scope={scope}")
            rank = integer(row.get("Rank", ""))
            if rank is None or not 1 <= rank <= 8:
                reasons.append(f"declared_invalid_rank:line={line}")
        if len(by_case) != 16:
            reasons.append(f"declared_case_count:{len(by_case)}")
        for case_id, kinds in by_case.items():
            if kinds != mandatory_kinds:
                reasons.append(
                    f"declared_case_test_kinds:{case_id}:"
                    f"{','.join(sorted(kinds))}")


    elif name == "pdsch_pairwise_cases.csv":
        if len(rows) < 40:
            reasons.append(
                f"pairwise_row_count_below_floor:"
                f"minimum=40:actual={len(rows)}")
        ranks: set[int] = set()
        codewords: set[int] = set()
        mappings: set[str] = set()
        dmrs_types: set[int] = set()
        dmrs_lengths: set[int] = set()
        additional_positions: set[int] = set()
        multiplexing: set[str] = set()
        ptrs_values: set[bool] = set()
        modulations: set[str] = set()
        rvs: set[int] = set()
        numerologies: set[int] = set()
        allocation_shapes: set[str] = set()
        reservation_modes: set[str] = set()
        declared_channels: set[str] = set()
        precoding_modes: set[str] = set()
        proof_definitions: set[str] = set()
        proof_required: set[int] = set()
        proof_covered: set[int] = set()
        proof_missing: set[int] = set()
        proof_hashes: set[str] = set()
        for line, row in enumerate(rows, 2):
            rank = integer(row.get("Rank", ""))
            codeword_count = integer(row.get("NumCodewords", ""))
            dmrs_type = integer(row.get("DMRSConfigurationType", ""))
            dmrs_length = integer(row.get("DMRSLength", ""))
            additional = integer(row.get("DMRSAdditionalPosition", ""))
            rv = integer(row.get("RV", ""))
            numerology = integer(row.get("NumerologyKHz", ""))
            ptrs_enabled = truth(row.get("PTRSEnabled", ""))
            if rank is not None:
                ranks.add(rank)
            if codeword_count is not None:
                codewords.add(codeword_count)
            if dmrs_type is not None:
                dmrs_types.add(dmrs_type)
            if dmrs_length is not None:
                dmrs_lengths.add(dmrs_length)
            if additional is not None:
                additional_positions.add(additional)
            if rv is not None:
                rvs.add(rv)
            if numerology is not None:
                numerologies.add(numerology)
            if ptrs_enabled is not None:
                ptrs_values.add(ptrs_enabled)
            mappings.add(str(row.get("MappingType", "")).strip().upper())
            multiplexing.add(
                str(row.get("DMRSMultiplexing", "")).strip().lower())
            modulations.add(
                str(row.get("Modulation", "")).strip().upper())
            allocation_shapes.add(
                str(row.get("AllocationShape", "")).strip().lower())
            reservation_mode = str(
                row.get("ReservationMode", "")).strip().lower()
            reservation_modes.add(reservation_mode)
            declared_channel = str(
                row.get("DeclaredChannelModel", "")).strip().upper()
            execution_channel = str(
                row.get("ExecutionChannelModel", "")).strip().upper()
            declared_channels.add(declared_channel)
            precoding_modes.add(
                str(row.get("PrecodingMode", "")).strip().lower())
            definition = str(
                row.get("PairUniverseDefinition", "")).strip()
            required_pairs = integer(row.get("RequiredPairCount", ""))
            covered_pairs = integer(row.get("CoveredPairCount", ""))
            missing_pairs = integer(row.get("MissingPairCount", ""))
            coverage_hash = str(
                row.get("PairCoverageSHA256", "")).strip().lower()
            proof_definitions.add(definition)
            if required_pairs is not None:
                proof_required.add(required_pairs)
            if covered_pairs is not None:
                proof_covered.add(covered_pairs)
            if missing_pairs is not None:
                proof_missing.add(missing_pairs)
            proof_hashes.add(coverage_hash)
            if not definition:
                reasons.append(
                    f"pairwise_empty_universe_definition:line={line}")
            if required_pairs is None or required_pairs <= 0 \
                    or covered_pairs is None or covered_pairs <= 0 \
                    or missing_pairs != 0 \
                    or covered_pairs != required_pairs:
                reasons.append(
                    f"pairwise_invalid_coverage_counts:line={line}:"
                    f"required={required_pairs}:covered={covered_pairs}:"
                    f"missing={missing_pairs}")
            if not is_hex64(coverage_hash):
                reasons.append(
                    f"pairwise_invalid_coverage_hash:line={line}")
            if truth(row.get("ProductionTXExecuted", "")) is not True \
                    or truth(row.get("ProductionRXExecuted", "")) is not True \
                    or truth(row.get("CRCPass", "")) is not True:
                reasons.append(f"pairwise_missing_real_tx_rx_crc:line={line}")
            generation = str(
                row.get("GenerationPolicy", "")).strip().lower()
            if generation != \
                    "deterministic_materialized_factor_covering_array_v2" \
                    or any(token in generation for token in (
                        "synthetic", "proxy", "fallback")):
                reasons.append(
                    f"pairwise_invalid_generation_policy:line={line}:"
                    f"value={generation}")
            if not str(row.get("PRBSet", "")).strip():
                reasons.append(f"pairwise_empty_prb_set:line={line}")
            source_count = integer(row.get("ReservationSourceCount", ""))
            overlap = integer(
                row.get("ReservationOverlapMultiplicity", ""))
            reserved = integer(row.get("ReservedRECount", ""))
            if None in {source_count, overlap, reserved}:
                reasons.append(
                    f"pairwise_invalid_reservation_counts:line={line}")
            elif reservation_mode == "overlapping":
                if source_count < 2 or overlap <= 0 or reserved <= 0:
                    reasons.append(
                        f"pairwise_overlap_not_materialized:line={line}")
            elif reservation_mode == "single":
                if source_count != 1 or overlap != 0 or reserved <= 0:
                    reasons.append(
                        f"pairwise_single_reservation_not_materialized:"
                        f"line={line}")
            elif reservation_mode == "none":
                if source_count != 0 or overlap != 0 or reserved != 0:
                    reasons.append(
                        f"pairwise_unexpected_reservation:line={line}")
            else:
                reasons.append(
                    f"pairwise_unknown_reservation_mode:line={line}")
            anchor = str(
                row.get("FadingTruthAnchorCaseID", "")).strip()
            if declared_channel.startswith(("TDL", "CDL")):
                if not anchor or execution_channel != declared_channel:
                    reasons.append(
                        f"pairwise_fading_truth_anchor_missing:line={line}")
            elif declared_channel == "AWGN":
                if execution_channel != "AWGN":
                    reasons.append(
                        f"pairwise_awgn_execution_mismatch:line={line}")
            else:
                reasons.append(
                    f"pairwise_unknown_declared_channel:line={line}")
        if len(proof_definitions) != 1 \
                or len(proof_required) != 1 \
                or len(proof_covered) != 1 \
                or len(proof_missing) != 1 \
                or len(proof_hashes) != 1:
            reasons.append(
                "pairwise_coverage_proof_inconsistent_across_rows")
        expected_levels: tuple[tuple[str, object, object], ...] = (
            ("rank", ranks, set(range(1, 9))),
            ("codewords", codewords, {1, 2}),
            ("mapping", mappings, {"A", "B"}),
            ("dmrs_type", dmrs_types, {1, 2}),
            ("dmrs_length", dmrs_lengths, {1, 2}),
            ("dmrs_additional_position", additional_positions, {0, 1, 2, 3}),
            ("dmrs_multiplexing", multiplexing, {"basic", "enhanced"}),
            ("ptrs", ptrs_values, {False, True}),
            ("modulation", modulations, {
                "QPSK", "16QAM", "64QAM", "256QAM", "1024QAM"}),
            ("rv", rvs, {0, 1, 2, 3}),
            ("numerology", numerologies, {15, 30, 60, 120}),
            ("allocation_shape", allocation_shapes, {
                "contiguous", "noncontiguous"}),
            ("reservation_mode", reservation_modes, {
                "none", "single", "overlapping"}),
            ("channel", declared_channels, {"AWGN", "TDL-A", "CDL-C"}),
        )
        for label, observed, required in expected_levels:
            if not required <= observed:
                reasons.append(
                    f"pairwise_factor_levels_missing:{label}:"
                    f"{sorted(required - observed)}")
        required_precoding_modes = {
            "wideband_codebook", "prg_codebook", "prg_noncodebook"}
        if not required_precoding_modes <= precoding_modes:
            reasons.append(
                "pairwise_precoding_levels_missing:"
                + ",".join(sorted(
                    required_precoding_modes - precoding_modes)))


    elif name == "pdsch_no_noise_roundtrip.csv":
        if len(rows) != 40:
            reasons.append(f"no_noise_row_count:{len(rows)}")
        combinations: set[tuple[int, str]] = set()
        required_modulations = {
            "QPSK", "16QAM", "64QAM", "256QAM", "1024QAM"}
        for line, row in enumerate(rows, 2):
            rank = integer(row.get("Rank", ""))
            modulation = str(
                row.get("Modulation", "")).strip().upper()
            if rank is None or not 1 <= rank <= 8:
                reasons.append(f"no_noise_invalid_rank:line={line}")
            else:
                combinations.add((rank, modulation))
            if integer(row.get("BitErrors", "")) != 0:
                reasons.append(f"no_noise_bit_error:line={line}")
            if integer(row.get("CollisionCount", "")) != 0:
                reasons.append(f"no_noise_collision:line={line}")
            for field in (
                    "CRCPass", "ExactStageLengths", "FiniteMetrics",
                    "ProductionTXExecuted", "ProductionRXExecuted"):
                if truth(row.get(field, "")) is not True:
                    reasons.append(
                        f"no_noise_false_guard:{field}:line={line}")
            num_codewords = integer(row.get("NumCodewords", ""))
            tbs_tokens = [
                token for token in str(
                    row.get("TransportBlockSize", "")).split("|")
                if token.strip()]
            if num_codewords not in {1, 2} \
                    or len(tbs_tokens) != num_codewords \
                    or any(integer(token) is None or integer(token) <= 0
                           for token in tbs_tokens):
                reasons.append(f"no_noise_invalid_tbs_vector:line={line}")
        required_combinations = {
            (rank, modulation)
            for rank in range(1, 9)
            for modulation in required_modulations
        }
        if combinations != required_combinations:
            reasons.append(
                "no_noise_rank_modulation_matrix_incomplete")


    elif name == "pdsch_phase_execution_summary.csv":
        required_stages = {
            "vector_pack_verification", "phase_evidence_builder",
            "coverage_executor", "focused_test_function",
            "artifact_export", "matlab_output_contract",
        }
        observed_stages: set[str] = set()
        for line, row in enumerate(rows, 2):
            stage = str(row.get("Stage", "")).strip().lower()
            observed_stages.add(stage)
            records = integer(row.get("RecordCount", ""))
            passed = integer(row.get("PassedCount", ""))
            failed = integer(row.get("FailedCount", ""))
            duration = finite(row.get("DurationSeconds", ""))
            if records is None or passed is None or failed is None \
                    or records <= 0 or passed + failed != records:
                reasons.append(
                    f"phase_execution_count_mismatch:line={line}")
            status = str(row.get("Status", "")).strip().upper()
            if status == "PASS" and (
                    failed != 0 or passed != records):
                reasons.append(
                    f"phase_execution_pass_count_mismatch:line={line}")
            if duration is None or duration <= 0:
                reasons.append(
                    f"phase_execution_duration_not_measured:line={line}")
            for field in ("Source", "ExecutionMode", "Detail"):
                text = str(row.get(field, "")).strip()
                if not text:
                    reasons.append(
                        f"phase_execution_empty_{field.lower()}:line={line}")
                if any(token in text.lower() for token in (
                        "invented", "synthetic", "placeholder", "nominal")):
                    reasons.append(
                        f"phase_execution_unmeasured_detail:line={line}:"
                        f"field={field}")
            if status == "PASS" and (
                    str(row.get("ErrorIdentifier", "")).strip()
                    or str(row.get("ErrorMessage", "")).strip()):
                reasons.append(
                    f"phase_execution_pass_has_error:line={line}")
        missing_stages = required_stages - observed_stages
        if missing_stages:
            reasons.append(
                "phase_execution_required_stages_missing:"
                + ",".join(sorted(missing_stages)))


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


def verify_artifact_inventory(
        root: Path, csv_contracts: dict[str, CsvContract],
        image_contracts: dict[str, ImageContract]) -> list[dict[str, object]]:
    required_csv = set(csv_contracts)
    audit_name = "pdsch_artifact_verification.csv"
    observed_csv = {path.name for path in root.glob("*.csv")}
    observed_png = {path.name for path in root.glob("*.png")}
    required_png = set(image_contracts)
    reasons: list[str] = []
    permitted_csv_sets = (required_csv, required_csv | {audit_name})
    if not any(observed_csv == expected for expected in permitted_csv_sets):
        nearest = min(
            permitted_csv_sets,
            key=lambda expected: len(observed_csv ^ expected))
        reasons.append(
            "csv_inventory_mismatch:missing="
            + ",".join(sorted(nearest - observed_csv))
            + ":unexpected=" + ",".join(sorted(observed_csv - nearest)))
    if observed_png != required_png:
        reasons.append(
            "png_inventory_mismatch:missing="
            + ",".join(sorted(required_png - observed_png))
            + ":unexpected=" + ",".join(sorted(observed_png - required_png)))
    return [result(
        "pdsch_phase_artifact_inventory", "INVENTORY", reasons,
        Rows=len(observed_csv), Columns=len(observed_png))]


def verify_no_expected_csv_copy(
        root: Path, vector_root: Path,
        csv_contracts: dict[str, CsvContract]) -> list[dict[str, object]]:
    reasons: list[str] = []
    if not vector_root.is_dir():
        reasons.append(f"vector_root_missing:{vector_root}")
        return [result(
            "pdsch_no_expected_csv_copy", "INTEGRITY", reasons)]
    expected_by_digest: dict[str, list[str]] = {}
    for path in sorted(vector_root.rglob("expected_*.csv")):
        if path.is_file():
            expected_by_digest.setdefault(digest(path), []).append(
                str(path.relative_to(vector_root)))
    if not expected_by_digest:
        reasons.append("no_frozen_expected_csvs_found")
    for name in sorted(csv_contracts):
        actual = root / name
        if not actual.is_file():
            continue
        matches = expected_by_digest.get(digest(actual), [])
        if matches:
            reasons.append(
                f"byte_identical_to_frozen_expected:output={name}:"
                f"expected={'|'.join(matches)}")
    return [result(
        "pdsch_no_expected_csv_copy", "INTEGRITY", reasons,
        Rows=len(expected_by_digest))]

def verify_external_receiver_vector_binding(
        vector_root: Path,
        parsed: dict[str, list[dict[str, str]]]
        ) -> list[dict[str, object]]:
    manifest_path = vector_root / "independent_vector_manifest.json"
    if not manifest_path.is_file():
        return [result(
            "pdsch_external_receiver_vector_binding", "INTEGRITY", [],
            Rows=0, Mode="NOT_APPLICABLE_NO_VECTOR_MANIFEST")]

    reasons: list[str] = []
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return [result(
            "pdsch_external_receiver_vector_binding", "INTEGRITY",
            [f"vector_manifest_unreadable:{exc}"], Rows=0)]
    contract = manifest.get("external_receiver")
    required = {
        "fixture", "generator", "generator_sha256", "readme",
        "readme_sha256", "implementation", "version",
        "source_artifact_sha256", "fixture_schema_version",
    }
    if not isinstance(contract, dict) or not required <= set(contract):
        return [result(
            "pdsch_external_receiver_vector_binding", "INTEGRITY",
            ["external_receiver_manifest_missing_or_incomplete"], Rows=0)]

    fixture = vector_root / str(contract["fixture"])
    generator = vector_root / str(contract["generator"])
    readme = vector_root / str(contract["readme"])
    if not fixture.is_file():
        reasons.append(f"receiver_fixture_missing:{fixture.name}")
        fixture_rows: list[dict[str, str]] = []
    else:
        _, fixture_rows, csv_errors = read_rectangular_csv(fixture)
        reasons.extend(
            f"receiver_fixture_{error}" for error in csv_errors)
    if not generator.is_file() or (
            generator.is_file()
            and digest(generator) != str(contract["generator_sha256"])):
        reasons.append("receiver_generator_hash_mismatch")
    if not readme.is_file() or (
            readme.is_file()
            and digest(readme) != str(contract["readme_sha256"])):
        reasons.append("receiver_readme_hash_mismatch")

    file_contracts = {
        str(item.get("name", "")): item
        for item in manifest.get("files", [])
        if isinstance(item, dict)
    }
    fixture_contract = file_contracts.get(fixture.name)
    if fixture_contract is None:
        reasons.append("receiver_fixture_not_manifested")
    elif fixture.is_file():
        if str(fixture_contract.get("sha256", "")) != digest(fixture):
            reasons.append("receiver_fixture_manifest_hash_mismatch")
        if integer(str(fixture_contract.get("rows", ""))) != 1:
            reasons.append("receiver_fixture_manifest_row_count_mismatch")

    receiver_rows = [
        row for row in parsed.get(
            "pdsch_independent_vector_results.csv", [])
        if str(row.get("VectorFamily", "")).strip().lower()
        == "receiver_chain"
    ]
    if len(fixture_rows) != 1:
        reasons.append(
            f"receiver_fixture_row_count:{len(fixture_rows)}")
    if len(receiver_rows) != 1:
        reasons.append(
            f"receiver_evidence_row_count:{len(receiver_rows)}")
    if len(fixture_rows) == 1 and len(receiver_rows) == 1:
        fixture_row = fixture_rows[0]
        evidence_row = receiver_rows[0]
        fixture_hash = digest(fixture)
        expected_implementation = (
            str(contract["implementation"])
            + "/external_pdsch_waveform"
        )
        if fixture_row.get("FixtureSchemaVersion") != str(
                contract["fixture_schema_version"]):
            reasons.append("receiver_fixture_schema_version_mismatch")
        if fixture_row.get("SourceArtifactSHA256") != str(
                contract["source_artifact_sha256"]):
            reasons.append("receiver_fixture_source_hash_mismatch")
        if evidence_row.get("CaseID") != fixture_row.get("CaseID"):
            reasons.append("receiver_evidence_case_mismatch")
        if evidence_row.get("OracleImplementation") != (
                expected_implementation):
            reasons.append("receiver_evidence_implementation_mismatch")
        if evidence_row.get("OracleVersion") != str(contract["version"]):
            reasons.append("receiver_evidence_version_mismatch")
        if evidence_row.get("OracleArtifactSHA256") != fixture_hash:
            reasons.append("receiver_evidence_fixture_hash_mismatch")
        expected_tb = fixture_row.get(
            "ExpectedTransportBlockSHA256", "")
        if (
            evidence_row.get("ExpectedDigest") != expected_tb
            or evidence_row.get("ActualDigest") != expected_tb
        ):
            reasons.append("receiver_evidence_transport_block_mismatch")
        if "frozen waveform" not in str(
                evidence_row.get("ComparedField", "")).lower():
            reasons.append("receiver_evidence_not_frozen_waveform")
    return [result(
        "pdsch_external_receiver_vector_binding", "INTEGRITY", reasons,
        Rows=len(receiver_rows))]


def verify_plot_evidence(
        parsed: dict[str, list[dict[str, str]]]) -> list[dict[str, object]]:
    results: list[dict[str, object]] = []

    reference_reasons: list[str] = []
    dmrs_rows = parsed.get("pdsch_dmrs_matrix.csv", [])
    ptrs_rows = parsed.get("pdsch_ptrs_matrix.csv", [])
    dmrs_points = 0
    ptrs_points = 0

    def plot_coordinates(
            row: dict[str, str], line: int, label: str,
            reasons: list[str]) -> list[tuple[int, int]]:
        raw = str(row.get("PlotCoordinates0Based", "")).strip()
        if not raw:
            return []
        coordinates: list[tuple[int, int]] = []
        for token in raw.split("|"):
            parts = token.split(":")
            if len(parts) != 2:
                reasons.append(
                    f"{label}_plot_coordinate_malformed:line={line}")
                return []
            try:
                x, y = int(parts[0]), int(parts[1])
            except ValueError:
                reasons.append(
                    f"{label}_plot_coordinate_noninteger:line={line}")
                return []
            if x < 0 or y < 0:
                reasons.append(
                    f"{label}_plot_coordinate_negative:line={line}")
                return []
            coordinates.append((x, y))
        return coordinates

    for line, row in enumerate(dmrs_rows, 2):
        count = integer(row.get("DMRSRECount", ""))
        coordinates = plot_coordinates(
            row, line, "dmrs", reference_reasons)
        if count is None or count <= 0 or len(coordinates) != count:
            reference_reasons.append(
                f"dmrs_plot_coordinate_count_mismatch:line={line}")
        else:
            dmrs_points += len(coordinates)
    for line, row in enumerate(ptrs_rows, 2):
        expected = truth(row.get("ExpectedPresent", ""))
        count = integer(row.get("PTRSRECount", ""))
        coordinates = plot_coordinates(
            row, line, "ptrs", reference_reasons)
        if count is None or len(coordinates) != count:
            reference_reasons.append(
                f"ptrs_plot_coordinate_count_mismatch:line={line}")
        elif expected is True and count <= 0:
            reference_reasons.append(
                f"ptrs_present_without_coordinates:line={line}")
        else:
            ptrs_points += len(coordinates)
    if dmrs_points < 1 or ptrs_points < 1:
        reference_reasons.append(
            f"reference_coordinate_series_empty:dmrs={dmrs_points}:"
            f"ptrs={ptrs_points}")
    results.append(result(
        "pdsch_dmrs_ptrs_map.png", "EVIDENCE", reference_reasons))

    reserved_reasons: list[str] = []
    ownership = parsed.get("pdsch_resource_ownership.csv", [])
    coding = parsed.get("pdsch_coding_chain.csv", [])
    ownership_by_case: dict[str, list[dict[str, str]]] = {}
    coding_by_case: dict[str, list[dict[str, str]]] = {}
    for row in ownership:
        ownership_by_case.setdefault(
            str(row.get("CaseID", "")).strip(), []).append(row)
    for row in coding:
        coding_by_case.setdefault(
            str(row.get("CaseID", "")).strip(), []).append(row)
    aligned: list[tuple[str, int, int, int]] = []
    for case_id in sorted(set(ownership_by_case) & set(coding_by_case)):
        own_rows = ownership_by_case[case_id]
        coordinates = tuple(sorted(
            (
                str(row.get("Slot", "")),
                str(row.get("PRB", "")),
                str(row.get("Symbol", "")),
                str(row.get("Subcarrier", "")),
            )
            for row in own_rows
        ))
        geometry_key = hashlib.sha256(
            repr(coordinates).encode("utf-8")).hexdigest()
        reserved_count = sum(
            str(row.get("Owner", "")).strip().lower().startswith("reserved")
            for row in own_rows
        )
        g_values = [integer(row.get("G", "")) for row in coding_by_case[case_id]]
        tbs_values = [
            integer(row.get("TBS", "")) for row in coding_by_case[case_id]]
        if any(value is None or value <= 0 for value in g_values + tbs_values):
            reserved_reasons.append(
                f"aligned_reserved_coding_invalid:{case_id}")
            continue
        aligned.append((
            geometry_key, reserved_count,
            sum(value for value in g_values if value is not None),
            sum(value for value in tbs_values if value is not None),
        ))
    geometry_groups: dict[str, list[tuple[int, int, int]]] = {}
    for geometry, reserved_count, g_value, tbs_value in aligned:
        geometry_groups.setdefault(geometry, []).append(
            (reserved_count, g_value, tbs_value))
    candidates = [
        values for values in geometry_groups.values()
        if any(item[0] == 0 for item in values)
        and any(item[0] > 0 for item in values)
    ]
    if not candidates:
        reserved_reasons.append(
            "no_exact_geometry_with_reserved_and_unreserved_coding")
    else:
        values = max(candidates, key=len)
        baseline_g = max(item[1] for item in values if item[0] == 0)
        if any(item[1] >= baseline_g for item in values if item[0] > 0):
            reserved_reasons.append(
                "reserved_execution_did_not_reduce_exact_g")
        ordered = sorted(values, key=lambda item: item[0])
        if any(right[1] > left[1]
               for left, right in zip(ordered, ordered[1:])):
            reserved_reasons.append(
                "reserved_g_nonmonotonic_for_exact_geometry")
    results.append(result(
        "pdsch_reserved_re_impact.png", "EVIDENCE", reserved_reasons))

    phase_reasons: list[str] = []
    test_summary = parsed.get("pdsch_test_summary.csv", [])
    phase_rows = parsed.get("pdsch_phase_execution_summary.csv", [])
    artifact_suite_present = any(
        str(row.get("TestSuite", "")).strip()
        == "testPDSCHArtifactGeneration"
        for row in test_summary
    )
    artifact_execution_present = any(
        str(row.get("Source", "")).strip()
        == "testPDSCHArtifactGeneration"
        for row in phase_rows
    )
    if artifact_suite_present and not artifact_execution_present:
        phase_reasons.append(
            "artifact_suite_has_no_measured_phase_execution_row")
    results.append(result(
        "pdsch_phase_execution_summary.csv",
        "EVIDENCE", phase_reasons))
    return results


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
        if image_name == "pdsch_dmrs_ptrs_map.png":
            actual_sources = tuple(
                token.strip()
                for token in str(
                    row.get("ActualPlotSourceCSV", "")).split("|")
                if token.strip())
            if actual_sources != contract.sources:
                reasons.append(
                    "dmrs_ptrs_actual_plot_source_mismatch")
            if any(
                    Path(source).name != source or not source.endswith(".csv")
                    for source in actual_sources):
                reasons.append(
                    "dmrs_ptrs_actual_plot_source_invalid_path")
            actual_hash = expected_source_hash_text(root, actual_sources)
            if actual_hash is None:
                reasons.append(
                    "dmrs_ptrs_actual_plot_source_missing_for_hash")
            elif str(row.get(
                    "ActualPlotSourceCSV_SHA256", "")).strip() \
                    != actual_hash:
                reasons.append(
                    "dmrs_ptrs_actual_plot_source_hash_mismatch")
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


def verify(
        root: Path, vector_root: Path,
        write_output: bool = True) -> tuple[int, list[dict[str, object]]]:
    csv_contracts, image_contracts = read_contracts()
    csv_results, parsed = verify_csvs(root, csv_contracts)
    inventory_results = verify_artifact_inventory(
        root, csv_contracts, image_contracts)
    no_copy_results = verify_no_expected_csv_copy(
        root, vector_root, csv_contracts)
    receiver_binding_results = verify_external_receiver_vector_binding(
        vector_root, parsed)
    evidence_results = verify_plot_evidence(parsed)
    png_results, png_meta = verify_pngs(root, image_contracts)
    semantic_results = verify_semantic_audit(root, image_contracts, parsed, png_meta)
    all_results = (
        csv_results + inventory_results + no_copy_results
        + receiver_binding_results + evidence_results
        + png_results + semantic_results)
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
            rows = []
            for case_id, reserved_count in (
                    ("SYN-RES-UNRESERVED", 0),
                    ("SYN-RES-RESERVED", 1)):
                for subcarrier in range(4):
                    q = base_row(contract.columns)
                    q.update(
                        CaseID=case_id, Slot=0, PRB=0, Symbol=2,
                        Subcarrier=subcarrier,
                        Owner=(
                            "reserved_rate_match_pattern"
                            if subcarrier < reserved_count
                            else "pdsch_data"),
                        CollisionCount=0,
                    )
                    rows.append(q)
        elif name == "pdsch_re_mapping.csv":
            r.update(CaseID="SYN-001", Domain="DATA", Codeword=0, Layer=0, Port=0, PRB=0, Symbol=2, Subcarrier=0, LinearIndex0Based=0)
        elif name == "pdsch_dmrs_matrix.csv":
            r.update(
                MappingType="A", DMRSConfigurationType=1,
                DMRSSymbols="2|5", DMRSRECount=12,
                PlotCoordinates0Based="|".join(
                    f"{subcarrier}:{symbol}"
                    for symbol in (2, 5)
                    for subcarrier in (0, 2, 4, 6, 8, 10)),
                IndexMismatchCount=0,
                SequenceNMSE=0,
                SequenceDigest=hashlib.sha256(
                    b"synthetic-dmrs-sequence").hexdigest())
        elif name == "pdsch_ptrs_matrix.csv":
            r.update(
                ExpectedPresent=1, PTRSRECount=12,
                PlotCoordinates0Based="|".join(
                    f"{subcarrier}:3" for subcarrier in range(12)),
                CPEBeforeDeg=8, CPEAfterDeg=1,
                EVMBeforePercent=10, EVMAfterPercent=2)
        elif name == "pdsch_coding_chain.csv":
            rows = []
            for case_id, g_value in (
                    ("SYN-RES-UNRESERVED", 8),
                    ("SYN-RES-RESERVED", 6)):
                q = base_row(contract.columns)
                q.update(
                    CaseID=case_id, Codeword=0, TBS=4,
                    BaseGraph=2, G=g_value,
                    RateMatchedBits=g_value, CRCOK=1,
                )
                rows.append(q)
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
                actual_digest = hashlib.sha256(
                    f"synthetic-result-{family}".encode()).hexdigest()
                q.update(
                    VectorFamily=family, CaseID=f"SYN-{idx:03d}",
                    ComparedField="all",
                    OracleImplementation="independent_python_self_test",
                    OracleVersion="1.0.0",
                    OracleArtifactSHA256=hashlib.sha256(
                        f"synthetic-oracle-{family}".encode()).hexdigest(),
                    ExpectedDigest=actual_digest,
                    ActualDigest=actual_digest, MismatchCount=0,
                    MaxAbsError=0, Tolerance=0)
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
                matrix_digest = hashlib.sha256(
                    f"synthetic-precoder-{idx}".encode()).hexdigest()
                q.update(
                    CaseID=f"SYN-P{idx}", Mode=mode, PRG=idx-1,
                    SymbolGroup=0, MatrixDigest=matrix_digest,
                    AppliedMatrixDigest=matrix_digest,
                    TXApplicationCount=1, RXApplicationCount=1,
                    PowerRelativeError=0)
                rows.append(q)
        elif name == "pdsch_harq_trials.csv":
            rows = []
            for tx, (rv, combined, ok) in enumerate(((0, 0, 0), (2, 1, 1)), 1):
                q = base_row(contract.columns)
                q.update(
                    CaseID="SYN-HARQ", HARQProcessID=2, Codeword=0,
                    TransmissionIndex=tx, NDI=1, RV=rv,
                    CodeBlockLayoutDigest=hashlib.sha256(
                        b"synthetic-layout").hexdigest(),
                    SoftBufferInputDigest=hashlib.sha256(
                        f"synthetic-soft-in-{tx}".encode()).hexdigest(),
                    SoftBufferOutputDigest=hashlib.sha256(
                        f"synthetic-soft-out-{tx}".encode()).hexdigest(),
                    Combined=combined, TBCRCOK=ok)
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
            for campaign_index, (
                    campaign, (channel, rank, modulation, mcs)) in enumerate(
                        BLER_CAMPAIGNS.items(), 1):
                for idx, snr in enumerate((-2, 0, 2, 4), 1):
                    trials = 1000
                    errors = max(1, 400 - idx * 90)
                    estimate = errors / trials
                    low = max(0, estimate - 0.03)
                    high = min(1, estimate + 0.03)
                    q = base_row(contract.columns)
                    q.update(
                        CampaignID=campaign,
                        OperatingPointID=f"OP-{idx:02d}",
                        SNRdB=snr + 6 * campaign_index,
                        ChannelModel=channel, Rank=rank, MCSIndex=mcs,
                        Modulation=modulation, Trials=trials,
                        TBErrors=errors, BLER=estimate,
                        ConfidenceLevel=0.95, CILower=low, CIUpper=high,
                        CIHalfWidth=(high - low) / 2,
                        MinErrorsRequired=1,
                        StopReason="CI_AND_MIN_ERRORS_MET")
                    rows.append(q)
        elif name == "pdsch_negative_tests.csv":
            rows = []
            case_index = 0
            for family, count in NEGATIVE_FAMILY_COUNTS.items():
                for family_index in range(1, count + 1):
                    case_index += 1
                    q = base_row(contract.columns)
                    error_id = (
                        f"sixgr:pdsch:selftest:{family}:"
                        f"{family_index:03d}")
                    q.update(
                        CaseID=f"SYN-NEG-{case_index:03d}",
                        TestKind=family,
                        ExpectedErrorIdentifier=error_id,
                        ActualErrorIdentifier=error_id,
                        WaveformGenerated=0)
                    rows.append(q)
            for family, count in DECLARED_NEGATIVE_MINIMUM_COUNTS.items():
                for family_index in range(1, count + 1):
                    case_index += 1
                    q = base_row(contract.columns)
                    error_id = (
                        f"sixgr:pdsch:selftest:{family}:"
                        f"{family_index:03d}")
                    q.update(
                        CaseID=f"SYN-NEG-{case_index:03d}",
                        TestKind=family,
                        ExpectedErrorIdentifier=error_id,
                        ActualErrorIdentifier=error_id,
                        WaveformGenerated=0)
                    rows.append(q)
            integration_ids = set(
                MANDATORY_INTEGRATION_NEGATIVES.values())
            for identifier in sorted(
                    MANDATORY_NEGATIVE_IDENTIFIERS - integration_ids):
                case_index += 1
                q = base_row(contract.columns)
                q.update(
                    CaseID=f"SYN-NEG-{case_index:03d}",
                    TestKind="prompt_mandatory_identifier",
                    ExpectedErrorIdentifier=identifier,
                    ActualErrorIdentifier=identifier,
                    WaveformGenerated=0)
                rows.append(q)
            for family, identifier in (
                    MANDATORY_INTEGRATION_NEGATIVES.items()):
                case_index += 1
                q = base_row(contract.columns)
                q.update(
                    CaseID=f"SYN-NEG-{case_index:03d}",
                    TestKind=family,
                    ExpectedErrorIdentifier=identifier,
                    ActualErrorIdentifier=identifier,
                    WaveformGenerated=0)
                rows.append(q)
        elif name == "pdsch_test_summary.csv":
            rows = []
            for suite in sorted(FINAL_TEST_SUITES):
                q = base_row(contract.columns)
                q.update(
                    TestSuite=suite, Total=1, Passed=1, Failed=0,
                    Skipped=0, Blocked=0)
                rows.append(q)
        elif name == "pdsch_declared_coverage_results.csv":
            rows = []
            kinds = (
                "positive", "no_signal", "wrong_rnti", "wrong_dmrs",
                "wrong_rv", "reserved_re", "impairment",
            )
            production_backend_by_kind = {
                "positive": "canonical_pdsch_tx_channel_rx",
                "no_signal": "canonical_receiver_input_validation",
                "wrong_rnti": "canonical_assignment_validation",
                "wrong_dmrs": "canonical_dmrs_configuration_validation",
                "wrong_rv": "canonical_dlsch_coding_plan_validation",
                "reserved_re": "canonical_pdsch_tx_channel_rx",
                "impairment": "canonical_pdsch_tx_channel_rx",
            }
            channels = ("AWGN", "TDL-A", "CDL-C")
            modulations = (
                "QPSK", "16QAM", "64QAM", "256QAM", "1024QAM")
            for case_index in range(16):
                channel = channels[case_index % len(channels)]
                for kind in kinds:
                    q = base_row(contract.columns)
                    tx = kind in {"positive", "reserved_re", "impairment"}
                    rx = tx or kind == "no_signal"
                    q.update(
                        CaseID=f"SYN-COV-{case_index + 1:03d}",
                        TestKind=kind,
                        Rank=case_index // 2 + 1,
                        Modulation=modulations[
                            case_index % len(modulations)],
                        ChannelModel=channel,
                        ProductionTXExecuted=int(tx),
                        ProductionRXExecuted=int(rx),
                        ExpectedStatus="PASS", ActualStatus="PASS",
                        ErrorIdentifier="",
                        ExecutionBackend=production_backend_by_kind[kind],
                        ChannelEstimateScope=(
                            "dmrs_backed_resource_selective_"
                            "effective_layer_channel"
                            if channel != "AWGN" and tx
                            else "pre_tx_validation_only"),
                        ReceiverCRCPass=int(
                            kind in {"positive", "reserved_re"}),
                        EvidenceDetail="observed_production_execution",
                    )
                    rows.append(q)
        elif name == "pdsch_pairwise_cases.csv":
            rows = []
            channels = ("AWGN", "TDL-A", "CDL-C", "AWGN")
            modulations = (
                "QPSK", "16QAM", "64QAM", "256QAM", "1024QAM")
            numerologies = (15, 30, 60, 120)
            precoding_modes = (
                "wideband_codebook", "prg_codebook",
                "prg_noncodebook")
            reservation_modes = ("none", "single", "overlapping")
            pair_definition = (
                "independently_enumerated_feasible_pairs_over_mandatory_"
                "domains_with_dmrs_rank_constraints")
            pair_hash = hashlib.sha256(
                b"synthetic-independent-feasible-pair-universe").hexdigest()
            for index in range(48):
                q = base_row(contract.columns)
                channel = channels[index % len(channels)]
                rank = index % 8 + 1
                dmrs_length = 2 if index % 6 in {4, 5} else 1
                dmrs_additional = (
                    index % 2 if dmrs_length == 2 else index % 4)
                reservation_mode = reservation_modes[
                    index % len(reservation_modes)]
                if reservation_mode == "none":
                    source_count, overlap, reserved = 0, 0, 0
                elif reservation_mode == "single":
                    source_count, overlap, reserved = 1, 0, 4
                else:
                    source_count, overlap, reserved = 3, 1, 6
                q.update(
                    CaseID=f"SYN-PAIR-{index + 1:03d}",
                    Rank=rank,
                    NumCodewords=1 if rank <= 4 else 2,
                    MappingType="A" if index % 2 == 0 else "B",
                    DMRSConfigurationType=1 + index % 2,
                    DMRSLength=dmrs_length,
                    DMRSAdditionalPosition=dmrs_additional,
                    DMRSMultiplexing=(
                        "basic" if index < 8 else "enhanced"),
                    PTRSEnabled=index % 2,
                    Modulation=modulations[index % len(modulations)],
                    RV=index % 4, RVSequence=str(index % 4),
                    PrecodingMode=precoding_modes[
                        index % len(precoding_modes)],
                    NumerologyKHz=numerologies[
                        index % len(numerologies)],
                    PRBSet=(
                        "0|1|2|3" if index % 2 == 0 else "0|2|3"),
                    AllocationShape=(
                        "contiguous"
                        if index % 2 == 0 else "noncontiguous"),
                    ReservationMode=reservation_mode,
                    ReservationSourceCount=source_count,
                    ReservationOverlapMultiplicity=overlap,
                    ReservedRECount=reserved,
                    DeclaredChannelModel=channel,
                    ExecutionChannelModel=channel,
                    FadingTruthAnchorCaseID=(
                        "" if channel == "AWGN"
                        else f"SYN-ANCHOR-{index + 1:03d}"),
                    ProductionTXExecuted=1,
                    ProductionRXExecuted=1, CRCPass=1,
                    GenerationPolicy=(
                        "deterministic_materialized_factor_covering_array_v2"),
                    PairUniverseDefinition=pair_definition,
                    RequiredPairCount=360,
                    CoveredPairCount=360,
                    MissingPairCount=0,
                    PairCoverageSHA256=pair_hash,
                )
                rows.append(q)
        elif name == "pdsch_no_noise_roundtrip.csv":
            rows = []
            modulations = (
                "QPSK", "16QAM", "64QAM", "256QAM", "1024QAM")
            case_index = 0
            for rank in range(1, 9):
                for modulation in modulations:
                    case_index += 1
                    num_codewords = 1 if rank <= 4 else 2
                    q = base_row(contract.columns)
                    q.update(
                        CaseID=f"SYN-NN-{case_index:03d}",
                        Rank=rank, Modulation=modulation,
                        NumCodewords=num_codewords,
                        TransportBlockSize=(
                            "64" if num_codewords == 1 else "64|72"),
                        BitErrors=0, CRCPass=1,
                        ExactStageLengths=1, CollisionCount=0,
                        FiniteMetrics=1, ProductionTXExecuted=1,
                        ProductionRXExecuted=1,
                    )
                    rows.append(q)
        elif name == "pdsch_phase_execution_summary.csv":
            rows = []
            stages = (
                ("vector_pack_verification", "verify_pdsch_vector_pack.py"),
                ("phase_evidence_builder", "PDSCHPhaseEvidenceBuilder"),
                ("coverage_executor", "PDSCHCoverageExecutor"),
                ("focused_test_function", "testPDSCHReceiverNoNoiseExact"),
                ("focused_test_function", "testPDSCHArtifactGeneration"),
                ("artifact_export", "PDSCHArtifactExporter"),
                ("matlab_output_contract", "runPDSCHPhaseValidation"),
            )
            for index, (stage, source) in enumerate(stages, 1):
                q = base_row(contract.columns)
                q.update(
                    Stage=stage, Source=source,
                    ExecutionMode="measured_direct_execution",
                    RecordCount=1, PassedCount=1, FailedCount=0,
                    DurationSeconds=0.001 * index,
                    ErrorIdentifier="", ErrorMessage="",
                    Detail="observed_elapsed_time_and_record_count",
                )
                rows.append(q)
        if not rows:
            rows = [r]
        columns = contract.columns
        if name in {
                "pdsch_dmrs_matrix.csv",
                "pdsch_ptrs_matrix.csv"}:
            columns = columns + ("PlotCoordinates0Based",)
        write_csv(root / name, columns, rows)


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
        actual_sources = contract.sources
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
            "ActualPlotSourceCSV": "|".join(actual_sources),
            "ActualPlotSourceCSV_SHA256": expected_source_hash_text(
                root, actual_sources),
            "PNG_SHA256": digest(path),
            "Status": "PASS",
        })
    columns = tuple(csv_contract.columns) + (
        "ActualPlotSourceCSV", "ActualPlotSourceCSV_SHA256")
    write_csv(root / csv_contract.name, columns, rows)


def self_test() -> int:
    csv_contracts, image_contracts = read_contracts()
    with tempfile.TemporaryDirectory(prefix="pdsch-verifier-self-test-") as tmp:
        root = Path(tmp)
        vector_root = root / "vectors"
        vector_root.mkdir()
        write_csv(
            vector_root / "expected_self_test_anchor.csv",
            ("Oracle", "Value"),
            ({"Oracle": "independent", "Value": "anchor"},))
        create_synthetic_csvs(root, csv_contracts)
        create_synthetic_images(root, image_contracts)
        create_semantic_audit(root, image_contracts, csv_contracts["pdsch_image_semantic_audit.csv"])
        good_code, good_rows = verify(
            root, vector_root, write_output=False)

        def mutate_csv(
                name: str,
                mutation: object) -> tuple[int, list[dict[str, object]]]:
            path = root / name
            original = path.read_bytes()
            try:
                header, rows, errors = read_rectangular_csv(path)
                if errors or not rows:
                    raise RuntimeError(
                        f"self-test setup invalid for {name}: {errors}")
                mutation(rows)
                write_csv(path, header, rows)
                return verify(root, vector_root, write_output=False)
            finally:
                path.write_bytes(original)

        omission_checks: list[tuple[str, int, bool]] = []
        code, rows = mutate_csv(
            "pdsch_test_summary.csv",
            lambda values: values.pop())
        omission_checks.append((
            "mandatory_suite", code,
            any("test_suite_set_mismatch" in str(row["Reason"])
                for row in rows if row["Status"] == "FAIL")))
        code, rows = mutate_csv(
            "pdsch_bler_curve.csv",
            lambda values: values.__setitem__(
                slice(None),
                [row for row in values
                 if row["CampaignID"] != "BLER-AWGN-PTRS-PN"]))
        omission_checks.append((
            "bler_campaign", code,
            any("bler_campaign_set_mismatch" in str(row["Reason"])
                for row in rows if row["Status"] == "FAIL")))
        code, rows = mutate_csv(
            "pdsch_negative_tests.csv",
            lambda values: values.pop())
        omission_checks.append((
            "typed_negative", code,
            any("missing_mandatory_integration_negative" in str(row["Reason"])
                for row in rows if row["Status"] == "FAIL")))
        code, rows = mutate_csv(
            "pdsch_pairwise_cases.csv",
            lambda values: values.__setitem__(
                slice(None), values[:39]))
        omission_checks.append((
            "pairwise_row_floor", code,
            any("pairwise_row_count_below_floor" in str(row["Reason"])
                for row in rows if row["Status"] == "FAIL")))

        def corrupt_pairwise_proof(
                values: list[dict[str, str]]) -> None:
            values[0]["MissingPairCount"] = "1"

        code, rows = mutate_csv(
            "pdsch_pairwise_cases.csv",
            corrupt_pairwise_proof)
        omission_checks.append((
            "pairwise_coverage_proof", code,
            any("pairwise_invalid_coverage_counts" in str(row["Reason"])
                for row in rows if row["Status"] == "FAIL")))

        def omit_dmrs_plot_coordinates(
                values: list[dict[str, str]]) -> None:
            values[0]["PlotCoordinates0Based"] = ""

        code, rows = mutate_csv(
            "pdsch_dmrs_matrix.csv",
            omit_dmrs_plot_coordinates)
        omission_checks.append((
            "dmrs_ptrs_matrix_coordinates", code,
            any(
                "dmrs_plot_coordinate_count_mismatch"
                in str(row["Reason"])
                for row in rows if row["Status"] == "FAIL")))

        copied_expected = (
            vector_root / "expected_renamed_actual_output.csv")
        copied_expected.write_bytes(
            (root / "pdsch_independent_vector_results.csv").read_bytes())
        copied_code, copied_rows = verify(
            root, vector_root, write_output=False)
        copied_detected = any(
            "byte_identical_to_frozen_expected" in str(row["Reason"])
            for row in copied_rows if row["Status"] == "FAIL")
        copied_expected.unlink()

        # Corrupt a recorded PNG digest without changing the image. The verifier
        # must reject this integrity failure.
        audit_path = root / "pdsch_image_semantic_audit.csv"
        header, rows, errors = read_rectangular_csv(audit_path)
        if errors or not rows:
            print("SELF-TEST setup failed")
            return 3
        rows[0]["PNG_SHA256"] = "0" * 64
        write_csv(audit_path, header, rows)
        bad_code, bad_rows = verify(
            root, vector_root, write_output=False)
        bad_failures = [r for r in bad_rows if r["Status"] == "FAIL"]
        expected_detected = any("png_hash_mismatch" in str(r["Reason"]) for r in bad_failures)
        print(f"Verifier self-test valid set: exit={good_code}, checks={len(good_rows)}, failures={sum(r['Status']!='PASS' for r in good_rows)}")
        for label, exit_code, detected in omission_checks:
            print(
                "Verifier self-test omission "
                f"{label}: exit={exit_code}, detected={detected}")
        print(
            "Verifier self-test renamed expected copy: "
            f"exit={copied_code}, detected={copied_detected}")
        print(f"Verifier self-test corrupted hash: exit={bad_code}, checks={len(bad_rows)}, failures={len(bad_failures)}, detected={expected_detected}")
        omissions_detected = all(
            code == 2 and detected
            for _, code, detected in omission_checks)
        return 0 if (
            good_code == 0
            and omissions_detected
            and copied_code == 2 and copied_detected
            and bad_code == 2 and expected_detected) else 3


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", nargs="?", type=Path, help="Directory containing PDSCH phase artifacts")
    parser.add_argument(
        "--vector-root", type=Path, default=HERE,
        help="Frozen PDSCH vector root used for no-copy integrity checks")
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
    vector_root = args.vector_root.resolve()
    if not vector_root.is_dir():
        print(f"Vector root not found: {vector_root}", file=sys.stderr)
        return 2
    code, _ = verify(root, vector_root)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
