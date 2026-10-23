"""Consumer-contract tests only: fixtures are not simulated PHY results.

Actual native archive acceptance is checked separately against retained MATLAB
execution outputs. These fixtures exercise serialization, identity and guards.
"""
from __future__ import annotations

import copy
import csv
import hashlib
import io
import json
import math
import struct
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps"))
import lls_contract_materializer as m
import lls_csi_selection_quality as quality
import lls_output_contract as contract
import lls_contract_aliases as aliases


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encode(rows, header=None):
    return m._encode_dict_rows(header or list(rows[0]), rows)


def decode(data):
    if hasattr(data, "read"):
        data.seek(0); data = data.read()
    return m._decode_csv_dicts(data)[1]


def real_array(values, shape):
    raw = struct.pack("<"+"d"*len(values), *values)
    descriptor = dict(Class="double", Shape=shape, RealBytesSHA256=sha(raw), ImagBytesSHA256=sha(bytes(len(raw))))
    return json.dumps(dict(Contract="sixgr_real_array_column_major/v1", Class="double", Shape=shape,
                          ColumnMajorValues=values, SHA256=sha(json.dumps(descriptor, separators=(",", ":")).encode())))


def matrix(rank, phase=1):
    nr = 2
    real = [phase/math.sqrt(2), 1/math.sqrt(2)] if rank == 1 else [1/math.sqrt(2), 0, 0, 1/math.sqrt(2)]
    imag = [0]*len(real)
    digest = sha(f"sixgr-mimo-matrix-v1|double|[{nr} {rank}]|".encode()+
                 struct.pack("<"+"d"*len(real), *real)+struct.pack("<"+"d"*len(imag), *imag))
    return digest, json.dumps(dict(ContractVersion="sixgr_complex_matrix/v1", Rows=nr, Columns=rank,
                                  RealColumnMajor=real, ImagColumnMajor=imag, MatrixSHA256=digest))


def fixture(point=1, seed=7, window="rx-window-1", snr=-10, run="component-fixture"):
    """Plain serialized consumer fixture; does not assert waveform execution."""
    identity = dict(RunID=run, ExecutionID="fixture-execution", ConfigHash=sha(b"config"), RandomSeed=seed,
                    ChannelSeed=9, SweepPointIndex=point, ConfiguredSNR_dB=snr, UEIndex=1, CellID=1,
                    ResourceID="CSI-RS-4", ResourceOrdinal0=0, ObservationID="local-repeatable-id",
                    MeasurementID="measurement-1", MeasurementDigest=sha(b"measurement"), ReportConfigID="report-1",
                    RequestSHA256=sha(b"request"), ConfigurationEpoch=0, ReceiverID="ue-1",
                    ReceiverWindowID=window, ReceiverClockDomain="shared_physical_sample_clock/v1", ReceiverClockEpoch=0,
                    ObservationStartSample=100, ObservationEndSampleExclusive=200, SampleRateHz=30.72e6,
                    ObservationSHA256=sha(b"capture"))
    # Native digest is typed/class-aware, not a hash of the JSON token. This
    # fixture uses a deterministic opaque marker for that archive boundary.
    identity_sha = sha(b"component-fixture-native-typed-digest:"+json.dumps(identity, sort_keys=True).encode())
    operand_sha = sha(b"component fixture operands"+identity_sha.encode())
    fields = dict(ReferencePlane="nominal_linear_CSI_RS_port_channel_on_actual_RX_FFT_clock", Scope=quality.SCOPE,
                  ObjectiveClassification="IMPLEMENTATION_POLICY_NOT_NR_NORMATIVE_OPTIMALITY",
                  CandidateDomainSHA256=sha(b"candidate domain"), ChannelSHA256=sha(b"channel"),
                  PortToPhysicalMatrixSHA256=sha(b"map"), PhysicalPowerReferencePlane=quality.PLANE,
                  PhysicalPowerUnit="normalized_grid_coefficient_squared_units",
                  PowerNormalization="unit_physical_chain_grid_coefficient_power")
    candidates = []
    for index, (rank, pmi, sinr) in enumerate(((1, 0, [1, 3]), (1, 1, [3, 7]), (2, 0, [3, 3, 3, 3]))):
        per_support = [sum(math.log2(1+sinr[q+2*l]) for l in range(rank)) for q in range(2)]
        matrix_sha, matrix_json = matrix(rank, 1 if index == 0 else -1)
        candidates.append(dict(Rank=rank, PMI=pmi, PMIComponentsJSON="{}", MatrixSHA256=matrix_sha,
            CodebookSpecification="consumer_fixture_not_PHY_execution", LogicalFrobeniusPower=1,
            UnscaledPhysicalFrobeniusPower=4, AppliedAmplitudeFactor=.5, ScoredPhysicalFrobeniusPower=1,
            Objective_bpsHz=sum(per_support)/2, SelectedByReceiver=index == 0,
            WithinJointTie=index == 2, WithinReportedRankTie=index == 1,
            SupportObjectiveJSON=real_array(per_support, [2, 1]), LayerSINRJSON=real_array(sinr, [2, rank]),
            CandidateMatrixJSON=matrix_json, **identity,
            CSISelectionQualityObservationID=identity["ObservationID"], IdentitySHA256=identity_sha,
            OperandSetSHA256=operand_sha, **fields, SupportJSON=real_array([0, 2, 4, 4], [2, 2]),
            StatisticallyQualified=False, EvidenceRole=quality.ROLE))
    csv_path = f"beamforming/csv/csi_selection_quality_{identity_sha}.csv"
    mat_path = f"beamforming/mat/csi_selection_quality_{identity_sha}.mat"
    candidate_bytes = encode(candidates)
    # The consumer checks bytes only; deliberately not a fabricated MATLAB
    # simulation archive. No test presents this fixture as real RF evidence.
    mat_bytes = b"component-test opaque native-archive boundary "+identity_sha.encode()
    row = dict(identity)
    row.update(ResourceID=4, CRI=0, Slot=1, CSIMeasurementID=identity["MeasurementID"],
               CSIMeasurementDigest=identity["MeasurementDigest"], CSIConfigurationEpoch=0, CSIReportConfigID="report-1",
               ObservationSampleRateHz=identity["SampleRateHz"], ReceiverObservationSHA256=identity["ObservationSHA256"])
    row.update({quality.PREFIX+k: v for k, v in fields.items()})
    row.update(CSISelectionQualityAvailable=True, CSISelectionQualityStatus="archived_private_UE_selection_quality_not_delivery_or_grant",
        CSISelectionQualityIdentityJSON=json.dumps(identity), CSISelectionQualityObservationID=identity["ObservationID"],
        CSISelectionQualityIdentitySHA256=identity_sha, CSISelectionQualityOperandSetSHA256=operand_sha,
        CSISelectionQualityMATFile=mat_path, CSISelectionQualityMATFileSHA256=sha(mat_bytes),
        CSISelectionQualityCandidatesCSV=csv_path, CSISelectionQualityCandidatesCSVSHA256=sha(candidate_bytes),
        CSISelectionQualityCandidateCount=3, CSISelectionQualitySupportCount=2,
        CSISelectionQualityLegalRankDomainJSON=real_array([1, 2], [1, 2]),
        CSISelectionQualitySelectedRank=1, CSISelectionQualitySelectedPMI=0,
        CSISelectionQualitySelectedPMIComponentsJSON="{}", CSISelectionQualitySelectedMatrixSHA256=candidates[0]["MatrixSHA256"],
        CSISelectionQualitySelectedObjective_bpsHz=1.5, CSISelectionQualityBestReportedRankObjective_bpsHz=2.5,
        CSISelectionQualityBestJointObjective_bpsHz=4, CSISelectionQualityConditionalPMIRegret_bpsHz=1,
        CSISelectionQualityRankRegret_bpsHz=1.5, CSISelectionQualityJointRegret_bpsHz=2.5,
        CSISelectionQualityStatisticallyQualified=False, CSISelectionQualityActualPDSCHPerformanceQualified=False,
        CSISelectionQualityCQIBLERQualified=False, CSISelectionQualityCRISelectionQualified=False)
    return row, {csv_path: candidate_bytes, mat_path: mat_bytes}


def inputs(rows, archives, source=quality.SOURCES[1]):
    sources = {source: encode(rows), **archives}
    blobs = {i: data for i, data in enumerate(sources.values(), 1)}
    existing = {path: dict(artifact_id=i, logical_path=path, artifact_kind="table_csv" if path.endswith("csv") else "mat_binary")
                for i, path in enumerate(sources, 1)}
    return existing, blobs.__getitem__


def chart(rows, archives, source=quality.SOURCES[1]):
    existing, fetch = inputs(rows, archives, source)
    return quality.chart_materialization(quality.CHART, existing, fetch, 99)


def test_complete_populations_roundtrip_all_points_without_reduction_or_series_cap():
    rows = []; archives = {}
    for point in range(1, 10):
        for seed in (7, 8):
            row, files = fixture(point, seed, window="same-local-window", snr=10-point)
            rows.append(row); archives.update(files)
    result = chart(rows, archives)
    plotted = decode(result["csv_bytes"])
    assert len(plotted) == 54 and result["source_row_count"] == 18
    assert {r["RandomSeed"] for r in plotted} == {"7", "8"}
    assert {r["SweepPointIndex"] for r in plotted} == set(map(str, range(1, 10)))
    assert len({r["identity_sha256"] for r in plotted}) == 18
    assert {r["y_value"] for r in plotted} == {"1.0", "1.5", "2.5"}
    assert all(r["evidence_role"] == quality.ROLE and r["source_mapping_status"] == "exact" for r in plotted)
    assert b"PRIVATE RETROSPECTIVE AUDIT" in result["img_bytes"] and b"not received UCI" in result["img_bytes"]
    assert b"point 9" in result["img_bytes"] and b"seed 8" in result["img_bytes"]
    png = m._rasterize_contract_png(result["img_bytes"], source_mime_type="image/svg+xml")
    assert png.startswith(b"\x89PNG\r\n\x1a\n")
    header, values = m._decode_csv(result["csv_bytes"])
    interactive = quality.numeric_chart(header, values)
    assert len(interactive["series"]) == 54 and sum(len(s["points"]) for s in interactive["series"]) == 54


def test_public_owner_aliases_keep_source_run_separate_from_publication_run():
    row, archives = fixture()
    row["SourceRunID"] = row.pop("RunID"); row["RunId"] = "publication-container"
    row["RunID"] = "publication-container-uppercase"
    row["UEId"] = row.pop("UEIndex"); row["CellId"] = row.pop("CellID"); row["ResourceId"] = row.pop("ResourceID")
    for field in ("RequestSHA256", "MeasurementID", "MeasurementDigest", "ConfigurationEpoch", "ReportConfigID", "SampleRateHz", "ObservationSHA256"):
        row.pop(field, None)
    result = chart([row], archives, quality.SOURCES[0])
    assert result["source_row_count"] == 1
    assert decode(result["csv_bytes"])[0]["RunID"] == "component-fixture"


def test_json_token_digest_is_distinct_from_native_typed_identity_digest():
    row, archives = fixture()
    # Whitespace is semantically irrelevant to the native typed identity but
    # remains exact bytes of the retained JSON token in the browser dataset.
    row["CSISelectionQualityIdentityJSON"] = "  "+row["CSISelectionQualityIdentityJSON"]+"\n"
    existing, fetch = inputs([row], archives)
    observations, _, _ = quality.collect(existing, fetch)
    assert len(observations) == 1
    observation = observations[0]
    assert observation["identity_json_sha256"] == sha(row["CSISelectionQualityIdentityJSON"].encode())
    assert observation["identity_json_sha256"] != observation["identity_sha256"]
    assert "not_JSON_token_SHA256" in observation["identity_hash_contract"]


@pytest.mark.parametrize("field", ["ConfigHash", "RequestSHA256", "ObservationSHA256", "MeasurementDigest"])
def test_invalid_required_identity_digest_is_diagnostic(field):
    row, archives = fixture()
    identity = json.loads(row["CSISelectionQualityIdentityJSON"]); identity[field] = "not-a-digest"
    row["CSISelectionQualityIdentityJSON"] = json.dumps(identity)
    existing, fetch = inputs([row], archives)
    observations, audit, _ = quality.collect(existing, fetch)
    assert not observations and "Invalid SHA256 "+field in audit[0]["reason"]


@pytest.mark.parametrize("field,value", [("Source", "synthetic_component"), ("ApproximationMode", "fast_proxy"),
                                         ("ExecutionBackend", "fallback"), ("TruthStatus", "lut")])
def test_non_runtime_marker_never_promoted_to_private_physical_observation(field, value):
    row, archives = fixture(); row[field] = value
    existing, fetch = inputs([row], archives)
    observations, audit, _ = quality.collect(existing, fetch)
    assert not observations and "Non-runtime provenance" in audit[0]["reason"]


@pytest.mark.parametrize("field,value", [
    ("RandomSeed", 99), ("SweepPointIndex", 2), ("ReceiverWindowID", "wrong"),
    ("ReceiverClockEpoch", 8), ("ResourceID", 5), ("ObservationStartSample", 101),
    ("CSISelectionQualityJointRegret_bpsHz", 0), ("CSISelectionQualityCandidateCount", 2),
    ("CSISelectionQualityStatisticallyQualified", True),
    ("CSISelectionQualityReferencePlane", "post_equalizer_RF"),
    ("CSISelectionQualityPhysicalPowerUnit", "actual_PDSCH_mW"),
])
def test_owner_mismatch_is_only_diagnostic_not_zero_or_valid_plot(field, value):
    row, archives = fixture(); row[field] = value
    existing, fetch = inputs([row], archives)
    observations, audit, _ = quality.collect(existing, fetch)
    assert not observations and len(audit) == 1 and audit[0]["source_mapping_status"] == "invalid"
    result = quality.chart_materialization(quality.CHART, existing, fetch, 99)
    assert result["no_plot"] and "img_bytes" not in result and not decode(result["csv_bytes"])


@pytest.mark.parametrize("kind", ["csv", "mat"])
def test_archive_byte_corruption_rejected(kind):
    row, archives = fixture()
    path = row["CSISelectionQualityCandidatesCSV" if kind == "csv" else "CSISelectionQualityMATFile"]
    archives[path] += b"corruption"
    existing, fetch = inputs([row], archives)
    observations, audit, _ = quality.collect(existing, fetch)
    assert not observations and "checksum mismatch" in audit[0]["reason"]


@pytest.mark.parametrize("change", ["identity", "support", "layer", "matrix", "objective", "duplicate", "selection"])
def test_rehashed_candidate_content_still_requires_identity_array_and_summary_closure(change):
    row, archives = fixture(); path = row["CSISelectionQualityCandidatesCSV"]
    candidates = decode(archives[path])
    if change == "identity": candidates[0]["RandomSeed"] = "999"
    if change == "support":
        p = json.loads(candidates[0]["SupportJSON"]); p["ColumnMajorValues"][0] = 9
        candidates[0]["SupportJSON"] = json.dumps(p)
    if change == "layer": candidates[0]["LayerSINRJSON"] = real_array([99, 3], [2, 1])
    if change == "matrix":
        p = json.loads(candidates[0]["CandidateMatrixJSON"]); p["ImagColumnMajor"][0] = 1
        candidates[0]["CandidateMatrixJSON"] = json.dumps(p)
    if change == "objective": candidates[0]["Objective_bpsHz"] = 99
    if change == "duplicate": candidates[1] = dict(candidates[0])
    if change == "selection": candidates[0]["SelectedByReceiver"] = False
    archives[path] = encode(candidates); row["CSISelectionQualityCandidatesCSVSHA256"] = sha(archives[path])
    existing, fetch = inputs([row], archives)
    observations, audit, _ = quality.collect(existing, fetch)
    assert not observations and audit[0]["source_mapping_status"] == "invalid"


def test_missing_lifecycle_never_invented_and_authoritative_empty_public_table_not_filled():
    row, archives = fixture()
    identity = json.loads(row["CSISelectionQualityIdentityJSON"]); identity.pop("ExecutionID")
    row["CSISelectionQualityIdentityJSON"] = json.dumps(identity)
    existing, fetch = inputs([row], archives)
    observations, audit, _ = quality.collect(existing, fetch)
    assert not observations and "ExecutionID" in audit[0]["reason"]
    existing[quality.SOURCES[0]] = dict(artifact_id=100, logical_path=quality.SOURCES[0])
    observations, audit, _ = quality.collect(existing, lambda i: b"CSISelectionQualityAvailable\n" if i == 100 else fetch(i))
    assert not observations and not audit


def test_exact_duplicate_not_counted_twice_but_source_row_audit_preserved():
    row, archives = fixture(); existing, fetch = inputs([row, copy.deepcopy(row)], archives)
    observations, audit, _ = quality.collect(existing, fetch)
    assert len(observations) == 1 and len(audit) == 2
    assert audit[0]["counts_as_observation"] and not audit[1]["counts_as_observation"]
    assert "Duplicate" in audit[1]["reason"]


def test_partial_valid_population_preserved_bad_row_never_becomes_zero():
    a, files_a = fixture(); b, files_b = fixture(2); b["CSISelectionQualityJointRegret_bpsHz"] = 999
    existing, fetch = inputs([a, b], {**files_a, **files_b})
    table = m._specialized_table_materialization(quality.OBSERVATIONS, existing, fetch, 99, "Private study")
    audit = m._specialized_table_materialization(quality.AUDIT, existing, fetch, 99, "Private study")
    assert len(decode(table["data"])) == 1 and len(decode(audit["data"])) == 2
    result = m._specialized_chart_materialization(quality.CHART, existing, fetch, 99)
    assert len(decode(result["csv_bytes"])) == 3 and b"invalid_sources=1" in result["img_bytes"]


def test_contract_registration_and_default_disabled_policy():
    tables = {r["table_name"] for r in contract.iter_table_specs("reports")}
    assert {quality.OBSERVATIONS, quality.AUDIT} <= tables
    spec = next(r for r in contract.iter_chart_specs("reports") if r["chart_name"] == quality.CHART)
    assert aliases.CONTRACT_CHART_ALIAS_PATHS[quality.CHART] == list(quality.SOURCES)
    path = m.chart_contract_csv_path(spec)
    assert m.contract_artifact_is_policy_filtered(path, {})
    assert not m.contract_artifact_is_policy_filtered(path, {"csi_selection_quality_enabled": True})
    enabled_no_raster = {"csi_selection_quality_enabled": True, "raster_output_enabled": False}
    assert m.contract_artifact_is_policy_filtered(path, enabled_no_raster)
    for name in (quality.OBSERVATIONS, quality.AUDIT):
        assert m.contract_artifact_is_policy_filtered(f"reports/csv/{name}.csv", {})
        assert not m.contract_artifact_is_policy_filtered(f"reports/csv/{name}.csv", enabled_no_raster)


def test_genuine_zero_candidate_objectives_remain_valid_zero_not_unavailable_fill():
    row, archives = fixture(); path = row["CSISelectionQualityCandidatesCSV"]
    candidates = decode(archives[path])
    for candidate in candidates:
        rank = int(candidate["Rank"])
        candidate["LayerSINRJSON"] = real_array([0]*(2*rank), [2, rank])
        candidate["SupportObjectiveJSON"] = real_array([0, 0], [2, 1])
        candidate["Objective_bpsHz"] = 0
        candidate["WithinJointTie"] = True
        candidate["WithinReportedRankTie"] = rank == 1
    for name in quality.METRICS:
        row[quality.PREFIX+name] = 0
    archives[path] = encode(candidates); row["CSISelectionQualityCandidatesCSVSHA256"] = sha(archives[path])
    result = chart([row], archives)
    assert len(decode(result["csv_bytes"])) == 3
    assert all(float(r["y_value"]) == 0 for r in decode(result["csv_bytes"]))
    assert not result.get("no_plot") and b"PRIVATE RETROSPECTIVE AUDIT" in result["img_bytes"]


def test_empty_tables_have_typed_contract_headers_no_reason_rows():
    for name in (quality.OBSERVATIONS, quality.AUDIT):
        table = quality.table_materialization(name, {}, lambda i: b"", 99)
        assert not decode(table["data"]) and b"source_table_logical_path" in table["data"]
    result = quality.chart_materialization(quality.CHART, {}, lambda i: b"", 99)
    assert result["no_plot"] and not decode(result["csv_bytes"]) and "img_bytes" not in result


def test_dashboard_consumer_reads_all_rows_not_its_generic_200_row_preview(monkeypatch):
    import lls_web_dashboard as dash
    row, archives = fixture(); result = chart([row], archives)
    header, values = m._decode_csv(result["csv_bytes"])
    received = []
    def read(artifact, count):
        received.append(count)
        return header, values*100
    monkeypatch.setattr(dash, "load_artifact_csv_preview", read)
    view = dash.build_numeric_chart_from_artifact(dict(artifact_id=9, logical_path="reports/csv/contract__private-csi-selection-study__test.csv"))
    assert received == [None] and sum(len(s["points"]) for s in view["series"]) == 300


def test_real_publication_path_writes_complete_csv_png_lineage_then_rejects_changed_source(tmp_path, monkeypatch):
    rows = []; payloads = {}
    for point in (1, 2):
        row, files = fixture(point=point, snr=point*5)
        rows.append(row); payloads.update(files)
    source = quality.SOURCES[1]
    payloads[source] = encode(rows)
    for path, data in payloads.items():
        target = tmp_path/path; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
    table_specs = [s for s in contract.iter_table_specs("reports") if s["table_name"] in {quality.OBSERVATIONS, quality.AUDIT}]
    chart_spec = next(s for s in contract.iter_chart_specs("reports") if s["chart_name"] == quality.CHART)
    monkeypatch.setattr(m, "_table_specs", lambda: table_specs)
    monkeypatch.setattr(m, "_chart_specs", lambda: [chart_spec])

    def publish():
        files = sorted(p for p in tmp_path.rglob("*") if p.is_file())
        artifacts = [dict(artifact_id=i, logical_path=p.relative_to(tmp_path).as_posix(),
                          artifact_kind="image_png" if p.suffix == ".png" else "table_csv" if p.suffix == ".csv" else "mat_binary",
                          filesystem_path=str(p), byte_size=p.stat().st_size,
                          mime_type="image/png" if p.suffix == ".png" else "text/csv" if p.suffix == ".csv" else "application/octet-stream")
                     for i, p in enumerate(files, 1)]
        by_id = {i: p for i, p in enumerate(files, 1)}
        return m.materialize_run_contract_artifacts(dict(run_id=99, run_folder=str(tmp_path), status_text="completed"),
            artifacts, fetch_artifact_bytes=lambda i: by_id[i].read_bytes(), db_connection_factory=None,
            feature_policy={"csi_selection_quality_enabled": True}, force=True, filesystem_only=True)

    result = publish()
    plotted = tmp_path/m.chart_contract_csv_path(chart_spec); image = tmp_path/m.chart_contract_image_path(chart_spec)
    assert len(decode(plotted.read_bytes())) == 6 and image.read_bytes().startswith(b"\x89PNG")
    assert not result["coverage"]["missing_chart_names"]
    lineage = decode((tmp_path/m.plot_lineage_logical_path()).read_bytes())
    entry = next(r for r in lineage if r["ImagePath"] == image.relative_to(tmp_path).as_posix())
    assert entry["SourceCSV_SHA256"] == sha(plotted.read_bytes()) and entry["ImageSHA256"] == sha(image.read_bytes())
    for row in rows:
        row["ReceiverWindowID"] = "transplanted-window"
    (tmp_path/source).write_bytes(encode(rows))
    rejected = publish()
    assert not image.exists() and not decode(plotted.read_bytes())
    diagnostic = decode((tmp_path/f"reports/csv/{quality.AUDIT}.csv").read_bytes())
    assert len(diagnostic) == 2 and all(r["source_mapping_status"] == "invalid" for r in diagnostic)
    assert quality.CHART in rejected["coverage"]["missing_chart_names"]
