"""Zero EVM is a valid measurement, not infinite primary receiver SINR."""
import sys
from pathlib import Path

import pytest

candidate = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(candidate / 'tools'))
from lls_csv_semantics import _audit_link_table


def valid_zero():
    return dict(Direction='DL', Frame='1', Slot='1', UEID='1',
                NoiseVariance='1', PostEqualizationNoiseVariance='1', LLRNoiseVariance='1',
                MeasuredTrialSINR_dB='0', PostEqSINR_dB='0',
                MeasuredTrialSINRSource='equalizer', PostEqSINRSource='equalizer',
                EVM_rms='0', EVMErrorEnergy='0', EVMReferenceEnergy='100',
                EVMSymbolCount='100', EVMStatus='OK',
                EVMEnergyUnit='sum_squared_complex_symbol_amplitude_not_joules',
                EVMComputationDomain='receiver_equalized_symbols_average_reference_power_no_payload_fit',
                EVMProxySINR_dB='Inf', EVMProxySINRValueStatus='zero_error_unbounded_diagnostic')


def check(row):
    checks = _audit_link_table('measured.csv', list(row), [row], 'DL', 1)
    return next(item for item in checks if item.check_id == 'noise_sinr_evm_lineage')


def test_zero_error_and_unbounded_diagnostic_preserved():
    assert check(valid_zero()).passed


@pytest.mark.parametrize('field,value', [('EVMErrorEnergy', '1'), ('EVMErrorEnergy', '1e-30'),
    ('EVMReferenceEnergy', '0'),
    ('EVMProxySINR_dB', '156.535597745'), ('EVMProxySINR_dB', '-Inf'),
    ('EVMProxySINR_dB', 'NaN'), ('EVMProxySINRValueStatus', 'OK'),
    ('PostEqSINR_dB', 'Inf'), ('EVMSymbolCount', '0')])
def test_no_epsilon_cap_or_primary_sinr_substitution(field, value):
    row = valid_zero(); row[field] = value
    assert not check(row).passed
