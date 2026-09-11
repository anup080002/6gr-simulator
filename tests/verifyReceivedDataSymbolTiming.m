function verifyReceivedDataSymbolTiming(completed,prepared,observation,arrival)
% Cross-check actual coded RX timing against this test's known sample delay.
% This verifier is not a production timing source or a hardware N1 model.
available=observation.EndSampleExclusive;
e=sixgr.truth.receivedDataSymbolTiming(prepared,observation,completed.ReceiveTiming,available);
carrier=prepared.Tx.Carrier;
info=nrOFDMInfo(carrier,'SampleRate',prepared.SampleRateHz,'Windowing',0);
n=double(carrier.SymbolsPerSlot);
base=mod(double(carrier.NSlot),double(carrier.SlotsPerSubframe))*n;
allocation=double(prepared.RequestBinding.Grant.SymbolAllocation);
lengths=double(info.SymbolLengths(base+(1:n)));
assert(e.AppliedTimingCorrectionSamples==arrival && ...
    e.ReceivedSymbolStartSample==observation.StartSample+arrival+sum(lengths(1:allocation(1))) && ...
    e.ReceivedSymbolEndSampleExclusive==observation.StartSample+arrival+sum(lengths(1:sum(allocation))));
assert(e.ResultAvailableAtSample==available && ~e.ProcessingBudgetIncluded);
harq=completed.HARQ; harq.ReceivedTimingEvidence=e;
assert(string(harq.GrantSnapshot.Direction)==prepared.Direction, ...
    'The executed HARQ snapshot must retain the actual transmitter direction.');
for name=["TimingDecision","K0","K1","K2","ControlAbsoluteSlot", ...
        "ScheduledAbsoluteSlot","HARQFeedbackAbsoluteSlot", ...
        "SchedulingCCID","ScheduledCCID","CarrierIndicator","SourceBWPID","TargetBWPID"]
    if isfield(prepared.RequestBinding.Grant,name)
        assert(isfield(harq.GrantSnapshot,name) && ...
            isequaln(harq.GrantSnapshot.(name),prepared.RequestBinding.Grant.(name)), ...
            'The completed HARQ snapshot lost or changed executed timing field %s.',name);
    end
end
fields=sixgr.truth.harqFeedbackReceiveTimingFields(harq,harq.GrantSnapshot,true);
assert(fields.DataReceiveSymbolEndSampleExclusive==e.ReceivedSymbolEndSampleExclusive && ...
    fields.DataDecodeAvailableAtSample==available);
file=[tempname '.csv']; writetable(struct2table(fields),file);
saved=readtable(file,'TextType','string');
assert(saved.DataDecodeAvailableAtSample==available && ...
    saved.DataReceiveSymbolEndSampleExclusive==e.ReceivedSymbolEndSampleExclusive);
decoded=jsondecode(saved.DataReceiveTimingEvidenceJSON);
assert(decoded.DataAbsoluteSlot==e.DataAbsoluteSlot && decoded.RNTI==e.RNTI && ...
    decoded.ReceivedSymbolEndSampleExclusive==e.ReceivedSymbolEndSampleExclusive);
if prepared.Direction=="DL"
    % Actual received DL timing, with a declared reservation identity. This
    % tests the ledger/availability boundary, not N1 or a HARQ codebook.
    feedback=fields; feedback.RNTI=e.RNTI; feedback.SourceSlot=e.DataAbsoluteSlot+1;
    feedback.PUCCHGrantId="received_dl_timing_component_reservation";
    feedback.UEIndex=1; feedback.HarqID=0; feedback.DueSlot=feedback.SourceSlot+2;
    feedback.Ack=logical(completed.TrialTable.CRCPass); feedback.Processed=false;
    sixgr.truth.assertHARQFeedbackAvailable(feedback,available,e.SampleRateHz);
    localReject(@()sixgr.truth.assertHARQFeedbackAvailable(feedback,available-1,e.SampleRateHz), ...
        'sixgr:truth:FutureHARQFeedbackAtUCIEncoding');
    localReject(@()sixgr.truth.assertHARQFeedbackAvailable(feedback,available,2*e.SampleRateHz), ...
        'sixgr:truth:InvalidUCIReceiveTiming');
    wrongFeedback=feedback; wrongFeedback.DataDecodeAvailableAtSample=available-1;
    localReject(@()sixgr.truth.assertHARQFeedbackAvailable(wrongFeedback,available,e.SampleRateHz), ...
        'sixgr:truth:InvalidUCIReceiveTiming');
    wrongFeedback=feedback; wrongFeedback.SourceSlot=feedback.SourceSlot+1;
    localReject(@()sixgr.truth.assertHARQFeedbackAvailable(wrongFeedback,available,e.SampleRateHz), ...
        'sixgr:truth:InvalidUCIReceiveTiming');
    wrongFeedback=rmfield(feedback,'DataReceiveTimingEvidenceJSON');
    localReject(@()sixgr.truth.assertHARQFeedbackAvailable(wrongFeedback,available,e.SampleRateHz), ...
        'sixgr:truth:MissingUCIReceiveTiming');
    ledger=struct('PendingFeedbackTable',struct2table(feedback));
    collected=sixgr.truth.CoupledTruthRuntime.pucchFeedbackDueHARQACKRuntime(ledger,feedback.DueSlot);
    assert(isscalar(collected));
    for name=string(fieldnames(fields)).'
        assert(isequaln(collected.(name),fields.(name)), ...
            'The UCI collector dropped receive timing field %s.',name);
    end
    sixgr.truth.assertHARQFeedbackAvailable(collected,available,e.SampleRateHz);
    fprintf('HARQ_FEEDBACK_RECEIVE_AVAILABILITY_PASS: actual DL capture, no future result authority.\n');
end
localReject(@()sixgr.truth.harqFeedbackReceiveTimingFields(completed.HARQ,harq.GrantSnapshot,true), ...
    'sixgr:truth:MissingSharedHARQReceiveTiming');
wrong=harq; wrong.ReceivedTimingEvidence.RNTI=e.RNTI+1;
localReject(@()sixgr.truth.harqFeedbackReceiveTimingFields(wrong,harq.GrantSnapshot,true), ...
    'sixgr:truth:SharedHARQReceiveTimingMismatch');
wrong=harq; wrong.ReceivedTimingEvidence.Direction="DL";
if prepared.Direction=="DL", wrong.ReceivedTimingEvidence.Direction="UL"; end
localReject(@()sixgr.truth.harqFeedbackReceiveTimingFields(wrong,harq.GrantSnapshot,true), ...
    'sixgr:truth:SharedHARQReceiveTimingMismatch');
wrong=harq; wrong.ReceivedTimingEvidence.DataAbsoluteSlot=e.DataAbsoluteSlot+1;
localReject(@()sixgr.truth.harqFeedbackReceiveTimingFields(wrong,harq.GrantSnapshot,true), ...
    'sixgr:truth:SharedHARQReceiveTimingMismatch');
for field=["OracleTimingUsed","ReceiverZeroPaddingUsed"]
    bad=completed.ReceiveTiming; bad.(field)=true;
    localReject(@()sixgr.truth.receivedDataSymbolTiming(prepared,observation,bad,available), ...
        'sixgr:truth:MeasuredDataTimingRequired');
end
localReject(@()sixgr.truth.receivedDataSymbolTiming(prepared,observation,completed.ReceiveTiming,available-1), ...
    'sixgr:truth:DataTimingOutsideReceivedEvent');
bad=completed.ReceiveTiming; bad.DemodulatedSampleCount=bad.DemodulatedSampleCount-1;
localReject(@()sixgr.truth.receivedDataSymbolTiming(prepared,observation,bad,available), ...
    'sixgr:truth:DataTimingDemodulationExtentMismatch');
fprintf('RECEIVED_DATA_SYMBOL_TIMING_PASS: %s start=%g end=%g available=%g\n', ...
    prepared.Direction,e.ReceivedSymbolStartSample,e.ReceivedSymbolEndSampleExclusive,available);
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Unexpected error: %s: %s',cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
