from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
STATIC_ROOT = REPO_ROOT / "jio_ran_web_design_v7"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> None:
    required_files = [
        STATIC_ROOT / "analytics-data.js",
        STATIC_ROOT / "chart-engine.js",
        STATIC_ROOT / "app.js",
        STATIC_ROOT / "data.js",
    ]
    for path in required_files:
        assert path.exists(), f"missing static web asset: {path.name}"

    combined = "\n".join(_read(path) for path in STATIC_ROOT.glob("*.js"))
    forbidden = [
        "lineSpark(",
        "barSpark(",
        "heatMap(",
        "Math.sin",
        "[1,3,2,5,3,6,4,7,3,8]",
        "[84,72,65,91,58,74]",
        "[40,20,20,10,10]",
        "[20,20,5,10,20]",
        "[1,2,3,5,8,13,21,34,55,89]",
        "PRB 42",
        "17.2 dB",
        "1.96 Gbps",
    ]
    for marker in forbidden:
        assert marker not in combined, f"static chart layer still contains fake marker {marker!r}"

    analytics_data = _read(STATIC_ROOT / "analytics-data.js")
    for csv_name in [
        "throughput_analytics.csv",
        "link_adaptation_analytics.csv",
        "prach_analytics.csv",
        "channel_estimation_analytics.csv",
        "mobility_analytics.csv",
        "resource_grid_analytics.csv",
        "fairness_analytics.csv",
        "energy_efficiency_analytics.csv",
        "waveform_analytics.csv",
    ]:
        assert csv_name in analytics_data, f"analytics data layer does not load {csv_name}"

    for measured_field in [
        "MeasuredTrialSINR_dB",
        "Goodput_Mbps",
        "WidebandCQI",
        "MCSIndex",
        "CRCPass",
        "ServingRSRP_dBm",
        "TBSize_bits",
        "LLRMeanAbs",
        "ConditionNumber_dB",
        "NoiseVariance",
        "ResidualCFO_PostCorrection_Hz",
        "PAPR_dB",
    ]:
        assert measured_field in analytics_data, f"analytics charts are not wired to {measured_field}"

    app_text = _read(STATIC_ROOT / "app.js")
    assert "window.AnalyticsData" in app_text
    assert "window.Charts" in app_text
    assert "No run selected" in app_text
    for chart_name in [
        "Spectral Efficiency vs SINR",
        "TBS Distribution per MCS",
        "LLR Mean Abs CDF",
        "Condition Number CDF",
        "Noise Variance vs SINR",
        "Beam-Hit Rate vs SINR",
        "Residual CFO CDF",
        "PAPR CDF",
    ]:
        assert chart_name in app_text, f"missing real-data chart card: {chart_name}"
    assert "Runtime CSV" in _read(STATIC_ROOT / "analytics.html")

    chart_pages = [
        "analytics.html",
        "geometry.html",
        "traffic.html",
        "realtime.html",
        "waveform.html",
    ]
    for name in chart_pages:
        text = _read(STATIC_ROOT / name)
        assert "analytics-data.js" in text, f"{name} must load AnalyticsData"
        assert "chart-engine.js" in text, f"{name} must load chart engine"
        assert text.index("analytics-data.js") < text.index("app.js"), f"{name} must load AnalyticsData before app.js"
        assert text.index("chart-engine.js") < text.index("app.js"), f"{name} must load chart engine before app.js"

    data_text = _read(STATIC_ROOT / "data.js")
    assert "realtimeKpis: []" in data_text
    assert "realtimeTables: { grants: [], control: [], channel: [] }" in data_text
    assert "Awaiting runtime evidence" in data_text


if __name__ == "__main__":
    main()
