function bindingT = validateMatrixCampaignConstraints(matrixCfg, matrixConfigPath)
%VALIDATEMATRIXCAMPAIGNCONSTRAINTS Enforce campaign-wide resolved PHY scope.
% This validator inspects the fully inherited scenario and every generic-
% sweep child. It deliberately validates physical configuration values, not
% campaign labels.

arguments
    matrixCfg (1,1) struct
    matrixConfigPath (1,1) string
end

requiredFc = double(sixgr.util.structGet(matrixCfg, ...
    "execution.required_center_frequency_hz", NaN));
requiredDuplex = upper(string(sixgr.util.structGet(matrixCfg, ...
    "execution.required_duplex_mode", "")));
singleCarrier = logical(sixgr.util.structGet(matrixCfg, ...
    "execution.require_single_carrier", false));
forbidCA = logical(sixgr.util.structGet(matrixCfg, ...
    "execution.forbid_carrier_aggregation", false));
forbidFrequencySweep = logical(sixgr.util.structGet(matrixCfg, ...
    "execution.forbid_frequency_sweep", false));
forbidNTN = logical(sixgr.util.structGet(matrixCfg, ...
    "execution.forbid_ntn", false));
forbidISAC = logical(sixgr.util.structGet(matrixCfg, ...
    "execution.forbid_isac", false));

rows = repmat(localEmptyBinding(), 0, 1);
scenarioList = string(matrixCfg.scenarios(:));
for scenarioIndex = 1:numel(scenarioList)
    scenarioPath = localResolveScenarioPath(matrixConfigPath, scenarioList(scenarioIndex));
    scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
    parent = scfg.toStruct();
    cases = localResolvedCases(parent, scfg);
    for caseIndex = 1:numel(cases)
        resolved = cases(caseIndex).Config;
        caseID = cases(caseIndex).CaseID;
        rows = [rows; localValidateResolvedCase(resolved, scenarioPath, caseID, ... %#ok<AGROW>
            requiredFc, requiredDuplex, singleCarrier, forbidCA, ...
            forbidFrequencySweep, forbidNTN, forbidISAC)];
    end
end
bindingT = struct2table(rows);
end

function cases = localResolvedCases(parent, scfg)
cases = struct("CaseID", string(scfg.ScenarioID), "Config", parent);
profile = lower(string(sixgr.util.structGet(parent, ...
    "scenario.runner_profile", "")));
if profile ~= "generic_sweep"
    return;
end
overrides = sixgr.util.structGet(parent, "scenario.sweep.overrides", struct([]));
cases = repmat(struct("CaseID", "", "Config", struct()), numel(overrides), 1);
for index = 1:numel(overrides)
    authority = sixgr.util.structGet(overrides(index), "config", struct());
    resolved = sixgr.util.mergeStruct(parent, authority);
    resolved = sixgr.lls6g.config.normalizeScenarioAliases(resolved, ...
        "SourceFiles", scfg.SourceFiles, "ConfigPath", scfg.ConfigPath, ...
        "Authority", authority);
    resolved.scenario.runner_profile = string(sixgr.util.structGet( ...
        parent, "scenario.sweep.base_profile", "waveform_bundle"));
    sixgr.lls6g.config.validateScenarioConfig(resolved, "Kind", "scenario", ...
        "AllowPartial", false, "Context", scfg.ConfigPath + "::campaign_preflight");
    cases(index).CaseID = string(sixgr.util.structGet(overrides(index), ...
        "label", "case_" + index));
    cases(index).Config = resolved;
end
end

function rows = localValidateResolvedCase(cfg, scenarioPath, caseID, requiredFc, ...
        requiredDuplex, singleCarrier, forbidCA, forbidFrequencySweep, forbidNTN, forbidISAC)
rows = repmat(localEmptyBinding(), 0, 1);
fcPaths = localCollectNamedNumericFields(cfg, "", ...
    ["center_frequency_hz", "carrier_frequency_hz"]);
if isfinite(requiredFc) && isempty(fcPaths)
    error("sixgr:lls6g:config:CampaignCarrierBindingMissing", ...
        "Resolved case '%s' has no carrier-frequency binding.", caseID);
end
for index = 1:numel(fcPaths)
    actual = fcPaths(index).Value;
    if isfinite(requiredFc) && actual ~= requiredFc
        error("sixgr:lls6g:config:CampaignCarrierMismatch", ...
            "Resolved case '%s' binds %s=%g Hz; campaign requires %g Hz.", ...
            caseID, fcPaths(index).Path, actual, requiredFc);
    end
    rows(end+1,1) = localBinding(scenarioPath, caseID, ... %#ok<AGROW>
        fcPaths(index).Path, "Hz", actual, requiredFc, "resolved_config_exact_match");
end

duplexPaths = localCollectNamedStringFields(cfg, "", "duplex_mode");
for index = 1:numel(duplexPaths)
    actual = upper(duplexPaths(index).Value);
    if strlength(requiredDuplex) > 0 && actual ~= requiredDuplex
        error("sixgr:lls6g:config:CampaignDuplexMismatch", ...
            "Resolved case '%s' binds %s=%s; campaign requires %s.", ...
            caseID, duplexPaths(index).Path, actual, requiredDuplex);
    end
    rows(end+1,1) = localBinding(scenarioPath, caseID, ... %#ok<AGROW>
        duplexPaths(index).Path, "enum", actual, requiredDuplex, "resolved_config_exact_match");
end

carrierCount = double(sixgr.util.structGet(cfg, "frequency.carrier_count", 1));
componentCarriers = sixgr.util.structGet(cfg, "bwp.component_carriers", struct([]));
if singleCarrier && (carrierCount ~= 1 || numel(componentCarriers) > 1)
    error("sixgr:lls6g:config:CampaignNotSingleCarrier", ...
        "Resolved case '%s' has carrier_count=%g and %d component carriers.", ...
        caseID, carrierCount, numel(componentCarriers));
end
caEnabled = logical(sixgr.util.structGet(cfg, ...
    "frequency.carrier_aggregation_enabled", false));
if forbidCA && caEnabled
    error("sixgr:lls6g:config:CampaignCarrierAggregationForbidden", ...
        "Resolved case '%s' enables carrier aggregation.", caseID);
end
if forbidFrequencySweep && localAnyEnabledField(cfg, "frequency_sweep")
    error("sixgr:lls6g:config:CampaignFrequencySweepForbidden", ...
        "Resolved case '%s' enables a carrier-frequency sweep.", caseID);
end
if forbidNTN && localDomainEnabled(cfg, ["ntn", "satellite"])
    error("sixgr:lls6g:config:CampaignNTNForbidden", ...
        "Resolved case '%s' enables NTN/satellite processing.", caseID);
end
if forbidISAC && localDomainEnabled(cfg, ["isac", "sensing"])
    error("sixgr:lls6g:config:CampaignISACForbidden", ...
        "Resolved case '%s' enables ISAC/sensing processing.", caseID);
end
rows(end+1,1) = localBinding(scenarioPath, caseID, ...
    "frequency.carrier_count", "count", carrierCount, 1, "single_carrier_gate");
rows(end+1,1) = localBinding(scenarioPath, caseID, ...
    "frequency.carrier_aggregation_enabled", "boolean", caEnabled, false, "carrier_aggregation_gate");
end

function tf = localAnyEnabledField(value, token)
tf = false;
if isstruct(value)
    for name = string(fieldnames(value)).'
        child = value.(name);
        if contains(lower(name), lower(token))
            if islogical(child) && isscalar(child) && child
                tf = true; return;
            end
            if isstruct(child) && logical(sixgr.util.structGet(child, "enabled", false))
                tf = true; return;
            end
        end
        if localAnyEnabledField(child, token), tf = true; return; end
    end
elseif iscell(value)
    for index = 1:numel(value)
        if localAnyEnabledField(value{index}, token), tf = true; return; end
    end
end
end

function tf = localDomainEnabled(value, tokens)
tf = false;
if ~isstruct(value), return; end
for name = string(fieldnames(value)).'
    child = value.(name);
    if any(contains(lower(name), lower(tokens)))
        if (islogical(child) && isscalar(child) && child) || ...
                (isstruct(child) && logical(sixgr.util.structGet(child, "enabled", false)))
            tf = true; return;
        end
    end
    if localDomainEnabled(child, tokens), tf = true; return; end
end
end

function out = localCollectNamedNumericFields(value, prefix, names)
out = repmat(struct("Path", "", "Value", NaN), 0, 1);
if ~isstruct(value), return; end
for index = 1:numel(value)
    fields = string(fieldnames(value(index)));
    for fieldIndex = 1:numel(fields)
        name = fields(fieldIndex);
        path = localJoinPath(prefix, name, index, numel(value));
        child = value(index).(name);
        if any(lower(name) == lower(names)) && isnumeric(child) && isscalar(child)
            out(end+1,1) = struct("Path", path, "Value", double(child)); %#ok<AGROW>
        end
        childOut = localCollectNamedNumericFields(child, path, names);
        out = [out; childOut]; %#ok<AGROW>
    end
end
end

function out = localCollectNamedStringFields(value, prefix, nameWanted)
out = repmat(struct("Path", "", "Value", ""), 0, 1);
if ~isstruct(value), return; end
for index = 1:numel(value)
    fields = string(fieldnames(value(index)));
    for fieldIndex = 1:numel(fields)
        name = fields(fieldIndex);
        path = localJoinPath(prefix, name, index, numel(value));
        child = value(index).(name);
        if lower(name) == lower(nameWanted) && (isstring(child) || ischar(child))
            out(end+1,1) = struct("Path", path, "Value", string(child)); %#ok<AGROW>
        end
        childOut = localCollectNamedStringFields(child, path, nameWanted);
        out = [out; childOut]; %#ok<AGROW>
    end
end
end

function path = localJoinPath(prefix, name, index, count)
if strlength(prefix) == 0, path = name; else, path = prefix + "." + name; end
if count > 1, path = path + "(" + index + ")"; end
end

function row = localBinding(source, caseID, key, units, actual, required, verification)
row = localEmptyBinding();
row.SourceConfig = replace(string(source), "\", "/");
row.CaseID = string(caseID);
row.CanonicalKey = string(key);
row.Units = string(units);
row.ResolvedValue = string(actual);
row.RequiredValue = string(required);
row.SchemaOwner = "matrix.execution campaign constraint";
row.RuntimeConsumer = "sixgr.lls6g.runners.runMatrix";
row.Verification = string(verification);
end

function row = localEmptyBinding()
row = struct("SourceConfig", "", "CaseID", "", "CanonicalKey", "", ...
    "Units", "", "ResolvedValue", "", "RequiredValue", "", ...
    "SchemaOwner", "", "RuntimeConsumer", "", "Verification", "");
end

function pathOut = localResolveScenarioPath(matrixConfigPath, scenarioPath)
scenarioPath = char(string(scenarioPath));
if exist(scenarioPath, "file") == 2, pathOut = string(scenarioPath); return; end
candidate = fullfile(fileparts(char(matrixConfigPath)), scenarioPath);
if exist(candidate, "file") == 2, pathOut = string(candidate); return; end
root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
candidate = fullfile(root, scenarioPath);
if exist(candidate, "file") == 2, pathOut = string(candidate); return; end
error("sixgr:lls6g:runner:MatrixScenarioNotFound", ...
    "Unable to resolve matrix scenario '%s'.", string(scenarioPath));
end
