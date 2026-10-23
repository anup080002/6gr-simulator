function [aligned,evidence] = alignULReferenceObservation(carrier,waveform,indices,symbols,searchWindow,resourceIDs)
% Practical received-reference timing, never a TX/channel-delay oracle.
% The observation owner declares a bounded receiver search interval in
% samples. Only complete actual OFDM samples are extracted; no RX padding.
validateattributes(waveform,{'single','double'},{'2d','nonempty','finite'});
validateattributes(searchWindow,{'numeric'},{'real','finite','integer','nonnegative','numel',2});
searchWindow=double(searchWindow(:).');
assert(searchWindow(1)<=searchWindow(2), ...
    'sixgr:phy:sync:InvalidULReceiveSearchWindow','Receiver search endpoints must be ordered.');
info=nrOFDMInfo(carrier);
symbolsPerSlot=double(carrier.SymbolsPerSlot);
localSlot=mod(double(carrier.NSlot),double(carrier.SlotsPerSubframe));
count=sum(double(info.SymbolLengths(localSlot*symbolsPerSlot+(1:symbolsPerSlot))));
assert(size(waveform,1)>=count+searchWindow(2), ...
    'sixgr:phy:sync:IncompleteULReferenceObservation', ...
    'The actual capture must contain a full slot for every allowed timing hypothesis.');
assert(~isempty(indices) && ~isempty(symbols), ...
    'sixgr:phy:sync:MissingULReference','Timing acquisition requires receiver-known reference REs.');
offsets=(searchWindow(1):searchWindow(2)).';
resourceEvidence=struct();
if nargin>=6
    % Installed resources can use independent beam channels. Combine their
    % detected energies, not their complex reference correlations. Existing
    % single-resource callers retain the native timing behavior below.
    [energy,resourceEvidence]=sixgr.phy.sync.referenceResourceTimingEnergy( ...
        carrier,waveform,indices,symbols,searchWindow,resourceIDs);
else
    [~,magnitude]=nrTimingEstimate(carrier,waveform,indices,symbols);
    assert(size(magnitude,1)>searchWindow(2), ...
        'sixgr:phy:sync:IncompleteULTimingCorrelation','Correlation must cover the declared receive search window.');
    % Noncoherent combining does not assume equal phase across RX branches.
    energy=sum(abs(magnitude(offsets+1,:)).^2,2);
end
[rawPeak,rawIndex]=max(energy);
score=energy;
if nargin>=6
    % CSI-RS comb/CDM correlations can alias by a substantial FFT fraction.
    % Resolve them with independent CP consistency on the SAME RX capture,
    % before estimating CFO. Never clamp to an injected/expected delay.
    % The product is an explicit receiver selection metric, not pilot power,
    % a 3GPP-mandated algorithm, or a detector qualification probability.
    [cpCoherence,cpEvidence]=sixgr.phy.sync.receivedCPTimingCoherence( ...
        carrier,waveform,offsets);
    score=energy.*cast(cpCoherence,'like',energy);
end
[peak,k]=max(score);
assert(isfinite(peak) && peak>0, ...
    'sixgr:phy:sync:ULReferenceTimingUnavailable','No received reference correlation is available.');
offset=offsets(k);
aligned=waveform(offset+(1:count),:);
evidence=struct('TimingOffsetSamples',offset,'AppliedTimingCorrectionSamples',offset, ...
    'TimingSource',"received_reference_correlation_bounded_search", ...
    'SearchWindowSamples',searchWindow,'CorrelationPeakEnergy',energy(k), ...
    'TimingSearchHypothesisCount',numel(offsets), ...
    'TimingAcquisitionPerformed',numel(offsets)>1, ...
    'InputSampleCount',size(waveform,1),'DemodulatedSampleCount',count, ...
    'OracleTimingUsed',false,'ReceiverZeroPaddingUsed',false);
if nargin>=6
    evidence.TimingSource="received_per_resource_noncoherent_correlation_bounded_search";
    evidence.ReferenceResourceEvidence=resourceEvidence;
    evidence.TimingSelectionMetric="reference_energy_times_received_cp_coherence_squared";
    evidence.TimingSelectionScore=peak;
    evidence.RawReferencePeakOffsetSamples=offsets(rawIndex);
    evidence.RawReferencePeakEnergy=rawPeak;
    evidence.SelectedCPCoherenceSquared=cpCoherence(k);
    evidence.RawReferencePeakCPCoherenceSquared=cpCoherence(rawIndex);
    evidence.CyclicPrefixTimingEvidence=cpEvidence;
end
end
