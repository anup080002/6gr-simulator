"""Clock arithmetic fixtures, not a physical latency campaign."""
import csv
import io
import re
import sys
from pathlib import Path

import pytest

candidate = Path(__file__).resolve().parents[1]
root = candidate.parents[1]
sys.path.insert(0, str(root / 'apps'))
sys.path.insert(0, str(candidate / 'apps'))
import lls_contract_materializer as m
from lls_received_harq_latency_plot import received_feedback_latency_chart


def packet(**updates):
    row = dict(RTTStatus='measured_independent_usable_feedback_completion', RTT_ms='2.7',
               SweepPointIndex='1', ConfiguredSNR_dB='-10', UEIndex='1', FeedbackBitIndex='1',
               DataTransmitSymbolStartSample='100', DataTransmitSymbolEndSampleExclusive='500',
               DataTransmitSampleRateHz='1000000', FeedbackAvailableAtSample='2800',
               FeedbackSampleRateHz='1000000', FeedbackObservationID='rx1', PHYGrantContextId='g1',
               FeedbackTransport='PUCCH', Direction='DL', FeedbackObservationAvailable='1',
               DTX='0', ACK='1', NACK='0', ScheduledFeedbackOffset_ms='2',
               DataTransmitTimingSource='executed_prepared_waveform_origin_and_OFDM_symbol_lengths')
    row.update(updates)
    return row


def chart(monkeypatch, records):
    monkeypatch.setattr(m, '_first_available_rows', lambda *_:
                        ('harq/csv/probe_harq_packets.csv', records))
    return received_feedback_latency_chart({}, lambda _: b'', 1)


def test_actual_latency_not_schedule_and_visible_png(monkeypatch):
    out = chart(monkeypatch, [packet()])
    rows = list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
    assert len(rows) == 1 and float(rows[0]['x_value']) == 2.7
    assert rows[0]['source_row_indices_json'] == '[1]'
    assert b'<circle' in out['img_bytes'] and b'visual_gate=' not in out['img_bytes']
    point = re.search(rb'<circle cx="([\d.]+)" cy="([\d.]+)"', out['img_bytes'])
    assert point and 126 < float(point[1]) < 868 and 134 < float(point[2]) < 524
    assert m._rasterize_contract_png(out['img_bytes'], source_mime_type='image/svg+xml').startswith(b'\x89PNG')


def test_sweep_transport_populations_not_pooled(monkeypatch):
    out = chart(monkeypatch, [packet(), packet(SweepPointIndex='2', ConfiguredSNR_dB='20'),
                            packet(FeedbackTransport='PUSCH')])
    rows = list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
    assert len(rows) == 3 and all(float(row['y_value']) == 1 for row in rows)
    assert all(row['series_name'] in out['img_bytes'].decode() for row in rows)


def test_dtx_excluded_with_reason_not_scheduled_delay(monkeypatch):
    dtx = packet(RTTStatus='unavailable_DTX_disposition_not_usable_feedback', RTT_ms='NaN',
                 DTX='1', ACK='0', FeedbackDispositionLatency_ms='2.7')
    out = chart(monkeypatch, [packet(), dtx])
    rows = list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
    assert len(rows) == 1 and 'unavailable_DTX_disposition' in rows[0]['excluded_rows_json']
    assert chart(monkeypatch, [dtx])['csv_status'] == 'unavailable_exact_reason'


def test_legacy_schedule_never_used_as_measured_rtt(monkeypatch):
    assert chart(monkeypatch, [dict(Slot='31', FeedbackDueSlot='34', RTT_ms='3')])[
        'csv_status'] == 'unavailable_exact_reason'


@pytest.mark.parametrize('field,value', [('RTT_ms', '2'), ('FeedbackSampleRateHz', '2000000'),
    ('FeedbackAvailableAtSample', '400'), ('DataTransmitSymbolStartSample', '-1'),
    ('DataTransmitTimingSource', 'configured_k1'), ('FeedbackObservationID', ''),
    ('DTX', '1'), ('ACK', '0'), ('Direction', 'UL'), ('FeedbackObservationAvailable', '0')])
def test_corrupt_clock_and_identity_rejected(monkeypatch, field, value):
    with pytest.raises(ValueError):
        chart(monkeypatch, [packet(**{field: value})])


def test_duplicate_observation_rejected(monkeypatch):
    with pytest.raises(ValueError, match='Duplicate'):
        chart(monkeypatch, [packet(), packet()])


def test_main_chart_router_uses_received_clock_contract(monkeypatch):
    monkeypatch.setattr(m, '_first_available_rows', lambda *_:
                        ('harq/csv/probe_harq_packets.csv', [packet()]))
    result = m._specialized_chart_materialization('HARQ RTT distribution', {}, lambda _: b'', 1)
    assert '2.7' in result['csv_bytes'].decode()
    assert 'Observed usable-feedback RTT (ms)' in result['csv_bytes'].decode()
