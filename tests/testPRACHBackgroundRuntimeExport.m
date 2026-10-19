function ok=testPRACHBackgroundRuntimeExport()
% Execute only one bounded Msg1 receiver completion, not a scenario/campaign.
setup6GRSimToolkit('Verbose',false); old=rng; cleanup=onCleanup(@()rng(old)); rng(719012);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
for policy=["strongest","awgn_sic_unrestricted"]
cfg.random_access.preamble_detection_policy=char(policy);
cfg.random_access.multi_preamble_max_delay_us=2;
[prepared,cp]=sixgr.phy.ra.runFourStepRA(cfg,'WriteArtifacts',false, ...
    'RuntimeIntegrationMode','provided_observation_unit_channel_test', ...
    'RequireRuntimeStageWaveforms',true,'UseRuntimeChannel',false, ...
    'AllowRuntimeStageWaveformComposition',false,'StageAction','prepare_next_stage');
assert(cp.RAConfig.ResolvedPRACHFormat=="B4");
w=cp.Msg1Tx.Waveform;
variance=mean(abs(w).^2,'all')/100;
w=w+sqrt(variance/2)*(randn(size(w))+1i*randn(size(w)));
p=prepared.PreparedTransmission; first=round(p.StartTime_s*p.SampleRate_Hz);
b=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(w,1),p.SampleRate_Hz,size(w,2));
b.append(sixgr.phy.waveform.WaveformChunk(w,first),p.SampleRate_Hz);
[received,~]=sixgr.phy.ra.runFourStepRA(cfg,'Continuation',cp, ...
    'RuntimeStageWaveforms',struct('Msg1RxWaveform',b),'StopAfterStage','Msg1');
assert(received.PreambleDetected && isfinite(received.Msg1PDPAverageNoiseFloor));
assert(received.Msg1PDPAverageNoiseFloor>0 && received.Msg1NoiseFloorPairCount>0);
assert(received.Msg1NoiseFloorStatus=="measured_noise_plus_inter_repetition_variation");
t=received.ArtifactTables.msg1_prach_detection;
assert(t.PDPAverageNoiseFloor==received.Msg1PDPAverageNoiseFloor);
assert(t.NoiseFloorEstimator=="disjoint_received_repetition_differences");
assert(t.NoiseFloorDefinition==received.Msg1NoiseFloorDefinition);
assert(t.NoiseFloorStatus==received.Msg1NoiseFloorStatus);
assert(t.NoiseFloorPairCount==received.Msg1NoiseFloorPairCount);
assert(received.Msg1DetectionTrace.NoiseFloor==t.PDPAverageNoiseFloor);
if policy=="strongest"
    trace=received.Msg1DetectionTrace;
    assert(isnan(trace.Threshold) && trace.DecisionThreshold==t.DetectionThreshold);
    [~,sequenceInfo]=nrPRACH(cp.Msg1Tx.Carrier,cp.Msg1Tx.PRACH);
    row=struct('DetectionSuccess',true,'FalseAlarm',NaN,'MissedDetection',false, ...
        'PRACHRootSequenceIndex',cp.Msg1Tx.PRACH.SequenceIndex, ...
        'PRACHRestrictedSetType',string(cp.Msg1Tx.PRACH.RestrictedSet), ...
        'PRACHNCS',sequenceInfo.NumCyclicShifts, ...
        'PRACHZeroCorrelationZone',cp.Msg1Tx.PRACH.ZeroCorrelationZone, ...
        'PreambleIndex',received.PreambleIndexTx,'Slot',cp.RAConfig.PRACHAbsoluteSlot+1);
    plotted=sixgr.truth.buildFourStepRACorrelationTraceTable(received,row,cfg,20,1);
    mirrored=sixgr.truth.buildPRACHCorrelationTraceTable(plotted);
    assert(height(plotted)==trace.NoiseFloorEvidence.NFFT && height(mirrored)==height(plotted));
    for name=string(plotted.Properties.VariableNames)
        assert(isequaln(plotted.(name),mirrored.(name)), ...
            'test:PRACHTraceRoundtrip','Measured trace field %s changed in the primary mirror.',name);
    end
    assert(all(plotted.noise_floor==trace.NoiseFloor) && all(isnan(plotted.threshold)) && ...
        all(plotted.decision_peak_metric==t.DetectionMetric));
    assert(all(plotted.noise_floor_normalization==trace.NoiseFloorEvidence.Normalization));
end
assert(isnan(t.FalseAlarm),'Signal-present detection is not a false-alarm trial.');
end
ok=true; disp('PRACH_BACKGROUND_RUNTIME_EXPORT_PASS: actual B4 received waveform through Msg1 completion and primary evidence table.');
end
