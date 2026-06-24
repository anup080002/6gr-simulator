#!/usr/bin/env python3
"""Generate missing LLS manifest CSVs from completed-run evidence only.

This script derives secondary analysis tables from existing runtime CSVs. It
does not synthesize primary trial evidence, strict conformance evidence, grant
TBS values, channel realizations, or standards reference values. When the
needed source evidence is absent, the artifact is left untouched and the reason
is recorded in reports/csv/manifest_generation_log.csv.
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import sys
from pathlib import Path
from typing import Any, Iterable

import numpy as np
import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from lls_manifest_contract import CSV_MANIFEST, CsvSpec, check_csv_spec  # noqa: E402


PASS_TOKENS = {"1", "true", "pass", "ok", "success", "decoded", "detected"}
FAIL_TOKENS = {"0", "false", "fail", "failed", "nack", "missed"}
REAL_EVIDENCE = "real_lls_evidence"


def _clean_name(name: str) -> str:
    return name.lower().replace("_", "").replace("-", "")


def _col(df: pd.DataFrame, names: str | Iterable[str]) -> str | None:
    if isinstance(names, str):
        names = [names]
    lookup = {_clean_name(c): c for c in df.columns}
    for name in names:
        found = lookup.get(_clean_name(name))
        if found is not None:
            return found
    return None


def _series(df: pd.DataFrame, names: str | Iterable[str], default: Any = np.nan) -> pd.Series:
    name = _col(df, names)
    if name is None:
        return pd.Series([default] * len(df), index=df.index)
    return df[name]


def _num(df: pd.DataFrame, names: str | Iterable[str], default: Any = np.nan) -> pd.Series:
    return pd.to_numeric(_series(df, names, default), errors="coerce")


def _text(df: pd.DataFrame, names: str | Iterable[str], default: str = "") -> pd.Series:
    return _series(df, names, default).fillna(default).astype(str)


def _boolish(values: pd.Series) -> pd.Series:
    if values.empty:
        return pd.Series(dtype=bool)
    if pd.api.types.is_bool_dtype(values):
        return values.fillna(False)
    if pd.api.types.is_numeric_dtype(values):
        return pd.to_numeric(values, errors="coerce").fillna(0).astype(float) != 0
    return values.astype(str).str.strip().str.lower().isin(PASS_TOKENS)


def _fail_count(df: pd.DataFrame) -> int:
    c = _col(df, "CRCPass")
    if c is None:
        return 0
    values = df[c]
    if pd.api.types.is_bool_dtype(values):
        return int((~values.fillna(False)).sum())
    if pd.api.types.is_numeric_dtype(values):
        return int((pd.to_numeric(values, errors="coerce").fillna(0) == 0).sum())
    s = values.astype(str).str.strip().str.lower()
    return int(s.isin(FAIL_TOKENS).sum())


def _pass_count(df: pd.DataFrame) -> int:
    c = _col(df, "CRCPass")
    if c is None:
        return 0
    return int(_boolish(df[c]).sum())


def _safe_div(numer: float, denom: float) -> float:
    if not math.isfinite(numer) or not math.isfinite(denom) or denom == 0:
        return math.nan
    return numer / denom


def _mean_finite(values: pd.Series) -> float:
    finite = pd.to_numeric(values, errors="coerce").dropna()
    return float(finite.mean()) if len(finite) else math.nan


def _first_text(values: pd.Series) -> str:
    for value in values:
        if value is None:
            continue
        if isinstance(value, float) and math.isnan(value):
            continue
        text = str(value).strip()
        if text:
            return text
    return ""


def _mode_text(values: pd.Series) -> str:
    s = values.fillna("").astype(str).str.strip()
    s = s[s != ""]
    if s.empty:
        return ""
    return str(s.mode(dropna=True).iloc[0])


def _wilson_ci(fails: float, total: float) -> tuple[float, float]:
    if not math.isfinite(total) or total <= 0:
        return math.nan, math.nan
    z = 1.96
    p = _safe_div(fails, total)
    denom = 1 + z * z / total
    center = (p + z * z / (2 * total)) / denom
    half = z * math.sqrt((p * (1 - p) / total) + (z * z / (4 * total * total))) / denom
    return max(0.0, center - half), min(1.0, center + half)


def _dbm_to_mw(dbm: pd.Series) -> pd.Series:
    x = pd.to_numeric(dbm, errors="coerce")
    return 10 ** (x / 10.0)


class CsvGenerator:
    def __init__(self, run_dir: Path, overwrite: bool = False):
        self.run_dir = run_dir
        self.overwrite = overwrite
        self.log_rows: list[dict[str, Any]] = []

    def rel(self, path: str) -> Path:
        return self.run_dir / path

    def read(self, path: str) -> pd.DataFrame:
        full = self.rel(path)
        if not full.exists():
            return pd.DataFrame()
        try:
            return pd.read_csv(full)
        except Exception:
            return pd.DataFrame()

    def log(self, artifact: str, action: str, status: str, sources: Iterable[str], row_count: int = 0, notes: str = "") -> None:
        self.log_rows.append(
            {
                "artifact": artifact,
                "action": action,
                "status": status,
                "source_artifacts": "|".join(str(s) for s in sources if str(s)),
                "row_count": int(row_count) if row_count is not None else 0,
                "notes": notes,
            }
        )

    def write(self, path: str, df: pd.DataFrame, action: str, sources: Iterable[str], notes: str = "") -> None:
        full = self.rel(path)
        full.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(full, index=False)
        self.log(path, action, "GENERATED", sources, len(df), notes)

    def needs_write(self, spec: CsvSpec | str) -> bool:
        if isinstance(spec, str):
            full = self.rel(spec)
            return self.overwrite or not full.exists()
        if self.overwrite:
            return True
        status = check_csv_spec(self.run_dir, spec)["status"]
        return status in {"MISSING", "FAIL_SCHEMA", "ERROR"}

    def spec_for(self, path: str) -> CsvSpec | None:
        return next((spec for spec in CSV_MANIFEST if spec.path == path), None)

    def target_needs(self, path: str) -> bool:
        spec = self.spec_for(path)
        return self.needs_write(spec) if spec else self.needs_write(path)

    def write_log(self) -> None:
        out = self.rel("reports/csv/manifest_generation_log.csv")
        out.parent.mkdir(parents=True, exist_ok=True)
        pd.DataFrame(
            self.log_rows,
            columns=["artifact", "action", "status", "source_artifacts", "row_count", "notes"],
        ).to_csv(out, index=False)

    def raw_table(self, direction: str) -> tuple[pd.DataFrame, str]:
        if direction.upper() == "DL":
            return self.read("air_interface/csv/dl_pdsch_trials.csv"), "air_interface/csv/dl_pdsch_trials.csv"
        return self.read("air_interface/csv/ul_pusch_trials.csv"), "air_interface/csv/ul_pusch_trials.csv"

    def copy_same_name_sources(self) -> None:
        for spec in CSV_MANIFEST:
            if not self.needs_write(spec):
                continue
            target = self.rel(spec.path)
            candidates = [
                p
                for p in self.run_dir.rglob(target.name)
                if p != target
                and "manifest_" not in p.name
                and p.is_file()
                and p.suffix.lower() == ".csv"
            ]
            for candidate in candidates:
                try:
                    df = pd.read_csv(candidate)
                except Exception:
                    continue
                if all(col in df.columns for col in spec.required_columns) and len(df) >= min(spec.min_rows, 1):
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(candidate, target)
                    self.log(
                        spec.path,
                        "copy_existing_equivalent_artifact",
                        "GENERATED",
                        [str(candidate.relative_to(self.run_dir))],
                        len(df),
                        "copied only because schema already satisfied at alternate runtime location",
                    )
                    break

    def derive_snr_sweep(self) -> None:
        target = "air_interface/csv/lls_snr_sweep.csv"
        if not self.target_needs(target):
            self.log(target, "derive_snr_sweep", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        rows: list[dict[str, Any]] = []
        sources: list[str] = []
        for direction in ("DL", "UL"):
            df, source = self.raw_table(direction)
            if df.empty or _col(df, "CRCPass") is None:
                continue
            snr = _num(df, ["SNR_dB", "ConfiguredSNR_dB", "AppliedAWGNSNR_dB", "PilotSNR_dB"])
            if snr.dropna().empty:
                continue
            sources.append(source)
            work = df.copy()
            work["_snr"] = snr
            for snr_value, sub in work.dropna(subset=["_snr"]).groupby("_snr", dropna=True):
                n_tb = int(len(sub))
                n_fail = _fail_count(sub)
                ci_low, ci_high = _wilson_ci(n_fail, n_tb)
                tbs = _num(sub, ["TBSBits", "TBSize_bits", "TBS"])
                bit_errors = _num(sub, ["BitErrors", "NBitErrors", "n_bit_errors"])
                if bit_errors.dropna().empty:
                    bit_errors = _num(sub, "RawBER") * tbs
                rows.append(
                    {
                        "direction": direction,
                        "snr_db": float(snr_value),
                        "noise_variance": _mean_finite(_num(sub, ["NoiseVar", "NoiseVariance"])),
                        "n_tb": n_tb,
                        "n_crc_fail": n_fail,
                        "bler": _safe_div(n_fail, n_tb),
                        "bler_ci_low": ci_low,
                        "bler_ci_high": ci_high,
                        "n_bits": float(tbs.dropna().sum()) if not tbs.dropna().empty else math.nan,
                        "n_bit_errors": float(bit_errors.dropna().sum()) if not bit_errors.dropna().empty else math.nan,
                        "ber": _mean_finite(_num(sub, ["RawBER", "BER"])),
                        "throughput_mbps": _mean_finite(_num(sub, ["OfferedThroughput_Mbps", "Throughput_Mbps"])),
                        "goodput_mbps": _mean_finite(_num(sub, "Goodput_Mbps")),
                        "mcs_index": _mean_finite(_num(sub, ["MCS", "MCSIndex"])),
                        "n_layers": _mean_finite(_num(sub, ["Layers", "Rank"])),
                        "channel_model": _mode_text(_text(sub, ["ChannelModel", "Cfg_ChannelModel", "App_ChannelModel"])),
                        "seed": _first_text(_series(sub, ["Seed", "RandomSeed"], "")),
                        "truth_status": REAL_EVIDENCE,
                    }
                )
        if rows:
            self.write(target, pd.DataFrame(rows), "derive_snr_sweep", sources)
            return
        self.log(target, "derive_snr_sweep", "BLOCKED_SOURCE_MISSING", sources, 0, "requires DL/UL raw trials with CRCPass and SNR")

    def derive_nmse_vs_snr(self) -> None:
        target = "reports/csv/nmse_vs_snr.csv"
        if not self.target_needs(target):
            self.log(target, "derive_nmse_vs_snr", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        rows: list[dict[str, Any]] = []
        sources = [
            ("air_interface/csv/srs_trials.csv", "SRS"),
            ("air_interface/csv/dl_pdsch_trials.csv", "DL"),
            ("air_interface/csv/ul_pusch_trials.csv", "UL"),
        ]
        used: list[str] = []
        for source, method in sources:
            df = self.read(source)
            if df.empty or _col(df, "NMSE_dB") is None:
                continue
            snr = _num(df, ["SNR_dB", "PilotSNR_dB", "ConfiguredSNR_dB", "AppliedAWGNSNR_dB"])
            if snr.dropna().empty:
                continue
            used.append(source)
            work = df.copy()
            work["_snr"] = snr
            work["_ue"] = _series(df, "UEIndex", 0)
            work["_est"] = _text(df, "EstimationMethod", method)
            for (ue, snr_value, est), sub in work.dropna(subset=["_snr"]).groupby(["_ue", "_snr", "_est"], dropna=False):
                values = _num(sub, "NMSE_dB").dropna()
                if values.empty:
                    continue
                rows.append(
                    {
                        "UEIndex": ue,
                        "snr_db": float(snr_value),
                        "NMSE_dB_mean": float(values.mean()),
                        "NMSE_dB_min": float(values.min()),
                        "NMSE_dB_max": float(values.max()),
                        "N_trials": int(len(values)),
                        "Method": method,
                        "EstimationMethod": est,
                    }
                )
        if rows:
            self.write(target, pd.DataFrame(rows), "derive_nmse_vs_snr", used)
        else:
            self.log(target, "derive_nmse_vs_snr", "BLOCKED_SOURCE_MISSING", [s for s, _ in sources], 0, "requires NMSE_dB and SNR/PilotSNR")

    def derive_energy_vs_throughput(self) -> None:
        target = "reports/csv/energy_vs_throughput.csv"
        if not self.target_needs(target):
            self.log(target, "derive_energy_vs_throughput", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        rows: list[dict[str, Any]] = []
        used: list[str] = []
        for direction in ("DL", "UL"):
            df, source = self.raw_table(direction)
            if df.empty:
                continue
            power_mw = _num(df, ["Power_mW", "power_mW", "AppliedPower_mW", "TxPower_mW"])
            if power_mw.dropna().empty:
                tx_dbm = _num(df, ["TxPower_dBm", "PreambleTxPower_dBm", "Msg3TxPower_dBm"])
                power_mw = _dbm_to_mw(tx_dbm)
            if power_mw.dropna().empty:
                continue
            snr = _num(df, ["SNR_dB", "ConfiguredSNR_dB", "AppliedAWGNSNR_dB"])
            work = df.copy()
            work["_snr"] = snr
            work["_ue"] = _series(df, "UEIndex", 0)
            work["_power_mw"] = power_mw
            used.append(source)
            for (ue, snr_value), sub in work.groupby(["_ue", "_snr"], dropna=False):
                goodput = _mean_finite(_num(sub, "Goodput_Mbps"))
                power = _mean_finite(sub["_power_mw"])
                energy_per_bit = _safe_div(power / 1000.0, goodput * 1e6)
                rows.append(
                    {
                        "UEIndex": ue,
                        "Direction": direction,
                        "snr_db": snr_value,
                        "goodput_mbps": goodput,
                        "power_mW": power,
                        "energy_per_bit_j": energy_per_bit,
                        "SNR_dB": snr_value,
                        "EE_bits_per_joule": _safe_div(goodput * 1e6, power / 1000.0),
                        "N_trials": int(len(sub)),
                    }
                )
        if rows:
            self.write(target, pd.DataFrame(rows), "derive_energy_vs_throughput", used)
        else:
            self.log(target, "derive_energy_vs_throughput", "BLOCKED_SOURCE_MISSING", ["air_interface/csv/*_trials.csv"], 0, "requires measured/applied power columns; no default power used")

    def derive_tbs_reference_comparison(self) -> None:
        target = "reports/csv/tbs_reference_comparison.csv"
        if not self.target_needs(target):
            self.log(target, "derive_tbs_reference_comparison", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        rows: list[dict[str, Any]] = []
        used: list[str] = []
        for direction in ("DL", "UL"):
            df, source = self.raw_table(direction)
            if df.empty:
                continue
            ref_col = _col(df, ["Reference_nrTBS_bits", "ReferenceTBSBits", "TBSize_Reference", "nrTBS_bits"])
            dut_col = _col(df, ["TBSBits", "TBSize_bits", "TBS", "DUT_TBSize_bits"])
            if ref_col is None or dut_col is None:
                continue
            used.append(source)
            for _, row in df.iterrows():
                dut = pd.to_numeric(pd.Series([row.get(dut_col)]), errors="coerce").iloc[0]
                ref = pd.to_numeric(pd.Series([row.get(ref_col)]), errors="coerce").iloc[0]
                rows.append(
                    {
                        "UEIndex": row.get(_col(df, "UEIndex") or "", np.nan),
                        "Direction": direction,
                        "Slot": row.get(_col(df, "Slot") or "", np.nan),
                        "MCS": row.get(_col(df, ["MCS", "MCSIndex"]) or "", np.nan),
                        "PRBCount": row.get(_col(df, ["PRBCount", "AllocatedPRBCount", "PRBs"]) or "", np.nan),
                        "Layers": row.get(_col(df, ["Layers", "Rank"]) or "", np.nan),
                        "Modulation": row.get(_col(df, "Modulation") or "", ""),
                        "DUT_TBSize_bits": dut,
                        "Reference_nrTBS_bits": ref,
                        "Delta_bits": dut - ref if math.isfinite(dut) and math.isfinite(ref) else math.nan,
                        "Pass": bool(math.isfinite(dut) and math.isfinite(ref) and abs(dut - ref) <= 0),
                        "BaseGraph": row.get(_col(df, ["BaseGraph", "LDPCBaseGraph"]) or "", ""),
                    }
                )
        if rows:
            self.write(target, pd.DataFrame(rows), "derive_tbs_reference_comparison", used, "reference column had to exist in source rows")
        else:
            self.log(target, "derive_tbs_reference_comparison", "BLOCKED_SOURCE_MISSING", ["air_interface/csv/*_trials.csv"], 0, "requires existing reference nrTBS column; generator will not set reference=DUT")

    def find_bandwidth_hz(self) -> tuple[float, str]:
        for source in ["air_interface/csv/lls_snr_sweep.csv", "air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"]:
            df = self.read(source)
            if df.empty:
                continue
            bw = _num(df, ["Bandwidth_Hz", "bandwidth_hz", "ChannelBandwidth_Hz", "CarrierBandwidth_Hz"]).dropna()
            if not bw.empty and float(bw.iloc[0]) > 0:
                return float(bw.iloc[0]), source
        keys = {"bandwidthhz", "bandwidth", "channelbandwidthhz", "channelbandwidth", "carrierbandwidthhz"}
        for path in list(self.run_dir.rglob("*.json"))[:200]:
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except Exception:
                continue
            found = self._find_json_number(data, keys)
            if math.isfinite(found) and found > 0:
                return found, str(path.relative_to(self.run_dir))
        return math.nan, ""

    def _find_json_number(self, value: Any, keys: set[str]) -> float:
        if isinstance(value, dict):
            for key, child in value.items():
                if _clean_name(str(key)) in keys:
                    try:
                        x = float(child)
                        if math.isfinite(x):
                            return x
                    except Exception:
                        pass
                found = self._find_json_number(child, keys)
                if math.isfinite(found):
                    return found
        elif isinstance(value, list):
            for child in value:
                found = self._find_json_number(child, keys)
                if math.isfinite(found):
                    return found
        return math.nan

    def derive_shannon_capacity_gap(self) -> None:
        target = "reports/csv/shannon_capacity_gap.csv"
        if not self.target_needs(target):
            self.log(target, "derive_shannon_capacity_gap", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        sweep = self.read("air_interface/csv/lls_snr_sweep.csv")
        if sweep.empty:
            self.log(target, "derive_shannon_capacity_gap", "BLOCKED_SOURCE_MISSING", ["air_interface/csv/lls_snr_sweep.csv"], 0)
            return
        bandwidth, bw_source = self.find_bandwidth_hz()
        if not math.isfinite(bandwidth):
            self.log(target, "derive_shannon_capacity_gap", "BLOCKED_SOURCE_MISSING", ["*.json", "lls_snr_sweep.csv"], 0, "requires explicit bandwidth; no 100 MHz default used")
            return
        rows = []
        for _, row in sweep.iterrows():
            snr_db = pd.to_numeric(pd.Series([row.get(_col(sweep, ["snr_db", "SNR_dB"]) or "")]), errors="coerce").iloc[0]
            layers = pd.to_numeric(pd.Series([row.get(_col(sweep, ["n_layers", "MeanLayers", "Layers"]) or "")]), errors="coerce").iloc[0]
            goodput = pd.to_numeric(pd.Series([row.get(_col(sweep, ["goodput_mbps", "Goodput_Mbps"]) or "")]), errors="coerce").iloc[0]
            if not math.isfinite(layers) or layers <= 0:
                layers = 1.0
            if not math.isfinite(snr_db):
                continue
            capacity_bps_hz = layers * math.log2(1 + 10 ** (snr_db / 10.0))
            shannon_mbps = capacity_bps_hz * bandwidth / 1e6
            achieved_se = _safe_div(goodput * 1e6, bandwidth)
            rows.append(
                {
                    "direction": str(row.get(_col(sweep, ["direction", "Direction"]) or "", "")),
                    "snr_db": snr_db,
                    "n_layers": layers,
                    "shannon_capacity_bps_hz": capacity_bps_hz,
                    "shannon_mbps": shannon_mbps,
                    "achieved_goodput_mbps": goodput,
                    "achieved_se_bps_hz": achieved_se,
                    "gap_db": 10 * math.log10(_safe_div(shannon_mbps, goodput)) if goodput and goodput > 0 else math.nan,
                    "gap_pct": 100 * _safe_div(shannon_mbps - goodput, shannon_mbps),
                }
            )
        if rows:
            self.write(target, pd.DataFrame(rows), "derive_shannon_capacity_gap", ["air_interface/csv/lls_snr_sweep.csv", bw_source])
        else:
            self.log(target, "derive_shannon_capacity_gap", "BLOCKED_INSUFFICIENT_COLUMNS", ["air_interface/csv/lls_snr_sweep.csv"], 0)

    def derive_trs_doppler_error_trace(self) -> None:
        target = "reports/csv/trs_doppler_error_trace.csv"
        if not self.target_needs(target):
            self.log(target, "derive_trs_doppler_error_trace", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        source = "air_interface/csv/trs_trials.csv"
        df = self.read(source)
        if df.empty or _col(df, ["EstimatedDopplerHz", "EstimatedDoppler_Hz"]) is None:
            self.log(target, "derive_trs_doppler_error_trace", "BLOCKED_SOURCE_MISSING", [source], 0, "requires TRS runtime Doppler estimates")
            return
        est = _num(df, ["EstimatedDoppler_Hz", "EstimatedDopplerHz"])
        injected = _num(df, ["InjectedDoppler_Hz", "TheoreticalDoppler_Hz", "DopplerHz"])
        err = _num(df, ["DopplerError_Hz", "EstimationError_Hz"])
        if injected.dropna().empty and not err.dropna().empty:
            injected = est - err
        if injected.dropna().empty:
            self.log(target, "derive_trs_doppler_error_trace", "BLOCKED_INSUFFICIENT_COLUMNS", [source], 0, "requires injected/theoretical Doppler or error column")
            return
        out = pd.DataFrame(
            {
                "AbsoluteSlot": _series(df, "AbsoluteSlot", np.nan),
                "Frame": _series(df, "Frame", np.nan),
                "Slot": _series(df, "Slot", np.nan),
                "UEIndex": _series(df, "UEIndex", np.nan),
                "InjectedDoppler_Hz": injected,
                "EstimatedDoppler_Hz": est,
                "DopplerError_Hz": est - injected,
                "TrackingState": _text(df, "TrackingState", ""),
                "StrictOk": _series(df, "StrictOk", ""),
            }
        )
        self.write(target, out, "derive_trs_doppler_error_trace", [source])

    def slot_duration_ms(self) -> tuple[float, str]:
        for source in ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv", "reports/csv/scenario_summary.csv"]:
            df = self.read(source)
            if df.empty:
                continue
            slot = _num(df, ["SlotDuration_ms", "slot_duration_ms"]).dropna()
            if not slot.empty and slot.iloc[0] > 0:
                return float(slot.iloc[0]), source
        for path in list(self.run_dir.rglob("*.json"))[:200]:
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except Exception:
                continue
            found = self._find_json_number(data, {"slotdurationms", "slotduration"})
            if math.isfinite(found) and found > 0:
                return found, str(path.relative_to(self.run_dir))
        return math.nan, ""

    def radio_duration_ms(self, df: pd.DataFrame) -> tuple[float, str]:
        observed = _num(df, ["AirInterfaceObservation_ms", "RadioDuration_ms", "ObservationDuration_ms"]).dropna()
        if not observed.empty and observed.sum() > 0:
            return float(observed.sum()), "raw_duration_column"
        slot_ms, source = self.slot_duration_ms()
        slot_col = _num(df, ["AbsoluteSlot", "Slot"]).dropna()
        if math.isfinite(slot_ms) and not slot_col.empty:
            return float((slot_col.max() - slot_col.min() + 1) * slot_ms), source
        return math.nan, ""

    def derive_kpi_summary_and_lineage(self) -> None:
        summary_target = "air_interface/csv/lls_kpi_summary.csv"
        lineage_target = "reports/csv/kpi_lineage_table.csv"
        need_summary = self.target_needs(summary_target)
        need_lineage = self.target_needs(lineage_target)
        if not (need_summary or need_lineage):
            self.log(summary_target, "derive_kpi_summary", "SKIPPED_EXISTS", [summary_target], len(self.read(summary_target)))
            self.log(lineage_target, "derive_kpi_lineage", "SKIPPED_EXISTS", [lineage_target], len(self.read(lineage_target)))
            return
        lineage_rows = []
        metrics: dict[str, dict[str, Any]] = {}
        sources = []
        for direction in ("DL", "UL"):
            df, source = self.raw_table(direction)
            if df.empty or _col(df, "CRCPass") is None:
                continue
            sources.append(source)
            total = len(df)
            fail = _fail_count(df)
            ci_low, ci_high = _wilson_ci(fail, total)
            duration, duration_source = self.radio_duration_ms(df)
            duration_ok = math.isfinite(duration) and duration > 0
            goodput = _mean_finite(_num(df, "Goodput_Mbps"))
            metrics[direction] = {
                "bler": _safe_div(fail, total),
                "ci_low": ci_low,
                "ci_high": ci_high,
                "ber": _mean_finite(_num(df, ["RawBER", "BER"])),
                "goodput": goodput,
                "offered": _mean_finite(_num(df, ["OfferedThroughput_Mbps", "Throughput_Mbps"])),
                "duration": duration,
                "duration_ok": duration_ok,
            }
            lineage_rows.append(
                {
                    "Direction": direction,
                    "KPI_BLER": metrics[direction]["bler"],
                    "BLER_Source": f"{fail}/{total} failed transport blocks from {source}",
                    "KPI_Goodput_Mbps": goodput,
                    "Goodput_Source": f"mean Goodput_Mbps from {source}" if _col(df, "Goodput_Mbps") else "unavailable",
                    "T_radio_ms": duration,
                    "T_radio_Source": duration_source or "unavailable",
                    "RadioDurationOk": duration_ok,
                }
            )
        if need_lineage and lineage_rows:
            self.write(lineage_target, pd.DataFrame(lineage_rows), "derive_kpi_lineage", sources)
        elif need_lineage:
            self.log(lineage_target, "derive_kpi_lineage", "BLOCKED_SOURCE_MISSING", ["air_interface/csv/*_trials.csv"], 0)
        if need_summary and metrics:
            dl = metrics.get("DL", {})
            ul = metrics.get("UL", {})
            unavailable = not bool(dl.get("duration_ok", False)) or ("UL" in metrics and not bool(ul.get("duration_ok", False)))
            out = pd.DataFrame(
                [
                    {
                        "ScenarioID": self.run_dir.name,
                        "DL_BLER": dl.get("bler", math.nan),
                        "DL_BLER_CI95_Low": dl.get("ci_low", math.nan),
                        "DL_BLER_CI95_High": dl.get("ci_high", math.nan),
                        "DL_BER": dl.get("ber", math.nan),
                        "DL_Goodput_Mbps": dl.get("goodput", math.nan),
                        "DL_Offered_Mbps": dl.get("offered", math.nan),
                        "DL_RadioDuration_ms": dl.get("duration", math.nan),
                        "UL_BLER": ul.get("bler", math.nan),
                        "UL_Goodput_Mbps": ul.get("goodput", math.nan),
                        "UL_RadioDuration_ms": ul.get("duration", math.nan),
                        "KpiConsistencyOk": not unavailable,
                        "RadioDurationUnavailable": unavailable,
                        "Status": "runtime_derived" if not unavailable else "runtime_derived_duration_unavailable",
                    }
                ]
            )
            self.write(summary_target, out, "derive_kpi_summary", sources)
        elif need_summary:
            self.log(summary_target, "derive_kpi_summary", "BLOCKED_SOURCE_MISSING", ["air_interface/csv/*_trials.csv"], 0)

    def derive_fer_summary(self) -> None:
        target = "air_interface/csv/fer_summary.csv"
        if not self.target_needs(target):
            self.log(target, "derive_fer_summary", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        rows: list[dict[str, Any]] = []
        sources: list[str] = []
        for direction in ("DL", "UL"):
            df, source = self.raw_table(direction)
            if df.empty or _col(df, "CRCPass") is None:
                continue
            sources.append(source)
            work = df.copy()
            work["_ue"] = _series(df, "UEIndex", "ALL")
            for ue, sub in work.groupby("_ue", dropna=False):
                total = len(sub)
                fail = _fail_count(sub)
                ci_low, ci_high = _wilson_ci(fail, total)
                rows.append(
                    {
                        "Scope": "per_ue",
                        "Direction": direction,
                        "UEIndex": ue,
                        "N_TB": total,
                        "N_CRC_Fail": fail,
                        "FER": _safe_div(fail, total),
                        "FER_CI95_Low": ci_low,
                        "FER_CI95_High": ci_high,
                        "SNR_dB": _mean_finite(_num(sub, ["SNR_dB", "ConfiguredSNR_dB", "AppliedAWGNSNR_dB"])),
                        "MCS_Mode": _mode_text(_text(sub, ["MCS", "MCSIndex"])),
                        "ScenarioID": self.run_dir.name,
                    }
                )
        if rows:
            self.write(target, pd.DataFrame(rows), "derive_fer_summary", sources)
        else:
            self.log(target, "derive_fer_summary", "BLOCKED_SOURCE_MISSING", ["air_interface/csv/*_trials.csv"], 0)

    def derive_harq_combining_gain(self) -> None:
        target = "air_interface/csv/harq_combining_gain.csv"
        if not self.target_needs(target):
            self.log(target, "derive_harq_combining_gain", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        df = self.read("air_interface/csv/dl_pdsch_trials.csv")
        if df.empty or _col(df, "CRCPass") is None:
            self.log(target, "derive_harq_combining_gain", "BLOCKED_SOURCE_MISSING", ["air_interface/csv/dl_pdsch_trials.csv"], 0)
            return
        rounds = _num(df, ["HARQRound", "RV"]).fillna(0)
        work = df.copy()
        work["_round"] = rounds

        def bler_for(max_round: int) -> float:
            sub = work[work["_round"] <= max_round]
            return _safe_div(_fail_count(sub), len(sub))

        bler0 = bler_for(0)
        bler1 = bler_for(1)
        bler2 = bler_for(2)
        bler3 = bler_for(3)
        gain = 10 * math.log10(_safe_div(bler0, bler1)) if bler0 > 0 and bler1 > 0 else math.nan
        out = pd.DataFrame(
            [
                {
                    "CombiningGain_dB": gain,
                    "BLER_RV0": bler0,
                    "BLER_RV0_plus1": bler1,
                    "BLER_RV0_plus2": bler2,
                    "BLER_RV0_plus3": bler3,
                    "N_per_round_0": int((rounds == 0).sum()),
                    "N_per_round_1": int((rounds >= 1).sum()),
                    "Exercised": bool((rounds >= 1).any()),
                }
            ]
        )
        self.write(target, out, "derive_harq_combining_gain", ["air_interface/csv/dl_pdsch_trials.csv"], "Exercised=false when no retransmission rows are present")

    def derive_mobility_adequacy_report(self) -> None:
        target = "reports/csv/mobility_adequacy_report.csv"
        if not self.target_needs(target):
            self.log(target, "derive_mobility_adequacy_report", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        dl = self.read("air_interface/csv/dl_pdsch_trials.csv")
        trs = self.read("air_interface/csv/trs_trials.csv")
        if dl.empty:
            self.log(target, "derive_mobility_adequacy_report", "BLOCKED_SOURCE_MISSING", ["air_interface/csv/dl_pdsch_trials.csv"], 0)
            return
        speed = _mean_finite(_num(dl, ["UESpeed_kmh", "Velocity_kmh", "App_Velocity_kmh", "Cfg_Velocity_kmh"]))
        doppler = _mean_finite(_num(dl, ["InjectedDoppler_Hz", "TheoreticalDoppler_Hz", "DopplerHz"]))
        if not math.isfinite(doppler) and not trs.empty:
            doppler = _mean_finite(_num(trs, ["InjectedDoppler_Hz", "TheoreticalDoppler_Hz", "EstimatedDopplerHz"]))
        duration, duration_source = self.radio_duration_ms(dl)
        total_slots = int(_num(dl, ["AbsoluteSlot", "Slot"]).dropna().nunique())
        coherence_ms = _safe_div(0.423 * 1000.0, doppler) if doppler > 0 else math.nan
        travel = (speed / 3.6) * (duration / 1000.0) if math.isfinite(speed) and math.isfinite(duration) else math.nan
        n_coherence = _safe_div(duration, coherence_ms)
        attempts = len(dl)
        fail = _fail_count(dl)
        ci_low, ci_high = _wilson_ci(fail, attempts)
        goodput = _num(dl, "Goodput_Mbps").dropna()
        cv = float(goodput.std() / goodput.mean()) if len(goodput) > 1 and goodput.mean() else math.nan
        per_ue_counts = dl.groupby(_series(dl, "UEIndex", 0)).size()
        min_trials_per_ue = int(per_ue_counts.min()) if len(per_ue_counts) else 0
        checks = {
            "CoherenceOk": math.isfinite(n_coherence) and n_coherence >= 10,
            "TrialCountOk": min_trials_per_ue >= 100,
            "BLERCIOk": math.isfinite(ci_high - ci_low) and (ci_high - ci_low) <= 0.10,
            "ThroughputCVOk": math.isfinite(cv) and cv <= 0.20,
        }
        missing = []
        if not math.isfinite(speed):
            missing.append("speed")
        if not math.isfinite(doppler):
            missing.append("doppler")
        if not math.isfinite(duration):
            missing.append("duration")
        adequate = not missing and all(checks.values())
        out = pd.DataFrame(
            [
                {
                    "UESpeed_kmh": speed,
                    "MaxDoppler_Hz": doppler,
                    "CoherenceTime_ms": coherence_ms,
                    "TotalSlots": total_slots,
                    "RunDuration_ms": duration,
                    "UETravel_m": travel,
                    "NumCoherenceIntervals": n_coherence,
                    "NumDLTrials_perUE": min_trials_per_ue,
                    "DL_BLER": _safe_div(fail, attempts),
                    "DL_BLER_CI95_Width": ci_high - ci_low,
                    "DL_Throughput_CV": cv,
                    **checks,
                    "MobilityAdequate": adequate,
                    "HonestLabel": "mobility_adequate" if adequate else "insufficient_source_evidence:" + ",".join(missing or ["statistical_threshold_not_met"]),
                }
            ]
        )
        self.write(target, out, "derive_mobility_adequacy_report", ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/trs_trials.csv", duration_source])

    def derive_runtime_call_graph(self) -> None:
        target = "reports/csv/runtime_call_graph.csv"
        if not self.target_needs(target):
            self.log(target, "derive_runtime_call_graph", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        source = "analytics/csv/time_profile_analytics.csv"
        df = self.read(source)
        if df.empty or _col(df, "FunctionName") is None:
            self.log(target, "derive_runtime_call_graph", "BLOCKED_SOURCE_MISSING", [source], 0)
            return
        time_col = _col(df, ["Elapsed_s", "TotalTime_s", "ElapsedSeconds"])
        if time_col is None:
            self.log(target, "derive_runtime_call_graph", "BLOCKED_INSUFFICIENT_COLUMNS", [source], 0, "requires elapsed time column")
            return
        work = df.copy()
        work["_time"] = pd.to_numeric(work[time_col], errors="coerce").fillna(0)
        self_col = _col(work, ["SelfTime", "SelfTime_s"])
        work["_self"] = pd.to_numeric(work[self_col], errors="coerce").fillna(work["_time"]) if self_col else work["_time"]
        out = (
            work.groupby(_text(work, "FunctionName", ""), dropna=False)
            .agg(TotalTime_s=("_time", "sum"), NumCalls=("_time", "size"), SelfTime=("_self", "sum"))
            .reset_index()
            .rename(columns={"index": "FunctionName"})
        )
        if "FunctionName" not in out.columns:
            out.insert(0, "FunctionName", out.iloc[:, 0])
            out = out[["FunctionName", "TotalTime_s", "NumCalls", "SelfTime"]]
        self.write(target, out, "derive_runtime_call_graph", [source])

    def derive_scheduler_decision_log(self) -> None:
        target = "packet_flow/csv/scheduler_decision_log.csv"
        if not self.target_needs(target):
            self.log(target, "derive_scheduler_decision_log", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        for source in ["packet_flow/csv/live_scheduler_decision_log.csv", "packet_flow/csv/live_dl_scheduler_grants.csv"]:
            df = self.read(source)
            if df.empty:
                continue
            out = pd.DataFrame(
                {
                    "AbsoluteSlot": _series(df, ["AbsoluteSlot", "Slot"], np.nan),
                    "Frame": _series(df, "Frame", np.nan),
                    "Slot": _series(df, "Slot", np.nan),
                    "UEIndex": _series(df, ["UEIndex", "UEID", "UEId"], np.nan),
                    "PF_Rank": _series(df, ["PF_Rank", "PFRank", "Rank"], np.nan),
                    "PF_Metric": _series(df, ["PF_Metric", "PFMetric"], np.nan),
                    "PF_Metric_rank1": _series(df, ["PF_Metric_rank1", "PFMetricRank1"], np.nan),
                    "Inst_Rate_bps": _series(df, ["Inst_Rate_bps", "InstantRate_bps"], np.nan),
                    "Avg_Rate_bps": _series(df, ["Avg_Rate_bps", "AverageRate_bps"], np.nan),
                    "SINR_dB": _series(df, ["SINR_dB", "PostEqSINR_dB"], np.nan),
                    "CQI": _series(df, ["CQI", "CQIUsed"], np.nan),
                    "BLER_est": _series(df, ["BLER_est", "EstimatedBLER"], np.nan),
                    "HARQ_ProcID": _series(df, ["HARQ_ProcID", "HARQ_ID", "HARQProcessID"], np.nan),
                    "HARQ_Blocked": _series(df, ["HARQ_Blocked", "HARQBlocked"], False),
                    "Scheduled": _series(df, "Scheduled", True),
                    "RejectionReason": _series(df, "RejectionReason", ""),
                    "PRBCount": _series(df, ["PRBCount", "PRBLength", "AllocatedPRBCount"], np.nan),
                    "MCSIndex": _series(df, ["MCSIndex", "MCS"], np.nan),
                    "TBS": _series(df, ["TBS", "TBSBits", "TBSize_bits"], np.nan),
                    "HARQ_ID": _series(df, ["HARQ_ID", "HARQProcessID"], np.nan),
                }
            )
            self.write(target, out, "derive_scheduler_decision_log", [source], "TBS left blank if absent in real grant source")
            return
        self.log(target, "derive_scheduler_decision_log", "BLOCKED_SOURCE_MISSING", ["packet_flow/csv/live_*scheduler*.csv"], 0)

    def derive_scheduler_ue_summary(self) -> None:
        target = "packet_flow/csv/scheduler_ue_summary.csv"
        if not self.target_needs(target):
            self.log(target, "derive_scheduler_ue_summary", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        source = "packet_flow/csv/scheduler_decision_log.csv"
        df = self.read(source)
        if df.empty:
            self.log(target, "derive_scheduler_ue_summary", "BLOCKED_SOURCE_MISSING", [source], 0)
            return
        work = df.copy()
        work["_ue"] = _series(df, "UEIndex", 0)
        work["_scheduled"] = _boolish(_series(df, "Scheduled", True))
        rows = []
        for ue, sub in work.groupby("_ue", dropna=False):
            reasons = _text(sub, "RejectionReason", "")
            total = int(len(sub))
            scheduled = int(sub["_scheduled"].sum())
            rows.append(
                {
                    "UEIndex": ue,
                    "TotalSlots": int(_num(sub, ["AbsoluteSlot", "Slot"]).dropna().nunique()) or total,
                    "ScheduledSlots": scheduled,
                    "RejectedSlots": total - scheduled,
                    "ScheduledFrac": _safe_div(scheduled, total),
                    "MeanPF_Metric": _mean_finite(_num(sub, "PF_Metric")),
                    "MeanInstRate_Mbps": _mean_finite(_num(sub, "Inst_Rate_bps")) / 1e6,
                    "MeanAvgRate_Mbps": _mean_finite(_num(sub, "Avg_Rate_bps")) / 1e6,
                    "MeanSINR_dB": _mean_finite(_num(sub, "SINR_dB")),
                    "Rejected_HARQ_ALL_PROCESSES_BUSY": int((reasons == "HARQ_ALL_PROCESSES_BUSY").sum()),
                    "Rejected_NO_PRB_REMAINING": int((reasons == "NO_PRB_REMAINING").sum()),
                    "Rejected_CQI_ZERO_UNREACHABLE": int((reasons == "CQI_ZERO_UNREACHABLE").sum()),
                }
            )
        self.write(target, pd.DataFrame(rows), "derive_scheduler_ue_summary", [source])

    def derive_ul_scheduling_coverage(self) -> None:
        target = "air_interface/csv/ul_scheduling_coverage.csv"
        if not self.target_needs(target):
            self.log(target, "derive_ul_scheduling_coverage", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        source = "packet_flow/csv/live_ul_scheduler_grants.csv"
        df = self.read(source)
        status = "scheduled_runtime_grant"
        if df.empty:
            source = "air_interface/csv/ul_pusch_trials.csv"
            df = self.read(source)
            status = "decoded_ul_trial_without_grant_trace"
        if df.empty:
            self.log(target, "derive_ul_scheduling_coverage", "BLOCKED_SOURCE_MISSING", ["packet_flow/csv/live_ul_scheduler_grants.csv", "air_interface/csv/ul_pusch_trials.csv"], 0)
            return
        slot_type = _text(df, "SlotType", "regular").str.lower()
        out = pd.DataFrame(
            {
                "AbsoluteSlot": _series(df, ["AbsoluteSlot", "Slot"], np.nan),
                "UEIndex": _series(df, ["UEIndex", "UEID"], np.nan),
                "GrantType": np.where(slot_type.str.contains("special"), "UL_SPECIAL", "UL_REGULAR"),
                "Status": status,
                "PRBCount": _series(df, ["PRBCount", "PRBLength", "AllocatedPRBCount"], np.nan),
                "MCSIndex": _series(df, ["MCSIndex", "MCS"], np.nan),
                "TBS": _series(df, ["TBS", "TBSBits", "TBSize_bits"], np.nan),
            }
        )
        self.write(target, out, "derive_ul_scheduling_coverage", [source])

    def derive_channel_per_ue_realization(self) -> None:
        target = "reports/csv/channel_rf_per_ue_realization.csv"
        if not self.target_needs(target):
            self.log(target, "derive_channel_rf_per_ue_realization", "SKIPPED_EXISTS", [target], len(self.read(target)))
            return
        rows = []
        used = []
        for direction in ("DL", "UL"):
            df, source = self.raw_table(direction)
            if df.empty:
                continue
            if _col(df, ["AppliedPathLoss_dB", "AppliedPathloss_dB", "InjectedDoppler_Hz", "DopplerHz"]) is None:
                continue
            used.append(source)
            work = df.copy()
            work["_ue"] = _series(df, "UEIndex", 0)
            for ue, sub in work.groupby("_ue", dropna=False):
                ref = _mean_finite(_num(sub, ["TheoreticalDoppler_Hz", "DopplerHz_Ref", "InjectedDoppler_Hz"]))
                applied = _mean_finite(_num(sub, ["DopplerHz_Applied", "App_DopplerHz", "InjectedDoppler_Hz", "DopplerHz"]))
                rows.append(
                    {
                        "UEIndex": ue,
                        "RNTI": _first_text(_series(sub, "RNTI", "")),
                        "Seed": _first_text(_series(sub, ["Seed", "RandomSeed"], "")),
                        "PropagationDist_m": _mean_finite(_num(sub, ["PropagationDist_m", "PropagationDistance_m"])),
                        "AppliedPathLoss_dB": _mean_finite(_num(sub, ["AppliedPathLoss_dB", "AppliedPathloss_dB", "App_PathLoss_dB"])),
                        "ShadowFading_dB": _mean_finite(_num(sub, ["ShadowFading_dB", "AppliedShadowFading_dB"])),
                        "InjectedDoppler_Hz": _mean_finite(_num(sub, ["InjectedDoppler_Hz", "DopplerHz"])),
                        "FreeSpacePathLoss_dB": _mean_finite(_num(sub, ["FreeSpacePathLoss_dB", "Ref_FreeSpacePathLoss_dB"])),
                        "ChannelModel": _mode_text(_text(sub, ["ChannelModel", "App_ChannelModel"])),
                        "DopplerHz_Ref": ref,
                        "DopplerHz_Applied": applied,
                        "DopplerConsistent": math.isfinite(ref) and math.isfinite(applied) and abs(ref - applied) <= max(1.0, abs(ref) * 0.05),
                    }
                )
        if rows:
            self.write(target, pd.DataFrame(rows), "derive_channel_rf_per_ue_realization", used)
        else:
            self.log(target, "derive_channel_rf_per_ue_realization", "BLOCKED_SOURCE_MISSING", ["air_interface/csv/*_trials.csv"], 0, "requires applied path-loss or Doppler evidence")

    def run(self) -> None:
        self.copy_same_name_sources()
        self.derive_snr_sweep()
        self.derive_nmse_vs_snr()
        self.derive_energy_vs_throughput()
        self.derive_tbs_reference_comparison()
        self.derive_shannon_capacity_gap()
        self.derive_trs_doppler_error_trace()
        self.derive_kpi_summary_and_lineage()
        self.derive_fer_summary()
        self.derive_harq_combining_gain()
        self.derive_mobility_adequacy_report()
        self.derive_runtime_call_graph()
        self.derive_scheduler_decision_log()
        self.derive_scheduler_ue_summary()
        self.derive_ul_scheduling_coverage()
        self.derive_channel_per_ue_realization()
        self.write_log()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_dir", type=Path)
    parser.add_argument("--overwrite", action="store_true", help="Regenerate derived CSVs even when present.")
    args = parser.parse_args(argv)
    if not args.run_dir.exists():
        print(f"Run directory does not exist: {args.run_dir}", file=sys.stderr)
        return 2
    generator = CsvGenerator(args.run_dir, overwrite=args.overwrite)
    generator.run()
    print(f"CSV generation log: {args.run_dir / 'reports' / 'csv' / 'manifest_generation_log.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
