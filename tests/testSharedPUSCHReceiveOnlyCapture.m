function ok=testSharedPUSCHReceiveOnlyCapture()
% Real shared CDL/RF capture with a retained scheduled grant and no UE TX.
% No new DCI reception, PUSCH decode, feedback, or 12 dB acceptance claimed.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
outputRoot=tempname(fullfile(root,'logs')); mkdir(outputRoot);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile(root,'simulator','configs','scenarios', ...
    'lls_received_ul_harq_shared_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,outputRoot);
retained=load(fullfile(root,'docs','lls','evidence_20260913','scheduled_ul_dai_03', ...
    'scheduled_ul_dai_0.mat'),'fixed');
grant=retained.fixed;
previousRNG=rng; cleanup=onCleanup(@()rng(previousRNG)); %#ok<NASGU>
rng(double(cfg.run.seed),'twister');
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
slot0=grant.TimingDecision.DataAbsoluteSlot;
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,outputRoot,multi,struct(),slot0+1);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
ul=sixgr.phy.grid.applyRuntimeCarrierTimeline(ul,slot0+1);
carrier=sixgr.phy.grid.makeCarrier(ul); fs=owner.SampleRateHz;
first=sixgr.phy.frame.slotStartSample(carrier,slot0,fs);
stop=sixgr.phy.frame.slotStartSample(carrier,slot0+1,fs);
beforeClock=owner.Events.NextSampleIndex;
beforePending=owner.Pending;
reject(@()owner.queuePUSCHReceiveOnly(1,ul,grant,first+1,stop), ...
    'sixgr:truth:IncompleteScheduledPUSCHWindow');
bad=grant; bad.UEIndex=2;
reject(@()owner.queuePUSCHReceiveOnly(1,ul,bad,first,stop), ...
    'sixgr:truth:PUSCHReceiveOnlyIdentityMismatch');
assert(isequaln(beforePending,owner.Pending) && isempty(owner.PUSCHReceiveOnlyRegistrations));
id=owner.queuePUSCHReceiveOnly(1,ul,grant,first,stop);
assert(owner.Events.NextSampleIndex==beforeClock && isempty(owner.DataTransmissions));
reject(@()owner.queuePUSCHReceiveOnly(1,ul,grant,first,stop), ...
    'sixgr:truth:DuplicatePUSCHReceiveOnlyObservation');
captures=struct([]);
for slot=1:slot0+1
    % Preserve the retained ordinal's integer class: advanceSlot must handle
    % received grant ordinals without mixed-class OFDM index arithmetic.
    state.CurrentSlot=slot;
    [state,items]=owner.advanceSlot(state,cfg);
    if ~isempty(items), captures=[captures items]; end %#ok<AGROW>
end
assert(isscalar(captures) && captures.Kind=="PUSCHReceiveOnly" && captures.Context.ObservationID==id);
assert(numel(captures.Planes)==2 && ~isfield(captures.Context,'Prepared'));
for plane=captures.Planes
    observation=plane.Observation;
    samples=observation.readComplete();
    assert(observation.StartSample==first && observation.EndSampleExclusive==stop && ...
        observation.SampleRateHz==fs && size(samples,1)==stop-first && all(isfinite(samples),'all'));
    assert(endsWith(plane.ReceiverID,":pre_rf") || endsWith(plane.ReceiverID,":post_rf"));
end
assert(isempty(owner.DataTransmissions) && state.ULHarq.Stats.Tx==0 && state.DLHarq.Stats.Tx==0 && ...
    isempty(state.PendingFeedbackTable) && ~owner.hasPending('PUSCHReceiveOnly',1) && ...
    numel(owner.PUSCHReceiveOnlyRegistrations)==1);
resolvedScenario=s.Data; runtimeVersion=version;
save(fullfile(outputRoot,'receive_only_capture.mat'),'captures','cfg','resolvedScenario','runtimeVersion','grant','-v7.3');
fprintf('PUSCH_RECEIVE_ONLY_CAPTURE_PASS actual_capture=1 UE_TX=0 HARQ_TX=0 decoder_attempts=0 root=%s\n',outputRoot);
ok=true;
end

function reject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
