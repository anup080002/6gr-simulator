function assertGrantTimingIdentity(grant, direction)
%ASSERTGRANTTIMINGIDENTITY Reject an allocation edited after timing selection.
% This checks an issued decision, not current mutable BWP/TAG state. Raw
% resource-only/calibration contracts without a TimingDecision remain outside
% this check; passing here is not evidence of received control or RF timing.
if ~isfield(grant,'TimingDecision')
    return;
end
t=grant.TimingDecision;
if isstruct(t) && isscalar(t) && isempty(fieldnames(t))
    return;
end
localRequire(isstruct(t) && isscalar(t) && isfield(t,'Valid') && isequal(t.Valid,true),'TimingDecision');
if nargin<2, direction=grant.Direction; end
localRequire(isscalar(string(direction)) && upper(string(direction))==string(t.Direction),'Direction');
localRequire(isfield(grant,'Direction') && isscalar(string(grant.Direction)) && ...
    upper(string(grant.Direction))==string(t.Direction),'Direction');
localRequire(isfield(t,'DataDecision'),'DataDecision');
d=t.DataDecision;
localRequire(isstruct(d) && isscalar(d) && isfield(d,'Valid') && isequal(d.Valid,true),'DataDecision');
localNumber(grant,'SymbolAllocation',[d.TargetStartSymbol d.TargetNumSymbols],true);
localNumber(grant,'ScheduledAbsoluteSlot',d.TargetAbsoluteSlot,true);
localNumber(t,'DataAbsoluteSlot',d.TargetAbsoluteSlot,true);
localNumber(grant,'ControlAbsoluteSlot',t.ControlAbsoluteSlot,true);
for field=["K0","K1","K2","CarrierIndicator"]
    localNumber(grant,field,t.(field),false);
end
for field=["SchedulingCCID","ScheduledCCID","SourceBWPID","TargetBWPID"]
    if isfield(grant,field)
        value=string(grant.(field));
        localRequire(isscalar(value) && value==string(t.(field)),field);
    end
end
% The control allocation is resolved once from explicit grant/config
% authority and retained in the production timing decision for replay.
localRequire(isfield(t,'ControlSymbolAllocation') && ...
    numel(t.ControlSymbolAllocation)==2,'ControlSymbolAllocation');
localNumber(grant,'ControlSymbolAllocation',t.ControlSymbolAllocation,false);
localNumber(grant,'PDCCHSymbolAllocation',t.ControlSymbolAllocation,false);
localNumber(d,'SourceNumSymbols',t.ControlSymbolAllocation(2),true);
localNumber(grant,'DataAbsoluteSlot',t.DataAbsoluteSlot,false);
localNumber(grant,'HARQFeedbackAbsoluteSlot',t.FeedbackAbsoluteSlot,false);
localNumber(grant,'FeedbackAbsoluteSlot',t.FeedbackAbsoluteSlot,false);
if string(t.Direction)=="UL"
    localNumber(grant,'TimingAdvanceTicks',d.TimingAdvanceTicks,false);
elseif t.HARQACKRequired
    ack=t.HARQACKDecision;
    localRequire(isstruct(ack) && isscalar(ack) && isequal(ack.Valid,true),'HARQACKDecision');
    localNumber(grant,'TimingAdvanceTicks',ack.TimingAdvanceTicks,false);
    allocation=[ack.TargetStartSymbol ack.TargetNumSymbols];
    localNumber(grant,'HARQFeedbackSymbolAllocation',allocation,false);
    localNumber(grant,'PUCCHSymbolAllocation',allocation,false);
    localNumber(ack,'SourceTick',d.TargetTick,true);
    localNumber(ack,'SourceEndTick',d.TargetEndTick,true);
    localNumber(ack,'TargetAbsoluteSlot',t.FeedbackAbsoluteSlot,true);
end
end

function localNumber(s,field,expected,required)
if ~isfield(s,field)
    localRequire(~required,field);
    return;
end
value=s.(field);
localRequire(isnumeric(value) && isreal(value) && numel(value)==numel(expected) && ...
    all(isfinite(value(:)) | isnan(value(:))) && ...
    all(value(isfinite(value))==fix(value(isfinite(value)))) && ...
    all((value(:)==expected(:)) | (isnan(value(:)) & isnan(expected(:)))),field);
end

function localRequire(condition,field)
assert(condition,'sixgr:phy:grant:TimingIdentityMismatch', ...
    'grant_timing_identity_mismatch:%s. Resolve a new canonical timing decision before DCI/TX.',field);
end
