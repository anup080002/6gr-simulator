function ok=testPDCCHReceivedGrantClock()
% Reducer fixture: these explicit input rows are NOT waveform evidence.
% Actual PDCCH generation/reception is covered by the physical-queue test.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_pdcch_shared_queue_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
base=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
base.CurrentSlot=4; base.CurrentCanonicalSlot=4; base.CurrentFrame=1;
base.CurrentServingIdx(:)=1;
for direction=["DL","UL"]
    grant=struct('UEIndex',1,'RNTI',1,'Direction',direction,'Slot',5, ...
        'Frame',1,'ControlSlot',4,'ControlAbsoluteSlot',3, ...
        'PDCCHGrantBindingRequired',true,'PDCCHGrantBindingOk',true);
    row=table(4,1,"PASS",true,true,true,true,false,false, ...
        'VariableNames',{'Slot','Frame','Status','CRCPass','DCICrcPass', ...
        'PDCCHPayloadMatch','PDCCHCausalGrantDecodeOk','PDCCHFalseAlarm','PDCCHMissedDetection'});
    [state,received,allowed]=sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial(base,grant,direction,row);
    assert(allowed && received.ControlDecodeOk && received.Slot==5);
    % Unit-only reducer evidence. Exercise the same late-control boundary
    % used by production data completion without claiming a PHY decode.
    received.PDCCHGrantDCIFieldsHash=string(repmat('a',1,64));
    received.PDCCHGrantFieldsHash=received.PDCCHGrantDCIFieldsHash;
    preparedGrant=grant;
    preparedGrant.TBSBits=984;
    preparedGrant.PrecodingMatrix=[1;1]/sqrt(2);
    for evidenceField=["ControlDecodeOk","DCICrcPass","PDCCHPayloadMatch", ...
            "PDCCHCausalGrantDecodeOk","PDCCHGrantBindingRequired","PDCCHGrantBindingOk"]
        preparedGrant.(evidenceField)=false;
    end
    bound=sixgr.truth.bindReceivedPDCCHGrantEvidence(preparedGrant,received);
    assert(bound.DCICrcPass && bound.PDCCHPayloadMatch && ...
        bound.PDCCHCausalGrantDecodeOk && bound.PDCCHGrantBindingRequired && ...
        bound.PDCCHGrantBindingOk && bound.TBSBits==984 && ...
        isequal(bound.PrecodingMatrix,preparedGrant.PrecodingMatrix));
    before=sixgr.link.PreparedDataTransmission.requestBinding(struct(),preparedGrant,struct());
    after=sixgr.link.PreparedDataTransmission.requestBinding(struct(),bound,struct());
    assert(isequaln(before,after), ...
        'Late control evidence must not change the immutable prepared-data request.');
    wrong=received; wrong.RNTI=received.RNTI+1;
    localReject(@()sixgr.truth.bindReceivedPDCCHGrantEvidence(preparedGrant,wrong), ...
        'sixgr:truth:ReceivedPDCCHGrantIdentityMismatch');
    wrong=received; wrong.PDCCHPayloadMatch=false;
    localReject(@()sixgr.truth.bindReceivedPDCCHGrantEvidence(preparedGrant,wrong), ...
        'sixgr:truth:IncompleteReceivedPDCCHGrantEvidence');
    wrong=rmfield(received,'DCICrcPass');
    localReject(@()sixgr.truth.bindReceivedPDCCHGrantEvidence(preparedGrant,wrong), ...
        'sixgr:truth:IncompleteReceivedPDCCHGrantEvidence');
    wrong=received; wrong.PDCCHGrantFieldsHash=string(repmat('b',1,64));
    localReject(@()sixgr.truth.bindReceivedPDCCHGrantEvidence(preparedGrant,wrong), ...
        'sixgr:truth:IncompleteReceivedPDCCHGrantEvidence');
    if direction=="UL"
        % Explicit grant fixture: do not reconstruct this TBS from throughput.
        received.GrantContextId="fixture_received_ul_slot5";
        received.TBSBits=984; received.TBSBytes=123;
        queue=state.ULQueueBits; txCount=state.ULHarq.Stats.Tx;
        traced=sixgr.truth.recordReceivedULGrant(state,received);
        t=traced.ULGrantTraceTable;
        assert(height(t)==1 && t.Slot==5 && t.TBSBits==984 && t.TBSBytes==123 && ...
            string(t.GrantContextId)==received.GrantContextId && t.ControlDecodeOk && ...
            isempty(sixgr.util.structGet(traced,'SharedDataTXLedger',{})) && ...
            isequal(traced.ULQueueBits,queue) && ...
            traced.ULHarq.Stats.Tx==txCount);
        localReject(@()sixgr.truth.recordReceivedULGrant(traced,received), ...
            'sixgr:truth:DuplicateReceivedULGrant');
        unreceived=received; unreceived.ControlDecodeOk=false;
        localReject(@()sixgr.truth.recordReceivedULGrant(state,unreceived), ...
            'sixgr:truth:ReceivedULGrantRequired');
    end
    assert(state.LastSuccessfulPDCCHSlotByUE(1)==4, ...
        'Decoded control history must not claim the future scheduled data slot.');
    events=state.InitialAccessLifecycleTraceTable;
    hit=string(events.EventName)=="PDCCH_DCI_DECODED";
    assert(nnz(hit)==1 && events.CanonicalSlot(hit)==4);
    late=base; late.CurrentSlot=5; late.CurrentCanonicalSlot=5;
    [late,~,allowed]=sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial(late,grant,direction,row);
    assert(allowed && late.LastSuccessfulPDCCHSlotByUE(1)==4);
    bad=row; bad.Slot=5;
    localReject(@()sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial(base,grant,direction,bad), ...
        'sixgr:truth:PDCCHControlSlotMismatch');
    future=grant; future.ControlSlot=6; future.ControlAbsoluteSlot=5; future.Slot=7;
    bad.Slot=6;
    localReject(@()sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial(base,future,direction,bad), ...
        'sixgr:truth:FuturePDCCHReception');
    for invalidUE=[NaN 0 2 1.5]
        invalid=grant; invalid.UEIndex=invalidUE;
        localReject(@()sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial(base,invalid,direction,row), ...
            'sixgr:truth:InvalidPDCCHGrantUE');
    end
end
ok=true; disp('PDCCH_RECEIVED_GRANT_CLOCK_PASS');
end

function localReject(call,id)
try, call(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s.',id,cause.identifier);
    return;
end
error('test:MissingError','Expected %s.',id);
end
