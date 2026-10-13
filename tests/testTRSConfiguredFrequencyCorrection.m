function ok=testTRSConfiguredFrequencyCorrection()
% Bounded receiver unit test: real 273-PRB TRS IQ, analytic impairment only.
% This does not qualify the physical array, fading channel or full scenario.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
p=sixgr.link.prepareTRSTransmission(cfg,40,'RuntimeSlot',7);
assert(p.Tx.GridSlots(1).Carrier.NSizeGrid==273);
origin=7*61440; p.TransmitStartSample=origin;
% Explicitly declared unit-test channel with four independent RX branches.
wave=p.Tx.Waveform*[1 -1 0.5i -0.5i];
delay=16;
reference=sixgr.util.applyFractionalSampleDelay(wave,delay);
ref=localObservation(reference,origin,p.SampleRateHz);
for hz=[-400 0 400]
    n=origin+(0:size(wave,1)-1).';
    observed=sixgr.util.applyFractionalSampleDelay( ...
        wave.*exp(1i*2*pi*hz*n/p.SampleRateHz),delay);
    replay=struct('InjectedNoiseVariance',0,'InjectedTimingOffset_samples',delay, ...
        'InjectedCFO_Hz',hz,'CFOApplied',hz~=0,'ChannelFadingApplied',false,'ScalarDopplerInjected',false);
    capture=struct('Prepared',p,'Observation',localObservation(observed,origin,p.SampleRateHz), ...
        'Replay',replay,'ChannelState',struct(),'DesiredReferenceObservation',ref, ...
        'RecordedReceiverTimingOffset_samples',delay);
    out=sixgr.link.runTRSTracking(p.ReceiverConfig,'ReceivedContext',capture);
    assert(~out.Crash && out.Ok && out.CFOCorrectionApplied && ...
        abs(out.EstimatedCommonFrequency_Hz-hz)<1e-6 && ...
        out.CFOCorrectionApplied_Hz==out.EstimatedCommonFrequency_Hz && ...
        out.CFOCorrectionSampleOrigin==origin && out.EstimatedTimingOffset_samples==delay && ...
        out.NMSE_dB<-50,'Configured CP correction must run before TRS channel estimation: %s',out.FailureReason);
    assert(contains(out.CFOEstimateSource,'cyclic_prefix') && isnan(out.EstimatedOscillatorCFO_Hz));
    raw=capture.Observation.readComplete();
    assert(isequal(raw,observed),'Reception must not mutate the original received IQ.');
    % Truth metadata and scoring have no authority over receiver decisions.
    poisoned=capture; poisoned.Replay.InjectedCFO_Hz=-99999;
    poisoned.Replay.InjectedTimingOffset_samples=99999;
    poisoned.Prepared.ReceiverConfig.phy.impairments.cfoHz=99999;
    poisoned.Prepared.ReceiverConfig.phy.impairments.configuredCFOHz=-99999;
    poisoned.DesiredReferenceObservation=localObservation(2*reference,origin,p.SampleRateHz);
    bad=sixgr.link.runTRSTracking(p.ReceiverConfig,'ReceivedContext',poisoned);
    assert(~bad.Crash && ~bad.Ok && bad.NMSE_dB>p.StrictConfig.ChannelNMSEThresholddB && ...
        bad.CFOCorrectionApplied_Hz==out.CFOCorrectionApplied_Hz && ...
        bad.EstimatedTimingOffset_samples==out.EstimatedTimingOffset_samples && ...
        isequaln(bad.DetectionTable,out.DetectionTable));
    disabled=capture;
    disabled.Prepared.ReceiverConfig.phy.rx.cfoCorrectionEnabled=false;
    disabled.Prepared.ReceiverConfig.phy.impairments.cfoCorrectionEnabled=false;
    off=sixgr.link.runTRSTracking(p.ReceiverConfig,'ReceivedContext',disabled);
    assert(~off.Crash && ~off.CFOCorrectionApplied && off.CFOCorrectionApplied_Hz==0 && ...
        off.EstimatedCommonFrequency_Hz==out.EstimatedCommonFrequency_Hz && ...
        isequaln(off.DetectionTable,out.DetectionTable));
    if hz~=0
        assert(off.PreRXRFReferenceNMSE_dB>p.StrictConfig.ChannelNMSEThresholddB, ...
            'Uncompensated RF phase error must remain visible in its distinct pre-RX-RF comparison.');
    end
    again=sixgr.link.runTRSTracking(p.ReceiverConfig,'ReceivedContext',capture);
    assert(again.NMSE_dB==out.NMSE_dB && again.CFOCorrectionApplied_Hz==out.CFOCorrectionApplied_Hz, ...
        'Replaying immutable received IQ must not double-apply correction.');
    fprintf('TRS_CONFIGURED_CP hz=%g estimate=%.9g NMSE=%g offNMSE=%g\n', ...
        hz,out.EstimatedCommonFrequency_Hz,out.NMSE_dB,off.NMSE_dB);
end
% A CP is not a TRS identity detector. Retain all rejected-resource decisions.
rx=struct('Waveform',reference,'NoiseVariance',0,'InjectedTimingOffset_samples',delay);
timing=sixgr.phy.trs.estimateTRSTiming(rx,p.StrictConfig,p.Tx);
det=sixgr.phy.trs.detectTRSResources(rx,p.StrictConfig,p.Tx,'Timing',timing);
det.SlotDetections(1).Detected=false;
det.SlotDetections(2).OFDMInfo=struct();
f=sixgr.phy.trs.estimateTRSFrequencyOffset(det,p.StrictConfig,p.Tx,struct(),p.ReceiverConfig);
assert(~f.EstimateAvailable && all(~f.Table.TRSCFOEstimateAvailable), ...
    'Missing clock/rejected reference cannot be rescued by another frequency hypothesis.');
ok=true;
end

function o=localObservation(wave,origin,fs)
o=sixgr.phy.waveform.WaveformObservationBuffer(origin,origin+size(wave,1),fs,size(wave,2));
o.append(sixgr.phy.waveform.WaveformChunk(wave,origin),fs);
end
