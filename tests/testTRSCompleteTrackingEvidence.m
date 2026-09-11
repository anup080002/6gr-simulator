function ok=testTRSCompleteTrackingEvidence()
% Real NR waveform loopback, with deliberate negative evidence mutations.
% No fading/thermal-noise or full-run qualification is claimed here.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
runtimeSlot=double(cfg.phy.trs.slotNumbers(1))+1;
p=sixgr.link.prepareTRSTransmission(cfg,12,'RuntimeSlot',runtimeSlot);
tx=p.Tx; cfg=p.StrictConfig;
rx=struct('Waveform',tx.Waveform,'InjectedTimingOffset_samples',NaN, ...
    'InjectedCFO_Hz',NaN,'NoiseVariance',NaN,'AppliedAWGNSNR_dB',NaN);
timing=sixgr.phy.trs.estimateTRSTiming(rx,cfg,tx);
det=sixgr.phy.trs.detectTRSResources(rx,cfg,tx,'Timing',timing);
freq=sixgr.phy.trs.estimateTRSFrequencyOffset(det,cfg,tx);
ch=sixgr.phy.trs.estimateTRSChannel(rx,cfg,tx,det);
b=sixgr.phy.waveform.WaveformObservationBuffer(0,size(rx.Waveform,1),tx.SampleRateHz,size(rx.Waveform,2));
b.append(sixgr.phy.waveform.WaveformChunk(rx.Waveform,0),tx.SampleRateHz);
t=sixgr.phy.trs.trackTRSOverTime(det,timing,freq,ch,cfg,b);
assert(t.RuntimeEvidenceUsable && ~t.StrictOk, ...
    'Received tracking must work without injected truth, while accuracy remains unqualified.');
withoutClock=sixgr.phy.trs.trackTRSOverTime(det,timing,freq,ch,cfg);
assert(~withoutClock.RuntimeEvidenceUsable);
for value=[0 NaN 2]
    bad=freq; bad.Table.TRSCFOEstimateAvailable=double(bad.Table.TRSCFOEstimateAvailable);
    bad.Table.TRSCFOEstimateAvailable(end)=value;
    failed=sixgr.phy.trs.trackTRSOverTime(det,timing,bad,ch,cfg,b);
    assert(~failed.RuntimeEvidenceUsable);
    score=sixgr.phy.trs.scoreTRSDetection(cfg,rx,det,timing,freq,ch,failed, ...
        'TrialType','runtime_coupled_trs');
    assert(~score.StrictOk && ~score.TrialRow.TrackingRuntimeEvidenceUsable && ...
        contains(score.FailureReason,'tracking'));
end
bad=freq; bad.Table=bad.Table(1,:);
failed=sixgr.phy.trs.trackTRSOverTime(det,timing,bad,ch,cfg,b);
assert(~failed.RuntimeEvidenceUsable,'One successful window cannot replace the full configured burst.');
bad=freq; bad.Table.EstimatedCommonFrequency_Hz(end)=Inf;
failed=sixgr.phy.trs.trackTRSOverTime(det,timing,bad,ch,cfg,b);
assert(~failed.RuntimeEvidenceUsable);
changed=ch; changed.NMSEScoringAvailable=true; changed.MeanNMSE_dB=40;
repeated=sixgr.phy.trs.trackTRSOverTime(det,timing,freq,changed,cfg,b);
assert(repeated.RuntimeEvidenceUsable && ~repeated.StrictOk);
fprintf('TRS_COMPLETE_TRACKING_EVIDENCE_PASS: real waveform, all windows, no truth-dependent receiver gate.\n');
ok=true;
end
