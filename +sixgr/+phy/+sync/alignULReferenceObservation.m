function [aligned,evidence] = alignULReferenceObservation(carrier,waveform,indices,symbols,searchWindow)
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
[~,magnitude]=nrTimingEstimate(carrier,waveform,indices,symbols);
offsets=(searchWindow(1):searchWindow(2)).';
assert(size(magnitude,1)>searchWindow(2), ...
    'sixgr:phy:sync:IncompleteULTimingCorrelation','Correlation must cover the declared receive search window.');
% Noncoherent combining does not assume equal phase across RX branches.
energy=sum(abs(magnitude(offsets+1,:)).^2,2);
[peak,k]=max(energy);
assert(isfinite(peak) && peak>0, ...
    'sixgr:phy:sync:ULReferenceTimingUnavailable','No received reference correlation is available.');
offset=offsets(k);
aligned=waveform(offset+(1:count),:);
evidence=struct('TimingOffsetSamples',offset,'AppliedTimingCorrectionSamples',offset, ...
    'TimingSource',"received_reference_correlation_bounded_search", ...
    'SearchWindowSamples',searchWindow,'CorrelationPeakEnergy',peak, ...
    'InputSampleCount',size(waveform,1),'DemodulatedSampleCount',count, ...
    'OracleTimingUsed',false,'ReceiverZeroPaddingUsed',false);
end
