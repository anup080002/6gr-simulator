function out = runSelectedSubcases(options)
%RUNSELECTEDSUBCASES Execute only explicitly selected canonical subcases.
arguments
    options.ScenarioPath (1,1) string
    options.Preset (1,1) string = "comprehensive_smoke"
    options.SubcaseIDs (:,1) string
    options.ParentRunID (1,1) string
    options.OutputRoot (1,1) string
    options.Strict (1,1) logical = true
end

scenarioPath = localAbsolute(options.ScenarioPath);
outputRoot = localAbsolute(options.OutputRoot);
if ~isfile(scenarioPath)
    error("FULLSTACK:SelectedScenarioMissing", ...
        "Selected-subcase scenario does not exist: %s",scenarioPath);
end
selected = unique(upper(strtrim(options.SubcaseIDs)),"stable");
if isempty(selected) || any(~matches(selected,"SC-"+compose("%02d",(0:30)')))
    error("FULLSTACK:SelectedSubcaseInvalid", ...
        "SubcaseIDs must be a nonempty subset of SC-00..SC-30.");
end
if isfolder(outputRoot) && ~isempty(dir(fullfile(outputRoot,"*")))
    error("FULLSTACK:SelectedOutputNotFresh", ...
        "Selected-subcase output root must be fresh: %s",outputRoot);
end
sixgr.util.ensureFolder(outputRoot);
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
profile = sixgr.integration.qualification. ...
    FullStackQualificationProfile.load(scfg);
if profile.Preset ~= lower(strtrim(options.Preset))
    error("FULLSTACK:SelectedPresetMismatch", ...
        "Scenario resolved preset '%s', not requested '%s'.", ...
        profile.Preset,options.Preset);
end
registry = sixgr.integration.qualification. ...
    FullStackSubcaseRegistry.load(profile);
allIDs = string({registry.SubcaseID})';
if any(~ismember(selected,allIDs))
    error("FULLSTACK:SelectedSubcaseUnknown", ...
        "One or more selected subcases are absent from the registry.");
end
groups = arrayfun(@(id)sixgr.integration.qualification. ...
    ComponentExecutionAdapter.groupFor(id),selected);
if any(ismember(groups,["ORCHESTRATOR","REGRESSION"]))
    error("FULLSTACK:SelectedSubcaseNotIndependentlyRunnable", ...
        "Orchestrator and regression subcases require their dedicated recovery/shard runners.");
end

cfg = sixgr.lls6g.buildInternalConfig(scfg,outputRoot);
cfg.run.runTag = char(options.ParentRunID+"-selected");
ctx = sixgr.integration.qualification. ...
    FullStackRunContext.create(cfg,scfg,outputRoot,profile);
uniqueGroups = unique(groups,"stable");
outcomes = repmat(localOutcome(),numel(uniqueGroups),1);
manifestDir = fullfile(outputRoot,"qualification_evidence", ...
    "selected_subcase_manifests");
sixgr.util.ensureFolder(manifestDir);
for groupIndex = 1:numel(uniqueGroups)
    group = uniqueGroups(groupIndex);
    started = localUTC();
    outcome = sixgr.integration.qualification. ...
        ComponentExecutionAdapter.execute(group,ctx);
    outcomes(groupIndex) = outcome;
    groupIDs = selected(groups==group);
    manifest = table(repmat(options.ParentRunID,numel(groupIDs),1), ...
        groupIDs,repmat(group,numel(groupIDs),1), ...
        repmat(logical(outcome.Executed),numel(groupIDs),1), ...
        repmat(logical(outcome.Passed),numel(groupIDs),1), ...
        repmat(started,numel(groupIDs),1), ...
        repmat(localUTC(),numel(groupIDs),1), ...
        repmat(string(outcome.FailureCode),numel(groupIDs),1), ...
        repmat(string(outcome.Details),numel(groupIDs),1), ...
        'VariableNames',{'ParentRunID','SubcaseID','ExecutionGroup', ...
        'RunnerStarted','RunnerPassed','StartUTC','EndUTC', ...
        'FailureCode','Details'});
    sixgr.integration.qualification.QualificationAtomicWriter. ...
        writeTable(fullfile(manifestDir,lower(group)+ ...
        "_execution_manifest.csv"),manifest);
end

artifactIndex = sixgr.integration.qualification. ...
    RunArtifactIndex.build(outputRoot);
rows = repmat(localRow(),numel(selected),1);
for index = 1:numel(selected)
    id = selected(index);
    item = registry(allIDs==id);
    group = groups(index);
    outcome = outcomes(uniqueGroups==group);
    required = unique([localList(item.RequiredCSV); ...
        localList(item.RequiredPNG)],"stable");
    [present,matched] = localEvidencePresent(artifactIndex,required);
    rows(index).ParentRunID = options.ParentRunID;
    rows(index).SubcaseID = id;
    rows(index).ExecutionGroup = group;
    rows(index).Executed = logical(outcome.Executed);
    rows(index).EvidencePresent = present;
    rows(index).CorrectnessChecked = logical(outcome.Passed);
    rows(index).RequiredArtifacts = strjoin(required,"|");
    rows(index).MatchedArtifacts = strjoin(matched,"|");
    rows(index).Status = localStatus( ...
        outcome.Executed && outcome.Passed && present);
    rows(index).FailureCode = string(outcome.FailureCode);
    if ~present && strlength(rows(index).FailureCode)==0
        rows(index).FailureCode = ...
            "FULLSTACK:SelectedSubcaseEvidenceMissing";
    end
    rows(index).OutputRoot = outputRoot;
end
results = struct2table(rows,"AsArray",true);
resultPath = fullfile(outputRoot,"reports","csv", ...
    "selected_subcase_results.csv");
sixgr.integration.qualification.QualificationAtomicWriter. ...
    writeTable(resultPath,results);
out = struct("CompletedWithoutException",true, ...
    "ParentRunID",options.ParentRunID,"OutputRoot",outputRoot, ...
    "SubcaseResults",results,"Outcomes",outcomes, ...
    "ResultPath",string(resultPath));
if options.Strict && any(string(results.Status)~="PASS")
    error("FULLSTACK:SelectedSubcaseFailed", ...
        "%d selected subcase(s) failed execution or exact evidence gates.", ...
        nnz(string(results.Status)~="PASS"));
end
end

function value=localAbsolute(value)
value=string(value);
if ~isfolder(value) && ~isfile(value) && ~localIsAbsolute(value)
    value=fullfile(pwd,value);
elseif ~localIsAbsolute(value)
    value=fullfile(pwd,value);
end
value=string(char(java.io.File(char(value)).getCanonicalPath()));
end

function tf=localIsAbsolute(value)
tf=~isempty(regexp(char(value),'^(?:[A-Za-z]:[\\/]|\\\\|/)','once'));
end

function list=localList(value)
list=string(value);
list=split(strjoin(list(:),"|"),"|");
list=strtrim(list);
list=list(strlength(list)>0);
end

function [passed,matched]=localEvidencePresent(index,required)
matched=strings(0,1);
passed=true;
for name=reshape(required,1,[])
    [path,uniquePath]=sixgr.integration.qualification. ...
        RunArtifactIndex.findUnique(index,name);
    if ~uniquePath
        passed=false;
    else
        relative=replace(erase(string(path), ...
            string(index.Root)+filesep),"\\","/");
        matched(end+1,1)=relative; %#ok<AGROW>
    end
end
end

function row=localRow()
row=struct("ParentRunID","","SubcaseID","","ExecutionGroup","", ...
    "Executed",false,"EvidencePresent",false, ...
    "CorrectnessChecked",false,"RequiredArtifacts","", ...
    "MatchedArtifacts","","Status","FAIL","FailureCode","", ...
    "OutputRoot","");
end

function row=localOutcome()
row=struct("Group","","Executed",false,"Passed",false, ...
    "FailureCode","","Details","","OutputDir","", ...
    "DurationSeconds",NaN,"Summary",struct());
end

function value=localStatus(tf)
if tf,value="PASS";else,value="FAIL";end
end

function value=localUTC()
value=string(datetime("now","TimeZone","UTC", ...
    "Format","yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end
