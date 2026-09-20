function state=storeReceivedULTimingReference(state,ue,reference)
% Preserve measured pilot clocks for observations overlapping later pilots.
validateattributes(ue,{'numeric'},{'scalar','integer','positive','<=',state.NumUsers});
assert(isa(reference,'sixgr.phy.sync.ReceivedULTimingReference') && isscalar(reference), ...
    'sixgr:truth:InvalidReceivedULTimingReference','Retain only a measured, validated UL pilot clock.');
latest=sixgr.util.structGet(state,'ReceivedULTimingReferences',cell(state.NumUsers,1));
history=sixgr.util.structGet(state,'ReceivedULTimingHistory',cell(state.NumUsers,1));
if isempty(history{ue}) && ~isempty(latest{ue})
    history{ue}={latest{ue}};
end
if ~isempty(history{ue})
    previous=history{ue}{end};
    assert(reference.AvailableAtSample>=previous.AvailableAtSample, ...
        'sixgr:truth:OutOfOrderULTimingReference','Pilot clocks must be retained in receiver-completion order.');
    if isequaln(previous,reference), return; end
end
entries=history{ue};
if isempty(entries), entries={}; end
entries{end+1}=reference;
history{ue}=entries;
latest{ue}=reference;
state.ReceivedULTimingReferences=latest;
state.ReceivedULTimingHistory=history;
end
