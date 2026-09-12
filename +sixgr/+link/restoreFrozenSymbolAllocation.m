function grant=restoreFrozenSymbolAllocation(grant,phyGrant,direction)
% Rehydrate a missing compatibility alias from exact frozen allocation.
% The current canonical timing decision must still agree; no YAML inference.
if isfield(grant,'SymbolAllocation') && ~isempty(grant.SymbolAllocation), return; end
assert(isstruct(phyGrant) && isscalar(phyGrant) && ...
    isequal(sixgr.util.structGet(phyGrant,'IsFrozen',false),true), ...
    'sixgr:link:FrozenSymbolAllocationRequired', ...
    'A missing symbol-allocation alias requires a real frozen PHY grant.');
sixgr.phy.grant.assertPHYGrantDimensions(phyGrant,'restore_frozen_symbol_allocation');
allocation=sixgr.util.structGet(phyGrant,'ResourceAllocation.SymbolAllocation',[]);
validateattributes(allocation,{'numeric'},{'vector','numel',2,'integer','finite','nonnegative'});
grant.SymbolAllocation=double(allocation(:).');
sixgr.phy.grant.assertGrantTimingIdentity(grant,direction);
end
