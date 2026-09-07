function policy=resolvePreconnectionRSRPFilter(cfg)
% One explicit UE implementation authority; no implicit received RRC config.
policy=struct();
k=sixgr.util.structGet(cfg,'initial_access.preconnection_rsrp_filter_coefficient_k',[]);
period=sixgr.util.structGet(cfg,'initial_access.preconnection_rsrp_filter_reference_period_ms',[]);
if isempty(k) && isempty(period), return; end
if isempty(k) || isempty(period)
    error('sixgr:truth:IncompleteUEFilterConfiguration','Preconnection RSRP filter needs both coefficient k and reference period.');
end
epoch=sixgr.util.structGet(cfg,'initial_access.configuration_epoch',NaN);
validateattributes(epoch,{'numeric'},{'scalar','finite','integer','nonnegative'});
source="ue_preconnection_implementation_filter_not_received_quantityConfig";
sixgr.rrc.ReferenceRSRPFilter(k,double(period)/1000,source); % Strict value validation.
policy=struct('Epoch',epoch,'CoefficientK',double(k),'ReferencePeriod_ms',double(period),'Source',source);
policy.ConfigHash=string(sixgr.util.sha256Hex(jsonencode(policy)));
end
