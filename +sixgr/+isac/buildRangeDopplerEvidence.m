function mapTable = buildRangeDopplerEvidence(cfg,bundle,raw,delayClass)
%BUILDRANGEDOPPLEREVIDENCE Build a saved range-Doppler map from Rx samples.

% The map is evaluated from the same received sensing samples used by the
% trial detector.  It is not reconstructed from expected target values.

arguments
    cfg (1,1) struct
    bundle (1,1) struct
    raw (1,1) struct
    delayClass (1,1) string
end
received=raw.ReceivedSensing(:,1);
rxGrid=nrOFDMDemodulate(bundle.Carrier,received,"CyclicPrefixFraction", ...
    double(cfg.receiver.ofdmCyclicPrefixFraction));
mask=raw.PatternState.EffectiveMask;
symbols=find(any(mask,1));
if numel(symbols)<2
    error("sixgr:isac:InsufficientRangeDopplerOccasions", ...
        "At least two sensing occasions are required for a Doppler map.");
end
fs=double(bundle.OFDMInfo.SampleRate);
nFFT=double(bundle.OFDMInfo.Nfft);
cp=double(raw.Trial.CPSamples);
maxDelay=max(cp*1.75,double(raw.Trial.DelaySamples)+.25*cp);
delaySamples=unique(round(linspace(0,maxDelay, ...
    double(cfg.rangeDopplerEvidence.delayHypotheses)))).';
starts=[0;cumsum(double(bundle.CPLengths(:))+nFFT)];
times=(starts(symbols)+double(bundle.CPLengths(symbols)))/fs;
responseByOccasion=complex(zeros(numel(delaySamples),numel(symbols)));
physicalAll=(-size(mask,1)/2:size(mask,1)/2-1).'+12*double(bundle.Carrier.NStartGrid);
for i=1:numel(symbols)
    symbol=symbols(i);
    active=mask(:,symbol);
    product=rxGrid(active,symbol).*conj(raw.ReceiverReferenceGrid(active,symbol));
    physical=physicalAll(active);
    derotation=exp(1i*2*pi*(physical/nFFT)*delaySamples.');
    responseByOccasion(:,i)=transpose(product.'*derotation);
end
scsHz=double(bundle.Carrier.SubcarrierSpacing)*1e3;
maxNormalized=double(cfg.rangeDopplerEvidence.maximumNormalizedDoppler);
dopplerHz=linspace(-maxNormalized*scsHz,maxNormalized*scsHz, ...
    double(cfg.rangeDopplerEvidence.dopplerHypotheses)).';
dopplerSteering=exp(-1i*2*pi*times(:)*dopplerHz.');
power=abs(responseByOccasion*dopplerSteering).^2;
powerDb=10*log10(max(power,realmin)/max(power,[],'all'));
rangeScale=double(cfg.channel.propagationSpeedMps)/fs;
if contains(lower(string(raw.Trial.SensingMode)),"monostatic")
    rangeScale=rangeScale/2;
end
rangeM=delaySamples*rangeScale;
[rangeGrid,dopplerGrid]=ndgrid(rangeM,dopplerHz);
mapTable=table(repmat(delayClass,numel(power),1), ...
    repmat(string(raw.Trial.WaveformProfile),numel(power),1), ...
    repmat(string(raw.Trial.ReceiverProfile),numel(power),1), ...
    rangeGrid(:),dopplerGrid(:), ...
    power(:),powerDb(:),repmat(raw.Trial.ExpectedRangeM,numel(power),1), ...
    repmat(raw.Trial.ExpectedDopplerHz,numel(power),1), ...
    repmat(string(raw.Trial.TrialId),numel(power),1), ...
    repmat(string(raw.Trial.ReceivedObservationSHA256),numel(power),1), ...
    'VariableNames',{'DelayClass','WaveformProfile','ReceiverProfile', ...
    'RangeM','DopplerHz','PowerLinear', ...
    'PowerRelativeDb','ExpectedRangeM','ExpectedDopplerHz','TrialId', ...
    'ReceiveWaveformSHA256'});
end
