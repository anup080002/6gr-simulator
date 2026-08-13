function [nmse,meta] = channelEstimateMSE(receiverResult,cleanWaveformWithCFO,bundle,cfg)
%CHANNELESTIMATEMSE Compare Hhat and exact receiver-referenced HtrueEff.
% The noiseless waveform is passed through the same CFO correction, timing
% crop and OFDM demodulation used by the practical receiver.  Division by
% the known transmitted PBCH/DMRS symbols then yields the effective channel
% after precoding, TDL filtering and the receiver's residual impairments.
meta = localUnavailable("receiver_or_channel_estimate_unavailable");
nmse = NaN;
if isempty(receiverResult.RxSSBGrid) || ~receiverResult.PBCHAttempted || ...
        ~receiverResult.CorrectPCIDeclared || ...
        ~isfield(receiverResult.PBCH,"EstimatedChannelGrid") || ...
        isempty(receiverResult.PBCH.EstimatedChannelGrid)
    return;
end
if logical(cfg.receiver.require_correct_dmrs_for_nmse) && ...
        double(receiverResult.PBCH.SelectedIBarSSB) ~= double(bundle.IBarSSB)
    meta = localUnavailable("selected_pbch_dmrs_hypothesis_incorrect");
    return;
end
try
    cleanGrid = localReplayReceiverTransform( ...
        cleanWaveformWithCFO,receiverResult,bundle);
    hhatGrid = receiverResult.PBCH.EstimatedChannelGrid;
    if ndims(hhatGrid)==2
        hhatGrid=reshape(hhatGrid,size(hhatGrid,1),size(hhatGrid,2),1);
    end
    if ndims(cleanGrid)==2
        cleanGrid=reshape(cleanGrid,size(cleanGrid,1),size(cleanGrid,2),1);
    end
    indices=unique([double(nrPBCHIndices(bundle.NCellID)); ...
        double(nrPBCHDMRSIndices(bundle.NCellID))]);
    transmitted=bundle.SSBGrid(indices);
    htrue=zeros(numel(indices),size(cleanGrid,3),"like",cleanGrid);
    hhat=zeros(numel(indices),size(hhatGrid,3),"like",hhatGrid);
    for rx=1:size(cleanGrid,3)
        slice=cleanGrid(:,:,rx);
        htrue(:,rx)=slice(indices)./transmitted;
    end
    for rx=1:size(hhatGrid,3)
        slice=hhatGrid(:,:,rx);
        hhat(:,rx)=slice(indices);
    end
    if ~isequal(size(hhat),size(htrue))
        meta=localUnavailable("effective_channel_dimension_mismatch");
        meta.HhatSize=double(size(hhat)); meta.HtrueEffSize=double(size(htrue));
        return;
    end
    numerator=sum(abs(hhat-htrue).^2,"all");
    denominator=sum(abs(htrue).^2,"all");
    nmse=double(numerator/max(denominator,realmin));
    meta=struct("Available",isfinite(nmse),"Reason","", ...
        "Source","receiver_replayed_noiseless_effective_pbch_channel", ...
        "Conditioning","correct_joint_sync_and_correct_pbch_dmrs_hypothesis", ...
        "NMSELinear",nmse,"NMSEDB",10*log10(max(nmse,realmin)), ...
        "SquaredErrorNumerator",double(numerator), ...
        "TruthEnergyDenominator",double(denominator), ...
        "HhatSize",double(size(hhat)),"HtrueEffSize",double(size(htrue)), ...
        "ComparedRE",double(numel(indices)),"Normalized",true);
catch ME
    meta=localUnavailable("effective_channel_replay_failed:"+string(ME.identifier));
end
end

function grid=localReplayReceiverTransform(waveform,receiver,bundle)
estimateHz=double(receiver.CFOEstimateHz);
n=(0:size(waveform,1)-1).';
corrected=waveform.*exp(-1j*2*pi*estimateHz*n/bundle.SampleRateHz);
tOff=double(receiver.Sync.TimingOffset);
startIdx=1+max(0,round(tOff));
candidateStart=double(receiver.Sync.SelectedCandidateStartSymbol);
symbolWithinSlot=mod(candidateStart,14);
carrier=nrCarrierConfig;
carrier.NCellID=0; carrier.NSizeGrid=20; carrier.NStartGrid=0;
carrier.SubcarrierSpacing=double(bundle.Carrier.SubcarrierSpacing);
carrier.CyclicPrefix="normal";
carrier.NFrame=0; carrier.NSlot=floor(candidateStart/14);
sampling=sixgr.phy.frame.OFDMSamplingResolver.resolve( ...
    carrier,"SampleRate",bundle.SampleRateHz);
lengths=double(sampling.CyclicPrefixLengthsPerSlot(:).')+double(sampling.Nfft);
demodStart=startIdx-sum(lengths(1:symbolWithinSlot));
if demodStart>=1
    aligned=corrected(demodStart:end,:);
else
    aligned=[complex(zeros(1-demodStart,size(corrected,2),"like",corrected));corrected];
end
full=sixgr.phy.waveform.ofdmDemodulate(carrier,aligned, ...
    "Nfft",sampling.Nfft,"SampleRate",sampling.SampleRateHz);
columns=symbolWithinSlot+(1:4);
grid=full(:,columns,:);
end

function meta=localUnavailable(reason)
meta=struct("Available",false,"Reason",string(reason),"Source","", ...
    "Conditioning","correct_joint_sync_and_correct_pbch_dmrs_hypothesis", ...
    "NMSELinear",NaN,"NMSEDB",NaN,"SquaredErrorNumerator",NaN, ...
    "TruthEnergyDenominator",NaN,"HhatSize",zeros(1,3), ...
    "HtrueEffSize",zeros(1,3),"ComparedRE",0,"Normalized",true);
end
