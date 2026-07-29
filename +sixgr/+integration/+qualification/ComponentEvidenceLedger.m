classdef ComponentEvidenceLedger
    %COMPONENTEVIDENCELEDGER Bind component rows to executed evidence.
    methods (Static)
        function results = evaluate(ctx,subcases,valueResults,implementation)
            contract = ctx.Profile.Components;
            n = height(contract);
            mandatoryField = "MandatoryInComprehensiveSmoke";
            if ctx.Profile.Preset == "deep_acceptance"
                mandatoryField = "MandatoryInDeepAcceptance";
            end
            mandatory = localTruth(contract.(mandatoryField));
            executed = false(n,1);
            evidencePresent = false(n,1);
            correctnessChecked = false(n,1);
            status = repmat("FAIL",n,1);
            failureCode = strings(n,1);
            evidenceIDs = strings(n,1);
            for index = 1:n
                subID = string(contract.SubcaseID(index));
                subMask = string(subcases.SubcaseID) == subID;
                executed(index) = any(subMask & logical(subcases.Executed));
                names = [localList(contract.RequiredCSV(index)); ...
                    localList(contract.RequiredPNG(index))];
                paths = strings(0,1);
                present = true;
                for name = reshape(names,1,[])
                    path = localFindUniqueOrEmpty(ctx.RunFolder,name);
                    present = present && strlength(path)>0;
                    if strlength(path)>0, paths(end+1,1)=path; end %#ok<AGROW>
                end
                evidencePresent(index) = present && ~isempty(names);
                valueMask = string(valueResults.SubcaseID) == subID & ...
                    logical(valueResults.Required);
                correctnessChecked(index) = any(valueMask) && ...
                    all(string(valueResults.Status(valueMask))=="PASS");
                implMask = string(implementation.ComponentID) == ...
                    string(contract.ComponentID(index));
                implementationValid = any(implMask & ...
                    string(implementation.Status)=="PASS");
                passed = executed(index) && evidencePresent(index) && ...
                    correctnessChecked(index) && implementationValid;
                if passed
                    status(index)="PASS";
                else
                    failureCode(index)=string(contract.FailureCode(index));
                end
                evidenceIDs(index)=strjoin(localRelative(paths,ctx.RunFolder),"|");
            end
            results = table(repmat(ctx.RunID,n,1), ...
                string(contract.ComponentID),string(contract.Domain), ...
                string(contract.Component),mandatory,executed, ...
                evidencePresent,correctnessChecked,status,failureCode, ...
                evidenceIDs,'VariableNames',{'RunID','ComponentID', ...
                'Domain','Component','Mandatory','Executed', ...
                'EvidencePresent','CorrectnessChecked','Status', ...
                'FailureCode','EvidenceArtifactIDs'});
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "full_stack_component_coverage_results.csv"),results);
        end
    end
end

function out=localList(value)
out=strip(split(string(value),"|"));
out=out(strlength(out)>0);
end

function tf=localTruth(value)
tf=ismember(lower(strtrim(string(value))),["true","1","yes"]);
end

function path=localFindUniqueOrEmpty(root,name)
listing=dir(fullfile(root,"**",char(name)));
listing=listing(~[listing.isdir]);
paths=unique(string(fullfile({listing.folder},{listing.name})));
if numel(paths)==1, path=paths(1); else, path=""; end
end

function rel=localRelative(paths,root)
rel=replace(string(paths),string(root)+filesep,"");
rel=replace(rel,"\","/");
end
