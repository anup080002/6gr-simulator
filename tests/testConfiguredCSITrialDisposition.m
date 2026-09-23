function ok=testConfiguredCSITrialDisposition()
% Metadata reducer test, not physical PUCCH or detector qualification.
[trials,report]=fixture();
before=trials;
out=sixgr.truth.bindConfiguredCSITrialDisposition(trials,report);
assert(all(out.RuntimeStateUpdated==[true;false]) && ...
    all(out.ControlStateChanged==[true;false]) && ...
    all(out.StateChangeApplied==[true;false]));
assert(out.CSIReportStateChangeApplied(1)==1 && isnan(out.CSIReportStateChangeApplied(2)));
for field=setdiff(string(before.Properties.VariableNames), ...
        ["RuntimeStateUpdated","ControlStateChanged","StateChangeApplied"])
    assert(isequaln(out.(field),before.(field)), ...
        'Disposition must not change receiver/TX evidence: %s.',field);
end
assert(isequaln(trials,before) && ~out.SuccessFlag(1) && ...
    out.PUCCHTransmissionPrepared(1)==0 && out.ReceiverOnlyAssignment(1)==1);
assert(isequaln(out,sixgr.truth.bindConfiguredCSITrialDisposition(out,report)));
for status=["receiver_csi_unavailable_not_delivered","stale_received_csi_ignored"]
    report.DeliveryStatus=status;
    report.CSIUCIDecodeOk=status=="stale_received_csi_ignored";
    % Old decode-based flags must be replaced by the actual CSI disposition,
    % not preserved via OR for an occasion with no HARQ state to retain.
    rejected=sixgr.truth.bindConfiguredCSITrialDisposition(out,report);
    assert(rejected.RuntimeStateUpdated(1) && ~rejected.StateChangeApplied(1) && ...
        ~rejected.ControlStateChanged(1) && rejected.CSIReportStateChangeApplied(1)==0);
end
[trials,report]=fixture();
alias=trials; alias.BaseStationID=alias.ServingCell; alias.ServingCell(:)=NaN;
assert(sixgr.truth.bindConfiguredCSITrialDisposition(alias,report).StateChangeApplied(1));
for name=["RNTI","UEIndex","DueSlot","ServingCell"]
    bad=report; bad.(name)=99;
    reject(@()sixgr.truth.bindConfiguredCSITrialDisposition(trials,bad), ...
        'sixgr:truth:CSITrialDispositionIdentity');
end
bad=report; bad.ReceiverContextDigest="";
reject(@()sixgr.truth.bindConfiguredCSITrialDisposition(trials,bad), ...
    'sixgr:truth:CSITrialDispositionIdentity');
reject(@()sixgr.truth.bindConfiguredCSITrialDisposition([trials;trials(1,:)],report), ...
    'sixgr:truth:CSITrialDispositionIdentity');
bad=trials; bad.ReceiverExpectedHARQBitCount(1)=3;
reject(@()sixgr.truth.bindConfiguredCSITrialDisposition(bad,report), ...
    'sixgr:truth:CSITrialDispositionRequiresCSIOnly');
bad=report; bad.Processed=false;
reject(@()sixgr.truth.bindConfiguredCSITrialDisposition(trials,bad), ...
    'sixgr:truth:CSITrialDispositionNotCompleted');
bad=report; bad.CSIUCIDecodeOk=false;
reject(@()sixgr.truth.bindConfiguredCSITrialDisposition(trials,bad), ...
    'sixgr:truth:CSITrialDispositionInvalidDelivery');
bad=trials; bad.BaseStationID=[2;1];
reject(@()sixgr.truth.bindConfiguredCSITrialDisposition(bad,report), ...
    'sixgr:truth:CSITrialDispositionIdentity');
fprintf('CONFIGURED_CSI_TRIAL_DISPOSITION_PASS metadata_only=1 physical_qualification=0\n');
ok=true;
end

function [T,r]=fixture()
T=table([24;29],[1;1],[7;7],[1;1],["context24";"context29"], ...
    [0;0],false(2,1),false(2,1),false(2,1),false(2,1),ones(2,1),zeros(2,1), ...
    ["10110110100";""], ...
    'VariableNames',{'Slot','UEIndex','RNTI','ServingCell','ReceiverContextDigest', ...
    'ReceiverExpectedHARQBitCount','RuntimeStateUpdated','ControlStateChanged', ...
    'StateChangeApplied','SuccessFlag','ReceiverOnlyAssignment','PUCCHTransmissionPrepared', ...
    'UCIDecodedBitVector'});
r=struct('UEIndex',1,'RNTI',7,'ServingCell',1,'DueSlot',24, ...
    'ReceiverContextDigest',"context24",'Processed',true,'CSIUCIChannel',"PUCCH", ...
    'CSIUCIDecodeOk',true,'DeliveryStatus',"delivered_to_runtime_scheduler");
end

function reject(action,id)
try
    action();
catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s.',id,err.identifier); return;
end
error('test:MissingRejection','Expected %s.',id);
end
