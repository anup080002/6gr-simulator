function clock=ssbEmittedSymbolClock(portGrid,waveformSamples,scsKHz,sampleRateHz)
% Native normal-CP SS/PBCH symbol support in the original local TX buffer.
% The Toolbox grid may include a zero-padded frame tail beyond the emitted
% waveform. It may not add transmitted REs there, nor end within a symbol.
validateattributes(waveformSamples,{'numeric'},{'scalar','real','finite','integer','positive'});
validateattributes(scsKHz,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(sampleRateHz,{'numeric'},{'scalar','real','finite','positive'});
assert(isnumeric(portGrid) && size(portGrid,1)==240 && size(portGrid,2)>0, ...
    'sixgr:truth:SSBNativeSampleClockMismatch','Retain the original native SS/PBCH port grid.');
native=nrCarrierConfig('NSizeGrid',20,'SubcarrierSpacing',double(scsKHz), ...
    'CyclicPrefix','normal');
ofdm=nrOFDMInfo(native,'SampleRate',double(sampleRateHz), ...
    'Nfft',double(sampleRateHz)/(double(scsKHz)*1000));
lengths=double(ofdm.SymbolLengths(:)); cp=double(ofdm.CyclicPrefixLengths(:));
nSymbols=size(portGrid,2); count=ceil(nSymbols/numel(lengths));
lengths=repmat(lengths,count,1); cp=repmat(cp,count,1);
starts=[0;cumsum(lengths(1:nSymbols-1))];
ends=starts+lengths(1:nSymbols);
outside=ends>double(waveformSamples);
assert(any(ends==double(waveformSamples)) && ~any(portGrid(:,outside,:)~=0,'all'), ...
    'sixgr:truth:SSBNativeSampleClockMismatch', ...
    'The emitted waveform must end on its native symbol clock and contain every nonzero SSB grid symbol.');
clock=struct('CPStartSample0',starts,'CyclicPrefixLengths',cp(1:nSymbols), ...
    'UsefulEndSampleExclusive0',ends,'Nfft',double(ofdm.Nfft), ...
    'EmittedSymbolMask',~outside);
end
