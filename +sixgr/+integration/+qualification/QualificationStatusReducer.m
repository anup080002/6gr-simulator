classdef QualificationStatusReducer
    %QUALIFICATIONSTATUSREDUCER Deterministic bottom-up status reduction.
    methods (Static)
        function [components,subcases,trace] = reduce( ...
                profile,runID,originalSubcases,values,negatives, ...
                artifactAudit,regression)
            [components,componentTrace] = localComponents( ...
                profile,runID,originalSubcases,values,negatives, ...
                artifactAudit);
            [subcases,subcaseTrace] = localSubcases( ...
                profile,runID,originalSubcases,components,values, ...
                negatives,artifactAudit,regression);
            trace = [componentTrace;subcaseTrace];
            localAssertHierarchy(components,subcases,values,negatives);
        end

        function results = acceptance(profile,runID,subcases, ...
                components,values,negatives,artifactAudit,regression, ...
                resolver)
            rules = profile.AcceptanceRules;
            n = height(rules);
            requiredField = "RequiredInComprehensiveSmoke";
            if profile.Preset=="deep_acceptance"
                requiredField = "RequiredInDeepAcceptance";
            end
            rows = repmat(localAcceptanceRow(),n,1);
            for index = 1:n
                rows(index).RunID = string(runID);
                rows(index).RuleID = string(rules.RuleID(index));
                rows(index).Category = string(rules.Category(index));
                rows(index).Required = localTruth( ...
                    rules.(requiredField)(index));
                rows(index).Threshold = string(rules.Threshold(index));
                rows(index).EvidenceArtifactID = string( ...
                    rules.EvidenceCSV(index));
                rows(index).FailureCode = string( ...
                    rules.FailureCode(index));
                if ~rows(index).Required
                    rows(index).Status = "PASS";
                    rows(index).Observed = ...
                        "NOT_REQUIRED_FOR_SELECTED_PRESET";
                    rows(index).Details = ...
                        "Rule is outside the selected preset.";
                    continue;
                end
                try
                    [passed,observed,checked,failed] = ...
                        localAcceptanceOperator( ...
                        string(rules.Operator(index)), ...
                        string(rules.EvidenceCSV(index)), ...
                        subcases,components,values,negatives, ...
                        artifactAudit,regression,resolver);
                    rows(index).Status = localStatus(passed);
                    rows(index).Observed = observed;
                    rows(index).RowsChecked = checked;
                    rows(index).RowsFailed = failed;
                    rows(index).Details = ...
                        "Rule reduced from canonical child ledgers.";
                catch ME
                    rows(index).Details = string(ME.identifier) + ...
                        ": " + string(ME.message);
                end
            end
            results = struct2table(rows,"AsArray",true);
        end
    end
end

function [components,trace] = localComponents(profile,runID, ...
    originalSubcases,values,negatives,audit)
contract = profile.Components;
n = height(contract);
rows = repmat(localComponentRow(),n,1);
traceRows = repmat(localReductionRow(),0,1);
mandatoryColumn = "MandatoryInComprehensiveSmoke";
if profile.Preset=="deep_acceptance"
    mandatoryColumn = "MandatoryInDeepAcceptance";
end
for index = 1:n
    componentID = string(contract.ComponentID(index));
    subcaseID = string(contract.SubcaseID(index));
    rows(index).RunID = string(runID);
    rows(index).ComponentID = componentID;
    rows(index).SubcaseID = subcaseID;
    rows(index).Domain = string(contract.Domain(index));
    rows(index).Component = string(contract.Component(index));
    rows(index).Mandatory = localTruth(contract.(mandatoryColumn)(index));
    rows(index).FailureCode = string(contract.FailureCode(index));
    sourceMask = string(originalSubcases.SubcaseID)==subcaseID;
    rows(index).Executed = nnz(sourceMask)==1 && ...
        localTruth(originalSubcases.Executed(sourceMask));

    requiredFiles = unique([localList(contract.RequiredCSV(index)); ...
        localList(contract.RequiredPNG(index))],"stable");
    [artifactPass,artifactIDs,artifactChildren] = ...
        localRequiredArtifacts(requiredFiles,audit);
    rows(index).EvidencePresent = artifactPass;
    rows(index).EvidenceArtifactIDs = strjoin(artifactIDs,"|");

    valueMask = string(values.SubcaseID)==subcaseID & ...
        localTruth(values.Required);
    valuePass = all(string(values.Status(valueMask))=="PASS");
    negativeMask = string(negatives.SubcaseID)==subcaseID & ...
        localTruth(negatives.Mandatory);
    negativePass = all(string(negatives.Status(negativeMask))=="PASS");
    rows(index).CorrectnessChecked = valuePass && negativePass;
    passed = rows(index).Executed && artifactPass && valuePass && ...
        negativePass;
    if ~rows(index).Mandatory
        passed = true;
    end
    rows(index).Status = localStatus(passed);

    traceRows = [traceRows;localChildRows("COMPONENT",componentID, ... %#ok<AGROW>
        "VALUE_CHECK",string(values.CheckID(valueMask)), ...
        string(values.Status(valueMask)),true)];
    traceRows = [traceRows;localChildRows("COMPONENT",componentID, ... %#ok<AGROW>
        "NEGATIVE_CHECK",string(negatives.CaseID(negativeMask)), ...
        string(negatives.Status(negativeMask)),true)];
    traceRows = [traceRows;localChildRows("COMPONENT",componentID, ... %#ok<AGROW>
        "ARTIFACT",artifactChildren.ID,artifactChildren.Status,true)];
    traceRows(end+1,1) = localReductionRowFrom( ... %#ok<AGROW>
        "COMPONENT",componentID,"EXECUTION",subcaseID, ...
        rows(index).Mandatory,localStatus(rows(index).Executed), ...
        "Component inherits execution from its canonical subcase.");
end
components = struct2table(rows,"AsArray",true);
trace = struct2table(traceRows,"AsArray",true);
end

function [subcases,trace] = localSubcases(profile,runID, ...
    originalSubcases,components,values,negatives,audit,regression)
contract = profile.Subcases;
n = height(contract);
rows = repmat(localSubcaseRow(),n,1);
traceRows = repmat(localReductionRow(),0,1);
for index = 1:n
    subcaseID = string(contract.SubcaseID(index));
    rows(index).RunID = string(runID);
    rows(index).SubcaseID = subcaseID;
    rows(index).Name = string(contract.Name(index));
    rows(index).Category = string(contract.Category(index));
    rows(index).Direction = string(contract.Direction(index));
    rows(index).Mandatory = localTruth(contract.Mandatory(index));
    sourceMask = string(originalSubcases.SubcaseID)==subcaseID;
    rows(index).Executed = nnz(sourceMask)==1 && ...
        localTruth(originalSubcases.Executed(sourceMask));

    componentMask = string(components.SubcaseID)==subcaseID & ...
        localTruth(components.Mandatory);
    valueMask = string(values.SubcaseID)==subcaseID & ...
        localTruth(values.Required);
    negativeMask = string(negatives.SubcaseID)==subcaseID & ...
        localTruth(negatives.Mandatory);
    requiredFiles = unique([localList(contract.RequiredCSV(index)); ...
        localList(contract.RequiredPNG(index))],"stable");
    [artifactPass,~,artifactChildren] = ...
        localRequiredArtifacts(requiredFiles,audit);
    componentPass = all(string(components.Status(componentMask))=="PASS");
    valuePass = all(string(values.Status(valueMask))=="PASS");
    negativePass = all(string(negatives.Status(negativeMask))=="PASS");
    regressionPass = true;
    if subcaseID=="SC-30"
        regressionPass = ~isempty(regression) && ...
            all(string(regression.Status)=="PASS") && ...
            all(double(regression.SkippedTests)==0) && ...
            all(double(regression.BlockedTests)==0);
    end
    passed = rows(index).Executed && componentPass && valuePass && ...
        negativePass && artifactPass && regressionPass;
    if ~rows(index).Mandatory
        passed = true;
    end
    rows(index).Status = localStatus(passed);
    [rows(index).FailureCode,rows(index).Details] = ...
        localSubcaseFailure(rows(index),componentPass,valuePass, ...
        negativePass,artifactPass,regressionPass);

    traceRows = [traceRows;localChildRows("SUBCASE",subcaseID, ... %#ok<AGROW>
        "COMPONENT",string(components.ComponentID(componentMask)), ...
        string(components.Status(componentMask)),true)];
    traceRows = [traceRows;localChildRows("SUBCASE",subcaseID, ... %#ok<AGROW>
        "VALUE_CHECK",string(values.CheckID(valueMask)), ...
        string(values.Status(valueMask)),true)];
    traceRows = [traceRows;localChildRows("SUBCASE",subcaseID, ... %#ok<AGROW>
        "NEGATIVE_CHECK",string(negatives.CaseID(negativeMask)), ...
        string(negatives.Status(negativeMask)),true)];
    traceRows = [traceRows;localChildRows("SUBCASE",subcaseID, ... %#ok<AGROW>
        "ARTIFACT",artifactChildren.ID,artifactChildren.Status,true)];
    if subcaseID=="SC-30"
        traceRows = [traceRows;localChildRows("SUBCASE",subcaseID, ... %#ok<AGROW>
            "REGRESSION_SUITE",string(regression.Suite), ...
            string(regression.Status),true)];
    end
end
subcases = struct2table(rows,"AsArray",true);
trace = struct2table(traceRows,"AsArray",true);
end

function [passed,ids,children] = localRequiredArtifacts(names,audit)
ids = strings(0,1);
childID = strings(0,1);
childStatus = strings(0,1);
passed = true;
for name = reshape(names,1,[])
    mask = string(audit.FileName)==name;
    if nnz(mask)~=1
        passed = false;
        childID(end+1,1) = name; %#ok<AGROW>
        childStatus(end+1,1) = "FAIL"; %#ok<AGROW>
    else
        ids(end+1,1) = string(audit.ArtifactID(mask)); %#ok<AGROW>
        childID(end+1,1) = string(audit.ArtifactID(mask)); %#ok<AGROW>
        childStatus(end+1,1) = string(audit.Status(mask)); %#ok<AGROW>
        passed = passed && string(audit.Status(mask))=="PASS";
    end
end
children = struct("ID",childID,"Status",childStatus);
end

function [code,details] = localSubcaseFailure(row,components,values, ...
    negatives,artifacts,regression)
if row.Status=="PASS"
    code = "";
    details = "All mandatory child gates passed bottom-up reduction.";
elseif ~row.Executed
    code = "FULLSTACK:SubcaseNotExecuted";
    details = "Canonical source subcase was not executed.";
elseif ~components
    code = "FULLSTACK:MandatoryComponentFailure";
    details = "One or more mandatory child components failed.";
elseif ~values
    code = "FULLSTACK:MandatoryValueFailure";
    details = "One or more mandatory child value checks failed.";
elseif ~negatives
    code = "FULLSTACK:MandatoryNegativeFailure";
    details = "One or more mandatory negative checks failed.";
elseif ~artifacts
    code = "FULLSTACK:RequiredSubcaseEvidenceInvalid";
    details = "One or more required subcase artifacts are missing or invalid.";
elseif ~regression
    code = "FULLSTACK:RegressionIncomplete";
    details = "A required regression suite is failed, skipped, or blocked.";
else
    code = "FULLSTACK:SubcaseFailure";
    details = "Subcase failed bottom-up reduction.";
end
end

function localAssertHierarchy(components,subcases,values,negatives)
for index = 1:height(subcases)
    if string(subcases.Status(index))~="PASS"
        continue;
    end
    id = string(subcases.SubcaseID(index));
    cm = string(components.SubcaseID)==id & localTruth(components.Mandatory);
    vm = string(values.SubcaseID)==id & localTruth(values.Required);
    nm = string(negatives.SubcaseID)==id & localTruth(negatives.Mandatory);
    if any(string(components.Status(cm))~="PASS") || ...
            any(~localTruth(components.CorrectnessChecked(cm))) || ...
            any(string(values.Status(vm))~="PASS") || ...
            any(string(negatives.Status(nm))~="PASS")
        error("FULLSTACK:IllegalParentChildStatus", ...
            "Subcase %s passed while a mandatory child failed.",id);
    end
end
end

function [passed,observed,checked,failed] = localAcceptanceOperator( ...
    operator,evidenceNames,subcases,components,values,negatives, ...
    audit,regression,resolver)
op = upper(strtrim(string(operator)));
token = regexp(char(op),'^STATUS\(([^)]+)\)$','tokens','once');
if ~isempty(token)
    id = string(token{1});
    if startsWith(id,"SC-")
        T=subcases; key="SubcaseID";
    elseif startsWith(id,"COMP-")
        T=components; key="ComponentID";
    elseif startsWith(id,"VALCHK-")
        T=values; key="CheckID";
    else
        error("FULLSTACK:UnknownAcceptanceStatusID", ...
            "Unknown acceptance ID '%s'.",id);
    end
    mask=string(T.(char(key)))==id;
    checked=nnz(mask);
    failed=nnz(mask & string(T.Status)~="PASS");
    passed=checked==1 && failed==0;
    observed=localStatus(passed);
    return;
end
token = regexp(char(op), ...
    '^NEGATIVE_STATUS\(([^)]+)\)$','tokens','once');
if ~isempty(token)
    id=string(token{1});
    mask=string(negatives.CaseID)==id;
    checked=nnz(mask);
    failed=nnz(mask & string(negatives.Status)~="PASS");
    passed=checked==1 && failed==0;
    observed=localStatus(passed);
    return;
end
if ~ismember(op,["ALL_PASS","ALL_REQUIRED_PASS", ...
        "ALL_DEEP_REQUIRED_PASS"])
    error("FULLSTACK:UnsupportedAcceptanceOperator", ...
        "Unsupported acceptance operator '%s'.",op);
end
names=localList(evidenceNames);
checked=0;
failed=0;
for name=reshape(names,1,[])
    T=localAcceptanceTable(name,subcases,components,values, ...
        negatives,audit,regression,resolver);
    mask=true(height(T),1);
    if contains(op,"REQUIRED")
        if ismember("Required",string(T.Properties.VariableNames))
            mask=localTruth(T.Required);
        elseif ismember("Mandatory",string(T.Properties.VariableNames))
            mask=localTruth(T.Mandatory);
        elseif ismember("RequiredForPreset", ...
                string(T.Properties.VariableNames))
            mask=localTruth(T.RequiredForPreset);
        end
    end
    if ~ismember("Status",string(T.Properties.VariableNames))
        error("FULLSTACK:AcceptanceStatusColumnMissing", ...
            "Acceptance evidence '%s' has no Status column.",name);
    end
    checked=checked+nnz(mask);
    failed=failed+nnz(mask & upper(string(T.Status))~="PASS");
end
passed=checked>0 && failed==0;
observed=localStatus(passed);
end

function T = localAcceptanceTable(name,subcases,components,values, ...
    negatives,audit,regression,resolver)
switch string(name)
    case "full_stack_subcase_status.csv", T=subcases;
    case "full_stack_component_coverage_results.csv", T=components;
    case "full_stack_value_correctness_results.csv", T=values;
    case "full_stack_negative_fault_injection_results.csv", T=negatives;
    case "full_stack_artifact_audit.csv", T=audit;
    case "full_stack_regression_summary.csv", T=regression;
    otherwise
        loaded=sixgr.integration.qualification. ...
            QualificationTableLoader.load(resolver,name,"Status",false);
        T=loaded.Table;
end
end

function rows = localChildRows(parentType,parentID,childType,ids,status,required)
rows = repmat(localReductionRow(),numel(ids),1);
for index=1:numel(ids)
    rows(index)=localReductionRowFrom(parentType,parentID, ...
        childType,ids(index),required,status(index), ...
        "Bottom-up mandatory child binding.");
end
end

function row = localReductionRowFrom(parentType,parentID,childType, ...
    childID,required,status,reason)
row=localReductionRow();
row.ParentType=string(parentType);
row.ParentID=string(parentID);
row.ChildType=string(childType);
row.ChildID=string(childID);
row.Required=logical(required);
row.ChildStatus=string(status);
row.ParentPassContribution=~required || string(status)=="PASS";
row.Reason=string(reason);
end

function row = localComponentRow()
row=struct("RunID","","ComponentID","","SubcaseID","", ...
    "Domain","","Component","","Mandatory",false,"Executed",false, ...
    "EvidencePresent",false,"CorrectnessChecked",false, ...
    "Status","FAIL","FailureCode","","EvidenceArtifactIDs","");
end

function row = localSubcaseRow()
row=struct("RunID","","SubcaseID","","Name","","Category","", ...
    "Direction","","Mandatory",false,"Executed",false, ...
    "Status","FAIL","FailureCode","","Details","");
end

function row = localReductionRow()
row=struct("ParentType","","ParentID","","ChildType","", ...
    "ChildID","","Required",false,"ChildStatus","", ...
    "ParentPassContribution",false,"Reason","");
end

function row = localAcceptanceRow()
row=struct("RunID","","RuleID","","Category","","Required",false, ...
    "Status","FAIL","Observed","","Threshold","","RowsChecked",0, ...
    "RowsFailed",0,"EvidenceArtifactID","","FailureCode","", ...
    "Details","");
end

function values=localList(raw)
values=strip(split(string(raw),"|"));
values=values(strlength(values)>0);
end

function tf=localTruth(value)
tf=ismember(lower(strtrim(string(value))), ...
    ["true","1","yes","pass","required"]);
end

function value=localStatus(tf)
if tf,value="PASS";else,value="FAIL";end
end
