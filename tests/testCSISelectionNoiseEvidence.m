function ok=testCSISelectionNoiseEvidence()
% Declared component receipts test the adapter; no noise/waveform/channel
% execution or production-adapter integration qualification is claimed.
setup6GRSimToolkit('Verbose',false);
for mode=["fixed","thermal"]
    [planes,ofdm,id,nRx]=fixture(mode);
    before=rng; storage=planes.Observation.storageInfo();
    originalPlanes=planes; originalOFDM=ofdm;
    d=sixgr.truth.captureCSISelectionNoiseEvidence(planes,ofdm,id,nRx,id.ReceiverWindowID);
    assert(isequal(before,rng) && isequal(storage,planes.Observation.storageInfo()) && ...
        isequaln(planes,originalPlanes) && isequaln(ofdm,originalOFDM) && isequaln(d.Identity,id));
    expected=planes.Segments{1}.Execution.RX.Replay.InjectedNoiseVariance*ofdm.SampleToGridNoiseVarianceGain;
    assert(isequal(d.Covariance,expected*eye(nRx)) && ...
        d.NoiseStreamSeed==7 && d.NoiseReceipt.ReceiverID==id.ReceiverID && ...
        d.NoiseReceipt.ReceiverWindowID==id.ReceiverWindowID && ...
        d.NoiseReceipt.ReceiverClockEpoch==id.ReceiverClockEpoch && ...
        isequaln(d.NoiseReceipt.NoiseTransform,ofdm.NoiseTransform) && ...
        d.NoiseReceipt.AdditionalNoiseExecutions==0 && ...
        d.NoiseReceipt.AdditionalOFDMCalibrationExecutions==0 && ...
        d.NoiseReceiptSHA256==sixgr.util.sha256Hex(jsonencode(d.NoiseReceipt)));
    assert(d.Source=="executed_pre_rx_rf_noise_with_recorded_ofdm_gain" && ...
        d.SampleNoiseVarianceReferencePlane=="receiver_sample_waveform_pre_composite_front_end" && ...
        contains(d.NoiseVarianceReferencePlane,"raw_grid_coefficient") && ...
        d.NoiseReceipt.ValidatedNoiseRecord.NoiseReferenceEvidenceSource== ...
        "same_execution_receiver_noise_ledger_post_decode_export");
    if mode=="thermal"
        assert(d.WaveformAmplitudeUnit=="sqrt_mW" && d.NoiseVarianceUnit=="mW" && ...
            isnan(d.NoiseReceipt.ValidatedNoiseRecord.SampleToGridNoiseVarianceGain) && ...
            d.SampleToGridNoiseVarianceGain==ofdm.Nfft);
    else
        assert(d.WaveformAmplitudeUnit=="normalized_complex_baseband" && ...
            d.NoiseVarianceUnit=="normalized_complex_baseband_squared");
    end
    % Actual injection closure remains owned by the production binder.
    bad=planes;
    bad.Segments{1}.Execution.RX.Replay.InjectedNoiseVariance=2*d.SampleNoiseVariance;
    expectedFailure='sixgr:truth:SharedFixedSNRNoiseClosure';
    if mode=="thermal", expectedFailure='sixgr:truth:SharedThermalNoiseClosure'; end
    mustFail(@()capture(bad,ofdm,id,nRx),expectedFailure);
    bad=planes;
    bad.Segments{2}.Execution.RX.Replay.NoiseStreamSeed=8;
    mustFail(@()capture(bad,ofdm,id,nRx),'sixgr:truth:NoiseReferenceChangedWithinCapture');
    bad=planes;
    bad.Segments{1}.Execution.RX.Replay=rmfield(bad.Segments{1}.Execution.RX.Replay,'InjectedNoiseVariance');
    mustFail(@()capture(bad,ofdm,id,nRx),'sixgr:truth:IncompleteNoiseReference');
end
% The production completed-item schema stores its ID on the parent, not
% each plane. Both unaliased production and agreeing direct-engine forms
% retain the same receipt; conflicting aliases cannot silently overwrite it.
assert(~isfield(planes,'ID'));
aliased=planes; aliased.ID=id.ReceiverWindowID;
assert(isequaln(capture(aliased,ofdm,id,nRx),capture(planes,ofdm,id,nRx)));
aliased.ID="different_window";
mustFail(@()capture(aliased,ofdm,id,nRx),'sixgr:truth:CSISelectionNoiseObservation');
mustFail(@()sixgr.truth.captureCSISelectionNoiseEvidence(planes,ofdm,id,nRx,"different_window"), ...
    'sixgr:truth:CSISelectionNoiseObservation');
% Endpoint/capture/clock checks never substitute matching configuration.
badID=id; badID.ReceiverID="other_receiver";
mustFail(@()capture(planes,ofdm,badID,nRx),'sixgr:truth:CSISelectionNoiseIdentity');
badID=id; badID.ObservationStartSample=id.ObservationStartSample+1;
mustFail(@()capture(planes,ofdm,badID,nRx),'sixgr:truth:CSISelectionNoiseIdentity');
badID=id; badID.SampleRateHz=2*id.SampleRateHz;
mustFail(@()capture(planes,ofdm,badID,nRx),'sixgr:truth:CSISelectionNoiseIdentity');
badID=id; badID.ReceiverClockDomain="configured_report_clock";
mustFail(@()capture(planes,ofdm,badID,nRx),'sixgr:truth:CSISelectionNoiseIdentity');
badID=id; badID.ReceiverClockEpoch=id.ReceiverClockEpoch+1;
mustFail(@()capture(planes,ofdm,badID,nRx),'sixgr:truth:CSISelectionNoiseExecution');
mustFail(@()capture(planes,ofdm,id,nRx+1),'sixgr:truth:CSISelectionNoiseIdentity');
bad=planes; bad.ReceiverID="other_receiver:post_rf";
mustFail(@()capture(bad,ofdm,id,nRx),'sixgr:truth:CSISelectionNoiseIdentity');
mustFail(@()capture([planes,planes],ofdm,id,nRx),'sixgr:truth:CSISelectionNoiseEndpoint');
bad=planes; bad.Segments{2}.Execution.RX.ID="another_node";
mustFail(@()capture(bad,ofdm,id,nRx),'sixgr:truth:NoiseReferenceReceiverScope');
bad=planes; bad.Segments{2}.Execution.StartSample=51;
mustFail(@()capture(bad,ofdm,id,nRx),'sixgr:truth:NoiseReferenceCoverageGap');
bad=planes; bad.Segments{2}.StartSample=51;
mustFail(@()capture(bad,ofdm,id,nRx),'sixgr:truth:CSISelectionNoiseExecution');
bad=planes; bad.Segments{2}.Execution.SampleRateHz=2*id.SampleRateHz;
mustFail(@()capture(bad,ofdm,id,nRx),'sixgr:truth:CSISelectionNoiseExecution');
bad=planes; bad.Segments{2}.Execution.ApproximationMode="synthetic";
mustFail(@()capture(bad,ofdm,id,nRx),'sixgr:truth:CSISelectionNoiseExecution');
bad=planes;
for k=1:numel(bad.Segments), bad.Segments{k}.Execution.RX.Replay=struct(); end
mustFail(@()capture(bad,ofdm,id,nRx),'sixgr:truth:CSISelectionNoiseMissing');
bad=planes;
bad.Observation=sixgr.phy.waveform.WaveformObservationBuffer(0,100,id.SampleRateHz,nRx);
mustFail(@()capture(bad,ofdm,id,nRx),'sixgr:truth:CSISelectionNoiseObservation');
% Top-level gain must be the recorded native receiver transform's gain.
badOFDM=ofdm; badOFDM.SampleToGridNoiseVarianceGain=2*ofdm.Nfft;
mustFail(@()capture(planes,badOFDM,id,nRx),'sixgr:truth:CSISelectionNoiseTransform');
badOFDM=ofdm; badOFDM.NoiseTransform.NativeSampleRate=2*id.SampleRateHz;
mustFail(@()capture(planes,badOFDM,id,nRx),'sixgr:truth:CSISelectionNoiseTransform');
badOFDM=ofdm; badOFDM.NoiseTransform.CyclicPrefixFraction=.75;
mustFail(@()capture(planes,badOFDM,id,nRx),'sixgr:truth:CSISelectionNoiseTransform');
badOFDM=ofdm; badOFDM.NoiseTransform.CalibrationKey="";
mustFail(@()capture(planes,badOFDM,id,nRx),'sixgr:truth:CSISelectionNoiseTransform');
badOFDM=rmfield(ofdm,'NoiseTransform');
mustFail(@()capture(planes,badOFDM,id,nRx),'sixgr:truth:CSISelectionNoiseMetadata');
% Receiver-estimated and thermal replay placeholder gains have no authority.
poison=planes;
for k=1:numel(poison.Segments)
    poison.Segments{k}.Execution.RX.Replay.SampleNoiseVariance=1e10;
end
assert(isequaln(capture(poison,ofdm,id,nRx),capture(planes,ofdm,id,nRx)));
ok=true;
fprintf('testCSISelectionNoiseEvidence: PASS (declared receipt components; no noise/waveform replay)\n');
end

function d=capture(planes,ofdm,id,nRx)
d=sixgr.truth.captureCSISelectionNoiseEvidence(planes,ofdm,id,nRx,id.ReceiverWindowID);
end

function [planes,ofdm,id,nRx]=fixture(mode)
fs=1920000; nRx=2; nfft=64;
id=struct('ObservationID',"declared_component_capture",'ReceiverID',"ue_1_rx", ...
    'ReceiverWindowID',"declared_window", ...
    'ReceiverClockDomain',"shared_receiver_sample_clock/v1",'ReceiverClockEpoch',3, ...
    'ObservationStartSample',0,'ObservationEndSampleExclusive',100,'SampleRateHz',fs, ...
    'RunFolder',"declared_component_not_production",'RandomSeed',11);
observation=sixgr.phy.waveform.WaveformObservationBuffer(0,100,fs,nRx);
% Deterministic component buffer contents establish completion only; they
% are not generated noise, a PHY waveform, or a simulated decoded outcome.
observation.append(sixgr.phy.waveform.WaveformChunk(complex(zeros(100,nRx)),0),fs);
replay=struct('InjectedNoiseVariance',.01/nfft,'NoiseStreamSeed',7, ...
    'RequestedAWGNReferenceSNR_dB',20,'SignalEnergyPerOccupiedRE',1, ...
    'ReferenceAWGNGridNoiseVariance',.01,'ReferenceAWGNSampleNoiseVariance',.01/nfft, ...
    'SampleToGridNoiseVarianceGain',nfft,'AppliedAWGNSNR_dB',20, ...
    'ThermalSampleNoiseBandwidth_Hz',NaN,'ThermalNoisePSD_mWPerHz',NaN, ...
    'InjectedNoiseVarianceDomain',"receiver_sample_waveform_pre_composite_front_end", ...
    'NoiseOperatingMode',"standalone_awgn_snr_argument", ...
    'NoiseVarianceSource',"declared_component_fixed_noise_ledger", ...
    'AWGNReferenceEnergySource',"declared_component_occupied_RE_reference", ...
    'SharedNoiseCalibrationSource',"declared_component_reference", ...
    'AppliedAWGNSNRSource',"executed_sample_noise_variance_and_occupied_re_energy", ...
    'AppliedAWGNSNRValueRole',"applied_noise_reference_not_measured_receiver_sinr", ...
    'WaveformAmplitudeUnit',"normalized_complex_baseband");
if mode=="thermal"
    replay.NoiseOperatingMode="receiver_noise_figure_thermal_noise";
    replay.WaveformAmplitudeUnit="sqrt_mW";
    replay.ThermalSampleNoiseBandwidth_Hz=fs;
    replay.ThermalNoisePSD_mWPerHz=1e-12;
    replay.InjectedNoiseVariance=fs*1e-12;
    for field=["RequestedAWGNReferenceSNR_dB","SignalEnergyPerOccupiedRE", ...
            "ReferenceAWGNGridNoiseVariance","ReferenceAWGNSampleNoiseVariance", ...
            "SampleToGridNoiseVarianceGain","AppliedAWGNSNR_dB"]
        replay.(field)=NaN;
    end
end
segments=cell(2,1);
for k=1:2
    e=struct('Source',"composed_tx_retained_rf_per_link_channel_sum_receiver_noise_rf", ...
        'ApproximationMode',"none",'ConfigurationEpoch',3,'SampleRateHz',fs, ...
        'StartSample',(k-1)*50,'EndSampleExclusive',k*50, ...
        'RX',struct('ID',id.ReceiverID,'Replay',replay));
    segments{k}=struct('StartSample',e.StartSample,'EndSampleExclusive',e.EndSampleExclusive,'Execution',e);
end
planes=struct('ReceiverID',id.ReceiverID+":post_rf", ...
    'Observation',observation,'Segments',{segments});
transform=struct('Version',"ofdm_noise_transform/v2", ...
    'Source',"deterministic_impulse_and_white_noise_toolbox_ofdm_calibration", ...
    'CalibrationKey',"declared_component_native_fft_key_not_executed_calibration", ...
    'Nfft',nfft,'SampleRate',fs,'NativeSampleRate',fs,'CyclicPrefixFraction',.5, ...
    'SampleToGridNoiseVarianceGain',nfft, ...
    'SampleToGridNoiseVarianceGainSource',"fft_length_transform_gain_verified_by_white_noise", ...
    'SamplePartitionStatus',"exact_native_sample_clock", ...
    'FrequencyDomainSignalPowerReference',"occupied_resource_grid_RE");
ofdm=struct('EngineUsed',"canonical_nrOFDMDemodulate",'Nfft',nfft,'SampleRate',fs, ...
    'CyclicPrefixFraction',.5,'FFTWindowPositionSource',"explicit_cyclic_prefix_fraction", ...
    'SampleToGridNoiseVarianceGain',nfft,'WaveformSHA256',"declared_component_waveform_digest", ...
    'GridSHA256',"declared_component_grid_digest",'NoiseTransform',transform);
end

function mustFail(action,expected)
try, action(); catch cause
    assert(strcmp(cause.identifier,expected),'Expected %s; got %s: %s',expected,cause.identifier,cause.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected %s.',expected);
end
