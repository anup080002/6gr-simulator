function evidence=executedResourceIntervals(grid,absoluteSlot0)
%EXECUTEDRESOURCEINTERVALS Compact actual mapped OFDM occupancy for reporting.
% PRB union across physical ports, separately for every occupied symbol.
% This is neither a receiver estimate nor measured RF on/off activity. A
% caller publishes this only with its executed transmission/reception row.
evidence=struct('ExecutedResourceIntervalsJSON',"", ...
    'ExecutedResourceIntervalSource',"",'ResourceGridPRBCount',NaN, ...
    'ResourceSymbolsPerSlot',NaN);
if nargin==0, return; end
validateattributes(absoluteSlot0,{'numeric'}, ...
    {'scalar','real','finite','integer','nonnegative'});
assert(isnumeric(grid) && ~isempty(grid) && ndims(grid)<=3 && ...
    mod(size(grid,1),12)==0 && any(size(grid,2)==[12 14]) && ...
    all(isfinite(grid),'all'),'sixgr:truth:InvalidExecutedResourceGrid', ...
    'Resource accounting requires the actual finite carrier OFDM grid.');
mask=any(grid~=0,3);
prototype=struct('AbsoluteSlotIndex0',double(absoluteSlot0), ...
    'SymbolIndex0',NaN,'PRBSet0Based',[]);
records=repmat(prototype,0,1);
for symbol=1:size(mask,2)
    prbs=find(any(reshape(mask(:,symbol),12,[]),1))-1;
    if isempty(prbs), continue; end
    r=prototype; r.SymbolIndex0=symbol-1; r.PRBSet0Based=double(prbs);
    records(end+1,1)=r; %#ok<AGROW>
end
evidence.ExecutedResourceIntervalsJSON=string(jsonencode(records));
evidence.ExecutedResourceIntervalSource="mapped_TX_grid_nonzero_PRB_symbol_union_not_RF_activity";
evidence.ResourceGridPRBCount=size(grid,1)/12;
evidence.ResourceSymbolsPerSlot=size(grid,2);
end
