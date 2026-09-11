function budget=puschPreparationProcessingTime(carrier,pusch,numerologies)
% TS 38.214 6.4 capability-1 N2+d2,1 from the actual PUSCH allocation.
% This is a scheduling calculation, not measured receiver latency. Switching,
% priority, multiple-TB and UCI-multiplexing terms require separate evidence.
arguments
    carrier (1,1) nrCarrierConfig
    pusch (1,1) nrPUSCHConfig
    numerologies (1,:) double
end
first=double(pusch.SymbolAllocation(1));
data=nrPUSCHIndices(carrier,pusch,'IndexStyle','subscript','IndexBase','0based');
dmrs=nrPUSCHDMRSIndices(carrier,pusch,'IndexStyle','subscript','IndexBase','0based');
ptrs=nrPUSCHPTRSIndices(carrier,pusch,'IndexStyle','subscript','IndexBase','0based');
dataCount=sum(double(data(:,2))==first);
dmrsCount=sum(double(dmrs(:,2))==first);
ptrsCount=0;
if ~isempty(ptrs), ptrsCount=sum(double(ptrs(:,2))==first); end
onlyDMRS=dmrsCount>0 && dataCount==0 && ptrsCount==0;
d21=double(~onlyDMRS);
assert(~isempty(numerologies),'sixgr:phy:frame:MissingProcessingNumerologies', ...
    'PUSCH processing requires actual control and data numerologies.');
budget=struct('Ticks',int64(-1),'Mu',NaN,'N2Symbols',NaN,'D21Symbols',d21, ...
    'FirstSymbol0Based',first,'FirstSymbolDMRSOnly',onlyDMRS, ...
    'FirstSymbolDataRE',dataCount,'FirstSymbolDMRSRE',dmrsCount, ...
    'FirstSymbolPTRSRE',ptrsCount,'MappingType',string(pusch.MappingType), ...
    'Source',"nr_pusch_and_reference_resource_indices", ...
    'Unit',"nr_nominal_symbol_duration", ...
    'Scope',"cap1_N2_plus_d21_not_complete_UCI_or_switching_budget");
for mu=numerologies
    row=sixgr.phy.frame.TimingPolicyCatalog.capability1(mu);
    ticks=sixgr.phy.frame.TimingPolicyCatalog.processingSymbolTicks(row.PUSCHN2Symbols+d21,mu);
    if ticks>budget.Ticks
        budget.Ticks=ticks; budget.Mu=mu; budget.N2Symbols=row.PUSCHN2Symbols;
    end
end
end
