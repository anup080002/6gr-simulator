function [energy,evidence]=referenceResourceTimingEnergy( ...
        carrier,waveform,indices,symbols,searchWindow,resourceIDs)
%REFERENCERESOURCETIMINGENERGY Noncoherent timing across installed resources.
% Different CSI-RS resources can illuminate different beam channels. Do not
% coherently concatenate their reference waveforms before magnitude detection.
% E(tau) = sum_resource sum_rx |mag_resource(tau,rx)|^2, where each native
% nrTimingEstimate magnitude already sums reference-port magnitudes.
% This is a receiver algorithm, not a 3GPP-mandated timing estimator. Only
% installed reference REs/resource identities and actual RX samples enter it.
arguments
    carrier (1,1) nrCarrierConfig
    waveform {mustBeNumeric,mustBeFinite,mustBeNonempty}
    indices {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger,mustBePositive}
    symbols {mustBeNumeric,mustBeFinite,mustBeNonempty}
    searchWindow (1,2) double {mustBeInteger,mustBeNonnegative,mustBeFinite}
    resourceIDs {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger,mustBeNonnegative}
end
identifier='sixgr:phy:sync:InvalidReferenceResourceTiming';
assert(ismatrix(waveform) && isfloat(waveform) && ~issparse(waveform) && ...
    ~isempty(indices) && numel(indices)==numel(symbols) && ...
    numel(resourceIDs)==numel(indices) && searchWindow(1)<=searchWindow(2), ...
    identifier,'Bind every known reference RE to one installed resource and an ordered search window.');
indices=indices(:); symbols=symbols(:); resourceIDs=double(resourceIDs(:));
assert(numel(unique(indices))==numel(indices),identifier, ...
    'Overlapping reference indices cannot be silently overwritten in the timing reference grid.');
info=nrOFDMInfo(carrier);
localSlot=mod(double(carrier.NSlot),double(carrier.SlotsPerSubframe));
slotSymbols=localSlot*double(carrier.SymbolsPerSlot)+(1:double(carrier.SymbolsPerSlot));
slotSamples=sum(double(info.SymbolLengths(slotSymbols)));
assert(size(waveform,1)>=slotSamples+searchWindow(2), ...
    'sixgr:phy:sync:IncompleteULReferenceObservation', ...
    'Every allowed timing hypothesis must retain a complete slot of actual received samples.');
offsets=(searchWindow(1):searchWindow(2)).';
groups=unique(resourceIDs,'stable');
energy=zeros(numel(offsets),1,class(waveform));
resourcePeaks=zeros(numel(groups),1); resourceOffsets=zeros(numel(groups),1);
referenceCounts=zeros(numel(groups),1);
for n=1:numel(groups)
    select=resourceIDs==groups(n);
    assert(any(abs(symbols(select))>0),identifier, ...
        'Every installed timing resource must contain a nonzero known reference.');
    [~,magnitude]=nrTimingEstimate(carrier,waveform,indices(select),symbols(select));
    assert(size(magnitude,1)>searchWindow(2), ...
        'sixgr:phy:sync:IncompleteULTimingCorrelation', ...
        'Each resource correlation must cover the whole receiver search window.');
    perResource=sum(abs(magnitude(offsets+1,:)).^2,2);
    assert(all(isfinite(perResource)),identifier,'Received correlation energy must be finite.');
    energy=energy+perResource;
    [resourcePeaks(n),peakIndex]=max(perResource);
    resourceOffsets(n)=offsets(peakIndex);
    referenceCounts(n)=nnz(select);
end
evidence=struct('Method',"per_resource_noncoherent_received_reference_energy", ...
    'ResourceIDs',groups,'ResourceCount',numel(groups), ...
    'ReferenceCounts',referenceCounts,'ResourcePeakOffsetsSamples',resourceOffsets, ...
    'ResourcePeakEnergies',resourcePeaks,'NativeCorrelationCalls',numel(groups), ...
    'SearchWindowSamples',searchWindow,'TimingSearchHypothesisCount',numel(offsets), ...
    'InputSampleCount',size(waveform,1),'CompleteSlotSampleCount',slotSamples, ...
    'ReferenceAuthority',"receiver_installed_resource_configuration", ...
    'OracleTimingUsed',false,'ReceiverZeroPaddingUsed',false, ...
    'EstimatorRole',"receiver_algorithm_not_normative_3gpp_requirement");
end
