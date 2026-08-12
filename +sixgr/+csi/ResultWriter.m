classdef ResultWriter
    %RESULTWRITER Atomic, provenance-enriched CSI suite CSV writer.

    methods (Static)
        function write(path,T,context)
            if ~istable(T) || height(T)==0
                error("sixgr:csi:EmptyPrimaryEvidence", ...
                    "CSI evidence artifact %s must contain executed or explicit NOT_EVALUATED rows.",path);
            end
            n=height(T);
            if ~ismember("RunId",string(T.Properties.VariableNames))
                T=addvars(T,repmat(string(context.RunId),n,1),'Before',1, ...
                    'NewVariableNames','RunId');
            end
            if ~ismember("ConfigHash",string(T.Properties.VariableNames))
                T=addvars(T,repmat(string(context.ConfigHash),n,1), ...
                    'After','RunId','NewVariableNames','ConfigHash');
            end
            if ~ismember("GitCommit",string(T.Properties.VariableNames))
                T=addvars(T,repmat(string(context.GitCommit),n,1), ...
                    'After','ConfigHash','NewVariableNames','GitCommit');
            end
            sixgr.util.csvWriteTable(path,T,"PreserveSchema",true);
            check=readtable(path,"Delimiter",",","VariableNamingRule","preserve");
            if height(check)~=n || width(check)~=width(T)
                error("sixgr:csi:CSVReadbackMismatch", ...
                    "CSV readback changed shape for %s.",path);
            end
        end

        function T=notEvaluated(kpi,reason)
            kpi=string(kpi(:));
            T=table(kpi,repmat("NOT_EVALUATED",numel(kpi),1), ...
                repmat("NOT_EVALUATED_IN_LLS",numel(kpi),1), ...
                repmat(string(reason),numel(kpi),1),'VariableNames', ...
                {'RequestedKPI','EvidenceClass','Status','Reason'});
        end
    end
end
