"""Retain every observed operating-point population without inventing BER."""
import csv
import io
import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'apps'))
import lls_contract_materializer as m


def render(rows, generic=False):
    payload = m._encode_dict_rows(list(rows[0]), rows)
    path = 'air_interface/csv/dl_pdsch_trials.csv'
    existing = {path: dict(artifact_id=1, logical_path=path)}
    if generic:
        return m._specialized_chart_materialization('BER vs SNR', existing, lambda _: payload, 1)
    return m._configured_sweep_chart_materialization('dl_ber_vs_snr', existing, lambda _: payload, 1)


def row(snr, errors, bits):
    return dict(Direction='DL', ConfiguredSNR_dB=str(snr), BitErrors=str(errors), BitsCompared=str(bits))


@pytest.mark.parametrize('generic', [False, True])
def test_all_eight_points_retained_with_unobserved_ber_not_zero(generic):
    raw = [row(snr, 'NaN' if snr < 0 else 1, 0 if snr < 0 else 100)
           for snr in [-30, -20, -10, 0, 10, 20, 30, 40]]
    result = render(raw, generic)
    records = list(csv.DictReader(io.StringIO(result['csv_bytes'].decode())))
    assert len(records) == 8 and result['source_row_count'] == 8
    assert sum(int(r['TotalTrialCount']) for r in records) == 8
    assert sum(int(r['UnpairedTrialCount']) for r in records) == 3
    assert sum(int(r['ObservedTrialCount']) for r in records) == 5
    assert all(math.isnan(float(r['BER'])) for r in records[:3])
    assert all(float(r['BER']) == 0.01 for r in records[3:])
    assert b'<polyline' not in result['img_bytes'], 'No interpolating curve across unknown points.'
    assert b'Unpaired bit attempts: 3' in result['img_bytes']
    assert b'visual_gate=' not in result['img_bytes'] and b'<circle' in result['img_bytes'], (
        'Observed equal BER values remain measurements; render the actual five measured points.')


@pytest.mark.parametrize('generic', [False, True])
def test_only_erasures_keep_counts_without_zero_ber_curve(generic):
    result = render([row(-30, 'NaN', 0), row(-20, 'NaN', 0)], generic)
    records = list(csv.DictReader(io.StringIO(result['csv_bytes'].decode())))
    assert len(records) == 2 and result['source_row_count'] == 2
    assert all(math.isnan(float(r['BER'])) and int(r['UnpairedTrialCount']) == 1 for r in records)
    assert b'<polyline' not in result['img_bytes']


def test_partial_point_retains_unpaired_count_and_weights_observed_bits():
    result = render([row(20, 10, 100), row(20, 30, 900), row(20, 'NaN', 0)])
    record = next(csv.DictReader(io.StringIO(result['csv_bytes'].decode())))
    assert float(record['BER']) == 0.04 and float(record['BitsCompared']) == 1000
    assert int(record['TotalTrialCount']) == 3 and int(record['UnpairedTrialCount']) == 1
