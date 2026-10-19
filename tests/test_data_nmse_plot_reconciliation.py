"""Independent complex-channel accounting fixtures, not waveform evidence."""
import csv
import hashlib
import io
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'apps'))
import lls_contract_materializer as m
import lls_radio_measurement_plots as radio


def fixture(error=0.5):
    sample=dict(ChannelObservationID='obs', ChannelReferenceSource='executed_channel',
        ChannelReferencePlane='nominal_linear_effective_layer_channel',
        ReferenceUsedByReceiver='0', GainOrPhaseFitted='0', SubcarrierIndex0='0',
        SymbolIndex0='2', RxBranchIndex0='0', ReferencePortIndex0='0',
        HReal=str(1+error), HImag='0', ReferenceHReal='1', ReferenceHImag='0',
        ChannelErrorEnergy=str(error**2), ReferenceChannelEnergy='1')
    out=io.StringIO()
    writer=csv.DictWriter(out,fieldnames=sample)
    writer.writeheader(); writer.writerow(sample)
    payload=out.getvalue().encode()
    path='channel_estimation/csv/pdsch_actual.csv'
    row=dict(ChannelObservationID='obs', NMSESource='executed_channel',
        ChannelEstimateReferencePlane=sample['ChannelReferencePlane'],
        ChannelEstimateReferenceUsedByReceiver='0', ChannelEstimateComparedValues='1',
        NMSE_dB=str(20*radio.math.log10(error)) if error else '-Inf',
        ChannelEstimateResourcesCSV=path, ChannelEstimateResourcesCSVSHA256=hashlib.sha256(payload).hexdigest())
    return row,{path:dict(artifact_id=1)},{1:payload}


@pytest.mark.parametrize('error', [0, .5, 1, 2])
def test_nmse_matches_hashed_complex_reference(error):
    row,existing,payload=fixture(error)
    assert radio._scored_data_channel_nmse(m,row,existing,payload.__getitem__)==float(row['NMSE_dB'])


def test_isolated_score_has_its_own_identity_not_a_shared_channel_archive():
    row,existing,payload=fixture()
    row['ChannelEstimateObservationID']='isolated_hest_measured'
    del row['ChannelObservationID']
    rows=list(csv.DictReader(io.StringIO(payload[1].decode())))
    rows[0]['ChannelEstimateObservationID']=row['ChannelEstimateObservationID']
    del rows[0]['ChannelObservationID']
    out=io.StringIO(); writer=csv.DictWriter(out,fieldnames=rows[0])
    writer.writeheader(); writer.writerows(rows)
    payload[1]=out.getvalue().encode()
    row['ChannelEstimateResourcesCSVSHA256']=hashlib.sha256(payload[1]).hexdigest()
    assert radio._scored_data_channel_nmse(m,row,existing,payload.__getitem__)==float(row['NMSE_dB'])
    row['ChannelEstimateObservationID']='different_capture'
    with pytest.raises(ValueError,match='reference identity mismatch'):
        radio._scored_data_channel_nmse(m,row,existing,payload.__getitem__)


@pytest.mark.parametrize('field,value', [
    ('NMSE_dB','12'), ('ChannelEstimateComparedValues','2'),
    ('ChannelEstimateResourcesCSVSHA256','stale'), ('ChannelObservationID','other'),
    ('ChannelEstimateReferenceUsedByReceiver','1'), ('NMSESource','other'),
    ('ChannelEstimateReferencePlane','other'),
])
def test_contradictory_scoring_does_not_become_a_plot(field,value):
    row,existing,payload=fixture()
    row[field]=value
    with pytest.raises(ValueError):
        radio._scored_data_channel_nmse(m,row,existing,payload.__getitem__)


def test_exact_zero_error_has_a_linear_plot_without_a_db_floor():
    row,existing,payload=fixture(0)
    row.update(Slot='1',UEIndex='1',PostEqSINR_dB='20',PostEqSINRSource='receiver',
        PostEqSINRValueStatus='OK',PostEqSINRValueRole='estimated',
        PostEqSINRMeasurementDomain='post_equalization')
    out=io.StringIO(); writer=csv.DictWriter(out,fieldnames=row)
    writer.writeheader(); writer.writerow(row)
    existing[radio.TRIALS[0]]=dict(artifact_id=2); payload[2]=out.getvalue().encode()
    chart=radio._relationships(m,'NMSE vs SNR / SINR',existing,payload.__getitem__,1)
    rows=list(csv.DictReader(io.StringIO(chart['csv_bytes'].decode())))
    assert float(rows[0]['metric_value']) == -radio.math.inf
    assert float(rows[0]['plotted_nmse_linear']) == 0
    assert b'Channel NMSE (linear ratio)' in chart['img_bytes']
    assert b'visual_gate=' not in chart['img_bytes']


def test_csirs_joint_points_reconcile_all_resources_not_pilot_residual():
    existing, payload = {}, {}
    trials = []
    for point, snr in enumerate([40, 30, 20, 10, 0, -10, -20, -30], 1):
        row, _, data = fixture(.5)
        sample = next(csv.DictReader(io.StringIO(data[1].decode())))
        identity = f'csi_observation_{point}'
        sample['CSIChannelEstimateObservationID'] = identity
        del sample['ChannelObservationID']
        # Identical RE/port coordinates on different resource identities
        # are distinct evidence, not duplicate rows to discard.
        resources = [dict(sample, ResourceID=resource) for resource in [1, 2]]
        out = io.StringIO(); writer = csv.DictWriter(out, fieldnames=resources[0])
        writer.writeheader(); writer.writerows(resources)
        path = f'channel_estimation/csv/csirs_{point}.csv'
        payload[point] = out.getvalue().encode()
        existing[path] = dict(artifact_id=point)
        row.update(SignalFamily='CSI-RS', Direction='DL', Slot='6', UEIndex='1',
            SweepPointIndex=str(point), ConfiguredSNR_dB=str(snr),
            CSIChannelEstimateObservationID=identity,
            ChannelNMSESource=row.pop('NMSESource'),
            ChannelNMSEReferencePlane=row.pop('ChannelEstimateReferencePlane'),
            ChannelNMSEReferenceUsedByReceiver='0', ChannelNMSEComparedComplexValues='2',
            NMSEScoringAvailable='1', PilotResidualNMSE_dB='-99',
            ChannelEstimateResourcesCSV=path,
            ChannelEstimateResourcesCSVSHA256=hashlib.sha256(payload[point]).hexdigest(),
            MeasuredTrialSINR_dB=str(snr-2), MeasuredTrialSINRSource='actual_reference_REs',
            MeasuredTrialSINRValueStatus='OK', MeasuredTrialSINRValueRole='received_reference_RE_power_ratio_estimate',
            MeasuredTrialSINRMeasurementDomain='csi_rs_port3000_reference_re_received_plane')
        trials.append(row)
    out=io.StringIO(); writer=csv.DictWriter(out,fieldnames=trials[0]); writer.writeheader(); writer.writerows(trials)
    payload[99]=out.getvalue().encode(); existing[radio.CSI_TRIALS]=dict(artifact_id=99)
    result=radio._relationships(m,'NMSE vs SNR / SINR',existing,payload.__getitem__,1)
    rows=list(csv.DictReader(io.StringIO(result['csv_bytes'].decode())))
    assert len(rows)==8 and {int(r['sweep_point_index']) for r in rows}==set(range(1,9))
    assert all(abs(float(r['metric_value'])-20*radio.math.log10(.5))<1e-10 for r in rows)
    assert all(r['signal_family']=='CSI-RS' and r['metric_reference_plane']=='nominal_linear_effective_layer_channel' for r in rows)
    assert b'CSI-RS' in result['img_bytes'] and b'-99' not in result['img_bytes']
    trials[0]['NMSE_dB']='-99'
    with pytest.raises(ValueError,match='independent pilot energies'):
        radio._scored_data_channel_nmse(m,trials[0],existing,payload.__getitem__)
