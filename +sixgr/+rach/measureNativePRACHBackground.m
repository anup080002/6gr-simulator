function [evidence,trace]=measureNativePRACHBackground(rx,cfg,occasion,preamble)
% Receiver-only diagnostic; never supplies nrPRACHDetect's decision metric.
% Useful-symbol coordinates come from native NR PRACH OFDM, not carrier CP.
% Repetition differences measure noise PLUS inter-repetition variation.
ref=sixgr.rach.generatePRACHWaveform(cfg,'Occasion',occasion,'PreambleIndex',preamble);
info=ref.OFDMInfo; prach=ref.PRACH; nfft=double(info.Nfft);
symbol=double(prach.SymbolLocation)-numel(info.SymbolLengths)*double(prach.ActivePRACHSlot);
assert(symbol>=0 && symbol<numel(info.CyclicPrefixLengths), ...
    'sixgr:rach:PRACHBackgroundCoordinates','Resolve the native useful-symbol origin.');
start=double(info.OffsetLength)+sum(double(info.SymbolLengths(1:symbol)))+ ...
    double(info.CyclicPrefixLengths(symbol+1));
repetitions=double(prach.PRACHDuration)-2*double(string(prach.Format)=="C2");
validateattributes(repetitions,{'numeric'},{'scalar','integer','positive'});
nrx=size(rx,2);
evidence=struct('NoiseFloor',NaN,'Estimator',"disjoint_received_repetition_differences", ...
    'Definition',"original_energy_normalized_correlation_noise_plus_inter_repetition_variation", ...
    'Status',"unavailable_incomplete_native_useful_symbols", ...
    'PairCount',floor(repetitions/2),'RxAntennaCount',nrx,'Normalization',NaN, ...
    'SampleEquivalentVariance',NaN,'SampleRateHz',double(info.SampleRate), ...
    'UsefulStartSample0',start,'NFFT',nfft,'Repetitions',repetitions, ...
    'ReferencePreamble',double(preamble),'ReferenceEnergy',NaN, ...
    'OccupiedReceivedEnergy',NaN,'AuxiliaryPeakMetric',NaN);
trace=struct();
if size(rx,1)<start+repetitions*nfft, return; end
reference=ref.Waveform(start+(1:nfft),1);
rf=fft(reference); occupied=abs(rf)>max(abs(rf))*1e-8;
assert(any(occupied),'sixgr:rach:EmptyRepetitionReference','Native PRACH reference has no occupied tones.');
referenceEnergy=sum(abs(reference).^2);
energy=0; correlation=zeros(nfft,1); floorNumerator=0; variance=0;
% Exact branch accumulation bounds temporary storage at one RX branch.
% No spatial averaging, downsampling or synthetic channel is used.
for branch=1:nrx
    y=reshape(rx(start+(1:repetitions*nfft),branch),nfft,repetitions);
    yf=fft(y,[],1);
    energy=energy+sum(abs(yf(occupied,:)).^2,'all')/nfft;
    correlation=correlation+sum(abs(ifft(yf.*conj(rf),[],1)).^2,2);
    measured=sixgr.rach.measurePRACHRepetitionBackground(y,reference,repetitions,1);
    floorNumerator=floorNumerator+measured.NoiseFloor;
    variance=variance+measured.SampleEquivalentVariance;
end
evidence.ReferenceEnergy=referenceEnergy;
evidence.OccupiedReceivedEnergy=energy;
evidence.Normalization=energy*referenceEnergy;
if ~(isfinite(evidence.Normalization) && evidence.Normalization>0)
    evidence.Status="unavailable_zero_received_reference_energy";
    return;
end
evidence.NoiseFloor=floorNumerator/evidence.Normalization;
evidence.SampleEquivalentVariance=variance/nrx;
evidence.Status=measured.Status;
correlation=correlation/evidence.Normalization;
[evidence.AuxiliaryPeakMetric,peak]=max(correlation);
trace=struct('PreambleIndex',double(preamble),'LagSamples',(0:nfft-1).', ...
    'CorrelationAbs',correlation,'PeakLagSamples',double(peak-1), ...
    'Threshold',NaN,'ThresholdSource',"not_applicable_auxiliary_repetition_matched_filter", ...
    'NoiseFloor',evidence.NoiseFloor,'NoiseFloorEvidence',evidence, ...
    'TraceStatus',"native_useful_repetition_auxiliary_correlation", ...
    'MetricDomain',"sum_RX_repetition_cyclic_matched_filter_power_over_original_occupied_energy", ...
    'LagReference',"cyclic_delay_relative_to_native_PRACH_useful_symbol_origin", ...
    'SampleRateHz',double(info.SampleRate));
end
