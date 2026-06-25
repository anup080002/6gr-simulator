#!/usr/bin/env python3
"""Generate LLS manifest plots from real completed-run CSV artifacts."""
from __future__ import annotations

import argparse
import html
import math
import sys
from pathlib import Path
from typing import Any, Callable, Iterable

import numpy as np
import pandas as pd

try:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except Exception:  # pragma: no cover - exercised only on stripped environments
    plt = None  # type: ignore[assignment]

try:
    import plotly.graph_objects as go
except Exception:  # pragma: no cover
    go = None  # type: ignore[assignment]

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from lls_manifest_contract import IMAGE_MANIFEST  # noqa: E402


PASS_TOKENS = {"1", "true", "pass", "ok", "success", "decoded", "detected"}


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


def _num(df: pd.DataFrame, names: str | Iterable[str]) -> pd.Series:
    name = _col(df, names)
    if name is None:
        return pd.Series([np.nan] * len(df), index=df.index)
    return pd.to_numeric(df[name], errors="coerce")


def _text(df: pd.DataFrame, names: str | Iterable[str], default: str = "") -> pd.Series:
    name = _col(df, names)
    if name is None:
        return pd.Series([default] * len(df), index=df.index)
    return df[name].fillna(default).astype(str)


def _boolish(series: pd.Series) -> pd.Series:
    if series.empty:
        return pd.Series(dtype=bool)
    if pd.api.types.is_bool_dtype(series):
        return series.fillna(False)
    if pd.api.types.is_numeric_dtype(series):
        return pd.to_numeric(series, errors="coerce").fillna(0).astype(float) != 0
    return series.astype(str).str.strip().str.lower().isin(PASS_TOKENS)


def _finite_xy(x: pd.Series, y: pd.Series) -> tuple[pd.Series, pd.Series]:
    xnum = pd.to_numeric(x, errors="coerce")
    ynum = pd.to_numeric(y, errors="coerce")
    mask = xnum.notna() & ynum.notna()
    return xnum[mask], ynum[mask]


def _pass_rate_by_snr(df: pd.DataFrame) -> pd.DataFrame:
    snr = _num(df, ["snr_db", "SNR_dB", "PilotSNR_dB", "PostEqSINR_dB"])
    detected = _boolish(df[_col(df, ["Detected", "CRCPass"])]) if _col(df, ["Detected", "CRCPass"]) else pd.Series([], dtype=bool)
    if snr.dropna().empty or detected.empty:
        return pd.DataFrame()
    work = pd.DataFrame({"snr_db": snr, "detected": detected})
    return work.dropna(subset=["snr_db"]).groupby("snr_db", as_index=False).agg(detection_probability=("detected", "mean"), n=("detected", "size"))


class PlotGenerator:
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

    def exists(self, path: str) -> bool:
        return self.rel(path).exists() and not self.overwrite

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

    def write_log(self) -> None:
        out = self.rel("reports/csv/manifest_plot_generation_log.csv")
        out.parent.mkdir(parents=True, exist_ok=True)
        pd.DataFrame(
            self.log_rows,
            columns=["artifact", "action", "status", "source_artifacts", "row_count", "notes"],
        ).to_csv(out, index=False)

    def source_missing(self, target: str, source: str, action: str) -> bool:
        if source == "__all__":
            return False
        if self.rel(source).exists():
            return False
        self.log(target, action, "BLOCKED_SOURCE_MISSING", [source], 0)
        return True

    def write_html(self, target: str, title: str, source: str, fig: Any, fallback_rows: pd.DataFrame | None = None) -> None:
        full = self.rel(target)
        full.parent.mkdir(parents=True, exist_ok=True)
        if go is not None and fig is not None:
            fig.update_layout(
                title=title,
                template="plotly_white",
                font={"family": "Arial, sans-serif", "size": 12},
                margin={"l": 60, "r": 24, "t": 64, "b": 56},
            )
            fig.write_html(full, include_plotlyjs="cdn", full_html=True)
        else:
            rows = fallback_rows if fallback_rows is not None else pd.DataFrame()
            full.write_text(self.simple_html(title, source, rows), encoding="utf-8")
        self.log(target, "render_html", "GENERATED", [source], 1)

    def simple_html(self, title: str, source: str, rows: pd.DataFrame) -> str:
        body = "<p>No interactive plotting backend was available; source rows are shown below.</p>"
        if not rows.empty:
            body += rows.head(100).to_html(index=False, escape=True)
        return (
            "<!doctype html><html><head><meta charset='utf-8'>"
            f"<title>{html.escape(title)}</title>"
            "<style>body{font-family:Arial,sans-serif;margin:24px;color:#1f2937}"
            "table{border-collapse:collapse;font-size:12px}td,th{border:1px solid #ddd;padding:4px}</style>"
            "</head><body>"
            f"<h1>{html.escape(title)}</h1><p>Source: {html.escape(source)}</p>{body}</body></html>"
        )

    def write_png(self, target: str, title: str, source: str, plotter: Callable[[Any], None], row_count: int) -> None:
        if plt is None:
            self.log(target, "render_png", "BLOCKED_UNAVAILABLE", [source], row_count, "matplotlib unavailable")
            return
        full = self.rel(target)
        full.parent.mkdir(parents=True, exist_ok=True)
        fig, ax = plt.subplots(figsize=(8.5, 5.0), dpi=140)
        plotter(ax)
        ax.set_title(title)
        ax.grid(True, alpha=0.25)
        fig.tight_layout()
        fig.savefig(full)
        plt.close(fig)
        self.log(target, "render_png", "GENERATED", [source], row_count)

    def line_png(self, target: str, title: str, source: str, df: pd.DataFrame, x_col: str, y_col: str, group_col: str | None = None, log_y: bool = False) -> None:
        def plot(ax: Any) -> None:
            if group_col and group_col in df.columns:
                for group, sub in df.groupby(group_col, dropna=False):
                    x, y = _finite_xy(sub[x_col], sub[y_col])
                    if len(x):
                        ax.plot(x, y, marker="o", label=str(group))
                ax.legend()
            else:
                x, y = _finite_xy(df[x_col], df[y_col])
                ax.plot(x, y, marker="o")
            ax.set_xlabel(x_col)
            ax.set_ylabel(y_col)
            if log_y:
                ax.set_yscale("log")

        self.write_png(target, title, source, plot, len(df))

    def plot_bler_vs_measured_sinr(self) -> None:
        source = "air_interface/csv/dl_measured_sinr_bler_curve.csv"
        df = pd.concat([self.read(source), self.read("air_interface/csv/ul_measured_sinr_bler_curve.csv")], ignore_index=True)
        needed = ["reports/html/bler_vs_measured_sinr.html", "reports/image/bler_vs_measured_sinr.png"]
        if df.empty or self.source_missing(needed[0], source, "plot_bler_vs_measured_sinr"):
            return
        x_col, y_col = _col(df, "PostEqSINR_dB_BinCenter"), _col(df, "BLER")
        if x_col is None or y_col is None:
            for target in needed:
                self.log(target, "plot_bler_vs_measured_sinr", "BLOCKED_INSUFFICIENT_COLUMNS", [source], len(df), "requires measured SINR bin center and BLER")
            return
        group = _col(df, ["Direction", "UEIndex"])
        if not self.exists(needed[0]):
            fig = go.Figure() if go is not None else None
            if fig is not None:
                groups = df.groupby(group, dropna=False) if group else [("all", df)]
                for name, sub in groups:
                    fig.add_trace(go.Scatter(x=sub[x_col], y=sub[y_col], mode="lines+markers", name=str(name)))
                    lo, hi = _col(sub, "BLER_CI_Low"), _col(sub, "BLER_CI_High")
                    if lo and hi:
                        fig.add_trace(go.Scatter(x=sub[x_col], y=sub[lo], mode="lines", line={"width": 0}, showlegend=False, hoverinfo="skip"))
                        fig.add_trace(go.Scatter(x=sub[x_col], y=sub[hi], mode="lines", fill="tonexty", line={"width": 0}, name=f"{name} CI95", opacity=0.25))
                fig.add_hline(y=0.10, line_dash="dash", annotation_text="Target BLER 10%")
                fig.update_yaxes(type="log", title="BLER")
                fig.update_xaxes(title="Measured post-EQ SINR (dB)")
            self.write_html(needed[0], "BLER vs Measured SINR", source, fig, df)
        if not self.exists(needed[1]):
            self.line_png(needed[1], "BLER vs Measured SINR", source, df.rename(columns={x_col: "PostEqSINR_dB", y_col: "BLER"}), "PostEqSINR_dB", "BLER", group, log_y=True)

    def plot_throughput_vs_measured_sinr(self) -> None:
        source = "air_interface/csv/dl_measured_sinr_throughput_curve.csv"
        df = pd.concat([self.read(source), self.read("air_interface/csv/ul_measured_sinr_throughput_curve.csv")], ignore_index=True)
        needed = ["reports/html/throughput_vs_measured_sinr.html", "reports/image/throughput_vs_measured_sinr.png"]
        if df.empty:
            for target in needed:
                self.log(target, "plot_throughput_vs_measured_sinr", "BLOCKED_SOURCE_MISSING", [source], 0)
            return
        x_col = _col(df, "PostEqSINR_dB_BinCenter")
        y_col = _col(df, ["Goodput_Mbps_mean", "OfferedThroughput_Mbps_mean"])
        if x_col is None or y_col is None:
            for target in needed:
                self.log(target, "plot_throughput_vs_measured_sinr", "BLOCKED_INSUFFICIENT_COLUMNS", [source], len(df), "requires measured SINR and throughput/goodput")
            return
        group = _col(df, ["Direction", "UEIndex"])
        if not self.exists(needed[0]):
            fig = go.Figure() if go is not None else None
            if fig is not None:
                groups = df.groupby(group, dropna=False) if group else [("all", df)]
                for name, sub in groups:
                    fig.add_trace(go.Scatter(x=sub[x_col], y=sub[y_col], mode="lines+markers", name=str(name)))
                shannon = self.read("reports/csv/shannon_capacity_gap.csv")
                sx, sy = _col(shannon, ["PostEqSINR_dB", "SINR_median_dB"]), _col(shannon, ["ShannonCapacity_Mbps", "shannon_mbps"])
                if sx and sy:
                    fig.add_trace(go.Scatter(x=shannon[sx], y=shannon[sy], mode="lines", name="Shannon reference", line={"dash": "dash"}))
                fig.update_xaxes(title="Measured post-EQ SINR (dB)")
                fig.update_yaxes(title="Throughput (Mbps)")
            self.write_html(needed[0], "Throughput vs Measured SINR", source, fig, df)
        if not self.exists(needed[1]):
            self.line_png(needed[1], "Throughput vs Measured SINR", source, df.rename(columns={x_col: "PostEqSINR_dB", y_col: "throughput_mbps"}), "PostEqSINR_dB", "throughput_mbps", group)

    def plot_nmse_vs_measured_sinr(self) -> None:
        source = "reports/csv/nmse_vs_measured_sinr.csv"
        df = self.read(source)
        needed = ["reports/html/nmse_vs_measured_sinr.html", "reports/image/nmse_vs_measured_sinr.png"]
        if df.empty:
            for target in needed:
                self.log(target, "plot_nmse_vs_measured_sinr", "BLOCKED_SOURCE_MISSING", [source], 0)
            return
        x_col, y_col = _col(df, ["PostEqSINR_dB", "MeasuredSINR_dB"]), _col(df, ["MetricValue", "NMSE_dB_mean", "NMSE_dB"])
        if x_col is None or y_col is None:
            for target in needed:
                self.log(target, "plot_nmse_vs_measured_sinr", "BLOCKED_INSUFFICIENT_COLUMNS", [source], len(df), "requires measured SINR and NMSE")
            return
        group = _col(df, ["UEIndex", "Direction", "Method"])
        if not self.exists(needed[0]):
            fig = go.Figure() if go is not None else None
            if fig is not None:
                groups = df.groupby(group, dropna=False) if group else [("all", df)]
                for name, sub in groups:
                    fig.add_trace(go.Scatter(x=sub[x_col], y=sub[y_col], mode="lines+markers", name=f"UE/method {name}"))
                fig.add_hline(y=0, line_dash="dash", annotation_text="0 dB")
                fig.update_xaxes(title="Measured post-EQ SINR (dB)")
                fig.update_yaxes(title="NMSE (dB)")
            self.write_html(needed[0], "NMSE vs Measured SINR", source, fig, df)
        if not self.exists(needed[1]):
            self.line_png(needed[1], "NMSE vs Measured SINR", source, df.rename(columns={x_col: "PostEqSINR_dB", y_col: "NMSE_dB_mean"}), "PostEqSINR_dB", "NMSE_dB_mean", group)

    def plot_shannon_gap(self) -> None:
        source = "reports/csv/shannon_capacity_gap.csv"
        target = "reports/html/shannon_gap.html"
        df = self.read(source)
        if df.empty:
            self.log(target, "plot_shannon_gap", "BLOCKED_SOURCE_MISSING", [source], 0)
            return
        sx, cap, good = _col(df, ["PostEqSINR_dB", "SINR_median_dB"]), _col(df, ["ShannonCapacity_Mbps", "shannon_mbps"]), _col(df, ["AchievedGoodput_Mbps", "achieved_goodput_mbps"])
        if sx is None or cap is None or good is None:
            self.log(target, "plot_shannon_gap", "BLOCKED_INSUFFICIENT_COLUMNS", [source], len(df))
            return
        if self.exists(target):
            self.log(target, "plot_shannon_gap", "SKIPPED_EXISTS", [source], len(df))
            return
        fig = go.Figure() if go is not None else None
        if fig is not None:
            fig.add_trace(go.Scatter(x=df[sx], y=df[cap], mode="lines+markers", name="Shannon"))
            fig.add_trace(go.Scatter(x=df[sx], y=df[good], mode="lines+markers", name="Achieved goodput"))
            fig.update_xaxes(title="Measured post-EQ SINR (dB)")
            fig.update_yaxes(title="Mbps")
        self.write_html(target, "Shannon Capacity Gap", source, fig, df)

    def plot_control_detection(self, source: str, target: str, title: str, action: str) -> None:
        df = self.read(source)
        if df.empty:
            self.log(target, action, "BLOCKED_SOURCE_MISSING", [source], 0)
            return
        agg = _pass_rate_by_snr(df)
        if agg.empty:
            self.log(target, action, "BLOCKED_INSUFFICIENT_COLUMNS", [source], len(df), "requires SNR and Detected/CRCPass")
            return
        if self.exists(target):
            self.log(target, action, "SKIPPED_EXISTS", [source], len(df))
            return
        fig = go.Figure() if go is not None else None
        if fig is not None:
            fig.add_trace(go.Scatter(x=agg["snr_db"], y=agg["detection_probability"], mode="lines+markers", name="Detection probability"))
            fig.add_hline(y=0.99, line_dash="dash", annotation_text="99% target")
            fig.update_xaxes(title="SNR (dB)")
            fig.update_yaxes(title="Probability", range=[0, 1.02])
        self.write_html(target, title, source, fig, agg)

    def access_delay_points(self) -> tuple[pd.DataFrame, str]:
        for source in ["control/csv/initial_access_lifecycle_trace.csv", "reports/csv/control_plane_timeline.csv"]:
            df = self.read(source)
            if df.empty:
                continue
            delay_col = _col(df, ["AccessDelay_ms", "ProcedureDelay_ms", "Latency_ms", "Delay_ms", "Duration_ms", "Timestamp_ms"])
            if delay_col is None:
                continue
            vals = pd.to_numeric(df[delay_col], errors="coerce").dropna().sort_values().reset_index(drop=True)
            if vals.empty:
                continue
            points = pd.DataFrame({"delay_ms": vals, "cdf": (np.arange(len(vals)) + 1) / len(vals)})
            return points, source
        return pd.DataFrame(), "control/csv/initial_access_lifecycle_trace.csv"

    def plot_access_delay(self) -> None:
        needed = ["reports/html/access_delay_cdf.html", "reports/image/access_delay_cdf.png"]
        points, source = self.access_delay_points()
        if points.empty:
            for target in needed:
                self.log(target, "plot_access_delay_cdf", "BLOCKED_SOURCE_MISSING", [source], 0, "requires access delay or latency column")
            return
        if not self.exists(needed[0]):
            fig = go.Figure() if go is not None else None
            if fig is not None:
                fig.add_trace(go.Scatter(x=points["delay_ms"], y=points["cdf"], mode="lines", name="CDF"))
                fig.update_xaxes(title="Access delay (ms)")
                fig.update_yaxes(title="CDF", range=[0, 1.02])
            self.write_html(needed[0], "Access Delay CDF", source, fig, points)
        if not self.exists(needed[1]):
            self.line_png(needed[1], "Access Delay CDF", source, points, "delay_ms", "cdf")

    def plot_trs_tracking(self) -> None:
        source, target = "reports/csv/trs_doppler_error_trace.csv", "reports/html/trs_tracking_error.html"
        df = self.read(source)
        if df.empty:
            self.log(target, "plot_trs_tracking_error", "BLOCKED_SOURCE_MISSING", [source], 0)
            return
        x_col = _col(df, ["AbsoluteSlot", "Slot"])
        est = _col(df, ["EstimatedDoppler_Hz", "EstimatedDopplerHz"])
        inj = _col(df, ["InjectedDoppler_Hz", "TheoreticalDoppler_Hz"])
        err = _col(df, ["DopplerError_Hz", "EstimationError_Hz"])
        if x_col is None or (est is None and err is None):
            self.log(target, "plot_trs_tracking_error", "BLOCKED_INSUFFICIENT_COLUMNS", [source], len(df))
            return
        if self.exists(target):
            self.log(target, "plot_trs_tracking_error", "SKIPPED_EXISTS", [source], len(df))
            return
        fig = go.Figure() if go is not None else None
        if fig is not None:
            if inj:
                fig.add_trace(go.Scatter(x=df[x_col], y=df[inj], mode="lines+markers", name="Injected/theoretical"))
            if est:
                fig.add_trace(go.Scatter(x=df[x_col], y=df[est], mode="lines+markers", name="Estimated"))
            if err:
                fig.add_trace(go.Bar(x=df[x_col], y=df[err], name="Error Hz", opacity=0.45))
            fig.add_hline(y=370.63, line_dash="dash", annotation_text="370.63 Hz reference")
            fig.update_xaxes(title="Slot")
            fig.update_yaxes(title="Hz")
        self.write_html(target, "TRS Tracking Error", source, fig, df)

    def plot_nvar(self) -> None:
        source, target = "air_interface/csv/dl_pdsch_trials.csv", "reports/html/nvar_calibration.html"
        df = self.read(source)
        sinr, nvar = _col(df, "PostEqSINR_dB"), _col(df, ["NoiseVar", "NoiseVariance"])
        if df.empty or sinr is None or nvar is None:
            self.log(target, "plot_nvar_calibration", "BLOCKED_INSUFFICIENT_COLUMNS", [source], len(df), "requires PostEqSINR_dB and NoiseVar")
            return
        if self.exists(target):
            self.log(target, "plot_nvar_calibration", "SKIPPED_EXISTS", [source], len(df))
            return
        sinr_lin = 10 ** (pd.to_numeric(df[sinr], errors="coerce") / 10.0)
        fig = go.Figure() if go is not None else None
        if fig is not None:
            fig.add_trace(go.Scatter(x=sinr_lin, y=pd.to_numeric(df[nvar], errors="coerce"), mode="markers", name="Runtime NoiseVar"))
            ref_x = np.linspace(float(sinr_lin.min()), float(sinr_lin.max()), 100) if sinr_lin.dropna().size else np.array([])
            if len(ref_x):
                fig.add_trace(go.Scatter(x=ref_x, y=1 / ref_x, mode="lines", name="1/PostEqSINR", line={"dash": "dash"}))
            fig.update_xaxes(title="Post-EQ SINR (linear)", type="log")
            fig.update_yaxes(title="Noise variance", type="log")
        self.write_html(target, "Noise Variance Calibration", source, fig, df)

    def plot_rank_distribution(self) -> None:
        target = "reports/html/rank_distribution.html"
        rank_source = "beamforming/csv/rank_layer_trials.csv" if self.rel("beamforming/csv/rank_layer_trials.csv").exists() else "air_interface/csv/dl_pdsch_trials.csv"
        df = self.read(rank_source)
        rank = _col(df, ["EffectiveRank", "Layers", "Rank"])
        if df.empty or rank is None:
            self.log(target, "plot_rank_distribution", "BLOCKED_SOURCE_MISSING", [rank_source], len(df), "requires rank/layer column")
            return
        if self.exists(target):
            self.log(target, "plot_rank_distribution", "SKIPPED_EXISTS", [rank_source], len(df))
            return
        counts = pd.to_numeric(df[rank], errors="coerce").dropna().value_counts().sort_index()
        fig = go.Figure() if go is not None else None
        if fig is not None:
            fig.add_trace(go.Bar(x=counts.index.astype(str), y=counts.values, name="Runtime rank"))
            mimo = self.read("beamforming/csv/mimo_configured_vs_effective.csv")
            exact = _col(mimo, "ExactMatchPercent")
            if exact:
                fig.add_annotation(text=f"Exact match: {pd.to_numeric(mimo[exact], errors='coerce').mean():.1f}%", xref="paper", yref="paper", x=0.98, y=0.98, showarrow=False)
            fig.update_xaxes(title="Rank/layers")
            fig.update_yaxes(title="Count")
        self.write_html(target, "Rank Distribution", rank_source, fig, pd.DataFrame({"rank": counts.index, "count": counts.values}))

    def plot_ul_beam_accuracy(self) -> None:
        source, target = "air_interface/csv/ul_pusch_trials.csv", "reports/html/ul_beam_accuracy.html"
        df = self.read(source)
        if df.empty or (_col(df, "BeamHit") is None and _col(df, "BeamGainGap_dB") is None):
            source = "beamforming/csv/beam_score_trace.csv"
            df = self.read(source)
        hit, gap = _col(df, "BeamHit"), _col(df, "BeamGainGap_dB")
        if df.empty or (hit is None and gap is None):
            self.log(target, "plot_ul_beam_accuracy", "BLOCKED_SOURCE_MISSING", [source], len(df), "requires BeamHit or BeamGainGap_dB")
            return
        if self.exists(target):
            self.log(target, "plot_ul_beam_accuracy", "SKIPPED_EXISTS", [source], len(df))
            return
        fig = go.Figure() if go is not None else None
        if fig is not None:
            if gap:
                fig.add_trace(go.Histogram(x=df[gap], name="Beam gain gap dB"))
            if hit:
                hit_rate = float(_boolish(df[hit]).mean())
                fig.add_annotation(text=f"Beam hit rate: {100 * hit_rate:.1f}%", xref="paper", yref="paper", x=0.98, y=0.98, showarrow=False)
        self.write_html(target, "UL Beam Accuracy", source, fig, df)

    def plot_mimo_condition(self) -> None:
        source, target = "beamforming/csv/mimo_config_validation.csv", "reports/html/mimo_condition_number.html"
        df = self.read(source)
        cond = _col(df, ["CondNum_dB", "ConditionNumber_dB"])
        if df.empty or cond is None:
            self.log(target, "plot_mimo_condition_number", "BLOCKED_SOURCE_MISSING", [source], len(df), "requires condition number")
            return
        if self.exists(target):
            self.log(target, "plot_mimo_condition_number", "SKIPPED_EXISTS", [source], len(df))
            return
        fig = go.Figure() if go is not None else None
        if fig is not None:
            fig.add_trace(go.Histogram(x=df[cond], name="Condition number"))
            fig.add_vline(x=20, line_dash="dash", annotation_text="20 dB viability threshold")
            fig.update_xaxes(title="Condition number (dB)")
        self.write_html(target, "MIMO Condition Number", source, fig, df)

    def plot_precoder_gain(self) -> None:
        source, target = "air_interface/csv/dl_pdsch_trials.csv", "reports/html/precoder_gain.html"
        df = self.read(source)
        sinr, layers = _col(df, "PostEqSINR_dB"), _col(df, ["Layers", "Rank"])
        if df.empty or sinr is None or layers is None:
            self.log(target, "plot_precoder_gain", "BLOCKED_INSUFFICIENT_COLUMNS", [source], len(df), "requires PostEqSINR_dB and Layers")
            return
        if self.exists(target):
            self.log(target, "plot_precoder_gain", "SKIPPED_EXISTS", [source], len(df))
            return
        fig = go.Figure() if go is not None else None
        if fig is not None:
            for layer, sub in df.groupby(layers, dropna=False):
                fig.add_trace(go.Histogram(x=sub[sinr], name=f"layers {layer}", opacity=0.65))
            fig.update_xaxes(title="Post-EQ SINR (dB)")
        self.write_html(target, "Precoder Gain", source, fig, df)

    def plot_harq_gain(self) -> None:
        source, target = "air_interface/csv/harq_combining_gain.csv", "reports/html/harq_combining_gain.html"
        df = self.read(source)
        cols = [c for c in ["BLER_RV0", "BLER_RV0_plus1", "BLER_RV0_plus2", "BLER_RV0_plus3"] if c in df.columns]
        if df.empty or not cols:
            self.log(target, "plot_harq_combining_gain", "BLOCKED_SOURCE_MISSING", [source], len(df), "requires HARQ BLER columns")
            return
        if self.exists(target):
            self.log(target, "plot_harq_combining_gain", "SKIPPED_EXISTS", [source], len(df))
            return
        fig = go.Figure() if go is not None else None
        if fig is not None:
            row = df.iloc[0]
            fig.add_trace(go.Bar(x=cols, y=[row[c] for c in cols], name="BLER"))
            if "CombiningGain_dB" in df.columns:
                fig.add_annotation(text=f"Combining gain: {pd.to_numeric(df['CombiningGain_dB'], errors='coerce').iloc[0]:.2f} dB", xref="paper", yref="paper", x=0.98, y=0.98, showarrow=False)
        self.write_html(target, "HARQ Combining Gain", source, fig, df)

    def plot_harq_timeline(self) -> None:
        source, target = "harq/csv/harq_process_timeline.csv", "reports/html/harq_process_timeline.html"
        df = self.read(source)
        slot, proc = _col(df, ["AbsoluteSlot", "Slot"]), _col(df, ["HARQ_ID", "HARQProcessID", "ProcessID"])
        state = _col(df, ["State", "HARQState"])
        if df.empty or slot is None or proc is None:
            self.log(target, "plot_harq_process_timeline", "BLOCKED_SOURCE_MISSING", [source], len(df), "requires slot and HARQ process")
            return
        if self.exists(target):
            self.log(target, "plot_harq_process_timeline", "SKIPPED_EXISTS", [source], len(df))
            return
        fig = go.Figure() if go is not None else None
        if fig is not None:
            text = df[state] if state else ""
            fig.add_trace(go.Scatter(x=df[slot], y=df[proc], mode="markers", text=text, name="HARQ state"))
            fig.update_xaxes(title="Slot")
            fig.update_yaxes(title="HARQ process")
        self.write_html(target, "HARQ Process Timeline", source, fig, df)

    def plot_olla(self) -> None:
        source, target = "air_interface/csv/dl_pdsch_trials.csv", "reports/html/olla_convergence.html"
        df = self.read(source)
        slot, delta = _col(df, ["AbsoluteSlot", "Slot"]), _col(df, "OLLADeltaMCS")
        if df.empty or slot is None or delta is None:
            self.log(target, "plot_olla_convergence", "BLOCKED_INSUFFICIENT_COLUMNS", [source], len(df), "requires OLLADeltaMCS")
            return
        if self.exists(target):
            self.log(target, "plot_olla_convergence", "SKIPPED_EXISTS", [source], len(df))
            return
        fig = go.Figure() if go is not None else None
        if fig is not None:
            ue = _col(df, "UEIndex")
            groups = df.groupby(ue, dropna=False) if ue else [("all", df)]
            for name, sub in groups:
                fig.add_trace(go.Scatter(x=sub[slot], y=sub[delta], mode="lines+markers", name=f"UE {name}"))
            fig.add_hline(y=0, line_dash="dash")
            fig.update_xaxes(title="Slot")
            fig.update_yaxes(title="OLLA delta MCS")
        self.write_html(target, "OLLA Convergence", source, fig, df)

    def plot_tbs(self) -> None:
        source, target = "reports/csv/tbs_reference_comparison.csv", "reports/html/tbs_mismatch.html"
        df = self.read(source)
        dut, ref = _col(df, "DUT_TBSize_bits"), _col(df, "Reference_nrTBS_bits")
        if df.empty or dut is None or ref is None:
            self.log(target, "plot_tbs_mismatch", "BLOCKED_SOURCE_MISSING", [source], len(df), "requires DUT and reference TBS")
            return
        if self.exists(target):
            self.log(target, "plot_tbs_mismatch", "SKIPPED_EXISTS", [source], len(df))
            return
        fig = go.Figure() if go is not None else None
        if fig is not None:
            fig.add_trace(go.Scatter(x=df[ref], y=df[dut], mode="markers", name="Trial"))
            max_v = pd.to_numeric(pd.concat([df[ref], df[dut]]), errors="coerce").max()
            if math.isfinite(max_v):
                fig.add_trace(go.Scatter(x=[0, max_v], y=[0, max_v], mode="lines", name="y=x", line={"dash": "dash"}))
            fig.update_xaxes(title="Reference nrTBS bits")
            fig.update_yaxes(title="DUT TBS bits")
        self.write_html(target, "TBS Reference Comparison", source, fig, df)

    def plot_scheduler_balance(self) -> None:
        source, target = "packet_flow/csv/scheduler_decision_log.csv", "reports/html/scheduler_balance.html"
        df = self.read(source)
        if df.empty:
            self.log(target, "plot_scheduler_balance", "BLOCKED_SOURCE_MISSING", [source], 0)
            return
        if self.exists(target):
            self.log(target, "plot_scheduler_balance", "SKIPPED_EXISTS", [source], len(df))
            return
        ue = _col(df, "UEIndex")
        scheduled = _boolish(df[_col(df, "Scheduled")]) if _col(df, "Scheduled") else pd.Series([True] * len(df))
        work = df.copy()
        work["_scheduled"] = scheduled
        frac = work.groupby(ue if ue else work.index, dropna=False)["_scheduled"].mean()
        fig = go.Figure() if go is not None else None
        if fig is not None:
            fig.add_trace(go.Bar(x=frac.index.astype(str), y=frac.values, name="Scheduled fraction"))
            fig.update_xaxes(title="UE")
            fig.update_yaxes(title="Scheduled fraction", range=[0, 1])
        self.write_html(target, "Scheduler Balance", source, fig, pd.DataFrame({"UE": frac.index, "ScheduledFrac": frac.values}))

    def plot_prb_heatmap(self) -> None:
        source, target = "reports/csv/prb_allocation_heatmap.csv", "reports/html/prb_allocation_heatmap.html"
        df = self.read(source)
        if df.empty:
            source = "packet_flow/csv/scheduler_decision_log.csv"
            df = self.read(source)
        slot, start, count = _col(df, ["AbsoluteSlot", "Slot"]), _col(df, "PRBStart"), _col(df, ["PRBCount", "PRBLength"])
        if df.empty or slot is None or count is None:
            self.log(target, "plot_prb_allocation_heatmap", "BLOCKED_SOURCE_MISSING", [source], len(df), "requires slot and PRB allocation")
            return
        if self.exists(target):
            self.log(target, "plot_prb_allocation_heatmap", "SKIPPED_EXISTS", [source], len(df))
            return
        fig = go.Figure() if go is not None else None
        if fig is not None:
            y = df[start] if start else pd.Series([0] * len(df))
            fig.add_trace(go.Scatter(x=df[slot], y=y, mode="markers", marker={"size": np.maximum(6, pd.to_numeric(df[count], errors="coerce").fillna(1))}, name="PRB allocation"))
            fig.update_xaxes(title="Slot")
            fig.update_yaxes(title="PRB start")
        self.write_html(target, "PRB Allocation Heatmap", source, fig, df)

    def png_hist_or_line(self, target: str, source: str, title: str, x_names: Iterable[str], y_names: Iterable[str] | None = None, action: str = "render_png_from_csv") -> None:
        if self.exists(target):
            self.log(target, action, "SKIPPED_EXISTS", [source], len(self.read(source)))
            return
        df = self.read(source)
        if df.empty:
            self.log(target, action, "BLOCKED_SOURCE_MISSING", [source], 0)
            return
        x_col = _col(df, x_names)
        y_col = _col(df, y_names) if y_names else None
        if x_col is None:
            self.log(target, action, "BLOCKED_INSUFFICIENT_COLUMNS", [source], len(df), "missing x column")
            return
        if y_col:
            xx, yy = _finite_xy(df[x_col], pd.to_numeric(df[y_col], errors="coerce"))
            if len(xx) == 0:
                self.log(target, action, "BLOCKED_INSUFFICIENT_COLUMNS", [source], len(df), "no finite x/y pairs")
                return
        else:
            if pd.to_numeric(df[x_col], errors="coerce").dropna().empty:
                self.log(target, action, "BLOCKED_INSUFFICIENT_COLUMNS", [source], len(df), "no finite x values")
                return

        def plot(ax: Any) -> None:
            x = pd.to_numeric(df[x_col], errors="coerce").dropna()
            if y_col:
                y = pd.to_numeric(df[y_col], errors="coerce")
                xx, yy = _finite_xy(df[x_col], y)
                ax.plot(xx, yy, marker="o", linestyle="none" if len(xx) < 3 else "-")
                ax.set_ylabel(y_col)
            else:
                ax.hist(x, bins=min(40, max(5, int(math.sqrt(len(x))))))
                ax.set_ylabel("Count")
            ax.set_xlabel(x_col)

        self.write_png(target, title, source, plot, len(df))

    def generate_remaining_pngs(self) -> None:
        self.png_hist_or_line("reports/image/beam_channel_sinr.png", "beamforming/csv/beam_score_trace.csv", "Beam Channel SINR", ["SINR_dB", "PostEqSINR_dB"], None)
        self.png_hist_or_line("reports/image/beam_condition_number.png", "beamforming/csv/mimo_config_validation.csv", "Beam Condition Number", ["CondNum_dB", "ConditionNumber_dB"], None)
        self.png_hist_or_line("reports/image/beam_gain_gap.png", "beamforming/csv/beam_score_trace.csv", "Beam Gain Gap", ["BeamGainGap_dB"], None)
        self.png_hist_or_line("reports/image/equalized_constellations.png", "air_interface/csv/dl_pdsch_trials.csv", "Equalized Constellations", ["EqualizedSymbolI", "EqSymI"], ["EqualizedSymbolQ", "EqSymQ"], "plot_equalized_constellations")
        self.png_hist_or_line("reports/image/llr_histograms.png", "air_interface/csv/dl_pdsch_trials.csv", "LLR Histograms", ["LLR", "LLRValue"], None, "plot_llr_histograms")
        self.png_hist_or_line("reports/image/bler_vs_sinr.png", "air_interface/csv/dl_pdsch_trials.csv", "BLER vs SINR", ["PostEqSINR_dB"], ["CRCPass"], "plot_bler_vs_sinr")
        self.png_hist_or_line("reports/image/papr_ccdf.png", "air_interface/csv/papr_ccdf.csv", "PAPR CCDF", ["PAPR_dB", "papr_db"], ["ccdf", "CCDF"], "plot_papr_ccdf")
        self.png_hist_or_line("reports/image/power_energy_cumulative.png", "reports/csv/energy_vs_throughput.csv", "Power/Energy Cumulative", ["goodput_mbps"], ["energy_per_bit_j"], "plot_power_energy")
        points, source = self.access_delay_points()
        if not points.empty and not self.exists("reports/image/latency_cdf.png"):
            self.line_png("reports/image/latency_cdf.png", "Latency CDF", source, points.rename(columns={"delay_ms": "latency_ms"}), "latency_ms", "cdf")
        else:
            self.log("reports/image/latency_cdf.png", "plot_latency_cdf", "BLOCKED_SOURCE_MISSING" if points.empty else "SKIPPED_EXISTS", [source], len(points))
        self.png_hist_or_line("reports/image/heatmap_band_feature_kpi.png", "reports/csv/per_slot_kpi_table.csv", "Band Feature KPI", ["Slot"], ["DL_BLER", "DL_Goodput_Mbps"], "plot_heatmap_band_feature")
        self.png_hist_or_line("reports/image/heatmap_beam_rank_trp_kpi.png", "beamforming/csv/mimo_configured_vs_effective.csv", "Beam Rank TRP KPI", ["ExactMatchPercent"], None, "plot_heatmap_beam_rank")
        self.png_hist_or_line("reports/image/heatmap_impairment_kpi.png", "reports/csv/physics_audit_table.csv", "Impairment KPI", ["MetricValue", "Value"], None, "plot_heatmap_impairment")
        self.png_hist_or_line("reports/image/gains_losses_waterfall.png", "reports/csv/shannon_capacity_gap.csv", "Gains/Losses Waterfall", ["PostEqSINR_dB", "SINR_median_dB"], ["Gap_pct", "gap_pct"], "plot_gains_losses_waterfall")
        self.png_hist_or_line("reports/image/metric_coverage_by_category.png", "reports/csv/output_coverage_registry.csv", "Metric Coverage", ["CoverageFraction", "Implemented"], None, "plot_metric_coverage")

    def build_master_dashboard(self) -> None:
        target = "reports/html/master_dashboard.html"
        html_dir = self.rel("reports/html")
        html_dir.mkdir(parents=True, exist_ok=True)
        pages = sorted(p.name for p in html_dir.glob("*.html") if p.name != "master_dashboard.html")
        nav = "".join(f"<button data-target='{html.escape(page)}'>{html.escape(Path(page).stem.replace('_', ' ').title())}</button>" for page in pages)
        panes = "".join(f"<iframe data-page='{html.escape(page)}' src='{html.escape(page)}' title='{html.escape(page)}'></iframe>" for page in pages[:1])
        body = (
            "<!doctype html><html><head><meta charset='utf-8'><title>6GR LLS Manifest Dashboard</title>"
            "<style>body{margin:0;font-family:Arial,sans-serif;background:#eef2f7;color:#172033}"
            "header{padding:14px 20px;background:#12324a;color:white}h1{font-size:20px;margin:0}"
            "nav{display:flex;flex-wrap:wrap;gap:4px;padding:8px;background:#dce5ef}"
            "button{border:1px solid #b8c6d4;background:white;border-radius:5px;padding:6px 9px;cursor:pointer}"
            "main{padding:10px}iframe{width:100%;height:calc(100vh - 112px);border:1px solid #c8d3df;border-radius:8px;background:white}"
            "</style></head><body>"
            f"<header><h1>6GR LLS Manifest Dashboard</h1><div>{html.escape(str(self.run_dir))}</div></header>"
            f"<nav>{nav}</nav><main>{panes or '<p>No HTML plots were generated from available CSV evidence.</p>'}</main>"
            "<script>document.querySelectorAll('button').forEach(b=>b.onclick=()=>{document.querySelector('main').innerHTML="
            "`<iframe src='${b.dataset.target}' title='${b.dataset.target}'></iframe>`;});</script>"
            "</body></html>"
        )
        self.rel(target).write_text(body, encoding="utf-8")
        self.log(target, "build_master_dashboard", "GENERATED", ["reports/html/*.html"], len(pages))

    def run(self) -> None:
        self.plot_bler_vs_measured_sinr()
        self.plot_throughput_vs_measured_sinr()
        self.plot_nmse_vs_measured_sinr()
        self.plot_shannon_gap()
        self.plot_control_detection("control/csv/pdcch_false_alarm_sweep.csv", "reports/html/pdcch_detection_vs_snr.html", "PDCCH Detection vs SNR", "plot_pdcch_detection")
        self.plot_access_delay()
        self.plot_trs_tracking()
        self.plot_nvar()
        self.plot_control_detection("control/csv/pucch_false_alarm_trials.csv", "reports/html/pucch_detection_vs_snr.html", "PUCCH Detection vs SNR", "plot_pucch_detection")
        self.plot_rank_distribution()
        self.plot_ul_beam_accuracy()
        self.plot_mimo_condition()
        self.plot_precoder_gain()
        self.plot_harq_gain()
        self.plot_harq_timeline()
        self.plot_olla()
        self.plot_tbs()
        self.plot_scheduler_balance()
        self.plot_prb_heatmap()
        self.generate_remaining_pngs()
        self.build_master_dashboard()
        self.write_log()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_dir", type=Path)
    parser.add_argument("--overwrite", action="store_true", help="Regenerate plots even when present.")
    args = parser.parse_args(argv)
    if not args.run_dir.exists():
        print(f"Run directory does not exist: {args.run_dir}", file=sys.stderr)
        return 2
    generator = PlotGenerator(args.run_dir, overwrite=args.overwrite)
    generator.run()
    print(f"Plot generation log: {args.run_dir / 'reports' / 'csv' / 'manifest_plot_generation_log.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
