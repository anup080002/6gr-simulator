function metricV = sixgr_freq_corr_search_kernel(x, ref, candHz, fs)
%#codegen
% sixgr_freq_corr_search_kernel
% Batch coarse CFO metric search used by freqOffsetCorrect.

x = x(:);
ref = ref(:);
candHz = double(candHz(:));
fs = double(fs);

nCand = numel(candHz);
metricV = zeros(nCand, 1);

nx = numel(x);
nr = numel(ref);
if nx == 0 || nr == 0 || fs <= 0 || nx < nr
    return;
end

n = (0:nx-1).';
filtRef = flipud(conj(ref));

for k = 1:nCand
    ph = exp(1j * 2*pi * (-candHz(k) / fs) * n);
    xs = x .* ph;
    c = abs(conv(xs, filtRef, "valid"));
    if isempty(c)
        metricV(k) = 0;
    else
        metricV(k) = max(c);
    end
end
end
