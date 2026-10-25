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
    assert(out.ResidualCFOEstimateAvailable && out.ResidualFrequencyUsesDifferentObservable && ...
        abs(out.ResidualCFO_EstimatedPostCorrection_Hz)<1e-5 && ...
        ~contains(out.ResidualCFOEstimateSource,'cyclic_prefix') && ...
        out.EVMSymbolCount>0 && isfinite(out.EVM_rms), ...
        'Independent post-correction TRS measurement and paired pilots must be retained.');
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
    fprintf('TRS_RESIDUAL_FREQUENCY injected=%g corrected=%.12g uncorrected=%.12g available=%d evidence=%s\n', ...
        hz,out.ResidualCFO_EstimatedPostCorrection_Hz,off.ResidualCFO_EstimatedPostCorrection_Hz, ...
        off.ResidualCFOEstimateAvailable,off.TRSResidualFrequencyEvidenceJSON);
    % Uncorrected CFO creates ICI: pilot phase slope is not algebraically
    % identical to the injected oscillator value, even without AWGN. Check
    % exact agreement with an independent direct-Toolbox IQ calculation,
    % plus the already configured frequency-accuracy requirement. Do not
    % retune the receiver or subtract the injected frequency from its result.
    expected=localPilotFrequencyOracle(observed,p.Tx,delay);
    assert(off.ResidualCFOEstimateAvailable && ...
        abs(off.ResidualCFO_EstimatedPostCorrection_Hz-expected)<1e-8 && ...
        abs(off.ResidualCFO_EstimatedPostCorrection_Hz-hz)<p.StrictConfig.FrequencyToleranceHz, ...
        'Post-correction diagnostic must match actual IQ, including uncompensated ICI.');
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

function hz=localPilotFrequencyOracle(observed,tx,delay)
% Independent test calculation: no SixGR detector/frequency-estimator call.
% The analytic fixture's known delay only positions this scoring oracle.
correlation=0; deltas=zeros(numel(tx.GridSlots),1);
for k=1:numel(tx.GridSlots)
    s=tx.GridSlots(k); K=12*s.Carrier.NSizeGrid;
    ids=double(s.Indices(:)); symbols=floor((ids-1)/K);
    pair=unique(symbols); assert(numel(pair)==2);
    firstSymbol=(s.Slot-tx.FirstSlot0Based)*s.Carrier.SymbolsPerSlot;
    lengths=double(tx.SymbolTimeline.SymbolLengths(:));
    cp=double(tx.SymbolTimeline.CyclicPrefixLengths(:));
    scale=tx.SampleRateHz/(tx.OFDM.Nfft*s.Carrier.SubcarrierSpacing*1000);
    count=round(sum(lengths(firstSymbol+(1:max(pair)+1)))*scale);
    first=tx.SlotTable.StartSample1Based(k)+delay;
    grid=nrOFDMDemodulate(s.Carrier,observed(first:first+count-1,:),'CyclicPrefixFraction',0.5);
    a=find(symbols==pair(1)); b=find(symbols==pair(2));
    [scA,ia]=sort(mod(ids(a)-1,K)+1); [scB,ib]=sort(mod(ids(b)-1,K)+1);
    assert(isequal(scA,scB));
    early=reshape(grid(scA,pair(1)+1,:),numel(a),[])./s.Symbols(a(ia));
    late=reshape(grid(scB,pair(2)+1,:),numel(b),[])./s.Symbols(b(ib));
    correlation=correlation+sum(late.*conj(early),'all');
    at=firstSymbol+pair+1;
    deltas(k)=(sum(lengths(at(1):at(2)-1))+0.5*(cp(at(2))-cp(at(1))))*scale/tx.SampleRateHz;
end
assert(max(deltas)-min(deltas)<1e-12);
hz=angle(correlation)/(2*pi*deltas(1));
end
