function out=summarizeSlotSymbolRoles(partition)
% Report the actual resolved calendar, including unresolved flexible symbols.
out=struct('SymbolRoleContractVersion',"SlotSymbolRoles/v2", ...
    'SymbolRolesJSON',"",'SymbolRoleIndexBase',0, ...
    'FlexibleNumSymbols',NaN,'UnusedNumSymbols',NaN, ...
    'ReservedNumSymbols',NaN,'ExplicitGuardNumSymbols',NaN, ...
    'ClassifiedNumSymbols',NaN,'SymbolRoleStatus',"unavailable_resolved_calendar");
if nargin==0 || ~isstruct(partition) || ~isfield(partition,'ResolvedDirection')
    return;
end
roles=upper(string(partition.ResolvedDirection)); roles=roles(:).';
count=sixgr.util.structGet(partition,'SymbolsPerSlot',NaN);
assert(isscalar(count) && isfinite(count) && count==numel(roles) && count>0, ...
    'sixgr:truth:InvalidSlotRoleMap','Resolved symbol map does not span the slot.');
roles(roles=="D")="DL"; roles(roles=="U")="UL";
roles(roles=="UNRESOLVED_FLEX" | roles=="F")="FLEXIBLE";
assert(all(ismember(roles,["DL","UL","GUARD","FLEXIBLE","UNUSED","RESERVED"])), ...
    'sixgr:truth:UnknownSlotRole','An unknown resolved symbol role cannot be scheduled or exported as guard.');
out.SymbolRolesJSON=string(jsonencode(roles));
out.FlexibleNumSymbols=nnz(roles=="FLEXIBLE");
out.UnusedNumSymbols=nnz(roles=="UNUSED");
out.ReservedNumSymbols=nnz(roles=="RESERVED");
out.ExplicitGuardNumSymbols=nnz(roles=="GUARD");
out.ClassifiedNumSymbols=numel(roles);
out.SymbolRoleStatus="available_resolved_calendar_not_measured_occupancy";
end
