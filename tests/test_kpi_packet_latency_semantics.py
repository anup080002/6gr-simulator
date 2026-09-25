import sys
from pathlib import Path
import pytest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import lls_csv_semantics as audit

def fixture():
    packets=[dict(Direction='DL',PacketId='p1',DeliverySuccess=1,EnqueueTime_s=0,DeliveryTime_s=t)
             for t in [.009,.005]]
    row=dict(Direction='DL',FirstSuccessDeliveryCount=1,DenominatorValue=1,NumeratorValue=5,Value=5)
    return row,packets

def test_first_packet_delivery_not_tb_latency_or_duplicate_average():
    row,packets=fixture()
    assert not audit._packet_latency_kpi_failures(row,packets)
    for value in [1,7]:
        row['Value']=value
        assert audit._packet_latency_kpi_failures(row,packets)

@pytest.mark.parametrize('field,value',[('EnqueueTime_s','NaN'),('DeliveryTime_s','NaN'),
    ('DeliveryTime_s',-.001),('PacketId',''),('DeliverySuccess','NaN')])
def test_malformed_success_cannot_be_silently_dropped(field,value):
    row,packets=fixture(); packets[0][field]=value
    assert audit._packet_latency_kpi_failures(row,packets)

def test_no_success_is_unavailable_not_zero_latency():
    row,packets=fixture()
    for p in packets: p['DeliverySuccess']=0
    row.update(FirstSuccessDeliveryCount=0,DenominatorValue=0,NumeratorValue=0,Value='NaN')
    assert not audit._packet_latency_kpi_failures(row,packets)
    row['Value']=0
    assert audit._packet_latency_kpi_failures(row,packets)

def test_packet_scope_is_not_shared_across_ues():
    row,packets=fixture(); packets[0]['UEId']=1; packets[1]['UEId']=2
    row.update(FirstSuccessDeliveryCount=2,DenominatorValue=2,NumeratorValue=14,Value=7)
    assert not audit._packet_latency_kpi_failures(row,packets)

def test_unavailable_tb_latency_is_reconciled_against_failed_phy_attempt(tmp_path):
    sys.path.insert(0,str(Path(__file__).resolve().parent))
    from test_kpi_no_transmission_semantics import publication, persist, selected_checks
    row=publication(tmp_path)
    path='air_interface/csv/ul_pusch_trials.csv'
    trials=[dict(Direction='UL',CRCPass=0)]
    persist(tmp_path,{path:(list(trials[0]),trials)})
    manifest_path='reports/csv/kpi_source_table_manifest.csv'
    fields,manifest=audit._read_rows(tmp_path/manifest_path)
    for m in manifest:
        if m['Direction']=='UL': m.update(RowCount=1,FileHash='b'*64)
    name='UL_TB_Delivery_Latency_ms'
    fields_registry,registry=audit._read_rows(tmp_path/'reports/csv/kpi_formula_registry.csv')
    registry[0]['KPIName']=name
    row.update(KPIName=name,FormulaId=name,NoTransmittedDataProven=0,
        SourceRowCount=1,EligibleRowCount=1,SourceRowsHash='b'*64,
        FirstSuccessDeliveryCount=0,DenominatorValue=0,NumeratorValue=0,
        Status='unavailable_no_successful_delivery',FailureReason='no_successful_delivery_in_source_population')
    persist(tmp_path,{manifest_path:(fields,manifest),
        'reports/csv/kpi_formula_registry.csv':(fields_registry,registry),
        'reports/csv/kpi_reconstruction_summary.csv':(list(row),[row])})
    assert all(c.passed for c in selected_checks(tmp_path))
    for flag in [1,'NaN']:
        trials[0]['CRCPass']=flag
        persist(tmp_path,{path:(list(trials[0]),trials)})
        assert any('no_delivery_latency_not_backed_by_source' in c.details for c in selected_checks(tmp_path))
