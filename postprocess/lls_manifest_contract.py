#!/usr/bin/env python3
"""Authoritative publication manifest for 6GR LLS run folders.

The helpers in this module audit completed run folders. They never fabricate
primary rows. Missing evidence is reported as missing or blocked, and generator
scripts may only derive secondary artifacts from existing measured CSV inputs.
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable, Mapping, Any

import pandas as pd


ConstraintResult = dict[str, bool | None | str]
ConstraintFn = Callable[[pd.DataFrame], ConstraintResult]


@dataclass(frozen=True)
class CsvSpec:
    path: str
    tier: str
    required_columns: tuple[str, ...]
    min_rows: int = 0
    description: str = ""
    source: str = ""
    constraints: ConstraintFn | None = None
    primary: bool = False
    row_filter: Callable[[pd.DataFrame], pd.DataFrame] | None = None


@dataclass(frozen=True)
class ImageSpec:
    path: str
    tier: str
    source_csv: str
    description: str = ""
    required: bool = True
    unavailable_stems: tuple[str, ...] = field(default_factory=tuple)


def _as_text(value: object) -> str:
    if value is None:
        return ""
    try:
        if pd.isna(value):
            return ""
    except Exception:
        pass
    return str(value).strip()


def _bool_series(series: pd.Series) -> pd.Series:
    if series.empty:
        return pd.Series(dtype=bool)
    if pd.api.types.is_bool_dtype(series):
        return series.fillna(False)
    if pd.api.types.is_numeric_dtype(series):
        return pd.to_numeric(series, errors="coerce").fillna(0).astype(float) != 0
    return series.astype(str).str.strip().str.lower().isin({"1", "true", "yes", "pass", "ok", "detected"})


def _num(series: pd.Series) -> pd.Series:
    return pd.to_numeric(series, errors="coerce")


def _has(df: pd.DataFrame, *cols: str) -> bool:
    return all(col in df.columns for col in cols)


def _empty_or_blank(series: pd.Series) -> bool:
    return series.map(_as_text).eq("").all()


def _no_bad_tokens(series: pd.Series, bad_tokens: Iterable[str]) -> bool:
    values = series.map(_as_text).str.lower()
    return not values.apply(lambda v: any(tok in v for tok in bad_tokens)).any()


def _non_warmup(df: pd.DataFrame) -> pd.DataFrame:
    if "IsWarmupFrame" not in df.columns:
        return df
    return df[~_bool_series(df["IsWarmupFrame"])]


def _all_true(df: pd.DataFrame, col: str) -> bool:
    return _has(df, col) and _bool_series(df[col]).all()


def _any_true(df: pd.DataFrame, col: str) -> bool:
    return _has(df, col) and _bool_series(df[col]).any()


def _finite_all(df: pd.DataFrame, col: str) -> bool:
    return _has(df, col) and _num(df[col]).notna().all()


def _constraint_raw_dl(df: pd.DataFrame) -> ConstraintResult:
    nw = _non_warmup(df)
    bad_noise = {"configured_snr", "synthetic", "fallback", "oracle", "perfect"}
    bad_channel = {"perfect", "oracle", "genie"}
    return {
        "min_non_warmup_rows": len(nw) >= 200,
        "used_oracle_fields_empty": _has(df, "UsedOracleFields") and _empty_or_blank(df["UsedOracleFields"]),
        "noise_source_measurement_backed": _has(df, "NoiseVarSource") and _no_bad_tokens(df["NoiseVarSource"], bad_noise),
        "channel_estimation_not_oracle": _has(df, "ChannelEstMethod") and _no_bad_tokens(df["ChannelEstMethod"], bad_channel),
        "layers_positive": _has(df, "Layers") and (_num(df["Layers"]) >= 1).all(),
    }


def _constraint_raw_ul(df: pd.DataFrame) -> ConstraintResult:
    ok_rate = None
    if _has(df, "MeasuredRateMatchedBits", "DataRECount", "Qm", "Layers"):
        lhs = _num(df["MeasuredRateMatchedBits"])
        rhs = _num(df["DataRECount"]) * _num(df["Qm"]) * _num(df["Layers"])
        ok_rate = (lhs - rhs).abs().dropna().le(1).all()
    slot_ok = None
    if "SlotType" in df.columns:
        slot_ok = df["SlotType"].map(_as_text).isin({"regular", "special_slot_mini"}).all()
    return {
        "min_rows": len(df) >= 20,
        "used_oracle_fields_empty": "UsedOracleFields" not in df.columns or _empty_or_blank(df["UsedOracleFields"]),
        "measured_rate_matched_bits_consistent": ok_rate,
        "slot_type_known": slot_ok,
    }


def _constraint_pdcch(df: pd.DataFrame) -> ConstraintResult:
    return {
        "min_rows": len(df) >= 61,
        "slot_coupled": _has(df, "AbsoluteSlot") and (_num(df["AbsoluteSlot"]) > 0).any(),
        "used_oracle_fields_empty": "UsedOracleFields" not in df.columns or _empty_or_blank(df["UsedOracleFields"]),
    }


def _constraint_pucch(df: pd.DataFrame) -> ConstraintResult:
    label_tokens = {"detected", "pass", "fail", "bypassed", "waveform", "n/a"}
    numeric_cols = [c for c in ["DetectionMetric", "DetectionThreshold", "PostEqSINR_dB", "NoiseVariance"] if c in df.columns]
    numeric_ok = all(_num(df[c]).notna().all() for c in numeric_cols) if numeric_cols else False
    token_ok = not df.apply(lambda col: col.map(_as_text).str.lower().isin(label_tokens).any()).any()
    return {
        "numeric_measurement_columns": numeric_ok,
        "no_label_proxy_tokens": token_ok,
        "posteq_sinr_finite": _finite_all(df, "PostEqSINR_dB"),
        "has_crc_applicable_row": _any_true(df, "CRCApplicable"),
    }


def _constraint_srs(df: pd.DataFrame) -> ConstraintResult:
    method_ok = None
    if "EstimationMethod" in df.columns:
        method_ok = df["EstimationMethod"].map(_as_text).str.lower().isin(
            {"ls+mmse_wiener", "ls_mmse_wiener", "mmse_wiener", "dmrs_nrchannelestimate"}
        ).all()
    return {
        "nmse_negative": _has(df, "NMSE_dB") and (_num(df["NMSE_dB"]) < 0).all(),
        "estimation_method_measurement_backed": method_ok,
    }


def _constraint_trs(df: pd.DataFrame) -> ConstraintResult:
    err_ok = None
    if _has(df, "EstimationError_Hz"):
        err_ok = _num(df["EstimationError_Hz"]).abs().dropna().lt(50).all()
    elif _has(df, "EstimatedDopplerHz", "TheoreticalDoppler_Hz"):
        err_ok = (_num(df["EstimatedDopplerHz"]) - _num(df["TheoreticalDoppler_Hz"])).abs().dropna().lt(50).all()
    return {
        "positive_estimated_doppler": _has(df, "EstimatedDopplerHz") and (_num(df["EstimatedDopplerHz"]) > 0).all(),
        "estimation_error_within_50hz": err_ok,
    }


def _constraint_prach(df: pd.DataFrame) -> ConstraintResult:
    return {
        "min_rows": len(df) >= 2,
        "used_oracle_fields_empty": "UsedOracleFields" not in df.columns or _empty_or_blank(df["UsedOracleFields"]),
        "all_detected": _all_true(df, "Detected"),
    }


def _constraint_strict_ok_no_oracle(df: pd.DataFrame) -> ConstraintResult:
    return {
        "strict_ok": "StrictOk" not in df.columns or _bool_series(df["StrictOk"]).all(),
        "used_oracle_fields_empty": "UsedOracleFields" not in df.columns or _empty_or_blank(df["UsedOracleFields"]),
        "oracle_field_rows_zero": "OracleFieldRows" not in df.columns or (_num(df["OracleFieldRows"]).fillna(0) == 0).all(),
    }


def _constraint_measured_sinr_summary(df: pd.DataFrame) -> ConstraintResult:
    dirs = set(df["Direction"].map(_as_text).str.upper()) if "Direction" in df.columns else set()
    formula_ok = None
    if "KPIFormulaVersion" in df.columns:
        formula_ok = df["KPIFormulaVersion"].map(_as_text).eq("measured_sinr_geometry_v1").all()
    sinr_ok = None
    if "SINR_median_dB" in df.columns:
        sinr_ok = _num(df["SINR_median_dB"]).notna().all()
    return {
        "geometry_formula_version": formula_ok,
        "finite_median_sinr": sinr_ok,
        "has_dl_and_ul": {"DL", "UL"}.issubset(dirs) if dirs else None,
        "minimum_rows": len(df) >= 2,
    }


def _constraint_kpi_summary(df: pd.DataFrame) -> ConstraintResult:
    if "KPIFormulaVersion" in df.columns or "KPIReconciliationPass" in df.columns:
        return {
            "geometry_formula_version": "KPIFormulaVersion" not in df.columns or df["KPIFormulaVersion"].map(_as_text).eq("measured_sinr_geometry_v1").all(),
            "kpi_reconciliation_pass": "KPIReconciliationPass" not in df.columns or _bool_series(df["KPIReconciliationPass"]).all(),
            "status_not_failed": "Status" not in df.columns or ~df["Status"].map(_as_text).str.lower().eq("fail").any(),
        }
    return {
        "kpi_consistency_ok": _all_true(df, "KpiConsistencyOk"),
        "radio_duration_available": _has(df, "RadioDurationUnavailable") and not _bool_series(df["RadioDurationUnavailable"]).any(),
    }


def _constraint_fer(df: pd.DataFrame) -> ConstraintResult:
    return {"has_scope_column": "Scope" in df.columns}


def _constraint_channel_configured(df: pd.DataFrame) -> ConstraintResult:
    ok = None
    if "ConfiguredAppliedOk" in df.columns and len(df) > 0:
        ok = _bool_series(df["ConfiguredAppliedOk"]).mean() >= 0.95
    return {"configured_applied_mostly_ok": ok}


def _constraint_cdlc(df: pd.DataFrame) -> ConstraintResult:
    rms_ok = None
    if _has(df, "Delay_ns", "RelativePower_dB") and len(df) == 24:
        delays = _num(df["Delay_ns"]).to_numpy()
        weights = 10 ** (_num(df["RelativePower_dB"]).to_numpy() / 10)
        weights = weights / weights.sum()
        mean_delay = (weights * delays).sum()
        rms = math.sqrt(float((weights * (delays - mean_delay) ** 2).sum()))
        rms_ok = abs(rms - 7410) <= 200
    return {"has_24_clusters": len(df) == 24, "rms_delay_close_to_contract": rms_ok}


def _constraint_parameter_binding(df: pd.DataFrame) -> ConstraintResult:
    populated = None
    if "Populated" in df.columns:
        populated = int(_bool_series(df["Populated"]).sum()) >= 200
    return {"populated_rows_200plus": populated}


def _constraint_mimo_effective(df: pd.DataFrame) -> ConstraintResult:
    exact = None
    if "ExactMatchPercent" in df.columns:
        exact = (_num(df["ExactMatchPercent"]).dropna() >= 99.0).all()
    return {
        "exact_match_percent_99plus": exact,
        "scenario_objective_pass": _all_true(df, "ScenarioObjectivePass"),
    }


def _constraint_mimo_runtime(df: pd.DataFrame) -> ConstraintResult:
    return {"runtime_trial_count_positive": _has(df, "RuntimeTrialCount") and (_num(df["RuntimeTrialCount"]) > 0).all()}


def _constraint_scheduler_summary(df: pd.DataFrame) -> ConstraintResult:
    balanced = None
    if "ScheduledFrac" in df.columns and len(df) >= 2:
        s = _num(df["ScheduledFrac"]).dropna()
        balanced = len(s) >= 2 and abs(float(s.max()) - float(s.min())) < 0.30
    return {"scheduler_balance_delta_lt_0p30": balanced}


def _constraint_runtime_call_graph(df: pd.DataFrame) -> ConstraintResult:
    return {"minimum_rows": len(df) >= 10}


CSV_MANIFEST: tuple[CsvSpec, ...] = (
    CsvSpec("air_interface/csv/dl_pdsch_trials.csv", "T1", (
        "Frame", "Slot", "AbsoluteSlot", "UEIndex", "RNTI", "MCS", "Modulation", "CodeRate",
        "Layers", "PRBStart", "PRBCount", "TBSBits", "GoodBits", "CRCPass", "RawBER",
        "PostEqSINR_dB", "NMSE_dB", "ConditionNumber_dB", "MeasuredLDPCDecoderMeanIterations",
        "NoiseVar", "SNR_dB", "OuterLoopApplied", "OLLADeltaMCS", "HARQ_ID", "RV",
        "HARQRound", "NDI", "UsedOracleFields", "NoiseVarSource", "ChannelEstMethod",
        "StrictOk", "IsWarmupFrame", "Goodput_Mbps", "OfferedThroughput_Mbps",
    ), 200, "Raw DL PDSCH trial evidence", constraints=_constraint_raw_dl, primary=True, row_filter=_non_warmup),
    CsvSpec("air_interface/csv/ul_pusch_trials.csv", "T1", (
        "Frame", "Slot", "AbsoluteSlot", "UEIndex", "RNTI", "MCS", "Modulation", "CodeRate",
        "Layers", "PRBStart", "PRBCount", "TBSBits", "GoodBits", "CRCPass", "RawBER",
        "PostEqSINR_dB", "NMSE_dB", "DataRECount", "Qm", "MeasuredRateMatchedBits",
        "ComputedE_TS38212", "NoiseVar", "SNR_dB", "HARQ_ID", "RV", "NDI", "SlotType",
        "UsedOracleFields", "StrictOk", "IsWarmupFrame", "Goodput_Mbps",
    ), 20, "Raw UL PUSCH trial evidence", constraints=_constraint_raw_ul, primary=True),
    CsvSpec("control/csv/pdcch_trials.csv", "T1", (
        "AbsoluteSlot", "Frame", "Slot", "RNTI", "DCIFormat", "AggregationLevel",
        "CandidateIndex", "CRCPass", "PostEqSINR_dB", "NoiseVariance", "DetectionMetric",
        "Detected", "MissedDetection", "FalseAlarm", "UsedOracleFields", "StrictOk",
    ), 61, "PDCCH trial evidence", constraints=_constraint_pdcch, primary=True),
    CsvSpec("control/csv/pucch_trials.csv", "T1", (
        "Frame", "Slot", "UEIndex", "Format", "NumBits", "CRCApplicable", "CRCPass",
        "DetectionMetric", "DetectionThreshold", "Detected", "PostEqSINR_dB",
        "NoiseVariance", "UCIBit_0", "UCIBit_1", "FalseAlarm", "MissedDetection",
        "UsedOracleFields", "StrictOk",
    ), 1, "PUCCH trial evidence", constraints=_constraint_pucch, primary=True),
    CsvSpec("air_interface/csv/srs_trials.csv", "T1", (
        "Frame", "Slot", "UEIndex", "RNTI", "N_SRS_Pilots", "CombSpacing", "NMSE_dB",
        "NMSE_LS_dB", "PilotSNR_dB", "EstimationMethod", "RankEstimate", "WidebandCQI",
        "UsedOracleFields", "StrictOk",
    ), 1, "SRS trial evidence", constraints=_constraint_srs, primary=True),
    CsvSpec("air_interface/csv/trs_trials.csv", "T1", (
        "Frame", "Slot", "AbsoluteSlot", "UEIndex", "EstimatedDopplerHz",
        "TheoreticalDoppler_Hz", "EstimationError_Hz", "DeltaPhi_rad", "DeltaT_s",
        "TrackingState", "StrictOk", "UsedOracleFields",
    ), 1, "TRS trial evidence", constraints=_constraint_trs, primary=True),
    CsvSpec("air_interface/csv/prach_trials.csv", "T1", (
        "Frame", "Slot", "UEIndex", "PreambleIndex", "TimingOffset_samples",
        "TimingAdvance_us", "DetectionMetric", "DetectionThreshold", "Detected",
        "UsedOracleFields", "StrictOk",
    ), 2, "PRACH trial evidence", constraints=_constraint_prach, primary=True),
    CsvSpec("control/csv/sib1_conformance_summary.csv", "T2", (
        "SSBIndex", "BeamIndex", "pdcchConfigSIB1", "CORESET0_NumRB", "CORESET0_NumSym",
        "SearchSpace0_SlotOffset", "DCI_Found", "DCI_RNTI", "MCSIndex", "PRBCount",
        "TBSBits", "CRCPass", "NoiseVariance", "UsedOracleFields", "StrictOk", "FailureReason",
    ), 2, "Strict SIB1 conformance summary", constraints=_constraint_strict_ok_no_oracle),
    CsvSpec("control/csv/prach_config_strict.csv", "T2", (
        "Format", "N_ZC", "RootSequenceIndex", "ZeroCorrelationZone", "RestrictedSetConfig",
        "PRACH_SCS_kHz", "ZC_UnitMagnitudeCheck", "CyclicShiftSpacing_N_cs",
        "MaxNumPreambles", "DetectionThreshold_eta", "ExpectedPfa", "Standard_Reference",
        "RuntimeTrialCount", "OracleFieldRows", "StrictOk", "FailureReason",
    ), 1, "Strict PRACH config evidence", constraints=_constraint_strict_ok_no_oracle),
    CsvSpec("control/csv/ra_attempts.csv", "T2", (
        "UEIndex", "RNTI", "PreambleIndex", "TimingAdvance_us", "TC_RNTI", "C_RNTI",
        "MSG1_Detected", "MSG2_Decoded", "MSG3_Decoded", "MSG4_Decoded",
        "ConResMatch", "RACHSuccess", "UsedOracleFields", "StrictOk",
    ), 2, "Four-step RA attempts", constraints=_constraint_strict_ok_no_oracle),
    CsvSpec("control/csv/msg2_rar_trials.csv", "T2", (
        "UEIndex", "RA_RNTI", "TC_RNTI", "TimingAdvance_us", "CRCPass", "PreambleEcho",
        "UsedOracleFields", "StrictOk",
    ), 1, "Msg2 RAR trials", constraints=_constraint_strict_ok_no_oracle),
    CsvSpec("control/csv/msg3_pusch_trials.csv", "T2", (
        "UEIndex", "TC_RNTI", "CRCPass", "UE_Identity_Bits", "PRBCount", "TBSBits",
        "UsedOracleFields", "StrictOk",
    ), 1, "Msg3 PUSCH trials", constraints=_constraint_strict_ok_no_oracle),
    CsvSpec("control/csv/msg4_trials.csv", "T2", (
        "UEIndex", "C_RNTI", "CRCPass", "ConResolutionMatch", "UE_IdentityEcho",
        "RACHSuccess", "UsedOracleFields", "StrictOk",
    ), 1, "Msg4 contention-resolution trials", constraints=_constraint_strict_ok_no_oracle),
    CsvSpec("control/csv/srs_config_strict.csv", "T2", (
        "SequenceType", "SequenceID", "CombNumber", "NumSRSSubcarriers", "NumSRSSymbols",
        "CyclicShift", "EstimationMethod", "ZC_UnitMagnitudeCheck", "Standard_Reference",
        "RuntimeTrialCount", "RuntimeMeanNMSE_dB", "RuntimeMaxNMSE_dB", "NMSEWorstCasePass",
        "OracleFieldRows", "StrictOk", "FailureReason",
    ), 1, "Strict SRS config evidence", constraints=_constraint_strict_ok_no_oracle),
    CsvSpec("control/csv/trs_config_strict.csv", "T2", (
        "CombSpacing", "SymbolLocations", "SlotsPerTRSBurst", "TRS_SCS_kHz",
        "InterSlotDelta_us", "TheoreticalDoppler_Hz", "MaxUnambiguousDoppler_Hz",
        "UnambiguousRangeOk", "SignCheckPass", "SignCheckInput_Hz", "SignCheckOutput_Hz",
        "Standard_Reference", "RuntimeTrialCount", "RuntimeMeanEstimate_Hz",
        "RuntimeEstimateSignOk", "OracleFieldRows", "StrictOk", "FailureReason",
    ), 1, "Strict TRS config evidence", constraints=_constraint_strict_ok_no_oracle),
    CsvSpec("air_interface/csv/lls_measured_sinr_summary.csv", "T3", (
        "Direction", "UEIndex", "N_Trials", "SINR_p5_dB", "SINR_median_dB",
        "SINR_p95_dB", "BLER_overall", "BER_overall", "Goodput_Mbps_mean",
        "SpectralEfficiency_mean_bps_Hz", "KPIFormulaVersion", "SourceArtifact",
    ), 2, "Measured SINR summary and BLER/throughput evidence", constraints=_constraint_measured_sinr_summary),
    CsvSpec("air_interface/csv/dl_measured_sinr_bler_curve.csv", "T3", (
        "Direction", "UEIndex", "PostEqSINR_dB_BinCenter", "BLER",
        "BLER_CI_Low", "BLER_CI_High", "BER", "TrialCount", "FailureCount",
        "SourceArtifact",
    ), 1, "DL BLER/BER vs measured post-EQ SINR"),
    CsvSpec("air_interface/csv/ul_measured_sinr_bler_curve.csv", "T3", (
        "Direction", "UEIndex", "PostEqSINR_dB_BinCenter", "BLER",
        "BLER_CI_Low", "BLER_CI_High", "BER", "TrialCount", "FailureCount",
        "SourceArtifact",
    ), 1, "UL BLER/BER vs measured post-EQ SINR"),
    CsvSpec("air_interface/csv/dl_measured_sinr_throughput_curve.csv", "T3", (
        "Direction", "UEIndex", "PostEqSINR_dB_BinCenter", "Goodput_Mbps_mean",
        "OfferedThroughput_Mbps_mean", "SpectralEfficiency_bps_Hz_mean",
        "TrialCount", "SourceArtifact",
    ), 1, "DL throughput vs measured post-EQ SINR"),
    CsvSpec("air_interface/csv/ul_measured_sinr_throughput_curve.csv", "T3", (
        "Direction", "UEIndex", "PostEqSINR_dB_BinCenter", "Goodput_Mbps_mean",
        "OfferedThroughput_Mbps_mean", "SpectralEfficiency_bps_Hz_mean",
        "TrialCount", "SourceArtifact",
    ), 1, "UL throughput vs measured post-EQ SINR"),
    CsvSpec("air_interface/csv/distance_vs_sinr.csv", "T3", (
        "Direction", "UEIndex", "TrialIndex", "PropagationDistance_m",
        "PostEqSINR_dB", "LargeScaleSINR_dB", "ReceiverHestSINR_dB",
        "MCS", "Modulation", "Rank", "CRCPass", "Goodput_Mbps",
    ), 1, "Propagation distance vs measured SINR evidence"),
    CsvSpec("reports/csv/nmse_vs_measured_sinr.csv", "T3", (
        "Direction", "PostEqSINR_dB", "MetricName", "MetricValue", "SampleCount",
        "EvidenceClass", "SourceArtifact",
    ), 1, "NMSE-vs-measured-SINR analysis"),
    CsvSpec("reports/csv/energy_vs_throughput.csv", "T3", (
        "Direction", "PostEqSINR_dB", "goodput_mbps", "energy_per_bit_j",
        "Goodput_Mbps", "EnergyPerBit_J", "successful_bits",
    ), 1, "Energy-throughput analysis"),
    CsvSpec("reports/csv/tbs_reference_comparison.csv", "T3", (
        "UEIndex", "Direction", "Slot", "MCS", "PRBCount", "Layers", "Modulation",
        "DUT_TBSize_bits", "Reference_nrTBS_bits", "Delta_bits", "Pass", "BaseGraph",
    ), 1, "DUT-vs-reference TBS comparison"),
    CsvSpec("reports/csv/shannon_capacity_gap.csv", "T3", (
        "Direction", "PostEqSINR_dB", "Layers", "ShannonCapacity_Mbps",
        "AchievedGoodput_Mbps", "Gap_Mbps",
    ), 1, "Shannon capacity gap analysis"),
    CsvSpec("reports/csv/trs_doppler_error_trace.csv", "T3", (
        "AbsoluteSlot", "Frame", "Slot", "UEIndex", "InjectedDoppler_Hz",
        "EstimatedDoppler_Hz", "DopplerError_Hz", "TrackingState", "StrictOk",
    ), 1, "TRS Doppler error trace"),
    CsvSpec("air_interface/csv/lls_kpi_summary.csv", "T4", (
        "RunId", "Direction", "UEIndex", "KPIFormulaVersion", "KPIReconciliationPass",
        "SINR_median_dB", "SINR_p5_dB", "SINR_p95_dB", "BLER_overall", "BER_overall",
        "Goodput_Mbps", "OfferedThroughput_Mbps", "SpectralEfficiency_bps_Hz",
        "RadioDuration_s", "TrialCount", "StrictOk", "Status", "FailureReason",
    ), 1, "KPI summary", constraints=_constraint_kpi_summary),
    CsvSpec("reports/csv/kpi_lineage_table.csv", "T4", (
        "Direction", "KPI_BLER", "BLER_Source", "KPI_Goodput_Mbps", "Goodput_Source",
        "T_radio_ms", "T_radio_Source", "RadioDurationOk",
    ), 1, "KPI lineage table"),
    CsvSpec("air_interface/csv/fer_summary.csv", "T4", (
        "Scope", "Direction", "UEIndex", "N_TB", "N_CRC_Fail", "FER", "FER_CI95_Low",
        "FER_CI95_High", "PostEqSINR_dB", "MCS_Mode", "ScenarioID",
    ), 1, "FER summary", constraints=_constraint_fer),
    CsvSpec("air_interface/csv/harq_combining_gain.csv", "T4", (
        "CombiningGain_dB", "BLER_RV0", "BLER_RV0_plus1", "BLER_RV0_plus2",
        "BLER_RV0_plus3", "N_per_round_0", "N_per_round_1", "Exercised",
    ), 1, "HARQ IR combining gain"),
    CsvSpec("reports/csv/mobility_adequacy_report.csv", "T4", (
        "UESpeed_kmh", "MaxDoppler_Hz", "CoherenceTime_ms", "TotalSlots", "RunDuration_ms",
        "UETravel_m", "NumCoherenceIntervals", "NumDLTrials_perUE", "DL_BLER",
        "DL_BLER_CI95_Width", "DL_Throughput_CV", "CoherenceOk", "TrialCountOk",
        "BLERCIOk", "ThroughputCVOk", "MobilityAdequate", "HonestLabel",
    ), 1, "Mobility adequacy report"),
    CsvSpec("reports/csv/channel_rf_configured_applied.csv", "T5", (
        "UEIndex", "Direction", "Frame", "Slot", "TrialIndex", "Cfg_ChannelModel",
        "Cfg_Velocity_kmh", "Cfg_CarrierFreq_Hz", "Cfg_DopplerHz", "App_ChannelModel",
        "App_Velocity_kmh", "App_PathLoss_dB", "App_ShadowFading_dB", "App_DopplerHz",
        "App_ChannelFadingApplied", "Ref_FreeSpacePathLoss_dB", "Match_ChannelModel",
        "Match_Velocity", "Match_DopplerHz", "Match_FadingApplied",
        "ConfiguredAppliedOk", "FailureReason",
    ), 1, "Configured-vs-applied channel/RF", constraints=_constraint_channel_configured),
    CsvSpec("reports/csv/channel_rf_cdlc_realization_table.csv", "T5", (
        "ClusterIndex", "Delay_ns", "RelativePower_dB", "LinearPower", "AoD_deg",
        "AoA_deg", "ZoD_deg", "ZoA_deg", "ChannelModel", "Standard", "Seed",
        "CarrierFreq_Hz", "UESpeed_kmh", "MaxDoppler_Hz",
    ), 24, "CDL-C realization table", constraints=_constraint_cdlc),
    CsvSpec("reports/csv/channel_rf_per_ue_realization.csv", "T5", (
        "UEIndex", "RNTI", "Seed", "PropagationDist_m", "AppliedPathLoss_dB",
        "ShadowFading_dB", "InjectedDoppler_Hz", "FreeSpacePathLoss_dB", "ChannelModel",
        "DopplerHz_Ref", "DopplerHz_Applied", "DopplerConsistent",
    ), 1, "Per-UE channel/RF realization"),
    CsvSpec("reports/csv/channel_rf_strict_summary.csv", "T5", (
        "ChannelModel", "CDL_TableRef", "NumClusters", "RMSDelaySpread_ns",
        "ConfiguredAppliedRows", "ConfiguredAppliedOkRows", "ConfiguredAppliedFrac",
        "RealizationTableWritten", "StrictOk", "FailureReason",
    ), 1, "Channel/RF strict summary"),
    CsvSpec("reports/csv/parameter_binding_matrix.csv", "T5", (
        "ParameterName", "ConfiguredValue", "RuntimeMeasuredEvidenceValue",
        "EvidenceSource", "EvidenceColumn", "AppliedValue", "Note", "Discrepancy",
        "Populated",
    ), 1, "Parameter binding matrix", constraints=_constraint_parameter_binding),
    CsvSpec("beamforming/csv/mimo_configured_vs_effective.csv", "T6", (
        "Direction", "ConfiguredRank", "DominantScheduledRank", "DominantTransmittedRank",
        "DominantEffectiveDecodedRank", "StrictEligibleRowCount", "ExactMatchRowCount",
        "ExactMatchPercent", "RequiredExactMatchPct", "ScenarioObjectivePass", "Status",
    ), 1, "Configured-vs-effective MIMO", constraints=_constraint_mimo_effective),
    CsvSpec("beamforming/csv/mimo_config_strict.csv", "T6", (
        "NominalRank", "MaxSupportedRank", "CodebookType", "N1", "N2", "N_ports",
        "ConditionThresh_dB", "RuntimeTrialCount", "RuntimeRank2Fraction",
        "RuntimeExactMatchFrac", "RuntimeMeanCondNum_dB", "StrictOk",
    ), 1, "Strict MIMO config evidence", constraints=_constraint_mimo_runtime),
    CsvSpec("beamforming/csv/mimo_config_validation.csv", "T6", (
        "NominalRank", "EffectiveRank", "ExactMatch", "Reason", "CondNum_dB",
        "PMI_i1_l1", "PMI_i1_l2", "PMI_i2", "Rate_rank1", "Rate_rank2",
    ), 1, "Per-trial MIMO validation"),
    CsvSpec("beamforming/csv/antenna_array_config.csv", "T6", (
        "N1", "N2", "N_total_ports", "N_rx_UE", "N_tx_gNB", "ArrayType",
        "AntennaSpacing_lambda", "CarrierFreq_Hz", "Runtime_populated",
    ), 1, "Antenna array config evidence", constraints=lambda df: {"runtime_populated": _all_true(df, "Runtime_populated")}),
    CsvSpec("packet_flow/csv/scheduler_decision_log.csv", "T7", (
        "AbsoluteSlot", "Frame", "Slot", "UEIndex", "PF_Rank", "PF_Metric",
        "PF_Metric_rank1", "Inst_Rate_bps", "Avg_Rate_bps", "SINR_dB", "CQI",
        "BLER_est", "HARQ_ProcID", "HARQ_Blocked", "Scheduled", "RejectionReason",
        "PRBCount", "MCSIndex", "TBS", "HARQ_ID",
    ), 1, "Scheduler decision log"),
    CsvSpec("packet_flow/csv/scheduler_ue_summary.csv", "T7", (
        "UEIndex", "TotalSlots", "ScheduledSlots", "RejectedSlots", "ScheduledFrac",
        "MeanPF_Metric", "MeanInstRate_Mbps", "MeanAvgRate_Mbps", "MeanSINR_dB",
        "Rejected_HARQ_ALL_PROCESSES_BUSY", "Rejected_NO_PRB_REMAINING",
        "Rejected_CQI_ZERO_UNREACHABLE",
    ), 1, "Scheduler UE balance summary", constraints=_constraint_scheduler_summary),
    CsvSpec("air_interface/csv/ul_scheduling_coverage.csv", "T7", (
        "AbsoluteSlot", "UEIndex", "GrantType", "Status", "PRBCount", "MCSIndex", "TBS",
    ), 1, "UL scheduling coverage"),
    CsvSpec("reports/csv/runtime_call_graph.csv", "T7", (
        "FunctionName", "TotalTime_s", "NumCalls", "SelfTime",
    ), 10, "Runtime call graph", constraints=_constraint_runtime_call_graph),
)


IMAGE_MANIFEST: tuple[ImageSpec, ...] = (
    ImageSpec("reports/image/bler_vs_measured_sinr.png", "I1", "air_interface/csv/dl_measured_sinr_bler_curve.csv", "BLER vs measured SINR PNG", unavailable_stems=("bler_vs_measured_sinr",)),
    ImageSpec("reports/image/ber_vs_measured_sinr.png", "I1", "air_interface/csv/dl_measured_sinr_bler_curve.csv", "BER vs measured SINR PNG", unavailable_stems=("ber_vs_measured_sinr",)),
    ImageSpec("reports/image/throughput_vs_measured_sinr.png", "I1", "air_interface/csv/dl_measured_sinr_throughput_curve.csv", "Throughput vs measured SINR PNG", unavailable_stems=("throughput_vs_measured_sinr",)),
    ImageSpec("reports/image/measured_sinr_distribution.png", "I1", "air_interface/csv/measured_sinr_distribution.csv", "Measured SINR distribution PNG", unavailable_stems=("measured_sinr_distribution",)),
    ImageSpec("reports/image/distance_vs_sinr.png", "I1", "air_interface/csv/distance_vs_sinr.csv", "Distance vs measured SINR PNG", unavailable_stems=("distance_vs_sinr",)),
    ImageSpec("reports/image/nmse_vs_measured_sinr.png", "I1", "reports/csv/nmse_vs_measured_sinr.csv", "NMSE vs measured SINR PNG"),
    ImageSpec("reports/html/shannon_gap.html", "I1", "reports/csv/shannon_capacity_gap.csv", "Shannon gap"),
    ImageSpec("reports/html/pdcch_detection_vs_snr.html", "I2", "control/csv/pdcch_false_alarm_sweep.csv", "PDCCH detection vs SNR"),
    ImageSpec("reports/html/access_delay_cdf.html", "I2", "control/csv/initial_access_lifecycle_trace.csv", "Access delay CDF", unavailable_stems=("access_delay_cdf",)),
    ImageSpec("reports/image/access_delay_cdf.png", "I2", "control/csv/initial_access_lifecycle_trace.csv", "Access delay CDF PNG", unavailable_stems=("access_delay_cdf",)),
    ImageSpec("reports/html/trs_tracking_error.html", "I2", "reports/csv/trs_doppler_error_trace.csv", "TRS tracking error"),
    ImageSpec("reports/html/nvar_calibration.html", "I2", "air_interface/csv/dl_pdsch_trials.csv", "Noise variance calibration"),
    ImageSpec("reports/html/pucch_detection_vs_snr.html", "I2", "control/csv/pucch_false_alarm_trials.csv", "PUCCH detection vs SNR"),
    ImageSpec("reports/html/rank_distribution.html", "I3", "beamforming/csv/rank_layer_trials.csv", "Rank distribution"),
    ImageSpec("reports/html/ul_beam_accuracy.html", "I3", "air_interface/csv/ul_pusch_trials.csv", "UL beam accuracy"),
    ImageSpec("reports/html/mimo_condition_number.html", "I3", "beamforming/csv/mimo_config_validation.csv", "MIMO condition number"),
    ImageSpec("reports/html/precoder_gain.html", "I3", "air_interface/csv/dl_pdsch_trials.csv", "Precoder gain"),
    ImageSpec("reports/image/beam_channel_sinr.png", "I3", "beamforming/csv/beam_score_trace.csv", "Beam channel SINR"),
    ImageSpec("reports/image/beam_condition_number.png", "I3", "beamforming/csv/mimo_config_validation.csv", "Beam condition number"),
    ImageSpec("reports/image/beam_gain_gap.png", "I3", "beamforming/csv/beam_score_trace.csv", "Beam gain gap"),
    ImageSpec("reports/html/harq_combining_gain.html", "I4", "air_interface/csv/harq_combining_gain.csv", "HARQ combining gain"),
    ImageSpec("reports/html/harq_process_timeline.html", "I4", "harq/csv/harq_process_timeline.csv", "HARQ process timeline"),
    ImageSpec("reports/html/olla_convergence.html", "I4", "air_interface/csv/dl_pdsch_trials.csv", "OLLA convergence"),
    ImageSpec("reports/html/tbs_mismatch.html", "I5", "reports/csv/tbs_reference_comparison.csv", "TBS mismatch"),
    ImageSpec("reports/image/equalized_constellations.png", "I5", "air_interface/csv/dl_pdsch_trials.csv", "Equalized constellations"),
    ImageSpec("reports/image/llr_histograms.png", "I5", "air_interface/csv/dl_pdsch_trials.csv", "LLR histograms"),
    ImageSpec("reports/image/bler_vs_sinr.png", "I5", "air_interface/csv/dl_pdsch_trials.csv", "BLER vs SINR"),
    ImageSpec("reports/html/energy_vs_throughput.html", "I6", "reports/csv/energy_vs_throughput.csv", "Energy vs throughput"),
    ImageSpec("reports/image/papr_ccdf.png", "I6", "air_interface/csv/papr_ccdf.csv", "PAPR CCDF"),
    ImageSpec("reports/image/power_energy_cumulative.png", "I6", "reports/csv/energy_vs_throughput.csv", "Power/energy cumulative"),
    ImageSpec("reports/image/latency_cdf.png", "I6", "reports/csv/control_plane_timeline.csv", "Latency CDF"),
    ImageSpec("reports/html/scheduler_balance.html", "I6", "packet_flow/csv/scheduler_decision_log.csv", "Scheduler balance"),
    ImageSpec("reports/html/prb_allocation_heatmap.html", "I6", "reports/csv/prb_allocation_heatmap.csv", "PRB allocation heatmap"),
    ImageSpec("reports/image/heatmap_band_feature_kpi.png", "I7", "reports/csv/per_slot_kpi_table.csv", "Band/feature KPI heatmap"),
    ImageSpec("reports/image/heatmap_beam_rank_trp_kpi.png", "I7", "beamforming/csv/mimo_configured_vs_effective.csv", "Beam/rank/TRP heatmap"),
    ImageSpec("reports/image/heatmap_impairment_kpi.png", "I7", "reports/csv/physics_audit_table.csv", "Impairment KPI heatmap"),
    ImageSpec("reports/image/gains_losses_waterfall.png", "I7", "reports/csv/shannon_capacity_gap.csv", "Gains/losses waterfall"),
    ImageSpec("reports/image/metric_coverage_by_category.png", "I7", "reports/csv/output_coverage_registry.csv", "Metric coverage by category"),
    ImageSpec("reports/html/master_dashboard.html", "I7", "__all__", "Master dashboard"),
)


def read_csv(path: Path) -> pd.DataFrame:
    return pd.read_csv(path) if path.exists() else pd.DataFrame()


def check_csv_spec(run_dir: Path, spec: CsvSpec) -> dict[str, Any]:
    path = run_dir / spec.path
    row = {
        "artifact_type": "csv",
        "path": spec.path,
        "tier": spec.tier,
        "description": spec.description,
        "source_csv": spec.source,
        "exists": False,
        "row_count": 0,
        "effective_row_count": 0,
        "min_rows": spec.min_rows,
        "required_column_count": len(spec.required_columns),
        "missing_columns": "",
        "constraint_failures": "",
        "constraint_results_json": "{}",
        "status": "MISSING",
        "notes": "",
    }
    if not path.exists():
        return row
    row["exists"] = True
    try:
        df = pd.read_csv(path)
    except Exception as exc:
        row["status"] = "ERROR"
        row["notes"] = f"read_error:{type(exc).__name__}:{exc}"
        return row
    effective = spec.row_filter(df) if spec.row_filter else df
    missing = [col for col in spec.required_columns if col not in df.columns]
    constraints: ConstraintResult = spec.constraints(df) if spec.constraints else {}
    failures = [key for key, value in constraints.items() if value is False]
    row["row_count"] = int(len(df))
    row["effective_row_count"] = int(len(effective))
    row["missing_columns"] = "|".join(missing)
    row["constraint_failures"] = "|".join(failures)
    row["constraint_results_json"] = json.dumps(constraints, sort_keys=True, default=str)
    if missing:
        row["status"] = "FAIL_SCHEMA"
    elif len(effective) < spec.min_rows:
        row["status"] = "FAIL_ROWS"
    elif failures:
        row["status"] = "FAIL_CONSTRAINTS"
    else:
        row["status"] = "PASS"
    return row


def _unavailable_svg_present(run_dir: Path, spec: ImageSpec) -> bool:
    image_dir = run_dir / "reports" / "image"
    stems = spec.unavailable_stems or (Path(spec.path).stem,)
    return any((image_dir / f"{stem}_unavailable.svg").exists() for stem in stems)


def check_image_spec(run_dir: Path, spec: ImageSpec) -> dict[str, Any]:
    path = run_dir / spec.path
    source_exists = spec.source_csv == "__all__" or (run_dir / spec.source_csv).exists()
    exists = path.exists() and path.is_file()
    blocked_unavailable = _unavailable_svg_present(run_dir, spec)
    if exists:
        status = "PASS"
    elif not source_exists:
        status = "BLOCKED_SOURCE_MISSING"
    elif blocked_unavailable:
        status = "BLOCKED_UNAVAILABLE"
    else:
        status = "MISSING"
    return {
        "artifact_type": "image" if spec.path.endswith(".png") else "html",
        "path": spec.path,
        "tier": spec.tier,
        "description": spec.description,
        "source_csv": spec.source_csv,
        "exists": bool(exists),
        "row_count": "",
        "effective_row_count": "",
        "min_rows": "",
        "required_column_count": "",
        "missing_columns": "",
        "constraint_failures": "",
        "constraint_results_json": "{}",
        "status": status,
        "notes": "source missing" if not source_exists else "unavailable SVG present" if blocked_unavailable and not exists else "",
    }


def audit_rows(run_dir: Path) -> list[dict[str, Any]]:
    rows = [check_csv_spec(run_dir, spec) for spec in CSV_MANIFEST]
    rows.extend(check_image_spec(run_dir, spec) for spec in IMAGE_MANIFEST)
    return rows


def summarize(rows: list[Mapping[str, Any]]) -> dict[str, Any]:
    total = len(rows)
    passed = sum(1 for row in rows if row.get("status") == "PASS")
    by_status: dict[str, int] = {}
    by_tier: dict[str, dict[str, int]] = {}
    for row in rows:
        status = str(row.get("status", ""))
        tier = str(row.get("tier", ""))
        by_status[status] = by_status.get(status, 0) + 1
        by_tier.setdefault(tier, {})
        by_tier[tier][status] = by_tier[tier].get(status, 0) + 1
    tier1 = [row for row in rows if row.get("tier") == "T1"]
    tier2 = [row for row in rows if row.get("tier") == "T2"]
    image_rows = [row for row in rows if str(row.get("tier", "")).startswith("I")]
    return {
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "total_items": total,
        "pass_count": passed,
        "pass_fraction": passed / total if total else 0.0,
        "by_status": by_status,
        "by_tier": by_tier,
        "tier1_pass": all(row.get("status") == "PASS" for row in tier1) if tier1 else False,
        "tier2_pass_fraction": sum(row.get("status") == "PASS" for row in tier2) / len(tier2) if tier2 else 0.0,
        "image_pass_fraction": sum(row.get("status") == "PASS" for row in image_rows) / len(image_rows) if image_rows else 0.0,
        "no_blocked": not any(str(row.get("status", "")).startswith("BLOCKED") for row in rows),
    }


def write_audit_outputs(run_dir: Path, rows: list[dict[str, Any]]) -> dict[str, Any]:
    report_dir = run_dir / "reports" / "csv"
    report_dir.mkdir(parents=True, exist_ok=True)
    summary_dir = run_dir / "reports" / "json"
    summary_dir.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(report_dir / "manifest_audit_report.csv", index=False)
    summary = summarize(rows)
    (summary_dir / "manifest_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def run_manifest_audit(run_dir: Path) -> dict[str, Any]:
    rows = audit_rows(run_dir)
    summary = write_audit_outputs(run_dir, rows)
    return {"rows": rows, "summary": summary}


def final_manifest_acceptance_gate(run_dir: Path) -> dict[str, Any]:
    report = run_dir / "reports" / "csv" / "manifest_audit_report.csv"
    if not report.exists():
        result = run_manifest_audit(run_dir)
        rows = result["rows"]
    else:
        rows = pd.read_csv(report).to_dict("records")
    summary = summarize(rows)
    ok = bool(
        summary["tier1_pass"]
        and summary["tier2_pass_fraction"] >= 0.90
        and summary["image_pass_fraction"] >= 0.85
        and summary["no_blocked"]
    )
    summary["ok"] = ok
    summary["grade_estimate"] = round(summary["pass_fraction"] * 10, 2)
    return summary
