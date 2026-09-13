function ok=testReceivedDLHARQACKEvent(outputRoot)
% New real PDCCH receptions, actual retained PDSCH IQ replay and UE states.
% This is a protocol handoff component, not shared-clock PUCCH qualification.
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve previous evidence.');
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,tempname);
% Pre-calendar-repair captures have different RE/rate-matching maps. Keep
% that historical evidence unchanged; use the separately generated current
% calendar fixture, never pad/crop/reinterpret its symbols to fit a new map.
sourceRoot=fullfile('docs','lls','evidence_20260913','received_dl_harq_calendar_02');
mkdir(outputRoot); fprintf('RECEIVED_DL_HARQ_EVENT_OUTPUT=%s\n',outputRoot);
rows=table();
for k=1:4
    sourceFile=fullfile(sourceRoot,sprintf('attempt_%d.mat',k));
    saved=load(sourceFile);
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,saved.a.ControlAbsoluteSlot+1);
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
    definitions=sixgr.phy.pdcch.DCISchemaEngine.resolve(context).Definitions;
    fields=struct();
    for def=definitions(:).', fields.(def.Name)=saved.control.DecodedDCI.Fields.(def.Name); end
    fields.dai=k-1;
    packed=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
    tx=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',packed.Bits,'RNTI',cfg.phy.pdsch.RNTI);
    [control,info]=sixgr.phy.dl.PDCCH_Rx(tx.TransmitSamples,cfg,'SampleRate_Hz',tx.SampleRateHz);
    a=sixgr.phy.pdcch.materializeConnectedDCI(control,info,cfg);
    assert(a.Fields.dai==k-1 && a.PayloadHash==packed.PayloadHash);
    before=saved.before;
    wave=saved.delayed; if k==3, wave=[]; end
    [rx,decision,after,protocol]=before.receive(cfg,a,wave,'TimingSearchWindowSamples',[0 60]);
    if decision.ACK~=(k~=1) || decision.DecodeAttempted~=(k~=3)
        % Preserve and isolate unexpected decoder behavior before failing.
        % Changing only counter DAI must not change PDSCH decoding. Compare
        % the original received assignment using the same immutable state/IQ.
        [originalRX,originalDecision,originalAfter]=before.receive( ...
            cfg,saved.a,wave,'TimingSearchWindowSamples',[0 60]);
        save(fullfile(outputRoot,sprintf('unexpected_decode_%d.mat',k)), ...
            'sourceFile','control','info','a','decision','after','rx','protocol', ...
            'originalRX','originalDecision','originalAfter');
        fprintf('HARQ_EVENT_UNEXPECTED_DECODE sequence=%d saved_ack=%d original_replay_ack=%d changed_dai_ack=%d\n', ...
            k,saved.decision.ACK,originalDecision.ACK,decision.ACK);
    end
    assert(decision.ACK==(k~=1) && decision.DecodeAttempted==(k~=3), ...
        'test:ReceivedHARQEventUnexpectedDecode', ...
        'Retained actual waveform outcome changed; inspect preserved same-IQ original/DAI comparison.');
    if k==3
        assert(isempty(rx) && protocol.ACK && ~decision.DeliverTransportBlock);
    else
        assert(rx.CRCPass==decision.ACK && rx.CRCPass==saved.rx.CRCPass && ...
            numel(rx.LayerSymbols)==numel(saved.rx.LayerSymbols) && ...
            numel(rx.DescrambledLLR)==numel(saved.rx.DescrambledLLR), ...
            'test:ReceivedHARQEventCaptureDomainMismatch', ...
            'The retained waveform and current receiver must share the actual resource/rate-matching map.');
        if decision.ACK, assert(isequal(rx.TransportBlock,saved.bits)); end
    end
    event=sixgr.link.receivedDLHARQACKEvent(cfg,a,decision,after);
    e=event.Data;
    assert(e.DAI==k && e.CounterDAIRaw==k-1 && e.RNTI==a.RNTI && ...
        e.UEId==after.UEId && e.ServingCell==context.Data.ScheduledServingCell && ...
        e.TargetSlot==a.HARQFeedbackAbsoluteSlot+1 && e.Priority==0 && ...
        e.ReceivedAssignmentDigest==a.AssignmentDigest && ~e.FeedbackTransmissionQualified);
    carrier=sixgr.phy.grid.makeCarrier(cfg);
    expectedClock=a.ControlAbsoluteSlot*carrier.SymbolsPerSlot+ ...
        cfg.phy.pdcch.operatorControl.connected_monitoring.start_symbol;
    assert(e.EventIndex==expectedClock && e.MonitoringOccasionIndex==expectedClock && ...
        ~any(isfield(e,{'CRCPass','SINR_dB','EVM_pct','ExpectedTXBits'})));
    book=sixgr.phy.pucch.HARQACKCodebookBuilder.build('TYPE2_DYNAMIC',e,a.ConfigurationEpoch);
    assert(isequal(book.Bits,[zeros(k-1,1,'int8');int8(decision.ACK)]) && ...
        isequal(book.SourceEventIndex,[zeros(k-1,1);1]) && numel(book.Events)==1 && ...
        all(book.MissingAssignmentMask(1:k-1)) && ~any(book.DTXMask) && ...
        all(book.EventOrder(1:k-1)=="") && book.EventOrder(end)==e.PDSCHID);
    assert(sixgr.link.receivedDLHARQACKEvent(cfg,a,decision,after).Digest==event.Digest);

    bad=a; bad.Fields.dai=mod(k,4);
    localReject(@()sixgr.link.receivedDLHARQACKEvent(cfg,bad,decision,after), ...
        'sixgr:phy:pdcch:ReceivedAssignmentDigestMismatch');
    localReject(@()sixgr.link.receivedDLHARQACKEvent(cfg,a,decision,before), ...
        'sixgr:link:ReceivedHARQEventStateMismatch');
    localReject(@()sixgr.link.receivedDLHARQACKEvent(cfg,a,decision,struct()), ...
        'sixgr:link:ReceivedHARQEventStateRequired');
    bad=decision; bad.ACK=~bad.ACK;
    localReject(@()sixgr.link.receivedDLHARQACKEvent(cfg,a,bad,after), ...
        'sixgr:link:ReceivedHARQEventStateMismatch');
    bad=decision; bad.ACK=NaN;
    localReject(@()sixgr.link.receivedDLHARQACKEvent(cfg,a,bad,after), ...
        'sixgr:link:ReceivedHARQEventDecisionRequired');
    bad=decision; bad.Source="scheduler_expected_ack";
    localReject(@()sixgr.link.receivedDLHARQACKEvent(cfg,a,bad,after), ...
        'sixgr:link:ReceivedHARQEventDecisionRequired');
    bad=decision; bad.FeedbackTransmissionQualified=true;
    localReject(@()sixgr.link.receivedDLHARQACKEvent(cfg,a,bad,after), ...
        'sixgr:link:ReceivedHARQEventDecisionRequired');
    bad=decision; bad.ReceivedAssignmentDigest="wrong";
    localReject(@()sixgr.link.receivedDLHARQACKEvent(cfg,a,bad,after), ...
        'sixgr:link:ReceivedHARQEventDecisionRequired');
    bad=decision; bad.Attempt=bad.Attempt+1;
    localReject(@()sixgr.link.receivedDLHARQACKEvent(cfg,a,bad,after), ...
        'sixgr:link:ReceivedHARQEventStateMismatch');
    bad=decision; bad.DecodeAttempted=bad.AcknowledgedFromPriorDecode;
    localReject(@()sixgr.link.receivedDLHARQACKEvent(cfg,a,bad,after), ...
        'sixgr:link:ReceivedHARQEventDecisionRequired');
    bad=decision; bad.DeliverTransportBlock=~bad.DeliverTransportBlock;
    localReject(@()sixgr.link.receivedDLHARQACKEvent(cfg,a,bad,after), ...
        'sixgr:link:ReceivedHARQEventDecisionRequired');
    disabled=cfg; disabled.phy.harq.enable=false;
    localReject(@()sixgr.link.receivedDLHARQACKEvent(disabled,a,decision,after), ...
        'sixgr:link:ReceivedHARQEventStateRequired');

    save(fullfile(outputRoot,sprintf('received_event_%d.mat',k)), ...
        'sourceFile','control','info','a','decision','after','rx','protocol','event','book');
    rows=[rows;table(k,e.CounterDAIRaw,e.DAI,e.EventIndex,e.TargetSlot,decision.ACK, ...
        decision.DecodeAttempted,decision.DeliverTransportBlock,numel(book.Bits), ...
        sum(book.MissingAssignmentMask),string(event.Digest),string(book.Digest), ...
        'VariableNames',{'Sequence','ReceivedRawDAI','CounterDAI','MonitoringSymbolClock', ...
        'FeedbackSlot1Based','ACK','DecodeAttempted','DeliverTransportBlock', ...
        'CodebookBits','MissingAssignmentBits','EventDigest','CodebookDigest'})]; %#ok<AGROW>
    sixgr.util.csvWriteTable(fullfile(outputRoot,'received_harq_events.csv'),rows,'PreserveSchema',true);
    fprintf('RECEIVED_DL_HARQ_EVENT_PASS sequence=%d raw_dai=%d ack=%d decode=%d missing=%d\n', ...
        k,k-1,decision.ACK,decision.DecodeAttempted,k-1);
end
fprintf('RECEIVED_DL_HARQ_EVENT_ALL_PASS no_shared_feedback_qualification=1\n');
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
