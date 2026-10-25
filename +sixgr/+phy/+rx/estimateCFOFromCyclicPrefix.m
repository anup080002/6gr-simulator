function [cfoHz, info] = estimateCFOFromCyclicPrefix(rxWaveform, ofdmInfo, sampleRateHz, observation)
%estimateCFOFromCyclicPrefix Estimate carrier-frequency offset from OFDM CP.
%
% The cyclic prefix repeats the last samples of the useful OFDM symbol. A
% carrier-frequency offset creates a phase rotation over the Nfft-sample
% separation between those two copies:
%   CFO_Hz = angle(sum(conj(CP) .* tail)) * Fs / (2*pi*Nfft)
% This is a fractional estimator, unambiguous only within +/- Fs/(2*Nfft).
% Canonical OFDM metadata identifies the captured slot. nrOFDMInfo's full
% subframe CP vector alone cannot identify a nonzero captured slot.
% An explicit received_coherence_window policy searches a fixed-width CP
% interval using received normalized correlation, never TX/channel truth.
% Its white-noise null gate includes a union bound over searched windows.
% This is a receiver algorithm, not a 3GPP-mandated estimator or a channel-
% delay support measurement. Fractional CFO ambiguity remains unchanged.
if nargin<4, observation=struct(); end

info = struct( ...
    "EstimateAvailable", false, ...
    "EstimatedCFO_Hz", NaN, ...
    "Status", "not_computed", ...
    "NumSymbolsUsed", 0, ...
    "Nfft", NaN, ...
    "SampleRate_Hz", NaN, ...
    "ClockSource", "unavailable", ...
    "CorrelationMagnitude", NaN, ...
    "ObservationPolicy", "full_prefix", ...
    "ObservationCoherenceSquared", NaN, ...
    "ObservationStartFromUsefulSymbol_samples", NaN, ...
    "ObservationLength_samples", NaN, ...
    "ObservationPairCount", 0, ...
    "ObservationWindowCount", 1, ...
    "NoiseOnlyCoherenceThreshold", NaN);
cfoHz = NaN;
assert(isstruct(observation) && isscalar(observation), ...
    'sixgr:phy:rx:CFOCPObservationPolicy','Use one explicit CP observation policy.');
policy=string(sixgr.util.structGet(observation,'Policy','full_prefix'));
assert(isscalar(policy) && any(policy==["full_prefix","received_coherence_window"]), ...
    'sixgr:phy:rx:CFOCPObservationPolicy','Unknown CP observation policy.');
info.ObservationPolicy=policy;

if isempty(rxWaveform) || ~isnumeric(rxWaveform) || ~ismatrix(rxWaveform)
    info.Status = "empty_or_non_numeric_waveform";
    return;
end
sampleRateHz = double(sampleRateHz);
if ~(isscalar(sampleRateHz) && isfinite(sampleRateHz) && sampleRateHz > 0)
    sampleRateHz = localFirstFinite(ofdmInfo, ["SampleRate","SampleRate_Hz"], NaN);
end
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    info.Status = "sample_rate_unavailable";
    return;
end
if ~localClockMatches(ofdmInfo,["SampleRate","SampleRate_Hz","SampleRateHz"],sampleRateHz)
    info.Status = "sample_rate_metadata_mismatch";
    return;
end

nfft = localFirstFinite(ofdmInfo, ["Nfft","FFTLength","NFFT"], NaN);
if ~(isreal(nfft) && isfinite(nfft) && nfft > 0 && nfft == fix(nfft))
    info.Status = "nfft_unavailable";
    return;
end
if ~localClockMatches(ofdmInfo,["Nfft","FFTLength","NFFT"],nfft)
    info.Status = "nfft_metadata_mismatch";
    return;
end

resolved = sixgr.util.structGet(ofdmInfo,"OFDMSamplingResolution",struct());
if isstruct(resolved) && isscalar(resolved) && ~isempty(fieldnames(resolved))
    resolvedNfft=localFirstFinite(resolved,"Nfft",NaN);
    resolvedRate=localFirstFinite(resolved,["SampleRateHz","SampleRate"],NaN);
    if ~isequal(resolvedNfft,nfft) || ~isequal(resolvedRate,sampleRateHz) || ...
            ~localClockMatches(resolved,["SampleRateHz","SampleRate"],sampleRateHz)
        info.Status = "captured_slot_clock_mismatch";
        return;
    end
    cpLens=localFirstVector(resolved,"CyclicPrefixLengthsPerSlot",[]);
    count=localFirstFinite(resolved,"SymbolsPerSlot",NaN);
    if isempty(cpLens) || numel(cpLens)~=count
        info.Status = "captured_slot_cyclic_prefix_metadata_invalid";
        return;
    end
    info.ClockSource="canonical_captured_slot";
else
    cpLens = localFirstVector(ofdmInfo, ...
        ["CyclicPrefixLengths","CyclicPrefixLength","CPLengths"], []);
    count=localFirstFinite(ofdmInfo,"SymbolsPerSlot",NaN);
    if isfinite(count) && numel(cpLens)>count
        info.Status = "captured_slot_authority_missing";
        return;
    end
    info.ClockSource="explicit_cp_vector";
end
if isempty(cpLens)
    info.Status = "cyclic_prefix_lengths_unavailable";
    return;
end
cpLens = double(cpLens(:));
if ~isreal(cpLens) || any(~isfinite(cpLens) | cpLens<=0 | ...
        cpLens>nfft | cpLens~=fix(cpLens))
    info.Status = "cyclic_prefix_lengths_invalid";
    return;
end
if info.ClockSource=="canonical_captured_slot" && ...
        ~isequal(sum(cpLens+nfft),localFirstFinite(resolved,"CurrentSlotSamples",NaN))
    info.Status="captured_slot_sample_count_mismatch";
    return;
end

x = double(rxWaveform);
if isvector(x)
    x = x(:);
end
nSamples = size(x, 1);
% Receiver-configured control symbols select CP pairs without concatenating
% symbols or changing their original OFDM sample positions. Absent selection
% preserves the existing full captured-slot estimator.
selectedSymbols=true(numel(cpLens),1);
if isfield(observation,'SymbolIndices0Based')
    selected=observation.SymbolIndices0Based;
    validateattributes(selected,{'numeric'},{'vector','real','finite','integer','nonnegative','nonempty','<',numel(cpLens)});
    assert(numel(unique(selected))==numel(selected), ...
        'sixgr:phy:rx:CFOCPObservationSymbols','Do not count repeated control symbols twice.');
    selectedSymbols(:)=false;
    selectedSymbols(double(selected)+1)=true;
    info.SymbolIndices0Based=double(selected(:).');
end
if policy=="received_coherence_window"
    assert(all(isfield(observation,{'WindowFraction','FalseAlarmProbability'})), ...
        'sixgr:phy:rx:CFOCPObservationPolicy','Declare CP window fraction and false-alarm probability.');
    fraction=double(observation.WindowFraction); alpha=double(observation.FalseAlarmProbability);
    validateattributes(fraction,{'double'},{'scalar','real','finite','>',0,'<=',1});
    validateattributes(alpha,{'double'},{'scalar','real','finite','>',0,'<',1});
    [corrSum,detail]=localReceivedWindow(x,cpLens,nfft,fraction,alpha,selectedSymbols);
    info.NumSymbolsUsed=detail.NumSymbols;
    info.Nfft=nfft; info.SampleRate_Hz=sampleRateHz;
    info.CorrelationMagnitude=abs(corrSum);
    info.ObservationCoherenceSquared=detail.CoherenceSquared;
    info.ObservationStartFromUsefulSymbol_samples=detail.StartFromUsefulSymbol;
    info.ObservationLength_samples=detail.Length;
    info.ObservationPairCount=detail.PairCount;
    info.ObservationWindowCount=detail.WindowCount;
    info.NoiseOnlyCoherenceThreshold=detail.Threshold;
    if ~detail.Available
        info.Status=detail.Status;
        return;
    end
    cfoHz=angle(corrSum)*sampleRateHz/(2*pi*nfft);
    info.EstimateAvailable=true; info.EstimatedCFO_Hz=cfoHz; info.Status="OK";
    return;
end
pos = 1;
corrSum = complex(0, 0);
numUsed = 0;
firstEnergy=0; secondEnergy=0; pairCount=0;
for sym = 1:numel(cpLens)
    cpLen = cpLens(sym);
    symLen = cpLen + nfft;
    if pos + symLen - 1 > nSamples
        break;
    end
    if ~selectedSymbols(sym)
        pos=pos+symLen;
        continue;
    end
    cp = x(pos:pos+cpLen-1, :);
    tailStart = pos + cpLen + nfft - cpLen;
    tail = x(tailStart:tailStart+cpLen-1, :);
    mask = isfinite(real(cp)) & isfinite(imag(cp)) & isfinite(real(tail)) & isfinite(imag(tail));
    if any(mask(:))
        corrSum = corrSum + sum(conj(cp(mask)) .* tail(mask), "all");
        firstEnergy=firstEnergy+sum(abs(cp(mask)).^2);
        secondEnergy=secondEnergy+sum(abs(tail(mask)).^2);
        pairCount=pairCount+nnz(mask);
        numUsed = numUsed + 1;
    end
    pos = pos + symLen;
end

info.NumSymbolsUsed = double(numUsed);
info.Nfft = double(nfft);
info.SampleRate_Hz = double(sampleRateHz);
info.CorrelationMagnitude = abs(corrSum);
info.ObservationPairCount=pairCount;
if firstEnergy>0 && secondEnergy>0
    info.ObservationCoherenceSquared=min(1,abs(corrSum/sqrt(firstEnergy)/sqrt(secondEnergy))^2);
end
if numUsed < 1 || ~(isfinite(real(corrSum)) && isfinite(imag(corrSum))) || abs(corrSum) <= eps
    info.Status = "insufficient_cp_correlation";
    return;
end

cfoHz = angle(corrSum) * double(sampleRateHz) / (2 * pi * double(nfft));
if ~isfinite(cfoHz)
    info.Status = "cfo_estimate_nonfinite";
    cfoHz = NaN;
    return;
end

info.EstimateAvailable = true;
info.EstimatedCFO_Hz = double(cfoHz);
info.Status = "OK";
end

function [selected,d]=localReceivedWindow(x,cpLens,nfft,fraction,alpha,selectedSymbols)
% Align CP observations to the useful-symbol boundary, not the start of a
% longer prefix. The same relative window is applied to every used symbol.
lengthCP=min(cpLens); width=max(1,ceil(fraction*lengthCP));
c=complex(zeros(lengthCP,1)); a=zeros(lengthCP,1); b=a; count=a;
d=struct('Available',false,'Status',"insufficient_cp_observation", ...
    'NumSymbols',0,'CoherenceSquared',NaN,'StartFromUsefulSymbol',NaN, ...
    'Length',width,'PairCount',0,'WindowCount',lengthCP-width+1,'Threshold',NaN);
selected=complex(0); pos=0;
for symbolIndex=1:numel(cpLens)
    n=cpLens(symbolIndex);
    if pos+n+nfft>size(x,1), break; end
    if ~selectedSymbols(symbolIndex)
        pos=pos+n+nfft;
        continue;
    end
    indices=pos+n-lengthCP+(1:lengthCP);
    first=x(indices,:); second=x(indices+nfft,:);
    valid=isfinite(real(first)) & isfinite(imag(first)) & ...
        isfinite(real(second)) & isfinite(imag(second)) & first~=0 & second~=0;
    % Deterministic zero padding is not an independent noise observation.
    first(~valid)=0; second(~valid)=0;
    c=c+sum(conj(first).*second,2);
    a=a+sum(abs(first).^2,2); b=b+sum(abs(second).^2,2);
    count=count+sum(valid,2);
    d.NumSymbols=d.NumSymbols+double(any(valid(:)));
    pos=pos+n+nfft;
end
kernel=ones(width,1);
c=conv(c,kernel,'valid'); a=conv(a,kernel,'valid'); b=conv(b,kernel,'valid');
count=conv(count,kernel,'valid');
usable=a>0 & b>0 & count>1;
if ~any(usable), return; end
coherence=-inf(size(a));
coherence(usable)=min(1,abs(c(usable)./sqrt(a(usable))./sqrt(b(usable))).^2);
[d.CoherenceSquared,index]=max(coherence);
selected=c(index); d.PairCount=count(index);
d.StartFromUsefulSymbol=index-1-lengthCP;
% For independent proper-complex white noise, squared normalized inner
% product is Beta(1,N-1). Bonferroni is valid despite overlapping windows.
d.Threshold=-expm1(log(alpha/d.WindowCount)/(d.PairCount-1));
if ~(isfinite(d.CoherenceSquared) && d.CoherenceSquared>d.Threshold)
    d.Status="cp_correlation_not_distinguishable_from_white_noise";
    return;
end
d.Available=true; d.Status="OK";
end

function matches=localClockMatches(s,names,expected)
matches=true;
for name=string(names(:)).'
    try
        value=s.(char(name));
    catch
        continue;
    end
    if isempty(value), continue; end
    if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
            isfinite(value) && double(value)==expected)
        matches=false;
        return;
    end
end
end

function value = localFirstFinite(s, names, defaultValue)
value = defaultValue;
if ~(isstruct(s) || isobject(s))
    return;
end
for name = string(names(:)).'
    try
        raw = s.(char(name));
    catch
        raw = [];
    end
    if isempty(raw) || ~isnumeric(raw) || ~isreal(raw) || ~isscalar(raw)
        continue;
    end
    raw = double(raw(:));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function values = localFirstVector(s, names, defaultValue)
values = defaultValue;
if ~(isstruct(s) || isobject(s))
    return;
end
for name = string(names(:)).'
    try
        raw = s.(char(name));
    catch
        raw = [];
    end
    if isempty(raw) || ~isnumeric(raw)
        continue;
    end
    values = double(raw(:));
    return;
end
end
