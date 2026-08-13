classdef PDCCHStudy
    %PDCCHSTUDY Exact BWOP PDCCH payload/capacity preparation.

    methods (Static)
        function T=run(analyticalCfg,dlCfg)
            riv=sixgr.bwop.RIVFDRA.rivTable(analyticalCfg.fdra_reference_bandwidth_rb);
            cce=sixgr.bwop.RIVFDRA.cceTable(dlCfg.coreset_rb,3,analyticalCfg.aggregation_levels);
            rows=cell(height(riv)*height(cce),1);r=0;
            fixedNonFDRABits=double(analyticalCfg.dci_non_fdra_bits);
            for i=1:height(riv)
                for j=1:height(cce)
                    r=r+1;
                    payload=fixedNonFDRABits+riv.FDRABits(i);
                    rows{r}=table(riv.NS_RB(i),riv.FDRABits(i),payload,cce.NC_RB(j), ...
                        cce.NCCE(j),cce.AggregationLevel(j),cce.Feasible(j), ...
                        "ANALYTICAL_EXACT",'VariableNames',{'NS_RB','FDRABits', ...
                        'AnalyticalDCIPayloadBits','NC_RB','NCCE','AggregationLevel', ...
                        'Feasible','EvidenceClass'});
                end
            end
            T=vertcat(rows{:});
        end
    end
end
