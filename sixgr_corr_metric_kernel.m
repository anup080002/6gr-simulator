function metric = sixgr_corr_metric_kernel(x, ref)
%#codegen
% sixgr_corr_metric_kernel
% Coder-friendly correlation peak metric.

c = abs(conv(x(:), flipud(conj(ref(:))), 'valid'));
if isempty(c)
    metric = 0;
else
    metric = max(c);
end
end

