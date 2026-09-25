"""Explicit no-observation panel, never fabricated PDCCH channel samples."""


def unobserved_pdcch_channel_chart(chart_name, existing, fetch, run_id):
    import lls_contract_materializer as m

    if chart_name not in {"PDCCH channel-estimate magnitude", "PDCCH channel-estimate phase"}:
        return None
    # A complete, identity-consistent clock and zero DL grants are necessary,
    # but not sufficient: common-control reception can exist without data.
    sources = m._recorded_direction_without_data_sources(existing, fetch, "DL")
    if not sources:
        return None
    required = {"Slot", "Direction", "CRCPass", "DecodeAttempted",
                "ChannelEstimateAvailable", "ConfiguredSNR_dB"}
    for path in ("control/csv/pdcch_trials.csv", "air_interface/csv/pdcch_trials.csv"):
        columns, rows = m._artifact_rows_by_path(existing, fetch, path)
        if not required.issubset(columns) or rows:
            return None
        sources.append(path)
    estimate_path = "control/csv/pdcch_channel_estimates.csv"
    if estimate_path in existing:
        columns, rows = m._artifact_rows_by_path(existing, fetch, estimate_path)
        if rows or not {"HReal", "HImag", "RxPortIndex0", "ReferencePortIndex0"}.issubset(columns):
            return None  # Contradictory/malformed capture must reach strict validation.
        sources.append(estimate_path)
    _, state = m._artifact_rows_by_path(existing, fetch, "reports/csv/run_state.csv")
    point = m._row_float(state[0], "ConfiguredSNR_dB")
    slots = int(m._row_float(state[0], "CurrentCanonicalSlot"))
    reason = (f"No PDCCH receiver occasion was recorded over {slots} completed slots "
              f"at configured reference SNR {point:g} dB; a channel estimate was not observed. "
              "This does not certify acquisition, control scheduling or overall scenario success.")
    return dict(
        csv_bytes=m._encode_csv(
            ["run_id", "chart_name", "status", "ConfiguredSNR_dB", "CompletedSlots", "reason"],
            [[run_id, chart_name, "unavailable_no_recorded_pdcch_reception", point, slots, reason]]),
        img_bytes=m._render_reason_svg(chart_name, "PDCCH channel estimate: not observed", [reason]),
        csv_status="unavailable_exact_reason", image_status="generated_unavailable_reason_svg",
        source_table_path="|".join(sources), source_row_count=0,
        source_mapping_status="unavailable_completed_clock_without_recorded_pdcch_reception",
        note=reason)
