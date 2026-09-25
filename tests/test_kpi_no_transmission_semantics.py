"""A completed zero-attempt window is not a successful decoder measurement."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_zero_attempt_semantic_authority import audit, persist, tables


def fixture(root):
    data = tables()
    columns, rows = data['reports/csv/scenario_summary.csv']
    columns.append('SlotDuration_ms'); rows[0]['SlotDuration_ms'] = 1
    persist(root, data)
    context = audit._no_transmission_kpi_context(root, 'UL')
    row = dict(Direction='UL', NoTransmittedDataProven=1,
        NoTransmissionEvidencePaths='|'.join(sorted(context['sources'])),
        NoTransmissionEvidenceHash='a'*64, WarmupDurationSec=0,
        MeasurementWindowSec=.002, MissingRawData=0, SchemaValid=1)
    return data, context, row


def test_completed_window_proof_and_matching_trace_alias(tmp_path):
    data, context, row = fixture(tmp_path)
    assert not audit._no_transmission_kpi_failures(tmp_path, row, context)
    alias = 'packet_flow/csv/slot_trace.csv'
    persist(tmp_path, {alias: data['reports/csv/slot_trace.csv']})
    row['NoTransmissionEvidencePaths'] = row['NoTransmissionEvidencePaths'].replace(
        'reports/csv/slot_trace.csv', alias)
    assert not audit._no_transmission_kpi_failures(tmp_path, row, context)
    data['reports/csv/slot_trace.csv'][1][0]['ULTBSBits'] = 8
    persist(tmp_path, {alias: data['reports/csv/slot_trace.csv']})
    assert 'no_transmission_slot_trace_alias_disagrees' in audit._no_transmission_kpi_failures(tmp_path, row, context)


@pytest.mark.parametrize('field,value', [
    ('NoTransmissionEvidencePaths', 'air_interface/csv/ul_pusch_trials.csv'),
    ('NoTransmissionEvidenceHash', 'empty'), ('WarmupDurationSec', -.1),
    ('WarmupDurationSec', .002), ('MeasurementWindowSec', 58),
    ('MissingRawData', 1), ('SchemaValid', 0)])
def test_malformed_proof_is_not_publication_permission(tmp_path, field, value):
    _, context, row = fixture(tmp_path)
    row[field] = value
    assert audit._no_transmission_kpi_failures(tmp_path, row, context)


def publication(root):
    data, context, row = fixture(root)
    path = 'air_interface/csv/ul_pusch_trials.csv'
    manifest = []
    for direction in ['UL','DL','PacketSDU','ApplicationPackets','HARQTimeline','ULGrants','DLGrants','SlotTrace']:
        present = direction == 'UL'
        manifest.append(dict(RunId='fixture', ScenarioName='fixture', Direction=direction,
            SourceTablePath=path if present else f'absent/{direction}.csv',
            SourceTableName=direction, Layer='PHY', RequiredForObjective=int(present),
            Exists=int(present), RowCount=0, ColumnCount=2 if present else 0,
            FileHash='empty', SchemaHash='fixture', ProducerModule='fixture',
            Status='pass' if present else 'not_applicable', FailureReason='' if present else 'disabled'))
    registry = [dict(KPIName='UL_BLER', Direction='UL', Layer='PHY', Units='ratio',
        RequiredSourceTables='ul_pusch_trials', Tolerance=1e-9, StrictAllowed=1,
        FormulaVersion='v1', FormulaEquation='failed/attempts', ProducerModule='fixture', Status='active')]
    row.update(KPIName='UL_BLER', FormulaId='UL_BLER', FormulaVersion='v1', Value='NaN',
        SourceTablePaths=path, SourceRowCount=0, EligibleRowCount=0, ExcludedRowCount=0,
        SourceRowsHash='empty', Applicable=1, ApplicabilityReason='enabled', FormulaExecuted=0,
        ReconstructionValue='NaN', ReconciliationTolerance=1e-9, ReconciliationPass=0,
        StrictOk=0, Status='unavailable_no_transmissions', FailureReason='completed_window_no_transmitted_data')
    for name, rows in [('kpi_formula_registry', registry), ('kpi_source_table_manifest', manifest),
                       ('kpi_reconstruction_summary', [row])]:
        persist(root, {f'reports/csv/{name}.csv': (list(rows[0]), rows)})
    return row


def selected_checks(root):
    return [check for check in audit._audit_kpi_reporting_tables(root)
        if check.artifact_path in {'reports/csv/kpi_source_table_manifest.csv',
                                  'reports/csv/kpi_reconstruction_summary.csv'}]


def test_header_only_source_and_unavailable_metric_are_honestly_exported(tmp_path):
    publication(tmp_path)
    checks = selected_checks(tmp_path)
    assert checks and all(c.passed for c in checks), [c.details for c in checks]


@pytest.mark.parametrize('field,value', [('Value', 0), ('ReconstructionValue', 0),
    ('StrictOk', 1), ('FormulaExecuted', 1), ('ReconciliationPass', 1), ('Status', 'pass'),
    ('SourceRowsHash', 'a'*64), ('NoTransmittedDataProven', 0)])
def test_forged_decoder_success_or_source_identity_rejected(tmp_path, field, value):
    row = publication(tmp_path); row[field] = value
    persist(tmp_path, {'reports/csv/kpi_reconstruction_summary.csv': (list(row), [row])})
    assert any(not c.passed for c in selected_checks(tmp_path))


def test_missing_physical_source_cannot_claim_unavailable_measurement(tmp_path):
    publication(tmp_path)
    (tmp_path/'packet_flow/csv/live_ul_scheduler_grants.csv').unlink()
    assert any(not c.passed for c in selected_checks(tmp_path))


@pytest.mark.parametrize('mutation', ['', 'zero_rate', 'fake_pass', 'positive_duration', 'missing_proof'])
def test_zero_exposure_unit_audit_does_not_compute_zero_over_zero(tmp_path, mutation):
    row = publication(tmp_path)
    name = 'UL_PHY_ScheduledThroughput_Mbps'
    row.update(KPIName=name, FormulaId=name)
    registry_path = tmp_path/'reports/csv/kpi_formula_registry.csv'
    columns, registry = audit._read_rows(registry_path)
    registry[0]['KPIName'] = name
    unit = dict(KPIName=name, Applicable=1, Bits=0, DurationSec=0,
        ComputedMbps='NaN', ExpectedMbps='NaN', Delta='NaN', Pass=0,
        Status='unavailable_no_transmissions', FailureReason='no_scheduled_resource_exposure')
    if mutation == 'zero_rate': unit['ComputedMbps'] = 0
    elif mutation == 'fake_pass': unit['Pass'] = 1
    elif mutation == 'positive_duration': unit['DurationSec'] = .002
    elif mutation == 'missing_proof': row['NoTransmittedDataProven'] = 0
    persist(tmp_path, {'reports/csv/kpi_formula_registry.csv': (columns, registry),
        'reports/csv/kpi_reconstruction_summary.csv': (list(row), [row]),
        'reports/csv/kpi_unit_conversion_audit.csv': (list(unit), [unit])})
    checks = [c for c in audit._audit_kpi_reporting_tables(tmp_path)
        if c.artifact_path == 'reports/csv/kpi_unit_conversion_audit.csv']
    assert checks
    assert all(c.passed for c in checks) == (not mutation), [c.details for c in checks]
