function T = buildResourceOpportunityTable(tti, nCells, direction, budget, dataSchedulable)
%BUILDRESOURCEOPPORTUNITYTABLE Independent scheduler PRB-symbol denominator.
% DMRS/PTRS inside a shared-channel allocation count as occupied resources.
% The calendar covers configured data symbols only (already intersected with
% the TDD partition by the caller). Explicit whole PRB-symbol reservations
% in the scheduler budget are subtracted. This is not a data-RE fraction.
arguments
    tti (1,1) double {mustBeInteger,mustBePositive}
    nCells (1,1) double {mustBeInteger,mustBePositive}
    direction (1,1) string
    budget struct
    dataSchedulable (1,1) logical
end
T=table(zeros(0,1),zeros(0,1),strings(0,1),strings(0,1), ...
    zeros(0,1),zeros(0,1),strings(0,1),strings(0,1), ...
    'VariableNames',{'TTI','CellID','Direction','PRBSet','SymbolStart', ...
    'NumSymbols','Source','ReservationSemantics'});
if ~dataSchedulable, return; end
if isfield(budget,'NPRB') && isequal(double(budget.NPRB),0) && ...
        (~isfield(budget,'PRBSet') || isempty(budget.PRBSet))
    return; % Explicit fully reserved budget has zero opportunities.
end
if ~ismember(direction,["UL","DL"])
    error("sixgr:system:ResourceOpportunityDirection","Direction must be UL or DL.");
end
if isfield(budget,"PRBSet") && ~isempty(budget.PRBSet)
    prbs=double(budget.PRBSet(:).');
elseif isfield(budget,"NPRB") && isscalar(budget.NPRB) && ...
        isfinite(budget.NPRB) && budget.NPRB>=1 && budget.NPRB==fix(budget.NPRB)
    prbs=0:double(budget.NPRB)-1;
else
    error("sixgr:system:ResourceOpportunityPRB","An exact PRB budget is required.");
end
if any(~isfinite(prbs)) || any(prbs<0) || any(prbs~=fix(prbs)) || numel(unique(prbs))~=numel(prbs)
    error("sixgr:system:ResourceOpportunityPRB","PRB set must have unique 0-based integers.");
end
if ~isfield(budget,"SymbolAllocation") || numel(budget.SymbolAllocation)~=2
    error("sixgr:system:ResourceOpportunitySymbols","Explicit [start,count] symbols required.");
end
a=double(budget.SymbolAllocation(:).');
if any(~isfinite(a)) || any(a<0) || any(a~=fix(a))
    error("sixgr:system:ResourceOpportunitySymbols","Symbol allocation must contain nonnegative integers.");
end
reserved=sixgr.util.structGet(budget,"ReservedResourceRegions",struct([]));
cellIDs=(1:nCells).';
if isfield(budget,'CellID')
    assert(nCells==1,'sixgr:system:ResourceOpportunityCell', ...
        'A cell-specific reserved budget requires nCells=1.');
    validateattributes(budget.CellID,{'numeric'},{'scalar','integer','positive'});
    cellIDs=double(budget.CellID);
end
for s=a(1)+(0:a(2)-1)
    available=prbs;
    for j=1:numel(reserved)
        r=reserved(j);
        if ~isfield(r,"PRBSet") || ~isfield(r,"SymbolAllocation") || numel(r.SymbolAllocation)~=2
            error("sixgr:system:ResourceOpportunityReservation", ...
                "Explicit reservations require PRBSet and [start,count] SymbolAllocation.");
        end
        allocation=double(r.SymbolAllocation(:).');
        rprbs=double(r.PRBSet(:).');
        if any(~isfinite([allocation,rprbs])) || any([allocation,rprbs]<0) || ...
                any([allocation,rprbs]~=fix([allocation,rprbs]))
            error("sixgr:system:ResourceOpportunityReservation","Invalid reservation indices.");
        end
        if s>=allocation(1) && s<sum(allocation)
            available=setdiff(available,rprbs,"stable");
        end
    end
    if isempty(available), continue; end
    encoded=string(jsonencode(available));
    if height(T)>=nCells
        last=(height(T)-nCells+1):height(T);
        if all(T.PRBSet(last)==encoded) && all(T.SymbolStart(last)+T.NumSymbols(last)==s)
            T.NumSymbols(last)=T.NumSymbols(last)+1;
            continue
        end
    end
    rows=table(repmat(tti,nCells,1),cellIDs,repmat(direction,nCells,1), ...
        repmat(encoded,nCells,1),repmat(s,nCells,1),ones(nCells,1), ...
        repmat("executed_slot_scheduler_budget_independent_of_grants",nCells,1), ...
        repmat("gross_PRB_symbol_DMRS_PTRS_included_explicit_whole_regions_excluded",nCells,1), ...
        'VariableNames',T.Properties.VariableNames);
    T=[T;rows]; %#ok<AGROW>
end
end
