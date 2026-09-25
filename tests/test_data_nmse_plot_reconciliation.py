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
