classdef PDSCHStudy
    %PDSCHSTUDY Controlled N_S/A allocation construction and accounting.

    methods (Static)
        function T=allocationCases(dlCfg)
            nc=double(dlCfg.coreset_rb(1));ns=nc*double(dlCfg.sib1_reference_multiplier(end));
            baselineCount=min(double(dlCfg.baseline_actual_allocation_rb),nc);start=0:baselineCount-1;
            distributed=[0:floor(baselineCount/2)-1,ns-floor(baselineCount/2):ns-1];
            relocated=ns-baselineCount:ns-1;
            cases=string(dlCfg.controlled_cases(:));rows=cell(numel(cases),1);
            for i=1:numel(cases)
                switch cases(i)
                    case {"SAME_SAME","WIDER_S_SAME_A"}, prb=start;
                    case "WIDER_S_WIDER_CONTIGUOUS_A", prb=0:min(ns-1,2*baselineCount-1);
                    case "WIDER_S_DISTRIBUTED_A", prb=distributed;
                    case "WIDER_S_RELOCATED_A", prb=relocated;
                    case "SHIFTED_OVERLAPPING_S", prb=start+floor(nc/2);
                    case "NON_OVERLAPPING_S", prb=relocated;
                    otherwise,error("sixgr:bwop:UnknownPDSCHCase","Unknown PDSCH case %s.",cases(i));
                end
                if any(prb<0|prb>=ns)||numel(unique(prb))~=numel(prb)
                    error("sixgr:bwop:InvalidPDSCHPRBSet", ...
                        "Case %s produced an invalid explicit PRB set.",cases(i));
                end
                rows{i}=table(cases(i),nc,ns,numel(prb),string(mat2str(prb)), ...
                    min(prb),max(prb),numel(prb)~=max(prb)-min(prb)+1, ...
                    "ANALYTICAL_EXACT",'VariableNames',{'CaseID','NC_RB','NS_RB', ...
                    'ActualAllocationRB','ExplicitPRBSet','MinimumPRB','MaximumPRB', ...
                    'NonContiguous','EvidenceClass'});
            end
            T=vertcat(rows{:});
        end
    end
end
