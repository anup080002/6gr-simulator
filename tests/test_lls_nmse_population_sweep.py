"""Declared report rows only: population-preserving publication, not PHY proof."""
import csv
import math
from pathlib import Path
import sys
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_sweep_report as report


POPULATION_FIELDS = ["PopulationID", "PopulationJSON", "SupportConfigurationJSON",
                     "PopulationSeriesID", "PopulationSeriesJSON"]


def row(value, population="", *, metadata='{"RandomSeed":7}'):
    result = dict(CategoryCode="A", CategoryKey="channel", CategoryName="Channel",
                  MetricKey="nmse", MetricName="NMSE", Entity="TRS", Statistic="mean",
                  Availability="derived", CountsTowardCoverage="1", ValueNumeric=value,
                  ValueText=str(value), Unit="dB", SourceArtifact="reports/csv/channel_nmse_population_summary.csv",
                  Notes="Declared test report fixture, no PHY")
    if population:
        result.update(PopulationID=population, PopulationJSON=metadata,
                      SupportConfigurationJSON='{"Layers":1}')
    return result


def source(tmp_path, rows):
    root = tmp_path / "child"
    path = root / "reports/csv/channel_outputs.csv"
    path.parent.mkdir(parents=True)
    fields = list(report.STANDARD_MEASUREMENT_FIELDS)
    if any("PopulationID" in item for item in rows):
        fields += POPULATION_FIELDS
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    progress = dict(points=[dict(index=1, label="declared", configured_snr_db=0,
                                status="passed", run_folder=str(root))])
    return path, progress


def test_population_fields_and_statistics_survive_actual_sweep_entry(tmp_path):
    path, progress = source(tmp_path, [row(-10, "a" * 64), row(0, "b" * 64)])
    original = path.read_bytes()
    manifest, = report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)
    values = report.read_rows(tmp_path / manifest["CampaignCSV"])
    assert manifest["SeriesCount"] == 2
    assert [item["PopulationID"] for item in values] == ["a" * 64, "b" * 64]
    assert [float(item["ValueNumeric"]) for item in values] == [-10, 0]
    assert {item["Entity"] for item in values} == {"TRS"}
    assert {item["Statistic"] for item in values} == {"mean"}
    assert all(item["PopulationJSON"] == '{"RandomSeed":7}' for item in values)
    assert all(item["SupportConfigurationJSON"] == '{"Layers":1}' for item in values)
    assert all(item["EvidenceClass"] == "original_producer_contract_NMSE_report_reduction_not_new_PHY_execution" for item in values)
    assert path.read_bytes() == original


@pytest.mark.parametrize("count", [2, 13])
def test_scoped_plot_never_averages_incompatible_or_high_cardinality_populations(tmp_path, count):
    source_rows = [row(float(k), f"{k:064x}") for k in range(count)]
    _, progress = source(tmp_path, source_rows)
    _, values = report.standardized_measurement_rows(progress)
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots()
    with patch.object(plt, "subplots", return_value=(fig, ax)), patch.object(plt, "close"):
        report._plot_standardized_metric(tmp_path / "plot.png", progress, values, "Declared NMSE", "dB")
    # A population-mean line would be an unsupported new NMSE calculation.
    plotted = [float(y) for line in ax.lines for y in line.get_ydata()]
    plotted += [float(y) for collection in ax.collections for _, y in collection.get_offsets()]
    assert sorted(plotted) == list(map(float, range(count)))
    assert not any("population mean" in line.get_label() for line in ax.lines)
    assert (tmp_path / "plot.png").is_file()
    plt.close(fig)


def test_same_population_different_supplied_support_is_not_collapsed(tmp_path):
    first, second = row(-10, "a" * 64), row(0, "a" * 64)
    second["SupportConfigurationJSON"] = '{"Layers":2}'
    _, progress = source(tmp_path, [first, second])
    manifest, = report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)
    assert manifest["SeriesCount"] == 2


def test_same_series_different_supplied_support_is_not_collapsed(tmp_path):
    first, second = row(-10, "a" * 64), row(0, "b" * 64)
    for item in (first, second):
        item.update(PopulationSeriesID="c" * 64, PopulationSeriesJSON='{"scope":"declared"}')
    second["SupportConfigurationJSON"] = '{"Layers":2}'
    _, progress = source(tmp_path, [first, second])
    manifest, = report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)
    assert manifest["SeriesCount"] == 2


def test_legacy_schema_remains_valid_without_population_inference(tmp_path):
    legacy = row(-4); legacy.update(Availability="observed", SourceArtifact="original_legacy.csv")
    path, progress = source(tmp_path, [legacy])
    original = path.read_bytes()
    manifest, = report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)
    values = report.read_rows(tmp_path / manifest["CampaignCSV"])
    assert manifest["SeriesCount"] == 1
    assert len(values) == 1 and values[0]["ValueNumeric"] == "-4.0"
    assert all(values[0][field] == "" for field in POPULATION_FIELDS)
    assert path.read_bytes() == original


def test_legacy_nmse_rows_keep_each_original_value_across_points(tmp_path):
    points = []
    for index in [1, 2]:
        rows = [row(-10), row(0)]
        for item in rows:
            item.update(Availability="observed", SourceArtifact="original_legacy.csv")
        _, progress = source(tmp_path / f"p{index}", rows)
        progress["points"][0].update(index=index, configured_snr_db=index)
        points.extend(progress["points"])
    progress = dict(points=points)
    manifest, = report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)
    assert manifest["SeriesCount"] == 4
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots()
    _, values = report.standardized_measurement_rows(progress)
    with patch.object(plt, "subplots", return_value=(fig, ax)), patch.object(plt, "close"):
        report._plot_standardized_metric(tmp_path / "legacy.png", progress, values, "Declared", "dB")
    assert len(ax.lines) == 4 and all(len(line.get_xdata()) == 1 for line in ax.lines)
    assert sorted(float(line.get_ydata()[0]) for line in ax.lines) == [-10, -10, 0, 0]
    plt.close(fig)


def test_explicit_same_series_across_snr_keeps_incompatible_seed_cohorts_separate(tmp_path):
    points = []
    originals = []
    for point_index, snr in enumerate([0, 10], 1):
        rows = []
        for seed, value in [(7, -10 + snr), (8, -20 + snr)]:
            item = row(value, f"{point_index * 10 + seed:064x}",
                       metadata=f'{{"RandomSeed":{seed},"ConfiguredSNR_dB":{snr}}}')
            item.update(PopulationSeriesID=f"{seed:064x}", PopulationSeriesJSON=(
                f'{{"ReferencePlane":"declared_nominal_plane","RandomSeed":{seed},'
                '"ConfigHash":"original_config","SupportConfigurationJSON":"declared_support"}'))
            rows.append(item)
        path, progress = source(tmp_path / f"p{point_index}", rows)
        point = progress["points"][0]
        point.update(index=point_index, configured_snr_db=snr)
        points.append(point)
        originals.append((path, path.read_bytes()))
    progress = dict(points=points)
    manifest, = report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)
    assert manifest["SeriesCount"] == 2 and manifest["ObservedRowCount"] == 4
    published = report.read_rows(tmp_path / manifest["CampaignCSV"])
    assert len({item["PopulationID"] for item in published}) == 4
    assert len({item["PopulationSeriesID"] for item in published}) == 2
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots()
    _, values = report.standardized_measurement_rows(progress)
    with patch.object(plt, "subplots", return_value=(fig, ax)), patch.object(plt, "close"):
        report._plot_standardized_metric(tmp_path / "cross_point.png", progress, values, "Declared", "dB")
    assert len(ax.lines) == 2
    assert all(list(line.get_xdata()) == [0, 10] for line in ax.lines)
    assert sorted(list(line.get_ydata()) for line in ax.lines) == [[-20, -10], [-10, 0]]
    assert all(path.read_bytes() == original for path, original in originals)
    plt.close(fig)


def test_point_population_without_series_does_not_infer_cross_point_compatibility(tmp_path):
    _, progress = source(tmp_path, [row(-10, "a" * 64)])
    _, values = report.standardized_measurement_rows(progress)
    later = dict(values[0], PointIndex=2, ConfiguredSNR_dB=10)
    assert report._measurement_series_key(values[0]) != report._measurement_series_key(later)


@pytest.mark.parametrize("missing", ["PopulationSeriesID", "PopulationSeriesJSON"])
@pytest.mark.parametrize("availability,value", [("derived", -10), ("derived", float("-inf")), ("not_available", "")])
def test_partial_series_declaration_is_rejected_not_inferred(tmp_path, missing, availability, value):
    item = row(-10, "a" * 64)
    item.update(PopulationSeriesID="b" * 64, PopulationSeriesJSON='{"scope":"declared"}')
    item.update(Availability=availability, ValueNumeric=value)
    item[missing] = ""
    _, progress = source(tmp_path, [item])
    with pytest.raises(ValueError, match="original ID and definition together"):
        report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)


def test_exact_zero_nmse_retained_across_cohorts_and_snr_without_finite_plot_floor(tmp_path):
    points = []
    for index, snr in enumerate([0, 10], 1):
        rows = [row(float("-inf"), f"{index:064x}"), row(-10, f"{index+10:064x}")]
        for cohort, item in enumerate(rows, 1):
            item.update(PopulationSeriesID=f"{cohort:064x}",
                        PopulationSeriesJSON=f'{{"declared_cohort":{cohort}}}')
        path, progress = source(tmp_path / f"p{index}", rows)
        progress["points"][0].update(index=index, configured_snr_db=snr)
        points.extend(progress["points"])
    progress = dict(points=points)
    manifest, = report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)
    persisted = report.read_rows(tmp_path / manifest["CampaignCSV"])
    assert len(persisted) == 4 and sum(float(item["ValueNumeric"]) == float("-inf") for item in persisted) == 2
    assert manifest["SeriesCount"] == 2 and manifest["ObservedRowCount"] == 4
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots()
    _, values = report.standardized_measurement_rows(progress)
    with patch.object(plt, "subplots", return_value=(fig, ax)), patch.object(plt, "close"):
        report._plot_standardized_metric(tmp_path / "zero.png", progress, values, "Declared NMSE", "dB")
    assert len(ax.lines) == 1 and list(ax.lines[0].get_ydata()) == [-10, -10]
    annotations = " ".join(" ".join(text.get_text() for text in [*ax.texts, *fig.texts]).split())
    assert "Exact-zero NMSE: 2" in annotations and "no finite plotted floor" in annotations
    plt.close(fig)


def test_nonmeasurement_derived_or_proxy_rows_are_not_promoted(tmp_path):
    derived_other = row(3, "a" * 64)
    derived_other["MetricKey"] = "arbitrary_config_derived_metric"
    proxy = row(-10, "b" * 64)
    proxy["Availability"] = "fast_proxy"
    no_coverage = row(-10, "c" * 64)
    no_coverage["CountsTowardCoverage"] = "0"
    wrong_source = row(-10, "d" * 64)
    wrong_source["SourceArtifact"] = "proxy/reports/csv/channel_nmse_population_summary.csv"
    old_srs = row(-10, "e" * 64)
    old_srs["SourceArtifact"] = "air_interface/csv/srs_trials.csv"
    _, progress = source(tmp_path, [derived_other, proxy, no_coverage, wrong_source, old_srs])
    availability, measured = report.standardized_measurement_rows(progress)
    assert len(availability) == 5 and measured == []


def test_zero_error_breaks_curve_without_replacing_original_csv_value(tmp_path):
    points = []
    for index, value in enumerate([-10, float("-inf"), -20], 1):
        item = row(value, f"{index:064x}")
        item.update(PopulationSeriesID="a" * 64, PopulationSeriesJSON='{"scope":"declared"}')
        _, progress = source(tmp_path / f"p{index}", [item])
        progress["points"][0].update(index=index, configured_snr_db=index)
        points.extend(progress["points"])
    progress = dict(points=points)
    _, values = report.standardized_measurement_rows(progress)
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots()
    with patch.object(plt, "subplots", return_value=(fig, ax)), patch.object(plt, "close"):
        report._plot_standardized_metric(tmp_path / "gap.png", progress, values, "Declared NMSE", "dB")
    assert len(ax.lines) == 1
    ys = list(ax.lines[0].get_ydata())
    assert ys[0] == -10 and math.isnan(ys[1]) and ys[2] == -20
    assert values[1]["ValueNumeric"] == float("-inf")
    plt.close(fig)


def test_joint_child_original_source_points_override_only_plot_axis_not_wrapper_provenance(tmp_path):
    source_points = [0, 10, 10 + 1e-10]
    rows = []
    for index, snr in enumerate(source_points, 1):
        item = row(-index, f"{index:064x}", metadata=f'{{"ConfiguredSNR_dB":{snr},"RandomSeed":7}}')
        item.update(PopulationSeriesID="a" * 64, PopulationSeriesJSON='{"scope":"same_original_config_seed_support"}')
        rows.append(item)
    path, progress = source(tmp_path, rows)
    progress["points"][0]["configured_snr_db"] = -30
    original = path.read_bytes()
    manifest, = report.export_standardized_measurement_curves(tmp_path, progress, save_images=False)
    persisted = report.read_rows(tmp_path / manifest["CampaignCSV"])
    assert [float(item["ConfiguredSNR_dB"]) for item in persisted] == [-30] * 3
    assert [float(item["PublishedOperatingPoint_dB"]) for item in persisted] == source_points
    assert {item["PublishedOperatingPointField"] for item in persisted} == {"ConfiguredSNR_dB"}
    _, values = report.standardized_measurement_rows(progress)
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(10, 5.8))
    with patch.object(plt, "subplots", return_value=(fig, ax)), patch.object(plt, "close"):
        report._plot_standardized_metric(tmp_path / "joint.png", progress, values, "Declared NMSE", "dB")
    assert len(ax.lines) == 1 and list(ax.lines[0].get_xdata()) == source_points
    assert list(ax.get_xticks()) == source_points
    assert len({text.get_text() for text in ax.get_xticklabels()}) == 3
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    labels = [text.get_window_extent(renderer) for text in ax.get_xticklabels()]
    assert not any(a.overlaps(b) for i, a in enumerate(labels) for b in labels[i+1:])
    assert all(fig.bbox.contains(*corner) for bounds in labels for corner in [bounds.p0, bounds.p1])
    assert len({text.get_position()[1] for text in ax.get_xticklabels()}) == 2
    assert all(not text.get_window_extent(renderer).overlaps(ax.bbox) for text in fig.texts)
    assert all(not text.get_window_extent(renderer).overlaps(ax.xaxis.label.get_window_extent(renderer))
               for text in fig.texts)
    assert all(fig.bbox.contains(*corner) for text in fig.texts
               for corner in [text.get_window_extent(renderer).p0, text.get_window_extent(renderer).p1])
    assert path.read_bytes() == original
    plt.close(fig)


def test_source_legacy_snr_role_and_wrapper_fallback_are_explicit(tmp_path):
    rows = [row(-1, "a" * 64, metadata='{"SNR_dB":12}'),
            row(-2, "b" * 64, metadata='{"ConfiguredSNR_dB":null}'),
            row(-3, "c" * 64, metadata='{"ConfiguredSNR_dB":5,"SNR_dB":12}')]
    _, progress = source(tmp_path, rows)
    _, values = report.standardized_measurement_rows(progress)
    assert values[0]["PublishedOperatingPointField"] == "SNR_dB"
    assert values[0]["PublishedOperatingPointRole"] == "source_SNR_metadata_not_measured_SINR"
    assert values[1]["PublishedOperatingPoint_dB"] == ""
    assert [report._plot_operating_point(item) for item in values] == [12, 0, 5]


@pytest.mark.parametrize("metadata", ["not-json", "[]", '{"ConfiguredSNR_dB":[1]}',
                                      '{"ConfiguredSNR_dB":true}', '{"ConfiguredSNR_dB":"5"}',
                                      '{"ConfiguredSNR_dB":NaN}', '{"ConfiguredSNR_dB":Infinity}'])
def test_malformed_source_axis_is_not_replaced_by_wrapper(tmp_path, metadata):
    _, progress = source(tmp_path, [row(-10, "a" * 64, metadata=metadata)])
    with pytest.raises(ValueError, match="Original"):
        report.standardized_measurement_rows(progress)
