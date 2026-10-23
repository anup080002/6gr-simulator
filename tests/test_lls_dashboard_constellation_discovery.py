"""Declared CSV/schema fixtures: dashboard publication, not waveform qualification."""
from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps"))
import lls_web_dashboard as dash


def artifact(tmp_path, logical, rows, *, run=11, artifact_id=1, header=None):
    path = tmp_path / f"run-{run}" / logical
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=header or list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    return dict(logical_path=logical, filesystem_path=str(path), run_id=run,
                artifact_id=artifact_id, artifact_kind="table_csv", mime_type="text/csv",
                byte_size=path.stat().st_size, created_utc="2026-10-23T00:00:00Z",
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def iq():
    return dict(RawEqualizedReal="0.25", RawEqualizedImag="-0.5", EqualizedReal="99",
                EqualizedImag="88", ReferenceSymbolReal="77", ReferenceSymbolImag="66",
                HardDecisionReal="55", HardDecisionImag="44", SourceRunID="declared-run",
                ExecutionID="declared-execution", SweepPointIndex="1", RandomSeed="17",
                Direction="UL", LayerIndex="1", OFDMSymbolIndex="2", SubcarrierIndex="3",
                SymbolCoordinateDomain="layer_resource_elements", SymbolOrderLinearIndex="7",
                SymbolOrderLinearIndexDomain="layer_grid_linear_index", CaptureScope="full_allocation",
                ObservationID="declared-observation")


@pytest.mark.parametrize("direction", ["dl", "ul"])
def test_full_source_discovery_chart_and_download(tmp_path, direction):
    source = artifact(tmp_path, f"air_interface/csv/{direction}_constellation_samples.csv",
                      [dict(iq(), Direction=direction.upper())], artifact_id=101)
    preview = artifact(tmp_path, f"air_interface/csv/{direction}_constellation_preview.csv",
                       [dict(iq(), Direction=direction.upper())], artifact_id=102)
    source["byte_size"] = 25_000_000  # Exercise the bounded large-file discovery branch.
    descriptors = [dash.build_artifact_descriptor(row) for row in (preview, source)]
    selected = dash.dedupe_table_descriptors_for_ui(descriptors)
    assert len(selected) == 1 and selected[0]["artifact_id"] == 101
    assert selected[0]["section"] == "constellation"
    assert selected[0]["constellation_alternate_sources"][0]["download_url"] == dash.artifact_url(102, download=True)
    assert dash.result_artifact_display_priority("constellation", source["logical_path"]) < dash.result_artifact_display_priority("constellation", preview["logical_path"])
    shortlisted = dash.shortlist_reference_gallery_chart_artifacts(selected)
    assert [row["artifact_id"] for row in shortlisted] == [101]
    browser = dash.plot_browser_chart_table_artifacts(descriptors, shortlisted)
    assert [row["artifact_id"] for row in browser] == [101]
    chart, = dash.build_numeric_charts_from_artifacts(browser)
    assert chart["source_kind"] == "samples" and chart["image_scope"] == "preview_only"
    assert chart["download_scope"] == "entire_original_source_csv"
    assert chart["download_url"] == dash.artifact_url(101, download=True)
    assert chart["constellation_alternate_sources"][0]["artifact_id"] == 102
    point, = chart["series"][0]["points"]
    assert (point["x"], point["y"]) == (.25, -.5)
    assert "bounded" in chart["title"]
    gallery = dash.build_reference_plot_gallery([chart], [])
    match, = [item for item in gallery["items"] if item["reference_id"] == "constellation"]
    assert match["chart"]["artifact_id"] == 101


def test_preview_only_is_never_labeled_full(tmp_path):
    source = artifact(tmp_path, "air_interface/csv/ul_constellation_preview.csv", [iq()])
    chart, = dash.build_numeric_charts_from_artifacts([source])
    assert chart["source_kind"] == "preview"
    assert "preview-source CSV" in dash.friendly_artifact_label(source["logical_path"])
    assert chart["image_scope"] == "preview_only"


def test_directional_source_cannot_relabel_receiver_rows(tmp_path):
    source = artifact(tmp_path, "air_interface/csv/dl_constellation_samples.csv", [iq()])
    chart = dash.build_numeric_chart_from_artifact(source)
    assert chart["status"] == "unavailable_receiver_iq_preview" and not chart["series"]
    assert "direction contradicts" in chart["reason"]


@pytest.mark.parametrize("case", ["header_only", "tx_only", "half_raw", "nonfinite_raw"])
def test_unusable_full_never_silently_falls_back_to_preview_or_tx(tmp_path, case):
    row = iq()
    if case == "tx_only":
        row = {name: value for name, value in row.items() if "Equalized" not in name}
    elif case == "half_raw":
        del row["RawEqualizedImag"]
    elif case == "nonfinite_raw":
        row["RawEqualizedReal"] = "NaN"
    source = artifact(tmp_path, "air_interface/csv/ul_constellation_samples.csv",
                      [] if case == "header_only" else [row], header=list(row))
    preview = artifact(tmp_path, "air_interface/csv/ul_constellation_preview.csv", [iq()], artifact_id=2)
    chart, = dash.build_numeric_charts_from_artifacts([preview, source])
    assert chart["artifact_id"] == 1 and not chart["series"]
    assert chart["status"] == "unavailable_receiver_iq_preview"
    assert chart["constellation_alternate_sources"][0]["source_kind"] == "preview"
    gallery = dash.build_reference_plot_gallery([chart], [])
    assert next(item for item in gallery["items"] if item["reference_id"] == "constellation")["status"] == "unavailable"


def test_legacy_receiver_schema_not_reference_fallback(tmp_path):
    row = {key: value for key, value in iq().items() if not key.startswith("RawEqualized")}
    source = artifact(tmp_path, "reports/csv/equalized_constellations.csv", [row])
    chart = dash.build_numeric_chart_from_artifact(source)
    assert (chart["series"][0]["points"][0]["x"], chart["series"][0]["points"][0]["y"]) == (99, 88)
    assert "equalizedreal" in chart["series"][0]["name"]
    assert chart["source_kind"] == "legacy_combined"


def test_canonical_report_missing_raw_iq_does_not_substitute_aligned_symbols(tmp_path):
    # Real canonical schema permits aligned Equalized* with unavailable Raw*.
    # This declared fixture verifies discovery does not change that evidence plane.
    row = dict(iq(), RawEqualizedReal="NaN", RawEqualizedImag="NaN",
               EqualizationSource="payload_aligned", Normalization="aligned_payload_fit")
    source = artifact(tmp_path, "reports/csv/equalized_constellations.csv", [row])
    assert dash.classify_result_section(source["logical_path"]) == "constellation"
    chart = dash.build_numeric_chart_from_artifact(source)
    assert chart["status"] == "unavailable_receiver_iq_preview" and not chart["series"]
    assert chart["omitted_nonfinite_receiver_rows"] == 1


def test_actual_joint_sweep_wrapper_names_are_retained_as_separate_scope(tmp_path):
    from lls_sweep_report import PROVENANCE
    assert set(PROVENANCE).issubset(dash.CONSTELLATION_PREVIEW_COHORT_FIELDS)
    wrappers = dict(zip(PROVENANCE, ["1", "declared-point-A", "0", "sweeps/A/ul_constellation_samples.csv", "passed"]))
    rows = [dict(iq(), **wrappers), dict(iq(), **dict(wrappers, SweepAggregateLabel="declared-point-B")),
            dict(iq(), **dict(wrappers, SweepAggregatePointStatus="failed"))]
    source = artifact(tmp_path, "air_interface/csv/ul_constellation_samples.csv", rows)
    chart = dash.build_numeric_chart_from_artifact(source)
    assert len(chart["series"]) == 3
    assert all("SweepPointIndex=1" in trace["name"] for trace in chart["series"])
    assert "SweepAggregateLabel=declared-point-B" in chart["series"][1]["name"]
    assert "SweepAggregatePointStatus=failed" in chart["series"][2]["name"]


def test_bounded_preview_never_changes_full_csv(tmp_path, monkeypatch):
    monkeypatch.setattr(dash, "MAX_ACTIVITY_POINTS", 2)
    source = artifact(tmp_path, "air_interface/csv/ul_constellation_samples.csv", [iq()] * 5)
    before = Path(source["filesystem_path"]).read_bytes()
    chart = dash.build_numeric_chart_from_artifact(source)
    assert len(chart["series"][0]["points"]) == 2
    assert chart["source_rows_previewed"] == 2 and chart["preview_row_limit"] == 2
    assert Path(source["filesystem_path"]).read_bytes() == before
    assert len(list(csv.DictReader(before.decode().splitlines()))) == 5


def test_actual_supplied_cohort_and_coordinate_tokens_remain_distinct(tmp_path):
    rows = [iq(), dict(iq(), RandomSeed="18"), dict(iq(), SweepPointIndex="2"),
            dict(iq(), ExecutionID="another-execution"), dict(iq(), SourceRunID="another-run"),
            dict(iq(), SubcarrierIndex="NaN", SymbolCoordinateDomain="pre_transform_qam_positions",
                 SymbolOrderLinearIndexDomain="native_pre_transform_allocation_position_key"),
            dict(iq(), CaptureScope="preview")]
    source = artifact(tmp_path, "air_interface/csv/ul_constellation_samples.csv", rows)
    chart = dash.build_numeric_chart_from_artifact(source)
    assert len(chart["series"]) == len(rows)
    points = [trace["points"][0] for trace in chart["series"]]
    assert [point["source_row_index"] for point in points] == list(range(1, 8))
    assert points[5]["retained_coordinates_and_capture"]["SubcarrierIndex"] == "NaN"
    assert points[5]["retained_coordinates_and_capture"]["SymbolOrderLinearIndex"] == "7"
    assert points[5]["retained_coordinates_and_capture"]["ObservationID"] == "declared-observation"


def test_direction_run_root_and_sweep_scopes_not_deduplicated(tmp_path):
    paths = ["air_interface/csv/ul_constellation_samples.csv",
             "air_interface/csv/dl_constellation_samples.csv",
             "sweeps/p1/air_interface/csv/ul_constellation_samples.csv",
             "sweeps/p2/air_interface/csv/ul_constellation_preview.csv"]
    sources = [artifact(tmp_path, path, [iq()], artifact_id=i) for i, path in enumerate(paths, 1)]
    sources += [artifact(tmp_path, paths[0], [iq()], run=12, artifact_id=5)]
    assert len(dash.prefer_raw_constellation_sources(sources)) == 5
    assert len(dash.build_numeric_charts_from_artifacts(sources)) == 5
    # Same supplied run ID is insufficient when actual file roots differ.
    other_root = artifact(tmp_path / "other", "air_interface/csv/ul_constellation_preview.csv", [iq()], artifact_id=6)
    assert len(dash.prefer_raw_constellation_sources([sources[0], other_root])) == 2


def test_unbound_artifact_names_are_not_cross_run_equivalence():
    sources = [dict(artifact_id=index, logical_path=f"air_interface/csv/ul_constellation_{kind}.csv")
               for index, kind in enumerate(("samples", "preview"), 1)]
    assert len(dash.prefer_raw_constellation_sources(sources)) == 2


@pytest.mark.parametrize("mutation,expected", [("exact", 1), ("undeclared", 2), ("hash", 2), ("run", 2), ("direction", 2)])
def test_only_declared_same_scope_byte_equal_alias_is_hidden(tmp_path, mutation, expected):
    source = artifact(tmp_path, "air_interface/csv/ul_constellation_samples.csv", [iq()])
    alias = artifact(tmp_path, "reports/csv/equalized_constellations.csv", [iq()], artifact_id=2)
    alias["source_csv"] = source["logical_path"]
    if mutation == "undeclared":
        del alias["source_csv"]
    elif mutation == "hash":
        alias["sha256"] = "f" * 64
    elif mutation == "run":
        alias["run_id"] = 99
    elif mutation == "direction":
        alias["source_csv"] = "air_interface/csv/dl_constellation_samples.csv"
    assert len(dash.prefer_raw_constellation_sources([alias, source, dict(source)])) == expected


def _javascript_function(script, name):
    match = re.search(r"function " + name + r"\([^\n]*\).*?^\}", script, re.M | re.S)
    assert match, name
    return match.group(0)


def test_table_javascript_uses_receiver_columns_and_explicit_preview_scope():
    node = shutil.which("node")
    if not node:
        # The installed Playwright driver ships Node even when it is not on PATH.
        spec = importlib.util.find_spec("playwright")
        if spec and spec.origin:
            driver = Path(spec.origin).parent / "driver"
            node = next((str(driver / name) for name in ("node.exe", "node") if (driver / name).is_file()), None)
    if not node:
        pytest.skip("Node required to execute the actual dashboard chart functions")
    script = dash.result_page_script(11)
    assert "Scenario Validation Mode · ${runClass}" in script
    assert "exported PNGs are preview-only" in script
    assert "Receiver-IQ preview (bounded rows; not full-capture validation)" in script
    assert "Download alternate preview CSV (not full capture)" in script
    assert "Live constellation scatter" not in script
    assert "constellation_preview.csv')) && size <= 2303" not in script
    functions = "\n".join(_javascript_function(script, name) for name in
                          ("parseResultNumber", "buildResultChartModel", "buildConstellationTraces"))
    row = iq()
    payload = dict(meta=dict(logical_path="air_interface/csv/ul_constellation_samples.csv"),
                   header=list(row), rows=[list(row.values()), list(dict(row, RandomSeed="18").values())])
    exercise = """
const m = buildResultChartModel(p);
const t = buildConstellationTraces(p, m.lowered);
if (m.kind !== 'constellation' || t.length !== 2 || t[0].x[0] !== .25 || t[0].y[0] !== -.5) throw Error('receiver/cohort');
p.rows.forEach((row) => row[p.header.indexOf('RawEqualizedReal')] = '');
if (buildConstellationTraces(p, m.lowered).length) throw Error('blank became zero');
p.header[p.header.indexOf('RawEqualizedImag')] = 'notReceiver';
if (buildConstellationTraces(p, buildResultChartModel(p).lowered).length) throw Error('raw fallback');
p.header = ['ReferenceSymbolReal', 'ReferenceSymbolImag']; p.rows = [['1','2']];
if (buildResultChartModel(p).kind !== 'constellation' || buildConstellationTraces(p, ['referencesymbolreal','referencesymbolimag']).length) throw Error('TX fallback');
"""
    subprocess.run([node, "-e", functions + "\nconst p=" + json.dumps(payload) + ";\n" + exercise], check=True, capture_output=True, text=True)
