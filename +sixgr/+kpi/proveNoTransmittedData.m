function evidence = proveNoTransmittedData(raw, direction)
%PROVENOTRANSMITTEDDATA Distinguish a completed zero-attempt window from loss.
% This is an applicability proof, not a PHY success or decoder measurement.
direction = upper(string(direction));
assert(isscalar(direction) && any(direction == ["DL","UL"]), ...
    'sixgr:kpi:InvalidDirection','Expected DL or UL.');
evidence = struct('Proven',false,'DurationSec',NaN,'SlotCount',0, ...
    'SourceHash',"",'Reason',"no_complete_zero_transmission_evidence");
names = ["ScenarioSummary","RunState","SlotTrace",direction,direction+"Grants"];
for name = names
    if ~isstruct(raw) || ~isfield(raw,name) || ~istable(raw.(name)) || width(raw.(name))==0
        return;
    end
end
summary=raw.ScenarioSummary; state=raw.RunState; slots=raw.SlotTrace;
trials=raw.(direction); grants=raw.(direction+"Grants");
if height(summary)~=1 || height(state)~=1 || isempty(slots) || ~isempty(trials) || ~isempty(grants)
    return;
end
if ~all(ismember(["Slot","CRCPass"],string(trials.Properties.VariableNames))) || ...
        ~all(ismember(["GrantContextId","TBSBits","Direction"],string(grants.Properties.VariableNames))) || ...
        ~any(localText(summary,"RunCompletion")==["completed","completed_with_failures","failed"])
    return;
end
n=height(slots);
for name=["CanonicalSlotsPerSweepPoint","CurrentCanonicalSlot","SlotTraceRows"]
    if localNumber(state,name)~=n, return; end
end
if localNumber(state,direction+"GrantRows")~=0 || ...
        localNumber(summary,"Effective"+direction+"TrialCount")~=0 || ...
        ~isequal(localNumber(slots,"CanonicalSlot"),(1:n)')
    return;
end
point=localNumber(slots,"SweepPointIndex");
if any(~isfinite(point) | point<1 | point~=fix(point)) || numel(unique(point))~=1
    return;
end
for key=["ScenarioID","ConfigHash"]
    identity=localText(state,key);
    if ismissing(identity) || strlength(identity)==0 || ...
            any(ismissing(localText(summary,key))) || any(ismissing(localText(slots,key))) || ...
            any(localText(summary,key)~=identity) || any(localText(slots,key)~=identity)
        return;
    end
end
snr=localNumber(state,"ConfiguredSNR_dB");
if ~isfinite(snr) || any(localNumber(slots,"ConfiguredSNR_dB")~=snr), return; end
for suffix=["GrantCount","ExecutedGrantCount","TrialRows","TBSBits","SuccessCount"]
    if any(localNumber(slots,direction+suffix)~=0), return; end
end
scheduled=localNumber(slots,direction+"Scheduled");
status=localText(slots,direction+"Status");
if any(~ismember(scheduled,[0,1])) || ~any(scheduled==1) || ...
        any(ismissing(status)) || any(~ismember(status,["","idle_no_grant"])) || ...
        any(status(scheduled==1)~="idle_no_grant")
    return;
end
% Same-window packet successes contradict a no-data-transmission claim.
for name=["PacketSDU","ApplicationPackets"]
    if isfield(raw,name) && istable(raw.(name)) && ~isempty(raw.(name))
        packets=raw.(name);
        packetDirection=localText(packets,"Direction");
        if any(ismissing(packetDirection)) || any(~ismember(packetDirection,["DL","UL"]))
            return;
        end
        selected=packetDirection==direction;
        delivered=localNumber(packets,"DeliverySuccess");
        if any(~ismember(delivered(selected),[0,1])) || any(delivered(selected)==1), return; end
    end
end
slotMs=localNumber(summary,"SlotDuration_ms");
if ~isfinite(slotMs) || slotMs<=0, return; end
evidence.Proven=true;
evidence.DurationSec=n*slotMs/1000;
evidence.SlotCount=n;
sourceDigests=table(direction,sixgr.kpi.hashKPISourceRows(summary), ...
    sixgr.kpi.hashKPISourceRows(state),sixgr.kpi.hashKPISourceRows(slots), ...
    'VariableNames',{'Direction','ScenarioSummarySHA256','RunStateSHA256','SlotTraceSHA256'});
evidence.SourceHash=sixgr.kpi.hashKPISourceRows(sourceDigests);
evidence.Reason="completed_window_no_transmitted_data";
end

function values=localNumber(T,name)
values=NaN(height(T),1);
if ismember(name,string(T.Properties.VariableNames))
    column=T.(name);
    if isnumeric(column) || islogical(column), values=double(column);
    else, values=str2double(string(column)); end
end
end

function values=localText(T,name)
values=strings(height(T),1); values(:)=missing;
if ismember(name,string(T.Properties.VariableNames)), values=strtrim(string(T.(name))); end
end
