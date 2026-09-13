function [next,entry]=nextScheduledType2DAI(ledger,assignment)
% Candidate gNB counter for ordinary single-cell, scalar-TB Type-2 feedback.
% TS 38.213 18.8.0 9.1.3.1/Table 9.1.3-1: on-wire 00/01/10/11 -> 1/2/3/4.
% Pure transaction: publish NEXT only after the associated PDCCH is accepted
% by the physical queue (or actually executed by the nonshared path). No UE
% decode status, payload or ACK/NACK belongs in this scheduled counter.
required={'GrantID','RNTI','PhysicalServingCell','ScheduledCCID', ...
    'FeedbackAbsoluteSlot','ControlAbsoluteSlot','ControlStartSymbol','ConfigurationEpoch'};
assert(isstruct(assignment) && isscalar(assignment) && ...
    all(isfield(assignment,required)) && isempty(setdiff(fieldnames(assignment),required)), ...
    'sixgr:truth:InvalidDAIAssignment','Use only explicit scheduled assignment identity.');
for field=required(2:end)
    if strcmp(field{1},'ScheduledCCID'), continue; end
    validateattributes(assignment.(field{1}),{'numeric'}, ...
        {'scalar','real','finite','integer','nonnegative'});
    assignment.(field{1})=double(assignment.(field{1}));
end
for field={'GrantID','ScheduledCCID'}
    value=string(assignment.(field{1}));
    assert(isscalar(value) && ~ismissing(value) && strlength(strtrim(value))>0, ...
        'sixgr:truth:InvalidDAIAssignment','Scheduled identity must not be blank.');
    assignment.(field{1})=value;
end
assert(assignment.FeedbackAbsoluteSlot>=assignment.ControlAbsoluteSlot, ...
    'sixgr:truth:InvalidDAIAssignment','Feedback cannot precede its control occasion.');
if isempty(ledger) || (isstruct(ledger) && isscalar(ledger) && isempty(fieldnames(ledger)))
    ledger=struct('Version',1,'LastControlAbsoluteSlot',-1,'Entries',struct([]));
end
assert(isstruct(ledger) && isscalar(ledger) && isfield(ledger,'Version') && ledger.Version==1 && ...
    isfield(ledger,'Entries') && isstruct(ledger.Entries) && isfield(ledger,'LastControlAbsoluteSlot'), ...
    'sixgr:truth:InvalidDAILedger','Use a versioned scheduled DAI ledger.');
digest=sixgr.phy.pucch.PUCCHUtil.hash(assignment);
entries=ledger.Entries;
if ~isempty(entries)
    same=arrayfun(@(e)e.Assignment.GrantID==assignment.GrantID && ...
        e.Assignment.ControlAbsoluteSlot==assignment.ControlAbsoluteSlot,entries);
    if any(same)
        assert(nnz(same)==1 && entries(same).AssignmentDigest==digest, ...
            'sixgr:truth:ChangedDAIAssignment','A retained DCI assignment cannot change identity.');
        entry=entries(same); next=ledger; return; % Repacking is idempotent.
    end
end
assert(assignment.ControlAbsoluteSlot>=ledger.LastControlAbsoluteSlot, ...
    'sixgr:truth:OutOfOrderDAIAssignment','New control assignments require chronological scheduling.');
% Expired feedback groups are not needed by future scheduling. Historical
% replay uses retained packed DCI rather than mutating this live ledger.
if ~isempty(entries)
    entries=entries(arrayfun(@(e)e.Assignment.FeedbackAbsoluteSlot>=assignment.ControlAbsoluteSlot,entries));
end
ordinal=1;
if ~isempty(entries)
    sameGroup=arrayfun(@(e)e.Assignment.RNTI==assignment.RNTI && ...
        e.Assignment.PhysicalServingCell==assignment.PhysicalServingCell && ...
        e.Assignment.ScheduledCCID==assignment.ScheduledCCID && ...
        e.Assignment.ConfigurationEpoch==assignment.ConfigurationEpoch && ...
        e.Assignment.FeedbackAbsoluteSlot==assignment.FeedbackAbsoluteSlot,entries);
    group=entries(sameGroup);
    if ~isempty(group)
        previous=group(end).Assignment;
        assert(assignment.ControlAbsoluteSlot>previous.ControlAbsoluteSlot || ...
            (assignment.ControlAbsoluteSlot==previous.ControlAbsoluteSlot && ...
             assignment.ControlStartSymbol>previous.ControlStartSymbol), ...
            'sixgr:truth:UnsupportedDAIMonitoringPair', ...
            'This single-cell profile permits one scalar-TB assignment per monitoring occasion.');
        ordinal=group(end).Ordinal+1;
    end
end
entry=struct('Assignment',assignment,'AssignmentDigest',digest, ...
    'Ordinal',ordinal,'CounterDAI',mod(ordinal-1,4)+1,'RawDAI',mod(ordinal-1,4), ...
    'Source',"gnb_scheduled_type2_counter_not_ue_reception");
if isempty(entries), entries=entry; else, entries(end+1)=entry; end
next=struct('Version',1,'LastControlAbsoluteSlot',assignment.ControlAbsoluteSlot,'Entries',entries);
end
