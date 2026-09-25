"""Rate export accounting fixtures; not a PHY or throughput qualification."""
import csv
import io
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'apps'))
import lls_contract_materializer as m


def timeline(rows):
    return m._runtime_throughput_timeline_chart('goodput over time',
        [('air_interface/csv/dl_pdsch_trials.csv', rows)], 1)


def test_zero_measured_goodput_is_a_visible_timeline():
    out = timeline([dict(Slot=str(slot), Goodput_Mbps='0', Throughput_Mbps='6')
                    for slot in [31, 32, 33]])
    rows = list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
    assert [float(row['y_value']) for row in rows] == [0, 0, 0]
    assert b'visual_gate=' not in out['img_bytes']
    assert out['uniform_runtime_evidence_is_valid']
    png = m._rasterize_contract_png(out['img_bytes'], source_mime_type='image/svg+xml')
    assert png.startswith(b'\x89PNG')


def test_missing_goodput_is_not_replaced_by_offered_bits():
    assert timeline([dict(Slot='31', Throughput_Mbps='6', OfferedThroughput_Mbps='6')]) is None


def test_missing_clock_is_not_invented_from_row_number():
    assert timeline([dict(Goodput_Mbps='0')]) is None


def test_sweep_and_clock_domains_are_not_summed():
    out = timeline([
        dict(Slot='31', SweepPointIndex='1', ConfiguredSNR_dB='-10', Goodput_Mbps='0'),
        dict(Slot='31', SweepPointIndex='2', ConfiguredSNR_dB='20', Goodput_Mbps='4'),
        dict(Time_ms='31', SweepPointIndex='2', ConfiguredSNR_dB='20', Goodput_Mbps='2')])
    rows = list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
    assert len(rows) == 3
    assert len({r['series_name'] for r in rows}) == 3
    assert sorted(float(r['y_value']) for r in rows) == [0, 2, 4]
    assert all(r['source_trial_indices_json'] for r in rows)


def test_negative_rate_is_invalid():
    with pytest.raises(ValueError, match='negative'):
        timeline([dict(Slot='31', Goodput_Mbps='-1')])


def spectral(monkeypatch, rows, authorities):
    monkeypatch.setattr(m, '_artifact_rows_by_path', lambda *_: ([], authorities))
    monkeypatch.setattr(m, '_all_available_rows', lambda *_: [
        ('air_interface/csv/dl_pdsch_trials.csv', rows)])
    return m._specialized_chart_materialization('spectral efficiency', {}, lambda _: b'', 1)


@pytest.mark.parametrize('bandwidth', [5e6, 400e6])
def test_spectral_efficiency_uses_actual_bandwidth(monkeypatch, bandwidth):
    identity = dict(ScenarioID='scenario', ConfigHash='hash')
    out = spectral(monkeypatch, [
        dict(**identity, Goodput_Mbps='20', Throughput_Mbps='50'),
        dict(**identity, Goodput_Mbps='0')],
        [dict(**identity, ConfiguredBandwidth_Hz=str(bandwidth))])
    rows = list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
    assert float(rows[0]['spectral_efficiency_bps_hz']) == 20e6 / bandwidth
    assert float(rows[1]['spectral_efficiency_bps_hz']) == 0
    assert all(float(r['channel_bandwidth_hz']) == bandwidth for r in rows)
    assert b'visual_gate=' not in out['img_bytes']


def test_spectral_efficiency_does_not_use_offered_rate(monkeypatch):
    assert spectral(monkeypatch, [dict(Throughput_Mbps='100')], []) is None


@pytest.mark.parametrize('authority', [
    [],
    [dict(ScenarioID='scenario', ConfigHash='stale', ConfiguredBandwidth_Hz='5000000')],
    [dict(ScenarioID='scenario', ConfigHash='hash', ConfiguredBandwidth_Hz='0')],
    [dict(ScenarioID='scenario', ConfigHash='hash', ConfiguredBandwidth_Hz=str(bw))
     for bw in [5e6, 400e6]],
])
def test_missing_or_conflicting_bandwidth_does_not_get_a_default(monkeypatch, authority):
    with pytest.raises(ValueError, match='bandwidth'):
        spectral(monkeypatch, [dict(ScenarioID='scenario', ConfigHash='hash', Goodput_Mbps='1')], authority)
