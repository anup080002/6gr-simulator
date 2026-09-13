function ok=testScheduledHARQACKMapping(outputRoot)
% Actual coded DL TX determines gNB bit identities without UE reception.
% No PDCCH/PDSCH/UCI decode or end-to-end qualification is claimed here.
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve earlier evidence.');
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.run.rootRunFolder=outputRoot;
fprintf('SCHEDULED_HARQ_MAPPING_FIXTURE folder=%s\n',outputRoot);
cfg.phy.ssb.enable=false; cfg.phy.sib1.enable=false; cfg.phy.trs.enable=false;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),3);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
daiLedger=struct(); due=zeros(1,2); state.DLQueueBits(1)=0;
for slot=1:2
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,slot);
    current=sixgr.util.structSet(current,'lls6g.userContext.RuntimeSlotStartTime_s', ...
        (slot-1)*state.SlotDuration_s);
    grant=sixgr.link.resolveWaveformGrant(current,'DL',1, ...
        'Slot',slot,'SFN',0,'ControlAbsoluteSlot',slot-1);
    allocated=state.DLHarq.allocate(grant.RNTI,slot,grant.TBSBits/8,'NewData',true);
    grant=sixgr.link.resolveWaveformGrant(current,'DL',1, ...
        'Slot',slot,'SFN',0,'ControlAbsoluteSlot',slot-1, ...
        'HARQProcess',allocated.HARQ.HarqID);
    grant.ServingCell=grant.BaseStationID;
    [grant,daiLedger]=sixgr.truth.prepareScheduledDLDAI(daiLedger,current,grant);
    assert(allocated.HARQ.NDI==grant.HARQ.NDI);
    grant.ControlDecodeOk=false; grant.PDCCHGrantBindingOk=false;
    job=sixgr.truth.buildGrantPHYJob(current,'DL',cfg.channel.snr_dB,1,[], ...
        struct('GrantSnapshot',grant,'PHYGrant',grant.PHYGrant,'PrepareOnly',true));
    job.StartSlotIndex=slot;
    result=sixgr.truth.executeGrantPHYJob(job);
    assert(~result.ReadyForReceiverCommit && isempty(result.Result.TrialTable));
    owner.queueData(1,result.Result.PreparedTransmission, ...
        struct('Purpose',"independent_gnb_feedback_mapping_component"));
    due(slot)=grant.TimingDecision.FeedbackAbsoluteSlot+1;
    state.DLQueueBits(1)=state.DLQueueBits(1)+grant.TBSBits;
end
localReject(@()sixgr.truth.buildScheduledHARQACKMapping(state,dl,1,due(1)), ...
    'sixgr:truth:MissingScheduledHARQMapping');
for slot=1:3
    state.CurrentSlot=slot;
    [state,~]=owner.advanceSlot(state,cfg,@localReceive);
end
assert(numel(owner.DataTransmissions)==2 && numel(state.SharedDataTXLedger)==2 && ...
    state.DLHarq.Stats.Tx==2 && state.TestMappingRXCaptures==2 && ...
    state.DLHarq.Stats.Ack==0 && state.DLHarq.Stats.Nack==0);
assert(isempty(sixgr.util.structGet(state,'SharedUEHARQACKEvents',{})));
rows=table();
for target=unique(due)
    mapping=sixgr.truth.buildScheduledHARQACKMapping(state,dl,1,target);
    identity=rmfield(mapping,{'LastGrant','Digest'});
    assert(mapping.Digest==sixgr.phy.pucch.PUCCHUtil.hash(identity));
    assert(mapping.BitCount==nnz(due==target) && ...
        isequal([mapping.Records.BitIndex],1:mapping.BitCount) && ...
        ~any(isfield(mapping.Records,{'ExpectedACK','Ack','Bits','DecodedBits'})));
    actualIDs=arrayfun(@(tx)string(tx.Identity.TransmissionID),owner.DataTransmissions);
    assert(all(ismember(string({mapping.Records.TransmissionID}),actualIDs)));
    poisoned=state;
    % Deliberately contradictory observer data must not influence gNB mapping.
    poisoned.SharedUEHARQACKEvents={struct('Event',"not_a_received_event")};
    poisoned.PendingFeedbackTable=table(true,'VariableNames',{'Ack'});
    poisoned.PUCCHGrantTraceTable=table(false,'VariableNames',{'ExpectedAck'});
    same=sixgr.truth.buildScheduledHARQACKMapping(poisoned,dl,1,target);
    assert(isequaln(mapping,same));
    bad=state; bad.SharedDataTXLedger={};
    localReject(@()sixgr.truth.buildScheduledHARQACKMapping(bad,dl,1,target), ...
        'sixgr:truth:HARQMappingUnexecutedSchedule');
    bad=state;
    idx=find(cellfun(@(e)e.FeedbackAbsoluteSlot0+1==target,bad.SharedDLHARQExpectations),1);
    bad.SharedDLHARQExpectations{idx}.NDI=~bad.SharedDLHARQExpectations{idx}.NDI;
    localReject(@()sixgr.truth.buildScheduledHARQACKMapping(bad,dl,1,target), ...
        'sixgr:truth:HARQMappingScheduleMismatch');
    rows=[rows;struct2table(mapping.Records)]; %#ok<AGROW>
    save(fullfile(outputRoot,sprintf('scheduled_mapping_%d.mat',target)),'mapping');
end
writetable(rows,fullfile(outputRoot,'scheduled_bit_mapping.csv'));
fprintf('SCHEDULED_HARQ_ACK_MAPPING_PASS actual_DL_TX=2 UE_receptions=0 gNB_feedback_updates=0 folder=%s\n',outputRoot);
ok=true;
end

function state=localReceive(state,items)
for item=items
    if item.Kind=="DataTX"
        state=sixgr.truth.commitSharedDataTransmission(state,item);
    else
        assert(item.Kind=="PDSCH");
        [post,~,~,~,~]=sixgr.truth.sharedObservationEvidence(item.Planes,item.Context.Prepared);
        assert(~isempty(post.readComplete()));
        state.TestMappingRXCaptures=sixgr.util.structGet(state,'TestMappingRXCaptures',0)+1;
    end
end
end

function localReject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return; end
error('test:MissingRejection','Expected %s',id);
end
