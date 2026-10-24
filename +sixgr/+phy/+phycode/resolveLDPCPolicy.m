function policy=resolveLDPCPolicy(cfg,algorithm)
%RESOLVELDPCPOLICY Runtime receiver policy, separate from primitive defaults.
catalog=sixgr.config.loadCoreCatalog();
rules=catalog.parameters.phy.ldpc;
policy=sixgr.util.structGet(cfg,'phy.ldpc',struct());
for name=["algorithm","scalingFactor","minSumOffset","termination"]
    if ~isfield(policy,name), policy.(name)=rules.(name).default; end
end
if nargin>1 && strlength(string(algorithm))>0, policy.algorithm=char(string(algorithm)); end
policy=sixgr.config.validateLDPCPolicy(policy);
end
