import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'apps'))
from lls_contract_materializer import _semantic_companion_mask, _canonicalize_contract_source_rows

def test_sentinels_and_pmi_type_are_not_measurements():
    row = {'AppliedBeamIndexSet': 'not_recorded_by_active_x_runtime',
           'AppliedPrecoderPMI': 'NaN', 'AppliedPrecoderPMIType': 'explicit_matrix'}
    assert _semantic_companion_mask([row], 'AppliedBeamValueStatus') == [False]
    assert _semantic_companion_mask([row], 'AppliedPrecoderValueStatus') == [False]
    row['AppliedPrecoderPMI'] = '0'
    assert _semantic_companion_mask([row], 'AppliedPrecoderValueStatus') == [True]

def test_existing_false_available_is_not_republished():
    header=['AppliedBeamIndexSet','AppliedBeamValueStatus','AppliedPrecoderPMI','AppliedPrecoderPMIType','AppliedPrecoderValueStatus']
    rows=[['not_recorded_by_active_x_runtime','available','NaN','explicit_matrix','available'],
          ['[0 1]','measured','0','type1','measured']]
    _, out_header, out = _canonicalize_contract_source_rows('air_interface/csv/dl_pdsch_trials.csv',header,rows)
    assert out[0][out_header.index('AppliedBeamValueStatus')] == 'unavailable'
    assert out[0][out_header.index('AppliedPrecoderValueStatus')] == 'unavailable'
    assert out[1][out_header.index('AppliedPrecoderValueStatus')] == 'measured'


def test_sinr_needs_value_and_actual_definition():
    header = ['SINR_dB', 'SINRValueDefinition', 'SINRValueStatus']
    rows = [['12', 'not_emitted_by_active_x_runtime', 'available'],
            ['NaN', 'measured_dmrs_residual', 'available'],
            ['0', 'measured_dmrs_residual', 'measured']]
    _, _, out = _canonicalize_contract_source_rows('air_interface/csv/dl_pdsch_trials.csv', header, rows)
    assert out[0][2] == 'unavailable_definition_not_recorded'
    assert out[1][2] == 'unavailable'
    assert out[2][2] == 'measured'
