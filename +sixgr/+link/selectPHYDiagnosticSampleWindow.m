function [timeIndex, fftIndex, window] = selectPHYDiagnosticSampleWindow(cfg, txWave, availableSamples)
%SELECTPHYDIAGNOSTICSAMPLEWINDOW Bounded display capture on the original clock.
% Select from actual TX samples, not injected timing, decoded outcomes, or RX
% energy. This is a post-processing window, NEVER receiver synchronization.
% The first waveform column remains the declared TX port; do not substitute
% another port just because this one is silent.
assert(isnumeric(txWave) && ismatrix(txWave) && isnumeric(availableSamples) && ...
    isscalar(availableSamples) && isfinite(availableSamples) && availableSamples>=0, ...
    'sixgr:link:PHYDiagnosticWindowInput','Supply a waveform and finite available sample count.');
n=min(size(txWave,1),floor(double(availableSamples)));
timeIndex=zeros(0,1); fftIndex=zeros(0,1);
window=struct('WaveformWindowStartSample',NaN,'WaveformWindowSamples',0, ...
    'SpectrumWindowStartSample',NaN,'SpectrumWindowSamples',0, ...
    'WaveformWindowSelection',"insufficient_contiguous_samples", ...
    'SpectrumWindowFunction',"symmetric_hann",'TXNonzeroSampleObserved',false);
if n<64 || size(txWave,2)<1, return; end
nTime=min(n,localLimit(cfg,'outputs.phySignalDiagnosticWaveformSamples'));
nFFT=2^floor(log2(min(n,localLimit(cfg,'outputs.phySignalDiagnosticFFTLength'))));
samples=txWave(1:n,1);
firstActive=find(isfinite(real(samples)) & isfinite(imag(samples)) & abs(samples)>0,1);
if isempty(firstActive)
    timeStart=1; fftStart=1;
    window.WaveformWindowSelection="leading_window_no_nonzero_tx_samples";
else
    % Each configured window must include the activity even when their
    % lengths differ near the end of a bounded observation.
    timeStart=min(firstActive,n-nTime+1);
    fftStart=min(firstActive,n-nFFT+1);
    window.WaveformWindowSelection="first_nonzero_tx_sample_bounded_contiguous_window";
    window.TXNonzeroSampleObserved=true;
end
timeIndex=(timeStart:timeStart+nTime-1).';
fftIndex=(fftStart:fftStart+nFFT-1).';
window.WaveformWindowStartSample=timeStart;
window.WaveformWindowSamples=nTime;
window.SpectrumWindowStartSample=fftStart;
window.SpectrumWindowSamples=nFFT;
end

function value=localLimit(cfg,path)
value=double(sixgr.util.structGet(cfg,path,1024));
if ~(isscalar(value) && isfinite(value)), value=1024; end
value=max(64,min(4096,round(value)));
end
