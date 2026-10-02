function ok=testSLSResourceOpportunityAccounting()
% Independent idle-cell denominator, TDD symbols and exact PRB reservations.
budget=struct("PRBSet",[0 2 4],"SymbolAllocation",[12 2], ...
    "ReservedResourceRegions",struct("PRBSet",2,"SymbolAllocation",[13 1]));
T=sixgr.system.buildResourceOpportunityTable(4,2,"UL",budget,true);
assert(height(T)==4 && all(T.SymbolStart>=12) && all(T.NumSymbols==1));
assert(all(T.TTI==4) && isequal(unique(T.CellID),[1;2]));
empty=T([],:);
idle=sixgr.studies.ran1ai1032.measureSLSResourceUtilization(empty,T,"UL",1);
assert(idle.AvailablePRBSymbols==10 && idle.RUPercent==0, ...
    "Two idle cells retain 2*(3+2) schedulable PRB-symbols after reservation.");
g=T(T.CellID==1,:);
g=g([1 1 2],:); % MU overlaps in symbol 12 must not be double counted.
used=sixgr.studies.ran1ai1032.measureSLSResourceUtilization(g,T,"UL",1);
assert(used.OccupiedPRBSymbols==5 && used.RUPercent==50);
disabled=sixgr.system.buildResourceOpportunityTable(4,2,"UL",budget,false);
assert(isempty(disabled) && isequal(disabled.Properties.VariableNames,T.Properties.VariableNames));
ok=true;
end
