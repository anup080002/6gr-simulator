classdef SeedLedger
    %SEEDLEDGER Detect collisions while preserving deterministic retries.
    methods (Static)
        function result=validate(input)
            required=["CampaignID","TaskID","IndependentDropID","Seed","Substream"];
            if ~istable(input)||any(~ismember(required,string(input.Properties.VariableNames)))
                error("sixgr:validation:SchemaMissingColumn", ...
                    "Seed ledger is missing mandatory columns.");
            end
            task=string(input.TaskID); seed=double(input.Seed);
            sub=double(input.Substream); drop=string(input.IndependentDropID);
            [uniqueTask,~,group]=unique(task,"stable");
            for index=1:numel(uniqueTask)
                rows=group==index;
                if numel(unique(seed(rows)))>1 || numel(unique(sub(rows)))>1 || ...
                        numel(unique(drop(rows)))>1
                    error("sixgr:validation:DuplicateTaskConflict", ...
                        "Retry task %s changed seed, substream or drop.",uniqueTask(index));
                end
            end
            representative=false(height(input),1);
            for index=1:numel(uniqueTask)
                representative(find(group==index,1))=true;
            end
            if numel(unique(seed(representative)))~=sum(representative) || ...
                    numel(unique(sub(representative)))~=sum(representative)
                error("sixgr:validation:TaskSeedCollision", ...
                    "Different validation tasks share a seed or substream.");
            end
            result=struct("Rows",height(input), ...
                "UniqueTaskCount",numel(uniqueTask),"CollisionCount",0, ...
                "Status","PASS");
        end
    end
end
