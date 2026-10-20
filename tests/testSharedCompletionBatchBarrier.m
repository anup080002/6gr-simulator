function ok=testSharedCompletionBatchBarrier()
% Explicit bookkeeping fixture, NOT a received waveform/performance claim.
% The physical companion test is testSharedSeparatePUCCHPUSCH.
row=struct('ScheduledAbsoluteSlot',50,'UEIndex',1,'RNTI',4660, ...
    'ServingCell',1,'ComponentCarrier',0,'ActiveULBWP',0, ...
    'FeedbackForDirection',"DL",'SourceSlot',49,'HarqID',0, ...
    'UCIType',"harq_ack",'PUCCHGrantId',"frozen_feedback_49_to_50", ...
    'GrantExecutedFlag',false,'MultiplexedOnPUSCH',false,'RightCensored',false);
state=struct('CfgMobility',struct(),'CurrentSlot',50, ...
    'PUCCHGrantTraceTable',struct2table(row), ...
    'SharedWaveformStream',struct('Pending', ...
        struct('Kind',{},'Context',{}),'Events',struct('NextSampleIndex',3072000)), ...
    'Reduced',strings(0,1),'PilotReady',false);
state.SharedArmedPUCCHOccasions=sixgr.truth.CoupledTruthRuntime.sharedPUCCHOccasionKey( ...
    state.PUCCHGrantTraceTable);
kinds=["PUCCH","PUSCH","SRS","DataTX"];
items=struct('Kind',cellstr(kinds),'ID',cellstr("completed_"+kinds));
% This is the failing production boundary: captures are no longer Pending,
% but the coincident PUCCH result has not yet disposed its frozen grant.
localReject(@()sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state), ...
    'sixgr:truth:LateSharedPUCCHFeedback');
result=sixgr.truth.completeSharedReceiverBatch(state,items,@reduce);
assert(isequal(result.Reduced,["DataTX";"SRS";"PUSCH";"PUCCH"]) && ...
    result.PUCCHGrantTraceTable.GrantExecutedFlag && ...
    result.SharedWaveformStream.Events.NextSampleIndex==3072000 && ...
    isempty(result.SharedWaveformStream.Pending));
% Removing the required PUCCH result must NOT turn the same late obligation
% into a successful/ignored disposition.
localReject(@()sixgr.truth.completeSharedReceiverBatch(state,items(2:end),@reduce), ...
    'sixgr:truth:LateSharedPUCCHFeedback');
% A new obligation injected after the frozen occasion remains an error.
localReject(@()sixgr.truth.completeSharedReceiverBatch(state,items,@reduceWithLateGrant), ...
    'sixgr:truth:LateSharedPUCCHFeedback');
% An actual receiver exception is preserved, not caught and labelled a pass.
localReject(@()sixgr.truth.completeSharedReceiverBatch(state,items,@crash), ...
    'test:ActualReceiverFailed');
assert(isequaln(state,sixgr.truth.completeSharedReceiverBatch(state,items([]),@reduce)));
fprintf('SHARED_COMPLETION_BATCH_BARRIER_PASS late_missing_and_crash_rejected=1 clock_unchanged=1\n');
ok=true;
end

function state=reduce(state,item)
state.Reduced(end+1,1)=string(item.Kind);
if item.Kind=="SRS", state.PilotReady=true; end
if item.Kind=="PUSCH"
    assert(state.PilotReady && ~state.PUCCHGrantTraceTable.GrantExecutedFlag);
end
if item.Kind=="PUCCH"
    assert(state.PilotReady && any(state.Reduced=="PUSCH"));
    state.PUCCHGrantTraceTable.GrantExecutedFlag=true;
end
end

function state=reduceWithLateGrant(state,item)
state=reduce(state,item);
if item.Kind=="PUCCH"
    late=state.PUCCHGrantTraceTable;
    late.PUCCHGrantId="new_unencoded_late_obligation";
    late.GrantExecutedFlag=false;
    state.PUCCHGrantTraceTable=[state.PUCCHGrantTraceTable;late];
end
end

function state=crash(state,item) %#ok<INUSD>
error('test:ActualReceiverFailed','Do not hide failed receiver completion.');
end

function localReject(action,identifier)
try
    action();
catch cause
    assert(string(cause.identifier)==identifier,'%s',getReport(cause));
    return;
end
error('test:ExpectedFailure','Expected %s.',identifier);
end
