"""Independent complex-channel accounting fixtures, not waveform evidence."""
import csv
import hashlib
import io
import sys
import tracemalloc
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'apps'))
import lls_contract_materializer as m
import lls_radio_measurement_plots as radio


def trs_fixture(error=.25):
    return dict(Slot='7', UEIndex='1', CellID='1', Direction='DL', SweepPointIndex='1',
        ConfiguredSNR_dB='40', NMSEScoringAvailable='1',
        NMSEReferenceSource='same_executed_desired_link_waveform_post_decode_TRS_pilot_ratio',
        ChannelNMSEReferencePlane='effective_TRS_port_on_recorded_RX_clock',
        ChannelNMSEReferenceUsedByReceiver='0', ChannelNMSEGainOrPhaseFitted='0',
        ChannelNMSEErrorEnergy=str(error), ChannelNMSEReferenceEnergy='1',
        ChannelNMSEComparedComplexValues='4', ChannelNMSEPilotResourceCount='1',
        NMSE_dB=str(10*radio.math.log10(error)) if error else '-Inf',
        ChannelNMSEQualificationMode='independent_complex_pilot_resources_no_gain_or_phase_fit',
        TRSRuntimeEvidenceUsable='1', StrictOk='0')


def trs_chart(rows):
    out=io.StringIO(); writer=csv.DictWriter(out,fieldnames=rows[0])
    writer.writeheader(); writer.writerows(rows)
    payload=out.getvalue().encode()
    return radio._trs_nmse_timeline(m,radio.TRS_NMSE_CHART,
        {radio.TRS_TRIALS:dict(artifact_id=1)},lambda _:payload,1)


def test_trs_timeline_retains_all_eight_sweep_points_and_qualification():
    rows=[dict(trs_fixture(),SweepPointIndex=str(i),ConfiguredSNR_dB=str(snr))
          for i,snr in enumerate([40,30,20,10,0,-10,-20,-30],1)]
    result=trs_chart(rows)
    exported=list(csv.DictReader(io.StringIO(result['csv_bytes'].decode())))
    assert len(exported)==8
    assert {int(r['sweep_point_index']) for r in exported}==set(range(1,9))
    assert all(r['scheduler_usable']=='True' and r['strict_qualification_pass']=='False' for r in exported)
    assert all(float(r['nmse_linear'])==.25 and int(r['compared_complex_values'])==4 for r in exported)
    assert radio.TRS_TRIALS in radio.SOURCE_PATHS
    assert radio.TRS_NMSE_CHART in radio.CHARTS
    out=io.StringIO(); writer=csv.DictWriter(out,fieldnames=rows[0]); writer.writeheader(); writer.writerows(rows)
    dispatched=radio.radio_measurement_chart(radio.TRS_NMSE_CHART,
        {radio.TRS_TRIALS:dict(artifact_id=1)},lambda _:out.getvalue().encode(),1)
    assert dispatched['csv_bytes']==result['csv_bytes']


@pytest.mark.parametrize('field,value',[
    ('NMSE_dB','-50'),('ChannelNMSEComparedComplexValues','0'),
    ('ChannelNMSEPilotResourceCount','0'),('ChannelNMSEErrorEnergy','-1'),
    ('ChannelNMSEReferenceEnergy','0'),('ChannelNMSEReferenceUsedByReceiver','1'),
    ('ChannelNMSEGainOrPhaseFitted','1'),('NMSEReferenceSource','synthetic_reference'),
    ('ChannelNMSEReferencePlane',''),('Slot','NaN'),
])
def test_trs_timeline_rejects_contradictory_scoring(field,value):
    with pytest.raises(ValueError):
        trs_chart([dict(trs_fixture(),**{field:value})])


def test_trs_timeline_does_not_merge_duplicates_or_invent_zero_floor():
    row=trs_fixture()
    with pytest.raises(ValueError,match='Duplicate TRS'):
        trs_chart([row,row])
    result=trs_chart([trs_fixture(0)])
    assert b'Channel NMSE (linear ratio)' in result['img_bytes']
    exported=next(csv.DictReader(io.StringIO(result['csv_bytes'].decode())))
    assert float(exported['nmse_db'])==-radio.math.inf and float(exported['nmse_linear'])==0
    missing=trs_chart([dict(row,NMSEScoringAvailable='0')])
    assert missing['source_row_count']==0


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


def test_nmse_parses_the_same_bytes_it_hashes():
    row, existing, payload = fixture()
    original = payload[1]
    # A different Hest with identical error/reference energies must not be
    # substituted after hash validation. These are labelled numeric fixtures.
    changed = original.replace(b'1.5,0,1,0,0.25', b'0.5,0,1,0,0.25')
    assert changed != original
    calls = []

    def fetch(artifact_id):
        calls.append(artifact_id)
        return original if len(calls) == 1 else changed

    assert radio._scored_data_channel_nmse(m, row, existing, fetch) == float(row['NMSE_dB'])
    assert calls == [1], 'Hashing and parsing must share one immutable read.'


def test_nmse_uses_local_stream_and_closes_it(tmp_path):
    row, existing, payload = fixture()
    path = tmp_path / 'resources.csv'
    path.write_bytes(payload[1])
    opened = []

    def fetch(_):
        raise AssertionError('NMSE must not load the whole local resource CSV into bytes.')

    def opener(_):
        stream = path.open('rb')
        opened.append(stream)
        return stream

    fetch.open_artifact_binary = opener
    assert radio._scored_data_channel_nmse(m, row, existing, fetch) == float(row['NMSE_dB'])
    assert len(opened) == 1 and opened[0].closed

    row['ChannelEstimateResourcesCSVSHA256'] = '0' * 64
    with pytest.raises(ValueError, match='resource hash mismatch'):
        radio._scored_data_channel_nmse(m, row, existing, fetch)
    assert len(opened) == 2 and all(stream.closed for stream in opened)


def test_large_nmse_stream_keeps_exact_population_and_bounded_memory(tmp_path):
    row, existing, payload = fixture()
    sample = next(csv.DictReader(io.StringIO(payload[1].decode())))
    path = tmp_path / 'wideband_channel.csv'
    count = 60_000
    with path.open('w', encoding='utf-8', newline='') as output:
        writer = csv.DictWriter(output, fieldnames=sample)
        writer.writeheader()
        for index in range(count):
            writer.writerow(dict(sample, SubcarrierIndex0=index % 3276,
                SymbolIndex0=(index // 3276) % 14, RxBranchIndex0=index // (3276*14)))
    row['ChannelEstimateComparedValues'] = str(count)
    row['ChannelEstimateResourcesCSVSHA256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    opened = []

    def fetch(_):
        raise AssertionError('The wideband NMSE source must be streamed.')

    def opener(_):
        stream = path.open('rb')
        opened.append(stream)
        return stream

    fetch.open_artifact_binary = opener
    tracemalloc.start()
    try:
        result = radio._scored_data_channel_nmse(m, row, existing, fetch)
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    assert result == float(row['NMSE_dB'])
    assert peak < 8*1024*1024, f'Channel rows retained in Python: peak={peak}'
    assert all(stream.closed for stream in opened)
    print(f'CHANNEL_NMSE_STREAM_MEMORY rows={count} bytes={path.stat().st_size} python_peak_bytes={peak}')

    # Retain count and fresh hash for a late duplicate: it must fail the
    # exact coordinate check, not merely an old digest or population count.
    with path.open('a', encoding='utf-8', newline='') as output:
        csv.DictWriter(output, fieldnames=sample).writerow(dict(sample,
            SubcarrierIndex0=0, SymbolIndex0=0, RxBranchIndex0=0))
    row['ChannelEstimateComparedValues'] = str(count + 1)
    row['ChannelEstimateResourcesCSVSHA256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    with pytest.raises(ValueError, match='repeated channel NMSE resource coordinate'):
        radio._scored_data_channel_nmse(m, row, existing, fetch)
    assert all(stream.closed for stream in opened)


def test_channel_hash_covers_short_reads_bom_and_long_quoted_fields():
    row, existing, payload = fixture()
    sample = next(csv.DictReader(io.StringIO(payload[1].decode())))
    sample['AuditDetail'] = 'x' * 200_000 + '\nquoted,tail'
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=sample)
    writer.writeheader(); writer.writerow(sample)
    data = b'\xef\xbb\xbf' + output.getvalue().encode()
    row['ChannelEstimateResourcesCSVSHA256'] = hashlib.sha256(data).hexdigest()
    opened = []

    class ShortReads(io.BytesIO):
        def read(self, size=-1):
            return super().read(min(127, size) if size >= 0 else 127)

    def fetch(_):
        raise AssertionError('Stream is available.')

    def opener(_):
        stream = ShortReads(data)
        opened.append(stream)
        return stream

    fetch.open_artifact_binary = opener
    previous_limit = csv.field_size_limit()
    assert radio._scored_data_channel_nmse(m, row, existing, fetch) == float(row['NMSE_dB'])
    assert csv.field_size_limit() == previous_limit
    assert all(stream.closed for stream in opened)


@pytest.mark.parametrize('mutation', ['duplicate_header', 'extra_column', 'missing_column', 'invalid_utf8'])
def test_malformed_channel_stream_is_rejected_and_closed(mutation):
    row, existing, payload = fixture()
    data = payload[1]
    header, values = data.splitlines()
    if mutation == 'duplicate_header':
        data = header + b',HReal\n' + values + b',1.5\n'
    elif mutation == 'extra_column':
        data = header + b'\n' + values + b',unowned\n'
    elif mutation == 'missing_column':
        data = header + b'\n' + values.rsplit(b',', 1)[0] + b'\n'
    else:
        data = data.replace(b'executed_channel', b'executed_chan\xffnel')
    row['ChannelEstimateResourcesCSVSHA256'] = hashlib.sha256(data).hexdigest()
    stream = io.BytesIO(data)
    def fetch(_):
        raise AssertionError('Stream is available.')
    fetch.open_artifact_binary = lambda _: stream
    previous_limit = csv.field_size_limit()
    with pytest.raises(ValueError):
        radio._scored_data_channel_nmse(m, row, existing, fetch)
    assert stream.closed and csv.field_size_limit() == previous_limit
