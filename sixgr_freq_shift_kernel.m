function y = sixgr_freq_shift_kernel(x, fs_Hz, foff_Hz)
%#codegen
% sixgr_freq_shift_kernel
% Coder-friendly complex frequency shift kernel.

n = (0:size(x,1)-1).';
rot = exp(1i * 2*pi * (foff_Hz / max(fs_Hz, eps)) * n);
y = x .* rot;
end

