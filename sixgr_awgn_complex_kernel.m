function [y, nVar] = sixgr_awgn_complex_kernel(x, snr_dB)
%#codegen
% sixgr_awgn_complex_kernel
% Coder-friendly AWGN add kernel for complex waveforms.

snrLin = 10.^(snr_dB/10);
sigPow = mean(abs(x(:)).^2);
nVar = sigPow / max(snrLin, eps);
n = sqrt(nVar/2) .* (randn(size(x)) + 1i*randn(size(x)));
y = x + n;
end

