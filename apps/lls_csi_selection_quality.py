"""Read-only publication of the private, retrospective CSI selection study.

No CSI is decoded here and no grant is selected or scored. MATLAB owns the
complex-operand/MMSE recomputation; this consumer verifies its immutable MAT
bytes, candidate CSV, identity, and complete candidate-to-summary arithmetic.
"""
from __future__ import annotations

import hashlib
import io
import json
import math
import re
import struct
from collections import defaultdict
from pathlib import PurePosixPath


CHART = "Private CSI selection regret — fixed-CRI nominal-MMSE study"
OBSERVATIONS = "private_csi_selection_observations"
AUDIT = "private_csi_selection_source_audit"
SOURCES = ("reports/csv/csi_rs_runtime_event_table.csv", "air_interface/csv/csi_rs_trials.csv")
ROLE = "private_UE_selection_quality_not_UCI_delivery_or_applied_grant"
SCOPE = "hypothetical_equal_raw_grid_chain_coefficient_power_nominal_linear_noise_only_fixed_CRI"
PLANE = "raw_native_grid_physical_chain_coefficient_power"
NOTE = ("Private retrospective fixed-CRI nominal-MMSE study. Hypothetical equal raw-grid "
        "chain-coefficient power; not received UCI, applied grant, CQI/BLER calibration, "
        "actual PDSCH performance, or statistically qualified/independent trials.")
PREFIX = "CSISelectionQuality"
METRICS = ("SelectedObjective_bpsHz", "BestReportedRankObjective_bpsHz", "BestJointObjective_bpsHz",
           "ConditionalPMIRegret_bpsHz", "RankRegret_bpsHz", "JointRegret_bpsHz")
TEXT_FIELDS = ("ReferencePlane", "Scope", "ObjectiveClassification", "CandidateDomainSHA256",
               "ChannelSHA256", "PortToPhysicalMatrixSHA256", "PhysicalPowerReferencePlane",
               "PhysicalPowerUnit", "PowerNormalization")
ALIASES = {"RunID": ("SourceRunID", "RunID"), "ObservationID": (PREFIX+"ObservationID",),
           "MeasurementID": ("CSIMeasurementID",), "MeasurementDigest": ("CSIMeasurementDigest",),
           "ConfigurationEpoch": ("CSIConfigurationEpoch",), "ReportConfigID": ("CSIReportConfigID",),
           "SampleRateHz": ("ObservationSampleRateHz",), "ObservationSHA256": ("ReceiverObservationSHA256",),
           "MeasurementSlot": ("Slot",), "ResourceOrdinal0": ("CRI",),
           "UEIndex": ("UEIndex", "UEId"), "CellID": ("CellID", "CellId")}
REQUIRED_ID = ("RunID", "ExecutionID", "ConfigHash", "RandomSeed", "ChannelSeed", "SweepPointIndex",
               "ConfiguredSNR_dB", "UEIndex", "CellID", "ResourceID", "ResourceOrdinal0",
               "ObservationID", "MeasurementID", "MeasurementDigest", "ReportConfigID", "RequestSHA256",
               "ConfigurationEpoch", "ReceiverID", "ReceiverWindowID", "ReceiverClockDomain",
               "ReceiverClockEpoch", "ObservationStartSample", "ObservationEndSampleExclusive",
               "SampleRateHz", "ObservationSHA256")
AUDIT_COLUMNS = ("source_table_logical_path", "source_table_sha256", "source_row_index",
                 "observation_id", "identity_sha256", "status", "reason", "counts_as_observation",
                 "source_mapping_status", "evidence_role")
BASE_COLUMNS = ("source_table_logical_path", "source_table_sha256", "source_row_index",
                "identity_json", "identity_json_sha256", "identity_sha256", "identity_hash_contract",
                "operand_set_sha256", "candidates_csv",
                "candidates_csv_sha256", "operand_mat", "operand_mat_sha256", "evidence_role",
                "statistically_qualified", "summary_validation", "source_mapping_status",
                "comparison_group_sha256", "support_sha256") + REQUIRED_ID + METRICS + TEXT_FIELDS


def _need(condition, reason):
    if not condition:
        raise ValueError(reason)


def _text(row, name):
    return str(row.get(name, "") or "").strip()


def _number(value, name, *, integer=False, minimum=None):
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"Missing/non-numeric {name}") from exc
    _need(math.isfinite(number), f"Nonfinite {name}")
    _need(not integer or number == int(number), f"Non-integer {name}")
    _need(minimum is None or number >= minimum, f"Out-of-range {name}")
    return int(number) if integer else number


def _flag(value, name):
    token = str(value).strip().lower()
    _need(token in {"true", "false", "1", "0", "1.0", "0.0"}, f"Missing boolean {name}")
    return token in {"true", "1", "1.0"}


def _sha(value, name):
    token = str(value).strip().lower()
    _need(re.fullmatch(r"[0-9a-f]{64}", token) is not None, f"Invalid SHA256 {name}")
    return token


def _json(token, name):
    try:
        return json.loads(token)
    except (ValueError, TypeError) as exc:
        raise ValueError(f"Invalid JSON {name}") from exc


def _same(actual, expected, name):
    if isinstance(expected, bool):
        equal = _flag(actual, name) == expected
    elif isinstance(expected, (int, float)):
        equal = _number(actual, name) == expected
    else:
        equal = str(actual) == str(expected)
    _need(equal, f"Identity/metadata mismatch: {name}")


def _near(actual, expected, name):
    _need(math.isclose(_number(actual, name), expected, rel_tol=1e-9, abs_tol=1e-9),
          f"Candidate/summary arithmetic mismatch: {name}")


def _array(token, name):
    """Decode and authenticate MATLAB's declared column-major real arrays."""
    value = _json(token, name)
    _need(isinstance(value, dict) and value.get("Contract") == "sixgr_real_array_column_major/v1",
          f"Unsupported array contract: {name}")
    dtype = value.get("Class")
    _need(dtype in {"double", "single"}, f"Unsupported array class: {name}")
    shape = [_number(v, name+" shape", integer=True, minimum=1) for v in value.get("Shape", [])]
    _need(len(shape) >= 2, f"Missing array dimensions: {name}")
    raw = value.get("ColumnMajorValues", [])
    raw = raw if isinstance(raw, list) else [raw]
    numbers = [_number(v, name) for v in raw]
    _need(len(numbers) == math.prod(shape), f"Array length mismatch: {name}")
    code = "d" if dtype == "double" else "f"
    real_bytes = struct.pack("<"+code*len(numbers), *numbers)
    descriptor = {"Class": dtype, "Shape": shape,
                  "RealBytesSHA256": hashlib.sha256(real_bytes).hexdigest(),
                  "ImagBytesSHA256": hashlib.sha256(bytes(len(real_bytes))).hexdigest()}
    digest = hashlib.sha256(json.dumps(descriptor, separators=(",", ":")).encode()).hexdigest()
    _need(digest == _sha(value.get("SHA256", ""), name), f"Array checksum mismatch: {name}")
    return numbers, shape, digest


def _matrix(token, expected, rank):
    value = _json(token, "CandidateMatrixJSON")
    _need(isinstance(value, dict) and value.get("ContractVersion") == "sixgr_complex_matrix/v1",
          "Unsupported candidate matrix contract")
    nr = _number(value.get("Rows"), "matrix rows", integer=True, minimum=1)
    nc = _number(value.get("Columns"), "matrix columns", integer=True, minimum=1)
    _need(nc == rank, "Candidate matrix rank mismatch")
    arrays = []
    for key in ("RealColumnMajor", "ImagColumnMajor"):
        values = value.get(key, [])
        values = values if isinstance(values, list) else [values]
        values = [_number(v, key) for v in values]
        _need(len(values) == nr*nc, "Candidate matrix shape mismatch")
        arrays.append(struct.pack("<"+"d"*len(values), *values))
    digest = hashlib.sha256(f"sixgr-mimo-matrix-v1|double|[{nr} {nc}]|".encode()+b"".join(arrays)).hexdigest()
    _need(digest == expected == _sha(value.get("MatrixSHA256", ""), "matrix"),
          "Candidate matrix checksum mismatch")
    return nr


def _read(existing, fetch, path):
    _need(path in existing, f"Missing retained artifact: {path}")
    return fetch(int(existing[path]["artifact_id"]))


def _digest(existing, fetch, path):
    _need(path in existing, f"Missing retained artifact: {path}")
    artifact_id = int(existing[path]["artifact_id"])
    opener = getattr(fetch, "open_artifact_binary", None)
    stream = opener(artifact_id) if callable(opener) else io.BytesIO(fetch(artifact_id))
    digest = hashlib.sha256()
    with stream:
        for chunk in iter(lambda: stream.read(1024*1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _archive_path(existing, relative, identity):
    path = str(relative).replace("\\", "/")
    parts = PurePosixPath(path)
    _need(path and not parts.is_absolute() and ":" not in path and ".." not in parts.parts,
          "Archive reference must be a contained relative path")
    _need(path.startswith("beamforming/"), "Archive reference is outside beamforming evidence")
    # Child runs may have been registered with qualified logical paths. Resolve
    # only an exact declared owner-folder/filesystem association, never a suffix
    # search or a guessed sweep-point directory.
    owner = str(identity.get("RunFolder", "")).replace("\\", "/").rstrip("/")
    wanted = owner+"/"+path if owner else ""
    exact = [key for key, artifact in existing.items() if wanted and
             str(artifact.get("filesystem_path", "")).replace("\\", "/") == wanted]
    if exact:
        _need(len(exact) == 1, "Ambiguous archive owner path")
        return exact[0]
    _need(path in existing, f"Missing retained artifact: {path}")
    return path


def _validate(row, source, source_sha, index, existing, fetch, m):
    non_runtime_field = m._non_runtime_evidence_field(row)
    _need(not non_runtime_field, f"Non-runtime provenance marker: {non_runtime_field}")
    _need(_text(row, PREFIX+"Status") == "archived_private_UE_selection_quality_not_delivery_or_grant",
          "Unexpected private-audit status")
    identity_token = str(row.get(PREFIX+"IdentityJSON", ""))
    identity = _json(identity_token, "selection identity")
    _need(isinstance(identity, dict), "Selection identity must be one object")
    for key in REQUIRED_ID:
        _need(key in identity and identity[key] is not None and str(identity[key]).strip(),
              f"Missing archived population identity: {key}")
    for key in ("ConfigHash", "RequestSHA256", "ObservationSHA256", "MeasurementDigest"):
        _sha(identity[key], key)
    for key, value in identity.items():
        _need(isinstance(value, (str, int, float, bool)), f"Nonscalar identity: {key}")
        if key == "ResourceID":
            for alias in ("ResourceID", "ResourceId"):
                if alias in row:
                    _same("CSI-RS-"+str(_number(row[alias], alias, integer=True, minimum=0)), value, key)
        elif key != "RequestSHA256":
            # Public RunID may identify the publication container. SourceRunID
            # is the explicit originating-run alias; never overwrite it with
            # a later aggregation/container run identifier.
            aliases = ("SourceRunID",) if key == "RunID" and "SourceRunID" in row else ALIASES.get(key, (key,))
            for alias in aliases:
                if alias in row:
                    _same(row[alias], value, key)
    _same(_text(row, PREFIX+"ObservationID"), identity["ObservationID"], "ObservationID")
    for name in ("StatisticallyQualified", "ActualPDSCHPerformanceQualified", "CQIBLERQualified", "CRISelectionQualified"):
        _need(not _flag(row.get(PREFIX+name), name), f"Unsupported qualification claim: {name}")
    for name in ("RandomSeed", "ChannelSeed", "SweepPointIndex", "ResourceOrdinal0", "ReceiverClockEpoch",
                 "ConfigurationEpoch", "ObservationStartSample", "ObservationEndSampleExclusive"):
        _number(identity[name], name, integer=True, minimum=0)
    _number(identity["SampleRateHz"], "SampleRateHz", minimum=1)
    _number(identity["ConfiguredSNR_dB"], "ConfiguredSNR_dB")
    _need(identity["ObservationEndSampleExclusive"] > identity["ObservationStartSample"], "Empty observation window")
    identity_sha = _sha(row.get(PREFIX+"IdentitySHA256"), "identity")
    operand_sha = _sha(row.get(PREFIX+"OperandSetSHA256"), "operands")
    paths = {kind: _archive_path(existing, _text(row, PREFIX+field), identity)
             for kind, field in (("csv", "CandidatesCSV"), ("mat", "MATFile"))}
    hashes = {kind: _sha(row.get(PREFIX+field), kind) for kind, field in
              (("csv", "CandidatesCSVSHA256"), ("mat", "MATFileSHA256"))}
    candidate_bytes = _read(existing, fetch, paths["csv"])
    _need(hashlib.sha256(candidate_bytes).hexdigest() == hashes["csv"], "Candidate CSV checksum mismatch")
    _need(_digest(existing, fetch, paths["mat"]) == hashes["mat"], "Operand MAT checksum mismatch")
    _, candidates = m._decode_csv_dicts(candidate_bytes)
    n = _number(row.get(PREFIX+"CandidateCount"), "CandidateCount", integer=True, minimum=1)
    support_count = _number(row.get(PREFIX+"SupportCount"), "SupportCount", integer=True, minimum=1)
    _need(len(candidates) == n, "Candidate population count mismatch")
    fields = {key: _text(row, PREFIX+key) for key in TEXT_FIELDS}
    _need(fields["Scope"] == SCOPE and fields["PhysicalPowerReferencePlane"] == PLANE and
          fields["ObjectiveClassification"] == "IMPLEMENTATION_POLICY_NOT_NR_NORMATIVE_OPTIMALITY" and
          fields["PowerNormalization"] == "unit_physical_chain_grid_coefficient_power" and
          fields["PhysicalPowerUnit"] in {"normalized_grid_coefficient_squared_units", "mW_scaled_grid_coefficient_squared_units"},
          "Unsupported objective/power scope")
    _need(fields["ReferencePlane"] == "nominal_linear_CSI_RS_port_channel_on_actual_RX_FFT_clock",
          "Unsupported reference plane")
    for name in ("CandidateDomainSHA256", "ChannelSHA256", "PortToPhysicalMatrixSHA256"):
        _sha(fields[name], name)
    selected = []; scores = []; ranks = []; seen = set(); support_digest = None
    for candidate in candidates:
        for key, value in identity.items():
            _same(candidate.get(key, ""), value, key)
        for key, value in fields.items():
            _same(candidate.get(key, ""), value, key)
        for key, value in (("IdentitySHA256", identity_sha), ("OperandSetSHA256", operand_sha),
                           (PREFIX+"ObservationID", identity["ObservationID"]), ("EvidenceRole", ROLE)):
            _same(candidate.get(key, ""), value, key)
        _need(not _flag(candidate.get("StatisticallyQualified"), "StatisticallyQualified"), "Candidate qualification conflict")
        support, shape, digest = _array(candidate.get("SupportJSON"), "SupportJSON")
        _need(shape == [support_count, 2] and all(v >= 0 and v == int(v) for v in support), "Resource support shape/domain mismatch")
        _need(len(set(zip(support[:support_count], support[support_count:]))) == support_count, "Duplicate resource support")
        _need(support_digest in (None, digest), "Candidate resource supports differ")
        support_digest = digest
        rank = _number(candidate.get("Rank"), "Rank", integer=True, minimum=1)
        pmi = _number(candidate.get("PMI"), "PMI", integer=True, minimum=0)
        key = (rank, pmi, _text(candidate, "PMIComponentsJSON"))
        _need(key not in seen, "Duplicate candidate identity")
        seen.add(key)
        _matrix(candidate.get("CandidateMatrixJSON"), _sha(candidate.get("MatrixSHA256"), "matrix"), rank)
        per_support, os, _ = _array(candidate.get("SupportObjectiveJSON"), "SupportObjectiveJSON")
        layer, ls, _ = _array(candidate.get("LayerSINRJSON"), "LayerSINRJSON")
        _need(os == [support_count, 1] and ls == [support_count, rank] and all(v >= 0 for v in layer),
              "Objective/SINR support dimensions mismatch")
        for q in range(support_count):
            _near(per_support[q], sum(math.log2(1+layer[q+support_count*l]) for l in range(rank)), "support objective")
        score = sum(per_support)/support_count
        _near(candidate.get("Objective_bpsHz"), score, "objective")
        power = _number(candidate.get("UnscaledPhysicalFrobeniusPower"), "physical power", minimum=0)
        factor = _number(candidate.get("AppliedAmplitudeFactor"), "amplitude factor", minimum=0)
        _need(power > 0 and factor > 0, "Zero candidate physical power")
        _near(power*factor*factor, 1.0, "equal grid-coefficient power")
        _near(candidate.get("ScoredPhysicalFrobeniusPower"), 1.0, "scored physical power")
        scores.append(score); ranks.append(rank)
        if _flag(candidate.get("SelectedByReceiver"), "SelectedByReceiver"):
            selected.append(len(scores)-1)
    _need(len(selected) == 1, "Require exactly one receiver-selected candidate")
    legal_ranks, _, _ = _array(row.get(PREFIX+"LegalRankDomainJSON"), "LegalRankDomainJSON")
    _need(sorted(legal_ranks) == sorted(set(ranks)), "Legal-rank candidate domain mismatch")
    chosen = selected[0]; selected_row = candidates[chosen]
    _same(row.get(PREFIX+"SelectedRank"), ranks[chosen], "selected rank")
    _same(row.get(PREFIX+"SelectedPMI"), _number(selected_row["PMI"], "PMI"), "selected PMI")
    for name, candidate_field in (("SelectedMatrixSHA256", "MatrixSHA256"), ("SelectedPMIComponentsJSON", "PMIComponentsJSON")):
        _same(_text(row, PREFIX+name), selected_row[candidate_field], name)
    rank_best = max(s for s, r in zip(scores, ranks) if r == ranks[chosen]); best = max(scores); chosen_score = scores[chosen]
    values = (chosen_score, rank_best, best, rank_best-chosen_score, best-rank_best, best-chosen_score)
    for name, value in zip(METRICS, values):
        _near(row.get(PREFIX+name), value, name)
    # These strata intentionally retain point and window: a scatter can show
    # every point without pretending captures at different clocks are pairs.
    group = {k: identity[k] for k in REQUIRED_ID if k not in {"ObservationID", "ObservationSHA256", "MeasurementDigest"}}
    group.update(fields, SupportSHA256=support_digest)
    group_sha = hashlib.sha256(json.dumps(group, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    record = {"source_table_logical_path": source, "source_table_sha256": source_sha, "source_row_index": index,
              "identity_json": identity_token, "identity_json_sha256": hashlib.sha256(identity_token.encode("utf-8")).hexdigest(),
              "identity_sha256": identity_sha,
              "identity_hash_contract": "native_typed_plain_value_shape_and_exact_numeric_bytes_not_JSON_token_SHA256",
              "operand_set_sha256": operand_sha, "candidates_csv": paths["csv"], "candidates_csv_sha256": hashes["csv"],
              "operand_mat": paths["mat"], "operand_mat_sha256": hashes["mat"], "evidence_role": ROLE,
              "statistically_qualified": False, "summary_validation": "hash_bound_archives_and_candidate_reduction_not_MMSE_reexecution",
              "source_mapping_status": "exact", "comparison_group_sha256": group_sha, "support_sha256": support_digest,
              **identity, **fields, **dict(zip(METRICS, values)), "CandidateCount": n, "SupportCount": support_count,
              "SelectedRank": ranks[chosen], "SelectedPMI": _number(selected_row["PMI"], "PMI"),
              "SelectedPMIComponentsJSON": selected_row["PMIComponentsJSON"], "SelectedMatrixSHA256": selected_row["MatrixSHA256"]}
    record["LegalRankDomainJSON"] = _text(row, PREFIX+"LegalRankDomainJSON")
    for key, value in row.items():
        if key.startswith(("CSIObservationPopulation", "SweepAggregate")) or key == "NoiseStreamSeed":
            record[key] = value  # Supplied metadata remains metadata, not inferred lifecycle.
    return record, list(paths.values())


def collect(existing, fetch):
    """Return valid observations and diagnostic rows; never fill absent history."""
    import lls_contract_materializer as m
    source = next((path for path in SOURCES if path in existing), "")
    if not source:
        return [], [], []
    payload = _read(existing, fetch, source); digest = hashlib.sha256(payload).hexdigest()
    _, rows = m._decode_csv_dicts(payload)
    observations = []; audit = []; sources = [source]; seen = {}
    for index, row in enumerate(rows, 1):
        diagnostic = dict(zip(AUDIT_COLUMNS, (source, digest, index, _text(row, PREFIX+"ObservationID"),
            _text(row, PREFIX+"IdentitySHA256"), "not_available", "", False, "unavailable", ROLE)))
        try:
            if not _flag(row.get(PREFIX+"Available", "false"), "Available"):
                diagnostic["reason"] = _text(row, PREFIX+"Status") or "private_audit_not_executed"
            else:
                record, dependencies = _validate(row, source, digest, index, existing, fetch, m)
                key = record["identity_sha256"]
                _need(key not in seen, "Duplicate archived observation identity; no double counting")
                seen[key] = len(observations)
                observations.append(record); sources.extend(dependencies)
                diagnostic.update(status="verified_private_selection_observation", reason="", counts_as_observation=True,
                                  source_mapping_status="exact")
        except (ValueError, KeyError, TypeError, OSError, UnicodeError) as exc:
            diagnostic.update(status="invalid_private_selection_source", reason=str(exc), source_mapping_status="invalid")
        audit.append(diagnostic)
    return observations, audit, list(dict.fromkeys(sources))


def _csv(m, rows, defaults):
    header = list(dict.fromkeys([*defaults, *(key for row in rows for key in row)]))
    return m._encode_dict_rows(header, rows)


def table_materialization(name, existing, fetch, run_id):
    if name not in {OBSERVATIONS, AUDIT}:
        return None
    import lls_contract_materializer as m
    observations, audit, sources = collect(existing, fetch)
    rows, columns = (observations, BASE_COLUMNS) if name == OBSERVATIONS else (audit, AUDIT_COLUMNS)
    return {"data": _csv(m, rows, columns), "status": "private_selection_observations" if name == OBSERVATIONS else "private_selection_source_audit",
            "note": NOTE, "source_logical_path": "|".join(sources), "source_row_count": len(rows)}


def chart_materialization(name, existing, fetch, run_id):
    if name != CHART:
        return None
    import lls_contract_materializer as m
    observations, audit, sources = collect(existing, fetch)
    rows = []; series = defaultdict(list)
    for observation in observations:
        label = (f"{observation['RunID']} / seed {observation['RandomSeed']} / point {observation['SweepPointIndex']} / "
                 f"UE{observation['UEIndex']} {observation['ResourceID']} / {observation['ReceiverWindowID']} / "
                 f"{observation['PhysicalPowerUnit']} / {observation['comparison_group_sha256'][:10]}")
        for metric in ("ConditionalPMIRegret_bpsHz", "RankRegret_bpsHz", "JointRegret_bpsHz"):
            series_name = label+" / "+metric.removesuffix("_bpsHz")
            rows.append({**observation, "chart_name": CHART, "series_name": series_name,
                         "metric_name": metric, "x_value": observation["ConfiguredSNR_dB"],
                         "y_value": observation[metric], "metric_unit": "bit/s/Hz_objective_regret",
                         "x_label": "Configured reference SNR (dB; not measured SINR)",
                         "y_label": "Nominal-MMSE objective regret (bit/s/Hz)", "chart_mode": "scatter"})
            series[series_name].append([observation["ConfiguredSNR_dB"], observation[metric]])
    result = {"csv_bytes": _csv(m, rows, BASE_COLUMNS+("chart_name", "series_name", "metric_name", "x_value", "y_value")),
              "source_table_path": "|".join(sources), "source_row_count": len(observations), "note": NOTE,
              "csv_status": "private_selection_exact_plotted_observations", "source_mapping_status": "exact"}
    if not rows:
        # The separately registered audit preserves actual rejected source rows.
        # No placeholder row and no unavailable/reason-card PNG is manufactured.
        return {**result, "no_plot": True, "csv_status": "unavailable_private_selection_observations",
                "source_mapping_status": "unavailable", "note": NOTE+" No valid archived observations; see source audit."}
    image = m._render_multi_series_svg(CHART, NOTE, [{"name": key, "points": points} for key, points in series.items()],
        [f"observations={len(observations)}", f"invalid_sources={sum(r['source_mapping_status']=='invalid' for r in audit)}",
         "No averaging, fitting, confidence interval or independent-trial claim", "All points, seeds, resources and windows retained"],
        x_label="Configured reference SNR (dB; not measured SINR)", y_label="Nominal-MMSE objective regret (bit/s/Hz)",
        mode="scatter", evidence_shape_policy="operating_point", show_all_series=True,
        pad_constant_axes=True, max_points_per_series=None, wrap_legend=True, wrap_subtitle=True)
    # The generic renderer's badge is intentionally replaced for this study.
    image = image.replace(b">RUNTIME MEASUREMENT<", b">PRIVATE RETROSPECTIVE AUDIT<")
    return {**result, "img_bytes": image, "image_status": "generated_private_selection_study_svg"}


def numeric_chart(header, values):
    """Complete WebGUI scatter; never use its generic duplicate-x reducer."""
    series = defaultdict(list)
    for values_row in values:
        row = dict(zip(header, values_row))
        _need(_text(row, "chart_name") == CHART and _text(row, "source_mapping_status") == "exact" and
              _text(row, "evidence_role") == ROLE, "Unverified private selection plotted row")
        series[_text(row, "series_name")].append({"x": _number(row.get("x_value"), "x_value"),
                                                 "y": _number(row.get("y_value"), "y_value"),
                                                 "observation_id": row.get("ObservationID"),
                                                 "receiver_window_id": row.get("ReceiverWindowID")})
    if not series:
        return None
    return {"title": CHART, "xaxis_title": "Configured reference SNR (dB; not measured SINR)",
            "yaxis_title": "Nominal-MMSE objective regret (bit/s/Hz)", "evidence_scope": ROLE,
            "layout_hints": {"hovermode": "closest"}, "note": NOTE,
            "series": [{"name": key, "mode": "markers", "points": points} for key, points in series.items()]}
