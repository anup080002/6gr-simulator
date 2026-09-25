function evidence=measureCSIIM(carrier,cfg,receivedGrid)
% Actual received disturbance on configured muted REs. No channel estimate,
% channel truth, thermal-noise configuration or transmitted data is used.
plan=sixgr.phy.refsig.csiIMResource(carrier,cfg);
evidence=struct('Available',false,'Plan',plan,'Covariance',[], ...
    'PowerPerReceiveAntenna',[],'MeanPower',NaN,'IncludesNoise',true, ...
    'SampleCount',0,'Source',"configured_CSI_IM_received_RE_second_moment", ...
    'Status',"disabled");
if ~plan.Enabled, return; end
evidence.Status="not_scheduled_in_slot";
if ~plan.Scheduled, return; end
validateattributes(receivedGrid,{'single','double'},{'nonempty','finite'});
assert(size(receivedGrid,1)==12*carrier.NSizeGrid && ...
    size(receivedGrid,2)==carrier.SymbolsPerSlot && ndims(receivedGrid)<=3, ...
    'sixgr:phy:csiim:InvalidGrid','CSI-IM requires the actual K-by-L-by-Nrx slot grid.');
flat=reshape(double(receivedGrid),[],size(receivedGrid,3));
samples=flat(plan.PhysicalIndices1Based,:);
% Do not subtract the sample mean: coherent interference is disturbance,
% not an offset to be removed. Rows contain unconjugated receive vectors.
covariance=samples.'*conj(samples)/size(samples,1);
covariance=(covariance+covariance')/2;
evidence.Covariance=covariance;
evidence.PowerPerReceiveAntenna=real(diag(covariance)).';
evidence.MeanPower=mean(evidence.PowerPerReceiveAntenna);
evidence.SampleCount=size(samples,1);
evidence.Available=true; evidence.Status="measured";
end
