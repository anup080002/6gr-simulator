function ok=testRuntimeUCIOwner()
assert(isequal(sixgr.truth.matchRuntimeUCIOwner(2,[1;2;3]),[false;true;false]));
assert(isequal(sixgr.truth.matchRuntimeUCIOwner(1,[1 2]),[true false]));
for invalid={NaN,Inf,0,-1,1.5,1+1i,[],[1 2],"1"}
    reject(@()sixgr.truth.matchRuntimeUCIOwner(invalid{1},1));
end
for invalid={NaN,Inf,0,-1,1.5,1+1i,"1",[1 NaN]}
    reject(@()sixgr.truth.matchRuntimeUCIOwner(1,invalid{1}));
end
ok=true;
end
function reject(fn)
caught=false;
try, fn(); catch ex
    assert(string(ex.identifier)=="sixgr:truth:MissingRuntimeUCIOwner",ex.message);
    caught=true;
end
assert(caught,'Missing/ambiguous runtime UE identity must fail, not use RNTI fallback.');
end
