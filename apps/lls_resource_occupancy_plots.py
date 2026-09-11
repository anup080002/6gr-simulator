"""Plots derived from executed TX RE coordinates, never slot-format capacity."""
from __future__ import annotations

import math
from collections import defaultdict


def symbol_occupancy_chart(existing, fetch_artifact_bytes, run_id):
    # Local import keeps the renderer's specialized-dispatch dependency acyclic.
    import lls_contract_materializer as m

    name = "frame/slot/symbol occupancy timeline"
    path = "reports/csv/live_re_allocation_snapshot.csv"
    header, rows = m._artifact_rows_by_path(existing, fetch_artifact_bytes, path)
    required = {"absolute_slot", "symbol_index", "cell_id", "direction",
                "subcarrier_count", "active_flag", "evidence_scope"}
    if not rows or not required.issubset(set(header)):
        reason = "Executed TX RE coordinates and occupancy provenance are unavailable; slot-format capacity is not occupancy."
        return {
            "csv_bytes": m._encode_csv(
                ["run_id", "chart_name", "status", "reason", "source_table_logical_path"],
                [[run_id, name, "unavailable_exact_reason", reason, path]]),
            "img_bytes": m._render_reason_svg(name, "Occupancy unavailable", [reason]),
            "csv_status": "unavailable_exact_reason",
            "image_status": "generated_unavailable_reason_svg",
            "source_table_path": path, "source_row_count": 0, "note": reason,
        }

    symbols = defaultdict(set)
    counts = defaultdict(int)
    for number, row in enumerate(rows, 1):
        if m._row_text(row, "evidence_scope") != "runtime_observed_tx_occupancy":
            raise ValueError(f"Occupancy row {number} is not executed TX evidence")
        domain = m._row_text(row, "grid_domain")
        if domain and domain != "carrier_cp_ofdm":
            raise ValueError(f"Occupancy row {number} is not a carrier-grid coordinate")
        if m._row_text(row, "channel").upper() == "PRACH":
            raise ValueError(f"Occupancy row {number} improperly labels native PRACH as carrier REs")
        active = m._row_text(row, "active_flag").lower()
        if active not in {"0", "1", "false", "true"}:
            raise ValueError(f"Occupancy row {number} has an invalid active flag")
        values = [m._row_float(row, field) for field in
                  ("absolute_slot", "symbol_index", "subcarrier_count")]
        if any(v is None or not math.isfinite(v) or v < 0 or v != int(v) for v in values):
            raise ValueError(f"Occupancy row {number} has invalid integer RE coordinates")
        slot, symbol, width = (int(v) for v in values)
        direction = m._row_text(row, "direction").upper()
        cell = m._row_text(row, "cell_id")
        if direction not in {"DL", "UL"} or not cell or cell.lower() in {"nan", "missing"}:
            raise ValueError(f"Occupancy row {number} lacks cell/direction identity")
        if active in {"0", "false"} or width == 0:
            continue
        # Deduplicate all REs, ports, layers, and channels within each scope.
        # Do not combine cells, carriers, BWPs, or directions, and do not
        # invent carrier/BWP identifiers when a legacy exporter omitted them.
        carrier = m._row_text(row, "component_carrier", "component_carrier_id")
        bwp = m._row_text(row, "bwp_id")
        key = (cell, carrier, bwp, direction, slot)
        symbols[key].add(symbol)
        counts[key] += 1
    if not symbols:
        # An empty active RE set does not establish complete zero-occupancy
        # coverage for all time intervals. Reuse the explicit missing result.
        return symbol_occupancy_chart({}, fetch_artifact_bytes, run_id)

    csv_rows = []
    series_points = defaultdict(list)
    for (cell, carrier, bwp, direction, slot), occupied in sorted(symbols.items()):
        scope = f"Cell {cell} {direction} CC {carrier or '?'} BWP {bwp or '?'}"
        series_points[scope].append([slot, len(occupied)])
        csv_rows.append({
            "run_id": run_id, "chart_name": name, "chart_mode": "scatter",
            "x_label": "Absolute slot (0-based)", "y_label": "Distinct occupied TX symbols",
            "point_index": len(csv_rows) + 1, "x_value": slot, "y_value": len(occupied),
            "cell_id": cell, "component_carrier": carrier, "bwp_id": bwp,
            "direction": direction, "symbol_indices_0based": "|".join(map(str, sorted(occupied))),
            "scope_identity_status": "complete" if carrier and bwp else "partial_carrier_or_bwp_not_exported",
            "source_table_logical_path": path, "source_row_count": counts[(cell, carrier, bwp, direction, slot)],
            "source_sample_count": counts[(cell, carrier, bwp, direction, slot)],
            "materialization_status": "executed_tx_symbol_occupancy_dataset",
            "source_mapping_status": "exact", "evidence_shape_policy": "observed_timeline",
            "lineage_note": "Distinct symbols in active executed TX RE rows; absent intervals are not filled with zeros.",
        })
    series = [{"name": scope, "points": points} for scope, points in series_points.items()]
    one_slot = len({row["x_value"] for row in csv_rows}) == 1
    mode = "bar" if one_slot else "scatter"
    shape = "measured_scalar" if len(csv_rows) == 1 else ("operating_point" if one_slot else "observed_timeline")
    for row in csv_rows:
        row["chart_mode"] = mode
        row["evidence_shape_policy"] = shape
    return {
        "csv_bytes": m._encode_dict_rows(list(csv_rows[0]), csv_rows),
        "img_bytes": m._render_multi_series_svg(
            name, "Executed TX grid occupancy by exported scope; missing carrier/BWP identity remains unavailable.",
            series, [f"executed_re_rows={sum(counts.values())}", "Distinct symbols, not RE/port counts", "No inferred empty slots", "CC?/BWP? = identity not exported"],
            x_label="Absolute slot (0-based)", y_label="Distinct occupied TX symbols",
            mode=mode, evidence_shape_policy=shape),
        "csv_status": "executed_tx_symbol_occupancy_dataset",
        "image_status": "generated_executed_tx_symbol_occupancy_svg",
        "source_table_path": path, "source_row_count": sum(counts.values()),
        "source_mapping_status": "exact",
        "note": "Union of exact active TX symbol indices per cell/carrier/BWP/direction/slot; not received-grid occupancy or configured capacity.",
    }


def native_prach_grid_chart(existing, fetch_artifact_bytes, run_id):
    """Native PRACH bin ownership; neither carrier PRBs nor measured PSD."""
    import lls_contract_materializer as m

    name = "PRACH native resource grid"
    path = "reports/csv/live_prach_native_allocation_snapshot.csv"
    header, rows = m._artifact_rows_by_path(existing, fetch_artifact_bytes, path)
    required = {"carrier_origin_slot0", "native_symbol_index", "native_subcarrier_start",
                "native_subcarrier_count", "port_index", "grid_domain", "grid_subcarrier_count",
                "grid_symbol_count", "grid_port_count", "native_grid_complete", "native_grid_sha256",
                "grid_subcarrier_spacing_hz", "sample_rate_hz", "port_domain", "allocation_id",
                "cell_id", "ue_id", "evidence_scope", "active_flag",
                "cp_start_sample_relative", "useful_start_sample_relative",
                "useful_end_sample_exclusive_relative"}
    if not rows or not required.issubset(header):
        reason = "Executed native PRACH grid, port mapping and OFDM timing are unavailable."
        return {"csv_bytes": m._encode_csv(["run_id", "status", "reason"],
                [[run_id, "unavailable_exact_reason", reason]]),
                "img_bytes": m._render_reason_svg(name, "Native PRACH unavailable", [reason]),
                "csv_status": "unavailable_exact_reason", "image_status": "generated_unavailable_reason_svg",
                "source_table_path": path, "source_row_count": 0, "note": reason}

    def integer(row, field, positive=False):
        value = m._row_float(row, field)
        if value is None or not math.isfinite(value) or value != int(value) or value < int(positive):
            raise ValueError(f"Native PRACH has invalid {field}")
        return int(value)

    groups = defaultdict(list)
    for row in rows:
        if (m._row_text(row, "grid_domain") != "prach_native_ofdm" or
                m._row_text(row, "evidence_scope") != "runtime_observed_tx_occupancy" or
                m._row_text(row, "native_grid_complete").lower() not in {"1", "true"} or
                m._row_text(row, "active_flag").lower() not in {"1", "true"}):
            raise ValueError("Native PRACH lacks complete executed-grid evidence")
        slot = integer(row, "carrier_origin_slot0")
        k, l = integer(row, "grid_subcarrier_count", True), integer(row, "grid_symbol_count", True)
        start, width = integer(row, "native_subcarrier_start"), integer(row, "native_subcarrier_count", True)
        symbol, port = integer(row, "native_symbol_index"), integer(row, "port_index")
        ports = integer(row, "grid_port_count", True)
        row_scs = integer(row, "grid_subcarrier_spacing_hz", True)
        row_fs = integer(row, "sample_rate_hz", True)
        integer(row, "cell_id")
        integer(row, "ue_id", True)
        cp = integer(row, "cp_start_sample_relative")
        useful = integer(row, "useful_start_sample_relative")
        end = integer(row, "useful_end_sample_exclusive_relative", True)
        if start + width > k or symbol >= l or port >= ports or not cp <= useful < end:
            raise ValueError("Native PRACH coordinates/timing exceed the executed grid")
        if (end - useful) * row_scs != row_fs:
            raise ValueError("Native PRACH useful duration does not equal one native FFT period")
        if m._row_text(row, "port_domain") not in {
                "waveform_port_before_spatial_projection", "physical_antenna_normalized_grid_before_power_and_rf"}:
            raise ValueError("Native PRACH port domain has no supported execution authority")
        digest = m._row_text(row, "native_grid_sha256")
        if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest.lower()):
            raise ValueError("Native PRACH grid hash is missing or malformed")
        key = (slot, m._row_text(row, "cell_id"), m._row_text(row, "ue_id"), m._row_text(row, "allocation_id"))
        if not all(key[1:]):
            raise ValueError("Native PRACH occasion identity is incomplete")
        groups[key].append(row)
    # One clearly labelled occasion per card; all occasions remain in the
    # canonical CSV. Combining unrelated native grids would invent a grid.
    key = max(groups)
    selected = groups[key]
    first = selected[0]
    k, l = integer(first, "grid_subcarrier_count", True), integer(first, "grid_symbol_count", True)
    scs = integer(first, "grid_subcarrier_spacing_hz", True)
    fs = integer(first, "sample_rate_hz", True)
    ports = integer(first, "grid_port_count", True)
    digest = m._row_text(first, "native_grid_sha256")
    port_domain = m._row_text(first, "port_domain")
    occupied = defaultdict(set)
    for row in selected:
        if (integer(row, "grid_subcarrier_count") != k or integer(row, "grid_symbol_count") != l or
                integer(row, "grid_subcarrier_spacing_hz") != scs or integer(row, "sample_rate_hz") != fs or
                integer(row, "grid_port_count") != ports or
                m._row_text(row, "native_grid_sha256") != digest or m._row_text(row, "port_domain") != port_domain):
            raise ValueError("Native PRACH occasion has inconsistent grid authority")
        symbol, port = integer(row, "native_symbol_index"), integer(row, "port_index")
        start, width = integer(row, "native_subcarrier_start"), integer(row, "native_subcarrier_count")
        for sc in range(start, start + width):
            occupied[(sc, symbol)].add(port)
    matrix = [[len(occupied[(sc, symbol)]) for symbol in range(l)] for sc in range(k - 1, -1, -1)]
    rendered = m._render_heatmap_svg(name,
        "Latest observed PRACH occasion, all mapped ports; native symbols/subcarriers, not carrier PRBs.",
        [str(i) for i in range(l)], [str(i) for i in range(k - 1, -1, -1)], matrix,
        [f"carrier_origin_slot0={key[0]}", f"cell={key[1]} UE={key[2]}", f"native_SCS_Hz={scs}",
         f"sample_rate_Hz={fs}", f"grid_ports={ports}", "Color: mapped ports per native RE", "Empty bins: retained complete grid",
         f"source_occasions={len(groups)}", "All occasions retained in source CSV", port_domain],
        "Native PRACH OFDM symbol index (0-based)", "Native PRACH subcarrier index (0-based)",
        allow_singleton_observation=True)
    output = [dict(row, run_id=run_id, chart_name=name, source_table_logical_path=path,
                   selection_policy="latest_observed_occasion_all_mapped_ports", source_occasion_count=len(groups))
              for row in selected]
    return {"csv_bytes": m._encode_dict_rows(list(output[0]), output), "img_bytes": rendered,
            "csv_status": "executed_native_prach_grid_dataset", "image_status": "generated_native_prach_grid_svg",
            "source_table_path": path, "source_row_count": len(selected), "source_mapping_status": "exact",
            "note": "Native PRACH ownership and retained OFDM timing; no carrier-RE conversion or measured-power claim."}
