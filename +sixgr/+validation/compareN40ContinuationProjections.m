function checks=compareN40ContinuationProjections(a,b)
% Exact comparison of declared checkpoint projections, not a PHY execution.
required=["CompletedSlot","ConfigHash","RNG","PendingULGrants", ...
    "DLTrials","ULTrials","SlotTraceTable","SchedulerDecisionTable", ...
    "DLGrantTraceTable","ULGrantTraceTable","HARQTimelineTable", ...
    "PhysicalClock","PhysicalExecutionTrace","RFExecutionLedger"];
checks=table(strings(0,1),false(0,1),strings(0,1), ...
    'VariableNames',{'CheckID','Passed','Scope'});
for name=required
    present=isfield(a,name)&&isfield(b,name);
    equal=present && isequaln(a.(name),b.(name));
    if name=="CompletedSlot", equal=equal && isequal(a.(name),65); end
    if name=="PhysicalExecutionTrace", equal=equal && ~isempty(a.(name)); end
    checks(end+1,:)={name,equal,"exact_original_endpoint65_value_comparison"}; %#ok<AGROW>
end
% Require actual post-checkpoint slot population, not two empty projections.
covered=false;
if isfield(a,'SlotTraceTable')&&istable(a.SlotTraceTable)&& ...
        ismember('CanonicalSlot',a.SlotTraceTable.Properties.VariableNames)
    covered=all(ismember((61:65).',double(a.SlotTraceTable.CanonicalSlot)));
end
checks(end+1,:)={"Slots61Through65Covered",covered,"actual_runtime_slot_trace"};
end
