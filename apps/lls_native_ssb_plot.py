"""Executed SS/PBCH occupancy in native time/frequency, never carrier REs."""
from __future__ import annotations

import math
import re
from collections import defaultdict


def native_ssb_grid_chart(chart_name, existing, fetch_artifact_bytes, run_id):
    import lls_contract_materializer as m

    path = "reports/csv/live_ssb_native_allocation_snapshot.csv"
    if path not in existing:
        return None  # Equal-numerology runs retain their carrier-grid renderer.
    context_names = ("RunID", "ExecutionID", "ScenarioID", "ConfigHash", "SweepPointIndex",
                     "SweepRealizationIndex", "ConfiguredSNR_dB", "Seed", "TrialIndex", "ObservationID")
    bins = {}
    authorities = {}
    row_count = 0

    def integer(row, name, minimum=0):
        value = m._row_float(row, name)
        if value is None or not math.isfinite(value) or value != int(value) or value < minimum:
            raise ValueError(f"Native SSB has invalid {name}")
        return int(value)

    with m._first_available_csv_stream(existing, fetch_artifact_bytes, [path]) as (_, rows):
        for row in rows:
            row_count += 1
            if (m._row_text(row, "grid_domain") != "ssb_native_cp_ofdm" or
                    m._row_text(row, "channel") != "SSB" or
                    m._row_text(row, "evidence_scope") != "runtime_observed_tx_occupancy" or
                    m._row_text(row, "active_flag").lower() not in {"1", "true"}):
                raise ValueError("Native SSB requires actual executed TX occupancy")
            context = tuple(m._row_text(row, name) for name in context_names)
            if not context[3]:
                raise ValueError("Native SSB lacks configuration identity")
            allocation = m._row_text(row, "allocation_id")
            digest = m._row_text(row, "transmit_grid_sha256")
            component = m._row_text(row, "component")
            if not allocation or not re.fullmatch(r"[a-f0-9]{64}", digest):
                raise ValueError("Native SSB lacks its allocation or mapped-grid hash")
            if component not in {"PSS", "SSS", "PBCH", "PBCH-DMRS"}:
                raise ValueError("Native SSB has unknown component ownership")
            cell, beam = integer(row, "cell_id"), integer(row, "ssb_index0")
            symbol, port = integer(row, "native_symbol_index_from_burst"), integer(row, "port_index")
            start, width = integer(row, "native_subcarrier_start"), integer(row, "native_subcarrier_count", 1)
            count, symbols = integer(row, "grid_subcarrier_count", 1), integer(row, "grid_symbol_count", 1)
            scs, fs = integer(row, "grid_subcarrier_spacing_hz", 1), integer(row, "observation_sample_rate_hz", 1)
            cp, useful, end = (integer(row, name) for name in
                               ("cp_start_sample", "useful_start_sample", "useful_end_sample_exclusive"))
            origin, stop = (integer(row, name) for name in
                            ("broadcast_start_sample", "broadcast_end_sample_exclusive"))
            first, last = (m._row_float(row, name) for name in ("frequency_first_hz", "frequency_last_hz"))
            if (count != 240 or start + width > count or symbol >= symbols or
                    not origin <= cp < useful < end <= stop or (end - useful) * scs != fs):
                raise ValueError("Native SSB coordinates or clock exceed the emitted waveform")
            if (first is None or last is None or not all(map(math.isfinite, (first, last))) or
                    last != first + (width - 1) * scs):
                raise ValueError("Native SSB frequency bounds disagree with its bin coordinates")
            identity = (context, cell, allocation, beam)
            authority = (digest, scs, fs, count, symbols, origin, stop, first - start * scs)
            if identity in authorities and authorities[identity] != authority:
                raise ValueError("Native SSB occasion has conflicting grid authority")
            authorities[identity] = authority
            for subcarrier in range(start, start + width):
                key = (identity, symbol, subcarrier)
                value = (component, cp, useful, end, first + (subcarrier - start) * scs)
                if key in bins:
                    if bins[key][0] != value:
                        raise ValueError("Native SSB components/ports disagree on the same RE")
                    bins[key][1].add(port)
                else:
                    bins[key] = (value, {port})
    if not bins:
        return None
    output = []
    series = defaultdict(list)
    for (identity, symbol, subcarrier), (value, ports) in sorted(bins.items()):
        context, cell, allocation, beam = identity
        component, cp, useful, end, frequency = value
        digest, scs, fs, _, _, origin, stop, _ = authorities[identity]
        values = dict(zip(context_names, context))
        name = f"Cell {cell} SSB {beam} {component}"
        for field in ("SweepPointIndex", "ConfiguredSNR_dB", "Seed", "TrialIndex", "ObservationID"):
            if values[field]:
                name += f" {field}={values[field]}"
        x, y = cp * 1000 / fs, frequency / 1000
        series[name].append([x, y])
        output.append(dict(values, run_id=run_id, chart_name=chart_name, series_name=name,
            x_value=x, y_value=y, x_label="Absolute TX time (ms)",
            y_label="Frequency relative to carrier centre (kHz)",
            cell_id=cell, ssb_index0=beam, allocation_id=allocation, component=component,
            native_symbol_index_from_burst=symbol, native_subcarrier_index=subcarrier,
            native_scs_hz=scs, sample_rate_hz=fs, cp_start_sample=cp,
            useful_start_sample=useful, useful_end_sample_exclusive=end,
            broadcast_start_sample=origin, broadcast_end_sample_exclusive=stop,
            mapped_port_count=len(ports), mapped_ports_0based="|".join(map(str, sorted(ports))),
            transmit_grid_sha256=digest, source_table_logical_path=path,
            evidence_scope="runtime_observed_tx_occupancy", grid_domain="ssb_native_cp_ofdm"))
    shape = "observed_timeline" if len({row["x_value"] for row in output}) > 1 else "operating_point"
    for row in output:
        row["evidence_shape_policy"] = shape
    rendered = m._render_multi_series_svg(chart_name,
        "All retained SSB occasions and sweep points; native bins, not carrier PRBs or measured power.",
        [{"name": name, "points": points} for name, points in series.items()],
        [f"source_rows={row_count}", f"SSB_occasions={len(authorities)}", "Ports unioned per transmitted RE",
         "All plotted bins retained in this CSV", "No inferred empty intervals"],
        x_label="Absolute TX time (ms)", y_label="Frequency relative to carrier centre (kHz)",
        mode="scatter", evidence_shape_policy=shape, show_all_series=True,
        max_points_per_series=None, pad_constant_axes=True, wrap_legend=True)
    return {"csv_bytes": m._encode_dict_rows(list(output[0]), output), "img_bytes": rendered,
            "csv_status": "executed_native_ssb_grid_dataset", "image_status": "generated_native_ssb_grid_svg",
            "source_table_path": path, "source_row_count": row_count, "source_mapping_status": "exact",
            "note": "Joint native SSB occupancy: each beam/occasion/SNR retains its identity; no carrier-RE conversion."}
