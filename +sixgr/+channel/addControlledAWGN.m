function [y, noiseVar, signalPower] = addControlledAWGN(x, snr_dB, varargin)
%ADDCONTROLLEDAWGN Add explicit AWGN with a known variance for a target SNR.

ip = inputParser;
ip.addRequired("x");
ip.addRequired("snr_dB", @(v)isnumeric(v) && isscalar(v));
ip.addParameter("SignalPower", NaN, @(v)isnumeric(v) && isscalar(v));
ip.addParameter("ReferenceWaveform", [], @(v)isnumeric(v) || islogical(v));
ip.parse(x, snr_dB, varargin{:});
opt = ip.Results;

y = x;
noiseVar = NaN;
signalPower = double(opt.SignalPower);

if ~(isscalar(snr_dB) && isfinite(double(snr_dB)))
    return;
end

if ~(isfinite(signalPower) && signalPower >= 0)
    ref = opt.ReferenceWaveform;
    if isempty(ref)
        ref = x;
    end
    if isempty(ref)
        return;
    end
    ref = double(ref(:));
    signalPower = mean(abs(ref).^2, "omitnan");
end

if ~(isfinite(signalPower) && signalPower >= 0)
    return;
end

noiseVar = signalPower / max(10.^(double(snr_dB) / 10), eps);
if ~(isfinite(noiseVar) && noiseVar >= 0)
    return;
end

if noiseVar == 0
    return;
end

n = sqrt(noiseVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
y = x + cast(n, "like", x);
end
