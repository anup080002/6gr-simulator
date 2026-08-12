function [mse,meta] = channelEstimateMSE(receiverResult,channelResult,bundle,cfg)
%CHANNELESTIMATEMSE Compare production PBCH estimate with perfect channel.
if isempty(receiverResult.RxSSBGrid) || ~receiverResult.PBCHAttempted
    mse = NaN;
    meta = struct("Available",false,"Reason","pbch_not_attempted");
    return;
end
nRx = size(receiverResult.RxSSBGrid,3);
nTx = double(cfg.mimo.num_tx_antennas);
weights = ones(1,nTx)/sqrt(nTx);
if string(channelResult.ExecutionBackend) == "unit_channel_awgn"
    trueH = complex(ones(240,4,nRx));
else
    h = nrPerfectChannelEstimate(bundle.Carrier,channelResult.PathGains, ...
        channelResult.PathFilters,double(channelResult.TimingOffsetSamples), ...
        channelResult.SampleTimes,"SampleRate",bundle.SampleRateHz);
    cols = double(bundle.CandidateStartSymbol)+(1:4);
    if size(h,2) < cols(end)
        mse = NaN;
        meta = struct("Available",false,"Reason","perfect_channel_grid_too_short");
        return;
    end
    trueH = complex(zeros(240,4,nRx));
    for tx = 1:min(nTx,size(h,4))
        trueH = trueH + h(:,cols,:,tx)*weights(tx);
    end
end
nCellID = double(receiverResult.Sync.NCellID);
ibar = double(receiverResult.PBCH.PBCH.iBar_SSB);
refGrid = complex(zeros(240,4));
refGrid(nrPBCHDMRSIndices(nCellID)) = nrPBCHDMRS(nCellID,ibar);
refGrid(nrSSSIndices) = nrSSS(nCellID);
[estimatedH,~] = nrChannelEstimate(receiverResult.RxSSBGrid,refGrid, ...
    "AveragingWindow",[0 1]);
if ndims(estimatedH) == 4
    estimatedH = estimatedH(:,:,:,1);
end
denominator = mean(abs(trueH(:)).^2,"omitnan");
mse = mean(abs(estimatedH(:)-trueH(:)).^2,"omitnan")/max(denominator,realmin);
meta = struct("Available",isfinite(mse), ...
    "Source","nrChannelEstimate_vs_nrPerfectChannelEstimate_effective_precoded_port", ...
    "Normalized",true,"Reason","");
end
