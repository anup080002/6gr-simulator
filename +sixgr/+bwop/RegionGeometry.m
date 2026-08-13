classdef RegionGeometry
    %REGIONGEOMETRY Exact common/SIB1-region relations for cases 1 and 2A-D.

    methods (Static)
        function T = enumerate(cfg)
            ncValues=double(cfg.coreset_rb(:)); multipliers=double(cfg.sib1_reference_multipliers(:));
            carriers=double(cfg.carrier_nsize_grid(:)); starts=double(cfg.coreset_start_crb(:));
            cases=["CASE_1","CASE_2A","CASE_2B","CASE_2C","CASE_2D"];
            rows=cell(numel(ncValues)*numel(multipliers)*numel(carriers)*numel(starts)*numel(cases),1);r=0;
            for carrier=carriers(:).'
                for nc=ncValues(:).'
                    for multiplier=multipliers(:).'
                        ns=nc*multiplier;
                        for nC=starts(:).'
                            for caseId=cases
                                [nS,relation]=sixgr.bwop.RegionGeometry.derive(caseId,nC,nc,ns);
                                overlap=max(0,min(nC+nc,nS+ns)-max(nC,nS));
                                feasibility=sixgr.bwop.RFSpanFeasibility.evaluate(nS,ns,carrier, ...
                                    double(cfg.mandatory_rf_span_start_crb), ...
                                    double(cfg.mandatory_rf_span_size_rb),double(cfg.guard_rb), ...
                                    double(cfg.ssb_start_crb),double(cfg.ssb_size_rb));
                                r=r+1;
                                rows{r}=table(caseId,carrier,nC,nc,nS,ns, ...
                                    nC+(nc-1)/2,nS+(ns-1)/2,overlap,overlap>0, ...
                                    feasibility.SSBContained,feasibility.CarrierContained, ...
                                    feasibility.RFSpanContained,feasibility.Feasible, ...
                                    relation,feasibility.Reason,"ANALYTICAL_EXACT", ...
                                    'VariableNames',{'CaseID','CarrierRB','NCStartRB','NC_RB', ...
                                    'NSStartRB','NS_RB','NCCentreRB','NSCentreRB','OverlapRB', ...
                                    'OverlapsCORESET','SSBContained','CarrierContained', ...
                                    'RFSpanContained','Feasible','Relation','FailureReason','EvidenceClass'});
                            end
                        end
                    end
                end
            end
            T=vertcat(rows{1:r});
        end

        function [startRB,relation] = derive(caseId,nC,nc,ns)
            caseId=upper(string(caseId));
            switch caseId
                case "CASE_1"
                    startRB=nC; relation="same_start_same_bandwidth";
                case "CASE_2A"
                    startRB=nC; relation="same_start_larger_bandwidth";
                case "CASE_2B"
                    startRB=nC-floor((ns-nc)/2); relation="centre_preserving";
                case "CASE_2C"
                    startRB=nC+max(1,floor(nc/2)); relation="shifted_overlapping";
                case "CASE_2D"
                    startRB=nC+nc+1; relation="non_overlapping";
                otherwise
                    error("sixgr:bwop:UnknownRegionCase", ...
                        "Unknown BWOP region case '%s'.",caseId);
            end
            if caseId=="CASE_1" && ns~=nc
                relation="case_1_requires_ns_equal_nc";
            end
        end

        function classId = transitionClass(commonStart,commonSize,targetStart,targetSize)
            commonCentre=double(commonStart)+(double(commonSize)-1)/2;
            targetCentre=double(targetStart)+(double(targetSize)-1)/2;
            if abs(commonCentre-targetCentre)>1e-12
                classId=2;
            elseif targetSize>commonSize
                classId=1;
            else
                classId=0;
            end
        end
    end
end
