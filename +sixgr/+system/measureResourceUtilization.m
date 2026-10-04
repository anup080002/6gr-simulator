function out = measureResourceUtilization(grants, opportunities, direction, firstTTI)
%MEASURERESOURCEUTILIZATION Measured PRB-symbol occupancy for one direction.
% The numerator is the union of executed grant PRB-symbols in each cell/TTI.
% The denominator is an independently recorded scheduling-opportunity
% calendar. Spatially overlapping grants occupy a resource once; failed TBs
% still consume it. This function does not estimate unexecuted grants.
arguments
    grants table
    opportunities table
    direction (1,1) string
    firstTTI (1,1) double {mustBeInteger,mustBePositive}
end
required = ["TTI","CellID","Direction","PRBSet","SymbolStart","NumSymbols"];
for T = {grants, opportunities}
    if ~all(ismember(required,string(T{1}.Properties.VariableNames)))
        error('sixgr:system:RUAllocationSchema', ...
            'Utilization requires exact PRBSet and independent cell/TTI/symbol evidence.');
    end
end
if ~ismember(direction,["UL","DL"])
    error('sixgr:system:RUDirection','Direction must be UL or DL.');
end
grants = grants(string(grants.Direction)==direction & grants.TTI>=firstTTI,:);
opportunities = opportunities(string(opportunities.Direction)==direction & ...
    opportunities.TTI>=firstTTI,:);
if isempty(opportunities)
    error('sixgr:system:RUOpportunityMissing', ...
        'No independent resource opportunities remain after warmup.');
end
[cellSlot,~,opGroup] = unique(double([opportunities.CellID,opportunities.TTI]),'rows');
[found,grantGroup] = ismember(double([grants.CellID,grants.TTI]),cellSlot,'rows');
if any(~found)
    error('sixgr:system:RUGrantOutsideOpportunity', ...
        'An executed grant has no independent cell/TTI opportunity.');
end
availableCount=zeros(size(cellSlot,1),1); occupiedCount=availableCount;
opIndices=accumarray(opGroup,(1:height(opportunities)).',[],@(x){x});
grantIndices=repmat({zeros(0,1)},size(cellSlot,1),1);
if ~isempty(grantGroup)
    grantIndices=accumarray(grantGroup,(1:height(grants)).', ...
        [size(cellSlot,1),1],@(x){x});
end
% Only materialize one cell/TTI grid at a time for large multi-cell runs.
for k=1:size(cellSlot,1)
    available=localExpand(opportunities(opIndices{k},:));
    occupied=localExpand(grants(grantIndices{k},:));
    if any(~ismember(occupied,available,'rows'))
        error('sixgr:system:RUGrantOutsideOpportunity', ...
            'An executed PRB-symbol lies outside the independent opportunity calendar.');
    end
    availableCount(k)=size(available,1); occupiedCount(k)=size(occupied,1);
end
if sum(availableCount)==0
    error('sixgr:system:RUOpportunityMissing','Available PRB-symbol count is zero.');
end
perSlot = table(cellSlot(:,1),cellSlot(:,2),occupiedCount,availableCount, ...
    100*occupiedCount./availableCount, ...
    'VariableNames',{'CellID','TTI','OccupiedPRBSymbols','AvailablePRBSymbols','RUPercent'});
out = struct('RUPercent',100*sum(occupiedCount)/sum(availableCount), ...
    'OccupiedPRBSymbols',sum(occupiedCount), ...
    'AvailablePRBSymbols',sum(availableCount),'PerCellSlot',perSlot, ...
    'Direction',direction,'FirstTTI',firstTTI, ...
    'Definition','union_executed_PRB_symbols_over_independent_available_PRB_symbols');
end

function rows = localExpand(T)
chunks = cell(height(T),1);
for k=1:height(T)
    idx = double([T.CellID(k),T.TTI(k),T.SymbolStart(k),T.NumSymbols(k)]);
    if any(~isfinite(idx)) || any(idx~=fix(idx)) || ...
            any(idx(1:2)<1) || idx(3)<0 || idx(4)<0
        error('sixgr:system:RUAllocationIndex', ...
            'CellID/TTI must be positive integers; symbol start/count nonnegative.');
    end
    p = T.PRBSet(k,:);
    if iscell(p), p=p{1}; end
    if isstring(p) || ischar(p), p=jsondecode(p); end
    p = double(p(:));
    if any(~isfinite(p)) || any(p<0) || any(p~=fix(p)) || numel(unique(p))~=numel(p)
        error('sixgr:system:RUInvalidPRBSet', ...
            'PRBSet must contain unique zero-based integer indices.');
    end
    [prb,symbol] = ndgrid(p,idx(3)+(0:idx(4)-1));
    chunks{k} = [repmat(idx(1:2),numel(prb),1),prb(:),symbol(:)];
end
if isempty(chunks), rows=zeros(0,4); else, rows=unique(vertcat(chunks{:}),'rows'); end
end
