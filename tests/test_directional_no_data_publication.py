"""Publication fixtures: absence is not decoding success or zero-valued SINR."""
import csv
import io
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'apps'))
import lls_contract_materializer as materializer


def fixture(direction='UL'):
    identity = dict(ScenarioID='fixture', ConfigHash='fixture_hash')
    state = dict(**identity, ConfiguredSNR_dB=-10, CanonicalSlotsPerSweepPoint=2,
                 CurrentCanonicalSlot=2, SlotTraceRows=2, **{direction+'GrantRows':0})
    rows = [dict(**identity, CanonicalSlot=slot, SweepPointIndex=1, ConfiguredSNR_dB=-10,
        **{direction+suffix:0 for suffix in ['GrantCount','ExecutedGrantCount','TrialRows','TBSBits','SuccessCount']},
        **{direction+'Scheduled':slot-1, direction+'Status':'idle_no_grant' if slot==2 else ''}) for slot in [1,2]]
    channel = 'pusch' if direction == 'UL' else 'pdsch'
    return {
        'reports/csv/scenario_summary.csv': (['ScenarioID','ConfigHash','RunCompletion'],
            [dict(**identity, RunCompletion='completed_with_failures')]),
        'reports/csv/run_state.csv': (list(state), [state]),
        'reports/csv/slot_trace.csv': (list(rows[0]), rows),
        f'air_interface/csv/{direction.lower()}_{channel}_trials.csv': (['Slot','CRCPass'], []),
        f'packet_flow/csv/live_{direction.lower()}_scheduler_grants.csv': (['GrantContextId','TBSBits','Direction'], []),
    }


def artifacts(tables):
    entries, payloads = [], {}
    for index, (path, (fields, rows)) in enumerate(tables.items()):
        out=io.StringIO(); writer=csv.DictWriter(out,fieldnames=fields)
        writer.writeheader(); writer.writerows(rows)
        entries.append(dict(artifact_id=index,logical_path=path))
        payloads[index]=out.getvalue().encode()
    return entries, payloads.__getitem__


@pytest.mark.parametrize('direction',['DL','UL'])
def test_completed_direction_without_attempts(direction):
    entries, fetch=artifacts(fixture(direction))
    sources=materializer._no_data_chart_sources(entries,fetch,direction=direction)
    assert len(sources)==5
    # It is not a global acquisition outage: peer-direction charts stay active.
    assert materializer._no_data_chart_sources(entries,fetch)==[]


@pytest.mark.parametrize('field,value', [('ULGrantCount',1), ('ULExecutedGrantCount',1),
    ('ULTrialRows',1), ('ULTBSBits',8), ('ULSuccessCount',1), ('ULStatus','started'),
    ('ULScheduled','NaN'), ('ConfigHash','other'), ('SweepPointIndex',2),
    ('CanonicalSlot',1), ('ConfiguredSNR_dB',20)])
def test_contradictory_slot_trace_is_not_absence(field,value):
    tables=fixture(); tables['reports/csv/slot_trace.csv'][1][1][field]=value
    entries,fetch=artifacts(tables)
    assert not materializer._no_data_chart_sources(entries,fetch,direction='UL')


@pytest.mark.parametrize('path',list(fixture()))
def test_missing_authority_is_not_absence(path):
    tables=fixture(); del tables[path]
    entries,fetch=artifacts(tables)
    assert not materializer._no_data_chart_sources(entries,fetch,direction='UL')


@pytest.mark.parametrize('field,value',[('CurrentCanonicalSlot',1),('ULGrantRows',1),('SlotTraceRows',3)])
def test_incomplete_clock_is_not_absence(field,value):
    tables=fixture(); tables['reports/csv/run_state.csv'][1][0][field]=value
    entries,fetch=artifacts(tables)
    assert not materializer._no_data_chart_sources(entries,fetch,direction='UL')


@pytest.mark.parametrize('path,row',[
    ('air_interface/csv/ul_pusch_trials.csv',dict(Slot=2,CRCPass=0)),
    ('packet_flow/csv/live_ul_scheduler_grants.csv',dict(GrantContextId='actual',TBSBits=8,Direction='UL')),
    ('air_interface/csv/ul_constellation_samples.csv',dict(I=1,Q=0)),
])
def test_actual_or_stray_data_is_not_hidden(path,row):
    tables=fixture(); tables[path]=(list(row),[row])
    entries,fetch=artifacts(tables)
    assert not materializer._no_data_chart_sources(entries,fetch,direction='UL')


def test_coverage_is_unavailable_not_success_or_policy_disabled(monkeypatch):
    entries,fetch=artifacts(fixture())
    specs=[dict(chart_name=name,section_slug='fixture') for name in ['ul_bler_vs_snr','dl_bler_vs_snr']]
    monkeypatch.setattr(materializer,'_table_specs',lambda:[])
    monkeypatch.setattr(materializer,'_chart_specs',lambda:specs)
    coverage=materializer.coverage_summary(entries,fetch_artifact_bytes=fetch)
    assert coverage['charts_available']==0 and coverage['charts_policy_disabled']==0
    assert coverage['unavailable_chart_names']==['ul_bler_vs_snr']
    assert coverage['missing_chart_names']==['dl_bler_vs_snr']
    # A stale/synthetic curve is contradictory and must not become a success.
    for path in [materializer.chart_contract_csv_path(specs[0]), materializer.chart_contract_image_path(specs[0])]:
        entries.append(dict(artifact_id=99,logical_path=path))
    coverage=materializer.coverage_summary(entries,fetch_artifact_bytes=fetch)
    assert coverage['charts_available']==0 and 'ul_bler_vs_snr' in coverage['missing_chart_names']
