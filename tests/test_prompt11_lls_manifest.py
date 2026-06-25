from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
POSTPROCESS = REPO_ROOT / "postprocess"
sys.path.insert(0, str(POSTPROCESS))

from generate_missing_csvs import CsvGenerator  # noqa: E402
from generate_missing_plots import PlotGenerator, plt  # noqa: E402
from lls_manifest_contract import CSV_MANIFEST, check_csv_spec, final_manifest_acceptance_gate  # noqa: E402


def _mkdirs(run_dir: Path) -> None:
    for rel in [
        "air_interface/csv",
        "control/csv",
        "reports/csv",
        "reports/html",
        "reports/image",
        "packet_flow/csv",
        "analytics/csv",
    ]:
        (run_dir / rel).mkdir(parents=True, exist_ok=True)


def _dl_required_row(**overrides: object) -> dict[str, object]:
    spec = next(spec for spec in CSV_MANIFEST if spec.path == "air_interface/csv/dl_pdsch_trials.csv")
    row = {col: "" for col in spec.required_columns}
    row.update(
        {
            "Frame": 0,
            "Slot": 0,
            "AbsoluteSlot": 0,
            "UEIndex": 1,
            "RNTI": 1001,
            "MCS": 10,
            "Modulation": "16QAM",
            "CodeRate": 0.5,
            "Layers": 2,
            "PRBStart": 0,
            "PRBCount": 24,
            "TBSBits": 1000,
            "GoodBits": 1000,
            "CRCPass": True,
            "RawBER": 0.0,
            "PostEqSINR_dB": 12.0,
            "NMSE_dB": -18.0,
            "ConditionNumber_dB": 8.0,
            "MeasuredLDPCDecoderMeanIterations": 4,
            "NoiseVar": 0.063,
            "SNR_dB": 12.0,
            "OuterLoopApplied": True,
            "OLLADeltaMCS": 0,
            "HARQ_ID": 0,
            "RV": 0,
            "HARQRound": 0,
            "NDI": 1,
            "UsedOracleFields": "",
            "NoiseVarSource": "runtime_metadata",
            "ChannelEstMethod": "pilot_based",
            "StrictOk": True,
            "IsWarmupFrame": False,
            "Goodput_Mbps": 8.0,
            "OfferedThroughput_Mbps": 10.0,
        }
    )
    row.update(overrides)
    return row


def _raw_rows(direction: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for i, snr in enumerate([0, 5, 10, 15, 20]):
        for ue in [1, 2]:
            fail = snr <= 5 and ue == 2
            base = _dl_required_row(
                Frame=i // 2,
                Slot=i,
                AbsoluteSlot=i,
                UEIndex=ue,
                SNR_dB=snr,
                PostEqSINR_dB=snr + 1.0,
                GoodBits=0 if fail else 1000,
                CRCPass=not fail,
                RawBER=0.04 if fail else 0.0,
                NoiseVar=10 ** (-(snr + 1.0) / 10),
                Goodput_Mbps=4.0 + snr / 2.0,
                OfferedThroughput_Mbps=9.0 + snr / 2.0,
            )
            base["SlotDuration_ms"] = 0.5
            base["TxPower_dBm"] = 23.0
            base["Bandwidth_Hz"] = 100_000_000
            if direction == "UL":
                base.update(
                    {
                        "DataRECount": 120,
                        "Qm": 4,
                        "MeasuredRateMatchedBits": 960,
                        "ComputedE_TS38212": 960,
                        "SlotType": "regular",
                    }
                )
            rows.append(base)
    return rows


def test_manifest_audit_rejects_configured_noise_and_perfect_channel(tmp_path: Path) -> None:
    run_dir = tmp_path / "run"
    _mkdirs(run_dir)
    pd.DataFrame(
        [
            _dl_required_row(
                NoiseVarSource="configured_snr",
                ChannelEstMethod="perfect",
            )
        ]
    ).to_csv(run_dir / "air_interface" / "csv" / "dl_pdsch_trials.csv", index=False)

    row = check_csv_spec(run_dir, next(spec for spec in CSV_MANIFEST if spec.path == "air_interface/csv/dl_pdsch_trials.csv"))

    assert row["status"] in {"FAIL_ROWS", "FAIL_CONSTRAINTS"}
    assert "noise_source_measurement_backed" in row["constraint_failures"]
    assert "channel_estimation_not_oracle" in row["constraint_failures"]


def test_csv_generator_derives_runtime_tables_without_fake_tbs_reference(tmp_path: Path) -> None:
    run_dir = tmp_path / "run"
    _mkdirs(run_dir)
    pd.DataFrame(_raw_rows("DL")).to_csv(run_dir / "air_interface" / "csv" / "dl_pdsch_trials.csv", index=False)
    pd.DataFrame(_raw_rows("UL")).to_csv(run_dir / "air_interface" / "csv" / "ul_pusch_trials.csv", index=False)

    CsvGenerator(run_dir).run()

    assert not (run_dir / "air_interface" / "csv" / "lls_snr_sweep.csv").exists()
    summary = pd.read_csv(run_dir / "air_interface" / "csv" / "lls_measured_sinr_summary.csv")
    assert {"SINR_median_dB", "KPIFormulaVersion", "Goodput_Mbps_mean"}.issubset(summary.columns)
    assert set(summary["KPIFormulaVersion"]) == {"measured_sinr_geometry_v1"}
    dl_curve = pd.read_csv(run_dir / "air_interface" / "csv" / "dl_measured_sinr_bler_curve.csv")
    assert {"PostEqSINR_dB_BinCenter", "BLER_CI_Low", "BLER_CI_High"}.issubset(dl_curve.columns)
    assert (run_dir / "reports" / "csv" / "kpi_lineage_table.csv").exists()
    assert (run_dir / "air_interface" / "csv" / "fer_summary.csv").exists()
    assert (run_dir / "air_interface" / "csv" / "harq_combining_gain.csv").exists()

    assert not (run_dir / "reports" / "csv" / "tbs_reference_comparison.csv").exists()
    log = pd.read_csv(run_dir / "reports" / "csv" / "manifest_generation_log.csv")
    tbs_log = log[log["artifact"] == "reports/csv/tbs_reference_comparison.csv"].iloc[-1]
    assert tbs_log["status"] == "BLOCKED_SOURCE_MISSING"
    assert "reference=DUT" in tbs_log["notes"]


def test_plot_generator_renders_measured_sinr_html_and_png_from_real_csv(tmp_path: Path) -> None:
    if plt is None:
        pytest.skip("matplotlib is unavailable")
    run_dir = tmp_path / "run"
    _mkdirs(run_dir)
    pd.DataFrame(
        {
            "Direction": ["DL", "DL"],
            "UEIndex": [float("nan"), float("nan")],
            "PostEqSINR_dB_BinCenter": [1, 11],
            "BLER": [0.5, 0.05],
            "BLER_CI_Low": [0.3, 0.01],
            "BLER_CI_High": [0.7, 0.1],
            "BER": [0.02, 0.001],
            "TrialCount": [10, 10],
            "FailureCount": [5, 1],
            "SourceArtifact": ["air_interface/csv/dl_pdsch_trials.csv"] * 2,
        }
    ).to_csv(run_dir / "air_interface" / "csv" / "dl_measured_sinr_bler_curve.csv", index=False)
    pd.DataFrame(
        {
            "Direction": ["UL", "UL"],
            "UEIndex": [float("nan"), float("nan")],
            "PostEqSINR_dB_BinCenter": [1, 11],
            "BLER": [0.6, 0.08],
            "BLER_CI_Low": [0.4, 0.02],
            "BLER_CI_High": [0.8, 0.14],
            "BER": [0.03, 0.002],
            "TrialCount": [10, 10],
            "FailureCount": [6, 1],
            "SourceArtifact": ["air_interface/csv/ul_pusch_trials.csv"] * 2,
        }
    ).to_csv(run_dir / "air_interface" / "csv" / "ul_measured_sinr_bler_curve.csv", index=False)
    pd.DataFrame(
        {
            "Direction": ["DL", "DL", "UL", "UL"],
            "UEIndex": [float("nan")] * 4,
            "PostEqSINR_dB_BinCenter": [1, 11, 1, 11],
            "Goodput_Mbps_mean": [4.0, 12.0, 3.0, 9.0],
            "OfferedThroughput_Mbps_mean": [5.0, 13.0, 4.0, 10.0],
            "SpectralEfficiency_bps_Hz_mean": [0.04, 0.12, 0.03, 0.09],
            "TrialCount": [10, 10, 10, 10],
            "SourceArtifact": ["air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/dl_pdsch_trials.csv", "air_interface/csv/ul_pusch_trials.csv", "air_interface/csv/ul_pusch_trials.csv"],
        }
    ).iloc[:2].to_csv(run_dir / "air_interface" / "csv" / "dl_measured_sinr_throughput_curve.csv", index=False)
    pd.DataFrame(
        {
            "Direction": ["UL", "UL"],
            "UEIndex": [float("nan"), float("nan")],
            "PostEqSINR_dB_BinCenter": [1, 11],
            "Goodput_Mbps_mean": [3.0, 9.0],
            "OfferedThroughput_Mbps_mean": [4.0, 10.0],
            "SpectralEfficiency_bps_Hz_mean": [0.03, 0.09],
            "TrialCount": [10, 10],
            "SourceArtifact": ["air_interface/csv/ul_pusch_trials.csv"] * 2,
        }
    ).to_csv(run_dir / "air_interface" / "csv" / "ul_measured_sinr_throughput_curve.csv", index=False)
    pd.DataFrame(
        {
            "Direction": ["SRS", "SRS"],
            "PostEqSINR_dB": [1, 11],
            "MetricName": ["NMSE_dB", "NMSE_dB"],
            "MetricValue": [-5, -16],
            "SampleCount": [2, 2],
            "EvidenceClass": ["RUNTIME_DERIVED"] * 2,
            "SourceArtifact": ["air_interface/csv/srs_trials.csv"] * 2,
        }
    ).to_csv(run_dir / "reports" / "csv" / "nmse_vs_measured_sinr.csv", index=False)

    PlotGenerator(run_dir).run()

    assert (run_dir / "reports" / "html" / "bler_vs_measured_sinr.html").exists()
    assert (run_dir / "reports" / "image" / "bler_vs_measured_sinr.png").exists()
    assert (run_dir / "reports" / "html" / "throughput_vs_measured_sinr.html").exists()
    assert (run_dir / "reports" / "image" / "nmse_vs_measured_sinr.png").exists()
    assert (run_dir / "reports" / "html" / "master_dashboard.html").exists()


def test_acceptance_gate_reports_missing_manifest_without_throwing(tmp_path: Path) -> None:
    run_dir = tmp_path / "run"
    _mkdirs(run_dir)

    gate = final_manifest_acceptance_gate(run_dir)

    assert gate["ok"] is False
    assert gate["total_items"] > 0
    assert (run_dir / "reports" / "csv" / "manifest_audit_report.csv").exists()
