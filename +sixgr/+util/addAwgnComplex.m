function [y, nVar] = addAwgnComplex(x, snr_dB)
%ADDAWGNCOMPLEX Add complex AWGN, using the MEX kernel when available.
%
%   [Y,NVAR] = sixgr.util.addAwgnComplex(X, SNR_DB) adds zero-mean
%   circularly-symmetric complex AWGN to X at the requested SNR in dB.
%   When the optional MEX kernel is present, use it to accelerate large
%   waveform paths without changing the signal model.

if nargin < 2
    error("sixgr:util:addAwgnComplex:InvalidInput", ...
        "x and snr_dB are required.");
end

snr_dB = double(snr_dB);
if ~(isscalar(snr_dB) && isfinite(snr_dB))
    error("sixgr:util:addAwgnComplex:InvalidSNR", ...
        "snr_dB must be a finite scalar.");
end

if exist("sixgr_awgn_complex_kernel_mex", "file") == 3
    [y, nVar] = sixgr_awgn_complex_kernel_mex(x, snr_dB);
    return;
end

if exist("sixgr_awgn_complex_kernel", "file") == 2
    [y, nVar] = sixgr_awgn_complex_kernel(x, snr_dB);
    return;
end

snrLin = 10.^(snr_dB/10);
sigPow = mean(abs(x(:)).^2);
nVar = sigPow / max(snrLin, eps);
n = sqrt(nVar/2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
y = x + cast(n, "like", x);
end
