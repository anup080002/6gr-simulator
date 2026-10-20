function ok=testPDCCHCSIWeightingContract()
% Numerical contract fixtures only, not extra physical/campaign samples.
for type=["single","double"]
    llr=cast([1 -2 3 -4 5 -6],type); csi=cast([1e-4 0 1e4],type);
    actual=sixgr.phy.pdcch.applyMMSECSIWeighting(llr,csi);
    assert(isequal(actual,llr.*repelem(csi,2))&&isa(actual,type)&&isrow(actual));
    assert(isequal(sixgr.phy.pdcch.applyMMSECSIWeighting(llr.',csi),actual.'));
end
assert(isequal(sixgr.phy.pdcch.applyMMSECSIWeighting([2;-3],0.5),[1;-1.5]));
assert(isequal(sixgr.phy.pdcch.applyMMSECSIWeighting([2 -3],0),[0 0]));
for invalid={[],[1 2],[1 NaN 3],[1 -1 3],[1 Inf 3],[1 1i 3]}
    reject(@()sixgr.phy.pdcch.applyMMSECSIWeighting(ones(6,1),invalid{1}));
end
reject(@()sixgr.phy.pdcch.applyMMSECSIWeighting([1;NaN],1));
reject(@()sixgr.phy.pdcch.applyMMSECSIWeighting([],[]));
reject(@()sixgr.phy.pdcch.applyMMSECSIWeighting(ones(2,2),ones(2,1)));
reject(@()sixgr.phy.pdcch.applyMMSECSIWeighting(realmax*ones(2,1),2));
ok=true; fprintf('PDCCH_CSI_WEIGHTING_CONTRACT_PASS\n');
end

function reject(fn)
try, fn(); catch err
    assert(strcmp(err.identifier,'sixgr:phy:pdcch:InvalidMMSECSIWeighting'),err.getReport()); return;
end
error('test:InvalidPDCCHWeightingAccepted','Invalid reliability evidence was silently accepted.');
end
