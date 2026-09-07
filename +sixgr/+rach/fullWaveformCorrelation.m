function correlation=fullWaveformCorrelation(received,reference)
%FULLWAVEFORMCORRELATION Full linear correlation, without lag pruning.
% Zero padding prevents circular wrap-around. This computes the same
% convolution as conv(received,flipud(conj(reference))), up to roundoff;
% it does not reduce samples, candidate count, or waveform resolution.
received=received(:); reference=reference(:);
if isempty(received) || isempty(reference) || ...
        ~all(isfinite(received)) || ~all(isfinite(reference)) || ...
        ~strcmp(class(received),class(reference)) || ...
        ~any(strcmp(class(received),{'double','single'}))
    % Preserve the exact reference kernel's empty/nonfinite/type semantics.
    % This is a numeric-kernel path, never replacement measurement data.
    correlation=conv(received,flipud(conj(reference)),'full');
    return;
end
nFull=numel(received)+numel(reference)-1;
nFFT=2^nextpow2(nFull);
correlation=ifft(fft(received,nFFT).*fft(flipud(conj(reference)),nFFT));
correlation=correlation(1:nFull);
if isreal(received) && isreal(reference), correlation=real(correlation); end
end
