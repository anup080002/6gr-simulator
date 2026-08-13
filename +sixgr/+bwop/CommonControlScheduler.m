classdef CommonControlScheduler
    %COMMONCONTROLSCHEDULER Bounded CCE-load procedure model.

    methods (Static)
        function T = run(cfg)
            ncValues=double(cfg.coreset_rb(:)); loads=double(cfg.offered_cce_load(:));
            beams=double(cfg.beam_counts(:)); levels=double(cfg.aggregation_levels(:));
            mix=double(cfg.aggregation_level_mix(:));
            if numel(levels)~=numel(mix)||abs(sum(mix)-1)>1e-9
                error("sixgr:bwop:InvalidALDistribution", ...
                    "Aggregation-level mix must match AL values and sum to one.");
            end
            expectedAL=sum(levels.*mix); periods=double(cfg.periods);
            rows=cell(numel(ncValues)*numel(loads)*numel(beams),1);r=0;
            for nc=ncValues(:).'
                nCCE=floor(nc*double(cfg.coreset_duration_symbols)/6);
                for beam=beams(:).'
                    effectiveCapacity=max(1,floor(nCCE/max(1,beam)));
                    for load=loads(:).'
                        r=r+1;
                        offeredCCE=load*nCCE*periods;
                        servedCCE=min(offeredCCE,nCCE*periods);
                        blockedCCE=max(0,offeredCCE-servedCCE);
                        blocking=blockedCCE/max(offeredCCE,eps);
                        offeredMessages=offeredCCE/expectedAL;
                        servedMessages=servedCCE/expectedAL;
                        utilization=servedCCE/(nCCE*periods);
                        delaySlots=1+max(0,load-1)*periods/(2*max(effectiveCapacity,1));
                        rClass="PROCEDURE_SLS";
                        rows{r}=table(nc,nCCE,beam,load,offeredMessages,servedMessages, ...
                            blocking,utilization,delaySlots,rClass, ...
                            'VariableNames',{'NC_RB','NCCE','BeamCount','OfferedCCELoad', ...
                            'OfferedMessages','ServedMessages','BlockingProbability', ...
                            'CCEUtilization','MeanSchedulingDelaySlots','EvidenceClass'});
                    end
                end
            end
            T=vertcat(rows{:});
        end

        function T = monitoringBudget(postCfg)
            policies=string(postCfg.monitoring_split_policies(:));
            maxBD=double(postCfg.max_blind_decodes); maxCCE=double(postCfg.max_nonoverlapped_cce);
            minBD=double(postCfg.common_min_blind_decodes);minCCE=double(postCfg.common_min_cce);
            rows=cell(numel(policies),1);
            for i=1:numel(policies)
                switch policies(i)
                    case "equal", targetShare=.50;
                    case "target_75", targetShare=.75;
                    case "target_90", targetShare=.90;
                    case "fixed_common_minimum", targetShare=1-minBD/maxBD;
                    case "priority", targetShare=.80;
                    otherwise
                        error("sixgr:bwop:UnknownMonitoringPolicy", ...
                            "Unknown monitoring split policy '%s'.",policies(i));
                end
                commonBD=max(minBD,floor(maxBD*(1-targetShare)));
                targetBD=maxBD-commonBD;
                commonCCE=max(minCCE,floor(maxCCE*(1-targetShare)));
                targetCCE=maxCCE-commonCCE;
                valid=commonBD+targetBD<=maxBD&&commonCCE+targetCCE<=maxCCE;
                rows{i}=table(policies(i),commonBD,targetBD,maxBD,commonCCE,targetCCE,maxCCE, ...
                    valid,"PROCEDURE_SLS",'VariableNames',{'Policy','CommonBD','TargetBD', ...
                    'MaxBD','CommonCCE','TargetCCE','MaxCCE','BudgetValid','EvidenceClass'});
            end
            T=vertcat(rows{:});
            if any(~T.BudgetValid)
                error("sixgr:bwop:MonitoringBudgetExceeded", ...
                    "A common/target monitoring split exceeds the configured UE budget.");
            end
        end
    end
end
