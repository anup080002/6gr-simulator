function [hScalar, nVar] = sixgr_channel_est_ls_kernel(rxRefSym, refSym)
%#codegen
% sixgr_channel_est_ls_kernel
% Coder-friendly LS channel-estimation kernel from reference symbols.

L = min(numel(rxRefSym), numel(refSym));
if L <= 0
    hScalar = complex(1,0);
    nVar = 0;
    return;
end

r = rxRefSym(1:L);
s = refSym(1:L);

den = sum(abs(s).^2);
if den <= eps
    hScalar = complex(1,0);
else
    hScalar = sum(r .* conj(s)) / den;
end

e = r - hScalar .* s;
nVar = mean(abs(e).^2);
if ~isfinite(nVar) || nVar < 0
    nVar = 0;
end
end
