function T=appendRejectedULReceiveAudit(previous,row)
% Extend historical audit schema with UNKNOWN metadata, never reconstructed RX.
assert(istable(previous)&&isstruct(row)&&isscalar(row), ...
    'sixgr:truth:RejectedULAuditSchema','Require an original audit and one completed receiver row.');
current=struct2table(row,'AsArray',true);
if width(previous)==0, T=current; return; end
textFields=["PowerAdmissionObservationID","LogicalPUCCHGrantIdSet","UEProducerDisposition", ...
    "UEReceivedCodebookDigest","PhysicalOccasionID","SelectedGNBTransport", ...
    "ReceivedUCIObservationID","RunUUID","ConfigHash"];
numberFields=["BaseStationID","ComponentCarrier","ActiveULBWP","SweepPointIndex", ...
    "AdmissionDecisionSample","ClockEpoch","ReceiverClockEpoch","ReceiverInvocationCompleted"];
oldNames=string(previous.Properties.VariableNames); newNames=string(current.Properties.VariableNames);
missing=setdiff(newNames,oldNames,'stable');
assert(all(ismember(oldNames,newNames))&&all(ismember(missing,[textFields numberFields])), ...
    'sixgr:truth:RejectedULAuditSchema','Only the declared additive audit metadata may be schema-aligned.');
original=previous;
for field=missing
    if ismember(field,textFields), previous.(field)=strings(height(previous),1);
    else, previous.(field)=NaN(height(previous),1); end
end
assert(isequaln(previous(:,original.Properties.VariableNames),original), ...
    'sixgr:truth:RejectedULAuditChangedHistory','Historical observations must remain byte-value identical.');
if ismember('ReceiverInvocationCompleted',original.Properties.VariableNames) && ...
        islogical(original.ReceiverInvocationCompleted)
    assert(isscalar(current.ReceiverInvocationCompleted)&& ...
        any(current.ReceiverInvocationCompleted==[0 1]), ...
        'sixgr:truth:RejectedULAuditSchema','Do not coerce unavailable evidence to logical false.');
    current.ReceiverInvocationCompleted=logical(current.ReceiverInvocationCompleted);
end
T=[previous;current(:,previous.Properties.VariableNames)];
end
