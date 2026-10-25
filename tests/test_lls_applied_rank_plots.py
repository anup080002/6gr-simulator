"""Declared export fixtures plus optional retained MATLAB CSV; no new PHY."""
import copy
import csv
import hashlib
import io
import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_applied_rank_plots as rank
import lls_contract_materializer as m


def encode(rows):
    return m._encode_dict_rows(list(rows[0]), rows)


def fixture():
    rows = []
    for i, (layers, crc) in enumerate(((1, 1), (4, 0), ("NaN", 1)), 1):
        row = dict(Direction="DL", Layers=layers, CRCPass=crc, Status="PASS" if crc else "FAIL",
                   Slot=i, Goodput_Mbps=8/i, SweepPointIndex=i, ConfiguredSNR_dB=10*i,
                   ExecutionID=f"declared_point_{i}", ExecutionBackend="scheduler_shared_stream_receiver")
        row.update({field: 1 for field in ("FinalizedFlag", "DecodeAttempted", "DecodeUsable",
                    "DLSCHDecodeAttempted", "DLSCHDecodeAvailable", "CRCApplicable")})
        row.update({field: 0 for field in ("PartialRowFlag", "Crash", "IsWarmupFrame")})
        rows.append(row)
    rows[-1]["DecodeUsable"] = 0
    groups = [dict(Direction="DL", AppliedLayers=row["Layers"], SourceRowsJSON=str(i),
                   SourceObservationCount=1, CompletedDecodeAttemptCount=int(i < 3),
                   CRCErrorCount=int(i == 2), CompletedAttemptBLER=(i-1) if i < 3 else "NaN",
                   MeanTrialThroughput_Mbps=row["Goodput_Mbps"], StatisticalIndependenceClaimed=0,
                   Scope=rank.SCOPE) for i, row in enumerate(rows, 1)]
    return groups, rows


def run(groups, rows):
    return run_sources(groups, {"DL": rows})


def run_sources(groups, sources):
    payloads = {1: encode(groups)}
    existing = {rank.SOURCE: {"artifact_id": 1}}
    for index, (direction, rows) in enumerate(sources.items(), 2):
        payloads[index] = encode(rows)
        existing[rank.TRIALS[direction]] = {"artifact_id": index}
    result = m._specialized_chart_materialization(rank.CHART, existing, payloads.__getitem__, 1)
    _, plotted = m._decode_csv_dicts(result["csv_bytes"])
    return result, plotted


def ul_fixture():
    groups, rows = fixture()
    for group in groups:
        group["Direction"] = "UL"
    for row in rows:
        row["Direction"] = "UL"
        row["ULSCHDecodeAttempted"] = row.pop("DLSCHDecodeAttempted")
        row["ULSCHDecodeAvailable"] = row.pop("DLSCHDecodeAvailable")
    return groups, rows


def test_ul_and_dl_groups_keep_directional_membership_and_completed_outcomes_separate():
    groups, dl = fixture()
    ul_groups, ul = ul_fixture()
    result, plotted = run_sources(groups + ul_groups, {"DL": dl, "UL": ul})
    assert len(plotted) == 6
    assert [row["direction"] for row in plotted] == ["DL"]*3 + ["UL"]*3
    assert [row["completed_attempt_bler"] for row in plotted[3:]] == ["0.0", "1.0", ""]
    assert all(row["source_trial_csv"] == rank.TRIALS["UL"] for row in plotted[3:])
    assert all(row["source_trial_csv_sha256"] == hashlib.sha256(encode(ul)).hexdigest() for row in plotted[3:])
    assert b"UL layers=unknown" in result["img_bytes"]


@pytest.mark.parametrize("missing_crc", [False, True])
def test_ul_partial_or_missing_original_crc_cannot_support_group_denominator(missing_crc):
    groups, ul = ul_fixture()
    if missing_crc:
        ul[0]["CRCPass"] = ""
    else:
        ul[0]["PartialRowFlag"] = 1
    with pytest.raises(ValueError, match="CompletedDecodeAttemptCount"):
        run_sources(groups, {"UL": ul})


def test_no_original_group_source_is_explicitly_unavailable_not_rank_zero():
    result = m._specialized_chart_materialization(rank.CHART, {}, lambda _: pytest.fail("No source exists"), 1)
    assert result["source_row_count"] == 0 and result["csv_status"] == "unavailable_exact_reason"
    header, rows = m._decode_csv(result["csv_bytes"])
    assert header == ["status", "reason"] and rows[0][0] == "unavailable"
    assert "applied_layers" not in header and b"layers=0" not in result["img_bytes"]


def test_default_registered_consumer_retains_exact_groups_unknown_and_denominators():
    groups, rows = fixture()
    original = copy.deepcopy((groups, rows))
    result, plotted = run(groups, rows)
    assert [x["applied_layers"] for x in plotted] == ["1", "4", ""]
    assert [x["completed_attempt_bler"] for x in plotted] == ["0.0", "1.0", ""]
    assert "layers=unknown" in plotted[-1]["group_label"]
    assert all("layers=0" not in x["group_label"] for x in plotted)
    assert [json.loads(x["source_observation_identity_json"])[0]["SweepPointIndex"] for x in plotted] == ["1", "2", "3"]
    assert all(x["source_trial_csv_sha256"] == hashlib.sha256(encode(rows)).hexdigest() for x in plotted)
    assert all(x["source_group_csv_sha256"] == hashlib.sha256(encode(groups)).hexdigest() for x in plotted)
    assert (groups, rows) == original
    assert b"whole-run goodput" in result["img_bytes"]
    assert "configured SNR=" in plotted[0]["group_label"]
    assert b"Goodput_Mbps" in result["img_bytes"]
    assert m._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml").startswith(b"\x89PNG")
    assert any(s["chart_name"] == rank.CHART for s in m._chart_specs())


@pytest.mark.parametrize("mutation", ["membership", "duplicate", "omit", "denominator", "mean", "independence", "rank", "late"])
def test_corrupt_group_or_original_population_fails_closed(mutation):
    groups, rows = fixture()
    if mutation == "membership":
        groups[0]["SourceRowsJSON"] = "2"
    elif mutation == "duplicate":
        groups.append(copy.deepcopy(groups[0]))
    elif mutation == "omit":
        groups.pop()
    elif mutation == "denominator":
        groups[0]["CompletedDecodeAttemptCount"] = 10
    elif mutation == "mean":
        groups[0]["MeanTrialThroughput_Mbps"] = 100
    elif mutation == "independence":
        groups[0]["StatisticalIndependenceClaimed"] = 1
    elif mutation == "rank":
        rows[0]["Layers"] = 2.5
    else:
        rows = [copy.deepcopy(rows[0]) for _ in range(257)]
        rows[-1]["Layers"] = 4
        groups = [dict(groups[0], SourceRowsJSON=json.dumps(list(range(1, 258))),
                       SourceObservationCount=257, CompletedDecodeAttemptCount=257)]
    with pytest.raises(ValueError):
        run(groups, rows)


def test_mixed_point_source_group_is_explicit_not_relabelled_one_point():
    groups, rows = fixture()
    rows = rows[:2]
    rows[1]["Layers"] = 1
    groups = [dict(groups[0], SourceRowsJSON="[1,2]", SourceObservationCount=2,
                   CompletedDecodeAttemptCount=2, CRCErrorCount=1, CompletedAttemptBLER=.5,
                   MeanTrialThroughput_Mbps=6)]
    _, plotted = run(groups, rows)
    assert "mixed operating points (2)" in plotted[0]["group_label"]
    assert json.loads(plotted[0]["original_operating_points_json"]) == [["1", "10"], ["2", "20"]]


def test_offered_rate_fallback_keeps_its_original_operand_name_visible():
    groups, rows = fixture()
    for row in rows:
        row["OfferedThroughput_Mbps"] = row.pop("Goodput_Mbps")
    result, plotted = run(groups, rows)
    assert all(row["throughput_source_field"] == "OfferedThroughput_Mbps" for row in plotted)
    assert b"OfferedThroughput_Mbps" in result["img_bytes"]


def test_default_filesystem_materializer_writes_png_plotted_csv_and_exact_lineage(tmp_path, monkeypatch):
    groups, rows = fixture()
    inventory = []
    for index, (path, values) in enumerate(((rank.SOURCE, groups), (rank.TRIALS["DL"], rows)), 1):
        file = tmp_path / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(encode(values))
        inventory.append(dict(artifact_id=index, logical_path=path, filesystem_path=str(file),
                              artifact_kind="table_csv", mime_type="text/csv"))
    original_hashes = {p: hashlib.sha256((tmp_path/p).read_bytes()).hexdigest() for p in (rank.SOURCE, rank.TRIALS["DL"])}
    spec = next(s for s in m._chart_specs() if s["chart_name"] == rank.CHART)
    monkeypatch.setattr(m, "_chart_specs", lambda: [spec])
    monkeypatch.setattr(m, "_table_specs", lambda: [])
    result = m.materialize_filesystem_run_contract_artifacts(
        {"run_id": 1, "run_folder": str(tmp_path), "status_text": "completed"}, inventory, force=True)
    assert result["coverage"]["charts_available"] == 1
    csv_path = tmp_path / m.chart_contract_csv_path(spec)
    png_path = tmp_path / m.chart_contract_image_path(spec)
    assert png_path.read_bytes().startswith(b"\x89PNG")
    _, plotted = m._decode_csv_dicts(csv_path.read_bytes())
    assert len(plotted) == 3
    _, lineage = m._decode_csv_dicts((tmp_path / m.plot_lineage_logical_path()).read_bytes())
    assert len(lineage) == 1 and lineage[0]["SourceCSV_SHA256"] == hashlib.sha256(csv_path.read_bytes()).hexdigest()
    assert original_hashes == {p: hashlib.sha256((tmp_path/p).read_bytes()).hexdigest() for p in original_hashes}


def test_retained_v200_default_matlab_groups_no_new_phy_or_original_write():
    root = Path(__file__).resolve().parents[1] / "results/validation/csi_selection_identity/20261024_132354_776"
    if not (root/rank.SOURCE).is_file():
        pytest.skip("Optional retained v200 reporting fixture is not present.")
    paths = [rank.SOURCE, rank.TRIALS["DL"]]
    payloads = {i: (root/path).read_bytes() for i, path in enumerate(paths, 1)}
    before = {path: hashlib.sha256((root/path).read_bytes()).hexdigest() for path in paths}
    result = m._specialized_chart_materialization(rank.CHART,
        {path: {"artifact_id": i} for i, path in enumerate(paths, 1)}, payloads.__getitem__, 1)
    _, plotted = m._decode_csv_dicts(result["csv_bytes"])
    assert [x["applied_layers"] for x in plotted] == ["1", "4"]
    assert [x["completed_attempt_bler"] for x in plotted] == ["0.0", "1.0"]
    assert before == {path: hashlib.sha256((root/path).read_bytes()).hexdigest() for path in paths}
