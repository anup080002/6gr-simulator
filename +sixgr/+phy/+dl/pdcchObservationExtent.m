function extent=pdcchObservationExtent(carrier,indices,ofdmInfo)
% Actual monitored REs define the receive prefix needed for a DCI decision.
% This is not a whole-slot timeout and does not authorize zero padding.
values=localIndices(indices);
validateattributes(values,{'numeric'},{'real','finite','integer','positive','nonempty'});
k=12*double(carrier.NSizeGrid); l=double(carrier.SymbolsPerSlot);
symbols=unique(floor(mod(double(values(:))-1,k*l)/k)).';
nfft=double(ofdmInfo.Nfft); fs=double(ofdmInfo.SampleRate);
validateattributes(nfft,{'numeric'},{'scalar','finite','integer','positive'});
validateattributes(fs,{'numeric'},{'scalar','finite','positive'});
slots=double(ofdmInfo.SlotsPerSubframe);
validateattributes(slots,{'numeric'},{'scalar','finite','integer','positive'});
lengths=double(ofdmInfo.SymbolLengths(:));
if numel(lengths)~=l*slots || any(~isfinite(lengths) | lengths<=0 | lengths~=fix(lengths)) || ...
        abs(fs-nfft*double(carrier.SubcarrierSpacing)*1000)>1e-9*fs
    error('sixgr:phy:pdcch:ObservationSamplingMismatch', ...
        'The actual OFDM symbol lengths, numerology and sample rate must agree.');
end
matrix=reshape(lengths,l,slots);
current=matrix(:,mod(double(carrier.NSlot),slots)+1);
extent=struct('MonitoredSymbols0Based',symbols,'LastMonitoredSymbol0Based',max(symbols), ...
    'MinimumReceiveSamples',sum(current(1:max(symbols)+1)), ...
    'SlotSamples',sum(current),'SampleRateHz',fs, ...
    'Source',"actual_pdcch_candidate_and_dmrs_RE_symbols_plus_nrOFDMInfo_CP_lengths");
end

function values=localIndices(indices)
if iscell(indices)
    values=[];
    for k=1:numel(indices), values=[values;localIndices(indices{k})]; end %#ok<AGROW>
else
    values=indices(:);
end
end
