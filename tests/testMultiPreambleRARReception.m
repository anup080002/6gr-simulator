function ok=testMultiPreambleRARReception()
% Independent two-preamble receive evidence and a single coded multi-RAR.
% Bounded unit-channel test, not statistical detector or access qualification.
setup6GRSimToolkit('Verbose',false); previous=rng; cleanup=onCleanup(@()rng(previous));
rng(124083,'twister');
cfg=raStrictAnchorConfig(); cfg.phy.duplex.mode='TDD';
cfg.random_access.temporary_crnti_pool=[6201 6210];
cfg.random_access.preamble_detection_policy='awgn_sic_unrestricted';
cfg.random_access.multi_preamble_max_delay_us=10;
[prepared,cp]=sixgr.phy.ra.runFourStepRA(cfg,'WriteArtifacts',false, ...
    'RuntimeIntegrationMode','provided_observation_unit_channel_test', ...
    'RequireRuntimeStageWaveforms',true,'UseRuntimeChannel',false, ...
    'AllowRuntimeStageWaveformComposition',false,'StageAction','prepare_next_stage');
tx=cp.Msg1Tx; occ=cp.PreparedContext.Occasion; ra=cp.RAConfig;
other=mod(ra.PreambleIndex+1,64);
alt=sixgr.rach.generatePRACHWaveform(tx.PRACHRuntimeConfig,'Occasion',occ,'PreambleIndex',other);
% runFourStepRA already applied the configured PRACH open-loop power to
% tx.Waveform; apply that same configured TX operation to the second UE.
alt.Waveform=alt.Waveform*tx.PowerControl.PreambleTxAmplitudeScale;
single=sixgr.phy.ra.detectMsg1PRACH(tx.Waveform,cfg,ra,occ);
assert(isequal([single.Detections.DetectedPreambleIndex],ra.PreambleIndex));
samples=tx.Waveform+alt.Waveform;
d=sixgr.phy.ra.detectMsg1PRACH(samples,cfg,ra,occ);
assert(isequal(sort([d.Detections.DetectedPreambleIndex]),sort([ra.PreambleIndex other])));
assert(all(startsWith(string({d.Detections.PropagationTimingEstimateSource}), ...
    "sixgr_awgn_unrestricted_measured_sic_original_energy")));
poison=ra; poison.PreambleIndex=63;
blind=sixgr.phy.ra.detectMsg1PRACH(samples,cfg,poison,occ);
assert(isequaln(d.Detections,blind.Detections),'UE TX identity cannot select gNB detections.');
% Noise-only and a weaker second preamble: do not turn root-global peaks
% into copies of the strongest identity or force the expected UE count.
for k=1:4
    noise=(randn(size(samples))+1i*randn(size(samples)))/sqrt(2);
    empty=sixgr.phy.ra.detectMsg1PRACH(noise,cfg,ra,occ);
    assert(~empty.Detected && isempty(empty.Detections));
    % This existing format-0 fixture has one useful symbol. A repetition
    % estimator must explicitly stay unavailable, not invent a noise value.
    assert(isnan(empty.PDPNoiseFloor) && empty.NoiseFloorEvidence.PairCount==0);
    assert(empty.NoiseFloorEvidence.Status=="unavailable_fewer_than_two_repetitions");
    assert(isnan(empty.PeakToNoiseRatio) && isempty(fieldnames(empty.CorrelationTrace)));
end
nearfar=sixgr.phy.ra.detectMsg1PRACH(tx.Waveform+0.6*alt.Waveform,cfg,ra,occ);
assert(numel(nearfar.Detections)==2);
[received,cp]=sixgr.phy.ra.runFourStepRA(cfg,'Continuation',cp, ...
    'RuntimeStageWaveforms',struct('Msg1RxWaveform',localBuffer(samples,prepared.PreparedTransmission)), ...
    'StopAfterStage','Msg1');
assert(received.PreambleDetected);
assert(received.Msg1NoiseFloorEstimator=="disjoint_received_repetition_differences");
assert(received.Msg1NoiseFloorStatus=="unavailable_fewer_than_two_repetitions");
mt=received.ArtifactTables.msg1_prach_detection;
assert(isnan(mt.PDPAverageNoiseFloor) && isnan(received.Msg1PDPAverageNoiseFloor));
assert(mt.NoiseFloorDefinition==received.Msg1NoiseFloorDefinition && mt.NoiseFloorPairCount==0);
% A bounded continuation publishes only actually completed Msg1 evidence.
assert(numel(received.DetectedPRACHPreambles)==2 && ...
    all([received.DetectedPRACHPreambles.Detected]));
assert(height(received.ArtifactTables.msg1_detected_candidates)==2 && ...
    ~received.ArtifactTables.msg1_prach_detection.MissedDetection && ...
    isnan(received.ArtifactTables.msg1_prach_detection.FalseAlarm) && ...
    ~isfield(received.ArtifactTables,'msg3_pusch_trials'));
[state,response,frozen]=sixgr.truth.prepareCellRARResponse(struct(),cfg,cp);
assert(numel(state.GNBTemporaryCRNTIAllocator.Allocations)==2);
assert(numel(frozen.Msg2Tx.RAR.Responses)==2 && frozen.Msg2Tx.RAR.BitLength==128);
reservations=sixgr.truth.CommonRAResourceCalendar.fromTransmission( ...
    frozen.Msg2Tx,frozen.RAConfig,"Msg2");
calendar=sixgr.truth.CommonRAResourceCalendar;
calendar=calendar.reserve(reservations);
assert(numel(calendar.Entries)==3 && ...
    isequaln(calendar.reserve(reservations),calendar), ...
    'One actual RAR reserves one DL allocation and its two disjoint future Msg3 grants.');
assert(~isempty(calendar.lookup(ra.ServingCell,ra.Msg3Slot,"UL",frozen.Msg2Tx.Carrier)));
assert(isempty(calendar.lookup(ra.ServingCell,ra.Msg3Slot-1,"UL",frozen.Msg2Tx.Carrier)));
[state,duplicate,waiting]=sixgr.truth.prepareCellRARResponse(state,cfg,cp);
assert(isempty(fieldnames(duplicate.PreparedTransmission)) && waiting.NextStage==2);
grants=cell(2,1); ueRA=cell(2,1); msg3=cell(2,1);
for k=1:2
    preambles=[ra.PreambleIndex other]; ueRA{k}=ra; ueRA{k}.PreambleIndex=preambles(k);
    ueRA{k}.UEId=k;
    % No transmitted schedule, payload width or RAR reference is supplied.
    [rx,rar]=sixgr.phy.ra.recoverMsg2RAR(response.PreparedTransmission.Waveform,cfg,ueRA{k},struct(),struct());
    assert(rx.Ok && rx.PDCCHReceiver.CausalGrantDecodeOk && rar.RAPID==ueRA{k}.PreambleIndex);
    grants{k}=rar.ULGrant;
    ueRA{k}=sixgr.phy.ra.bindReceivedRARTiming(cfg,ueRA{k},grants{k},rx.RecoveredSchedule);
    payload=sixgr.mac.ra.buildMsg3Payload('UEId',k,'UEIdentity',"UE-"+k,'RRCSetupRequest',true);
    msg3{k}=sixgr.phy.ra.generateMsg3PUSCHWaveform(cfg,ueRA{k},grants{k},payload);
end
assert(grants{1}.TemporaryCRNTI~=grants{2}.TemporaryCRNTI);
assert(msg3{1}.Msg3.ContentionIdentity~=msg3{2}.Msg3.ContentionIdentity);
r1=grants{1}.PRBStart+(0:grants{1}.NumPRB-1); r2=grants{2}.PRBStart+(0:grants{2}.NumPRB-1);
assert(isempty(intersect(r1,r2)) && ueRA{1}.Msg3Slot==ueRA{2}.Msg3Slot);
shared=msg3{1}.Waveform+msg3{2}.Waveform;
for k=1:2
    [rx,message]=sixgr.phy.ra.recoverMsg3PUSCH(shared,cfg,ueRA{k},grants{k},msg3{k});
    assert(rx.Ok && message.ContentionIdentity==msg3{k}.Msg3.ContentionIdentity);
end
% A full-BWP per-preamble request must fail, not silently overlap.
tooWide=cp; tooWide.RAConfig.Msg3PUSCH.NumPRB=ra.NSizeGrid;
localReject(@()sixgr.truth.prepareCellRARResponse(struct(),cfg,tooWide), ...
    'sixgr:truth:RARMsg3CapacityExceeded');
ok=true; disp('MULTI_PREAMBLE_RAR_PASS: independent 2-RAPID detection, one coded RAR, two distinct decoded grants and composite Msg3 CRCs.');
end
function b=localBuffer(w,p)
first=round(p.StartTime_s*p.SampleRate_Hz);
b=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(w,1),p.SampleRate_Hz,size(w,2));
b.append(sixgr.phy.waveform.WaveformChunk(w,first),p.SampleRate_Hz);
end
function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('test:MissingExpectedRejection','Expected %s.',id);
end
