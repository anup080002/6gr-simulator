function [events,sourceIndices]=type2HARQACKLayout(events,epoch,ulTotalDAI)
% TS 38.213 18.8.0 9.1.3.1, two-bit counter DAI, scalar TB feedback.
% Only received events are retained. A zero source index denotes a protocol
% NACK position inferred from DAI, NOT an observed PDSCH or receiver DTX.
% There is no scheduler ledger input: undetectable whole missed DAI cycles
% and trailing missed assignments cannot be reconstructed by the UE.
if nargin<3, ulTotalDAI=[]; end
if ~isempty(ulTotalDAI)
    ulTotalDAI=localInteger(ulTotalDAI,1,4,'ReceivedULTotalDAI');
end
sourceIndices=zeros(0,1);
if isempty(events)
    % TS 38.213 9.1.3.2: with no received DL assignment and UL total DAI=4,
    % omit HARQ-ACK. Other indicated positions are protocol NACKs, not DTX.
    if ~isempty(ulTotalDAI) && ulTotalDAI~=4
        sourceIndices=zeros(ulTotalDAI,1);
    end
    return;
end
n=numel(events); key=zeros(n,3); dai=zeros(n,1); total=nan(n,1);
priority=zeros(n,1);
hasOccasion=arrayfun(@(e)isfield(e.Data,'MonitoringOccasionIndex'),events);
assert(all(hasOccasion) || ~any(hasOccasion), ...
    'sixgr:phy:pucch:InvalidHARQEvent','Monitoring-occasion identity must be supplied for every event or none.');
for k=1:n
    d=events(k).Data;
    index=localInteger(d.EventIndex,0,flintmax,'EventIndex');
    cellIndex=localInteger(d.ServingCell,0,flintmax,'ServingCell');
    dai(k)=localInteger(d.DAI,1,4,'DAI');
    priority(k)=localInteger(d.Priority,0,1,'Priority');
    if all(hasOccasion)
        occasion=localInteger(d.MonitoringOccasionIndex,0,flintmax,'MonitoringOccasionIndex');
    else
        occasion=index;
    end
    key(k,:)=[occasion cellIndex index];
    if isfield(d,'TotalDAI') && ~isempty(d.TotalDAI)
        total(k)=localInteger(d.TotalDAI,1,4,'TotalDAI');
    end
    if isfield(d,'ConfigurationEpoch')
        assert(localInteger(d.ConfigurationEpoch,0,flintmax,'ConfigurationEpoch')==epoch, ...
            'sixgr:phy:pucch:StaleConfiguration','HARQ event configuration epoch differs from its codebook.');
    end
    for field=["NumCodewords","CounterDAIBits"]
        expected=1+double(field=="CounterDAIBits");
        if isfield(d,field)
            assert(localInteger(d.(field),1,2,field)==expected, ...
                'sixgr:phy:pucch:UnsupportedHARQCodebook', ...
                'This scalar-TB procedure requires NumCodewords=1 and CounterDAIBits=2.');
        end
    end
end
assert(numel(unique(priority))==1,'sixgr:phy:pucch:MixedHARQPriority', ...
    'Different priorities require separate codebooks before any configured multiplexing.');
% Supplied identity must never mix distinct UE/feedback contexts.
for field=["TargetSlot","RNTI"]
    present=arrayfun(@(e)isfield(e.Data,field),events);
    if any(present)
        assert(all(present),'sixgr:phy:pucch:InvalidHARQEvent','Partial %s identity is not allowed.',field);
        values=arrayfun(@(e)localInteger(e.Data.(field),0,flintmax,field),events);
        assert(numel(unique(values))==1,'sixgr:phy:pucch:MixedHARQContext', ...
            'HARQ events must share %s.',field);
    end
end
[key,order]=sortrows(key,[1 2 3]);
events=events(order); dai=dai(order); total=total(order);
for occasion=unique(key(:,1)).'
    indicated=total(key(:,1)==occasion & isfinite(total));
    assert(numel(unique(indicated))<=1,'sixgr:phy:pucch:InconsistentTotalDAI', ...
        'Total DAI must agree across decoded DCIs in one monitoring occasion.');
end
wraps=0; previous=0; positions=zeros(n,1);
for k=1:n
    if dai(k)<=previous, wraps=wraps+1; end
    positions(k)=4*wraps+dai(k);
    previous=dai(k);
end
% Use a received total DAI from the final observed monitoring occasion when
% present, including when its highest-cell received DCI omits that field.
lastTotal=total(key(:,1)==key(end,1) & isfinite(total));
if isempty(lastTotal), lastTotal=previous; else, lastTotal=lastTotal(1); end
% PUSCH uses the received UL grant's total DAI after the monitoring loops.
% Do not overwrite a received DL event or invent a trailing DL reception.
if ~isempty(ulTotalDAI), lastTotal=ulTotalDAI; end
if lastTotal<previous, wraps=wraps+1; end
sourceIndices=zeros(4*wraps+lastTotal,1);
sourceIndices(positions)=(1:n).';
end

function value=localInteger(raw,lower,upper,name)
assert(isnumeric(raw) && isreal(raw) && isscalar(raw) && isfinite(raw) && ...
    raw==fix(raw) && raw>=lower && raw<=upper, ...
    'sixgr:phy:pucch:InvalidHARQEvent','%s must be a finite integer in [%g,%g].',name,lower,upper);
value=double(raw);
end
