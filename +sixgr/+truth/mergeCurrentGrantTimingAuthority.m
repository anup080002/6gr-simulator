function merged = mergeCurrentGrantTimingAuthority(merged, current)
% An immutable TB cache never owns a later transmission's control clock.
% Preserve coding/soft-buffer fields, but copy or invalidate EVERY timing
% alias together. Missing current authority is absent, not the old occasion.
assert(isstruct(merged) && isscalar(merged) && isstruct(current) && isscalar(current), ...
    'sixgr:truth:InvalidCurrentGrantTiming','Grant timing merge requires scalar structs.');
fields=["ControlAbsoluteSlot","ControlSlot","ControlFrame", ...
    "ScheduledAbsoluteSlot","HARQFeedbackAbsoluteSlot", ...
    "DataAbsoluteSlot","FeedbackAbsoluteSlot","K0","K1","K2","TimingDecision"];
for field=fields
    name=char(field);
    if isfield(current,name)
        merged.(name)=current.(name);
    elseif isfield(merged,name)
        if field=="TimingDecision"
            merged.(name)=struct();
        else
            merged.(name)=NaN;
        end
    end
end
end
