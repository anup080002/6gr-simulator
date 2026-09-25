"""Raw PUCCH decoded-bit/erasure accounting, not detector qualification."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from lls_csv_semantics import _audit_control_table, _pucch_bit_comparison_failures


def row(**changes):
    result = dict(ExpectedBitCount='4', DecodedBitCount='4', BitsCompared='4', BitErrors='1',
                  UCIExpectedBitVector='0101', UCIDecodedBitVector='0001', UCIBitErrorVector='0100')
    result.update(changes)
    return result


def test_complete_actual_pairs_and_bracket_encoding():
    assert not _pucch_bit_comparison_failures(row())
    assert not _pucch_bit_comparison_failures(row(UCIExpectedBitVector='[0|1|0|1]'))


@pytest.mark.parametrize('decoded', ['0', '3', '5'])
def test_erasures_or_mismatched_hypotheses_do_not_fabricate_bit_errors(decoded):
    assert not _pucch_bit_comparison_failures(row(DecodedBitCount=decoded, BitsCompared='0',
                                               BitErrors='NaN', UCIBitErrorVector=''))


@pytest.mark.parametrize('changes', [dict(DecodedBitCount='0', BitsCompared='0', BitErrors='4'),
    dict(DecodedBitCount='3', BitsCompared='3', BitErrors='1'), dict(BitErrors='5'),
    dict(BitErrors='NaN'), dict(BitErrors='1.5'), dict(UCIBitErrorVector='0000'),
    dict(UCIDecodedBitVector='unavailable'), dict(BitsCompared='0', BitErrors='NaN'),
    dict(DecodedBitCount='0', BitsCompared='0', BitErrors='NaN', UCIBitErrorVector='1111')])
def test_invalid_padding_prefix_or_error_vector_not_certified(changes):
    assert _pucch_bit_comparison_failures(row(**changes))


def test_primary_control_audit_detects_retained_zero_denominator_bug():
    raw = row(ExpectedBitCount='14', DecodedBitCount='0', BitsCompared='0', BitErrors='14')
    checks = _audit_control_table('air_interface/csv/pucch_trials.csv', list(raw), [raw])
    assert not next(c for c in checks if c.check_id == 'paired_pucch_bit_evidence').passed
