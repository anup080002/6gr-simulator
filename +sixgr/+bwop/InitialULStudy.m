classdef InitialULStudy
    %INITIALULSTUDY Common UL range versus actual resource subsets.

    methods (Static)
        function T = run(cfg)
            widths=double(cfg.configured_range_rb(:)); allocations=double(cfg.actual_pusch_rb(:));
            powers=double(cfg.ue_tx_power_dbm(:)); rows=cell(numel(widths)*numel(allocations)*numel(powers),1);r=0;
            for width=widths(:).'
                for allocation=allocations(:).'
                    for power=powers(:).'
                        r=r+1;
                        contained=allocation<=width&&double(cfg.prach_rb)<=width&&double(cfg.pucch_rb)<=width;
                        psdDbmPerRB=power-10*log10(allocation);
                        rows{r}=table(width,allocation,double(cfg.prach_rb),double(cfg.pucch_rb), ...
                            power,psdDbmPerRB,contained,"PROCEDURE_SLS", ...
                            'VariableNames',{'ConfiguredCommonULRangeRB','ActualPUSCHRB', ...
                            'ActualPRACHRB','ActualPUCCHRB','UETotalPowerDbm', ...
                            'PUSCHPowerPerRBDbm','AllResourcesContained','EvidenceClass'});
                    end
                end
            end
            T=vertcat(rows{:});
        end

        function assertPRBSet(prbSet,configuredWidth)
            set=double(prbSet(:).');width=double(configuredWidth);
            if isempty(set)||any(~isfinite(set))||any(set~=round(set))|| ...
                    any(set<0)||numel(unique(set))~=numel(set)||any(set>=width)
                error("sixgr:bwop:InitialULResourceOutsideRange", ...
                    "Every actual initial-UL PRB must be a unique zero-based index inside the configured common range.");
            end
        end
    end
end
