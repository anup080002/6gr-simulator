function ok=testSharedReceivedPUCCHPower(evidenceFolder)
% Actual shared decoded nonzero TPC -> selected CSI PUCCH -> first-sample commit.
% Actual shared SS/PBCH clock; declared preconnected identity/TA/pathloss;
% no claim of measured access or decoded RRC P0. PUCCH RX quality is not asserted.
setup6GRSimToolkit('Verbose',false);
if nargin<1, evidenceFolder=tempname; end
assert(~isfolder(evidenceFolder)); mkdir(evidenceFolder);
s=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/validation/lls_pucch_received_power_physical.yaml');
d=s.toStruct();
d.pucch_resources.power_control.closed_loop_mode='received_dci';
d.pucch_resources.power_control.received_dci_installation_policy='configured_dedicated_p0_at_first_connected_control_preparation';
d.pucch_resources.power_control.received_dci_autonomous_policy='received_common_k2';
d.pucch_resources.power_control.delta_tf_mode='ts_38_213_payload_resource';
d.pucch_resources.power_control.require_measured_reference_rs=false;
d.pucch_resources.power_control.closed_loop_adjustment_db=0;
cfg=sixgr.lls6g.buildInternalConfig(sixgr.lls6g.config.ScenarioConfig(d),evidenceFolder);
assert(~sixgr.rf.isNormalizedFixedSNRPowerReference(cfg));
assert(sixgr.phy.frame.ResourceAllocationValidator.encodeSLIV(0,11,14)==69);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,evidenceFolder,multi,struct(),16);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
state.ControlGating.PRACHRequired=false; % Explicit preconnected component boundary.
[state,stream]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,1);
carrier=sixgr.phy.grid.makeCarrier(dl); fs=stream.SampleRateHz;
state.TestEvidenceFolder=evidenceFolder;state.TestReceivedTPC=0;state.TestPUCCHCommits=0;
state.TestPreparationCalls=0;state.TestReceivedPUCCHCapture=false;
prototype=sixgr.link.runCellSearch_MIB_SIB1(dl,'PrepareOnly',true,'UseRuntimeChannel',true,'RuntimeSlot',0,'Content','SSB_MIB_SIB1');
assert(isfield(prototype,'PreparedBroadcast'),'%s',prototype.FailureReason);
broadcast=prototype.PreparedBroadcast;
assert(broadcast.NumSamples<=9*fs*state.SlotDuration_s,'test:BoundedClockCapture','Acquisition must complete before the reserved control preparation boundary.');
stream.queueDownlink('PBCH',1,broadcast,struct('Config',dl,'Slot',1,'ServingCell',1,'Prototype',prototype));
% Complete the original acquisition and preserve its actual shared clock.
% The second-frame control/UL occasions keep the original configured pattern.
for slot=1:9
    state.CurrentSlot=slot;state.CurrentCanonicalSlot=slot;
    state.CurrentFrame=floor((slot-1)/state.SlotsPerFrame)+1;
    [state,~]=stream.advanceSlot(state,cfg,@receive);
end
assert(isfield(state,'TestReceivedSSBClock'),'test:ActualSSBDecodeFailed','Original shared SS/PBCH did not produce a received clock.');
clock=state.TestReceivedSSBClock;
state.CurrentSlot=11;state.CurrentCanonicalSlot=11;
state.CurrentFrame=floor(10/state.SlotsPerFrame)+1;
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,11);
common=state.UECommonCellConfigurationByUE{1};
state.ConnectedULTimingByUE={struct('DLReference',clock, ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,carrier.SubcarrierSpacing,fs), ...
    'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
    'TimeAlignmentExpirySampleExclusive',round(.02*fs))};
state=sixgr.truth.installSharedReceivedPUCCHPower(state,dl,1);
originalOwnerDigest=state.SharedReceivedPUCCHPowerOwners{1}.digest();
repeat=sixgr.truth.installSharedReceivedPUCCHPower(state,dl,1);
assert(repeat.SharedReceivedPUCCHPowerOwners{1}.digest()==originalOwnerDigest);
changed=dl; changed.validation.pucch_resources.power_control.p0_dbm= ...
    changed.validation.pucch_resources.power_control.p0_dbm+1;
rejectInstall(@()sixgr.truth.installSharedReceivedPUCCHPower(state,changed,1));
changedState=state;
changedState.DecodedSIB1RecoveryByUE{1}=rmfield(changedState.DecodedSIB1RecoveryByUE{1},'SIB1RxTreeHash');
rejectInstall(@()sixgr.truth.installSharedReceivedPUCCHPower(changedState,dl,1),'sixgr:truth:PUCCHCommonK2Binding');
changedState=state;
changedState.DecodedSIB1RecoveryByUE{1}.ReceivedSIB1AvailableAtSample=[0 1];
rejectInstall(@()sixgr.truth.installSharedReceivedPUCCHPower(changedState,dl,1),'sixgr:truth:PUCCHCommonK2Binding');
changedState=state;
changedState.UECommonCellConfigurationByUE{1}.PUSCHCommonTiming.K2Slots=1;
rejectInstall(@()sixgr.truth.installSharedReceivedPUCCHPower(changedState,dl,1),'sixgr:truth:PUCCHCommonK2Binding');
changed=dl; changed.phy.frame.DefaultIdentity.ULBWPID=changed.phy.frame.DefaultIdentity.ULBWPID+1;
rejectInstall(@()sixgr.truth.installSharedReceivedPUCCHPower(state,changed,1),'sixgr:truth:PUCCHCommonK2Binding');
installSample=stream.Events.NextSampleIndex;
assert(state.SharedReceivedPUCCHPowerOwners{1}.digest()==originalOwnerDigest && clock.AvailableAtSample<=installSample);
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(dl,'1_1');
defs=sixgr.phy.pdcch.DCISchemaEngine.resolve(context).Definitions;
fields=struct(); for x=defs(:).', fields.(x.Name)=x.ValueMin; end
fields.frequency_resource_assignment=dl.phy.carrier.NSizeGrid*5+3;
fields.mcs=0; fields.rv=0; fields.ndi=0; fields.harq_process=0;
fields.tpc_command_for_pucch=2; % Actual encoded +1 dB command, no forced RX.
packet=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
p=sixgr.link.prepareSharedPDCCHTransmission(dl,'DCIBits',packet.Bits,'RNTI',context.Data.RNTIValue);
stream.queuePDCCH(1,p,struct('Direction',"DL",'ReceivedDLTimingReference',clock, ...
    'Purpose',"declared_connected_control_component_original_RX_required"));
for slot=10:11
    state.CurrentSlot=slot;state.CurrentCanonicalSlot=slot;
    state.CurrentFrame=floor((slot-1)/state.SlotsPerFrame)+1;
    [state,~]=stream.advanceSlot(state,cfg,@receive);
end
assert(state.TestReceivedTPC==1 && isempty(state.SharedReceivedPUCCHPowerOwners{1}.History));
assert(isempty(sixgr.truth.collectReceivedPUCCHPowerHistory(state))); % Received TPC is not TX.
target=15;
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
ul=sixgr.phy.grid.applyRuntimeCarrierTimeline(ul,target);
c=sixgr.phy.grid.makeCarrier(ul); first=sixgr.phy.frame.slotStartSample(c,target-1,fs);
last=sixgr.phy.frame.slotStartSample(c,target,fs);
timing=sixgr.link.resolveConnectedULTransmissionTiming(ul,first/fs,fs,last-first);
state.TestTarget=target;
stream.queuePUCCHPreparation(1,timing,ul,struct('Slot',target,'Key',"original_TPC_CSI_power_component"));
for slot=12:16
    state.CurrentSlot=slot; state.CurrentCanonicalSlot=slot;
    state.CurrentFrame=floor((slot-1)/state.SlotsPerFrame)+1;
    [state,~]=stream.advanceSlot(state,cfg,@receive);
end
assert(state.TestPUCCHCommits==1 && state.TestReceivedPUCCHCapture && ...
    numel(state.SharedReceivedPUCCHPowerOwners{1}.History)==1);
h=state.SharedReceivedPUCCHPowerOwners{1}.History{1};
assert(h.UpdatedG_dB==1 && h.NetTPC_dB==1 && numel(h.AppliedOrHeldAssignmentDigests)==1 && ...
    h.CommittedAtSample==state.SharedPUCCHTXLedger{end}.FirstActiveSample+1);
history=state.SharedReceivedPUCCHPowerOwners{1}.History;
installation=state.SharedReceivedPUCCHPowerInstallations{1};
commands=state.SharedReceivedPUCCHTPCReceipts;
ledger=state.SharedPUCCHTXLedger;
published=sixgr.truth.collectReceivedPUCCHPowerHistory(state);
assert(height(published)==1 && published.HistorySHA256==h.Digest && ...
    published.UpdatedG_dB==1 && published.TransmissionID==ledger{end}.Identity.TransmissionID);
csvPath=fullfile(evidenceFolder,'pucch_received_power_history.csv');
writetable(published,csvPath);
roundtrip=readtable(csvPath,'TextType','string','VariableNamingRule','preserve');
assert(height(roundtrip)==1 && roundtrip.HistorySHA256==published.HistorySHA256 && ...
    roundtrip.AssignmentSHA256==published.AssignmentSHA256 && ...
    roundtrip.HistoryJSON==published.HistoryJSON && roundtrip.UpdatedG_dB==published.UpdatedG_dB);
duplicate=state; duplicate.SharedPUCCHTXLedger{end+1}=ledger{end};
rejectHistory(@()sixgr.truth.collectReceivedPUCCHPowerHistory(duplicate));
tampered=state; tampered.SharedPUCCHTXLedger{end}.FirstActiveSample= ...
    tampered.SharedPUCCHTXLedger{end}.FirstActiveSample+1;
rejectHistory(@()sixgr.truth.collectReceivedPUCCHPowerHistory(tampered));
save(fullfile(evidenceFolder,'original_owner_history.mat'),'history','installation','commands','ledger','-v7.3');
fprintf('SHARED_RECEIVED_PUCCH_POWER_PASS nonzero_received_TPC=1 actual_TX_commit=1\n');
ok=true;
end

function state=receive(state,items)
for item=items
    stream=state.SharedWaveformStream;
    switch item.Kind
        case "PBCH"
            c=item.Context;p=c.Prepared;
            [~,pre,tx,replay,post]=sixgr.truth.sharedObservationEvidence(item.Planes);
            prototype=c.Prototype;prototype.RuntimeChannelReplay=replay;
            prototype.RuntimeDLChannelState=stream.channelState(item.UE,'DL');
            prototype.RuntimeChannelStateUsed=true;prototype.PowerContext=p.PowerContext;
            options=struct('UseRuntimeChannel',true,'RuntimeSlot',0, ...
                'CandidateSSBIndices',c.Config.phy.ssb.activeCandidateIndices0Based,'SSBIndex',[], ...
                'WriteArtifacts',false,'RunFolder','','RunId','original_pucch_clock', ...
                'PhysicalMeasurementObservation',pre,'TransmitObservation',tx);
            output=sixgr.link.completeCellSearchBroadcast(p,post,prototype,options,tic);
            save(fullfile(state.TestEvidenceFolder,'original_shared_SSB_clock.mat'),'output','p','post','-v7.3');
            assert(output.SIB1.BCHCrcPass && output.SIB1.MIBDecoded && ...
                isfield(output.SIB1,'ReceivedDLTimingReference'),'test:ActualSSBDecodeFailed','Original shared PBCH clock is unavailable.');
            state.TestReceivedSSBClock=output.SIB1.ReceivedDLTimingReference;
            assert(output.SIB1.DCICrcPass && output.SIB1.DLSCHCrcPass && ...
                output.SIB1.SIB1ASN1DecodeOk && output.SIB1.SIB1TreeEqual, ...
                'test:ActualSIB1DecodeFailed','Original shared SI did not decode its common UL BWP.');
            installed=sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(),output.SIB1);
            common=installed.UECommonCellConfiguration;
            common.ServingCell=item.Context.ServingCell;
            common.AvailableSlot=state.CurrentSlot;
            common.ConfigurationEpoch=c.Config.initial_access.configuration_epoch;
            common.ReceivedDLTimingReference=output.SIB1.ReceivedDLTimingReference;
            state.UECommonCellConfigurationByUE={common};
            assert(common.PUSCHConfigCommonPresent && common.PUSCHCommonTiming.Available && ...
                isequal(common.PUSCHCommonTiming.K2Slots,4) && common.PUSCHCommonTiming.K2Present && ...
                common.PUSCHCommonTiming.StartSymbolAndLength==69 && ...
                common.PUSCHCommonTiming.MappingType=="typeA");
            recovery=output.SIB1;
            recovery.ReceivedSIB1AvailableAtSample=stream.Events.NextSampleIndex;
            state.DecodedSIB1RecoveryByUE={recovery};
            state.TestOriginalSIB1Recovery=output.SIB1;
        case "PDCCH"
            p=item.Context.Prepared;
            [~,~,~,~,observation]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
            [rx,info]=sixgr.link.completePDCCHReception(p,observation);
            save(fullfile(state.TestEvidenceFolder,'original_control.mat'),'rx','info','p','observation','-v7.3');
            assert(rx.Ok,'test:ActualTPCDecodeFailed','The original physical PDCCH did not decode.');
            a=sixgr.phy.pdcch.materializeConnectedDCI(rx,info,p.ReceiverConfig);
            assert(a.Fields.tpc_command_for_pucch==2);
            receipt=sixgr.truth.buildReceivedPUCCHTPCClock(p,observation,rx,info,a,item.ID,stream.Physical.ConfigurationEpoch);
            state=sixgr.truth.ingestSharedReceivedPUCCHTPC(state,item,a,receipt,true);
            state.TestReceivedTPC=state.TestReceivedTPC+1;
        case "PreparePUCCH"
            [cfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(state.CfgMobility,state,item.UE,'UL');
            cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,item.Context.Slot);
            cfg.lls6g.userContext.RuntimeSlotStartTime_s= ...
                sixgr.phy.frame.slotStartSample(sixgr.phy.grid.makeCarrier(cfg),item.Context.Slot-1,stream.SampleRateHz)/stream.SampleRateHz;
            id=cfg.phy.frame.DefaultIdentity;
            ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
                'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
            frame=struct('K1',1,'K1Source','configured_periodic_CSI_report_occasion', ...
                'PDSCHEndSlot',item.Context.Slot-1,'TargetSlot',item.Context.Slot, ...
                'DecodedPRI',0,'PRIFieldWidth',3,'PRIProvenance','configured_csi_resource', ...
                'FirstCCE',0,'NumCCE',8,'SlotSymbolOwnership',"UUUUUUUUUUUUUU", ...
                'FlexibleResolutionProvided',false);
            sr=sixgr.truth.initializeConfiguredSRProcedures(cfg,ue);
            if ~isempty(sr)
                frame.SchedulingRequestStates=sixgr.phy.pucch.SchedulingRequestState.atSlot(sr,item.Context.Slot-1);
            else
                rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
                assert(isempty(rrc.Data.SchedulingRequestResources), ...
                    'test:MissingConfiguredSRState','Configured SR requires its original procedure state.');
            end
            planned=sixgr.phy.pucch.PUCCHConfigBuilder.planCSI(cfg,ue,int8([1;0;1;0]),int8([]),frame);
            before=state.SharedReceivedPUCCHPowerOwners{1}.digest();
            [deferred,binding]=sixgr.truth.resolveSharedReceivedPUCCHPower(state,item,cfg,planned,struct());
            state.TestPreparationCalls=state.TestPreparationCalls+1;
            assert(state.SharedReceivedPUCCHPowerOwners{1}.digest()==before);
            if deferred, continue; end
            connected=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,planned,binding);
            trial=sixgr.link.runPUCCHWaveformTrial(cfg,'Carrier',sixgr.phy.grid.makeCarrier(cfg), ...
                'Assignment',connected.Assignment,'Report',connected.Report,'ReceiverContext',connected.ReceiverContext, ...
                'SNR_dB',cfg.channel.snr_dB,'ChannelProfile',sixgr.channel.resolveConcreteProfile(cfg), ...
                'TimingAdvanceSamples',cfg.SharedULTimingContext.ReceivedRARTiming.Samples,'PrepareOnly',true);
            prepared=trial.PreparedTransmission;
            assert(prepared.RequestBinding.Assignment.PowerControlState.Data.ClosedLoopAdjustmentdB==1 && ...
                abs(prepared.Tx.Power.PowerError_dB)<1e-10 && isempty(state.SharedReceivedPUCCHPowerOwners{1}.History));
            assert(isempty(sixgr.truth.collectReceivedPUCCHPowerHistory(state))); % Prepared but unsent.
            save(fullfile(state.TestEvidenceFolder,'original_PUCCH_preparation.mat'),'prepared','binding','-v7.3');
            stream.queueUplinkControl(1,prepared,struct('ObservationID',item.Context.ObservationID,'Key',item.Context.Key));
        case "PUCCHTX"
            state=sixgr.truth.commitSharedPUCCHTransmission(state,item);
            try
                sixgr.truth.commitSharedPUCCHTransmission(state,item);
                error('test:DuplicateCommitAccepted','Duplicate TX commit was accepted.');
            catch failure
                assert(strcmp(failure.identifier,'sixgr:truth:DuplicateSharedPUCCHTXCommit'));
            end
            state.TestPUCCHCommits=state.TestPUCCHCommits+1;
        case "PUCCH"
            [post,pre,tx]=sixgr.truth.sharedObservationEvidence(item.Planes,item.Context.Prepared);
            assert(post.isComplete()&&pre.isComplete()&&tx.isComplete());
            state.TestReceivedPUCCHCapture=true;
    end
end
end
function rejectHistory(fn)
try, fn(); catch failure
    assert(strcmp(failure.identifier,'sixgr:truth:PUCCHPowerHistoryBinding')); return;
end
error('test:InvalidPowerHistoryAccepted','Invalid physical power history was published.');
end
function rejectInstall(fn,expected)
if nargin<2,expected='sixgr:truth:PUCCHPowerInstallation';end
try, fn(); catch failure
    assert(strcmp(failure.identifier,expected)); return;
end
error('test:PUCCHRetaggedOwner','A changed owner installation was silently reused.');
end
