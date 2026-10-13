function [detections,background]=detectUnrestrictedPreambles(rx,cfg,occasion,template,maxDelayUs)
% AWGN multi-preamble receiver with measured successive interference removal.
% Search every RAPID, fit its amplitude from received IQ per antenna and
% repetition, subtract that component, repeat. Original energy normalization
% is frozen: subtraction cannot inflate noise. No TX identity/count/gain is
% used. Multipath and restricted-set support are not claimed by this path.
assert(string(occasion.PRACH.RestrictedSet)=="UnrestrictedSet", ...
    'sixgr:rach:MultiPRACHRestrictedSet','Multi-preamble reception currently requires UnrestrictedSet.');
validateattributes(maxDelayUs,{'numeric'},{'scalar','real','finite','positive'});
assert(upper(string(cfg.ChannelModel))=="AWGN", ...
    'sixgr:rach:MultiPRACHFadingNotQualified','Flat-component PRACH cancellation is AWGN-only.');
template.NoiseFloorEvidence=struct();
detections=repmat(template,0,1); bank=cell(64,1);
for index=0:63
    ref=sixgr.rach.generatePRACHWaveform(cfg,'Occasion',occasion,'PreambleIndex',index);
    info=ref.OFDMInfo; nfft=double(info.Nfft);
    p=ref.PRACH;
    [~,sequenceInfo]=nrPRACH(ref.Carrier,p);
    scale=double(info.SampleRate)/(double(p.LRA)*double(p.SubcarrierSpacing)*1e3);
    ncs=double(sequenceInfo.NumCyclicShifts);
    % The native PRACH useful-symbol clock, not carrier-slot sample counts.
    symbol=double(p.SymbolLocation)-numel(info.SymbolLengths)*double(p.ActivePRACHSlot);
    start=double(info.OffsetLength)+sum(double(info.SymbolLengths(1:symbol)))+ ...
        double(info.CyclicPrefixLengths(symbol+1));
    repetitions=double(p.PRACHDuration)-2*double(string(p.Format)=="C2");
    needed=start+repetitions*nfft;
    assert(size(rx,1)>=needed,'sixgr:rach:IncompleteMultiPRACHCapture', ...
        'A completed received PRACH observation must contain all useful symbols.');
    reference=ref.Waveform(start+(1:nfft),1);
    spectrum=fft(reference);
    % Restrict received-energy normalization to the actual PRACH tones.
    occupied=abs(spectrum)>max(abs(spectrum))*1e-8;
    received=reshape(rx(start+(1:repetitions*nfft),:),nfft,[]);
    receivedFFT=fft(received,[],1);
    energy=sum(abs(receivedFFT(occupied,:)).^2,'all')/nfft;
    % One main-lobe sample interval below zero is the boundary tolerance;
    % the next cyclic shift is never included in this candidate's window.
    if ncs==0
        last=nfft-1;
    else
        last=ceil((ncs-1)*scale)-1;
    end
    configuredLast=ceil(maxDelayUs*double(info.SampleRate)*1e-6);
    assert(configuredLast<=last,'sixgr:rach:MultiPRACHDelayOutsideZCZ', ...
        'Configured receive delay exceeds the unambiguous preamble timing window.');
    lags=(ceil(-scale):configuredLast).';
    bank{index+1}=struct('Reference',reference,'FFT',spectrum,'Lags',lags, ...
        'Positions',mod(lags,nfft)+1,'ReferenceEnergy',sum(abs(reference).^2), ...
        'Normalization',energy*sum(abs(reference).^2)+eps);
end
% Also return a measured background for an empty/no-detection occasion.
% Reference 0 is a configured public candidate, not a transmitted identity.
background=sixgr.rach.measurePRACHRepetitionBackground(received, ...
    bank{1}.Reference,repetitions,bank{1}.Normalization);
residual=received; remaining=true(64,1);
for iteration=1:64
    rf=fft(residual,[],1); peaks=-inf(64,1); offsets=zeros(64,1); traces=cell(64,1);
    for k=find(remaining).'
        b=bank{k}; metric=sum(abs(ifft(rf.*conj(b.FFT),[],1)).^2,2)/b.Normalization;
        traces{k}=metric(b.Positions);
        [peaks(k),at]=max(traces{k}); offsets(k)=b.Lags(at);
    end
    [peak,k]=max(peaks);
    if ~isfinite(peak) || peak<template.Threshold, break; end
    b=bank{k}; remaining(k)=false; index=k-1; lags=b.Lags;
    shifted=circshift(b.Reference,offsets(k));
    amplitude=(shifted'*residual)/b.ReferenceEnergy;
    residual=residual-shifted*amplitude;
    d=template;
    d.Detected=true; d.DetectedPreambleIndex=index; d.DetectedPreambleIndexRaw=index;
    d.PreambleIndexFromPeak=index; d.TimingOffsetSamples=max(0,offsets(k));
    d.PeakLagSamples=d.TimingOffsetSamples; d.PeakMetric=peak;
    d.PeakToThresholdRatio=peak/template.Threshold;
    d.TimingSearchWindow=struct('MinLagSamples',lags(1),'MaxLagSamples',lags(end), ...
        'Source',"configured_cell_multi_preamble_arrival_window",'SearchApplied',true);
    d.DetectorBackend="sixgr_awgn_unrestricted_measured_sic_original_energy";
    d.ThresholdSource="configured_fixed_candidate_cyclic_correlation";
    if string(template.ThresholdMode)=="auto"
        d.ThresholdSource="nrPRACHDetect_format_threshold_applied_to_original_energy_sic";
    end
    d.NoiseFloorEvidence=sixgr.rach.measurePRACHRepetitionBackground(received, ...
        b.Reference,repetitions,b.Normalization);
    d.PDPNoiseFloor=d.NoiseFloorEvidence.NoiseFloor;
    d.PeakToNoiseRatio=NaN; d.PeakToNoiseRatio_dB=NaN;
    if isfinite(d.PDPNoiseFloor) && d.PDPNoiseFloor>0
        d.PeakToNoiseRatio=peak/d.PDPNoiseFloor;
        d.PeakToNoiseRatio_dB=10*log10(d.PeakToNoiseRatio);
    end
    peaks(~isfinite(peaks))=NaN;
    d.CorrelationPeaks=peaks; d.CandidatePreambles=(0:63).'; d.CandidateCount=64;
    d.MultiCandidateAboveThreshold=false; d.CandidatesAboveThreshold=1;
    d.FrequencyEstimate=struct('Valid',false,'EstimateHz',NaN, ...
        'Estimator',"unavailable_multi_preamble_frequency_estimator_not_executed");
    d.DetInfo=struct('DetectorBackend',d.DetectorBackend,'CancellationIteration',iteration, ...
        'ReceivedComplexAmplitude',amplitude, ...
        'DetectionThreshold',d.Threshold,'DetectedPreambleIndicesRaw',index, ...
        'DetectedTimingOffsetsRaw',d.TimingOffsetSamples, ...
        'DecisionSource',"received_samples_installed_preamble_bank_original_energy_sic");
    d.CorrelationTrace=struct('PreambleIndex',index,'LagSamples',lags, ...
        'CorrelationAbs',traces{k},'Threshold',d.Threshold, ...
        'ThresholdSource',d.ThresholdSource,'PeakLagSamples',d.TimingOffsetSamples, ...
        'NoiseFloor',d.PDPNoiseFloor,'NoiseFloorEvidence',d.NoiseFloorEvidence, ...
        'TraceStatus',"received_residual_correlation_original_energy_normalized");
    detections(end+1,1)=d; %#ok<AGROW>
end
end
