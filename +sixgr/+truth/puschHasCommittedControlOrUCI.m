function tf = puschHasCommittedControlOrUCI(state,grant)
% A received DCI or a live UCI reservation cannot be erased by SRS priority.
% This is an ownership check, not receiver evidence or a cancellation DCI.
tf = localFlag(grant,"PDCCHGrantBindingOk") || ...
    (localFlag(grant,"PDCCHGatingActive") && localFlag(grant,"ControlDecodeOk")) || ...
    localFlag(grant,"UCIOnPUSCHApplied");
for field = ["ExpectedUCIBits","MultiplexedUCIBits","HARQACKBits", ...
        "MultiplexedHARQACKBits","UCIOnPUSCHFeedbackGrantIds", ...
        "UCIOnPUSCHCSIReportIdentity"]
    value = sixgr.util.structGet(grant,field,[]);
    if ischar(value) || isstring(value)
        present = any(strlength(strtrim(string(value)))>0,'all');
    else
        present = ~isempty(value);
    end
    tf = tf || present;
end
id = string(sixgr.util.structGet(grant,"GrantContextId", ...
    sixgr.util.structGet(grant,"PHYGrant.GrantContextId","")));
if ~isscalar(id) || ismissing(id) || strlength(strtrim(id))==0, return; end
contracts = {"PendingFeedbackTable","PUSCHGrantContextId","Processed"; ...
    "PUCCHGrantTraceTable","PUSCHGrantContextId","GrantExecutedFlag"; ...
    "PendingCSITable","CSIUCIPUSCHGrantContextId","Processed"};
for k=1:size(contracts,1)
    T = sixgr.util.structGet(state,contracts{k,1},table());
    if ~istable(T) || isempty(T) || ~ismember(contracts{k,2},string(T.Properties.VariableNames))
        continue;
    end
    active = true(height(T),1);
    for flag = [contracts{k,3},"RightCensored","CanceledAtSweepBoundary"]
        if ismember(flag,string(T.Properties.VariableNames))
            active = active & ~logical(T.(flag));
        end
    end
    tf = tf || any(active & string(T.(contracts{k,2}))==id);
end
end

function tf = localFlag(s,name)
value = sixgr.util.structGet(s,name,false);
if isempty(value), tf=false; return; end
if ~(isnumeric(value)||islogical(value)) || ~isreal(value) || ...
        ~isscalar(value) || ~isfinite(value) || ~any(value==[0 1])
    error("sixgr:truth:InvalidPUSCHCommitFlag", ...
        "PUSCH ownership field %s must be an explicit boolean.",name);
end
tf=logical(value);
end
