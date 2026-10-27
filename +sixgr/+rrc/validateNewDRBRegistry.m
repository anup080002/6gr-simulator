function validateNewDRBRegistry(installed,connection,message)
% The caller supplies the complete connection registry, including configured DRBs.
id='sixgr:rrc:NewDRBRegistry';
assert(iscell(installed)&&isstruct(connection)&&isscalar(connection)&&all(isfield(connection,{'ExecutionRunID','UEID','ServingCell','RNTI','ConfigurationEpoch'})),id,'Require the complete original connection registry.');
s=message.Semantic;
for k=1:numel(installed)
    prior=installed{k};
    names={'ExecutionRunID','UEID','ServingCell','RNTI','ConfigurationEpoch','DRBID','LCID','PduSessionID','QFI','DefaultDRB'};
    assert(isstruct(prior)&&isscalar(prior)&&all(isfield(prior,names)),id,'A malformed prior record cannot be interpreted as no conflict.');
    same=true;
    for name=["ExecutionRunID","UEID","ServingCell","RNTI","ConfigurationEpoch"]
        same=same&&isequaln(prior.(name),connection.(name));
    end
    if ~same,continue;end
    error('sixgr:rrc:MultipleDRBsUnsupported','The current Bridge supports one original DRB per connection; never replace an existing owner.');

end
end
