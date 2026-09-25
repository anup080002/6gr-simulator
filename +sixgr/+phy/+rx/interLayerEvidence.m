function evidence=interLayerEvidence(equalizerResult)
% Receiver-estimated residual from the actual executed equalizer response.
% Unit desired-gain layer-symbol power, NOT injected channel interference
% and NOT a truth-channel measurement. No diagonal-channel zero fallback.
evidence=struct('ResidualInterLayerPowerMean',NaN, ...
    'ResidualInterLayerPowerPerLayer',[], ...
    'ResidualInterLayerPowerSource',"executed_equalizer_estimated_WH", ...
    'ResidualInterLayerPowerStatus',"unavailable_equalizer_response");
A=sixgr.util.structGet(equalizerResult,'EffectiveResponseWH',[]);
if isempty(A), return; end
nLayers=size(A,2);
assert(size(A,3)==nLayers && all(isfinite(A),'all'), ...
    'sixgr:phy:InvalidInterLayerResponse','Expected finite RE-by-layer-by-layer WH.');
powers=NaN(size(A,1),nLayers);
for layer=1:nLayers
    gain=abs(A(:,layer,layer)).^2;
    assert(all(gain>0),'sixgr:phy:InvalidInterLayerResponse','Desired layer response is zero.');
    others=setdiff(1:nLayers,layer);
    powers(:,layer)=sum(abs(A(:,layer,others)).^2,3)./gain;
end
evidence.ResidualInterLayerPowerPerLayer=mean(powers,1);
evidence.ResidualInterLayerPowerMean=mean(powers,'all');
evidence.ResidualInterLayerPowerStatus="measured_equalizer_response_unit_desired_gain";
end
