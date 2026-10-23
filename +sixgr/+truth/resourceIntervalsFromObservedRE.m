function evidence=resourceIntervalsFromObservedRE(T,carrier,channel)
% Compact one actual transmission's per-port RE runs, never planned grants.
% Multiple ports/components share PRBs; each absolute symbol is unioned.
evidence=sixgr.truth.executedResourceIntervals();
if isempty(T), return; end
if nargin>=3
    assert(ismember('channel',T.Properties.VariableNames), ...
        'sixgr:truth:MissingResourceChannel','Actual channel ownership is required.');
    T=T(string(T.channel)==string(channel),:);
    assert(~isempty(T),'sixgr:truth:MissingExecutedChannelResources', ...
        'The requested channel has no executed resources in this transmission.');
end
required={'absolute_slot','symbol_index','subcarrier_start','subcarrier_count', ...
    'grid_domain','evidence_scope','active_flag','allocation_id'};
assert(istable(T) && all(ismember(required,T.Properties.VariableNames)) && ...
    all(string(T.grid_domain)=="carrier_cp_ofdm") && ...
    all(string(T.evidence_scope)=="runtime_observed_tx_occupancy") && ...
    all(T.active_flag==1) && ...
    all(~ismissing(string(T.allocation_id)) & strlength(strtrim(string(T.allocation_id)))>0) && ...
    numel(unique(string(T.allocation_id)))==1, ...
    'sixgr:truth:InvalidExecutedREIntervals','Require one actual carrier-OFDM transmission, not a planned allocation.');
gridRB=double(carrier.NSizeGrid); symbols=double(carrier.SymbolsPerSlot);
coordinates=unique(double(T{:,required(1:4)}),'rows','sorted');
assert(all(isfinite(coordinates)&coordinates==fix(coordinates),'all') && ...
    all(coordinates(:,1)>=0 & coordinates(:,2)>=0 & coordinates(:,2)<symbols & ...
    coordinates(:,3)>=0 & coordinates(:,4)>0 & coordinates(:,3)+coordinates(:,4)<=12*gridRB), ...
    'sixgr:truth:InvalidExecutedRECoordinates','Executed RE runs must fit their actual carrier grid.');
[clock,~,group]=unique(coordinates(:,1:2),'rows','sorted');
rows=repmat(struct('AbsoluteSlotIndex0',NaN,'SymbolIndex0',NaN,'PRBSet0Based',[]),size(clock,1),1);
for k=1:size(clock,1)
    runs=coordinates(group==k,3:4);
    ranges=unique([floor(runs(:,1)/12),floor((sum(runs,2)-1)/12)],'rows');
    mask=false(1,gridRB);
    for r=1:size(ranges,1), mask(ranges(r,1)+1:ranges(r,2)+1)=true; end
    rows(k).AbsoluteSlotIndex0=clock(k,1); rows(k).SymbolIndex0=clock(k,2);
    rows(k).PRBSet0Based=find(mask)-1;
end
evidence.ExecutedResourceIntervalsJSON=string(jsonencode(rows));
evidence.ExecutedResourceIntervalSource="executed_TX_RE_runs_PRB_symbol_union_not_RF_activity";
evidence.ResourceGridPRBCount=gridRB;
evidence.ResourceSymbolsPerSlot=symbols;
end
