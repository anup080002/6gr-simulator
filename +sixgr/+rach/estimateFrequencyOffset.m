function freq = estimateFrequencyOffset(rxWaveform, refWaveform, sampleRateHz)
%ESTIMATEFREQUENCYOFFSET Estimate residual CFO from repeated PRACH symbols.
%
% PRACH waveforms contain repeated useful symbols.  Measuring the phase
% between repetitions gives orders of magnitude more CFO sensitivity than
% a short adjacent-sample regression and is robust to a static multipath
% channel.  The reference autocorrelation selects the repetition lag and
% removes any deterministic phase of the waveform at that lag.

rx = localMatrix(rxWaveform);
ref = localMatrix(refWaveform);
L = min(size(rx,1), size(ref,1));

freq = struct( ...
    "Valid", false, ...
    "EstimateHz", NaN, ...
    "Estimator", "mlr_multilag_ls", ...
    "AmbiguityRange_Hz", NaN);

sampleRateHz = double(sampleRateHz);
if L < 8 || ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    return;
end

rx = rx(1:L,:);
ref = ref(1:L,:);
if size(ref,2)>1
    ref=mean(ref,2);
end
if L < 32
    return;
end

lag = localRepetitionLag(ref);
if ~(isfinite(lag) && lag>=1 && lag<L)
    return;
end

refLag=sum(ref(lag+1:end).*conj(ref(1:end-lag)),'omitnan');
rxLag=complex(0);
for iBranch=1:size(rx,2)
    branch=rx(:,iBranch);
    rxLag=rxLag+sum(branch(lag+1:end).*conj(branch(1:end-lag)),'omitnan');
end
if ~(isfinite(real(rxLag))&&isfinite(imag(rxLag))&&abs(rxLag)>eps&&abs(refLag)>eps)
    return;
end

phase=angle(rxLag*conj(refLag));
freq.Valid=isfinite(phase);
freq.EstimateHz=double(phase)*sampleRateHz/(2*pi*double(lag));
freq.AmbiguityRange_Hz=sampleRateHz/(2*double(lag));
freq.Estimator="prach_repetition_phase";
freq.RepetitionLagSamples=double(lag);
end

function lag=localRepetitionLag(ref)
N=numel(ref); nfft=2^nextpow2(2*N-1);
ac=ifft(abs(fft(ref,nfft)).^2);
minLag=max(8,floor(N/64)); maxLag=floor(N/3);
lags=(minLag:maxLag).'; scores=zeros(size(lags));
power=cumsum(abs(ref).^2);
for k=1:numel(lags)
    m=lags(k); cross=ac(m+1);
    e1=power(N-m); e2=power(N)-power(m);
    scores(k)=abs(cross)/max(sqrt(e1*e2),eps);
end
[peak,idx]=max(scores);
if isempty(idx)||~isfinite(peak)||peak<0.25
    lag=NaN;
else
    % Multiples of the fundamental repetition have essentially identical
    % normalized correlation.  Select the shortest near-maximum lag to
    % maximize the unambiguous CFO range and prevent phase wrapping.
    idx=find(scores>=peak-max(1e-8,1e-6*peak),1,"first");
    lag=lags(idx);
end
end

function value=localMatrix(x)
if isempty(x),value=complex(zeros(0,1));elseif isvector(x),value=x(:);else,value=x;end
end
