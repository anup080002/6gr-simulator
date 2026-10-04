function evidence=receiveSlotSupport(pathFilters,trimSamples,nfft,cpLengths,symbolsPerSlot,absoluteSlot0,receiveSymbols0,cpFraction)
%RECEIVESLOTSUPPORT Committed source slots needed by actual receive FFTs.
% The CP vector covers a repeating subframe, not necessarily one slot.
% Keep every nonzero filter tap. Interior-symbol leakage need not cross a
% slot boundary; a last-symbol FFT can require a following committed slot.
arguments
    pathFilters (:,:) double {mustBeFinite}
    trimSamples (1,1) double {mustBeInteger,mustBeNonnegative,mustBeFinite}
    nfft (1,1) double {mustBeInteger,mustBePositive,mustBeFinite}
    cpLengths double {mustBeInteger,mustBePositive,mustBeFinite}
    symbolsPerSlot (1,1) double {mustBeInteger,mustBePositive,mustBeFinite}
    absoluteSlot0 (1,1) double {mustBeInteger,mustBeNonnegative,mustBeFinite}
    receiveSymbols0 double {mustBeInteger,mustBeNonnegative,mustBeFinite}
    cpFraction (1,1) double {mustBeFinite,mustBeGreaterThanOrEqual(cpFraction,0),mustBeLessThanOrEqual(cpFraction,1)}
end
assert(isvector(cpLengths) && ~isempty(cpLengths) && mod(numel(cpLengths),symbolsPerSlot)==0 && ...
    isvector(receiveSymbols0) && ~isempty(receiveSymbols0) && all(receiveSymbols0<symbolsPerSlot), ...
    'sixgr:phy:waveform:ReceiveSlotClock','Require complete subframe CP lengths and actual in-slot receive symbols.');
cp=reshape(cpLengths,symbolsPerSlot,[]);
slotInSubframe=mod(absoluteSlot0,size(cp,2))+1;
currentCP=cp(:,slotInSubframe).';
support=sixgr.phy.waveform.channelCyclicPrefixSupport(pathFilters,trimSamples,currentCP,cpFraction);
lengths=nfft+currentCP;
starts=[0 cumsum(lengths(1:end-1))];
symbols=unique(receiveSymbols0(:).');
fftStart=starts(symbols+1)+fix(cpFraction*currentCP(symbols+1));
first=min(fftStart-support.LatestRelativeFilterTap_samples);
last=max(fftStart+nfft-1-support.EarliestRelativeFilterTap_samples);
slotLengths=sum(nfft+cp,1);
previous=0; firstBoundary=0;
while first<firstBoundary
    previous=previous+1;
    firstBoundary=firstBoundary-slotLengths(mod(absoluteSlot0-previous,size(cp,2))+1);
end
following=0; endBoundary=slotLengths(slotInSubframe);
while last>=endBoundary
    following=following+1;
    endBoundary=endBoundary+slotLengths(mod(absoluteSlot0+following,size(cp,2))+1);
end
evidence=struct('Schema',"sixgr.receive_slot_support/v1", ...
    'Source',"native_filter_support_and_selected_receive_fft_windows", ...
    'ObservationAbsoluteSlot0',absoluteSlot0,'ReceiveSymbols0Based',symbols, ...
    'FirstRequiredSourceSample0RelativeToSlot',first, ...
    'LastRequiredSourceSample0RelativeToSlot',last, ...
    'CurrentSlotSamples',sum(lengths),'RequiredPreviousSlots',previous, ...
    'RequiredFollowingSlots',following,'RequiredCommittedThroughTTI',absoluteSlot0+1+following, ...
    'PreSimulationSourceSamplesRequired',firstBoundary<0 && absoluteSlot0<previous, ...
    'ChannelCyclicPrefixSupport',support,'WaveformMeasured',false, ...
    'ResidualISIICIIncluded',false,'StatisticalCalibrationQualified',false);
end
