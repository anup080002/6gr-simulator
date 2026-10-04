function model=resolveNetworkSINRModel(cfg)
%RESOLVENETWORKSINRMODEL YAML-owned predictor and explicit legacy default.
catalog=sixgr.config.loadCoreCatalog();
policy=catalog.parameters.system.linkAbstraction.networkSpatial.sinrPredictorModel;
model=string(sixgr.util.structGet(cfg,'system.linkAbstraction.networkSpatial.sinrPredictorModel',policy.default));
assert(isscalar(model) && ismember(model,string(policy.allowed_values)), ...
    'sixgr:abstraction:NetworkSINRModel','system.linkAbstraction.networkSpatial.sinrPredictorModel must be one of: %s.', ...
    strjoin(string(policy.allowed_values),', '));
end
