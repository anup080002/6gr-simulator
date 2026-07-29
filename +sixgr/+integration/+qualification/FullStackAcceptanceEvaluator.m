classdef FullStackAcceptanceEvaluator
    %FULLSTACKACCEPTANCEEVALUATOR Bind all 387 rules to status evidence.
    methods (Static)
        function results=evaluate(ctx,subcases,components,values,negatives)
            rules=ctx.Profile.AcceptanceRules;
            requiredField="RequiredInComprehensiveSmoke";
            if ctx.Profile.Preset=="deep_acceptance"
                requiredField="RequiredInDeepAcceptance";
            end
            required=localTruth(rules.(requiredField));
            n=height(rules);
            status=repmat("FAIL",n,1);
            observed=strings(n,1);
            rowsChecked=zeros(n,1);
            rowsFailed=zeros(n,1);
            evidence=string(rules.EvidenceCSV);
            details=strings(n,1);
            for index=1:n
                if ~required(index)
                    status(index)="PASS";
                    observed(index)="NOT_REQUIRED_FOR_SELECTED_PRESET";
                    details(index)="Rule is outside the selected preset.";
                    continue;
                end
                op=upper(strtrim(string(rules.Operator(index))));
                try
                    [passed,obs,checked,failed]=localEvaluateOperator( ...
                        op,subcases,components,values,negatives,ctx, ...
                        string(rules.EvidenceCSV(index)));
                    observed(index)=obs;
                    rowsChecked(index)=checked;
                    rowsFailed(index)=failed;
                    if passed,status(index)="PASS";end
                    details(index)="Rule evaluated from bound status evidence.";
                catch ME
                    details(index)=string(ME.identifier)+": "+string(ME.message);
                end
            end
            results=table(repmat(ctx.RunID,n,1),string(rules.RuleID), ...
                string(rules.Category),required,status,observed, ...
                string(rules.Threshold),rowsChecked,rowsFailed,evidence, ...
                string(rules.FailureCode),details, ...
                'VariableNames',{'RunID','RuleID','Category','Required', ...
                'Status','Observed','Threshold','RowsChecked','RowsFailed', ...
                'EvidenceArtifactID','FailureCode','Details'});
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "full_stack_acceptance_results.csv"),results);
        end
    end
end

function [passed,observed,checked,failed]=localEvaluateOperator( ...
    op,subcases,components,values,negatives,ctx,evidenceCSV)
token=regexp(char(op),'^STATUS\(([^)]+)\)$','tokens','once');
if ~isempty(token)
    id=string(token{1});
    if startsWith(id,"SC-")
        T=subcases;key="SubcaseID";
    elseif startsWith(id,"COMP-")
        T=components;key="ComponentID";
    elseif startsWith(id,"VALCHK-")
        T=values;key="CheckID";
    else
        error("FULLSTACK:UnknownAcceptanceStatusID", ...
            "Unknown acceptance status ID %s.",id);
    end
    mask=string(T.(key))==id;
    checked=nnz(mask);failed=nnz(mask & string(T.Status)~="PASS");
    passed=checked==1&&failed==0;observed=localStatus(passed);
    return;
end
token=regexp(char(op),'^NEGATIVE_STATUS\(([^)]+)\)$', ...
    'tokens','once');
if ~isempty(token)
    id=string(token{1});mask=string(negatives.CaseID)==id;
    checked=nnz(mask);failed=nnz(mask & string(negatives.Status)~="PASS");
    passed=checked==1&&failed==0;observed=localStatus(passed);
    return;
end
if startsWith(op,"ALL_")||op=="ALL_PASS"
    names=unique(localList(evidenceCSV),"stable");
    checked=0;failed=0;
    for name=reshape(names,1,[])
        path=localFindUnique(ctx.RunFolder,name);
        T=readtable(path,"TextType","string", ...
            "VariableNamingRule","preserve");
        if ~ismember("Status",string(T.Properties.VariableNames))
            error("FULLSTACK:AcceptanceStatusColumnMissing", ...
                "Evidence %s has no Status column.",name);
        end
        mask=true(height(T),1);
        if contains(op,"REQUIRED") && ...
                ismember("Required",string(T.Properties.VariableNames))
            mask=localTruth(T.Required);
        elseif contains(op,"REQUIRED") && ...
                ismember("Mandatory",string(T.Properties.VariableNames))
            mask=localTruth(T.Mandatory);
        end
        checked=checked+nnz(mask);
        failed=failed+nnz(mask & upper(string(T.Status))~="PASS");
    end
    passed=checked>0&&failed==0;observed=localStatus(passed);
    return;
end
error("FULLSTACK:UnsupportedAcceptanceOperator", ...
    "Unsupported acceptance operator %s.",op);
end

function path=localFindUnique(root,name)
listing=dir(fullfile(root,"**",char(name)));
listing=listing(~[listing.isdir]);
paths=unique(string(fullfile({listing.folder},{listing.name})));
if numel(paths)~=1
    error("FULLSTACK:AcceptanceEvidenceMissing", ...
        "Acceptance evidence %s resolved to %d files.",name,numel(paths));
end
path=paths(1);
end

function out=localList(value)
out=strip(split(string(value),"|"));
out=out(strlength(out)>0);
end

function tf=localTruth(value)
tf=ismember(lower(strtrim(string(value))),["true","1","yes","pass"]);
end

function value=localStatus(tf)
if tf,value="PASS";else,value="FAIL";end
end
