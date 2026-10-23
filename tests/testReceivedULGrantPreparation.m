function ok=testReceivedULGrantPreparation()
% Actual isolated blind PDCCH decode, declared TAG/capture-placement fixture,
% and real shared event clock. NOT shared-channel PDCCH, access, PUSCH TX/RX,
% or scheduler qualification. The event callback only observes preparation;
% no data waveform is built and no emitted-data/HARQ success is asserted.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_pdcch_shared_queue_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),20);
state.CurrentSlot=1; state.CurrentCanonicalSlot=1; state.CurrentFrame=1;
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[installed,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
carrier=sixgr.phy.grid.makeCarrier(installed); fs=owner.SampleRateHz;
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'NCellID',carrier.NCellID,'SampleRateHz',fs,'DLPhaseOffsetSamples',6,'AvailableAtSample',0);
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
state.ConnectedULTimingByUE={struct('DLReference',reference, ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,carrier.SubcarrierSpacing,fs), ...
    'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
    'TimeAlignmentExpirySampleExclusive',round(.02*fs))};
state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture(cfg,0,1,1)};
state.UECommonCellConfigurationByUE{1}.InitialULBWP.SubcarrierSpacing_kHz=carrier.SubcarrierSpacing;

% Choose an installed legal DCI/PUSCH pair with room for the complete
% isolated control-slot buffer. Do not edit K2, TDD or TAG to force a pass.
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(installed,'0_1');
[control0,tdra]=localOccasion(installed,context.Data.ULTimeDomainAllocations);
installed=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,control0+1);
first=sixgr.phy.frame.slotStartSample(carrier,control0,fs);
installed.lls6g.userContext.RuntimeSlotStartTime_s=first/fs;
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(installed,'0_1');
schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
fields=struct(); for d=schema.Definitions(:).', fields.(d.Name)=d.ValueMin; end
fields.time_resource_assignment=tdra(1);
fields.frequency_resource_assignment=installed.phy.carrier.NSizeGrid*5+3;
fields.mcs=0; fields.ndi=1; fields.rv=0;
packet=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
p=sixgr.link.preparePDCCHTransmission(installed,'DCIBits',packet.Bits,'RNTI',context.Data.RNTIValue);
post=localBuffer(first,p.TransmitSamples,fs);
[rx,info]=sixgr.link.completePDCCHReception(p,post);
a=sixgr.phy.pdcch.materializeConnectedDCI(rx,info,installed);
assert(rx.Ok && rx.CausalGrantDecodeOk && isequal(rx.DCIBits(:),packet.Bits(:)) && ...
    a.ControlAbsoluteSlot==control0 && a.DataAbsoluteSlot==control0+tdra(4));
allocation=sixgr.phy.pdcch.connectedDataAllocation(installed,a);
g=struct('UEIndex',1,'RNTI',a.RNTI,'ServingCell',1,'Direction',"UL", ...
    'Slot',a.DataAbsoluteSlot+1,'Frame',floor(a.DataAbsoluteSlot/carrier.SlotsPerFrame)+1, ...
    'ControlSlot',control0+1,'ControlAbsoluteSlot',control0, ...
    'GrantContextId',"declared_handoff_"+a.AssignmentDigest, ...
    'PRBSet',a.PRBStart+(0:a.NumPRB-1),'SymbolAllocation',a.SymbolAllocation, ...
    'MCSIndex',a.MCS,'NumLayers',a.NumLayers,'HARQProcess',a.HARQProcess, ...
    'NDI',a.NDI,'RV',a.RV,'TBSBits',allocation.NominalTBSBits, ...
    'TBSBytes',allocation.NominalTBSBits/8, ...
    'PDCCHGrantBindingRequired',true,'PDCCHGrantBindingOk',true, ...
    'PDCCHGrantDCIId',a.PayloadHash);
% These reducer-boundary field hashes are computed from the actual decoded
% fields and independently parsed authored fields; they are not a claim to
% the runner's separate normalized grant-binding hash schema.
authored=sixgr.phy.pdcch.DCIParser.parse(packet.Bits,context);
g.PDCCHGrantDCIFieldsHash=localHash(rx.DecodedDCI.Fields);
g.PDCCHGrantFieldsHash=localHash(authored.Fields);
key="declared_received_ul_"+a.AssignmentDigest;
c=struct('Key',key,'Grant',g,'Prepared',p,'UserCfg',{{cfg}}, ...
    'Direction',"UL",'Slot',control0+1,'Frame',floor(control0/carrier.SlotsPerFrame)+1, ...
    'ServingCell',1,'RNTI',a.RNTI, ...
    'Purpose',"isolated_decoded_DCI_handoff_not_shared_waveform_qualification");
item=struct('ID',"declared_completed_capture_"+a.AssignmentDigest, ...
    'Kind',"PDCCH",'UE',1,'Context',c, ...
    'Planes',struct('ReceiverID',"ue_1_rx:post_rf",'Observation',post));
state.TestReceivedULItem=item;
state.TestReceivedULAssignment=a;
state.TestReceivedULRow=table(control0+1,c.Frame,"PASS",logical(rx.Ok),logical(rx.Ok), ...
    logical(rx.DCIPayloadMatch),logical(rx.CausalGrantDecodeOk),logical(rx.FalseAlarm),false, ...
    'VariableNames',{'Slot','Frame','Status','CRCPass','DCICrcPass','PDCCHPayloadMatch', ...
    'PDCCHCausalGrantDecodeOk','PDCCHFalseAlarm','PDCCHMissedDetection'});
state.TestReceivedULPreparationCount=0;
state.TestOriginalULQueueBits=state.ULQueueBits;
state.TestOriginalULTxCount=state.ULHarq.Stats.Tx;
state.SharedPendingULGrants=struct('Slot',g.Slot+1,'PriorCalendarMetadata',"retain_me");
% A declared receive-completion timer places the isolated decoded buffer on
% the component clock. It is not registered as shared PDCCH RF execution.
owner.queueULDataPreparation(1,post.EndSampleExclusive,struct('TestReceiveBoundary',true));
for slot=1:g.Slot
    state.CurrentSlot=slot; state.CurrentCanonicalSlot=slot;
    state.CurrentFrame=floor((slot-1)/carrier.SlotsPerFrame)+1;
    [state,~]=owner.advanceSlot(state,cfg,@localReceive);
end
assert(state.TestReceivedULPreparationCount==1 && state.TestReceivedULNegativeCount==15);
before=owner.Events.NextSampleIndex;
localReject(@()sixgr.truth.queueReceivedULGrantPreparation(state, ...
    state.TestReceivedULItem,state.SharedReceivedGrantControls{1}), ...
    'sixgr:truth:LateReceivedULPreparation');
assert(owner.Events.NextSampleIndex==before);
assert(height(state.ULGrantTraceTable)==1 && ...
    state.ULGrantTraceTable.TBSBits==allocation.NominalTBSBits && ...
    string(state.ULGrantTraceTable.GrantContextId)==string(g.GrantContextId));
assert(isempty(owner.DataTransmissions) && isempty(sixgr.util.structGet(state,'SharedDataTXLedger',{})) && ...
    isequaln(state.ULQueueBits,state.TestOriginalULQueueBits) && ...
    state.ULHarq.Stats.Tx==state.TestOriginalULTxCount);
ok=true; disp('RECEIVED_UL_GRANT_PREPARATION_PASS');
end

function state=localReceive(state,events)
for event=events
    assert(event.Kind=="PrepareULData");
    owner=state.SharedWaveformStream;
    if isfield(event.Context,'TestReceiveBoundary')
        item=state.TestReceivedULItem;
        [state,g,allowed]=sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial( ...
            state,item.Context.Grant,'UL',state.TestReceivedULRow);
        assert(allowed);
        control=struct('Key',item.Context.Key,'Grant',g,'Allowed',allowed, ...
            'ReceivedAssignment',state.TestReceivedULAssignment, ...
            'AvailableAtSample',item.Planes.Observation.EndSampleExclusive);
        state.SharedReceivedGrantControls={control};
        before=owner.Events.NextSampleIndex;
        bad=state; bad.RuntimeViewMode="future_ul_grant_planning";
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(bad,item,control), ...
            'sixgr:truth:ReceivedULPreparationLiveOwnerRequired');
        bad=state; bad.SharedReceivedGrantControls={};
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(bad,item,control), ...
            'sixgr:truth:ReceivedULPreparationControlMismatch');
        wrong=control; wrong.Allowed=false;
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(state,item,wrong), ...
            'sixgr:truth:ReceivedULPreparationAdmissionRequired');
        wrong=control; wrong.Grant.RNTI=wrong.Grant.RNTI+1;
        bad=state; bad.SharedReceivedGrantControls={wrong};
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(bad,item,wrong), ...
            'sixgr:truth:ReceivedPDCCHGrantIdentityMismatch');
        wrong=control; wrong.Grant.ServingCell=2;
        wrongItem=item; wrongItem.Context.Grant.ServingCell=2;
        bad=state; bad.SharedReceivedGrantControls={wrong};
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(bad,wrongItem,wrong), ...
            'sixgr:truth:ReceivedULPreparationIdentityMismatch');
        wrong=control; wrong.Grant.MCSIndex=wrong.Grant.MCSIndex+1;
        bad=state; bad.SharedReceivedGrantControls={wrong};
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(bad,item,wrong), ...
            'sixgr:truth:ReceivedULPreparationGrantOperandsChanged');
        wrong=control; wrong.Grant.PRBSet=wrong.Grant.PRBSet+1;
        bad=state; bad.SharedReceivedGrantControls={wrong};
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(bad,item,wrong), ...
            'sixgr:truth:ReceivedULPreparationGrantOperandsChanged');
        % Deliberately malformed nested operand fixture, rejected before any
        % PHY consumer: this checks deep preservation, not freeze validity.
        wrongItem=item;
        wrongItem.Context.Grant.PHYGrant=struct('DeclaredOperandFixture',true, ...
            'PrecodingMatrix',[1;0]);
        wrong=control; wrong.Grant.PHYGrant=wrongItem.Context.Grant.PHYGrant;
        wrong.Grant.PHYGrant.PrecodingMatrix=[0;1];
        bad=state; bad.SharedReceivedGrantControls={wrong};
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(bad,wrongItem,wrong), ...
            'sixgr:truth:ReceivedULPreparationGrantOperandsChanged');
        wrong=control; wrong.ReceivedAssignment.MCS=wrong.ReceivedAssignment.MCS+1;
        bad=state; bad.SharedReceivedGrantControls={wrong};
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(bad,item,wrong), ...
            'sixgr:phy:pdcch:ReceivedAssignmentDigestMismatch');
        wrong=control; wrong.AvailableAtSample=before+1;
        bad=state; bad.SharedReceivedGrantControls={wrong};
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(bad,item,wrong), ...
            'sixgr:truth:ReceivedULPreparationClockMismatch');
        wrongItem=item; wrongItem.Planes.ReceiverID="ue_2_rx:post_rf";
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(state,wrongItem,control), ...
            'sixgr:truth:ReceivedULPreparationEndpointMismatch');
        wrongItem=item;
        p=item.Planes.Observation;
        wrongItem.Planes.Observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
            p.StartSample,p.EndSampleExclusive,p.SampleRateHz,p.NumReceiveAntennas);
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(state,wrongItem,control), ...
            'sixgr:truth:ReceivedULPreparationClockMismatch');
        bad=state; bad.ConnectedULTimingByUE={[]};
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(bad,item,control), ...
            'sixgr:link:MissingConnectedULTiming');
        bad=state; bad.ConnectedULTimingByUE{1}.TimeAlignmentExpirySampleExclusive=before;
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(bad,item,control), ...
            'sixgr:link:ConnectedULAfterTAExpiry');
        assert(owner.Events.NextSampleIndex==before && isempty(owner.DataTransmissions) && ...
            isempty(state.ULGrantTraceTable) && numel(state.SharedPendingULGrants)==1);
        state=sixgr.truth.queueReceivedULGrantPreparation(state,item,control);
        localReject(@()sixgr.truth.queueReceivedULGrantPreparation(state,item,control), ...
            'sixgr:truth:DuplicateReceivedULGrant');
        state.TestReceivedULNegativeCount=15;
        state.TestReceivedULAcceptedGrant=g;
        assert(owner.Events.NextSampleIndex==before && height(state.ULGrantTraceTable)==1);
        pending=state.SharedPendingULGrants;
        assert(numel(pending)==2 && pending(1).PriorCalendarMetadata=="retain_me" && ...
            isempty(pending(2).PriorCalendarMetadata) && ...
            string(pending(2).GrantContextId)==string(g.GrantContextId));
    else
        c=event.Context; g=state.TestReceivedULAcceptedGrant;
        assert(isequaln(c.Grant,g) && c.Key==state.TestReceivedULItem.Context.Key);
        cfg=c.PreparationConfig;
        assert(isequaln(cfg.SharedULTimingContext,state.ConnectedULTimingByUE{1}) && ...
            cfg.lls6g.runtime.AbsoluteSlotIndex0==g.Slot-1);
        carrier=sixgr.phy.grid.makeCarrier(cfg); fs=owner.SampleRateHz;
        first=sixgr.phy.frame.slotStartSample(carrier,g.Slot-1,fs);
        stop=sixgr.phy.frame.slotStartSample(carrier,g.Slot,fs);
        timing=sixgr.link.resolveConnectedULTransmissionTiming(cfg,first/fs,fs,stop-first);
        assert(owner.Events.NextSampleIndex==min(timing.TransmitStartSample,timing.ReceiveStartSample) && ...
            owner.Events.NextSampleIndex>=state.SharedReceivedGrantControls{1}.AvailableAtSample);
        state.TestReceivedULPreparationCount=state.TestReceivedULPreparationCount+1;
    end
end
end

function [control0,tdra]=localOccasion(cfg,rows)
control0=NaN; tdra=[];
for candidate=0:19
    [dl,~,~,controlPartition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,candidate+1);
    if ~dl || controlPartition.DLSymbolAllocation(1)~=0, continue; end
    for row=rows.'
        % The isolated decoder consumes a whole control slot in this test.
        if row(4)<2, continue; end
        [~,ul,~,dataPartition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,candidate+row(4)+1);
        allocation=dataPartition.ULSymbolAllocation;
        if ul && row(2)>=allocation(1) && sum(row(2:3))<=sum(allocation)
            control0=candidate; tdra=row.'; return;
        end
    end
end
error('test:MissingInstalledULHandoffOccasion','No legal installed DCI/PUSCH pair in the bounded calendar.');
end

function b=localBuffer(first,x,fs)
b=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(x,1),fs,size(x,2));
b.append(sixgr.phy.waveform.WaveformChunk(x,first),fs);
end

function h=localHash(value)
h=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(orderfields(value)),'UTF-8'))));
end

function localReject(call,id)
try, call(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingError','Expected %s.',id);
end
