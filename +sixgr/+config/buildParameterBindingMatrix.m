function T = buildParameterBindingMatrix(scenarioConfig, cfg, runtimeArtifacts, options)
%BUILDPARAMETERBINDINGMATRIX Build a browser->MATLAB->runtime binding matrix.

if nargin < 3 || ~isstruct(runtimeArtifacts)
    runtimeArtifacts = struct();
end
if nargin < 4 || ~isstruct(options)
    options = struct();
end

scenarioStruct = localScenarioStruct(scenarioConfig);
overlayStruct = sixgr.util.structGet(runtimeArtifacts, "OverlayStruct", struct());
baseStruct = sixgr.util.structGet(runtimeArtifacts, "BaseStruct", struct());
dbStruct = sixgr.util.structGet(runtimeArtifacts, "DBConfigStruct", struct());
if isfield(dbStruct, "lls6g") && isstruct(dbStruct.lls6g)
    submittedFromDB = sixgr.util.structGet(dbStruct, "lls6g.submittedScenarioConfig", struct());
    if isstruct(submittedFromDB) && ~isempty(fieldnames(submittedFromDB)) && isempty(fieldnames(overlayStruct))
        overlayStruct = submittedFromDB;
    end
end
runFolder = char(string(sixgr.util.structGet(runtimeArtifacts, "RunFolder", "")));
applicationEvidence = sixgr.util.structGet(runtimeArtifacts, "ApplicationEvidence", table());
registryHints = localNormalizeRegistryHints(sixgr.util.structGet(runtimeArtifacts, "RegistryHints", struct([])));

contractRows = localLoadContractRows();
taxonomyRows = localLoadTaxonomyRows();

scenarioLeaves = localFlattenLeafMap(scenarioStruct);
overlayLeaves = localFlattenLeafMap(overlayStruct);
baseLeaves = localFlattenLeafMap(baseStruct);

% Build invocation-local indexes once.  The ownership inventory contains
% thousands of leaves; rescanning the full contract, evidence table and leaf
% vectors for every parameter made strict finalization quadratic and consumed
% several minutes after even a three-point waveform run.  These maps change
% lookup cost only; values and first/last-row precedence remain identical.
contractIndex = localBuildContractIndex(contractRows);
registryHintIndex = localBuildRegistryHintIndex(registryHints);
scenarioLeafIndex = localBuildLeafIndex(scenarioLeaves);
overlayLeafIndex = localBuildLeafIndex(overlayLeaves);
baseLeafIndex = localBuildLeafIndex(baseLeaves);
evidenceIndex = localBuildEvidenceIndex(applicationEvidence);

parameterIds = strings(0, 1);
parameterIds = [parameterIds; string({contractRows.ParameterId}).']; %#ok<AGROW>
parameterIds = [parameterIds; string({scenarioLeaves.Path}).']; %#ok<AGROW>
parameterIds = [parameterIds; string({overlayLeaves.Path}).']; %#ok<AGROW>
parameterIds = unique(parameterIds(strlength(strtrim(parameterIds)) > 0), "stable");

% Several parameters intentionally bind to the same large runtime table.
% Cache each table for this matrix build so the audit remains proportional
% to the number of distinct artifacts rather than reparsing a multi-megabyte
% CSV once per parameter. containers.Map is a handle object, so the local
% resolver can populate the invocation-scoped cache without global state.
measuredArtifactCache = containers.Map("KeyType", "char", "ValueType", "any");

rows = repmat(localEmptyBindingRow(), numel(parameterIds), 1);
for i = 1:numel(parameterIds)
    parameterId = string(parameterIds(i));
    contract = localFindContractRowIndexed(contractIndex, parameterId);
    taxonomy = localFindTaxonomyRow(taxonomyRows, parameterId);
    registryHint = localFindRegistryHintIndexed(registryHintIndex, parameterId);

    browserPath = localCoalesceString(localGetField(contract, "BrowserPath", ""), parameterId);
    scenarioPath = localCoalesceString(localGetField(contract, "ScenarioPath", ""), browserPath);
    internalCfgPath = localCoalesceString(localGetField(contract, "InternalCfgPath", ""), localGetField(registryHint, "InternalCfgPath", ""));
    aliases = localConcatStringVectors(localGetField(contract, "Aliases", strings(0, 1)), localGetField(registryHint, "Aliases", strings(0, 1)));
    consumerFunctions = localConcatStringVectors(localGetField(contract, "MATLABConsumerFunctions", strings(0, 1)), localGetField(registryHint, "MATLABConsumerFunctions", strings(0, 1)));
    runtimeObjectPath = localGetField(contract, "RuntimeObjectPath", "");
    measuredArtifact = localCoalesceString(localGetField(contract, "MeasuredArtifact", ""), localGetField(registryHint, "MeasuredArtifact", ""));
    measuredField = localCoalesceString(localGetField(contract, "MeasuredField", ""), localGetField(registryHint, "MeasuredField", ""));
    if strlength(measuredArtifact) == 0 || strlength(measuredField) == 0
        [measuredArtifact, measuredField] = localDefaultMeasuredMapping(parameterId);
    end

    [submittedValue, submittedFound] = localTryGetLeafIndexed(overlayLeafIndex, browserPath);
    [baseValue, baseFound] = localTryGetLeafIndexed(baseLeafIndex, scenarioPath);
    [resolvedScenarioValue, resolvedFound] = localTryGetLeafIndexed(scenarioLeafIndex, scenarioPath);
    [internalCfgValue, internalFound] = localGetInternalValue(cfg, internalCfgPath, aliases);
    [dbValue, dbFound] = localTryGet(dbStruct, scenarioPath);
    if ~dbFound && strlength(internalCfgPath) > 0
        [dbValue, dbFound] = localTryGet(dbStruct, internalCfgPath);
    end

    contractClassification = localGetField(contract, "Classification", "");
    if strlength(contractClassification) == 0
        contractClassification = localInferClassification(parameterId, submittedFound, resolvedFound, internalFound);
    end

    defaultBrowserVisible = localInferBrowserVisible(parameterId);
    registryBrowserVisible = localToLogicalMaybe(localGetField(registryHint, "BrowserVisible", []));
    if ~isempty(registryBrowserVisible) && registryBrowserVisible
        defaultBrowserVisible = true;
    end
    browserVisible = localInferLogical(localGetField(contract, "BrowserVisible", []), defaultBrowserVisible);
    defaultBrowserEditable = browserVisible;
    registryBrowserEditable = localToLogicalMaybe(localGetField(registryHint, "BrowserEditable", []));
    if ~isempty(registryBrowserEditable) && registryBrowserEditable
        defaultBrowserEditable = true;
    end
    browserEditable = localInferLogical(localGetField(contract, "BrowserEditable", []), defaultBrowserEditable);
    [inferredFeatureFamily,inferredUISection] = localInferTaxonomy(parameterId);
    featureFamily = localCoalesceString(localGetField(contract, "FeatureFamily", ""), localGetField(taxonomy, "FeatureFamily", ""), localGetField(registryHint, "FeatureFamily", ""), inferredFeatureFamily);
    uiLayer = localCoalesceString(localGetField(contract, "UILayer", ""), localGetField(taxonomy, "UILayer", ""), localGetField(registryHint, "UILayer", ""), "Outputs");
    uiSection = localCoalesceString(localGetField(contract, "UISection", ""), localGetField(taxonomy, "UISection", ""), localGetField(registryHint, "UISection", ""), inferredUISection);
    supportStatus = localCoalesceString(localGetField(contract, "SupportStatus", ""), localInferSupportStatus(consumerFunctions, contractClassification));
    sharedDependency = localInferLogical(localGetField(contract, "SharedDependency", []), localGetField(taxonomy, "SharedDependency", false));
    appliesWhen = localGetField(contract, "AppliesWhen", strings(0, 1));
    if isempty(appliesWhen)
        appliesWhen = localGetField(taxonomy, "AppliesWhen", strings(0, 1));
    end

    evidenceRow = localFindEvidenceRowIndexed(evidenceIndex, parameterId);
    runtimeAppliedArtifact = "";
    runtimeAppliedField = "";
    runtimeAppliedValue = "";
    if ~isempty(evidenceRow)
        runtimeAppliedArtifact = "reports/csv/runtime_config_application_evidence.csv";
        runtimeAppliedField = "AppliedValue";
        runtimeAppliedValue = string(evidenceRow.AppliedValue);
    end

    [runtimeMeasuredValue, runtimeMeasuredStatus] = localResolveMeasuredValue( ...
        runFolder, measuredArtifact, measuredField, measuredArtifactCache);
    featureDisabledReason = localFeatureDisabledReason(featureFamily, scenarioStruct);
    notApplicableReason = localCoalesceString(featureDisabledReason, localGetField(contract, "UnavailableReason", ""));
    unsupportedReason = "";
    if contractClassification == "unsupported_backend"
        unsupportedReason = localCoalesceString(localGetField(contract, "UnavailableReason", ""), "unsupported_backend");
    end

    mappingStatus = localResolveMappingStatus(internalCfgPath, internalFound, contractClassification);
    consumerStatus = localResolveConsumerStatus(consumerFunctions, contractClassification);
    configResolvedStatus = localResolveConfigStatus(submittedFound, baseFound, resolvedFound, contract);
    runtimeAppliedStatus = localResolveApplicationStatus(evidenceRow, consumerStatus, featureDisabledReason, contractClassification);
    runtimeMeasuredStatus = localFinalizeMeasurementStatus(runtimeMeasuredStatus, featureDisabledReason, runtimeAppliedStatus, measuredArtifact, measuredField);
    runtimeObservedValue = localSelectRuntimeObservedValue( ...
        runtimeAppliedValue, runtimeAppliedStatus, runtimeMeasuredValue, runtimeMeasuredStatus);
    dbSnapshotStatus = localTernary(dbFound, "db_snapshot_present", "db_snapshot_missing");
    browserDisplayStatus = localResolveBrowserDisplayStatus(browserVisible, runtimeAppliedStatus, runtimeMeasuredStatus, configResolvedStatus);
    finalBindingStatus = localResolveFinalBindingStatus(runtimeMeasuredStatus, runtimeAppliedStatus, mappingStatus, browserVisible, contractClassification, featureDisabledReason, resolvedFound);

    row = localEmptyBindingRow();
    row.ParameterId = char(parameterId);
    row.FeatureFamily = char(featureFamily);
    row.UILayer = char(uiLayer);
    row.UISection = char(uiSection);
    row.BrowserPath = char(browserPath);
    row.ScenarioPath = char(scenarioPath);
    row.InternalCfgPath = char(string(internalCfgPath));
    row.BrowserVisible = logical(browserVisible);
    row.BrowserEditable = logical(browserEditable);
    row.SubmittedValue = char(localValueToString(submittedValue));
    row.SubmittedValueSource = char(localTernary(submittedFound, "submitted_in_browser_overlay", "not_submitted"));
    row.BaseYAMLValue = char(localValueToString(baseValue));
    row.CatalogDefaultValue = "";
    if configResolvedStatus == "catalog_default_used" && ~resolvedFound
        row.CatalogDefaultValue = char(localValueToString(localGetField(contract, "DefaultValue", "")));
    end
    row.ResolvedScenarioValue = char(localValueToString(resolvedScenarioValue));
    row.InternalCfgValue = char(localValueToString(internalCfgValue));
    row.MappingStatus = char(mappingStatus);
    row.MATLABConsumerFunction = char(strjoin(string(consumerFunctions(:)).', "; "));
    row.ConsumerReachabilityStatus = char(consumerStatus);
    row.RuntimeObjectPath = char(string(runtimeObjectPath));
    row.RuntimeAppliedEvidenceArtifact = char(string(runtimeAppliedArtifact));
    row.RuntimeAppliedEvidenceField = char(string(runtimeAppliedField));
    row.RuntimeAppliedEvidenceValue = char(localValueToString(runtimeAppliedValue));
    row.RuntimeMeasuredEvidenceArtifact = char(string(measuredArtifact));
    row.RuntimeMeasuredEvidenceField = char(string(measuredField));
    row.RuntimeMeasuredEvidenceValue = char(localValueToString(runtimeMeasuredValue));
    row.RuntimeObservedValue = char(localValueToString(runtimeObservedValue));
    row.ConfigResolvedStatus = char(configResolvedStatus);
    row.RuntimeAppliedStatus = char(runtimeAppliedStatus);
    row.RuntimeMeasuredStatus = char(runtimeMeasuredStatus);
    row.DBSnapshotStatus = char(dbSnapshotStatus);
    row.BrowserDisplayStatus = char(browserDisplayStatus);
    row.FinalBindingStatus = char(finalBindingStatus);
    row.NotApplicableReason = char(notApplicableReason);
    row.UnsupportedReason = char(unsupportedReason);
    row.StrictTruthFailure = false;
    row.Classification = char(contractClassification);
    row.SupportStatus = char(supportStatus);
    row.SharedDependency = logical(sharedDependency);
    row.AppliesWhen = char(localValueToString(appliesWhen));
    row.DisplayedValue = char(localSelectDisplayedValue(submittedValue, resolvedScenarioValue));
    row.DisplayReason = char(localResolveDisplayReason(configResolvedStatus, runtimeAppliedStatus, runtimeMeasuredStatus));
    rows(i) = row;
end

T = struct2table(rows, "AsArray", true);
end

function s = localScenarioStruct(scenarioConfig)
if isa(scenarioConfig, "sixgr.lls6g.config.ScenarioConfig")
    s = scenarioConfig.toStruct();
else
    s = scenarioConfig;
end
if ~isstruct(s)
    s = struct();
end
end

function row = localEmptyBindingRow()
row = struct( ...
    "ParameterId", "", ...
    "FeatureFamily", "", ...
    "UILayer", "", ...
    "UISection", "", ...
    "BrowserPath", "", ...
    "ScenarioPath", "", ...
    "InternalCfgPath", "", ...
    "BrowserVisible", false, ...
    "BrowserEditable", false, ...
    "SubmittedValue", "", ...
    "SubmittedValueSource", "", ...
    "BaseYAMLValue", "", ...
    "CatalogDefaultValue", "", ...
    "ResolvedScenarioValue", "", ...
    "InternalCfgValue", "", ...
    "MappingStatus", "", ...
    "MATLABConsumerFunction", "", ...
    "ConsumerReachabilityStatus", "", ...
    "RuntimeObjectPath", "", ...
    "RuntimeAppliedEvidenceArtifact", "", ...
    "RuntimeAppliedEvidenceField", "", ...
    "RuntimeAppliedEvidenceValue", "", ...
    "RuntimeMeasuredEvidenceArtifact", "", ...
    "RuntimeMeasuredEvidenceField", "", ...
    "RuntimeMeasuredEvidenceValue", "", ...
    "RuntimeObservedValue", "", ...
    "ConfigResolvedStatus", "", ...
    "RuntimeAppliedStatus", "", ...
    "RuntimeMeasuredStatus", "", ...
    "DBSnapshotStatus", "", ...
    "BrowserDisplayStatus", "", ...
    "FinalBindingStatus", "", ...
    "NotApplicableReason", "", ...
    "UnsupportedReason", "", ...
    "StrictTruthFailure", false, ...
    "Classification", "", ...
    "SupportStatus", "", ...
    "SharedDependency", false, ...
    "AppliesWhen", "", ...
    "DisplayedValue", "", ...
    "DisplayReason", "");
end

function leaves = localFlattenLeafMap(s)
leaves = repmat(struct("Path", "", "Value", []), 0, 1);
if ~isstruct(s) || isempty(fieldnames(s))
    return;
end
leaves = localFlattenInto(leaves, s, "");
end

function leaves = localFlattenInto(leaves, value, prefix)
if isstruct(value) && isscalar(value)
    names = fieldnames(value);
    for i = 1:numel(names)
        name = names{i};
        path = localJoinPath(prefix, name);
        leaves = localFlattenInto(leaves, value.(name), path);
    end
    return;
end

leaf = struct("Path", char(string(prefix)), "Value", []);
leaf.Value = value;
leaves(end+1, 1) = leaf; %#ok<AGROW>
end

function out = localJoinPath(prefix, name)
if strlength(string(prefix)) == 0
    out = char(string(name));
else
    out = char(string(prefix) + "." + string(name));
end
end

function rows = localLoadContractRows()
catalogPath = fullfile(localRepoRoot(), "simulator", "configs", "schema", "scenario_parameter_matrix_catalog.yaml");
raw = sixgr.lls6g.config.readConfigFile(catalogPath);
params = sixgr.util.structGet(raw, "parameters", struct([]));
if isempty(params)
    rows = repmat(localEmptyContractRow(), 0, 1);
    return;
end
rows = repmat(localEmptyContractRow(), numel(params), 1);
for i = 1:numel(params)
    if iscell(params)
        p = params{i};
    else
        p = params(i);
    end
    rows(i).ParameterId = char(string(sixgr.util.structGet(p, "parameter_id", "")));
    rows(i).BrowserPath = string(sixgr.util.structGet(p, "browser_path", ""));
    rows(i).ScenarioPath = string(sixgr.util.structGet(p, "scenario_path", ""));
    rows(i).InternalCfgPath = string(sixgr.util.structGet(p, "internal_cfg_path", ""));
    rows(i).BrowserVisible = localToLogicalMaybe(sixgr.util.structGet(p, "browser_visible", []));
    rows(i).BrowserEditable = localToLogicalMaybe(sixgr.util.structGet(p, "browser_editable", []));
    rows(i).UILayer = string(sixgr.util.structGet(p, "ui_layer", ""));
    rows(i).UISection = string(sixgr.util.structGet(p, "ui_section", ""));
    rows(i).FeatureFamily = string(sixgr.util.structGet(p, "feature_family", ""));
    rows(i).Aliases = string(sixgr.util.structGet(p, "aliases", strings(0, 1)));
    rows(i).MATLABConsumerFunctions = string(sixgr.util.structGet(p, "matlab_consumer_functions", strings(0, 1)));
    rows(i).RuntimeObjectPath = string(sixgr.util.structGet(p, "runtime_object_path", ""));
    rows(i).Classification = string(sixgr.util.structGet(p, "classification", ""));
    rows(i).SupportStatus = string(sixgr.util.structGet(p, "support_status", ""));
    rows(i).UnavailableReason = string(sixgr.util.structGet(p, "unavailable_reason", ""));
    rows(i).DefaultSource = string(sixgr.util.structGet(p, "default_source", ""));
    rows(i).MeasuredArtifact = string(sixgr.util.structGet(p, "measured_artifact", ""));
    rows(i).MeasuredField = string(sixgr.util.structGet(p, "measured_field", ""));
    rows(i).AppliesWhen = string(sixgr.util.structGet(sixgr.util.structGet(p, "applies_when", struct()), "features", strings(0, 1)));
    rows(i).SharedDependency = localToLogicalMaybe(sixgr.util.structGet(p, "shared_dependency", []));
end
end

function row = localEmptyContractRow()
row = struct( ...
    "ParameterId", "", ...
    "BrowserPath", "", ...
    "ScenarioPath", "", ...
    "InternalCfgPath", "", ...
    "BrowserVisible", [], ...
    "BrowserEditable", [], ...
    "UILayer", "", ...
    "UISection", "", ...
    "FeatureFamily", "", ...
    "Aliases", strings(0, 1), ...
    "MATLABConsumerFunctions", strings(0, 1), ...
    "RuntimeObjectPath", "", ...
    "Classification", "", ...
    "SupportStatus", "", ...
    "UnavailableReason", "", ...
    "DefaultSource", "", ...
    "MeasuredArtifact", "", ...
    "MeasuredField", "", ...
    "AppliesWhen", strings(0, 1), ...
    "SharedDependency", []);
end

function rows = localLoadTaxonomyRows()
taxonomyPath = fullfile(localRepoRoot(), "simulator", "configs", "schema", "ui_parameter_taxonomy.yaml");
raw = sixgr.lls6g.config.readConfigFile(taxonomyPath);
rows = repmat(localEmptyTaxonomyRow(), 0, 1);
groups = sixgr.util.structGet(raw, "ui_groups", struct());
if ~isstruct(groups)
    return;
end
groupNames = fieldnames(groups);
for iGroup = 1:numel(groupNames)
    uiLayer = string(groupNames{iGroup});
    groupStruct = groups.(groupNames{iGroup});
    sections = sixgr.util.structGet(groupStruct, "sections", struct());
    if ~isstruct(sections)
        continue;
    end
    sectionNames = fieldnames(sections);
    for iSection = 1:numel(sectionNames)
        uiSection = string(sectionNames{iSection});
        sectionStruct = sections.(sectionNames{iSection});
        row = localEmptyTaxonomyRow();
        row.UILayer = uiLayer;
        row.UISection = uiSection;
        row.FeatureFamily = string(sixgr.util.structGet(sectionStruct, "feature_family", uiSection));
        row.IncludePrefixes = string(sixgr.util.structGet(sectionStruct, "include_prefixes", strings(0, 1)));
        row.HidePrefixes = string(sixgr.util.structGet(sectionStruct, "hide_prefixes", strings(0, 1)));
        row.SharedDependency = localInferLogical(localToLogicalMaybe(sixgr.util.structGet(sectionStruct, "shared_dependency", false)), false);
        row.Dependencies = string(sixgr.util.structGet(sixgr.util.structGet(sectionStruct, "dependencies", struct()), "shared_paths", strings(0, 1)));
        row.AppliesWhen = string(sixgr.util.structGet(sixgr.util.structGet(sectionStruct, "show_when", struct()), "any", strings(0, 1)));
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end
end

function hints = localNormalizeRegistryHints(rawHints)
hints = repmat(localEmptyRegistryHintRow(), 0, 1);
if isempty(rawHints)
    return;
end
if istable(rawHints)
    rawHints = table2struct(rawHints);
end
if ~isstruct(rawHints)
    return;
end
if isempty(rawHints)
    return;
end
if ~isvector(rawHints)
    rawHints = rawHints(:);
end
hints = repmat(localEmptyRegistryHintRow(), numel(rawHints), 1);
for i = 1:numel(rawHints)
    hint = rawHints(i);
    hints(i).ParameterId = string(localGetField(hint, "ParameterId", ""));
    hints(i).Aliases = string(localGetField(hint, "Aliases", strings(0, 1)));
    hints(i).InternalCfgPath = string(localGetField(hint, "InternalCfgPath", ""));
    hints(i).MATLABConsumerFunctions = string(localGetField(hint, "MATLABConsumerFunctions", strings(0, 1)));
    hints(i).MeasuredArtifact = string(localGetField(hint, "MeasuredArtifact", ""));
    hints(i).MeasuredField = string(localGetField(hint, "MeasuredField", ""));
    hints(i).BrowserVisible = localToLogicalMaybe(localGetField(hint, "BrowserVisible", []));
    hints(i).BrowserEditable = localToLogicalMaybe(localGetField(hint, "BrowserEditable", []));
    hints(i).FeatureFamily = string(localGetField(hint, "FeatureFamily", ""));
    hints(i).UILayer = string(localGetField(hint, "UILayer", ""));
    hints(i).UISection = string(localGetField(hint, "UISection", ""));
end
end

function index = localBuildContractIndex(rows)
index = containers.Map("KeyType", "char", "ValueType", "any");
for i = 1:numel(rows)
    key = char(string(localGetField(rows(i), "ParameterId", "")));
    if isempty(key) || isKey(index, key)
        continue;
    end
    index(key) = rows(i);
end
end

function row = localFindContractRowIndexed(index, parameterId)
row = localEmptyContractRow();
key = char(string(parameterId));
if ~isempty(key) && isKey(index, key)
    row = index(key);
end
end

function index = localBuildRegistryHintIndex(hints)
index = containers.Map("KeyType", "char", "ValueType", "any");
% Direct ParameterId matches have precedence over every alias, matching the
% former two-pass search exactly.
for i = 1:numel(hints)
    key = char(string(localGetField(hints(i), "ParameterId", "")));
    if isempty(key) || isKey(index, key)
        continue;
    end
    index(key) = hints(i);
end
for i = 1:numel(hints)
    aliases = string(localGetField(hints(i), "Aliases", strings(0, 1)));
    for j = 1:numel(aliases)
        key = char(aliases(j));
        if isempty(key) || isKey(index, key)
            continue;
        end
        index(key) = hints(i);
    end
end
end

function hint = localFindRegistryHintIndexed(index, parameterId)
hint = localEmptyRegistryHintRow();
key = char(string(parameterId));
if ~isempty(key) && isKey(index, key)
    hint = index(key);
end
end

function index = localBuildLeafIndex(leaves)
index = containers.Map("KeyType", "char", "ValueType", "any");
for i = 1:numel(leaves)
    key = char(string(leaves(i).Path));
    if isempty(key) || isKey(index, key)
        continue;
    end
    index(key) = leaves(i).Value;
end
end

function [value, found] = localTryGetLeafIndexed(index, path)
value = [];
found = false;
key = char(string(path));
if isempty(key) || ~isKey(index, key)
    return;
end
value = index(key);
found = true;
end

function index = localBuildEvidenceIndex(T)
index = containers.Map("KeyType", "char", "ValueType", "any");
if ~(istable(T) && ~isempty(T) && ...
        any(strcmp(string(T.Properties.VariableNames), "ParameterId")))
    return;
end
% The original resolver selected the last matching evidence row.
for i = 1:height(T)
    key = char(string(T.ParameterId(i)));
    if isempty(key)
        continue;
    end
    index(key) = T(i, :);
end
end

function row = localFindEvidenceRowIndexed(index, parameterId)
row = table();
key = char(string(parameterId));
if ~isempty(key) && isKey(index, key)
    row = index(key);
end
end

function hint = localFindRegistryHint(hints, parameterId)
hint = localEmptyRegistryHintRow();
if isempty(hints)
    return;
end
for i = 1:numel(hints)
    if string(localGetField(hints(i), "ParameterId", "")) == string(parameterId)
        hint = hints(i);
        return;
    end
end
for i = 1:numel(hints)
    aliases = string(localGetField(hints(i), "Aliases", strings(0, 1)));
    if any(aliases == string(parameterId))
        hint = hints(i);
        return;
    end
end
end

function row = localEmptyRegistryHintRow()
row = struct( ...
    "ParameterId", "", ...
    "Aliases", strings(0, 1), ...
    "InternalCfgPath", "", ...
    "MATLABConsumerFunctions", strings(0, 1), ...
    "MeasuredArtifact", "", ...
    "MeasuredField", "", ...
    "BrowserVisible", [], ...
    "BrowserEditable", [], ...
    "FeatureFamily", "", ...
    "UILayer", "", ...
    "UISection", "");
end

function row = localEmptyTaxonomyRow()
row = struct( ...
    "UILayer", "", ...
    "UISection", "", ...
    "FeatureFamily", "", ...
    "IncludePrefixes", strings(0, 1), ...
    "HidePrefixes", strings(0, 1), ...
    "SharedDependency", false, ...
    "Dependencies", strings(0, 1), ...
    "AppliesWhen", strings(0, 1));
end

function row = localFindContractRow(rows, parameterId)
row = localEmptyContractRow();
if isempty(rows)
    return;
end
mask = strcmp(string({rows.ParameterId}), string(parameterId));
if any(mask)
    row = rows(find(mask, 1, "first"));
end
end

function row = localFindTaxonomyRow(rows, parameterId)
row = localEmptyTaxonomyRow();
bestLen = -1;
for i = 1:numel(rows)
    prefixes = string(rows(i).IncludePrefixes);
    hides = string(rows(i).HidePrefixes);
    if any(startsWith(string(parameterId), hides))
        continue;
    end
    for j = 1:numel(prefixes)
        prefix = prefixes(j);
        if startsWith(string(parameterId), prefix) && strlength(prefix) > bestLen
            row = rows(i);
            bestLen = strlength(prefix);
        end
    end
end
end

function [value, found] = localTryGet(s, path)
marker = struct("sixgrMissingMarker__", true);
value = marker;
found = false;
if ~isstruct(s) || strlength(string(path)) == 0
    value = [];
    return;
end
value = sixgr.util.structGet(s, char(string(path)), marker);
found = ~(isstruct(value) && isscalar(value) && isfield(value, "sixgrMissingMarker__"));
if ~found
    value = [];
end
end

function [value, found] = localTryGetLeaf(leaves, path)
value = [];
found = false;
if isempty(leaves) || strlength(string(path)) == 0
    return;
end
paths = string({leaves.Path});
idx = find(strcmp(paths, string(path)), 1, "first");
if isempty(idx)
    return;
end
value = leaves(idx).Value;
found = true;
end

function [value, found] = localGetInternalValue(cfg, internalCfgPath, aliases)
[value, found] = localTryGet(cfg, internalCfgPath);
if found
    return;
end
aliases = string(aliases(:));
for i = 1:numel(aliases)
    alias = aliases(i);
    if startsWith(alias, "prach_lls.") || startsWith(alias, "phy.") || startsWith(alias, "channel.") || startsWith(alias, "frequency.") || startsWith(alias, "frame.")
        [value, found] = localTryGet(cfg, alias);
        if found
            return;
        end
    end
end
end

function row = localFindEvidenceRow(T, parameterId)
row = table();
if ~(istable(T) && ~isempty(T) && any(strcmp(string(T.Properties.VariableNames), "ParameterId")))
    return;
end
mask = strcmp(string(T.ParameterId), string(parameterId));
if any(mask)
    row = T(find(mask, 1, "last"), :);
end
end

function status = localResolveMappingStatus(internalCfgPath, internalFound, classification)
if classification == "unsupported_backend"
    status = "not_mapped_to_internal_cfg";
    return;
end
if strlength(string(internalCfgPath)) == 0
    status = "not_mapped_to_internal_cfg";
elseif internalFound
    status = "mapped_to_internal_cfg";
else
    status = "not_mapped_to_internal_cfg";
end
end

function status = localResolveConsumerStatus(consumerFunctions, classification)
if classification == "unsupported_backend"
    status = "blocked_by_backend";
elseif isempty(consumerFunctions)
    status = "runtime_consumer_missing";
else
    status = "runtime_consumer_registered";
end
end

function status = localResolveConfigStatus(submittedFound, baseFound, resolvedFound, contract)
if submittedFound
    status = "submitted_in_browser_overlay";
elseif baseFound
    status = "inherited_from_base_yaml";
elseif resolvedFound
    status = "resolved_in_matlab";
elseif strlength(localGetField(contract, "DefaultSource", "")) > 0
    status = "catalog_default_used";
else
    status = "not_submitted";
end
end

function status = localResolveApplicationStatus(evidenceRow, consumerStatus, featureDisabledReason, classification)
if ~isempty(evidenceRow)
    status = "applied_to_runtime_object";
elseif strlength(string(featureDisabledReason)) > 0
    status = "not_applicable_for_selected_feature";
elseif classification == "unsupported_backend"
    status = "unsupported_backend";
elseif consumerStatus == "runtime_consumer_registered"
    status = "consumer_not_instrumented";
else
    status = "consumer_missing";
end
end

function status = localFinalizeMeasurementStatus(status, featureDisabledReason, runtimeAppliedStatus, measuredArtifact, measuredField)
if strlength(string(featureDisabledReason)) > 0
    status = "evidence_unavailable_because_feature_disabled";
elseif runtimeAppliedStatus == "unsupported_backend"
    status = "unsupported_backend";
elseif strlength(string(status)) == 0
    if strlength(string(measuredArtifact)) == 0 || strlength(string(measuredField)) == 0
        status = "evidence_not_applicable";
    else
        status = "runtime_evidence_not_published";
    end
end
end

function status = localResolveBrowserDisplayStatus(browserVisible, runtimeAppliedStatus, runtimeMeasuredStatus, configResolvedStatus)
if ~browserVisible
    status = "hidden_from_browser_surface";
elseif runtimeMeasuredStatus == "measured_runtime_evidence_published"
    status = "display_runtime_measured";
elseif runtimeAppliedStatus == "applied_to_runtime_object"
    status = "display_runtime_applied";
else
    status = "display_config_resolved";
end
if configResolvedStatus == "not_submitted" && browserVisible
    status = "display_config_unsubmitted";
end
end

function status = localResolveFinalBindingStatus(runtimeMeasuredStatus, runtimeAppliedStatus, mappingStatus, browserVisible, classification, featureDisabledReason, resolvedFound)
if runtimeMeasuredStatus == "measured_runtime_evidence_published"
    status = "browser_to_runtime_measured";
elseif runtimeAppliedStatus == "applied_to_runtime_object"
    status = "browser_to_runtime_applied";
elseif strlength(string(featureDisabledReason)) > 0
    status = "not_applicable_for_selected_feature";
elseif classification == "unsupported_backend"
    status = "unsupported_backend";
elseif browserVisible && mappingStatus == "mapped_to_internal_cfg"
    status = "browser_to_matlab_resolved_only";
elseif browserVisible && ~resolvedFound
    status = "schema_declared_only";
elseif mappingStatus == "not_mapped_to_internal_cfg"
    status = "browser_to_cfg_unmapped";
else
    status = "blocked_missing_runtime_evidence";
end
end

function value = localSelectRuntimeObservedValue(runtimeAppliedValue, runtimeAppliedStatus, runtimeMeasuredValue, runtimeMeasuredStatus)
% Prefer direct runtime-object application evidence for config traceability.
% Measured artifacts are used only when no applied config evidence exists.
if string(runtimeAppliedStatus) == "applied_to_runtime_object" && localHasPresentValue(runtimeAppliedValue)
    value = runtimeAppliedValue;
elseif string(runtimeMeasuredStatus) == "measured_runtime_evidence_published" && localHasPresentValue(runtimeMeasuredValue)
    value = runtimeMeasuredValue;
else
    value = "";
end
end

function [value, status] = localResolveMeasuredValue(runFolder, artifactPath, fieldName, artifactCache)
value = "";
status = "";
if strlength(string(artifactPath)) == 0 || strlength(string(fieldName)) == 0
    status = "evidence_not_applicable";
    return;
end
if strlength(string(runFolder)) == 0
    status = "evidence_artifact_missing";
    return;
end
fullPath = fullfile(runFolder, char(string(artifactPath)));
if exist(fullPath, "file") ~= 2
    status = "evidence_artifact_missing";
    return;
end
cacheKey = char(string(fullPath));
if isKey(artifactCache, cacheKey)
    cached = artifactCache(cacheKey);
else
    cached = struct("ReadOk", false, "Table", table());
    try
        cached.Table = readtable(fullPath, "VariableNamingRule", "preserve");
        cached.ReadOk = true;
    catch
        cached.ReadOk = false;
    end
    artifactCache(cacheKey) = cached;
end
if ~cached.ReadOk
    status = "evidence_artifact_missing";
    return;
end
T = cached.Table;
if ~any(strcmp(string(T.Properties.VariableNames), string(fieldName)))
    status = "evidence_field_missing";
    return;
end
col = T.(char(string(fieldName)));
if isempty(col)
    status = "runtime_evidence_not_published";
    return;
end
[value, found] = localFirstPresentValue(col);
if ~found
    status = "runtime_evidence_not_published";
    return;
end
status = "measured_runtime_evidence_published";
end

function [artifact, field] = localDefaultMeasuredMapping(parameterId)
artifact = "";
field = "";
pid = lower(strtrim(string(parameterId)));
switch pid
    case "random_access.detection_threshold"
        artifact = "air_interface/csv/prach_trials.csv";
        field = "threshold";
    case "random_access.enabled"
        artifact = "air_interface/csv/prach_trials.csv";
        field = "Status";
end
if strlength(artifact) > 0
    return;
end

if contains(pid, "pucch")
    artifact = "air_interface/csv/pucch_trials.csv";
    if contains(pid, "sinr")
        field = "PUCCHControlSINR_dB";
    elseif contains(pid, "format")
        field = "PUCCHFormat";
    elseif contains(pid, "prb")
        field = "PUCCHPRBCount";
    elseif contains(pid, "symbol")
        field = "PUCCHNumSymbols";
    elseif contains(pid, "crc")
        field = "CRCPass";
    elseif contains(pid, "detection") || contains(pid, "threshold")
        field = "DetectionMetric";
    else
        field = "StrictOk";
    end
elseif contains(pid, "srs")
    artifact = "air_interface/csv/srs_trials.csv";
    if contains(pid, "nmse")
        field = "NMSE_dB";
    elseif contains(pid, "sinr")
        field = "ReceiverHestSINR_dB";
    elseif contains(pid, "doppler")
        field = "EstimatedDopplerHz";
    else
        field = "DetectionMetric";
    end
elseif contains(pid, "trs") || contains(pid, "cfo") || contains(pid, "timing")
    artifact = "air_interface/csv/trs_trials.csv";
    if contains(pid, "doppler")
        field = "EstimatedDopplerHz";
    elseif contains(pid, "cfo")
        field = "EstimatedCFO_Hz";
    elseif contains(pid, "timing")
        field = "TimingOffsetEstimate_samples";
    else
        field = "DetectionMetric";
    end
elseif contains(pid, "ul") || contains(pid, "pusch") || contains(pid, "uplink")
    artifact = "air_interface/csv/ul_pusch_trials.csv";
    field = localDefaultLinkMeasuredField(pid);
elseif contains(pid, "dl") || contains(pid, "pdsch") || contains(pid, "downlink")
    artifact = "air_interface/csv/dl_pdsch_trials.csv";
    field = localDefaultLinkMeasuredField(pid);
elseif contains(pid, "goodput") || contains(pid, "throughput")
    artifact = "air_interface/csv/lls_kpi_summary.csv";
    if contains(pid, "ul")
        field = "Goodput_UL_max_Mbps";
    else
        field = "Goodput_DL_max_Mbps";
    end
elseif contains(pid, "bler")
    artifact = "air_interface/csv/lls_kpi_summary.csv";
    if contains(pid, "ul")
        field = "BLER_UL_min";
    else
        field = "BLER_DL_min";
    end
elseif contains(pid, "snr") || contains(pid, "noise")
    artifact = "air_interface/csv/dl_pdsch_trials.csv";
    if contains(pid, "noise")
        field = "NoiseVariance";
    else
        field = "ConfiguredSNR_dB";
    end
elseif contains(pid, "mcs") || contains(pid, "cqi") || contains(pid, "rank") || contains(pid, "layer")
    artifact = "air_interface/csv/dl_pdsch_trials.csv";
    field = localDefaultLinkMeasuredField(pid);
elseif contains(pid, "doppler") || contains(pid, "speed") || contains(pid, "scs") || ...
        contains(pid, "slot") || contains(pid, "grid") || contains(pid, "bandwidth") || ...
        contains(pid, "duplex") || contains(pid, "traffic") || contains(pid, "scheduler")
    artifact = "reports/csv/runtime_operating_mode.csv";
    field = localDefaultRuntimeOperatingModeField(pid);
elseif contains(pid, "pathloss") || contains(pid, "shadow") || contains(pid, "rx_power")
    artifact = "air_interface/csv/dl_pdsch_trials.csv";
    if contains(pid, "pathloss")
        field = "Pathloss_dB";
    elseif contains(pid, "shadow")
        field = "ShadowFading_dB";
    else
        field = "ServingRxPower_dBm";
    end
end
end

function field = localDefaultLinkMeasuredField(pid)
pid = lower(strtrim(string(pid)));
if contains(pid, "posteq") || contains(pid, "sinr")
    field = "PostEqSINR_dB";
elseif contains(pid, "receiver")
    field = "ReceiverHestSINR_dB";
elseif contains(pid, "mcs")
    field = "MCS";
elseif contains(pid, "cqi")
    field = "WidebandCQI";
elseif contains(pid, "rank") || contains(pid, "layer")
    field = "Layers";
elseif contains(pid, "prb") || contains(pid, "rb")
    field = "PRBs";
elseif contains(pid, "noise")
    field = "NoiseVariance";
elseif contains(pid, "doppler")
    field = "DopplerHz";
elseif contains(pid, "evm")
    field = "EVM_rms";
elseif contains(pid, "crc")
    field = "CRCPass";
else
    field = "ConfiguredSNR_dB";
end
end

function field = localDefaultRuntimeOperatingModeField(pid)
pid = lower(strtrim(string(pid)));
if contains(pid, "doppler")
    field = "ResolvedDopplerHz";
elseif contains(pid, "speed")
    field = "MobilitySpeed_kmh";
elseif contains(pid, "scs")
    field = "SCS_kHz";
elseif contains(pid, "slot")
    field = "SlotDuration_ms";
elseif contains(pid, "grid")
    field = "ConfiguredGridNumRBs";
elseif contains(pid, "duplex")
    field = "DuplexMode";
elseif contains(pid, "traffic")
    field = "ConfiguredTrafficModel";
elseif contains(pid, "scheduler")
    field = "ConfiguredSchedulerType";
elseif contains(pid, "bandwidth")
    field = "ConfiguredBandwidth_Hz";
elseif contains(pid, "cp_type") || contains(pid, "cyclic_prefix")
    field = "CyclicPrefix";
else
    field = "ConfiguredGridNumRBs";
end
end

function reason = localFeatureDisabledReason(featureFamily, scenarioStruct)
reason = "";
switch string(featureFamily)
    case "Random_Access_PRACH"
        enabled = logical(sixgr.util.structGet(scenarioStruct, "random_access.enabled", false));
        if ~enabled
            reason = "prach_disabled_by_config";
        end
end
end

function classification = localInferClassification(parameterId, submittedFound, resolvedFound, internalFound)
if contains(parameterId, "config_inheritance.") || startsWith(parameterId, "lls6g.")
    classification = "hidden_internal";
elseif submittedFound || resolvedFound
    if internalFound
        classification = "browser_editable";
    else
        classification = "browser_editable";
    end
else
    classification = "schema_only";
end
end

function tf = localInferBrowserVisible(parameterId)
path = string(parameterId);
tf = ~(startsWith(path, "config_inheritance.") || startsWith(path, "lls6g."));
end

function status = localInferSupportStatus(consumerFunctions, classification)
if classification == "unsupported_backend"
    status = "unsupported_backend";
elseif isempty(consumerFunctions)
    status = "runtime_consumer_missing";
else
    status = "runtime_consumer_registered";
end
end

function out = localConcatStringVectors(varargin)
out = strings(0, 1);
for i = 1:nargin
    value = string(varargin{i});
    if isempty(value)
        continue;
    end
    value = value(:);
    value = value(strlength(strtrim(value)) > 0);
    if isempty(value)
        continue;
    end
    out = [out; value]; %#ok<AGROW>
end
if ~isempty(out)
    out = unique(out, "stable");
end
end

function value = localGetField(s, name, defaultValue)
if nargin < 3
    defaultValue = [];
end
if isstruct(s) && isfield(s, char(name))
    value = s.(char(name));
else
    value = defaultValue;
end
end

function tf = localToLogicalMaybe(value)
if isempty(value)
    tf = [];
elseif islogical(value)
    tf = value;
else
    tf = logical(value);
end
end

function out = localCoalesceString(varargin)
out = "";
for i = 1:nargin
    value = string(varargin{i});
    if any(strlength(strtrim(value)) > 0)
        out = value(1);
        return;
    end
end
end

function tf = localInferLogical(value, defaultValue)
if isempty(value)
    tf = logical(defaultValue);
else
    tf = logical(value);
end
end

function out = localTernary(cond, left, right)
if cond
    out = left;
else
    out = right;
end
end

function text = localValueToString(value)
if isempty(value)
    text = "";
    return;
end
try
    if all(ismissing(value), "all")
        text = "";
        return;
    end
catch
end
if isstring(value)
    value = value(:);
    value(ismissing(value)) = "";
    if isscalar(value)
        text = value;
    else
        try
            text = string(jsonencode(cellstr(value)));
        catch
            text = "[" + strjoin(value(:).', ",") + "]";
        end
    end
    return;
end
if ischar(value)
    text = string(value);
    return;
end
if isnumeric(value) || islogical(value)
    if isscalar(value)
        text = string(value);
    else
        try
            text = string(jsonencode(value));
        catch
            text = "[" + strjoin(string(value(:).'), ",") + "]";
        end
    end
    return;
end
if iscell(value)
    try
        text = string(jsonencode(value));
    catch
        text = "[" + strjoin(string(value(:).'), ",") + "]";
    end
    return;
end
try
    text = string(jsonencode(value));
catch
    text = string(value);
end
end

function [text, found] = localFirstPresentValue(col)
text = "";
found = false;
numelCol = numel(col);
for i = 1:numelCol
    candidate = col(i);
    if iscell(candidate)
        if isempty(candidate)
            continue;
        end
        candidate = candidate{1};
    end
    if ismissing(candidate)
        continue;
    end
    if iscategorical(candidate) && isundefined(candidate)
        continue;
    end
    if isnumeric(candidate)
        if isempty(candidate) || (isscalar(candidate) && isnan(candidate))
            continue;
        end
    end
    candidateText = localValueToString(candidate);
    normalized = strtrim(string(candidateText));
    if strlength(normalized) == 0 || any(strcmpi(normalized, ["NaN","<missing>","missing"]))
        continue;
    end
    text = normalized(1);
    found = true;
    return;
end
end

function [featureFamily,uiSection] = localInferTaxonomy(parameterId)
path = lower(string(parameterId));
path = erase(path,"canonical_control.");
root = extractBefore(path+".",".");
switch root
    case {"identity","meta"}
        featureFamily="Scenario_Identity";uiSection="Scenario";
    case {"launch","run","run_control","simulation","execution"}
        featureFamily="Execution_Control";uiSection="Run";
    case {"frequency","radio","frame","tdd_timing","bwp","carrier"}
        featureFamily="Frame_Grid_Radio";uiSection="Radio";
    case {"waveform","waveform_phase13","phase13"}
        featureFamily="Waveform";uiSection="Waveform";
    case {"pdsch","dlsch"}
        featureFamily="PDSCH_DLSCH";uiSection="Downlink PHY";
    case {"pusch","ulsch"}
        featureFamily="PUSCH_ULSCH";uiSection="Uplink PHY";
    case {"pdcch","dci"}
        featureFamily="PDCCH_DCI";uiSection="Downlink Control";
    case {"pucch","uci"}
        featureFamily="PUCCH_UCI";uiSection="Uplink Control";
    case {"reference_signals","csi","srs","trs","measurements", ...
            "link_adaptation","csi_acquisition_and_reporting"}
        featureFamily="Reference_Signals_Link_Adaptation";
        uiSection="Measurements";
    case {"initial_access","sib1_and_initial_access", ...
            "random_access","random_access_evidence"}
        featureFamily="Random_Access_PRACH";uiSection="Initial Access";
    case {"mimo","beamforming","precoding","topology"}
        featureFamily="MIMO_Beamforming";uiSection="MIMO & Beams";
    case {"channel","channels","mobility","geometry","interference"}
        featureFamily="Channel_Geometry";uiSection="Channel";
    case {"rf","power_control","impairments"}
        featureFamily="RF_Power_Control";uiSection="RF";
    case {"mac","harq","scheduler","scheduling"}
        featureFamily="MAC_HARQ_Scheduling";uiSection="MAC";
    case {"protocol","rlc","pdcp","sdap","rrc","traffic"}
        featureFamily="Protocol_Stack";uiSection="Protocol";
    case {"qualification","validation","integration"}
        featureFamily="Validation_Integration";uiSection="Validation";
    case {"output","analytics","reporting","export"}
        featureFamily="Results_Exports";uiSection="Results";
    otherwise
        featureFamily="Advanced_Configuration";
        uiSection="Advanced";
end
end

function tf = localHasPresentValue(value)
text = strtrim(string(localValueToString(value)));
tf = ~(strlength(text) == 0 || any(strcmpi(text, ["NaN","<missing>","missing"])));
end

function value = localSelectDisplayedValue(submittedValue, resolvedScenarioValue)
if ~isempty(submittedValue)
    value = localValueToString(submittedValue);
else
    value = localValueToString(resolvedScenarioValue);
end
end

function reason = localResolveDisplayReason(configResolvedStatus, runtimeAppliedStatus, runtimeMeasuredStatus)
if runtimeMeasuredStatus == "measured_runtime_evidence_published"
    reason = "runtime_measured_value_available";
elseif runtimeAppliedStatus == "applied_to_runtime_object"
    reason = "runtime_applied_value_available";
else
    switch string(configResolvedStatus)
        case "submitted_in_browser_overlay"
            reason = "resolved_in_matlab_from_browser_overlay";
        case "inherited_from_base_yaml"
            reason = "resolved_in_matlab_from_inherited_yaml";
        case "catalog_default_used"
            reason = "resolved_in_matlab_from_catalog_default";
        otherwise
            reason = "resolved_in_matlab_without_runtime_consumer_evidence";
    end
end
end

function root = localRepoRoot()
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(here));
end
