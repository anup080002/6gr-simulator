function ok = testSLSResourceUtilization()
% Core SLS accounting: independently available resources and executed use.
op = localRows([1;1;2],[1;2;1],{[0 2];[0 2];[0 2]},[0;0;0],[2;2;2]);
gr = localRows([1;1;1],[1;1;2],{0;0;2},[0;0;0],[2;2;1]);
r = sixgr.system.measureResourceUtilization(gr,op,"UL",1);
assert(r.AvailablePRBSymbols==12 && r.OccupiedPRBSymbols==3 && r.RUPercent==25);
assert(height(r.PerCellSlot)==3 && any(r.PerCellSlot.OccupiedPRBSymbols==0), ...
    'Idle opportunities must remain in the utilization denominator.');
late = sixgr.system.measureResourceUtilization(gr,op,"UL",2);
assert(late.AvailablePRBSymbols==4 && late.OccupiedPRBSymbols==1);
bad = gr; bad.PRBSet{1}=1;
localReject(@()sixgr.system.measureResourceUtilization(bad,op,"UL",1), ...
    'sixgr:system:RUGrantOutsideOpportunity');
localReject(@()sixgr.system.measureResourceUtilization(removevars(gr,'PRBSet'),op,"UL",1), ...
    'sixgr:system:RUAllocationSchema');
localReject(@()sixgr.system.measureResourceUtilization(gr,op,"DL",1), ...
    'sixgr:system:RUOpportunityMissing');
ok=true; fprintf('SLS_RESOURCE_UTILIZATION_PASS\n');
end

function T = localRows(cellID,tti,prbSet,symbolStart,numSymbols)
T=table(cellID,tti,repmat("UL",numel(tti),1),prbSet,symbolStart,numSymbols, ...
    'VariableNames',{'CellID','TTI','Direction','PRBSet','SymbolStart','NumSymbols'});
end

function localReject(fn,id)
try
    fn();
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message);
    return
end
error('test:MissingRejection','Expected %s.',id);
end
