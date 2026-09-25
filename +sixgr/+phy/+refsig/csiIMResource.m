function plan=csiIMResource(carrier,cfg)
% Configured periodic CSI-IM, TS 38.214 5.2.2.4 / TS 38.331 CSI-IM-Resource.
% No transmitted symbols: these exact physical REs must be muted by serving
% transmissions and sampled by the receiver. Configuration is independent
% of transmitted/decoded payloads and of the configured SNR.
resource=sixgr.util.structGet(cfg,'phy.csiim',struct('enabled',false));
slot=double(carrier.NFrame)*double(carrier.SlotsPerFrame)+double(carrier.NSlot);
plan=struct('Enabled',false,'Scheduled',false,'ResourceID',NaN, ...
    'AbsoluteSlot0',slot,'PhysicalIndices1Based',zeros(0,1), ...
    'NumRE',0,'Pattern',NaN,'PRBs0Based',zeros(0,1), ...
    'Subcarriers0Based',zeros(0,1),'Symbols0Based',zeros(0,1));
if ~logical(sixgr.util.structGet(resource,'enabled',false)), return; end
for name=["resource_id","pattern","subcarrier","symbol","starting_rb", ...
        "num_rbs","period_slots","offset_slots"]
    assert(isfield(resource,name),'sixgr:phy:csiim:MissingConfiguration', ...
        'Enabled CSI-IM requires phy.csiim.%s.',name);
    validateattributes(resource.(name),{'numeric'},{'real','finite','scalar','integer','nonnegative'});
end
assert(resource.resource_id<=31 && ismember(resource.pattern,[0 1]), ...
    'sixgr:phy:csiim:InvalidResource','CSI-IM requires resource ID 0..31 and pattern 0 or 1.');
assert(ismember(resource.period_slots,[4 5 8 10 16 20 32 40 64 80 160 320 640]) && ...
    resource.offset_slots<resource.period_slots, ...
    'sixgr:phy:csiim:InvalidCalendar','CSI-IM requires an NR periodic resource calendar.');
assert(resource.num_rbs>=24 && resource.num_rbs<=276 && mod(resource.num_rbs,4)==0 && ...
    resource.starting_rb<=274 && mod(resource.starting_rb,4)==0, ...
    'sixgr:phy:csiim:InvalidFrequencyOccupation','CSI-IM frequency occupation requires multiples of four CRBs.');
if resource.pattern==0
    assert(ismember(resource.subcarrier,0:2:10) && resource.symbol<=12, ...
        'sixgr:phy:csiim:InvalidPattern','Pattern 0 is a configured 2-subcarrier by 2-symbol block.');
    [dk,dl]=ndgrid(0:1,0:1);
else
    assert(ismember(resource.subcarrier,[0 4 8]) && resource.symbol<=13, ...
        'sixgr:phy:csiim:InvalidPattern','Pattern 1 is four adjacent subcarriers in one symbol.');
    dk=(0:3).'; dl=zeros(4,1);
end
assert(resource.symbol+max(dl(:))<double(carrier.SymbolsPerSlot), ...
    'sixgr:phy:csiim:SymbolOutsideSlot','CSI-IM must fit the configured cyclic-prefix slot.');
% Frequency occupation is relative to CRB 0, not the carrier's first PRB.
prbs=intersect(resource.starting_rb+(0:resource.num_rbs-1), ...
    double(carrier.NStartGrid)+(0:double(carrier.NSizeGrid)-1))-double(carrier.NStartGrid);
assert(~isempty(prbs),'sixgr:phy:csiim:OutsideCarrier','CSI-IM has no REs in the active carrier.');
runtimeSlot=double(sixgr.util.structGet(cfg,'lls6g.runtime.AbsoluteSlotIndex0',slot));
assert(isscalar(runtimeSlot) && runtimeSlot==slot, ...
    'sixgr:phy:csiim:ClockMismatch','CSI-IM and receiver carrier must use the same absolute slot.');
plan.Enabled=true; plan.ResourceID=double(resource.resource_id);
plan.Pattern=double(resource.pattern); plan.PRBs0Based=prbs(:);
plan.Scheduled=mod(slot-resource.offset_slots,resource.period_slots)==0;
if ~plan.Scheduled, return; end
K=12*double(carrier.NSizeGrid);
sc=reshape(12*prbs(:).'+resource.subcarrier+dk(:),[],1);
sy=repmat(resource.symbol+dl(:),numel(prbs),1);
plan.Subcarriers0Based=sc; plan.Symbols0Based=sy;
plan.PhysicalIndices1Based=sc+K*sy+1;
plan.NumRE=numel(sc);
end
