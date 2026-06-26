function [y, nVar] = addAwgnComplex(x, snr_dB, varargin)
%ADDAWGNCOMPLEX Add complex AWGN, using the MEX kernel when available.
%
%   [Y,NVAR] = sixgr.util.addAwgnComplex(X, SNR_DB) adds zero-mean
%   circularly-symmetric complex AWGN to X at the requested SNR in dB.
%   When the optional MEX kernel is present, use it to accelerate large
%   waveform paths without changing the signal model.
%
%   [Y,NVAR] = ...("NoiseVariance", NV) injects an explicit complex-noise
%   variance in the current sample-amplitude units and bypasses SNR-derived
%   variance. This preserves the same zero-mean circular AWGN model.

if nargin < 2
    error("sixgr:util:addAwgnComplex:InvalidInput", ...
        "x and snr_dB are required.");
end

snr_dB = double(snr_dB);
if ~(isscalar(snr_dB) && isfinite(snr_dB))
    error("sixgr:util:addAwgnComplex:InvalidSNR", ...
        "snr_dB must be a finite scalar.");
end

ip = inputParser;
ip.addParameter("NoiseVariance", [], @(v) isempty(v) || (isnumeric(v) && isscalar(v)));
ip.addParameter("SignalPower", [], @(v) isempty(v) || (isnumeric(v) && isscalar(v)));
ip.parse(varargin{:});
opt = ip.Results;

if ~isempty(opt.NoiseVariance)
    nVar = double(opt.NoiseVariance);
    if ~(isscalar(nVar) && isfinite(nVar) && nVar >= 0)
        error("sixgr:util:addAwgnComplex:InvalidNoiseVariance", ...
            "NoiseVariance must be a finite non-negative scalar.");
    end
    n = sqrt(nVar/2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
    y = x + cast(n, "like", x);
    return;
end

if isempty(varargin) && exist("sixgr_awgn_complex_kernel_mex", "file") == 3
    [y, nVar] = sixgr_awgn_complex_kernel_mex(x, snr_dB);
    return;
end

if isempty(varargin) && exist("sixgr_awgn_complex_kernel", "file") == 2
    [y, nVar] = sixgr_awgn_complex_kernel(x, snr_dB);
    return;
end

snrLin = 10.^(snr_dB/10);
if ~isempty(opt.SignalPower)
    sigPow = double(opt.SignalPower);
    if ~(isscalar(sigPow) && isfinite(sigPow) && sigPow >= 0)
        error("sixgr:util:addAwgnComplex:InvalidSignalPower", ...
            "SignalPower must be a finite non-negative scalar.");
    end
else
    sigPow = mean(abs(x(:)).^2);
end
nVar = sigPow / max(snrLin, eps);
n = sqrt(nVar/2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
y = x + cast(n, "like", x);
end
