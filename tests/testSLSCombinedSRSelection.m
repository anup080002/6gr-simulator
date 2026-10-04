function ok=testSLSCombinedSRSelection()
% Actual typed UCI planning with declared modeled-HARQ decision fixtures.
% Not received-control/PUCCH qualification or a statistical BLER population.
r=sixgr.config.loadSimulationRequest('simulator/configs/scenarios/sls_nr_tdd_21cell_connected.yaml');
cfg=sixgr.util.mergeStruct(r.Config,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/sls_combined_sr_selection.yaml'));
cfg.phy.csi.reportCSI=false;
for allowSelection=[false true]
    current=cfg;
    if ~allowSelection
        current.system.linkAbstraction.dynamicPUCCH.schedulingRequestMAC.positiveSRSelection='require_explicit_selection';
    end
    ledger=sixgr.system.SLSDynamicPUCCH(current); ledger.configureUEIdentities(4660);
    owners=cell(2,1);
    for id=0:1
        owners{id+1}=sixgr.system.SLSSchedulingRequestProcedure( ...
            struct('UEIndex',1,'RNTI',4660,'CellID',1,'SchedulingRequestID',id), ...
            struct('ProhibitTimerSlots',4,'MaxTransmissions',4));
        owners{id+1}.trigger(24,"owned_traffic_trigger_"+id);
    end
    ledger.installSRProcedures(owners);
    context=sixgr.phy.pdcch.DCIContext.fromLegacy(struct( ...
        'NSizeGrid',cfg.phy.carrier.NSizeGrid,'RNTIValue',4660),"1_0");
    schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context); fields=struct();
    for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
    fields.pucch_resource_indicator=0;
    dci=sixgr.phy.pdcch.DCIPacker.pack(fields,context); dci.ContextData=context.Data;
    bits=int8([1;0;1]);
    for k=1:3
        slot=24+k;
        g=struct('UEIndex',1,'RNTI',4660,'ControlAbsoluteSlot',slot, ...
            'ScheduledAbsoluteSlot',slot,'HARQFeedbackAbsoluteSlot',29,'DCI',dci, ...
            'PHYGrant',struct('IsFrozen',true,'CodingLayout',struct('NumCodewords',1)));
        ledger.appendDL(g,1,slot);
        tb="sr_selection_fixture_"+k;
        ctx=struct('Direction',"DL",'Grant',g,'ServingCellID',1,'TransportBlockIdentity',tb);
        ctx.Grant.TransportBlockIdentity=tb;
        result=struct('Ok',logical(bits(k)),'TransportBlockIdentity',tb, ...
            'TransmissionAbsoluteSlot0',slot,'ReceiveCompletionAbsoluteSlot0',slot, ...
            'SourceClassification',"development_fixture_not_study_result",'CalibrationQualified',false, ...
            'CalibrationSHA256',repmat('a',1,64),'CalibrationCurveID',"fixture_only", ...
            'CalibrationKeySHA256',repmat('b',1,64),'WaveformReplayExecuted',false,'PHYDecisionStatus',"OK");
        ledger.recordHARQDecision(ctx,result);
    end
    due=ledger.snapshot(28,29,1,struct([]));
    assert(isscalar(due) && due.HARQBits==3 && due.SRBits==2 && ...
        isequal(due.SRResourceConfigurationIDs,[1;2]));
    if ~allowSelection
        reject(@()ledger.completeSlot(29,1,struct([]),{},struct([])), ...
            'sixgr:system:MultiplePositiveSRsRequireSelection');
        assert(isempty(ledger.CompletionTrace) && all(cellfun(@(p)p.Counter==0,owners)));
        continue;
    end
    payload=ledger.srPayloadAtSlotStart(due,29);
    assert(isequal(payload.CandidatePositiveSchedulingRequestIDs,[0;1]) && ...
        payload.SelectedSRResourceConfigurationID==1 && payload.PositiveSchedulingRequestIDs==0);
    identity=cfg.phy.frame.DefaultIdentity;
    ue=struct('UEID',1,'RNTI',4660,'ServingCell',1,'PUCCHCell',1, ...
        'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
    frame=struct('TargetSlot',30,'PDSCHEndSlot',28,'K1',2,'K1Source',"decoded_dci", ...
        'PRIFieldWidth',3,'DecodedPRI',0,'SchedulingRequestStates',payload.ProcedureStates, ...
        'SelectedSRResourceConfigurationID',payload.SelectedSRResourceConfigurationID);
    harq=ledger.harqPayloadAtSlotStart(due,29); assert(harq.Available);
    plan=sixgr.phy.pucch.PUCCHConfigBuilder.planCombined(ledger.configForUE(ue),ue, ...
        harq.HARQACKBits,int8([]),int8([]),frame);
    wire=sixgr.phy.pucch.UCIReportSerializer.serialize(plan.Report);
    % Two configured opportunities retain two SR bits; selected resource ID1
    % is ordinal 1 => 01, not both positive requests or a two-bit bitmap.
    assert(isequal(wire.Sequence1.Bits,[bits;int8([0;1])]) && wire.InformationBitCount==5);
    prepared=ledger.preparePUCCHAtSlotStart(due,29,struct());
    assert(prepared.Available && ~prepared.NativeWaveformExecuted && ~prepared.PhysicalReceptionQualified && ...
        ~isfield(prepared.TransmitterPlan,'ReceiverContext'));
    composed=sixgr.phy.pucch.UCIReportSerializer.serialize(prepared.TransmitterPlan.Report);
    assert(isequal(composed.Sequence1.Bits,wire.Sequence1.Bits));
    changed=due; changed.ContextDigest="poisoned_receiver_layout_digest";
    repeated=ledger.preparePUCCHAtSlotStart(changed,29,struct());
    assert(repeated.TransmitterPlan.Plan.Digest==prepared.TransmitterPlan.Plan.Digest, ...
        'The gNB layout digest must not determine transmitted fields.');
    assert(all(cellfun(@(p)p.Counter==0,owners)),'Planning must not advance a transmission counter.');
    ledger.completeSlot(29,1,struct([]),{},struct([]));
    assert(owners{1}.Counter==1 && owners{2}.Counter==0 && owners{1}.Pending && owners{2}.Pending);
    row=ledger.CompletionTrace;
    assert(height(row)==1 && row.PositiveSRCount==1 && row.SelectedSRResourceConfigurationID==1 && ...
        row.SRSelectionPolicy=="lowest_scheduling_request_resource_id" && ~row.WaveformBacked);
end
fprintf('SLS_COMBINED_SR_SELECTION_PASS exact_ordinal=1 only_selected_counter=1 unselected_pending=1\n');
ok=true;
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
