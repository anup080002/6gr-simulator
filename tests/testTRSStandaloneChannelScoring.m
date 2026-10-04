function ok=testTRSStandaloneChannelScoring()
% Same-execution scoring evidence must not influence the practical receiver.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),9);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentServingIdx(:)=1;
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
[out,capture]=sixgr.link.runTRSTracking(dl,'SNR_dB',20,'RuntimeSlot',8);
assert(~out.Crash,'%s',out.FailureReason);
assert(out.NMSEScoringAvailable && isfinite(out.NMSE_dB) && ...
    out.ChannelNMSEComparedComplexValues>0 && ...
    contains(string(out.NMSEReferenceSource),'same_executed_desired_link_waveform'), ...
    'Standalone executed TRS must retain independent channel-scoring evidence.');
assert(capture.DesiredReferenceObservation.isComplete() && ...
    capture.DesiredReferenceObservation.StartSample==capture.Observation.StartSample);
without=rmfield(capture,'DesiredReferenceObservation');
absent=sixgr.link.runTRSTracking(dl,'ReceivedContext',without);
assert(~absent.Crash && ~absent.NMSEScoringAvailable && isnan(absent.NMSE_dB));
reference=capture.DesiredReferenceObservation;
poisoned=sixgr.phy.waveform.WaveformObservationBuffer(reference.StartSample, ...
    reference.EndSampleExclusive,reference.SampleRateHz,reference.NumReceiveAntennas);
poisoned.append(sixgr.phy.waveform.WaveformChunk( ...
    2*reference.readComplete(),reference.StartSample),reference.SampleRateHz);
changed=capture; changed.DesiredReferenceObservation=poisoned;
wrong=sixgr.link.runTRSTracking(dl,'ReceivedContext',changed);
assert(~wrong.Crash && wrong.NMSEScoringAvailable && abs(wrong.NMSE_dB-out.NMSE_dB)>1e-6, ...
    'Independent reference amplitude errors must remain visible; do not fit them away.');
fields={'DetectionMetric','DetectionSuccess','EstimatedTimingOffset_samples', ...
    'EstimatedCFO_Hz','TRSRuntimeEvidenceUsable','HestDimensions'};
for k=1:numel(fields)
    field=fields{k};
    assert(isequaln(out.(field),absent.(field)) && isequaln(out.(field),wrong.(field)), ...
        'Scoring reference must not influence practical receiver field %s.',field);
end
fprintf('TRS_STANDALONE_SCORING_PASS nmse_db=%g values=%d scoring_isolated=1\n', ...
    out.NMSE_dB,out.ChannelNMSEComparedComplexValues);
ok=true;
end
