function est = PDCCHChannelEstimator(rxGrid4D, dmrs, ctrlCfg, copyIndex, noiseVar, payloadLocations)
%PDCCHChannelEstimator Estimate the control-channel response from DMRS.

if nargin < 5 || isempty(noiseVar)
    noiseVar = 0;
end

if isempty(dmrs.Locations)
    est = struct("Hhat", complex([]), "NMSE", NaN, "NoiseVar", noiseVar, "QualityMetric", NaN);
    return;
end

slotMask = dmrs.Locations.CopyIndex == copyIndex;
loc = dmrs.Locations(slotMask, :);
txSym = dmrs.Symbols(slotMask);
if isempty(loc)
    est = struct("Hhat", complex([]), "NMSE", NaN, "NoiseVar", noiseVar, "QualityMetric", NaN);
    return;
end

nRx = size(rxGrid4D, 3);
hDmrs = complex(zeros(height(loc), nRx));
for i = 1:height(loc)
    y = squeeze(rxGrid4D(loc.Subcarrier(i)+1, loc.Symbol(i)+1, :, loc.SlotIndex(i)));
    hDmrs(i,:) = (y(:).' ./ txSym(i));
end

hMean = repmat(mean(hDmrs, 1), height(loc), 1);
residual = hDmrs - hMean;
nmse = mean(abs(hDmrs(:) - hMean(:)).^2) / max(mean(abs(hDmrs(:)).^2), eps);
est = struct();
est.Hhat = hDmrs;
est.HMean = mean(hDmrs, 1);
est.NMSE = NaN;
est.NMSESource = "unavailable_without_independent_channel_reference";
est.PilotReconstructionResidualRatio = double(nmse);
est.NoiseVar = double(noiseVar);
est.QualityMetric = mean(abs(hDmrs(:)).^2) / max(noiseVar, eps);
est.Residual = residual;
assert(nargin >= 6 && istable(payloadLocations) && ~isempty(payloadLocations), ...
    'sixgr:ctrl:PDCCHChannelEstimator:MissingPayloadCoordinates', ...
    'Channel estimates require the independently monitored payload RE coordinates.');
model = upper(string(ctrlCfg.ChannelModel));
if model == "AWGN"
    bundlePrecoding=logical(sixgr.util.structGet(ctrlCfg,'EnableTransmitDiversity',false)) && ...
        double(sixgr.util.structGet(ctrlCfg,'NTx',1))>1 && ...
        strcmpi(string(sixgr.util.structGet(ctrlCfg,'PrecoderGranularity','none')),'reg_bundle');
    if bundlePrecoding
        assert(ismember('REGIndex',loc.Properties.VariableNames) && ...
            ismember('REGIndex',payloadLocations.Properties.VariableNames), ...
            'sixgr:ctrl:PDCCHChannelEstimator:MissingBundleIdentity', ...
            'REG-bundle channel estimation requires independently monitored REG identities.');
        bundleSize=double(ctrlCfg.CORESET.REGBundleSize);
        pilotBundle=ceil(double(loc.REGIndex)/bundleSize);
        payloadBundle=ceil(double(payloadLocations.REGIndex)/bundleSize);
        est.HData=complex(zeros(height(payloadLocations),nRx));
        for slot=reshape(unique(payloadLocations.SlotIndex),1,[])
            for bundle=reshape(unique(payloadBundle(payloadLocations.SlotIndex==slot)),1,[])
                pilots=loc.SlotIndex==slot & pilotBundle==bundle;
                data=payloadLocations.SlotIndex==slot & payloadBundle==bundle;
                assert(any(pilots),'sixgr:ctrl:PDCCHChannelEstimator:MissingDMRS', ...
                    'Every monitored REG bundle needs its own received DMRS.');
                h=mean(hDmrs(pilots,:),1);
                est.HData(data,:)=repmat(h,sum(data),1);
                residual(pilots,:)=hDmrs(pilots,:)-h;
            end
        end
        est.Residual=residual;
        est.PilotReconstructionResidualRatio=mean(abs(residual(:)).^2)/max(mean(abs(hDmrs(:)).^2),eps);
        est.ChannelEstimateSource="received_dmrs_per_reg_bundle_awgn";
        return;
    end
    est.HData = repmat(est.HMean,height(payloadLocations),1);
    est.ChannelEstimateSource = "received_dmrs_flat_awgn";
    return;
end
assert(startsWith(model,"TDL-") || startsWith(model,"CDL-"), ...
    'sixgr:ctrl:PDCCHChannelEstimator:UnsupportedChannel', ...
    'Require explicit AWGN or a concrete fading profile, got %s.',model);
% A frequency-selective channel cannot use a burst-wide scalar estimate.
% Each repetition is estimated from its own received reference symbols.
K=size(rxGrid4D,1); L=size(rxGrid4D,2);
est.HData=complex(zeros(height(payloadLocations),nRx));
noiseSum=0; pilotCount=0;
for slot=reshape(unique(payloadLocations.SlotIndex),1,[])
    pilotRows=find(loc.SlotIndex==slot);
    payloadRows=find(payloadLocations.SlotIndex==slot);
    assert(~isempty(pilotRows),'sixgr:ctrl:PDCCHChannelEstimator:MissingDMRS', ...
        'The monitored payload slot has no received DMRS hypothesis.');
    pilotIndex=sub2ind([K L],loc.Subcarrier(pilotRows)+1,loc.Symbol(pilotRows)+1);
    reference=complex(zeros(K,L));
    reference(pilotIndex)=txSym(pilotRows);
    [hGrid,nVar]=nrChannelEstimate(rxGrid4D(:,:,:,slot),reference, ...
        'CDMLengths',[1 1],'CyclicPrefix',ctrlCfg.CyclicPrefix);
    h=reshape(hGrid,K*L,nRx);
    dataIndex=sub2ind([K L],payloadLocations.Subcarrier(payloadRows)+1, ...
        payloadLocations.Symbol(payloadRows)+1);
    est.HData(payloadRows,:)=h(dataIndex,:);
    residual(pilotRows,:)=hDmrs(pilotRows,:)-h(pilotIndex,:);
    noiseSum=noiseSum+double(nVar)*numel(pilotRows);
    pilotCount=pilotCount+numel(pilotRows);
end
assert(all(isfinite(est.HData(:))), ...
    'sixgr:ctrl:PDCCHChannelEstimator:InvalidEstimate','Nonfinite received channel estimate.');
est.NoiseVar=noiseSum/pilotCount;
est.Residual=residual;
est.PilotReconstructionResidualRatio=mean(abs(residual(:)).^2)/max(mean(abs(hDmrs(:)).^2),eps);
est.ChannelEstimateSource="received_dmrs_nrChannelEstimate_per_resource";
end
