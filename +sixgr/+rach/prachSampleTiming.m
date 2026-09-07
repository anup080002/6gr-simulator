function timing=prachSampleTiming(carrier,prach)
% Actual PRACH OFDM sample extent on the absolute radio clock. RE symbol
% indices belong to nrPRACHGrid, NOT the carrier's OFDM symbol grid.
info=nrPRACHOFDMInfo(carrier,prach,'Windowing',0);
indices=nrPRACHIndices(carrier,prach,'IndexStyle','subscript','IndexBase','0based');
if isempty(indices)
    error('sixgr:rach:InactivePRACHSampleTiming','An inactive PRACH occasion has no transmitted support.');
end
symbols=unique(double(indices(:,2)))+1;
lengths=double(info.SymbolLengths(:)); cp=double(info.CyclicPrefixLengths(:));
guard=double(info.GuardLengths(:));
if any(symbols<1 | symbols>numel(lengths)) || numel(cp)~=numel(lengths) || numel(guard)~=numel(lengths)
    error('sixgr:rach:PRACHSampleLayoutMismatch','PRACH REs and OFDM lengths must describe the same waveform.');
end
edges=double(info.OffsetLength)+[0;cumsum(lengths)];
fs=double(info.SampleRate);
origin=double(prach.NPRACHSlot)*double(prach.SubframesPerPRACHSlot)*1e-3;
ticksPerSample=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
originSample=origin*fs;
if ticksPerSample~=fix(ticksPerSample) || ...
        abs(originSample-round(originSample))>8*eps(max(1,originSample))
    error('sixgr:rach:PRACHSampleClockNotExact','PRACH sample boundaries must map exactly to Tc.');
end
timing=struct('Source','nrPRACHOFDMInfo_actual_CP_useful_samples_excluding_guard', ...
    'SampleRateHz',fs,'WaveformStartTime_s',origin, ...
    'WaveformEndTimeExclusive_s',origin+edges(end)/fs, ...
    'ActiveStartTime_s',origin+edges(symbols(1))/fs, ...
    'ActiveEndTimeExclusive_s',origin+(edges(symbols(end)+1)-guard(symbols(end)))/fs);
timing.ActiveEndTicksExclusive=int64(round(originSample)+ ...
    edges(symbols(end)+1)-guard(symbols(end)))*int64(ticksPerSample);
% Resource reservations cover every carrier symbol touched by the actual
% CP/useful samples. Do not scale PRACH-symbol numbers or round away a
% partial-symbol overlap. Guard zeros are not transmitted PRACH resources.
% Higher numerologies have unequal sample counts in adjacent slots due to
% the longer CP at each half-subframe. Anchor at the exact subframe edge.
subframe=floor(origin*1e3+8*eps(max(1,origin*1e3)));
firstSlot=subframe*double(carrier.SlotsPerSubframe);
c=carrier; c.NSlot=firstSlot;
ofdm=nrOFDMInfo(c); n=double(c.SymbolsPerSlot);
subframeLengths=double(ofdm.SymbolLengths(:));
edgesCarrier=subframe*1e-3; slot=firstSlot;
while edgesCarrier(end)<timing.ActiveEndTimeExclusive_s-16*eps(max(1,timing.ActiveEndTimeExclusive_s))
    ids=mod(slot,double(c.SlotsPerSubframe))*n+(1:n);
    edgesCarrier=[edgesCarrier edgesCarrier(end)+cumsum(subframeLengths(ids)).'/double(ofdm.SampleRate)]; %#ok<AGROW>
    slot=slot+1;
end
tol=16*eps(max(1,edgesCarrier(end)));
touched=find(edgesCarrier(1:end-1)<timing.ActiveEndTimeExclusive_s-tol & ...
    edgesCarrier(2:end)>timing.ActiveStartTime_s+tol);
if isempty(touched)
    error('sixgr:rach:PRACHCarrierSupportEmpty','Active PRACH samples must intersect the carrier clock.');
end
timing.CarrierSlot0=firstSlot+floor((touched(1)-1)/n);
timing.CarrierStartSymbol=mod(touched(1)-1,n);
timing.CarrierDurationSymbols=touched(end)-touched(1)+1;
end
