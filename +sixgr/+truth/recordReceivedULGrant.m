function state=recordReceivedULGrant(state,grant)
% Publish the exact decoded/admitted UL grant before future physical TX.
% This reducer does not reserve bytes, count a HARQ attempt, or invent TBS.
assert(upper(string(sixgr.util.structGet(grant,'Direction',"")))=="UL", ...
    'sixgr:truth:ReceivedULGrantRequired','Expected an uplink grant.');
for field=["ControlDecodeOk","PDCCHGrantBindingOk"]
    flag=sixgr.util.structGet(grant,field,false);
    assert((isnumeric(flag)||islogical(flag)) && isscalar(flag) && isequal(double(flag),1), ...
        'sixgr:truth:ReceivedULGrantRequired', ...
        'A queued or unbound DCI is not authority for a received UL grant trace.');
end
id=string(sixgr.util.structGet(grant,'GrantContextId',""));
assert(isscalar(id) && ~ismissing(id) && strlength(strtrim(id))>0, ...
    'sixgr:truth:ReceivedULGrantIdentityRequired','Retain the exact received grant identity.');
ue=double(sixgr.util.structGet(grant,'UEIndex',NaN));
validateattributes(ue,{'double'},{'scalar','integer','positive','<=',state.NumUsers});
traces=state.ULGrantTraceTable;
if ~isempty(traces)
    assert(~any(string(traces.GrantContextId)==id), ...
        'sixgr:truth:DuplicateReceivedULGrant','One received UL grant must be published once.');
end
feedback=sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirectionRuntime(state,ue,"UL");
state=sixgr.truth.CoupledTruthRuntime.appendGrantTraceRuntime(state,grant,"UL",feedback);
end
