"""An unexecuted direction can retain configuration, never applied rank."""
import sys
from pathlib import Path

import pytest

sys.path[:0] = [str(Path(__file__).resolve().parents[1]/'tools')]
import lls_csv_semantics as audit
from test_lls_csv_semantics import _mimo_configured_effective_row, _strict_mimo_config_row
from test_zero_attempt_semantic_authority import persist, tables


def rows():
    config, summary = _strict_mimo_config_row(), _mimo_configured_effective_row()
    for row in (config, summary):
        row.update(Direction='UL', Status='not_validated', RuntimePopulated='0',
                   RuntimeTrialCount='0', RuntimeRank2Fraction='NaN', RuntimeExactMatchFraction='NaN',
                   RuntimeEvidenceSource='no_runtime_trials', EvidenceClass='CONFIGURATION_WITH_RUNTIME_LINKAGE_PENDING')
    for field in summary:
        if field.startswith('Dominant'):
            summary[field] = '' if field.endswith('Modulation') else 'NaN'
        elif field.endswith('RowCount'):
            summary[field] = '0'
        elif field.endswith('Percent') and not field.startswith('Required'):
            summary[field] = 'NaN'
    summary.update(ScenarioObjectivePass='0', FailureReason='no_runtime_trials')
    return config, summary


def evaluate(config, summary, proof=frozenset({'UL'})):
    return audit._audit_mimo_config_strict_table('config.csv', list(config), [config], [], [summary], [], proof) + \
        audit._audit_mimo_configured_effective_table('summary.csv', list(summary), [summary], [], proof)


def test_no_attempt_configuration_requires_independent_proof():
    config, summary = rows()
    assert all(c.passed for c in evaluate(config, summary))
    assert any(not c.passed for c in evaluate(config, summary, frozenset()))
    assert summary['ScenarioObjectivePass']=='0'  # audit pass is not a PHY pass


def test_companion_entrypoint_requires_completed_clock_and_empty_grants(tmp_path):
    config, summary=rows()
    data=tables()
    data[audit.MIMO_RANK_LAYER_TABLE]=(['Direction','StrictEligible'],[])
    data['beamforming/csv/mimo_config_strict.csv']=(list(config),[config])
    data['beamforming/csv/mimo_configured_vs_effective.csv']=(list(summary),[summary])
    persist(tmp_path,data)
    checks=audit._audit_mimo_companion_outputs(tmp_path,{'UL':[]})
    assert checks and all(c.passed for c in checks)
    data['reports/csv/run_state.csv'][1][0]['CurrentCanonicalSlot']=1
    persist(tmp_path,data)
    checks=audit._audit_mimo_companion_outputs(tmp_path,{'UL':[]})
    assert any(not c.passed for c in checks)


@pytest.mark.parametrize('target,field,value', [
    ('config','RuntimeTrialCount','1'), ('config','RuntimePopulated','1'),
    ('config','RuntimeRank2Fraction','0'), ('config','Status','pass'),
    ('config','ConfiguredLayers','2'), ('summary','ScenarioObjectivePass','1'),
    ('summary','DominantTransmittedRank','2'), ('summary','DominantEffectiveMCS','0'),
    ('summary','DominantEffectiveModulation','QPSK'), ('summary','ExactMatchRowCount','1'),
    ('summary','RuntimeEvidenceSource','rank_layer_trials_from_air_interface_raw_trials'),
    ('summary','EvidenceClass','DIRECT_RUNTIME_EVIDENCE'),
])
def test_no_attempt_does_not_authorize_invented_execution(target,field,value):
    config, summary=rows()
    (config if target=='config' else summary)[field]=value
    assert any(not c.passed for c in evaluate(config,summary))
