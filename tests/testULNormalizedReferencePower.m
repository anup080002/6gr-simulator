function ok=testULNormalizedReferencePower()
% Exact arithmetic fixtures, not primary simulated measurement rows.
K=24; L=14; plane=K*L;
indices=[1;13;25;37]; symbols=ones(size(indices));
one=complex(ones(K,L));
a=sixgr.phy.ul.measureNormalizedReferencePower(one,indices,symbols);
for branches=[1 2 4]
    grid=repmat(one,1,1,branches);
    b=sixgr.phy.ul.measureNormalizedReferencePower(grid,indices,symbols);
    assert(abs(b.WindowRSSI_dB-10*log10(K))<1e-12 && ...
        b.ReferencePower_dB==a.ReferencePower_dB && ...
        b.WindowPowerRatio_dB==a.WindowPowerRatio_dB);
    assert(isequal(b.WindowPowerPerSymbolPerBranch,K*ones(2,branches)));
end
% Multi-column NR linear port indices must not be treated as [k,l].
ports=[indices indices+plane];
assert(isequal(sixgr.phy.ul.linearReferenceSubcarriers(one,ports),repmat([1;13;1;13],2,1)), ...
    'Multi-port linear indices must not become subcarrier numbers outside the receiver grid.');
assert(isequal(sixgr.phy.ul.linearReferenceSubcarriers(one,ports(:)), ...
    sixgr.phy.ul.linearReferenceSubcarriers(one,ports)));
b=sixgr.phy.ul.measureNormalizedReferencePower(cat(3,one,2*one),ports,ones(size(ports)));
assert(isequal(b.ReferenceREPowerPerBranch,[1 4]) && ...
    isequal(b.RSSIPerBranch,[K 4*K]) && abs(b.WindowPowerRatio_dB-10*log10(1/12))<1e-12);
silent=sixgr.phy.ul.measureNormalizedReferencePower(cat(3,one,0*one),ports,ones(size(ports)));
assert(isequal(silent.RSSIPerBranch,[K 0]) && ...
    abs(silent.WindowPowerRatio_dB-a.WindowPowerRatio_dB)<1e-12, ...
    'A silent branch must retain zero energy, not disappear or bias the ratio.');
bad=one; bad(1)=NaN;
failed=false; try, sixgr.phy.ul.measureNormalizedReferencePower(bad,indices,symbols); catch, failed=true; end
assert(failed,'Nonfinite energy must not be silently omitted.');
ok=true;
end
