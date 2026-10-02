function out = measureSLSResourceUtilization(grants, opportunities, direction, firstTTI)
%MEASURESLSRESOURCEUTILIZATION Union of executed allocation PRB-symbols.
% The denominator is a separately recorded scheduling-opportunity calendar.
% Multiple spatially multiplexed grants occupy a resource only once. Failed
% transport blocks still occupy resources. Idle opportunities remain counted.
arguments
    grants table
    opportunities table
    direction (1,1) string
    firstTTI (1,1) double {mustBeInteger,mustBePositive}
end
required = ["TTI","CellID","Direction","PRBSet","SymbolStart","NumSymbols"];
for T = {grants, opportunities}
    if ~all(ismember(required,string(T{1}.Properties.VariableNames)))
        error("sixgr:ran1ai1032:RUAllocationSchema", ...
            "RU requires exact PRBSet and independent cell/TTI/symbol allocation evidence.");
    end
end
if ~ismember(direction,["UL","DL"])
    error("sixgr:ran1ai1032:RUDirection","Direction must be UL or DL.");
end
grants = grants(string(grants.Direction)==direction & grants.TTI>=firstTTI,:);
opportunities = opportunities(string(opportunities.Direction)==direction & ...
    opportunities.TTI>=firstTTI,:);
if isempty(opportunities)
    error("sixgr:ran1ai1032:RUOpportunityMissing", ...
        "No independent resource opportunities remain after warmup.");
end
[cellSlot,~,opGroup] = unique(double([opportunities.CellID,opportunities.TTI]),"rows");
[found,grantGroup] = ismember(double([grants.CellID,grants.TTI]),cellSlot,"rows");
if any(~found)
    error("sixgr:ran1ai1032:RUGrantOutsideOpportunity","An executed grant has no independent cell/TTI opportunity.");
end
availableCount=zeros(size(cellSlot,1),1); occupiedCount=availableCount;
opIndices=accumarray(opGroup,(1:height(opportunities)).',[],@(x){x});
grantIndices=repmat({zeros(0,1)},size(cellSlot,1),1);
if ~isempty(grantGroup)
    grantIndices=accumarray(grantGroup,(1:height(grants)).', ...
        [size(cellSlot,1),1],@(x){x});
end
% Only one cell/TTI grid is materialized at once. Large campaigns must not
% expand all cells and slots into one multi-billion-row intermediate matrix.
for k=1:size(cellSlot,1)
    available=localExpand(opportunities(opIndices{k},:));
    occupied=localExpand(grants(grantIndices{k},:));
    if any(~ismember(occupied,available,"rows"))
        error("sixgr:ran1ai1032:RUGrantOutsideOpportunity", ...
            "An executed PRB-symbol lies outside the independent opportunity calendar.");
    end
    availableCount(k)=size(available,1); occupiedCount(k)=size(occupied,1);
end
if sum(availableCount)==0
    error("sixgr:ran1ai1032:RUOpportunityMissing","Available PRB-symbol count is zero.");
end
perSlot = table(cellSlot(:,1),cellSlot(:,2),occupiedCount,availableCount, ...
    100*occupiedCount./availableCount, ...
    'VariableNames',{'CellID','TTI','OccupiedPRBSymbols','AvailablePRBSymbols','RUPercent'});
out = struct("RUPercent",100*sum(occupiedCount)/sum(availableCount), ...
    "OccupiedPRBSymbols",sum(occupiedCount), ...
    "AvailablePRBSymbols",sum(availableCount),"PerCellSlot",perSlot, ...
    "Direction",direction,"FirstTTI",firstTTI, ...
    "Definition","union_executed_PRB_symbols_over_independent_available_PRB_symbols");
end

function rows = localExpand(T)
chunks = cell(height(T),1);
for k=1:height(T)
    idx = double([T.CellID(k),T.TTI(k),T.SymbolStart(k),T.NumSymbols(k)]);
    if any(~isfinite(idx)) || any(idx~=fix(idx)) || ...
            any(idx(1:2)<1) || idx(3)<0 || idx(4)<0
        error("sixgr:ran1ai1032:RUAllocationIndex", ...
            "CellID/TTI must be positive integers; symbol start/count nonnegative.");
    end
    p = T.PRBSet(k,:);
    if iscell(p), p=p{1}; end
    if isstring(p) || ischar(p), p=jsondecode(p); end
    p = double(p(:));
    if any(~isfinite(p)) || any(p<0) || any(p~=fix(p)) || numel(unique(p))~=numel(p)
        error("sixgr:ran1ai1032:RUInvalidPRBSet","PRBSet must contain unique 0-based integers.");
    end
    [prb,symbol] = ndgrid(p,idx(3)+(0:idx(4)-1));
    chunks{k} = [repmat(idx(1:2),numel(prb),1),prb(:),symbol(:)];
end
if isempty(chunks), rows=zeros(0,4); else, rows=unique(vertcat(chunks{:}),"rows"); end
end
