"""Observed usable-feedback latency; never configured k1 or retransmission span."""
import json
import math
from collections import defaultdict


def received_feedback_latency_chart(existing, fetch, run_id):
    import lls_contract_materializer as m
    paths = ['harq/csv/probe_harq_packets.csv', 'harq/csv/harq_process_timeline.csv']
    path, records = m._first_available_rows(existing, fetch, paths)
    populations = defaultdict(list)
    excluded = defaultdict(int)
    seen = set()
    for index, row in enumerate(records, 1):
        status = m._row_text(row, 'RTTStatus')
        rtt = m._row_float(row, 'RTT_ms')
        if status != 'measured_independent_usable_feedback_completion':
            if rtt is not None and status:
                raise ValueError('Unmeasured feedback must not carry a measured RTT')
            excluded[status or 'legacy_no_executed_RTT_contract'] += 1
            continue
        names = ['SweepPointIndex', 'ConfiguredSNR_dB', 'UEIndex', 'FeedbackBitIndex',
                 'DataTransmitSymbolStartSample', 'DataTransmitSymbolEndSampleExclusive',
                 'DataTransmitSampleRateHz', 'FeedbackAvailableAtSample', 'FeedbackSampleRateHz']
        values = [m._row_float(row, name) for name in names]
        if rtt is None or any(v is None for v in values):
            raise ValueError('Measured RTT requires complete executed clock and identity evidence')
        sweep, snr, ue, bit, start, end, fs, available, feedback_fs = values
        observation = m._row_text(row, 'FeedbackObservationID')
        grant = m._row_text(row, 'PHYGrantContextId')
        transport = m._row_text(row, 'FeedbackTransport')
        if (any(v != int(v) for v in [sweep, ue, bit, start, end, available]) or
                min(sweep, ue, bit) < 1 or start < 0 or end <= start or available < end or
                fs <= 0 or fs != feedback_fs or not observation or not grant or
                transport not in {'PUCCH', 'PUSCH'} or m._row_text(row, 'Direction') != 'DL' or
                m._row_text(row, 'DataTransmitTimingSource') !=
                'executed_prepared_waveform_origin_and_OFDM_symbol_lengths' or
                m._row_float(row, 'FeedbackObservationAvailable') != 1 or
                m._row_float(row, 'DTX') != 0 or
                (m._row_float(row, 'ACK'), m._row_float(row, 'NACK')) not in {(1, 0), (0, 1)}):
            raise ValueError('Contradictory measured RTT clocks or feedback identity')
        measured = 1000 * (available - start) / fs
        if not math.isclose(rtt, measured, rel_tol=1e-10, abs_tol=1e-10):
            raise ValueError('RTT disagrees with actual TX-to-feedback clock interval')
        identity = (sweep, ue, transport, observation, bit)
        if identity in seen:
            raise ValueError('Duplicate received feedback RTT observation')
        seen.add(identity)
        populations[(sweep, snr, ue, transport, rtt)].append(index)
    excluded_json = json.dumps(dict(sorted(excluded.items())))
    if not populations:
        reason = ('No usable received-feedback RTT with an executed TX-symbol clock. '
                  'Configured feedback offsets and DTX are not measured usable-feedback RTT. '
                  f'Excluded rows: {excluded_json}')
        return dict(csv_bytes=m._encode_csv(['status', 'reason'], [['unavailable_exact_reason', reason]]),
                    img_bytes=m._render_reason_svg('HARQ RTT distribution', reason, paths),
                    csv_status='unavailable_exact_reason', image_status='generated_unavailable_reason_svg',
                    source_table_path=path, source_row_count=len(records), note=reason)
    rows = []
    series = defaultdict(list)
    for (sweep, snr, ue, transport, rtt), indices in sorted(populations.items()):
        label = f'p{sweep:g} {snr:g}dB u{ue:g} {transport}'
        series[label].append([rtt, len(indices)])
        rows.append(dict(run_id=run_id, chart_name='HARQ RTT distribution', series_name=label,
                         chart_mode='scatter', x_label='Observed usable-feedback RTT (ms)',
                         y_label='Observed attempt count', x_value=rtt, y_value=len(indices),
                         SweepPointIndex=sweep, ConfiguredSNR_dB=snr, UEIndex=ue,
                         FeedbackTransport=transport, source_table_logical_path=path,
                         source_row_indices_json=json.dumps(indices), excluded_rows_json=excluded_json))
    shape = 'operating_point' if len({row['x_value'] for row in rows}) == 1 else 'observed_distribution'
    for row in rows:
        row['evidence_shape_policy'] = shape
    note = ('Actual TX-symbol start to independently received usable ACK/NACK availability; '
            'per-attempt observations, not independent episode statistics. '
            f'Excluded rows: {excluded_json}')
    return dict(csv_bytes=m._encode_dict_rows(list(rows[0]), rows),
                img_bytes=m._render_multi_series_svg('HARQ RTT distribution', note,
                    [dict(name=key, points=value) for key, value in series.items()],
                    [f'source_table={path}', f'usable_attempts={len(seen)}'],
                    x_label='Observed usable-feedback RTT (ms)', y_label='Observed attempt count',
                    mode='scatter', evidence_shape_policy=shape, show_all_series=True,
                    pad_constant_axes=True),
                csv_status='derived_chart_dataset', image_status='generated_specialized_runtime_summary_svg',
                source_table_path=path, source_row_count=len(records), note=note,
                uniform_runtime_evidence_is_valid=True)
