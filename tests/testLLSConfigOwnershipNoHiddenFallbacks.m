function ok = testLLSConfigOwnershipNoHiddenFallbacks()
%TESTLLSCONFIGOWNERSHIPNOHIDDENFALLBACKS Ensure behavior-owning fields are not silently backfilled in code.

setup6GRSimToolkit("Verbose", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml");
base = sixgr.lls6g.config.loadScenarioConfig(scenarioPath).toStruct();

cfgMissingWorkers = localRemoveNested(base, "run_control.num_workers");
localAssertBuildFails(cfgMissingWorkers, "MissingResolvedConfigValue");

cfgMissingHarqRetx = localRemoveNested(base, "harq.max_retx");
localAssertBuildFails(cfgMissingHarqRetx, "MissingResolvedConfigValue");

cfgMissingHARQValidation = localRemoveNested(base, "harq.validation_mode");
localAssertBuildFails(cfgMissingHARQValidation, "MissingResolvedConfigValue");

cfgMissingBeamMode = localRemoveNested(base, "link_adaptation.fixed_or_amc");
localAssertBuildFails(cfgMissingBeamMode, "MissingResolvedConfigValue");

cfgMissingCQITable = localRemoveNested(base, "link_adaptation.cqi_table");
localAssertBuildFails(cfgMissingCQITable, "MissingResolvedConfigValue");

cfgMissingCSIMode = localRemoveNested(base, "csi_acquisition_and_reporting.channel_state_information_mode");
cfgMissingCSIMode = localRemoveNested(cfgMissingCSIMode, "reference_signals.channel_state_information_mode");
cfgMissingCSIMode = localRemoveNested(cfgMissingCSIMode, "reference_signals.csi_feedback_mode");
localAssertBuildFails(cfgMissingCSIMode, "MissingResolvedConfigValue");

cfgMissingCQIPolicy = localRemoveNested(base, "csi_acquisition_and_reporting.cqi_policy");
cfgMissingCQIPolicy = localRemoveNested(cfgMissingCQIPolicy, "reference_signals.cqi_reporting_enabled");
localAssertBuildFails(cfgMissingCQIPolicy, "MissingResolvedConfigValue");

cfgMissingReportPayloadMode = localRemoveNested(base, "csi_acquisition_and_reporting.report_payload_mode");
localAssertBuildFails(cfgMissingReportPayloadMode, "MissingResolvedConfigValue");

cfgMissingIdealTimingSync = localRemoveNested(base, "receiver.use_ideal_timing_sync");
localAssertBuildFails(cfgMissingIdealTimingSync, "MissingResolvedConfigValue");

cfgMissingPDCCHGating = localRemoveNested(base, "control_gating.pdcch_required");
localAssertBuildFails(cfgMissingPDCCHGating, "MissingResolvedConfigValue");

cfgMissingSRSAge = localRemoveNested(base, "control_gating.srs_max_age_slots");
localAssertBuildFails(cfgMissingSRSAge, "MissingResolvedConfigValue");

cfgMissingTRSRequired = localRemoveNested(base, "control_gating.trs_required");
localAssertBuildFails(cfgMissingTRSRequired, "MissingResolvedConfigValue");

cfgMissingInterferenceExecutionMode = localRemoveNested(base, "interference.inter_cell_execution_mode");
localAssertBuildFails(cfgMissingInterferenceExecutionMode, "MissingResolvedConfigValue");

cfgMissingBSAntennaGeometry = localRemoveNested(base, "antenna_and_array.bs_array_geometry");
localAssertBuildFails(cfgMissingBSAntennaGeometry, "MissingResolvedConfigValue");

ok = true;
end

function localAssertBuildFails(s, expectedIdentifierSuffix)
tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
scfg = sixgr.lls6g.config.ScenarioConfig(s, ...
    "SourceFiles", strings(0,1), ...
    "ConfigPath", "", ...
    "ConfigHash", "test_missing_field", ...
    "Kind", "scenario");
failed = false;
try
    sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run")); %#ok<NASGU>
catch ME
    failed = true;
    assert(contains(string(ME.identifier), string(expectedIdentifierSuffix)), ...
        "Expected missing-config failure '%s', got '%s'.", string(expectedIdentifierSuffix), string(ME.identifier));
end
assert(failed, "buildInternalConfig must fail when a behavior-owning field is removed from resolved config.");
end

function s = localRemoveNested(s, pathStr)
parts = strsplit(char(string(pathStr)), ".");
s = localRemoveNestedImpl(s, parts, 1);
end

function s = localRemoveNestedImpl(s, parts, idx)
key = parts{idx};
if idx == numel(parts)
    if isfield(s, key)
        s = rmfield(s, key);
    end
    return;
end
if ~isfield(s, key) || ~isstruct(s.(key))
    return;
end
s.(key) = localRemoveNestedImpl(s.(key), parts, idx + 1);
end
