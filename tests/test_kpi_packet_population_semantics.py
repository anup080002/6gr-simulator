"""Packet KPI identity is directional even when its persisted ledger is shared."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_kpi_no_transmission_semantics import audit, persist, publication, selected_checks


@pytest.mark.parametrize('source,layer', [('PacketSDU','MAC'), ('ApplicationPackets','Application')])
@pytest.mark.parametrize('direction', ['DL','UL'])
def test_packet_kpi_uses_directional_subset_not_full_ledger(tmp_path, source, layer, direction):
    row = publication(tmp_path)
    path = 'packet_flow/csv/'+source+'.csv'
    packets = [dict(Direction=d, PacketId=str(i), PayloadBits=800, DeliverySuccess=1)
               for i,d in enumerate(['UL','DL','UL'])]
    persist(tmp_path, {path: (list(packets[0]), packets)})
    manifest_path = 'reports/csv/kpi_source_table_manifest.csv'
    columns, manifest = audit._read_rows(tmp_path/manifest_path)
    for m in manifest:
        m.update(DLSubsetRowCount=0, ULSubsetRowCount=0,
                 DLSubsetRowsHash='empty', ULSubsetRowsHash='empty')
        if m['Direction'] == source:
            m.update(SourceTablePath=path, Exists=1, RequiredForObjective=1, RowCount=3,
                ColumnCount=len(packets[0]), FileHash='a'*64, Status='pass', FailureReason='',
                DLSubsetRowCount=1, ULSubsetRowCount=2, DLSubsetRowsHash='b'*64, ULSubsetRowsHash='c'*64)
    name = direction+'_'+layer+'_Goodput_Mbps'
    columns, registry = audit._read_rows(tmp_path/'reports/csv/kpi_formula_registry.csv')
    registry[0].update(KPIName=name, Direction=direction, RequiredSourceTables=source)
    count = 1 if direction == 'DL' else 2
    row.update(KPIName=name, FormulaId=name, Direction=direction, NoTransmittedDataProven=0,
        SourceTablePaths=path, SourceRowCount=count, EligibleRowCount=count, ExcludedRowCount=0,
        SourceRowsHash=('b' if direction=='DL' else 'c')*64, Value=.8,
        ReconstructionValue=.8, FormulaExecuted=1, ReconciliationPass=1, StrictOk=1,
        Status='pass', FailureReason='')
    persist(tmp_path, {manifest_path: (list(manifest[0]), manifest),
        'reports/csv/kpi_formula_registry.csv': (columns, registry),
        'reports/csv/kpi_reconstruction_summary.csv': (list(row), [row])})
    checks=selected_checks(tmp_path)
    assert all(c.passed for c in checks), [c.details for c in checks]
    for corrupt in [{'SourceRowsHash':'a'*64}, {'SourceRowsHash':('c' if direction=='DL' else 'b')*64},
                    {'SourceRowCount':3, 'EligibleRowCount':3}]:
        changed=dict(row, **corrupt)
        persist(tmp_path, {'reports/csv/kpi_reconstruction_summary.csv': (list(changed), [changed])})
        assert any('source_count_or_hash_manifest_mismatch' in c.details for c in selected_checks(tmp_path))
