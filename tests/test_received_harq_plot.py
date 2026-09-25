"""Chart accounting tests; not detector statistical qualification."""
import csv
import io
import sys
from pathlib import Path

import pytest

sys.path.append(str(Path(__file__).resolve().parents[1] / 'apps'))
import lls_contract_materializer as m


def ledger(outcome, bit=1, sweep=1):
    return dict(FeedbackForDirection='DL', SweepPointIndex=str(sweep),
                ConfiguredSNR_dB='-10', SourceSlot='31', BitIndex=str(bit), UEIndex='1',
                ObservationID='rx1', UCITransport='PUCCH', FeedbackOutcome=outcome,
                ReceiverUsable=str(int(outcome != 'DTX')), ObservedAck=str(int(outcome == 'ACK')),
                AvailableAtSample='110', ObservationEndSampleExclusive='100',
                ObservationSampleRateHz='7680000', CombinedDecodeOK='1')


def chart(monkeypatch, rows):
    monkeypatch.setattr(m, '_first_available_rows', lambda *_:
                        ('control/csv/gnb_harq_feedback_observations.csv', rows))
    return m._specialized_chart_materialization('ACK/NACK timeline', {}, lambda _: b'', 1)


def test_independent_feedback_not_crc_and_png_same_population(monkeypatch):
    out = chart(monkeypatch, [ledger('NACK'), ledger('DTX', 2), ledger('ACK', 3)])
    rows = list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
    assert {r['FeedbackOutcome'] for r in rows} == {'ACK', 'NACK', 'DTX'}
    assert all(float(r['y_value']) == 1 / 3 and int(r['logical_bit_dispositions']) == 3 for r in rows)
    assert all(r['source_row_indices_json'] == '[1, 2, 3]' for r in rows)
    assert b'visual_gate=' not in out['img_bytes']
    assert b'<circle' in out['img_bytes'], 'A valid PNG header alone does not prove plotted measurements'
    png = m._rasterize_contract_png(out['img_bytes'], source_mime_type='image/svg+xml')
    assert png.startswith(b'\x89PNG')


def test_sweep_points_not_pooled(monkeypatch):
    out = chart(monkeypatch, [ledger('ACK'), ledger('NACK', sweep=2)])
    rows = list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
    assert len(rows) == 6 and all(int(r['logical_bit_dispositions']) == 1 for r in rows)


def test_all_eight_sweep_points_and_three_outcomes_have_visible_legend(monkeypatch):
    inputs = []
    for point, snr in enumerate([-30, -20, -10, 0, 10, 20, 30, 40], 1):
        row = ledger('DTX', sweep=point); row['ConfiguredSNR_dB'] = str(snr)
        inputs.append(row)
    out = chart(monkeypatch, inputs)
    rows = list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
    svg = out['img_bytes'].decode()
    assert len(rows) == 24
    for row in rows:
        assert row['series_name'] in svg, 'Every plotted outcome/point needs its visible label'


@pytest.mark.parametrize('field,value', [('ObservedAck', '1'), ('ReceiverUsable', '1'),
    ('AvailableAtSample', '99'), ('SweepPointIndex', ''), ('ObservationID', ''), ('BitIndex', '0')])
def test_corrupt_evidence_not_replaced_by_data_crc(monkeypatch, field, value):
    row = ledger('DTX'); row[field] = value
    with pytest.raises(ValueError):
        chart(monkeypatch, [row])


def test_duplicate_bit_rejected(monkeypatch):
    with pytest.raises(ValueError, match='Duplicate'):
        chart(monkeypatch, [ledger('ACK'), ledger('ACK')])


def test_missing_ledger_does_not_use_crc(monkeypatch):
    assert chart(monkeypatch, [])['csv_status'] == 'unavailable_exact_reason'
