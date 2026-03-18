function h = sixgr_truth_grant_hash_kernel(prbSet, sa, modId, nl, tcrScaled, rv, scs, nsg)
%#codegen
% sixgr_truth_grant_hash_kernel
% Coder-friendly compact grant signature hash.

prb = double(prbSet(:));
nPrb = uint64(numel(prb));
if isempty(prb)
    prbMin = uint64(0);
    prbMax = uint64(0);
    prbSum = uint64(0);
    prbSumSq = uint64(0);
    prbXor = uint64(0);
else
    p = uint64(max(0, round(prb)) + 1);
    prbMin = min(p);
    prbMax = max(p);
    prbSum = uint64(sum(double(p)));
    prbSumSq = uint64(sum(double(p) .* double(p)));
    prbXor = uint64(0);
    for i = 1:numel(p)
        prbXor = bitxor(prbXor, p(i));
    end
end

saV = double(sa(:));
if isempty(saV)
    sa0 = uint64(0);
    sa1 = uint64(0);
else
    sa0 = uint64(max(0, round(saV(1))));
    if numel(saV) >= 2
        sa1 = uint64(max(0, round(saV(2))));
    else
        sa1 = uint64(0);
    end
end

vals = uint64([ ...
    nPrb; prbMin; prbMax; prbSum; prbSumSq; prbXor; ...
    sa0; sa1; ...
    uint64(max(0, round(double(modId)))); ...
    uint64(max(0, round(double(nl)))); ...
    uint64(max(0, round(double(tcrScaled)))); ...
    uint64(max(0, round(double(rv)))); ...
    uint64(max(0, round(double(scs)))); ...
    uint64(max(0, round(double(nsg))))]);

h = uint64(1469598103934665603);
prime = uint64(1099511628211);
for i = 1:numel(vals)
    h = bitxor(h, vals(i));
    h = h * prime;
end
end
