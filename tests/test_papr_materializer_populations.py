"""Constructed CCDF accounting fixtures, not a physical qualification campaign."""
import csv
import io
import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'apps'))
import lls_contract_materializer as materializer


def chart(monkeypatch, dl, ul=()):
    sources = [('air_interface/csv/dl_pdsch_trials.csv', dl),
               ('air_interface/csv/ul_pusch_trials.csv', ul)]
    monkeypatch.setattr(materializer, '_all_available_rows', lambda *_args: sources)
    return materializer._runtime_papr_distribution_chart('PAPR histogram / CDF', {}, lambda _: b'', 42)


def test_snr_rank_direction_and_ties_are_not_pooled(monkeypatch, tmp_path):
    dl = [dict(ConfiguredSNR_dB=str(snr), Layers=str(rank), Modulation='QPSK',
               MCS='0', PAPR_dB=str(value))
          for snr, rank, value in [(-10, 1, 1), (-10, 1, 2), (-10, 1, 2),
                                   (20, 1, 8), (20, 1, 9), (20, 2, 10)]]
    dl.append({**dl[0], 'PAPR_dB':'NaN'})
    captured = []
    renderer = materializer._render_multi_series_svg
    def render(*args, **kwargs):
        captured.extend(args[2])
        return renderer(*args, **kwargs)
    monkeypatch.setattr(materializer, '_render_multi_series_svg', render)
    out = chart(monkeypatch, dl, [dict(ConfiguredSNR_dB='20', PAPR_dB='7')])
    rows = list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
    assert out['source_row_count'] == 7 and len(captured) == 4
    identities=list(dict.fromkeys(row['population_id'] for row in rows))
    first = [r for r in rows if r['population_id'] == identities[0]]
    assert [float(r['ccdf']) for r in first] == [2/3, 0]
    assert [int(r['sample_count']) for r in first] == [3, 3]
    assert all(int(r['unavailable_sample_count'])==1 for r in first)
    assert json.loads(first[0]['source_trial_indices_json']) == [1, 2, 3]
    for identity, series in zip(identities, captured):
        exported = [[float(r['papr_threshold_db']), float(r['ccdf'])]
                    for r in rows if r['population_id'] == identity]
        assert series['points'] == exported
    assert b'<svg' in out['img_bytes'] and b'Empirical CCDF' in out['img_bytes']
    png=materializer.resvg_py.svg_to_bytes(svg_string=out['img_bytes'].decode(), background='#ffffff')
    (tmp_path/'papr_populations.png').write_bytes(png)
    with materializer.Image.open(io.BytesIO(png)) as image:
        assert image.format=='PNG' and image.width==1280 and image.height>=720


def test_runtime_mcs_changes_are_separate(monkeypatch):
    out = chart(monkeypatch, [dict(PAPR_dB='4', MCS=str(mcs)) for mcs in [0, 1]])
    rows = list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
    assert len({row['population_id'] for row in rows}) == 2


def test_measurement_window_and_plane_are_separate(monkeypatch):
    context = dict(ContractVersion='tx_papr/v1', Source='actual_supplied_transmitter_waveform',
        MeasurementPoint='pre_rf', ReferenceDomain='CP_excluded', InputWaveformSampleCount=128,
        AggregateRule='maximum_finite_per_port_PAPR', PerPort=dict(PortIndex=1,
        OversamplingFactor=1, MeasuredSampleCount=120, InputSampleCount=120,
        OversamplingDefinition='additional_periodic_fft_interpolation_of_input_block'))
    observations = []
    for plane, domain in [('pre_rf','CP_excluded'), ('post_rf','CP_excluded'), ('post_rf','CP_included')]:
        observations.append(dict(PAPR_dB='4', PAPRMeasurementJSON=json.dumps({**context,
            'MeasurementPoint':plane, 'ReferenceDomain':domain})))
    out = chart(monkeypatch, observations)
    rows = list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
    assert len({row['population_id'] for row in rows}) == 3
    assert [json.loads(row['measurement_context_json'])['MeasurementPoint'] for row in rows] == [
        'pre_rf','post_rf','post_rf']
    with pytest.raises(ValueError, match='Incomplete PAPR measurement context'):
        chart(monkeypatch, [dict(PAPR_dB='4',PAPRMeasurementJSON='{}')])


def test_child_run_identifiers_do_not_collide(monkeypatch):
    ids=[]
    for snr in [-10,20,-10]:
        out=chart(monkeypatch,[dict(ConfiguredSNR_dB=str(snr),PAPR_dB='4')])
        rows=list(csv.DictReader(io.StringIO(out['csv_bytes'].decode())))
        ids.append(rows[0]['population_id'])
    assert ids[0]!=ids[1] and ids[0]==ids[2]


def test_no_finite_measurement_creates_no_measurement(monkeypatch):
    assert chart(monkeypatch, [dict(PAPR_dB='NaN')]) is None


def test_contradictory_direction_is_not_relabeled(monkeypatch):
    with pytest.raises(ValueError, match='direction contradicts'):
        chart(monkeypatch, [dict(PAPR_dB='4', Direction='UL')])
