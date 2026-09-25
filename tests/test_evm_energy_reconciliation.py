import math
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from lls_csv_semantics import _evm_energy_failures


def evidence(error=4.0, reference=100.0):
    return dict(EVM_rms=str(math.sqrt(error / reference)),
                EVMErrorEnergy=str(error), EVMReferenceEnergy=str(reference),
                EVMSymbolCount="100", EVMStatus="OK",
                EVMEnergyUnit="sum_squared_complex_symbol_amplitude_not_joules",
                EVMComputationDomain="receiver_equalized_symbols_average_reference_power_no_payload_fit")


@pytest.mark.parametrize("scale", [1e-20, 1.0, 1e20])
@pytest.mark.parametrize("error", [0.0, 4.0, 100.0])
def test_valid_symbol_energy_ratio_preserves_scale_and_zero(scale, error):
    assert not _evm_energy_failures(evidence(error * scale, 100.0 * scale))


@pytest.mark.parametrize("field,value", [
    ("EVM_rms", "0.01"), ("EVMErrorEnergy", "-1"),
    ("EVMReferenceEnergy", "0"), ("EVMReferenceEnergy", "NaN"),
    ("EVMSymbolCount", "0"), ("EVMSymbolCount", "1.5"),
    ("EVMEnergyUnit", "joules"), ("EVMComputationDomain", "fitted_gain"),
    ("EVMStatus", "unavailable"),
])
def test_inconsistent_evm_evidence_is_not_accepted(field, value):
    row = evidence()
    row[field] = value
    assert _evm_energy_failures(row)


@pytest.mark.parametrize("field", list(evidence()))
def test_missing_operand_or_identity_is_not_filled(field):
    row = evidence()
    del row[field]
    assert _evm_energy_failures(row)
