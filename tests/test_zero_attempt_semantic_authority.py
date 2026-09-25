"""No-data accounting must not certify a waveform or fabricate metric rows."""
import csv
import sys
from pathlib import Path

import pytest

sys.path[0:0]=[str(Path(__file__).resolve().parents[1]/'tools'),
              str(Path(__file__).resolve().parents[1]/'tests')]
import lls_csv_semantics as audit
from test_directional_no_data_publication import fixture


def persist(root,tables):
    for path,(columns,rows) in tables.items():
        target=root/path; target.parent.mkdir(parents=True,exist_ok=True)
        with target.open('w',newline='',encoding='utf-8') as stream:
            writer=csv.DictWriter(stream,fieldnames=columns)
            writer.writeheader(); writer.writerows(rows)


def tables():
    result=fixture('UL')
    summary=result['reports/csv/scenario_summary.csv']
    summary[0].append('EffectiveULTrialCount')
    summary[1][0]['EffectiveULTrialCount']=0
    return result


def test_schema_alone_does_not_prove_zero_attempts():
    checks=audit._audit_link_table('ul.csv',list(audit.LINK_REQUIRED_COLUMNS),[],'UL',0)
    assert not next(c for c in checks if c.check_id=='expected_trial_count').passed
    assert not next(c for c in checks if c.check_id=='zero_attempt_runtime_authority').passed


def test_completed_zero_attempts_are_not_a_missing_waveform(tmp_path):
    persist(tmp_path,tables())
    proof=audit._verified_zero_attempt_sources(tmp_path,'UL')
    assert len(proof)==5
    checks=audit._audit_link_table('ul.csv',list(audit.LINK_REQUIRED_COLUMNS),[],'UL',0,proof)
    assert all(c.passed for c in checks)
    assert all(c.row_count==0 for c in checks)
    # Header/schema validation must remain strict even with valid absence.
    bad=audit._audit_link_table('ul.csv',['Slot','CRCPass'],[],'UL',0,proof)
    assert not next(c for c in bad if c.check_id=='required_columns').passed
    bad=audit._audit_link_table('ul.csv',list(audit.LINK_REQUIRED_COLUMNS),[],'UL',1,proof)
    assert not next(c for c in bad if c.check_id=='expected_trial_count').passed


def test_late_publication_failure_does_not_erase_completed_zero_attempts(tmp_path):
    t=tables()
    t['reports/csv/scenario_summary.csv'][1][0]['RunCompletion']='failed'
    persist(tmp_path,t)
    assert len(audit._verified_zero_attempt_sources(tmp_path,'UL'))==5
    # A physical failure before completing the clock cannot use this route.
    t['reports/csv/run_state.csv'][1][0]['CurrentCanonicalSlot']=1
    persist(tmp_path,t)
    assert not audit._verified_zero_attempt_sources(tmp_path,'UL')


@pytest.mark.parametrize('metric', ['bler', 'throughput'])
def test_empty_derived_curve_requires_runtime_absence_proof(tmp_path, metric):
    persist(tmp_path,tables())
    proof=audit._verified_zero_attempt_sources(tmp_path,'UL')
    columns=['Direction','PostEqSINR_dB_BinCenter','PostEqSINR_dB_BinMin',
             'PostEqSINR_dB_BinMax','TrialCount','SourceArtifact']
    columns += (['BLER','BLER_CI_Low','BLER_CI_High','BER','FailureCount']
                if metric=='bler' else ['Throughput_Mbps_mean','Goodput_Mbps_mean',
                                       'OfferedThroughput_Mbps_mean'])
    path=f'air_interface/csv/ul_measured_sinr_{metric}_curve.csv'
    checks=audit._audit_derived_link_table(path,columns,[],{'UL':[]},proof)
    assert all(c.passed for c in checks if c.required)
    absent=next(c for c in checks if c.check_id=='not_evaluated_no_data_attempts')
    assert not absent.evaluated and not absent.passed and absent.row_count==0
    for source,authority in [({'UL':[]},()), ({'UL':[{'Slot':1}]},proof)]:
        bad=audit._audit_derived_link_table(path,columns,[],source,authority)
        assert any(c.required and not c.passed for c in bad)
    bad=audit._audit_derived_link_table(path,['Direction'],[],{'UL':[]},proof)
    assert any(c.required and not c.passed for c in bad)


@pytest.mark.parametrize('mutation',['summary_missing_count','summary_positive_count',
    'unfinished','missing_grants','executed_grant','stray_sample'])
def test_incomplete_or_contradictory_run_cannot_claim_no_attempts(tmp_path,mutation):
    t=tables(); s=t['reports/csv/scenario_summary.csv'][1][0]
    if mutation=='summary_missing_count': s.pop('EffectiveULTrialCount')
    elif mutation=='summary_positive_count': s['EffectiveULTrialCount']=1
    elif mutation=='unfinished': s['RunCompletion']='running'
    elif mutation=='missing_grants': del t['packet_flow/csv/live_ul_scheduler_grants.csv']
    elif mutation=='executed_grant': t['reports/csv/slot_trace.csv'][1][1]['ULExecutedGrantCount']=1
    else: t['air_interface/csv/ul_constellation_samples.csv']=(['I','Q'],[dict(I=1,Q=0)])
    persist(tmp_path,t)
    assert not audit._verified_zero_attempt_sources(tmp_path,'UL')
