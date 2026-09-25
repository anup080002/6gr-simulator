"""Received logical HARQ-bit outcomes, never data-CRC substitutes."""
import json
from collections import defaultdict


def received_feedback_chart(existing, fetch, run_id):
    import lls_contract_materializer as m
    paths = ['control/csv/gnb_harq_feedback_observations.csv',
             'air_interface/csv/gnb_harq_feedback_observations.csv']
    path, records = m._first_available_rows(existing, fetch, paths)
    if not records:
        reason = 'No independently received HARQ-bit observation ledger; data CRC is not received ACK/NACK.'
        return dict(csv_bytes=m._encode_csv(['status', 'reason'], [['unavailable_exact_reason', reason]]),
                    img_bytes=m._render_reason_svg('ACK/NACK timeline', reason, paths),
                    csv_status='unavailable_exact_reason', image_status='generated_unavailable_reason_svg',
                    source_table_path='', source_row_count=0, note=reason)
    grouped = defaultdict(list)
    seen = set()
    for index, row in enumerate(records, 1):
        if m._row_text(row, 'FeedbackForDirection') != 'DL':
            raise ValueError('Received HARQ plot requires explicit DL feedback direction')
        sweep = m._row_float(row, 'SweepPointIndex')
        snr = m._row_float(row, 'ConfiguredSNR_dB')
        slot = m._row_float(row, 'SourceSlot')
        bit = m._row_float(row, 'BitIndex')
        ue = m._row_float(row, 'UEIndex')
        observation = m._row_text(row, 'ObservationID')
        transport = m._row_text(row, 'UCITransport')
        outcome = m._row_text(row, 'FeedbackOutcome')
        if (any(x is None or x != int(x) for x in [sweep, slot, bit, ue]) or
                sweep < 1 or slot < 0 or bit < 1 or ue < 1 or snr is None or not observation or
                transport not in {'PUCCH', 'PUSCH'} or outcome not in {'ACK', 'NACK', 'DTX'}):
            raise ValueError('Received HARQ plot has incomplete identity/outcome evidence')
        usable = m._row_float(row, 'ReceiverUsable')
        ack = m._row_float(row, 'ObservedAck')
        if usable != int(outcome != 'DTX') or ack != int(outcome == 'ACK'):
            raise ValueError('Contradictory independently received HARQ outcome')
        available = m._row_float(row, 'AvailableAtSample')
        end = m._row_float(row, 'ObservationEndSampleExclusive')
        fs = m._row_float(row, 'ObservationSampleRateHz')
        if available is None or end is None or fs is None or fs <= 0 or available < end:
            raise ValueError('Received HARQ plot requires completed observation clocks')
        identity = (sweep, ue, transport, observation, bit)
        if identity in seen:
            raise ValueError('Duplicate received HARQ logical bit')
        seen.add(identity)
        grouped[(sweep, snr, ue, transport, slot)].append((index, outcome, observation, bit))
    rows = []
    series = defaultdict(list)
    for (sweep, snr, ue, transport, slot), population in sorted(grouped.items()):
        for outcome in ['ACK', 'NACK', 'DTX']:
            count = sum(item[1] == outcome for item in population)
            fraction = count / len(population)
            label = f'{outcome} p{sweep:g} {snr:g}dB u{ue:g} {transport}'
            series[label].append([slot, fraction])
            rows.append(dict(run_id=run_id, chart_name='ACK/NACK timeline', series_name=label,
                             chart_mode='line', x_label='DL transmission source slot',
                             y_label='Received logical-bit disposition fraction',
                             x_value=slot, y_value=fraction, SweepPointIndex=sweep,
                             ConfiguredSNR_dB=snr, UEIndex=ue, UCITransport=transport,
                             FeedbackOutcome=outcome, outcome_count=count,
                             logical_bit_dispositions=len(population),
                             source_table_logical_path=path,
                             source_row_indices_json=json.dumps([x[0] for x in population]),
                             observation_bit_identities_json=json.dumps([[x[2], x[3]] for x in population])))
    note = ('Independently received logical HARQ-bit dispositions, including DTX; grouped by source '
            'slot, sweep, UE and transport. Not independent-occasion or transmitter-silence probabilities.')
    plotted = [dict(name=key, points=value) for key, value in series.items()]
    mode = 'line' if all(len(item['points']) >= 3 for item in plotted) else 'scatter'
    shape = ('operating_point' if len({point[0] for item in plotted for point in item['points']}) == 1
             else 'observed_timeline')
    for row in rows:
        row['chart_mode'] = mode
        row['evidence_shape_policy'] = shape
    return dict(csv_bytes=m._encode_dict_rows(list(rows[0]), rows),
                img_bytes=m._render_multi_series_svg('ACK/NACK/DTX timeline', note, plotted,
                    [f'source_table={path}', f'logical_bits={len(records)}'],
                    x_label='DL transmission source slot',
                    y_label='Received logical-bit disposition fraction', mode=mode,
                    evidence_shape_policy=shape, show_all_series=True),
                csv_status='derived_chart_dataset', image_status='generated_specialized_runtime_summary_svg',
                source_table_path=path, source_row_count=len(records), note=note,
                uniform_runtime_evidence_is_valid=True)
