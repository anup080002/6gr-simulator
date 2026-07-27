classdef DeterministicMergeEngine
    %DETERMINISTICMERGEENGINE Idempotent retry and conflict-safe merge.
    methods (Static)
        function result=merge(input)
            input=sixgr.validation.TaskOutputManifest.validate(input);
            task=string(input.TaskID); hashes=lower(string(input.OutputSHA256));
            ids=unique(task,"sorted");
            keep=false(height(input),1);
            for index=1:numel(ids)
                rows=find(task==ids(index));
                if numel(unique(hashes(rows)))~=1
                    error("sixgr:validation:DuplicateTaskConflict", ...
                        "Task %s has conflicting output hashes.",ids(index));
                end
                [~,relative]=min(double(input.RetryIndex(rows)));
                keep(rows(relative))=true;
            end
            merged=input(keep,:);
            [~,order]=sort(string(merged.TaskID));
            merged=merged(order,:);
            result=struct("InputRows",height(input), ...
                "UniqueTaskIDs",numel(ids),"MergedTaskCount",height(merged), ...
                "ConflictCount",0,"Merged",merged,"Status","PASS");
        end
        function out=stableSum(values)
            values=sort(double(values(:)));
            total=0; compensation=0;
            for value=reshape(values,1,[])
                next=total+value;
                if abs(total)>=abs(value)
                    correction=(total-next)+value;
                else
                    correction=(value-next)+total;
                end
                compensation=compensation+correction;
                total=next;
            end
            out=total+compensation;
        end
    end
end
