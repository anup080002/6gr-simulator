function ok=testSharedInitialT300Cancellation()
% Codec-installed SI/clock are declared component
% inputs; T300, queued native Msg1 cancellation and late captures are actual
% shared-owner events. No received SI, access completion or RF pass claim.
folder=fullfile(pwd,'results','validation','initial_T300_cancellation',char(java.util.UUID.randomUUID()));
mkdir(folder);fprintf('INITIAL_T300_SHARED_EVIDENCE %s\n',folder);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_2ghz_5mhz_rank2_4tx2rx_awgn_0db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,folder);cfg.run.rootRunFolder=folder;
cfg.outputs.continuousRawIQCaptureEnabled=false;cfg.rrc.sib1.t300="ms100";
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
% This test has no application traffic; the fifth input is traffic horizon,
% not SNR. Only the original shared sample clock and access timer advance.
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),0);
state.CurrentSlot=1;state.CurrentCanonicalSlot=1;state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});fs=owner.SampleRateHz;
[common,recovery]=declaredCommonCodec(cfg,owner.Physical.ConfigurationEpoch);
policy=sixgr.lls6g.config.resolveNRAccessPolicy(struct('encoding_profile',"nr_rrc_access_base_srb1_uper_v1", ...
    'require_setup_complete',true,'transaction_id',2,'srb1_lcid',1,'establishment_cause',"mo-Signalling", ...
    'selected_plmn_identity',1,'dedicated_nas_hex',"7E0041"));
context=struct('RunID',"declared_codec_SI_actual_shared_T300",'UEIndex',1,'ServingCell',1, ...
    'ConfigurationEpoch',owner.Physical.ConfigurationEpoch,'SampleRateHz',fs,'StartSample',0);
a=sixgr.mac.ra.NRRRCSetupAttemptState(policy,common,recovery,context,RandStream('mt19937ar','Seed',41));
assert(a.ExpirySampleExclusive==fs*.1);
owner.armRRCSetupTimer(1,a);
[uc,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
uc.SharedULTimingContext=struct('DLReference',struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',fs,'DLPhaseOffsetSamples',0,'AvailableAtSample',0, ...
    'TestScope',"declared_receiver_clock_not_BCH_evidence"), ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(struct('Source',"decoded_sib1", ...
    'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',""),"FR1"));
future=ceil(.105/state.SlotDuration_s)+1;
[prepared,cp]=sixgr.phy.ra.runFourStepRA(uc,'WriteArtifacts',false, ...
    'RunId',"initial_T300_future_MAC_attempt",'UEId',1,'AttemptId',1, ...
    'RuntimeSlot',future,'PreamblePowerRampingCounter',1, ...
    'RuntimeIntegrationMode','shared_physical_waveform_stream','UseRuntimeChannel',true, ...
    'RequireRuntimeStageWaveforms',true,'AllowRuntimeStageWaveformComposition',false, ...
    'StageAction','prepare_next_stage','InitialDLChannelState',owner.directionalChannelState(1,"DL"), ...
    'InitialULChannelState',owner.directionalChannelState(1,"UL"));
p=prepared.PreparedTransmission;
first=sixgr.phy.ra.preparedStageTransmitStartSample(p);
active=find(any(p.PhysicalWaveform~=0,2),1,'first');
assert(first+active-1>a.ExpirySampleExclusive,'Use a genuinely future never-emitted native component.');
a=a.bindMACAttempt(cp.RAConfig,0);state.NRRRCSetupAttemptsByUE={a};
retry=sixgr.mac.ra.RARetryState(41);retry=retry.prepare("declared_initial_reference",int64(0),false,false);
state.RARetryByUE={retry.arm(cp.RAConfig)};
state.PendingRAAttempts={struct('Config',uc,'Continuation',cp,'Received',[])};
state.UECommonCellConfigurationByUE={common};state.TestOriginalCommon=common;
state.TestOriginalAttempt=a;state.TestExpiry=struct();state.TestLateItems={};
owner.armRARWindow(1,cp.RAConfig);component=owner.queueMsg1Transmission(1,p,cp);
tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
stop=double(cp.RAConfig.RARMonitoringWindow.ExpiryTicksExclusive/int64(tc));
assert(stop<fs*.2,'Keep the actual shared expiry/capture test under200ms.');
while owner.Events.NextSampleIndex<stop
    [state,~]=owner.advanceSlot(state,cfg,@receive);
    state.CurrentSlot=state.CurrentSlot+1;
    state.CurrentCanonicalSlot=state.CurrentSlot;
end
assert(state.NRRRCSetupAttemptsByUE{1}.Status=="failed_upper_layer_notified" && ...
    isempty(state.PendingRAAttempts{1})&&isempty(state.RARetryByUE{1}) && ...
    isequaln(state.UECommonCellConfigurationByUE{1},state.TestOriginalCommon));
r=state.NRRRCUpperLayerIndications{1};retired=r.PhysicalRetirement;
assert(r.ResetSample==a.ExpirySampleExclusive&&numel(retired.Cancellations)==1 && ...
    ~retired.EmittedSamplesChanged&&~retired.GNBCellResponsesCancelled);
assert(any(cellfun(@(v)v.ID==component && v.Context.OriginalKind=="Msg1TX" && ...
    v.Context.ComponentCancelled && isempty(fieldnames(v.Context.ActualMsg1TXCompletion)),state.TestLateItems)));
assert(numel(state.RetiredInitialAccessObservationIDs)==numel(state.TestLateItems));
save(fullfile(folder,'actual_T300_retirement.mat'),'r','component','cp','p','-v7.3');
ok=true;fprintf('SHARED_INITIAL_T300_CANCELLATION_PASS actual_timer_and_cancellation=1 late_original_captures=%d SI_declared_codec_boundary=1 UE_TX=0 access_completed=0\n',numel(state.TestLateItems));
end
function state=receive(state,items)
items=sixgr.truth.orderSharedReceiverCompletions(items);
for item=items
    if item.Kind=="RRCSetupExpiry"
        state=sixgr.truth.completeInitialNRRRCExpiry(state,item);state.TestExpiry=item;
    elseif item.Kind=="RetiredInitialAccess"
        state=sixgr.truth.retainRetiredInitialAccessObservation(state,item);
        state.TestLateItems{end+1,1}=item;
    else
        error('test:UnexpectedInitialRRCCompletion','Unexpected live callback %s.',item.Kind);
    end
end
end
function [common,rx]=declaredCommonCodec(cfg,epoch)
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);[bits,encoded]=sixgr.rrc.asn1.encodeSIB1UPER(tree);
tree=sixgr.rrc.asn1.decodeSIB1UPER(bits);[~,hash]=sixgr.rrc.asn1.compareSIB1Trees(tree,tree);
rx=struct('StrictOk',true,'DCICrcPass',true,'DLSCHCrcPass',true,'SIB1ASN1DecodeOk',true, ...
    'SIB1SemanticValid',true,'SIB1RxTree',tree,'SIB1PayloadHashRx',encoded.PayloadHash, ...
    'SIB1RxTreeHash',hash.RxTreeHash,'ReferenceConfigurationEpoch',epoch,'MeasurementClockEpoch',epoch, ...
    'OriginalServingCell',1,'ReceivedSIB1AvailableAtSample',0, ...
    'FixtureBoundary',"declared_original_codec_installation_no_SI_RF");
installed=sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,rx);
common=installed.UECommonCellConfiguration;common.ServingCell=1;common.ConfigurationEpoch=epoch;
end
