function ok=testConfiguredCSIReceiveTAGGate()
% Scheduling-only TAG boundary; no PHY/CSI decode qualification is claimed.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_four_port_shared_awgn_12db.yaml'));
root=fullfile(pwd,'results','lls','configured_csi_tag_gate', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(s,root);
cfg.run.rootRunFolder=root;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),58);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,58,cfg.channel.snr_dB);
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
% Probe the future planning view without executing or claiming any samples.
state.CurrentSlot=18; state.CurrentCanonicalSlot=18; state.CurrentFrame=2;
carrier=sixgr.phy.grid.makeCarrier(cfg); fs=owner.SampleRateHz;
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'NCellID',carrier.NCellID,'SampleRateHz',fs,'DLPhaseOffsetSamples',6,'AvailableAtSample',0);
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
context=struct('DLReference',reference, ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,carrier.SubcarrierSpacing,fs), ...
    'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
    'TimeAlignmentExpirySampleExclusive',Inf);
state.ConnectedULTimingByUE={context};
state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture(cfg,0,1,1)};
state.UECommonCellConfigurationByUE{1}.InitialULBWP.SubcarrierSpacing_kHz=carrier.SubcarrierSpacing;
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
begin=sixgr.phy.frame.slotStartSample(carrier,18,fs);
stop=sixgr.phy.frame.slotStartSample(carrier,19,fs);
timing=sixgr.link.resolveConnectedULTransmissionTiming(ul,begin/fs,fs,stop-begin);
assert(isempty(owner.Pending) && isempty(state.PendingCSITable));
before=owner.Events.NextSampleIndex;
ids=["sixgr:link:ConnectedULBeforeReceivedTA", ...
    "sixgr:link:ConnectedULBeforeTAApplication","sixgr:link:ConnectedULAfterTAExpiry"];
for k=1:3
    candidate=state; changed=context;
    if k==1
        changed.TimingAdvanceAvailableAtSample=timing.TransmitStartSample+1;
        changed.TimingAdvanceEffectiveAtSample=changed.TimingAdvanceAvailableAtSample;
    elseif k==2
        changed.TimingAdvanceEffectiveAtSample=timing.TransmitStartSample+1;
    else
        changed.TimeAlignmentExpirySampleExclusive=timing.TransmitEndSampleExclusive-1;
    end
    candidate.ConnectedULTimingByUE={changed};
    strict=ul; strict.SharedULTimingContext=changed;
    localReject(@()sixgr.link.resolveConnectedULTransmissionTiming(strict,begin/fs,fs,stop-begin),ids(k));
    if k==1
        localReject(@()sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(candidate), ...
            'sixgr:truth:FutureReceivedULTiming');
        continue;
    end
    candidate=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(candidate);
    assert(isempty(owner.Pending) && isempty(candidate.PendingCSITable) && ...
        isempty(candidate.SharedArmedPUCCHOccasions) && owner.Events.NextSampleIndex==before);
end
bad=state; bad.ConnectedULTimingByUE{1}.ReceivedRARTiming.Command=1;
localReject(@()sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(bad), ...
    'sixgr:link:ConnectedULTimingAuthorityMismatch');
% Inclusive application and exclusive expiry boundaries retain the complete
% waveform; no extra sample of tolerance or artificial timing shift.
state.ConnectedULTimingByUE{1}.TimingAdvanceEffectiveAtSample=timing.TransmitStartSample;
state.ConnectedULTimingByUE{1}.TimeAlignmentExpirySampleExclusive=timing.TransmitEndSampleExclusive;
state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
assert(numel(owner.Pending)==1 && numel(state.SharedArmedPUCCHOccasions)==1 && ...
    owner.Pending.Context.Slot==19 && isempty(state.PendingCSITable) && ...
    owner.Events.NextSampleIndex==before);
save(fullfile(root,'tag_gate.mat'),'timing','context','ids');
fprintf('CONFIGURED_CSI_RECEIVE_TAG_GATE_PASS scheduling_only=1 root=%s\n',root);
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(string(ME.identifier)==string(id),'Expected %s: %s',id,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
