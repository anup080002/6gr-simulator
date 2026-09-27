"""Cross-point exports preserve failures, exact rows, and missing measurements."""
import csv
import json
from pathlib import Path
import sys
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
from lls_sweep_report import observe_sweep, export_sweep, concatenate_csv, read_rows, io_path


def put_csv(path, fields, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def fixture(root):
    (root / "meta").mkdir(parents=True)
    (root / "meta/scenario_config_resolved.json").write_text(json.dumps({
        "scenario": {"runner_profile": "generic_sweep", "sweep": {"overrides": [
            {"label": f"snr_{n}", "config": {"simulation": {"snr_db": n}}} for n in [-30, 20, 40]]}}}), encoding="utf-8")
    # MATLAB sanitizes negative label sign to underscore.
    done = root / "sweeps/snr_30"
    active = root / "sweeps/snr_20"
    put_csv(root / "reports/csv/sweep_summary.csv", ["Label", "Ok", "ExecutionStatus", "ErrorIdentifier"],
            [dict(Label="snr_-30", Ok=0, ExecutionStatus="execution_error", ErrorIdentifier="PublicationFailure")])
    put_csv(active / "reports/csv/run_state.csv", ["CurrentCanonicalSlot", "CanonicalSlotsPerSweepPoint"],
            [dict(CurrentCanonicalSlot=58, CanonicalSlotsPerSweepPoint=58)])
    return done, active


def test_progress_completed_is_not_passed_and_slots_are_not_terminal(tmp_path):
    _, active = fixture(tmp_path)
    result = observe_sweep(active)
    assert result["completed"] == 1 and result["failed"] == 1 and result["passed"] == 0
    assert result["ongoing"] == 1 and result["pending"] == 1
    assert [p["status"] for p in result["points"]] == ["failed", "finalizing", "pending"]
    assert [p["configured_snr_db"] for p in result["points"]] == [-30, 20, 40]


def test_shared_export_retains_empty_table_and_failed_control_rows(tmp_path):
    done, active = fixture(tmp_path)
    put_csv(done / "air_interface/csv/dl_pdsch_trials.csv", ["CRCPass", "MeasuredTrialSINR_dB"], [])
    put_csv(done / "air_interface/csv/pbch_trials.csv", ["CRCPass", "MeasuredTrialSINR_dB"],
            [dict(CRCPass=0, MeasuredTrialSINR_dB="")])
    original = (done / "air_interface/csv/pbch_trials.csv").read_bytes()
    put_csv(active / "air_interface/csv/pbch_trials.csv", ["CRCPass"], [dict(CRCPass=1)])
    receipt = export_sweep(tmp_path)
    assert not receipt["Complete"] and receipt["FailedArtifacts"] == 0
    manifest = read_rows(tmp_path / "reports/csv/sweep_comparison_manifest.csv")
    tables = {r["SourceRelativePath"]: read_rows(tmp_path / r["CombinedArtifact"]) for r in manifest}
    assert not tables["air_interface/csv/dl_pdsch_trials.csv"]
    row, = tables["air_interface/csv/pbch_trials.csv"]
    assert row["CRCPass"] == "0" and row["MeasuredTrialSINR_dB"] == ""
    assert row["SweepAggregatePointStatus"] == "failed"
    assert row["SweepAggregateConfiguredSNR_dB"] == "-30.0"
    assert (done / "air_interface/csv/pbch_trials.csv").read_bytes() == original
    overview = read_rows(tmp_path / "reports/csv/sweep_link_comparison.csv")
    assert overview[0]["TrialCount"] == "0"
    assert overview[0]["AttemptBLER"] == overview[0]["MeanMeasuredSINR_dB"] == ""
    assert overview[0]["DataAvailability"] == "source_present_empty"
    assert len(overview) == 6
    assert {(r["PointIndex"], r["Direction"], r["DataAvailability"]) for r in overview[2:]} == {
        ("2", "DL", "not_completed"), ("2", "UL", "not_completed"),
        ("3", "DL", "not_completed"), ("3", "UL", "not_completed")}
    bler = read_rows(tmp_path / "reports/csv/sweep_bler_vs_configured_snr.csv")
    assert len(bler) == 6 and all("AttemptBLER_CI_Low" in row for row in bler)
    assert not read_rows(tmp_path / "reports/csv/sweep_bler_vs_measured_sinr.csv")


def test_union_schema_does_not_fill_missing_fields_with_zero(tmp_path):
    put_csv(tmp_path / "a.csv", ["MCS", "SINR"], [dict(MCS=0, SINR=-29.5)])
    put_csv(tmp_path / "b.csv", ["MCS", "Rank"], [dict(MCS=28, Rank=2)])
    sources = [(dict(index=i, label=str(i), configured_snr_db=s, status="passed", run_folder=str(tmp_path / str(i))),
                tmp_path / f, "trials.csv") for i, s, f in [(1, -30, "a.csv"), (2, 20, "b.csv")]]
    concatenate_csv(tmp_path / "combined.csv", sources)
    a, b = read_rows(tmp_path / "combined.csv")
    assert a["SINR"] == "-29.5" and a["Rank"] == ""
    assert b["Rank"] == "2" and b["SINR"] == ""


def test_export_bad_schema_is_reported_not_rescued(tmp_path):
    done, _ = fixture(tmp_path)
    put_csv(done / "bad.csv", ["Duplicate", "Duplicate"], [])
    receipt = export_sweep(tmp_path)
    assert receipt["FailedArtifacts"] == 1
    assert read_rows(tmp_path / "reports/csv/sweep_comparison_manifest.csv")[0]["Status"] == "failed"


def test_shared_png_contains_original_panels_and_manifest(tmp_path):
    from PIL import Image
    done, _ = fixture(tmp_path)
    done.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (32, 24), "red").save(done / "measurement.png")
    export_sweep(tmp_path)
    row, = read_rows(tmp_path / "reports/csv/sweep_comparison_manifest.csv")
    assert row["NotCompletedPoints"] == "2|3"
    with Image.open(tmp_path / row["CombinedArtifact"]) as image:
        assert image.getpixel((0, 38)) == (255, 0, 0)
        assert image.height == 24 + 48 + 2 * (65 + 48)


def test_all_eight_points_share_one_csv_and_png_without_overwriting_rows(tmp_path):
    from PIL import Image
    snrs = [40, 30, 20, 10, 0, -10, -20, -30]
    overrides = [dict(label=f"point_{i}", config={"simulation": {"snr_db": snr}})
                 for i, snr in enumerate(snrs, 1)]
    (tmp_path / "meta").mkdir()
    (tmp_path / "meta/scenario_config_resolved.json").write_text(json.dumps({
        "scenario": {"runner_profile": "generic_sweep", "sweep": {"overrides": overrides}}}))
    put_csv(tmp_path / "reports/csv/sweep_summary.csv", ["Label", "Ok"],
            [dict(Label=p["label"], Ok=1) for p in overrides])
    for i, snr in enumerate(snrs, 1):
        child = tmp_path / "sweeps" / f"point_{i}"
        put_csv(child / "trials.csv", ["Measurement"], [dict(Measurement=snr + 0.125)])
        # One completed point deliberately lacks its image. No substitute data.
        if i != 5:
            Image.new("RGB", (32, 24), (i * 20, 0, 0)).save(child / "measurement.png")
    receipt = export_sweep(tmp_path)
    assert receipt["Complete"] and receipt["CompletedPoints"] == 8
    manifest = {r["SourceRelativePath"]: r for r in read_rows(tmp_path / "reports/csv/sweep_comparison_manifest.csv")}
    assert len(manifest) == 2
    row = manifest["trials.csv"]
    assert row["SourcePoints"] == "1|2|3|4|5|6|7|8"
    assert row["MissingCompletedPoints"] == row["NotCompletedPoints"] == ""
    combined = read_rows(tmp_path / row["CombinedArtifact"])
    assert [float(r["SweepAggregateConfiguredSNR_dB"]) for r in combined] == snrs
    assert [float(r["Measurement"]) for r in combined] == [s + 0.125 for s in snrs]
    overview = read_rows(tmp_path / "reports/csv/sweep_link_comparison.csv")
    assert len(overview) == 16
    assert {float(r["ConfiguredSNR_dB"]) for r in overview} == set(snrs)
    assert all(r["DataAvailability"] == "source_missing" for r in overview)
    png = manifest["measurement.png"]
    assert png["MissingCompletedPoints"] == "5"
    with Image.open(tmp_path / png["CombinedArtifact"]) as image:
        assert image.height == 7 * (24 + 48) + 65 + 48


def test_standardized_measurements_publish_one_cross_point_csv_and_png(tmp_path):
    snrs = [40, 30, 20, 10, 0, -10, -20, -30]
    overrides = [dict(label=f"point_{i}", config={"simulation": {"snr_db": snr}})
                 for i, snr in enumerate(snrs, 1)]
    (tmp_path / "meta").mkdir()
    (tmp_path / "meta/scenario_config_resolved.json").write_text(json.dumps({
        "scenario": {"runner_profile": "generic_sweep", "sweep": {"overrides": overrides}}}))
    put_csv(tmp_path / "reports/csv/sweep_summary.csv", ["Label", "Ok"],
            [dict(Label=p["label"], Ok=1) for p in overrides])
    fields = ["CategoryCode", "CategoryKey", "CategoryName", "MetricKey", "MetricName",
              "Entity", "Statistic", "Availability", "CountsTowardCoverage",
              "ValueNumeric", "ValueText", "Unit", "SourceArtifact", "Notes"]
    for i, snr in enumerate(snrs, 1):
        rows = [dict(CategoryCode="A", CategoryKey="basic_phy", CategoryName="Basic PHY",
                     MetricKey="initial_bler", MetricName="Initial BLER", Entity="DL",
                     Statistic="rate", Availability="observed", CountsTowardCoverage=1,
                     ValueNumeric=i / 10, ValueText=i / 10, Unit="fraction",
                     SourceArtifact="air_interface/csv/dl_pdsch_trials.csv", Notes="")]
        if i == 1:
            rows.append(dict(CategoryCode="A", CategoryKey="basic_phy", CategoryName="Basic PHY",
                             MetricKey="configured_only", MetricName="Configured only", Entity="DL",
                             Statistic="value", Availability="config_only", CountsTowardCoverage=0,
                             ValueNumeric=7, ValueText=7, Unit="index",
                             SourceArtifact="meta/scenario_config_resolved.json", Notes="not measured"))
        put_csv(tmp_path / "sweeps" / f"point_{i}" / "reports/csv/basic_phy_outputs.csv",
                fields, rows)
    receipt = export_sweep(tmp_path)
    assert receipt["StandardizedMeasurementPlotCount"] == 1
    values = read_rows(tmp_path / "reports/csv/sweep_measurement_values.csv")
    assert len(values) == 8
    assert [float(row["ConfiguredSNR_dB"]) for row in values] == snrs
    assert {row["Availability"] for row in values} == {"observed"}
    availability = read_rows(tmp_path / "reports/csv/sweep_measurement_availability.csv")
    assert len(availability) == 9
    assert any(row["Availability"] == "config_only" for row in availability)
    manifest, = read_rows(tmp_path / "reports/csv/sweep_measurement_plot_manifest.csv")
    assert manifest["ObservedPointIndices"] == "1|2|3|4|5|6|7|8"
    assert manifest["MissingTerminalPointIndices"] == manifest["IncompletePointIndices"] == ""
    metric_rows = read_rows(tmp_path / manifest["CampaignCSV"])
    assert len(metric_rows) == 8
    assert (tmp_path / manifest["CampaignPNG"]).is_file()


def test_resolved_no_figures_policy_is_preserved(tmp_path):
    fixture(tmp_path)
    path = tmp_path / "meta/scenario_config_resolved.json"
    config = json.loads(path.read_text())
    config["output"] = {"save_figures": False}
    path.write_text(json.dumps(config))
    export_sweep(tmp_path)
    assert not (tmp_path / "reports/image").exists()
    assert (tmp_path / "reports/csv/sweep_link_comparison.csv").is_file()


def test_shared_bler_curves_use_observed_crc_and_separate_phy_populations(tmp_path):
    overrides = [dict(label="low", config={"simulation": {"snr_db": -10}}),
                 dict(label="high", config={"simulation": {"snr_db": 10}})]
    (tmp_path / "meta").mkdir()
    (tmp_path / "meta/scenario_config_resolved.json").write_text(json.dumps({
        "scenario": {"runner_profile": "generic_sweep", "sweep": {"overrides": overrides}}}))
    put_csv(tmp_path / "reports/csv/sweep_summary.csv", ["Label", "Ok"],
            [dict(Label="low", Ok=1), dict(Label="high", Ok=1)])
    put_csv(tmp_path / "sweeps/low/air_interface/csv/dl_pdsch_trials.csv",
            ["CRCPass", "MeasuredTrialSINR_dB", "MCSIndex", "Modulation", "Layers"], [
                dict(CRCPass=0, MeasuredTrialSINR_dB=-1.2, MCSIndex=0, Modulation="QPSK", Layers=1),
                dict(CRCPass=1, MeasuredTrialSINR_dB=-1.1, MCSIndex=0, Modulation="QPSK", Layers=1)])
    put_csv(tmp_path / "sweeps/high/air_interface/csv/dl_pdsch_trials.csv",
            ["CRCPass", "MeasuredTrialSINR_dB", "MCSIndex", "Modulation", "Layers"], [
                dict(CRCPass=1, MeasuredTrialSINR_dB=9.2, MCSIndex=10, Modulation="16QAM", Layers=2)])
    export_sweep(tmp_path)
    configured = read_rows(tmp_path / "reports/csv/sweep_bler_vs_configured_snr.csv")
    dl = [row for row in configured if row["Direction"] == "DL"]
    assert [float(row["AttemptBLER"]) for row in dl] == [0.5, 0.0]
    assert all(0 <= float(row["AttemptBLER_CI_Low"]) <= float(row["AttemptBLER_CI_High"]) <= 1
               for row in dl)
    measured = read_rows(tmp_path / "reports/csv/sweep_bler_vs_measured_sinr.csv")
    assert len(measured) == 2
    assert {(row["MCSIndex"], row["Modulation"], row["Rank"], row["TrialCount"]) for row in measured} == {
        ("0.0", "QPSK", "1.0", "2"), ("10.0", "16QAM", "2.0", "1")}
    assert all(row["EvidenceClass"] ==
               "cross_run_observed_crc_and_receiver_post_equalization_sinr" for row in measured)
    assert (tmp_path / "reports/image/sweep_bler_vs_configured_snr.png").is_file()
    assert (tmp_path / "reports/image/sweep_bler_vs_measured_sinr.png").is_file()


def test_gui_keeps_sweep_in_lite_and_renders_status_table():
    import lls_web_dashboard as dash
    assert dash.condense_live_payload({"sweep_progress": {"total": 8}})["sweep_progress"]["total"] == 8
    with patch.object(dash, "list_scenarios", return_value=["test.yaml"]):
        html = dash.build_product_frontend_page("realtime", "test.yaml", user_profile={"username": "test", "role": "Administrator"}).decode()
    assert "SNR sweep progress" in html and "sweepProgressPanel(live.sweep_progress)" in html
    assert "sweep_comparison_manifest.csv" in html
