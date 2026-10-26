function checks=compareN40ContinuationProjections(a,b,options)
% Exact comparison of declared checkpoint projections, not a PHY execution.
arguments
    a (1,1) struct
    b (1,1) struct
    options.StartSlot (1,1) double = NaN
    options.EndSlot (1,1) double = NaN
    options.CriteriaPath {mustBeTextScalar} = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), ...
        'simulator','configs','validation','n40_integration_gate.yaml')
end
startSlot=options.StartSlot; endSlot=options.EndSlot;
if isnan(startSlot)||isnan(endSlot)
    criteria=sixgr.lls6g.config.readConfigFile(options.CriteriaPath);
    if isnan(startSlot), startSlot=double(criteria.continuation_start_slot); end
    if isnan(endSlot), endSlot=double(criteria.completed_slots); end
end
assert(isfinite(startSlot)&&isfinite(endSlot)&&startSlot==fix(startSlot)&& ...
    endSlot==fix(endSlot)&&startSlot>0&&startSlot<endSlot, ...
    'sixgr:validation:ContinuationWindow','Require an increasing positive integer slot interval.');
required=["CompletedSlot","ConfigHash","RNG","PendingULGrants", ...
    "DLTrials","ULTrials","SlotTraceTable","SchedulerDecisionTable", ...
    "DLGrantTraceTable","ULGrantTraceTable","HARQTimelineTable", ...
    "PhysicalClock","PhysicalExecutionTrace","RFExecutionLedger","SchedulerMCSTransitionState"];
checks=table(strings(0,1),false(0,1),strings(0,1), ...
    'VariableNames',{'CheckID','Passed','Scope'});
for name=required
    present=isfield(a,name)&&isfield(b,name);
    equal=present && isequaln(a.(name),b.(name));
    if name=="CompletedSlot", equal=equal && isequal(a.(name),endSlot); end
    if name=="PhysicalExecutionTrace", equal=equal && ~isempty(a.(name)); end
    if name=="SchedulerMCSTransitionState"
        equal=equal && validSchedulerState(a.(name));
    end
    checks(end+1,:)={name,equal,"exact_original_endpoint_value_comparison"}; %#ok<AGROW>
end

% Require actual post-checkpoint slot population, not two empty projections.
covered=false;
if isfield(a,'SlotTraceTable')&&istable(a.SlotTraceTable)&& ...
        ismember('CanonicalSlot',a.SlotTraceTable.Properties.VariableNames)
    covered=all(ismember((startSlot+1:endSlot).',double(a.SlotTraceTable.CanonicalSlot)));
end
checks(end+1,:)={"Slots"+string(startSlot+1)+"Through"+string(endSlot)+"Covered",covered,"actual_runtime_slot_trace"};
end

function valid=validSchedulerState(value)
valid=isstruct(value)&&isscalar(value)&&all(isfield(value,{'DL','UL'}));
if ~valid, return; end
for direction=["DL","UL"]
    entries=value.(direction);
    valid=iscell(entries)&&~isempty(entries);
    if ~valid, return; end
    for k=1:numel(entries)
        entry=entries{k};
        valid=isstruct(entry)&&isscalar(entry)&&all(isfield(entry,{'SchedulerClass','State'}))&& ...
            strlength(string(entry.SchedulerClass))>0&&isstruct(entry.State)&& ...
            isscalar(entry.State)&&isfield(entry.State,'Entries')&&iscell(entry.State.Entries);
        if ~valid, return; end
    end
end
end
