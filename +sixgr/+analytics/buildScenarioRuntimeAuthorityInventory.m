function out = buildScenarioRuntimeAuthorityInventory(scenarioPath, outputRoot, repoRoot)
%BUILDSCENARIORUNTIMEAUTHORITYINVENTORY Classify scenario runtime ownership.
%
% This is a pre-run authority audit. It joins the YAML-declared causal PHY
% stages and parameter consumers to the complete +sixgr source/function
% inventory. A direct scenario owner may be a production runtime library or
% a reporting producer, but it may never be a TDoc, study, validation,
% oracle, impact-analysis, or legacy implementation. Indirect runtime
% helpers remain eligible without being falsely labelled dead code.

arguments
    scenarioPath {mustBeTextScalar}
    outputRoot {mustBeTextScalar}
    repoRoot {mustBeTextScalar} = pwd
end

scenarioPath = char(string(scenarioPath));
outputRoot = char(string(outputRoot));
repoRoot = char(string(repoRoot));
sixgr.util.ensureFolder(outputRoot);

scratch = tempname;
mkdir(scratch);
cleanup = onCleanup(@() localCleanup(scratch)); %#ok<NASGU>
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(scratch, "runtime_config"));
sourceAudit = sixgr.analytics.buildPHYPackageExecutionAudit( ...
    fullfile(scratch, "source_audit"), repoRoot);

auditCfg = sixgr.util.structGet(cfg, ...
    "validation.causal_phy_chain_audit", struct());
stages = localStructArray(sixgr.util.structGet(auditCfg, ...
    "stages", struct([])));
bindings = localStructArray(sixgr.util.structGet(auditCfg, ...
    "parameter_bindings", struct([])));

declared = containers.Map('KeyType','char','ValueType','any');
for index = 1:numel(stages)
    spec = stages(index);
    required = localLogical(sixgr.util.structGet(spec, "required", true), true);
    applicable = localStageApplicable(spec, scfg, cfg);
    stageId = string(sixgr.util.structGet(spec, "stage_id", ""));
    subsystem = string(sixgr.util.structGet(spec, "subsystem", ""));
    motive = "stage:" + stageId + ":" + subsystem;
    files = localStringList(sixgr.util.structGet(spec, ...
        "consumer_source_files", strings(0,1)));
    declared = localAddDeclarations(declared, files, motive, ...
        "causal_stage", required && applicable);
end
for index = 1:numel(bindings)
    spec = bindings(index);
    required = localLogical(sixgr.util.structGet(spec, "required", true), true);
    applicable = localBindingApplicable(spec, cfg);
    parameterId = string(sixgr.util.structGet(spec, "parameter_id", ""));
    subsystem = string(sixgr.util.structGet(spec, "subsystem", ""));
    motive = "parameter:" + parameterId + ":" + subsystem;
    files = localStringList(sixgr.util.structGet(spec, ...
        "consumer_source_files", strings(0,1)));
    declared = localAddDeclarations(declared, files, motive, ...
        "parameter_binding", required && applicable);
end

inventory = sourceAudit.DetailTable;
rows = repmat(localEmptyFileRow(), height(inventory), 1);
seen = containers.Map('KeyType','char','ValueType','logical');
for index = 1:height(inventory)
    row = localEmptyFileRow();
    row.FilePath = replace(string(inventory.FilePath(index)), "\", "/");
    key = char(lower(row.FilePath));
    seen(key) = true;
    row.QualifiedName = string(inventory.QualifiedName(index));
    row.Package = string(inventory.Package(index));
    row.PrimaryFunctionOrClass = string(inventory.PrimaryFunctionOrClass(index));
    row.SourceRole = string(inventory.SourceRole(index));
    row.RuntimeEligibility = string(inventory.RuntimeEligibility(index));
    row.ScenarioInputPolicy = string(inventory.ScenarioInputPolicy(index));
    row.FileExists = isfile(fullfile(repoRoot, char(row.FilePath)));
    if isKey(declared, key)
        item = declared(key);
        row.DeclaredByScenario = true;
        row.RequiredForScenario = logical(item.Required);
        row.DeclarationKind = strjoin(unique(item.Kind, "stable"), "|");
        row.Motive = strjoin(unique(item.Motive, "stable"), "|");
        row.DeclarationCount = numel(item.Motive);
    else
        row.Motive = localDefaultMotive(row.SourceRole, row.Package);
    end
    row.DuplicateSymbolAssessment = string(inventory.SameBasenameAssessment(index));
    row.AuthorityAllowed = localAuthorityAllowed(row.RuntimeEligibility);
    row.Category = localCategory(row);
    [row.RecommendedAction, row.FailureReason] = localRecommendation(row);
    row.PreRunPass = strlength(row.FailureReason) == 0;
    rows(index) = row;
end

declaredKeys = string(keys(declared));
for keyValue = declaredKeys(:).'
    key = char(keyValue);
    if isKey(seen, key)
        continue;
    end
    item = declared(key);
    row = localEmptyFileRow();
    row.FilePath = string(keyValue);
    row.DeclaredByScenario = true;
    row.RequiredForScenario = logical(item.Required);
    row.DeclarationKind = strjoin(unique(item.Kind, "stable"), "|");
    row.Motive = strjoin(unique(item.Motive, "stable"), "|");
    row.DeclarationCount = numel(item.Motive);
    row.Category = "MISSING_DECLARED_OWNER";
    row.RecommendedAction = "ADD_RUNTIME_OWNER_OR_REBIND_YAML";
    row.FailureReason = "declared_consumer_file_missing";
    row.PreRunPass = false;
    rows(end+1,1) = row; %#ok<AGROW>
end

fileT = struct2table(rows, "AsArray", true);
fileT = sortrows(fileT, ...
    ["RequiredForScenario","DeclaredByScenario","Category","FilePath"], ...
    ["descend","descend","ascend","ascend"]);
functionT = localBuildFunctionAuthorityTable(sourceAudit.FunctionTable, fileT);
requiredMask = fileT.RequiredForScenario;
requiredFailureMask = requiredMask & ~fileT.PreRunPass;
misclassifiedMask = requiredMask & ~fileT.AuthorityAllowed;
missingMask = requiredMask & ~fileT.FileExists;
duplicateMask = fileT.DuplicateSymbolAssessment == "UNRESOLVED_DUPLICATE_NAME";

gateT = table(string(scfg.ScenarioID), string(scfg.ConfigHash), ...
    height(fileT), height(functionT), sum(fileT.DeclaredByScenario), ...
    sum(requiredMask), sum(requiredFailureMask), sum(missingMask), ...
    sum(misclassifiedMask), sum(duplicateMask), ~any(requiredFailureMask), ...
    'VariableNames', {'ScenarioID','ConfigHash','SourceFileCount', ...
    'DeclaredFunctionCount','ScenarioDeclaredOwnerCount', ...
    'RequiredRuntimeOwnerCount','RequiredOwnerFailureCount', ...
    'MissingRequiredOwnerCount','MisclassifiedRequiredOwnerCount', ...
    'UnresolvedDuplicateSymbolCount','PreRunAuthorityPass'});

layout = sixgr.report.resultLayout(outputRoot);
sixgr.util.ensureFolder(layout.ReportCSVDir);
filePath = fullfile(layout.ReportCSVDir, ...
    "scenario_runtime_file_authority_inventory.csv");
functionPath = fullfile(layout.ReportCSVDir, ...
    "scenario_runtime_function_authority_inventory.csv");
gatePath = fullfile(layout.ReportCSVDir, ...
    "scenario_runtime_authority_gate.csv");
sixgr.util.csvWriteTable(filePath, fileT);
sixgr.util.csvWriteTable(functionPath, functionT);
sixgr.util.csvWriteTable(gatePath, gateT);

out = struct("FileTable", fileT, "FunctionTable", functionT, ...
    "GateTable", gateT, "FileInventoryPath", string(filePath), ...
    "FunctionInventoryPath", string(functionPath), ...
    "GatePath", string(gatePath), ...
    "PreRunAuthorityPass", logical(gateT.PreRunAuthorityPass));
end

function declared = localAddDeclarations(declared, files, motive, kind, required)
for file = files(:).'
    key = char(lower(replace(strtrim(file), "\", "/")));
    if isempty(key)
        continue;
    end
    if isKey(declared, key)
        item = declared(key);
    else
        item = struct("Motive",strings(0,1),"Kind",strings(0,1), ...
            "Required",false);
    end
    item.Motive(end+1,1) = string(motive);
    item.Kind(end+1,1) = string(kind);
    item.Required = logical(item.Required || required);
    declared(key) = item;
end
end

function applicable = localStageApplicable(spec, scfg, cfg)
if localLogical(sixgr.util.structGet(spec, "always_required", false), false)
    applicable = true;
    return;
end
feature = string(sixgr.util.structGet(spec, "feature_authority", ""));
if strlength(feature) > 0
    applicable = localLogical(sixgr.util.structGet(cfg, ...
        "runtime.features." + feature + ".Enabled", false), false);
    return;
end
pathValue = string(sixgr.util.structGet(spec, "scenario_enable_path", ""));
if strlength(pathValue) == 0
    applicable = true;
else
    applicable = localLogical(scfg.get(pathValue, false), false);
end
end

function applicable = localBindingApplicable(spec, cfg)
feature = string(sixgr.util.structGet(spec, "feature_authority", ""));
if strlength(feature) == 0
    applicable = true;
else
    applicable = localLogical(sixgr.util.structGet(cfg, ...
        "runtime.features." + feature + ".Enabled", false), false);
end
end

function allowed = localAuthorityAllowed(eligibility)
allowed = any(string(eligibility) == ...
    ["PRODUCTION_RUNTIME_ELIGIBLE","REPORTING_ONLY"]);
end

function value = localCategory(row)
if row.RequiredForScenario && ~row.FileExists
    value = "MISSING_DECLARED_OWNER";
elseif row.RequiredForScenario && ~row.AuthorityAllowed
    value = "MISCLASSIFIED_REQUIRED_OWNER";
elseif row.RequiredForScenario
    value = "REQUIRED_RUNTIME_OWNER";
elseif row.DeclaredByScenario && row.AuthorityAllowed
    value = "OPTIONAL_RUNTIME_OWNER";
elseif row.RuntimeEligibility == "PRODUCTION_RUNTIME_ELIGIBLE"
    value = "INDIRECT_RUNTIME_LIBRARY";
elseif row.RuntimeEligibility == "REPORTING_ONLY"
    value = "REPORTING_SUPPORT";
elseif contains(row.RuntimeEligibility, ["ISOLATED","OFFLINE", ...
        "ORACLE","VALIDATION"])
    value = "ISOLATED_STUDY_OR_VALIDATION";
elseif row.RuntimeEligibility == "LEGACY_NOT_PRODUCTION"
    value = "LEGACY_NOT_RUNTIME";
else
    value = "ARCHITECTURE_REVIEW_REQUIRED";
end
end

function [action, reason] = localRecommendation(row)
action = "KEEP_CLASSIFIED";
reason = "";
if row.RequiredForScenario && ~row.FileExists
    action = "ADD_RUNTIME_OWNER_OR_REBIND_YAML";
    reason = "required_runtime_owner_missing";
elseif row.RequiredForScenario && ~row.AuthorityAllowed
    action = "MOVE_CAPABILITY_TO_RUNTIME_OWNER_AND_REBIND";
    reason = "required_owner_is_study_validation_or_legacy";
elseif row.DuplicateSymbolAssessment == "UNRESOLVED_DUPLICATE_NAME"
    action = "RESOLVE_DUPLICATE_SYMBOL_AUTHORITY";
    reason = "unresolved_duplicate_symbol";
elseif row.RequiredForScenario
    action = "KEEP_RUNTIME_OWNER";
elseif row.Category == "INDIRECT_RUNTIME_LIBRARY"
    action = "KEEP_INDIRECT_RUNTIME_DEPENDENCY";
elseif row.Category == "ISOLATED_STUDY_OR_VALIDATION"
    action = "KEEP_STUDY_ONLY_DO_NOT_USE_AS_DEFAULT";
elseif row.Category == "LEGACY_NOT_RUNTIME"
    action = "KEEP_OUT_OF_PRODUCTION_RUNTIME";
end
end

function motive = localDefaultMotive(role, packageName)
switch string(role)
    case {"runtime_library","waveform_runtime_campaign"}
        motive = "indirect production support for " + string(packageName);
    case "artifact_reporting"
        motive = "persist measured runtime evidence and reports";
    case "tdoc_campaign"
        motive = "explicit TDoc study; never a runtime default";
    case "offline_study"
        motive = "explicit offline study; never a runtime default";
    case "offline_impact_analysis"
        motive = "offline paired impact analysis over measured evidence";
    case "validation_campaign"
        motive = "focused validation campaign";
    case "validation_oracle"
        motive = "independent validation oracle";
    otherwise
        motive = "architecture support classified as " + string(role);
end
end

function T = localBuildFunctionAuthorityTable(sourceFunctions, fileT)
T = sourceFunctions;
n = height(T);
T.ScenarioDeclaredOwner = false(n,1);
T.RequiredForScenario = false(n,1);
T.FileCategory = strings(n,1);
T.Motive = strings(n,1);
T.RecommendedAction = strings(n,1);
T.PreRunPass = true(n,1);
fileKeys = lower(replace(string(fileT.FilePath), "\", "/"));
for index = 1:n
    key = lower(replace(string(T.FilePath(index)), "\", "/"));
    match = find(fileKeys == key, 1, "first");
    if isempty(match)
        T.FileCategory(index) = "SOURCE_FILE_NOT_IN_AUTHORITY_INVENTORY";
        T.RecommendedAction(index) = "INVESTIGATE_SOURCE_INVENTORY";
        T.PreRunPass(index) = false;
        continue;
    end
    T.ScenarioDeclaredOwner(index) = fileT.DeclaredByScenario(match);
    T.RequiredForScenario(index) = fileT.RequiredForScenario(match);
    T.FileCategory(index) = fileT.Category(match);
    T.Motive(index) = fileT.Motive(match);
    T.RecommendedAction(index) = fileT.RecommendedAction(match);
    T.PreRunPass(index) = fileT.PreRunPass(match);
end
end

function row = localEmptyFileRow()
row = struct("FilePath","","QualifiedName","","Package","", ...
    "PrimaryFunctionOrClass","","SourceRole","", ...
    "RuntimeEligibility","","ScenarioInputPolicy","", ...
    "FileExists",false,"DeclaredByScenario",false, ...
    "RequiredForScenario",false,"DeclarationKind","", ...
    "DeclarationCount",0,"Motive","", ...
    "DuplicateSymbolAssessment","","AuthorityAllowed",false, ...
    "Category","","RecommendedAction","","FailureReason","", ...
    "PreRunPass",true);
end

function values = localStringList(value)
if isempty(value)
    values = strings(0,1);
elseif iscell(value)
    values = string(value(:));
else
    values = string(value(:));
end
values = strtrim(values);
values(values == "") = [];
end

function list = localStructArray(value)
if isempty(value)
    list = struct([]);
elseif isstruct(value)
    list = value(:);
elseif iscell(value)
    if ~all(cellfun(@(x) isstruct(x) && isscalar(x), value(:)))
        error("sixgr:analytics:ScenarioRuntimeAuthorityBadRegistry", ...
            "The causal runtime registry contains a non-struct item.");
    end
    fieldUnion = strings(0,1);
    for itemIndex = 1:numel(value)
        fieldUnion = union(fieldUnion, ...
            string(fieldnames(value{itemIndex})), "stable");
    end
    normalized = value(:);
    for itemIndex = 1:numel(normalized)
        for fieldName = fieldUnion(:).'
            if ~isfield(normalized{itemIndex}, char(fieldName))
                normalized{itemIndex}.(char(fieldName)) = [];
            end
        end
        normalized{itemIndex} = orderfields(normalized{itemIndex}, ...
            cellstr(fieldUnion));
    end
    list = vertcat(normalized{:});
    list = list(:);
else
    error("sixgr:analytics:ScenarioRuntimeAuthorityBadRegistry", ...
        "The causal runtime registry must contain structs.");
end
end

function value = localLogical(raw, defaultValue)
if isempty(raw)
    value = logical(defaultValue);
elseif islogical(raw) || isnumeric(raw)
    value = logical(raw(1));
else
    token = lower(strtrim(string(raw(1))));
    if any(token == ["true","1","yes","on","enabled"])
        value = true;
    elseif any(token == ["false","0","no","off","disabled"])
        value = false;
    else
        value = logical(defaultValue);
    end
end
end

function localCleanup(folder)
if isfolder(folder)
    rmdir(folder, "s");
end
end
