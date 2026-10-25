function [ok,result]=testReceivedMIBSIMonitoring()
% Actual shared BCH -> delivered MIB -> two RX-only SI monitoring members.
% One later cell SI is emitted independently. No new BCH, invented TX
% pointer, complete-access campaign or statistical miss-rate qualification.
% One candidate's actual MIB lifecycle is tested, not optimum beam selection
% or independent power/pathloss estimator qualification.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','received_mib_si_monitoring',char(java.util.UUID.randomUUID()));
mkdir(folder); fprintf('RECEIVED_MIB_SI_MONITORING_EVIDENCE %s\n',folder);
savedRNG=rng; restoreRNG=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
ownedLedger=~sixgr.runtime.RuntimeCallLedger.isConfigured();
if ownedLedger, sixgr.runtime.RuntimeCallLedger.configure(folder,struct('RunId',"received_mib_si_monitoring")); end
cleanupLedger=onCleanup(@()localReleaseLedger(ownedLedger)); %#ok<NASGU>
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,folder); cfg.run.rootRunFolder=folder;
cfg.phy.sib1.transmissionScope="selected_ssb_occasion"; cfg.phy.ssb.runtimeSSBIndex=0;
multi=struct('Enabled',true,'NumUsers',2,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),60);
state.CanonicalSlotsPerSweepPoint=60; % Explicit physical capture horizon for this bounded test.
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg,cfg});
fs=owner.SampleRateHz; carrier=sixgr.phy.grid.makeCarrier(cfg);
beforeRNG=rng; pendingBefore=owner.Pending; clockBefore=owner.Events.NextSampleIndex;
[none,unavailable]=owner.armSIB1ReceiveOnly(state,1,sixgr.phy.frame.slotStartSample(carrier,4,fs));
assert(isempty(none) && ~unavailable.Available && isempty(unavailable.Windows) && ...
    isequaln(owner.Pending,pendingBefore) && isequal(rng,beforeRNG) && owner.Events.NextSampleIndex==clockBefore);

% The new producer scope emits SS/PBCH only, although SI remains configured.
prototype=sixgr.link.runCellSearch_MIB_SIB1(cfg,'PrepareOnly',true, ...
    'UseRuntimeChannel',true,'RuntimeSlot',0,'Content','SSB_MIB','NumSubframes',5);
assert(isfield(prototype,'PreparedBroadcast'),'%s',prototype.FailureReason);
prepared=prototype.PreparedBroadcast;
assert(prepared.Content=="SSB_MIB" && isempty(prepared.Tx.SIB1Transmissions));
context=struct('Config',cfg,'Slot',1,'Frame',1,'RNTI',1,'ServingCell',1,'SNR',20,'Prototype',prototype);
owner.queueDownlink('PBCH',1,prepared,context);
receivedItem=[];
while isempty(receivedItem)
    [state,items]=owner.advanceSlot(state,cfg);
    for item=items
        if item.Kind=="PBCH", receivedItem=item; end
    end
    state.CurrentSlot=state.CurrentSlot+1;
end
[~,pre,tx,replay,post]=sixgr.truth.sharedObservationEvidence(receivedItem.Planes);
prototype.RuntimeChannelReplay=replay; prototype.RuntimeDLChannelState=owner.channelState(1,'DL');
prototype.PowerContext=prepared.PowerContext; prototype.RuntimeChannelStateUsed=true;
options=struct('UseRuntimeChannel',true,'RuntimeSlot',0,'CandidateSSBIndices',0, ...
    'SSBIndex',[],'WriteArtifacts',false,'RunFolder','','RunId','received_mib_si_monitoring', ...
    'PhysicalMeasurementObservation',pre,'TransmitObservation',tx);
[received,contexts]=sixgr.link.completeCellSearchBroadcast(prepared,post,prototype,options,tic);
recovery=received.SIB1; prior=contexts{1};
save(fullfile(folder,'original_shared_BCH.mat'),'receivedItem','received','prior','prepared','-v7.3');
assert(received.PBCH.Ok && recovery.BCHCRCValid && recovery.MIBDecoded && ...
    recovery.SSBIdentityVerified && ~recovery.SIB1ReceptionAttempted && ...
    isa(prior,'sixgr.phy.broadcast.ReceivedMIBContext'));
binding=sixgr.truth.ReceivedMIBDelivery.bindCompleted(state,receivedItem,prior, ...
    recovery.ReceivedDLTimingReference,post);
% Project only actual receiver outcomes/clock into the public acquisition
% reducer; no declared success or hand-written MIB context is substituted.
trial=table(1,post.StartSample,post.EndSampleExclusive,fs,post.EndSampleExclusive/fs, ...
    "complete_contiguous_received_sample_buffer", ...
    'VariableNames',{'Slot','ObservationStartSample','ObservationEndSampleExclusive', ...
    'ObservationSampleRateHz','ObservationCompletionTime_s','ObservationCoverageSource'});
for name=["BCHCRCValid","MIBDecoded","CandidateIdentityConsistent","SSBIdentityVerified","PBCHStrictReceiverEvidenceOk"]
    trial.(name)=recovery.(name);
end
% Retain measured operands when the original receiver supplied them; do not
% replace them with empty/default measurements merely to exercise admission.
for name=["SS_RSRP_dBm","SS_RSRP_dB_re_UnitOccupiedRE_Es","SS_RSRQ_dB","SS_SINR_dB", ...
        "MeasurementUnit","PowerReferencePlane","SSBPhysicalMeasurementReferencePlane", ...
        "SSBIndex","NCellID","Status","Crash"]
    if isfield(received,name), trial.(name)=received.(name);
    elseif isfield(recovery,name), trial.(name)=recovery.(name); end
end
state=sixgr.truth.BroadcastResultDelivery.enqueue(state,1,trial,recovery,false,binding);
[state,ready]=sixgr.truth.BroadcastResultDelivery.takeAvailable(state);
assert(isscalar(ready));
state=sixgr.truth.CoupledTruthRuntime.applyPBCHTrial(state,1,ready.Trial);
[state,installed,status]=sixgr.truth.ReceivedMIBDelivery.deliver(state,ready.MIBBinding);
assert(installed && status=="delivered_original_received_MIB");
[valid,~,binding]=sixgr.truth.ReceivedMIBDelivery.current(state,1); assert(valid);
assert(~sixgr.truth.ReceivedMIBDelivery.current(state,2),'The second UE received no acquisition.');
initialSI=sixgr.util.structGet(state,'DecodedSIB1RecoveryByUE',{struct()});
assert(isempty(initialSI{1}) || isempty(fieldnames(initialSI{1})));

% Two native monitoring members inside the next 20-ms recurrence. The
% horizon is physical and no TX calendar is supplied to the planner.
now=owner.Events.NextSampleIndex;
far=now+round(0.04*fs);
wide=sixgr.truth.planReceivedMIBSIMonitoring(state,1,far);
assert(wide.Available && height(wide.Windows)>=2);
firstPair=wide.Windows.PairStartAbsoluteSlot(1);
pair=wide.Windows(wide.Windows.PairStartAbsoluteSlot==firstPair,:);
assert(height(pair)==2 && isequal(pair.PairMember0Based,[0;1]));
horizon=pair.ReceiveEndSampleExclusive(end);
plan=sixgr.truth.planReceivedMIBSIMonitoring(state,1,horizon);
assert(height(plan.Windows)==2 && isequal(plan.Windows.AbsoluteSlot,pair.AbsoluteSlot));
beforeEnd=sixgr.truth.planReceivedMIBSIMonitoring(state,1,pair.ReceiveEndSampleExclusive(1)-1);
assert(isempty(beforeEnd.Windows),'Incomplete future slots are not receiver trials.');
changed=state;
changed.CfgMobility.initial_access.type0.monitoring_occasion_ordinal=10001;
changed.CfgMobility.phy.sib1.monitoringOccasionOrdinal=10001;
otherOrdinal=sixgr.truth.planReceivedMIBSIMonitoring(changed,1,horizon);
assert(isequaln(otherOrdinal.Windows,plan.Windows) && ...
    otherOrdinal.Type0MonitoringWindowSHA256==plan.Type0MonitoringWindowSHA256, ...
    'Configured selected TX/search ordinal cannot select the RX monitoring member.');
for raw={true,'1',single(horizon),NaN,Inf,-1,horizon+.5,[horizon horizon]}
    reject(@()sixgr.truth.planReceivedMIBSIMonitoring(state,1,raw{1}), ...
        'sixgr:truth:InvalidSIMonitoringClock');
end
reject(@()sixgr.truth.planReceivedMIBSIMonitoring(state,1,now-1), ...
    'sixgr:truth:InvalidSIMonitoringHorizon');
for kind=["lost","new_acquisition","configuration"]
    stale=state;
    switch kind
        case "lost", stale.CellAcquisitionState(1)="searching";
        case "new_acquisition", stale.LastSuccessfulPBCHSlotByUE(1)=state.CurrentSlot+1;
        case "configuration", stale.CfgMobility.initial_access.configuration_epoch= ...
                stale.CfgMobility.initial_access.configuration_epoch+1;
    end
    count=numel(owner.Pending); before=rng;
    [ids,denied]=owner.armSIB1ReceiveOnly(stale,1,horizon);
    assert(isempty(ids) && ~denied.Available && numel(owner.Pending)==count && ...
        owner.Events.NextSampleIndex==now && isequal(rng,before));
end
bad=state; bad.ReceivedMIBByUE{1}.ContextSHA256="changed";
reject(@()owner.armSIB1ReceiveOnly(bad,1,horizon),'sixgr:truth:InvalidReceivedMIBDelivery');

% Use the actual per-slot runtime lookahead for the FIRST registration.
% A shifted complete receive slot must be armed before its start, without
% extending the configured simulation horizon or consulting the SI TX.
perSlotIDs=strings(0,1);
while isempty(perSlotIDs)
    perSlotIDs=sixgr.truth.armReceivedMIBSIForSlot(state);
    if ~isempty(perSlotIDs), break; end
    assert(owner.Events.NextSampleIndex<pair.ReceiveStartSample(1), ...
        'Per-slot planning missed the first complete future SI capture.');
    [state,unexpected]=owner.advanceSlot(state,cfg);
    assert(isempty(unexpected),'No SI reception can complete before its first registration.');
    state.CurrentSlot=state.CurrentSlot+1;
end
now=owner.Events.NextSampleIndex;
assert(now<=pair.ReceiveStartSample(1));
firstArmed=owner.Pending(string({owner.Pending.Kind})=="SIB1");
assert(any(arrayfun(@(p)p.Context.AbsoluteMonitoringSlot,firstArmed)==pair.AbsoluteSlot(1)));
beforeRNG=rng; beforeLedger=sixgr.runtime.RuntimeCallLedger.snapshot();
[ids,armedPlan]=owner.armSIB1ReceiveOnly(state,1,horizon);
[again,~]=owner.armSIB1ReceiveOnly(state,1,horizon);
assert(isequal(ids,again) && numel(ids)==2 && numel(owner.Pending)==2 && ...
    isequal(rng,beforeRNG) && owner.Events.NextSampleIndex==now && ...
    isequaln(beforeLedger,sixgr.runtime.RuntimeCallLedger.snapshot()));
for p=owner.Pending
    assert(p.Kind=="SIB1" && p.UE==1 && ~isfield(p.Context,'Prepared') && ...
        ~isfield(p.Context,'TransmitterPlane') && p.Context.ReceiveOnly && ...
        ~p.Context.TransmissionScheduled && p.Context.ArmedAtSample<=now && ...
        p.Context.ReceivedMIBBinding.GenerationID==binding.GenerationID);
end
reject(@()owner.armSIB1ReceiveOnly(changed,1,horizon),'sixgr:truth:ChangedSIReceiveRegistration');

% TX makes its independent configured decision only AFTER RX obligations
% have been frozen. The receiver does not inspect this chosen ordinal.
txPlan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
txRows=txPlan.sib1TransmissionOccasions(pair.AbsoluteSlot(1),pair.AbsoluteSlot(end)+1);
assert(height(txRows)==1 && ismember(txRows.AbsoluteSlot,pair.AbsoluteSlot));
si=sixgr.link.prepareSIB1Transmission(cfg,prepared.Tx.SSBInfo,'AbsoluteSlot',txRows.AbsoluteSlot);
originalSIHash=sixgr.phy.waveform.WaveformHash.runtimeArray(si.TransmitSamples);
owner.queueSIB1Transmission(1,si);
afterTX=sixgr.truth.planReceivedMIBSIMonitoring(state,1,horizon);
assert(isequaln(afterTX.Windows,armedPlan.Windows));
protected=localProtectedState(state);
originalReceivers=cell(0,1); recoveries=cell(0,1); guarded=false;
while owner.Events.NextSampleIndex<horizon
    state=sixgr.truth.SIB1ResultDelivery.deliver(state);
    [state,items]=owner.advanceSlot(state,cfg);
    for item=items
        if item.Kind~="SIB1", continue; end
        assert(numel(item.Planes)==2 && isequal(sort(string({item.Planes.ReceiverID})), ...
            sort(["ue_1_rx:pre_rf","ue_1_rx:post_rf"])), ...
            'Only original RX planes belong to SI.');
        owner.validateCompletedBroadcastObservation(item);
        originalReceivers{end+1,1}=item; %#ok<AGROW>
        originalHash=item.Planes(1).Observation.sampleHash();
        clock=owner.Events.NextSampleIndex; before=rng;
        [state,r]=sixgr.truth.SIB1ResultDelivery.complete(state,item);
        recoveries{end+1,1}=r; %#ok<AGROW>
        save(fullfile(folder,sprintf('original_SI_RX_%d.mat',numel(recoveries))),'item','r','-v7.3');
        assert(~r.NewBCHReceptionAttempted && r.PriorBCHContextSHA256==binding.ContextSHA256 && ...
            r.SIB1ReceptionAttempted && r.SIB1ObservationComplete && ...
            owner.Events.NextSampleIndex==clock && isequal(rng,before) && ...
            item.Planes(1).Observation.sampleHash()==originalHash);
        reject(@()sixgr.truth.SIB1ResultDelivery.complete(state,item),'sixgr:truth:DuplicateSIB1Completion');
        deferred=sixgr.truth.SIB1ResultDelivery.deliver(state);
        assert(numel(deferred.PendingSIB1Results)==numel(state.PendingSIB1Results), ...
            'Complete samples cannot be installed before their canonical delivery boundary.');
        bad=item; bad.Context.AbsoluteMonitoringSlot=bad.Context.AbsoluteMonitoringSlot+1;
        reject(@()owner.validateCompletedBroadcastObservation(bad),'sixgr:truth:BroadcastCompletedCaptureMismatch');
        bad=item; bad.Context.ReceiverConfig.initial_access.configuration_epoch= ...
            bad.Context.ReceiverConfig.initial_access.configuration_epoch+1;
        reject(@()owner.validateCompletedBroadcastObservation(bad),'sixgr:truth:BroadcastCompletedCaptureMismatch');
        bad=item; j=find(endsWith(string({bad.Planes.ReceiverID}),':post_rf'));
        raw=bad.Planes(j).Observation; samples=raw.readComplete(); samples(1)=samples(1)+1;
        replacement=sixgr.phy.waveform.WaveformObservationBuffer(raw.StartSample,raw.EndSampleExclusive,fs,size(samples,2));
        replacement.append(sixgr.phy.waveform.WaveformChunk(samples,raw.StartSample),fs);
        bad.Planes(j).Observation=replacement;
        reject(@()owner.validateCompletedBroadcastObservation(bad),'sixgr:truth:BroadcastCompletedCaptureMismatch');
    end
    state.CurrentSlot=state.CurrentSlot+1;
    if ~guarded && isfield(state,'PendingSIB1Results') && ~isempty(state.PendingSIB1Results)
        bad=state; bad.PendingSIB1Results(1).Recovery.FailureReason="changed_pending_original_result";
        reject(@()sixgr.truth.SIB1ResultDelivery.deliver(bad),'sixgr:truth:SIB1PendingResultChanged');
        stale=state; stale.CellAcquisitionState(1)="searching";
        stale=sixgr.truth.SIB1ResultDelivery.deliver(stale);
        assert(~any(stale.SharedSIB1ReceptionTable.Installed));
        guarded=true;
    end
end
state=sixgr.truth.SIB1ResultDelivery.deliver(state);
T=state.SharedSIB1ReceptionTable;
pendingAfterInstall=owner.Pending;
assert(isempty(sixgr.truth.armReceivedMIBSIForSlot(state)) && ...
    isequaln(owner.Pending,pendingAfterInstall), ...
    'Installed SI must not create new monitoring or cancel an already armed capture.');
siPath=sixgr.truth.exportSharedSIB1Reception(state,folder);
assert(siPath==string(fullfile(folder,'air_interface','csv','sib1_received_trials.csv')));
siTypes=struct();
for siName=string(T.Properties.VariableNames)
    if isstring(T.(siName)), siTypes.(siName)='string'; end
end
siRead=sixgr.util.csvReadTable(siPath,'ColumnTypes',siTypes);
assert(isequal(siRead.Properties.VariableNames,T.Properties.VariableNames) && height(siRead)==height(T));
for siName=string(T.Properties.VariableNames)
    if isstring(T.(siName))
        siValue=string(siRead.(siName)); siValue(ismissing(siValue))="";
        assert(isequal(siValue,T.(siName)));
    elseif islogical(T.(siName))
        assert(isequal(logical(siRead.(siName)),T.(siName)));
    else
        assert(isequaln(siRead.(siName),T.(siName)));
    end
end
save(fullfile(folder,'original_monitoring_plan.mat'),'plan','armedPlan','binding','T','recoveries','-v7.3');
assert(height(T)==2 && numel(originalReceivers)==2 && guarded && ...
    all(T.SIB1ReceptionAttempted) && all(T.SIB1ObservationComplete) && ...
    ~any(T.NewBCHReceptionAttempted) && sum(T.Installed)==1 && ...
    T.ResourceAbsoluteSlot0Based(T.Installed)==txRows.AbsoluteSlot && ...
    isempty(state.PendingSIB1Results));
success=find(T.Installed); missed=find(~T.Installed);
assert(T.DCICrcPass(success) && T.DLSCHCrcPass(success) && ...
    ~T.DCICrcPass(missed) && ~T.DLSCHCrcPass(missed), ...
    'Retain an actual untransmitted monitoring outcome, not a configured scheduling answer.');
assert(isequaln(protected,localProtectedState(state)) && ...
    state.UECommonCellConfigurationByUE{1}.Source=="decoded_sib1" && ...
    isequaln(state.UECommonCellConfigurationByUE{1}.ReceivedDLTimingReference,binding.ReceivedDLTimingReference) && ...
    state.DecodedSIB1RecoveryByUE{1}.ReceivedMIBGenerationID==binding.GenerationID && ...
    numel(owner.SIB1Transmissions)==1 && ...
    owner.SIB1Transmissions.PreparedSampleSHA256==originalSIHash);
calls=sixgr.runtime.RuntimeCallLedger.snapshot(); calls=calls(height(beforeLedger)+1:end,:);
for name=["sixgr.phy.dl.PDCCH_Tx","sixgr.phy.dl.PDSCH_Tx"]
    assert(sum(calls.FunctionName==name)==1);
end
assert(sum(calls.FunctionName=="sixgr.phy.dl.PDCCH_Rx")==2 && ...
    ~any(contains(calls.FunctionName,"SSB_Tx")|contains(calls.FunctionName,"PBCH_Recovery")));
result=struct('EvidenceRoot',string(folder),'OriginalBCHReceivers',1, ...
    'LaterSIReceiveWindows',2,'LaterSITransmissions',1,'LaterBCHReceivers',0, ...
    'Scope',"bounded_original_shared_receiver_owner_not_full_access_campaign", ...
    'StatisticallyQualified',false);
ok=true;
fprintf('RECEIVED_MIB_SI_MONITORING_PASS original_BCH=1 SI_RX=2 SI_TX=1 later_BCH=0 root=%s\n',folder);
end

function value=localProtectedState(state)
value=struct();
for name=["CellAcquisitionState","LastSuccessfulPBCHSlotByUE","LastSuccessfulTRSSlotByUE", ...
        "SelectedSSBIndexByUE","SelectedSSBBeamIndexByUE","ReferenceSignalMeasurementTable","ReceivedMIBByUE"]
    if isfield(state,name), value.(name)=state.(name); end
end
end

function reject(action,identifier)
try, action(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s',identifier,cause.identifier,cause.message); return;
end
error('test:MissingSIReceiveRejection','Expected %s.',identifier);
end

function localReleaseLedger(owned)
if owned, sixgr.runtime.RuntimeCallLedger.reset(); end
end
