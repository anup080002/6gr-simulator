"""Descriptive PAPR populations must reconcile with exact raw observations."""
import hashlib
import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from lls_csv_semantics import _audit_derived_link_table


def fixture():
    raw = [{'ConfiguredSNR_dB': str(snr), 'PAPR_dB': str(value)}
           for snr, value in [(-10, 1), (-10, 2), (-10, 2), (20, 4)]]
    rows = []
    for snr, samples in [(-10, [1, 2, 2]), (20, [4])]:
        context = json.dumps({'Direction': 'DL', 'ConfiguredSNR_dB': snr})
        identity = 'DL:' + hashlib.sha256(context.encode()).hexdigest()
        for threshold in sorted(set(samples)):
            count = sum(value > threshold for value in samples)
            rows.append(dict(Direction='DL', PopulationID=identity,
                PopulationContextJSON=context, PAPR_dB=str(threshold),
                SampleCount=str(len(samples)), Exceedances=str(count),
                UnavailableSampleCount='0', CCDF=str(count / len(samples)), ThresholdComparator='>'))
    return rows, {'DL': raw, 'UL': []}


def audit(rows, raw):
    return _audit_derived_link_table('air_interface/csv/papr_ccdf.csv', list(rows[0]), rows, raw)


def test_exact_separate_populations_with_empty_ul():
    rows, raw = fixture()
    assert all(check.passed for check in audit(rows, raw))


@pytest.mark.parametrize('field,value', [('CCDF','0.5'), ('SampleCount','4'),
    ('Exceedances','1'), ('UnavailableSampleCount','1'), ('ThresholdComparator','>='),
    ('PopulationID','forged'), ('PAPR_dB','0.9'), ('Direction','UL')])
def test_corrupt_population_is_rejected(field, value):
    rows, raw = fixture()
    rows[0][field] = value
    assert any(not check.passed for check in audit(rows, raw))


def test_missing_population_is_rejected():
    rows, raw = fixture()
    assert any(not check.passed for check in audit(rows[:-1], raw))


def test_pooled_sweep_context_is_rejected():
    rows, raw = fixture()
    context = json.dumps({'Direction':'DL'})
    for row in rows:
        row['PopulationContextJSON'] = context
        row['PopulationID'] = 'DL:' + hashlib.sha256(context.encode()).hexdigest()
    assert any(not check.passed for check in audit(rows, raw))
