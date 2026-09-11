import csv
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'apps'))
import lls_contract_materializer as m


def render(payload, path='packet_flow/csv/live_pucch_grants.csv'):
    existing={path: {'artifact_id': 1, 'logical_path': path}}
    return m._explicit_runtime_metric_chart_materialization(
        'UE control/report timeline', existing, lambda _: payload, 1)


def test_coverage_values_cannot_become_runtime_timeline():
    assert render(b'Availability,ValueNumeric\nconfig_only,0\nnot_available,1\n',
                  'reports/csv/live_ue_control_state.csv') is None


def test_unobserved_or_proxy_control_cannot_become_measured_points():
    assert render(b'Slot,RuntimeStateUpdated,ControlObservationAvailable,FallbackFlag\n'
                  b'2,1,0,0\n5,1,1,1\n') is None


def test_received_feedback_keeps_actual_slot_and_both_state_outcomes():
    result=render(b'Slot,RuntimeStateUpdated,ControlObservationAvailable\n'
                  b'7,0,1\n12,1,1\n20,1,0\n')
    rows=list(csv.DictReader(io.StringIO(result['csv_bytes'].decode())))
    assert [(float(r['x_value']), float(r['y_value'])) for r in rows]==[(7.,0.),(12.,1.)]
    assert result['source_row_count']==2
    assert all(r['y_label']=='Received UE feedback applied (0/1)' for r in rows)


def test_missing_slot_is_not_replaced_by_row_number():
    assert render(b'RuntimeStateUpdated,ControlObservationAvailable\n1,1\n') is None
