classdef ResultWriter
    %RESULTWRITER Atomic provenance-enriched study CSV writer.

    methods (Static)
        function write(path, T, context)
            if ~istable(T) || height(T) == 0
                error("sixgr:ran1ai10522:EmptyArtifact", ...
                    "Artifact %s must contain exact, executed, or explicit blocked rows.", path);
            end
            n = height(T); names = string(T.Properties.VariableNames);
            additions = {"RunId", string(context.RunId); ...
                "ConfigHash", string(context.ConfigHash); ...
                "GitCommit", string(context.GitCommit)};
            for k = size(additions,1):-1:1
                if ~ismember(additions{k,1}, names)
                    T = addvars(T, repmat(additions{k,2}, n, 1), ...
                        'Before', 1, 'NewVariableNames', additions{k,1});
                end
            end
            sixgr.util.csvWriteTable(path, T, "PreserveSchema", true);
            check = readtable(path, "Delimiter", ",", "VariableNamingRule", "preserve");
            if height(check) ~= height(T) || width(check) ~= width(T)
                error("sixgr:ran1ai10522:CSVReadbackMismatch", ...
                    "CSV readback shape changed for %s.", path);
            end
        end

        function T = blocked(item, reason)
            item = string(item(:));
            T = table(item, repmat("BLOCKED",numel(item),1), ...
                repmat("BLOCKED",numel(item),1), repmat(string(reason),numel(item),1), ...
                'VariableNames',{'Item','EvidenceClass','Status','StopReason'});
        end
    end
end
