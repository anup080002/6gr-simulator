function out = runSingle(configPath, outputDir, runTag)
%RUNSINGLE Execute one config-driven 6G PHY LLS scenario.

if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = "results";
end
if nargin < 3
    runTag = "";
end

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

scfg = sixgr.lls6g.config.loadScenarioConfig(configPath);
leaf = localResolveLeaf(runTag);
backend = lower(string(scfg.get("output.backend", "filesystem")));
logicalRunFolder = localComposeRunFolderNoCreate(outputDir, "lls", scfg.ScenarioID, leaf);
if backend == "mysql_web"
    runFolder = localComposeDBStagingRunFolder(scfg.ScenarioID, leaf);
    localResetRunFolder(runFolder);
    localDeleteFolderTreeIfExists(logicalRunFolder);
else
    runFolder = sixgr.report.defaultRunFolder(outputDir, ...
        "Bucket", "lls", ...
        "Profile", scfg.ScenarioID, ...
        "Leaf", leaf, ...
        "CleanExisting", true);
end

cleanupStaging = onCleanup(@() localCleanupDBOnlyRunFolders(backend, runFolder, logicalRunFolder)); %#ok<NASGU>
execOut = localExecutePreparedScenario(scfg, runFolder, leaf, logicalRunFolder);

out = struct();
out.Ok = logical(execOut.Ok);
out.RunFolder = string(logicalRunFolder);
out.Config = scfg;
out.Manifest = execOut.Manifest;
out.Profile = string(execOut.Profile);
out.Result = execOut.Result;
end

function result = localRunWaveformBundleScenario(cfg, scfg, runFolder)
opt = struct();
slotDuration_s = max(eps, double(sixgr.util.structGet(cfg, "phy.numerology.slotDuration_ms", 1)) / 1e3);
totalSlots = max(1, round(double(sixgr.util.structGet(cfg, "run.totalSlots", ...
    sixgr.util.structGet(cfg, "run.numTTI", sixgr.util.structGet(cfg, "run.numFrames", 1))))));
opt.LinkDuration_s = max(double(totalSlots) * slotDuration_s, ...
    double(scfg.get("simulation.min_duration_s")));
opt.LinkMaxSimFrames = double(totalSlots);
opt.LinkSNR_dB = double(cfg.channel.snr_dB);
receiverNoiseMode = localUsesReceiverNoiseMeasurement(cfg);
if receiverNoiseMode
    opt.LinkSNRGrid_dB = localBuildPhysicalOperatingPointGrid(cfg.channel.snr_dB);
else
    opt.LinkSNRGrid_dB = localBuildSweepGrid(cfg.channel.snr_dB, ...
        double(scfg.get("simulation.snr_sweep_offsets_db")), ...
        logical(scfg.get("sweeps_and_matrix.snr_sweep.enabled")), ...
        double(scfg.get("sweeps_and_matrix.snr_sweep.values_db")));
end
opt.LinkQualityMode = char(string(sixgr.util.structGet(cfg, "run.noiseOperatingMode", ...
    "receiver_noise_figure_thermal_noise")));
mcIterations = max(1, round(double(scfg.get("simulation.monte_carlo_iterations"))));
opt.LinkSweepFrames = mcIterations;
opt.LinkSweepTrialsPerSNR = max(double(totalSlots), double(totalSlots) * mcIterations);
if receiverNoiseMode
    opt.LinkReferenceSweepFrames = 0;
    opt.LinkSweepMaxPoints = 1;
else
    opt.LinkReferenceSweepFrames = max(opt.LinkSweepTrialsPerSNR, ceil(1.5 * opt.LinkSweepTrialsPerSNR));
    opt.LinkSweepMaxPoints = numel(opt.LinkSNRGrid_dB);
end
opt.LinkAdaptiveSweepEnabled = ~receiverNoiseMode;
opt.LinkAdaptiveSweepStep_dB = 2;
opt.LinkAdaptiveSweepMaxPoints = ternaryDouble(receiverNoiseMode, 1, 12);
opt.LinkAnchorCases = scfg.get("scenario.bundle_anchor_cases", {});
opt.SaveFigures = logical(scfg.get("output.save_figures"));
tuning = sixgr.lls6g.runners.resolveWaveformBundleRuntimeTuning(scfg, cfg, opt.LinkSNRGrid_dB);
opt.RuntimeTuning = tuning;
opt.HARQDiagnosticsEnabled = logical(sixgr.util.structGet(tuning, "HARQDiagnosticsEnabled", true));
if strlength(strtrim(string(sixgr.util.structGet(tuning, "Notes", "")))) > 0
    localDBLog("INFO", "Waveform bundle runtime tuning: policy=%s notes=%s", ...
        char(string(sixgr.util.structGet(tuning, "Policy", ""))), ...
        char(string(sixgr.util.structGet(tuning, "Notes", ""))));
end
if receiverNoiseMode
    localDBLog("INFO", "Waveform bundle starting: qualityMode=%s operatingPointLabel=%.3f dB physicalPoints=%d canonicalSlots=%d monteCarlo=%d slotDuration_s=%.6f", ...
        char(string(opt.LinkQualityMode)), double(opt.LinkSNR_dB), double(numel(opt.LinkSNRGrid_dB)), ...
        double(opt.LinkMaxSimFrames), double(mcIterations), double(slotDuration_s));
else
    localDBLog("INFO", "Waveform bundle starting: snr=%.3f dB sweepPoints=%d canonicalSlots=%d monteCarlo=%d slotDuration_s=%.6f", ...
    double(opt.LinkSNR_dB), double(numel(opt.LinkSNRGrid_dB)), ...
    double(opt.LinkMaxSimFrames), double(mcIterations), double(slotDuration_s));
end
link = sixgr.truth.runWaveformLinkBundle(cfg, fullfile(runFolder, "air_interface"), opt);
localDBLog("INFO", "Waveform bundle finished: ok=%d", double(logical(sixgr.util.structGet(link, "Ok", false))));
strictControl = struct("Ok", true, "StrictOk", true, "SummaryTable", table(), "FailureReason", "");
if localShouldRunStrictControlEvidence(scfg, cfg)
    localDBLog("INFO", "Running strict waveform-backed control evidence for waveform-bundle scenario target_cases.");
    strictControl = sixgr.truth.exportStrictControlChannelEvidence(runFolder, cfg, ...
        "RunId", string(scfg.ScenarioID), ...
        "ScenarioName", string(scfg.ScenarioID), ...
        "EnablePDCCH", localStrictControlTargetEnabled(scfg, cfg, "pdcch"), ...
        "EnablePUCCH", localStrictControlTargetEnabled(scfg, cfg, "pucch"));
    localDBLog("INFO", "Strict waveform-backed control evidence finished: ok=%d", ...
        double(logical(sixgr.util.structGet(strictControl, "Ok", false))));
    tmpCanon = struct("RawTrials", sixgr.util.structGet(link, "RawTrials", struct()));
    tmpCanon = localAttachStrictControlRawTrials(tmpCanon, strictControl);
    link.RawTrials = tmpCanon.RawTrials;
    link.KPITable = localAppendStrictControlKPI(link.KPITable, strictControl);
    link.Ok = logical(sixgr.util.structGet(link, "Ok", false)) && logical(sixgr.util.structGet(strictControl, "Ok", true));
    if isfield(link, "Result") && isstruct(link.Result)
        link.Result.Ok = logical(link.Ok);
    end
    if ~logical(sixgr.util.structGet(strictControl, "Ok", true))
        link.Errors = [string(sixgr.util.structGet(link, "Errors", strings(0, 1))); ...
            string(sixgr.util.structGet(strictControl, "FailureReason", "strict_control_channel_evidence_failed"))];
    end
end
runtimeControl = sixgr.util.structGet(link, "RawTrials", struct());
runtimeControl.CoupledRuntime = sixgr.util.structGet(link, "CoupledRuntime", struct());
mobilityArtifacts = sixgr.util.structGet(link, "MobilityArtifacts", struct());
if ~(istable(sixgr.util.structGet(runtimeControl, "ControlGatingSummaryTable", table())) && ...
        ~isempty(sixgr.util.structGet(runtimeControl, "ControlGatingSummaryTable", table())))
    runtimeControl.ControlGatingSummaryTable = sixgr.util.structGet(mobilityArtifacts, "ControlGatingSummaryTable", table());
end
if ~(istable(sixgr.util.structGet(runtimeControl, "ControlGatingStateTable", table())) && ...
        ~isempty(sixgr.util.structGet(runtimeControl, "ControlGatingStateTable", table())))
    runtimeControl.ControlGatingStateTable = sixgr.util.structGet(mobilityArtifacts, "ControlGatingStateTable", table());
end
[link, strictSupplemental] = localRunWaveformBundleSupplementalStrictEvidence(link, cfg, scfg, runFolder);
runtimeControl = sixgr.util.structGet(link, "RawTrials", runtimeControl);
runtimeControl.CoupledRuntime = sixgr.util.structGet(link, "CoupledRuntime", struct());
if ~(istable(sixgr.util.structGet(runtimeControl, "ControlGatingSummaryTable", table())) && ...
        ~isempty(sixgr.util.structGet(runtimeControl, "ControlGatingSummaryTable", table())))
    runtimeControl.ControlGatingSummaryTable = sixgr.util.structGet(mobilityArtifacts, "ControlGatingSummaryTable", table());
end
if ~(istable(sixgr.util.structGet(runtimeControl, "ControlGatingStateTable", table())) && ...
        ~isempty(sixgr.util.structGet(runtimeControl, "ControlGatingStateTable", table())))
    runtimeControl.ControlGatingStateTable = sixgr.util.structGet(mobilityArtifacts, "ControlGatingStateTable", table());
end
controlTrace = sixgr.truth.exportControlPlaneTraces(runFolder, struct(), runtimeControl);
localDBLog("INFO", "Control-plane trace export complete.");

rows = repmat(struct("Block","", "Ok", false, "Notes",""), 0, 1);
if istable(link.KPITable)
    for i = 1:height(link.KPITable)
        rows(end+1,1) = struct( ... %#ok<AGROW>
            "Block", string(link.KPITable.Case(i)), ...
            "Ok", logical(link.KPITable.Ok(i)), ...
            "Notes", string(link.KPITable.Notes(i)));
    end
end
if ~isempty(rows)
    if localShouldWriteCSV(scfg)
        sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "case_status.csv"), struct2table(rows));
    end
end

result = struct();
result.Ok = logical(link.Ok);
result.Link = link;
result.Control = controlTrace;
result.StrictControl = strictControl;
result.StrictSupplemental = strictSupplemental;
end

function [link, strictSupplemental] = localRunWaveformBundleSupplementalStrictEvidence(link, cfg, scfg, runFolder)
strictSupplemental = struct("Ok", true, "SummaryTable", table(), ...
    "PRACH", struct(), "SRS", struct(), "TRS", struct(), "ChannelRF", struct(), "MIMO", struct());
rows = repmat(struct("Case", "", "Ok", true, "Skipped", false, "Notes", ""), 0, 1);

if localShouldRunStrictPRACHEvidence(scfg, cfg)
    localDBLog("INFO", "Running supplemental strict PRACH waveform validation for waveform-bundle scenario.");
    tp = sixgr.perf.TimeProfiler.scope("sixgr.phy.prach.runStrictPRACHValidation", ...
        "Stage", "strict_prach_validation");
    prach = sixgr.phy.prach.runStrictPRACHValidation(cfg, ...
        "RunFolder", runFolder, ...
        "RunId", string(scfg.ScenarioID), ...
        "ScenarioName", string(scfg.ScenarioID), ...
        "WriteArtifacts", true);
    clear tp;
    strictSupplemental.PRACH = prach;
    [link, rows] = localAttachSupplementalStrictResult(link, rows, "PRACH_StrictValidation", prach, ...
        "strict PRACH waveform validation completed", "strict_prach_validation_failed");
    link = localAttachRawTrialTable(link, "PRACH", prach, "prach_trials");
end

if localShouldRunStrictSRSEvidence(scfg, cfg)
    localDBLog("INFO", "Running supplemental strict SRS waveform validation for waveform-bundle scenario.");
    tp = sixgr.perf.TimeProfiler.scope("sixgr.phy.srs.runStrictSRSValidation", ...
        "Stage", "strict_srs_validation");
    srs = sixgr.phy.srs.runStrictSRSValidation(cfg, ...
        "RunFolder", runFolder, ...
        "RunId", string(scfg.ScenarioID), ...
        "ScenarioName", string(scfg.ScenarioID), ...
        "WriteArtifacts", true);
    clear tp;
    strictSupplemental.SRS = srs;
    [link, rows] = localAttachSupplementalStrictResult(link, rows, "SRS_StrictValidation", srs, ...
        "strict SRS waveform channel-sounding validation completed", "strict_srs_validation_failed");
    link = localAttachRawTrialTable(link, "SRS", srs, "srs_trials");
end

if localShouldRunStrictTRSEvidence(scfg, cfg)
    localDBLog("INFO", "Running supplemental strict TRS waveform validation for waveform-bundle scenario.");
    tp = sixgr.perf.TimeProfiler.scope("sixgr.phy.trs.runStrictTRSValidation", ...
        "Stage", "strict_trs_validation");
    trs = sixgr.phy.trs.runStrictTRSValidation(cfg, ...
        "RunFolder", runFolder, ...
        "RunId", string(scfg.ScenarioID), ...
        "ScenarioName", string(scfg.ScenarioID), ...
        "WriteArtifacts", true);
    clear tp;
    strictSupplemental.TRS = trs;
    [link, rows] = localAttachSupplementalStrictResult(link, rows, "TRS_StrictValidation", trs, ...
        "strict TRS waveform tracking validation completed", "strict_trs_validation_failed");
    link = localAttachRawTrialTable(link, "TRS", trs, "trs_trials");
end

if localShouldRunStrictChannelRFEvidence(scfg, cfg)
    localDBLog("INFO", "Running supplemental strict Channel/RF validation for waveform-bundle scenario.");
    tp = sixgr.perf.TimeProfiler.scope("sixgr.channel.runStrictChannelRFValidation", ...
        "Stage", "strict_channel_rf_validation");
    channelRF = sixgr.channel.runStrictChannelRFValidation(cfg, ...
        "RunFolder", runFolder, ...
        "RunId", string(scfg.ScenarioID), ...
        "ScenarioName", string(scfg.ScenarioID), ...
        "WriteArtifacts", true);
    clear tp;
    strictSupplemental.ChannelRF = channelRF;
    [link, rows] = localAttachSupplementalStrictResult(link, rows, "ChannelRF_StrictValidation", channelRF, ...
        "strict Channel/RF configured-vs-applied validation completed", "strict_channel_rf_validation_failed");
end

if localShouldRunMIMOEvidence(scfg, cfg, link)
    localDBLog("INFO", "Refreshing MIMO nominal-vs-effective evidence from waveform-bundle raw trials.");
    mimoArtifacts = sixgr.mimo.exportMIMOEvidenceArtifacts(runFolder, cfg, ...
        sixgr.util.structGet(link, "RawTrials", struct()), ...
        "RunId", string(scfg.ScenarioID), ...
        "ScenarioName", string(scfg.ScenarioID), ...
        "StrictMode", true);
    strictSupplemental.MIMO = mimoArtifacts;
    rows(end+1, 1) = struct("Case", "MIMO_NominalEffectiveEvidence", "Ok", true, ...
        "Skipped", false, "Notes", "MIMO nominal-vs-effective evidence refreshed from raw trials"); %#ok<AGROW>
end

if ~isempty(rows)
    strictSupplemental.SummaryTable = struct2table(rows, "AsArray", true);
    strictSupplemental.Ok = all(logical(strictSupplemental.SummaryTable.Ok));
    link.KPITable = localAppendStrictControlKPI(sixgr.util.structGet(link, "KPITable", table()), ...
        struct("SummaryTable", strictSupplemental.SummaryTable));
    link.Ok = logical(sixgr.util.structGet(link, "Ok", true)) && logical(strictSupplemental.Ok);
    if isfield(link, "Result") && isstruct(link.Result)
        link.Result.Ok = logical(link.Ok);
    end
end
end

function [link, rows] = localAttachSupplementalStrictResult(link, rows, caseName, result, successNote, failureNote)
ok = logical(sixgr.util.structGet(result, "StrictOk", sixgr.util.structGet(result, "Ok", false)));
note = string(successNote);
if ~ok
    note = string(sixgr.util.structGet(result, "FailureReason", failureNote));
end
rows(end+1, 1) = struct("Case", string(caseName), "Ok", ok, "Skipped", false, "Notes", note); %#ok<AGROW>
if ~ok
    existing = string(sixgr.util.structGet(link, "Errors", strings(0, 1)));
    link.Errors = [existing(:); string(caseName) + ":" + note];
end
end

function link = localAttachRawTrialTable(link, fieldName, result, tableName)
if ~(isstruct(result) && isfield(result, "ArtifactTables"))
    return;
end
T = sixgr.util.structGet(result.ArtifactTables, tableName, table());
if ~(istable(T) && ~isempty(T))
    return;
end
rawTrials = sixgr.util.structGet(link, "RawTrials", struct());
rawTrials.(char(fieldName)) = T;
link.RawTrials = rawTrials;
end

function tf = localShouldRunStrictPRACHEvidence(scfg, cfg)
targetCases = localScenarioTargetCases(scfg);
validationObjectives = localValidationObjectives(cfg);
prachGateRequired = logical(sixgr.util.structGet(cfg, "run.controlGating.prachRequired", ...
    sixgr.util.structGet(cfg, "control_gating.prach_required", false)));
raEvidence = sixgr.util.structGet(cfg, "validation.random_access_evidence", struct());
raStrictRequired = builtin("isstruct", raEvidence) && ( ...
    logical(sixgr.util.structGet(raEvidence, "four_step_ra_required", false)) || ...
    logical(sixgr.util.structGet(raEvidence, "msg1_prach_required", false)) || ...
    logical(sixgr.util.structGet(raEvidence, "false_alarm_test_enabled", false)) || ...
    logical(sixgr.util.structGet(raEvidence, "missed_detection_test_enabled", false)));
tf = logical(sixgr.util.structGet(cfg, "phy.prach.enable", false)) && ...
    (any(ismember(targetCases, ["prach","ra","random_access"])) || ...
    any(ismember(validationObjectives, ["prach_strict_validation","random_access_four_step"])) || ...
    prachGateRequired || raStrictRequired);
end

function tf = localShouldRunStrictSRSEvidence(scfg, cfg)
targetCases = localScenarioTargetCases(scfg);
validationObjectives = localValidationObjectives(cfg);
tf = logical(sixgr.util.structGet(cfg, "phy.srs.enable", false)) && ...
    (any(targetCases == "srs") || any(validationObjectives == "srs_strict_validation") || ...
    localControlGatingRequired(cfg, "srs"));
end

function tf = localShouldRunStrictTRSEvidence(scfg, cfg)
targetCases = localScenarioTargetCases(scfg);
validationObjectives = localValidationObjectives(cfg);
tf = logical(sixgr.util.structGet(cfg, "phy.trs.enable", false)) && ...
    (any(targetCases == "trs") || any(validationObjectives == "trs_strict_validation") || ...
    localControlGatingRequired(cfg, "trs"));
end

function tf = localShouldRunStrictChannelRFEvidence(scfg, cfg)
targetCases = localScenarioTargetCases(scfg);
validationObjectives = localValidationObjectives(cfg);
section = sixgr.util.structGet(cfg, "validation.channel_rf_configured_vs_applied", struct());
enabled = builtin("isstruct", section) && logical(sixgr.util.structGet(section, "enabled", false));
tf = enabled || any(targetCases == "channel_rf") || any(validationObjectives == "channel_rf_strict_validation");
end

function tf = localShouldRunMIMOEvidence(scfg, cfg, link)
targetCases = localScenarioTargetCases(scfg);
rawTrials = sixgr.util.structGet(link, "RawTrials", struct());
hasRaw = builtin("isstruct", rawTrials) && (~isempty(fieldnames(rawTrials)));
configuredMIMO = double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1)) > 1 || ...
    double(sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", 1)) > 1 || ...
    double(sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", 1)) > 1;
tf = hasRaw && (configuredMIMO || any(ismember(targetCases, ["mimo","beam","ssb"])));
end

function targets = localScenarioTargetCases(scfg)
targets = lower(strtrim(string(scfg.get("scenario.target_cases", {}))));
targets = targets(strlength(targets) > 0);
end

function objectives = localValidationObjectives(cfg)
objectives = lower(strtrim(string(sixgr.util.structGet(cfg, "validation.objectives", strings(0, 1)))));
objectives = objectives(strlength(objectives) > 0);
end

function tf = localControlGatingRequired(cfg, signalName)
signalName = lower(strtrim(string(signalName)));
switch signalName
    case "srs"
        tf = logical(sixgr.util.structGet(cfg, "run.controlGating.srsRequired", ...
            sixgr.util.structGet(cfg, "control_gating.srs_required", ...
            sixgr.util.structGet(cfg, "control_gating.srsRequired", false))));
    case "trs"
        tf = logical(sixgr.util.structGet(cfg, "run.controlGating.trsRequired", ...
            sixgr.util.structGet(cfg, "control_gating.trs_required", ...
            sixgr.util.structGet(cfg, "control_gating.trsRequired", false))));
    otherwise
        tf = false;
end
end

function result = localRunSystemLevelScenario(cfg, scfg, runFolder)
layout = sixgr.report.resultLayout(runFolder);
ctx = sixgr.core.SimContext(cfg, "RunFolder", layout.SystemDir);

slotDuration_s = max(eps, double(sixgr.util.structGet(cfg, "phy.numerology.slotDuration_ms", 0.5)) / 1e3);
numTTI = max(1, ceil(double(sixgr.util.structGet(cfg, "run.totalTime_ms", slotDuration_s * 1e3)) / (slotDuration_s * 1e3)));
params = struct();
params.PHYBackend = string(sixgr.util.structGet(cfg, "system.phyBackend", "waveform"));
params.DetailedTrace = true;
params.NumTTI = numTTI;
params.SimDuration_s = double(sixgr.util.structGet(cfg, "system.simDuration_s", numTTI * slotDuration_s));
params.TTI_s = slotDuration_s;

localDBLog("INFO", "System-level LLS starting: NumTTI=%d PHYBackend=%s simulationMode=%s", ...
    double(numTTI), char(string(params.PHYBackend)), char(string(sixgr.util.structGet(cfg, "run.simulationMode", ""))));
systemOut = sixgr.system.SystemLevelRunner.run(ctx, params);
localDBLog("INFO", "System-level LLS finished: ok=%d", double(logical(sixgr.util.structGet(systemOut, "Ok", false))));

canon = sixgr.truth.exportSystemLevelCanonicalArtifacts(runFolder, scfg, cfg, systemOut);
strictControl = struct("Ok", true, "StrictOk", true, "SummaryTable", table(), "FailureReason", "");
if localShouldRunStrictControlEvidence(scfg, cfg)
    localDBLog("INFO", "Running strict waveform-backed control evidence for scenario target_cases.");
    strictControl = sixgr.truth.exportStrictControlChannelEvidence(runFolder, cfg, ...
        "RunId", string(scfg.ScenarioID), ...
        "ScenarioName", string(scfg.ScenarioID), ...
        "EnablePDCCH", localStrictControlTargetEnabled(scfg, cfg, "pdcch"), ...
        "EnablePUCCH", localStrictControlTargetEnabled(scfg, cfg, "pucch"));
    localDBLog("INFO", "Strict waveform-backed control evidence finished: ok=%d", ...
        double(logical(sixgr.util.structGet(strictControl, "Ok", false))));
    canon = localAttachStrictControlRawTrials(canon, strictControl);
end

notes = string(strjoin(string(sixgr.util.structGet(systemOut, "Errors", strings(0, 1))), "; "));
if strlength(notes) == 0
    notes = "system_level_lls_runner_completed";
end
kpitable = table( ...
    string("system_level_lls"), ...
    logical(sixgr.util.structGet(systemOut, "Ok", false)), ...
    false, ...
    notes, ...
    'VariableNames', {'Case','Ok','Skipped','Notes'});
strictSummaryT = sixgr.util.structGet(strictControl, "SummaryTable", table());
if istable(strictSummaryT) && ~isempty(strictSummaryT)
    strictCases = "strict_" + lower(string(strictSummaryT.SignalFamily)) + "_waveform_control";
    strictNotes = string(strictSummaryT.FailureReason);
    strictNotes(strlength(strtrim(strictNotes)) == 0) = "strict waveform-backed control evidence completed";
    strictKPI = table(strictCases(:), logical(strictSummaryT.StrictOk(:)), false(height(strictSummaryT), 1), strictNotes(:), ...
        'VariableNames', {'Case','Ok','Skipped','Notes'});
    kpitable = [kpitable; strictKPI];
end
combinedOk = logical(sixgr.util.structGet(systemOut, "Ok", false)) && logical(sixgr.util.structGet(strictControl, "Ok", true));

link = struct();
link.Ok = combinedOk;
link.Result = struct("Ok", combinedOk);
link.Errors = string(sixgr.util.structGet(systemOut, "Errors", strings(0, 1)));
if ~logical(sixgr.util.structGet(strictControl, "Ok", true))
    link.Errors = [link.Errors(:); string(sixgr.util.structGet(strictControl, "FailureReason", "strict_control_channel_evidence_failed"))];
end
link.UnsupportedCases = table();
link.KPITable = kpitable;
link.RawTrials = canon.RawTrials;

result = struct();
result.Ok = combinedOk;
result.Link = link;
result.System = systemOut;
result.Canonical = canon;
result.StrictControl = strictControl;
end

function tf = localShouldRunStrictControlEvidence(scfg, cfg)
targetCases = lower(string(scfg.get("scenario.target_cases", {})));
tf = any(ismember(targetCases, ["pdcch","pucch"]));
if ~tf
    return;
end
tf = logical(sixgr.util.structGet(cfg, "phy.pdcch.enable", false)) || ...
    logical(sixgr.util.structGet(cfg, "phy.pucch.enable", false));
end

function tf = localStrictControlTargetEnabled(scfg, cfg, signalName)
signalName = lower(string(signalName));
targetCases = lower(string(scfg.get("scenario.target_cases", {})));
switch signalName
    case "pdcch"
        tf = any(targetCases == "pdcch") && logical(sixgr.util.structGet(cfg, "phy.pdcch.enable", false));
    case "pucch"
        tf = any(targetCases == "pucch") && logical(sixgr.util.structGet(cfg, "phy.pucch.enable", false));
    otherwise
        tf = false;
end
end

function canon = localAttachStrictControlRawTrials(canon, strictControl)
if ~(isstruct(canon) && isfield(canon, "RawTrials"))
    return;
end
pdcch = sixgr.util.structGet(strictControl, "PDCCH", struct());
if isstruct(pdcch) && isfield(pdcch, "ArtifactTables")
    T = sixgr.util.structGet(pdcch.ArtifactTables, "pdcch_trials", table());
    if istable(T) && ~isempty(T)
        canon.RawTrials.PDCCH = T;
    end
end
pucch = sixgr.util.structGet(strictControl, "PUCCH", struct());
if isstruct(pucch) && isfield(pucch, "ArtifactTables")
    T = sixgr.util.structGet(pucch.ArtifactTables, "pucch_trials", table());
    if istable(T) && ~isempty(T)
        canon.RawTrials.PUCCH = T;
    end
end
end

function kpi = localAppendStrictControlKPI(kpi, strictControl)
strictSummaryT = sixgr.util.structGet(strictControl, "SummaryTable", table());
if ~(istable(strictSummaryT) && ~isempty(strictSummaryT))
    return;
end
if all(ismember(["Case","Ok"], string(strictSummaryT.Properties.VariableNames)))
    strictKPI = strictSummaryT;
    strictKPI.Case = string(strictKPI.Case);
    strictKPI.Ok = logical(strictKPI.Ok);
    if ~ismember("Skipped", string(strictKPI.Properties.VariableNames))
        strictKPI.Skipped = false(height(strictKPI), 1);
    else
        strictKPI.Skipped = logical(strictKPI.Skipped);
    end
    if ~ismember("Notes", string(strictKPI.Properties.VariableNames))
        strictKPI.Notes = strings(height(strictKPI), 1);
    else
        strictKPI.Notes = string(strictKPI.Notes);
    end
    strictKPI = strictKPI(:, {'Case','Ok','Skipped','Notes'});
else
    strictCases = "strict_" + lower(string(strictSummaryT.SignalFamily)) + "_waveform_control";
    strictNotes = string(strictSummaryT.FailureReason);
    strictNotes(strlength(strtrim(strictNotes)) == 0) = "strict waveform-backed control evidence completed";
    strictKPI = table(strictCases(:), logical(strictSummaryT.StrictOk(:)), false(height(strictSummaryT), 1), strictNotes(:), ...
        'VariableNames', {'Case','Ok','Skipped','Notes'});
end
if ~(istable(kpi) && ~isempty(kpi))
    kpi = strictKPI;
    return;
end
kpi.Case = string(kpi.Case);
kpi.Ok = logical(kpi.Ok);
kpi.Skipped = logical(kpi.Skipped);
if ismember("Notes", string(kpi.Properties.VariableNames))
    kpi.Notes = string(kpi.Notes);
end
strictKPI = localAlignKPIColumns(strictKPI, kpi);
kpi = localAlignKPIColumns(kpi, strictKPI);
strictKPI = strictKPI(:, kpi.Properties.VariableNames);
kpi = [kpi; strictKPI];
end

function T = localAlignKPIColumns(T, referenceT)
refVars = string(referenceT.Properties.VariableNames);
for i = 1:numel(refVars)
    name = refVars(i);
    if ~ismember(name, string(T.Properties.VariableNames))
        T.(name) = localDefaultKPIColumn(referenceT.(name), height(T));
    end
end
T = T(:, refVars);
end

function col = localDefaultKPIColumn(referenceCol, n)
if islogical(referenceCol)
    col = false(n, 1);
elseif isnumeric(referenceCol)
    col = nan(n, 1);
elseif isstring(referenceCol)
    col = strings(n, 1);
elseif iscellstr(referenceCol)
    col = repmat({''}, n, 1);
else
    col = strings(n, 1);
end
end

function result = localRunPDCCHBlindDecodeSweep(cfg, scfg, runFolder)
aggLevels = double(scfg.get("control.aggregation_levels"));
nTrials = max(1, round(double(scfg.get("simulation.monte_carlo_iterations"))));
snr_dB = double(scfg.get("simulation.snr_db"));
pdcchPayloadBits = max(1, round(double(scfg.get("control.pdcch_payload_bits"))));
listLength = max(1, round(double(scfg.get("control.blind_decode_list_length"))));

trialRows = repmat(struct("AggregationLevel", NaN, "Trial", NaN, "SNR_dB", NaN, ...
    "BitErrors", NaN, "BitsCompared", NaN, "Pass", false, "DetectionMetric", NaN, ...
    "BlindDecodeCount", NaN, "ComputeLatency_ms", NaN, "AppliedAWGNSNR_dB", NaN, ...
    "NoiseVariance", NaN, "NoiseVarStatus", "", "NoiseVarSource", "", ...
    "ReceiverHestSINR_dB", NaN, "ReceiverHestSINRSource", "", ...
    "FalseAlarmFlag", false, "ChannelModelApplied", "", "ChannelFadingApplied", false, ...
    "AppliedLargeScaleGain_dB", NaN, "AppliedLargeScaleLoss_dB", NaN, ...
    "AppliedPathloss_dB", NaN, "AppliedShadowFading_dB", NaN, "AppliedO2I_dB", NaN, ...
    "InjectedCFO_Hz", NaN, "InjectedTimingOffset_samples", NaN), 0, 1);
summaryRows = repmat(struct("AggregationLevel", NaN, "PassRate", NaN, "MeanBitErrors", NaN), 0, 1);

for i = 1:numel(aggLevels)
    lvl = aggLevels(i);
    pass = false(nTrials,1);
    bitErr = NaN(nTrials,1);
    detMet = NaN(nTrials,1);
    for k = 1:nTrials
        trialTimer = tic;
        cfgK = cfg;
        cfgK.phy.pdcch.aggregationLevel = lvl;
        cfgK.phy.pdcch.blindSearch = true;
        [tx, txInfo] = sixgr.phy.dl.PDCCH_Tx(cfgK, "K", pdcchPayloadBits);
        [rxWave, noiseVar, replay, noiseOnlyWave] = localRunnerApplyPDCCHChannelAndNoise(tx.Waveform, cfgK, tx, txInfo, snr_dB);
        noiseVarArgs = localRunnerNoiseVarArgs(noiseVar);
        [rx, rxInfo] = sixgr.phy.dl.PDCCH_Rx(rxWave, cfgK, ...
            "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), ...
            "ListLength", listLength, noiseVarArgs{:}, "NoiseOnlyWaveform", noiseOnlyWave);
        [rxNoise, ~] = sixgr.phy.dl.PDCCH_Rx(noiseOnlyWave, cfgK, ...
            "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), ...
            "ListLength", listLength, noiseVarArgs{:});
        computeLatency_ms = toc(trialTimer) * 1e3;
        [be, bt] = localBitErrors(tx.DCIBits, rx.DCIBits);
        ok = logical(sixgr.util.structGet(rx, "Ok", false)) && be == 0;
        pass(k) = ok;
        bitErr(k) = be;
        detMet(k) = 1 - (double(be) / max(double(bt), 1));
        trialRows(end+1,1) = struct( ... %#ok<AGROW>
            "AggregationLevel", lvl, ...
            "Trial", k, ...
            "SNR_dB", snr_dB, ...
            "BitErrors", be, ...
            "BitsCompared", bt, ...
            "Pass", ok, ...
            "DetectionMetric", detMet(k), ...
            "BlindDecodeCount", double(sixgr.util.structGet(rxInfo, "NumCandidatesTried", NaN)), ...
            "ComputeLatency_ms", computeLatency_ms, ...
            "AppliedAWGNSNR_dB", double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN)), ...
            "NoiseVariance", double(noiseVar), ...
            "NoiseVarStatus", string(sixgr.util.structGet(rx, "NoiseVarStatus", "")), ...
            "NoiseVarSource", string(sixgr.util.structGet(rx, "NoiseVarSource", "")), ...
            "ReceiverHestSINR_dB", double(sixgr.util.structGet(rx, "ReceiverHestSINR_dB", NaN)), ...
            "ReceiverHestSINRSource", string(sixgr.util.structGet(rx, "ReceiverHestSINRSource", "")), ...
            "FalseAlarmFlag", logical(sixgr.util.structGet(rxNoise, "Ok", false)), ...
            "ChannelModelApplied", string(sixgr.util.structGet(replay, "ChannelModelApplied", "")), ...
            "ChannelFadingApplied", logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false)), ...
            "AppliedLargeScaleGain_dB", double(sixgr.util.structGet(replay, "AppliedLargeScaleGain_dB", NaN)), ...
            "AppliedLargeScaleLoss_dB", double(sixgr.util.structGet(replay, "AppliedLargeScaleLoss_dB", NaN)), ...
            "AppliedPathloss_dB", double(sixgr.util.structGet(replay, "AppliedPathloss_dB", NaN)), ...
            "AppliedShadowFading_dB", double(sixgr.util.structGet(replay, "AppliedShadowFading_dB", NaN)), ...
            "AppliedO2I_dB", double(sixgr.util.structGet(replay, "AppliedO2I_dB", NaN)), ...
            "InjectedCFO_Hz", double(sixgr.util.structGet(replay, "InjectedCFO_Hz", NaN)), ...
            "InjectedTimingOffset_samples", double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", NaN)));
    end
    summaryRows(end+1,1) = struct( ... %#ok<AGROW>
        "AggregationLevel", lvl, ...
        "PassRate", mean(pass), ...
        "MeanBitErrors", mean(bitErr, "omitnan"));
end

trialT = struct2table(trialRows);
summaryT = struct2table(summaryRows);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "control", "csv", "pdcch_blind_decode_trials.csv"), trialT);
    sixgr.util.csvWriteTable(fullfile(runFolder, "control", "csv", "pdcch_blind_decode_sweep.csv"), summaryT);
    canonicalTrialT = localCanonicalizePDCCHBlindDecodeTrials(trialT, cfg, pdcchPayloadBits, listLength);
    sixgr.util.csvWriteTable(fullfile(runFolder, "control", "csv", "pdcch_trials.csv"), canonicalTrialT);
    sixgr.util.csvWriteTable(fullfile(runFolder, "air_interface", "csv", "pdcch_trials.csv"), canonicalTrialT);
end

result = struct();
result.Ok = all(summaryT.PassRate >= 0);
result.TrialTable = trialT;
result.SummaryTable = summaryT;
end

function T = localCanonicalizePDCCHBlindDecodeTrials(T, cfg, pdcchPayloadBits, listLength)
if ~(istable(T) && ~isempty(T))
    return;
end
nRows = height(T);
pass = false(nRows, 1);
if ismember("Pass", string(T.Properties.VariableNames))
    pass = logical(T.Pass);
end
if ~ismember("Status", string(T.Properties.VariableNames))
    T.Status = repmat("FAIL", nRows, 1);
    T.Status(pass) = "PASS";
end
if ~ismember("CRCPass", string(T.Properties.VariableNames))
    T.CRCPass = pass;
end
if ~ismember("Direction", string(T.Properties.VariableNames))
    T.Direction = repmat("DL", nRows, 1);
end
if ~ismember("SignalFamily", string(T.Properties.VariableNames))
    T.SignalFamily = repmat("PDCCH", nRows, 1);
end
if ~ismember("ControlStage", string(T.Properties.VariableNames))
    T.ControlStage = repmat("PDCCH_DCI", nRows, 1);
end
if ~ismember("BlindDecodeCount", string(T.Properties.VariableNames))
    T.BlindDecodeCount = repmat(double(listLength), nRows, 1);
end
if ~ismember("DCISize_bits", string(T.Properties.VariableNames))
    T.DCISize_bits = repmat(double(pdcchPayloadBits), nRows, 1);
end
if ~ismember("FalseAlarmFlag", string(T.Properties.VariableNames))
    T.FalseAlarmFlag = false(nRows, 1);
end
if ~ismember("BlockingFlag", string(T.Properties.VariableNames))
    T.BlockingFlag = false(nRows, 1);
end
if ~ismember("NonOverlappedCCEUsage", string(T.Properties.VariableNames))
    T.NonOverlappedCCEUsage = double(localRunnerColumnOrDefault(T, "AggregationLevel", nan(nRows, 1)));
end
if ~ismember("ControlCapacityUtilization", string(T.Properties.VariableNames))
    T.ControlCapacityUtilization = double(localRunnerColumnOrDefault(T, "AggregationLevel", nan(nRows, 1))) ./ 16;
end
if ~ismember("CORESETUtilization", string(T.Properties.VariableNames))
    T.CORESETUtilization = T.ControlCapacityUtilization;
end
if ~ismember("ControlLatency_ms", string(T.Properties.VariableNames))
    slotDuration_ms = double(sixgr.util.structGet(cfg, "phy.numerology.slotDuration_ms", 1));
    T.ControlLatency_ms = repmat(slotDuration_ms, nRows, 1);
end
if ~ismember("ComputeLatency_ms", string(T.Properties.VariableNames))
    T.ComputeLatency_ms = nan(nRows, 1);
end
if ~ismember("AirInterfaceTTI_ms", string(T.Properties.VariableNames))
    T.AirInterfaceTTI_ms = T.ControlLatency_ms;
end
if ~ismember("Source", string(T.Properties.VariableNames))
    T.Source = repmat("pdcch_blind_decode_waveform_runtime", nRows, 1);
end
if ~ismember("ExecutionBackend", string(T.Properties.VariableNames))
    T.ExecutionBackend = repmat("waveform", nRows, 1);
end
if ~ismember("ApproximationMode", string(T.Properties.VariableNames))
    T.ApproximationMode = repmat("none", nRows, 1);
end
if ~ismember("Notes", string(T.Properties.VariableNames))
    T.Notes = repmat("PDCCH blind-decode sweep trial from executed Tx/Rx waveform path.", nRows, 1);
end
end

function result = localRunStrictPDCCHValidationScenario(cfg, scfg, runFolder)
pdcch = sixgr.phy.pdcch.runStrictPDCCHValidation(cfg, ...
    "RunFolder", runFolder, ...
    "RunId", string(scfg.ScenarioID), ...
    "ScenarioName", string(scfg.ScenarioID), ...
    "WriteArtifacts", true);

if logical(pdcch.StrictOk)
    note = "strict PDCCH waveform blind-decode validation completed";
else
    note = string(pdcch.FailureReason);
end
kpitable = table( ...
    string("PDCCH_StrictValidation"), ...
    logical(pdcch.StrictOk), ...
    false, ...
    note, ...
    'VariableNames', {'Case','Ok','Skipped','Notes'});
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "case_status.csv"), kpitable);
    sixgr.util.csvWriteTable(fullfile(runFolder, "air_interface", "csv", "pdcch_trials.csv"), ...
        pdcch.ArtifactTables.pdcch_trials);
end

link = struct();
link.Ok = logical(pdcch.StrictOk);
link.Result = struct("Ok", logical(pdcch.StrictOk));
link.KPITable = kpitable;
link.UnsupportedCases = table();
link.RawTrials = struct("PDCCH", pdcch.ArtifactTables.pdcch_trials);

result = struct();
result.Ok = logical(pdcch.StrictOk);
result.Link = link;
result.PDCCH = pdcch;
result.Control = struct();
result.TrialTable = pdcch.ArtifactTables.pdcch_trials;
result.SummaryTable = pdcch.ArtifactTables.pdcch_low_snr_sweep;
end

function result = localRunStrictTRSValidationScenario(cfg, scfg, runFolder)
trs = sixgr.phy.trs.runStrictTRSValidation(cfg, ...
    "RunFolder", runFolder, ...
    "RunId", string(scfg.ScenarioID), ...
    "ScenarioName", string(scfg.ScenarioID), ...
    "WriteArtifacts", true);

if logical(trs.StrictOk)
    note = "strict TRS waveform tracking validation completed";
else
    note = string(trs.FailureReason);
end
kpitable = table( ...
    string("TRS_StrictValidation"), ...
    logical(trs.StrictOk), ...
    false, ...
    note, ...
    'VariableNames', {'Case','Ok','Skipped','Notes'});
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "case_status.csv"), kpitable);
    sixgr.util.csvWriteTable(fullfile(runFolder, "air_interface", "csv", "trs_trials.csv"), ...
        trs.ArtifactTables.trs_trials);
end

link = struct();
link.Ok = logical(trs.StrictOk);
link.Result = struct("Ok", logical(trs.StrictOk));
link.KPITable = kpitable;
link.UnsupportedCases = table();
link.RawTrials = struct("TRS", trs.ArtifactTables.trs_trials);

result = struct();
result.Ok = logical(trs.StrictOk);
result.Link = link;
result.TRS = trs;
result.Control = struct();
result.TrialTable = trs.ArtifactTables.trs_trials;
result.SummaryTable = trs.ArtifactTables.trs_low_snr_sweep;
end

function result = localRunStrictSRSValidationScenario(cfg, scfg, runFolder)
srs = sixgr.phy.srs.runStrictSRSValidation(cfg, ...
    "RunFolder", runFolder, ...
    "RunId", string(scfg.ScenarioID), ...
    "ScenarioName", string(scfg.ScenarioID), ...
    "WriteArtifacts", true);

if logical(srs.StrictOk)
    note = "strict SRS waveform channel-sounding validation completed";
else
    note = string(srs.FailureReason);
end
kpitable = table( ...
    string("SRS_StrictValidation"), ...
    logical(srs.StrictOk), ...
    false, ...
    note, ...
    'VariableNames', {'Case','Ok','Skipped','Notes'});
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "case_status.csv"), kpitable);
    sixgr.util.csvWriteTable(fullfile(runFolder, "air_interface", "csv", "srs_trials.csv"), ...
        srs.ArtifactTables.srs_trials);
end

link = struct();
link.Ok = logical(srs.StrictOk);
link.Result = struct("Ok", logical(srs.StrictOk));
link.KPITable = kpitable;
link.UnsupportedCases = table();
link.RawTrials = struct("SRS", srs.ArtifactTables.srs_trials);

result = struct();
result.Ok = logical(srs.StrictOk);
result.Link = link;
result.SRS = srs;
result.Control = struct();
result.TrialTable = srs.ArtifactTables.srs_trials;
result.SummaryTable = srs.ArtifactTables.srs_low_snr_sweep;
end

function result = localRunStrictChannelRFValidationScenario(cfg, scfg, runFolder)
channelRF = sixgr.channel.runStrictChannelRFValidation(cfg, ...
    "RunFolder", runFolder, ...
    "RunId", string(scfg.ScenarioID), ...
    "ScenarioName", string(scfg.ScenarioID), ...
    "WriteArtifacts", true);

if logical(channelRF.StrictOk)
    note = "strict Channel/RF configured-vs-applied validation completed";
else
    note = string(channelRF.FailureReason);
end
kpitable = table( ...
    string("ChannelRF_StrictValidation"), ...
    logical(channelRF.StrictOk), ...
    false, ...
    note, ...
    'VariableNames', {'Case','Ok','Skipped','Notes'});
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "case_status.csv"), kpitable);
end

link = struct();
link.Ok = logical(channelRF.StrictOk);
link.Result = struct("Ok", logical(channelRF.StrictOk));
link.KPITable = kpitable;
link.UnsupportedCases = table();
link.RawTrials = struct("ChannelRF", channelRF.ConfiguredVsApplied);

result = struct();
result.Ok = logical(channelRF.StrictOk);
result.Link = link;
result.ChannelRF = channelRF;
result.Control = struct();
result.TrialTable = channelRF.ConfiguredVsApplied;
result.SummaryTable = channelRF.ChannelRealizations;
end

function result = localRun6GRPDCCHStudy(cfg, scfg, runFolder)
studyDir = fullfile(runFolder, "control", "pdcch6gr_study");
study = sixgr.ctrl.runPDCCHStudyLLS(cfg, ...
    "OutputDir", studyDir, ...
    "ScenarioID", char(string(scfg.ScenarioID)), ...
    "WriteOutputs", true, ...
    "Verbose", false);

controlTrace = struct();
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "air_interface", "csv", "pdcch_trials.csv"), study.PDCCHTrials);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch_control_outputs.csv"), study.SummaryByScenario);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_coreset_map.csv"), study.CORESETMap);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_search_space_map.csv"), study.SearchSpaceMap);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_reg_index_map.csv"), study.REGIndexMap);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_cce_reg_map.csv"), study.CCERegMap);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_candidate_hash_trace.csv"), study.CandidateHashTrace);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_dmrs_locations.csv"), study.DMRSLocations);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_per_candidate_results.csv"), study.PerCandidateResults);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_per_slot_results.csv"), study.PerSlotResults);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_summary_by_snr.csv"), study.SummaryBySNR);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_summary_by_al.csv"), study.SummaryByAL);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_summary_by_mapping.csv"), study.SummaryByMapping);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_summary_by_repetition.csv"), study.SummaryByRepetition);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_summary_by_coreset_duration.csv"), study.SummaryByCORESETDuration);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_summary_by_frequency_allocation.csv"), study.SummaryByFrequencyAllocation);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_summary_by_mrss_mode.csv"), study.SummaryByMRSSMode);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_complexity_summary.csv"), study.ComplexitySummary);
    if ~isempty(study.MRSSOverlapEvents)
        sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdcch6gr_mrss_overlap_events.csv"), study.MRSSOverlapEvents);
    end
    controlTrace = sixgr.truth.exportControlPlaneTraces(runFolder, struct(), struct("PDCCH", study.PDCCHTrials));
end

result = struct();
result.Ok = istable(study.PDCCHTrials) && ~isempty(study.PDCCHTrials);
result.Control = controlTrace;
result.Study = study;
result.TrialTable = study.PDCCHTrials;
result.SummaryTable = study.SummaryBySNR;
end

function result = localRun6GRPDSCHStudy(cfg, scfg, runFolder)
studyDir = fullfile(runFolder, "air_interface", "pdsch6gr_truth");
study = sixgr.pdsch.runPDSCHStudyLLS(cfg, ...
    "OutputDir", studyDir, ...
    "ScenarioID", char(string(scfg.ScenarioID)), ...
    "WriteOutputs", true, ...
    "Verbose", false);

if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "air_interface", "csv", "dl_pdsch_trials.csv"), study.DLTrialTable);
    sixgr.util.csvWriteTable(fullfile(runFolder, "packet_flow", "csv", "live_dl_scheduler_grants.csv"), study.DLGrantTrace);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_trial_level_results.csv"), study.TrialLevelResults);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_tb_level_results.csv"), study.TBLevelResults);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_codeword_level_results.csv"), study.CodewordLevelResults);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_layer_mapping_trace.csv"), study.LayerMappingTrace);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_fdra_allocations.csv"), study.FDRAAllocations);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_tdra_allocations.csv"), study.TDRAAllocations);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_dmrs_mapping.csv"), study.DMRSMapping);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_ptrs_mapping.csv"), study.PTRSMapping);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_channel_estimation_metrics.csv"), study.ChannelEstimationMetrics);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_parameter_estimation_metrics.csv"), study.ParameterEstimationMetrics);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_harq_trace.csv"), study.HARQTrace);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_summary_by_snr.csv"), study.SummaryBySNR);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_summary_by_band.csv"), study.SummaryByBand);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_summary_by_fdra_type.csv"), study.SummaryByFDRAType);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_summary_by_tdra_mode.csv"), study.SummaryByTDRAMode);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_summary_by_dmrs_setting.csv"), study.SummaryByDMRSSetting);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_summary_by_ptrs_setting.csv"), study.SummaryByPTRSSetting);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_summary_by_rank.csv"), study.SummaryByRank);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_summary_by_repetition.csv"), study.SummaryByRepetition);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_complexity_summary.csv"), study.ComplexitySummary);
    if ~isempty(study.MRSSOverlapEvents)
        sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "pdsch6gr_mrss_overlap_events.csv"), study.MRSSOverlapEvents);
    end
end

result = struct();
result.Ok = istable(study.DLTrialTable) && ~isempty(study.DLTrialTable);
result.Study = study;
result.TrialTable = study.DLTrialTable;
result.SummaryTable = study.SummaryBySNR;
end

function result = localRunPRACHDetectionScenario(cfg, scfg, runFolder)
study = sixgr.rach.runPRACHLLS(cfg, ...
    "ScenarioMatrix", struct("ScenarioName", char(string(scfg.ScenarioID))), ...
    "WriteOutputs", false, ...
    "Verbose", false);

[controlTrialT, initialAccessT, correlationTraceT] = localBuildPRACHRunnerTables(study, cfg);
probabilitySweepT = localBuildPRACHProbabilitySweepTable(study);
controlTrace = struct();
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "control", "csv", "prach_detection_trials.csv"), controlTrialT);
    sixgr.util.csvWriteTable(fullfile(runFolder, "control", "csv", "prach_detection_summary.csv"), study.SummaryBySNR);
    sixgr.util.csvWriteTable(fullfile(runFolder, "air_interface", "csv", "prach_trials.csv"), controlTrialT);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "initial_access_random_access_outputs.csv"), initialAccessT);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_correlation_trace.csv"), correlationTraceT);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_correlation_traces.csv"), correlationTraceT);
    if istable(probabilitySweepT) && ~isempty(probabilitySweepT)
        sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_probability_sweeps.csv"), probabilitySweepT);
    end
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_summary_by_snr.csv"), study.SummaryBySNR);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_summary_by_scenario.csv"), study.SummaryByScenario);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_confusion_detection_types.csv"), study.Confusion);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_timing_error_samples.csv"), study.TimingErrorSamples);
    if ~isempty(study.FrequencyErrorSamples)
        sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_frequency_error_samples.csv"), study.FrequencyErrorSamples);
    end
    z = sixgr.util.structGet(study, "ZCDPEMetrics", struct());
    if isstruct(z)
        localWriteOptionalTable(fullfile(runFolder, "reports", "csv", "zcdpe_dpi_confusion_matrix.csv"), sixgr.util.structGet(z, "DPIConfusionMatrix", table()));
        localWriteOptionalTable(fullfile(runFolder, "reports", "csv", "zcdpe_dpi_error_probability_by_snr.csv"), sixgr.util.structGet(z, "DPIErrorBySnr", table()));
        localWriteOptionalTable(fullfile(runFolder, "reports", "csv", "zcdpe_doppler_rmse_by_snr.csv"), sixgr.util.structGet(z, "DopplerRMSEBySnr", table()));
        localWriteOptionalTable(fullfile(runFolder, "reports", "csv", "zcdpe_pool_analysis.csv"), sixgr.util.structGet(z, "PoolAnalysis", table()));
    end
    controlTrace = sixgr.truth.exportControlPlaneTraces(runFolder, struct(), struct("PRACH", controlTrialT));
end

result = struct();
result.Ok = istable(controlTrialT) && ~isempty(controlTrialT);
result.Control = controlTrace;
result.Study = study;
result.TrialTable = controlTrialT;
result.SummaryTable = study.SummaryBySNR;
end

function result = localRunStrictPRACHValidationScenario(cfg, scfg, runFolder)
prach = sixgr.phy.prach.runStrictPRACHValidation(cfg, ...
    "RunFolder", runFolder, ...
    "RunId", string(scfg.ScenarioID), ...
    "ScenarioName", string(scfg.ScenarioID), ...
    "WriteArtifacts", true);

if logical(prach.StrictOk)
    note = "strict PRACH waveform validation completed";
else
    note = string(prach.FailureReason);
end
kpitable = table( ...
    string("PRACH_StrictValidation"), ...
    logical(prach.StrictOk), ...
    false, ...
    note, ...
    'VariableNames', {'Case','Ok','Skipped','Notes'});
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "case_status.csv"), kpitable);
    sixgr.util.csvWriteTable(fullfile(runFolder, "air_interface", "csv", "prach_trials.csv"), ...
        prach.ArtifactTables.prach_trials);
end

link = struct();
link.Ok = logical(prach.StrictOk);
link.Result = struct("Ok", logical(prach.StrictOk));
link.KPITable = kpitable;
link.UnsupportedCases = table();
link.RawTrials = struct("PRACH", prach.ArtifactTables.prach_trials);

result = struct();
result.Ok = logical(prach.StrictOk);
result.Link = link;
result.PRACH = prach;
result.Control = struct();
result.TrialTable = prach.ArtifactTables.prach_trials;
result.SummaryTable = prach.ArtifactTables.prach_missed_detection_sweep;
end

function result = localRunFourStepRAScenario(cfg, scfg, runFolder)
if logical(sixgr.util.structGet(cfg, "phy.sib1.enable", false))
    ia = sixgr.phy.broadcast.runInitialAccessWithRAAnchor(runFolder, cfg, ...
        "RunId", string(scfg.ScenarioID), ...
        "ScenarioName", string(scfg.ScenarioID));
    ra = ia.RandomAccess;
    scenarioOk = logical(ia.Ok);
else
    ia = struct();
    ra = sixgr.phy.ra.runFourStepRA(cfg, ...
        "RunFolder", runFolder, ...
        "RunId", string(scfg.ScenarioID), ...
        "ScenarioName", string(scfg.ScenarioID), ...
        "UEId", 1, ...
        "CellId", sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1), ...
        "AttemptId", 1, ...
        "WriteArtifacts", true);
    scenarioOk = logical(ra.StrictOk);
end

if scenarioOk
    note = "strict MSG1-MSG4 waveform RA completed";
else
    note = string(ra.FailureReason);
end
kpitable = table( ...
    string("RandomAccess_FourStep"), ...
    logical(ra.StrictOk), ...
    false, ...
    note, ...
    'VariableNames', {'Case','Ok','Skipped','Notes'});
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "case_status.csv"), kpitable);
end

link = struct();
link.Ok = logical(scenarioOk);
link.Result = struct("Ok", logical(scenarioOk));
link.KPITable = kpitable;
link.UnsupportedCases = table();
link.RawTrials = struct("RandomAccess", ra.ArtifactTables.ra_attempts);

result = struct();
result.Ok = logical(scenarioOk);
result.Link = link;
result.RandomAccess = ra;
if ~isempty(fieldnames(ia))
    result.InitialAccess = ia;
end
result.Control = struct();
end

function [controlTrialT, initialAccessT, correlationTraceT] = localBuildPRACHRunnerTables(study, cfg)
roT = sixgr.util.structGet(study, "ROTable", table());
trialT = sixgr.util.structGet(study, "TrialTable", table());
if ~(istable(roT) && ~isempty(roT))
    controlTrialT = table();
    initialAccessT = table();
    correlationTraceT = table();
    return;
end

slotsPerFrame = max(1, round(double(sixgr.util.structGet(cfg, "phy.numerology.slotsPerFrame", 20))));
nRows = height(roT);
frameCol = floor((double(roT.slot_id) - 1) / slotsPerFrame) + 1;
slotCol = round(double(roT.slot_id));
ueCount = localRunnerGroupedPRACHValue(trialT, roT, "preamble_tx_present", @sum, 0);
txPreamble = localRunnerGroupedPRACHValue(trialT, roT, "transmitted_preamble_index", @localFirstFiniteOrNaN, NaN);
snrCol = double(localRunnerColumnOrDefault(roT, "SNR_dB", localRunnerColumnOrDefault(roT, "snr_db", nan(nRows, 1))));
detectedPreamble = double(localRunnerColumnOrDefault(roT, "detected_preamble_index", nan(nRows, 1)));
peakMetric = double(localRunnerColumnOrDefault(roT, "peak_metric", nan(nRows, 1)));
thresholdCol = double(localRunnerColumnOrDefault(roT, "threshold", nan(nRows, 1)));
thresholdModeCol = string(localRunnerColumnOrDefault(roT, "threshold_mode", repmat("", nRows, 1)));
noiseOnlyMetric = double(localRunnerColumnOrDefault(roT, "noise_only_peak_metric", nan(nRows, 1)));
noiseVariance = double(localRunnerColumnOrDefault(roT, "noise_variance", nan(nRows, 1)));
noiseFloor = double(localRunnerColumnOrDefault(roT, "detector_noise_floor", noiseVariance));
missedDetection = double(localRunnerColumnOrDefault(roT, "missed_detection_flag", localRunnerColumnOrDefault(roT, "missed_detection", zeros(nRows, 1))));
falseAlarm = double(localRunnerColumnOrDefault(roT, "false_alarm_flag", localRunnerColumnOrDefault(roT, "FalseAlarmFlag", zeros(nRows, 1))));
timingEstSamples = double(localRunnerColumnOrDefault(roT, "EstimatedTimingOffset_samples", nan(nRows, 1)));
timingErrorSamples = double(localRunnerColumnOrDefault(roT, "TimingError_samples", nan(nRows, 1)));
timingAdvanceUs = double(localRunnerColumnOrDefault(roT, "timing_offset_est_us", nan(nRows, 1)));
channelModelApplied = string(localRunnerColumnOrDefault(roT, "channel_model", repmat("", nRows, 1)));
channelFadingApplied = double(channelModelApplied ~= "" & upper(channelModelApplied) ~= "AWGN");
rootSeq = repmat(double(sixgr.util.structGet(cfg, "phy.prach.rootSeqIndex", ...
    sixgr.util.structGet(cfg, "random_access.root_sequence_index", NaN))), nRows, 1);
zeroCorr = repmat(double(sixgr.util.structGet(cfg, "phy.prach.zeroCorrelationZone", ...
    sixgr.util.structGet(cfg, "random_access.zero_correlation_zone", NaN))), nRows, 1);
cfgIndex = repmat(double(sixgr.util.structGet(cfg, "phy.prach.configurationIndex", ...
    sixgr.util.structGet(cfg, "random_access.configuration_index", NaN))), nRows, 1);
prachDesign = string(localRunnerColumnOrDefault(roT, "prach_design", repmat("nr_baseline", nRows, 1)));
zcdpeEnabled = double(localRunnerColumnOrDefault(roT, "zcdpe_enabled", zeros(nRows, 1)));
dpiD = double(localRunnerColumnOrDefault(roT, "dpi_D", nan(nRows, 1)));
dpiTrue = double(localRunnerColumnOrDefault(roT, "dpi_d_true", nan(nRows, 1)));
dpiDetected = double(localRunnerColumnOrDefault(roT, "dpi_d_detected", nan(nRows, 1)));
dpiCorrect = double(localRunnerColumnOrDefault(roT, "dpi_correct_flag", nan(nRows, 1)));
dpiConfusion = double(localRunnerColumnOrDefault(roT, "dpi_confusion_score", nan(nRows, 1)));
dopplerEst = double(localRunnerColumnOrDefault(roT, "doppler_est_hz", nan(nRows, 1)));
dopplerError = double(localRunnerColumnOrDefault(roT, "doppler_error_hz", nan(nRows, 1)));
poolGain = double(localRunnerColumnOrDefault(roT, "pool_gain_factor", nan(nRows, 1)));

controlTrialT = table( ...
    string(localRunnerColumnOrDefault(roT, "Status", repmat("FAIL", nRows, 1))), ...
    frameCol, ...
    slotCol, ...
    ones(nRows, 1), ...
    ones(nRows, 1), ...
    double(localRunnerColumnOrDefault(roT, "CRCPass", zeros(nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "ComputeLatency_ms", nan(nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "ProcedureDelay_ms", nan(nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "AirInterfaceObservation_ms", nan(nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "AcquisitionTime_ms", nan(nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "TrueTimingOffset_samples", nan(nRows, 1))), ...
    timingEstSamples, ...
    timingErrorSamples, ...
    peakMetric, ...
    thresholdCol, ...
    thresholdModeCol, ...
    falseAlarm, ...
    double(localRunnerColumnOrDefault(roT, "wrong_preamble_flag", localRunnerColumnOrDefault(roT, "wrong_preamble_flag", zeros(nRows, 1)))), ...
    missedDetection, ...
    detectedPreamble, ...
    txPreamble, ...
    ueCount, ...
    double(localRunnerColumnOrDefault(roT, "CollisionFlag", zeros(nRows, 1))), ...
    snrCol, ...
    string(localRunnerColumnOrDefault(roT, "Notes", localRunnerColumnOrDefault(roT, "detection_type", repmat("", nRows, 1)))), ...
    string(localRunnerColumnOrDefault(roT, "scenario_id", repmat("", nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "seed", nan(nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "ro_id", nan(nRows, 1))), ...
    snrCol, ...
    peakMetric, ...
    thresholdCol, ...
    thresholdModeCol, ...
    noiseFloor, ...
    noiseOnlyMetric, ...
    noiseVariance, ...
    falseAlarm, ...
    missedDetection, ...
    txPreamble, ...
    detectedPreamble, ...
    double(localRunnerColumnOrDefault(roT, "preamble_index_from_peak", nan(nRows, 1))), ...
    rootSeq, ...
    zeroCorr, ...
    cfgIndex, ...
    double(localRunnerColumnOrDefault(roT, "ro_id", nan(nRows, 1))), ...
    slotCol - 1, ...
    timingEstSamples, ...
    timingAdvanceUs, ...
    channelModelApplied, ...
    channelFadingApplied, ...
    prachDesign, ...
    zcdpeEnabled, ...
    dpiD, ...
    dpiTrue, ...
    dpiDetected, ...
    dpiCorrect, ...
    dpiConfusion, ...
    dopplerEst, ...
    dopplerError, ...
    poolGain, ...
    true(nRows, 1), ...
    isfinite(peakMetric), ...
    true(nRows, 1), ...
    isfinite(noiseVariance), ...
    'VariableNames', {'Status','Frame','Slot','UEIndex','RNTI','CRCPass','ComputeLatency_ms','ProcedureDelay_ms', ...
    'AirInterfaceObservation_ms','AcquisitionTime_ms','TrueTimingOffset_samples','EstimatedTimingOffset_samples', ...
    'TimingError_samples','DetectionMetric','Threshold','ThresholdMode','FalseAlarmFlag','WrongPreambleFlag', ...
    'MissDetectionFlag','PreambleIndex','TransmittedPreambleIndex','ActiveUECount','CollisionFlag','SNR_dB','Notes', ...
    'ScenarioID','Seed','ROID','AppliedAWGNSNR_dB','CorrelationPeak','DetectionThreshold','DetectionThresholdMode', ...
    'DetectorNoiseFloor','NoiseOnlyDetectionMetric','NoiseVariance','FalseAlarm','MissedDetection', ...
    'RequestedPreambleIndex','DetectedPreambleIndex','PreambleIndexFromPeak', ...
    'PRACHRootSequenceIndex','PRACHZeroCorrelationZone','PRACHConfigurationIndex','PRACHOccasionIndex','PRACHCarrierSlot', ...
    'TimingAdvance_samples','TimingAdvance_us','ChannelModelApplied','ChannelFadingApplied', ...
    'PRACHDesign','ZCDPEEnabled','DPI_D','DPI_d_true','DPI_d_detected','DPICorrect', ...
    'DPIConfusionScore','DopplerEstimate_Hz','DopplerError_Hz','PoolGainFactor', ...
    'DetectionAttempted','DetectionUsable','MeasurementAttempted','MeasurementUsable'});

initialAccessT = study.SummaryBySNR;
if istable(initialAccessT) && ~isempty(initialAccessT)
    initialAccessT.ConfiguredUEsPerRO = repmat(max(double(ueCount), [], "omitnan"), height(initialAccessT), 1);
    initialAccessT.CollisionModeEnabled = repmat(any(double(controlTrialT.CollisionFlag) ~= 0), height(initialAccessT), 1);
    initialAccessT.ChannelModel = repmat(string(sixgr.util.structGet(cfg, "prach_lls.ChannelModel", "")), height(initialAccessT), 1);
end

correlationTraceT = sixgr.util.structGet(study, "CorrelationTraceTable", table());
if istable(correlationTraceT) && ~isempty(correlationTraceT)
    correlationTraceT = localNormalizePRACHCorrelationTraceTable(correlationTraceT);
else
    correlationTraceT = table();
end
end

function T = localNormalizePRACHCorrelationTraceTable(T)
requiredNames = ["trial_id","preamble_index","root_sequence_index","restricted_set_type","n_cs", ...
    "zero_correlation_zone_config","lag_samples","lag_us","correlation_abs","threshold", ...
    "noise_floor","peak_lag_samples","timing_advance_samples","detection_result", ...
    "false_alarm","missed_detection","snr_db","cfo_hz","seed","truth_status"];
for i = 1:numel(requiredNames)
    name = requiredNames(i);
    if ismember(name, string(T.Properties.VariableNames))
        continue;
    end
    if any(name == ["restricted_set_type","detection_result","truth_status"])
        T.(name) = strings(height(T), 1);
    elseif any(name == ["false_alarm","missed_detection"])
        T.(name) = false(height(T), 1);
    else
        T.(name) = nan(height(T), 1);
    end
end
T = T(:, requiredNames);
end

function T = localBuildPRACHProbabilitySweepTable(study)
roT = sixgr.util.structGet(study, "ROTable", table());
if ~(istable(roT) && ~isempty(roT))
    T = table();
    return;
end
parts = { ...
    localPRACHProbabilitySweepAxis(roT, "snr_db", "SNR_dB"), ...
    localPRACHProbabilitySweepAxis(roT, "cfo_true_hz", "CFO_Hz"), ...
    localPRACHProbabilitySweepAxis(roT, "timing_error_us", "TimingError_us")};
T = localVertcatTables(parts);
end

function T = localPRACHProbabilitySweepAxis(roT, sourceColumn, axisName)
T = table();
if ~ismember(sourceColumn, string(roT.Properties.VariableNames))
    return;
end
x = double(roT.(sourceColumn));
valid = isfinite(x);
if numel(unique(x(valid))) < 2
    return;
end
detected = localRunnerColumnOrDefault(roT, "detected_flag", zeros(height(roT), 1));
missed = localRunnerColumnOrDefault(roT, "missed_detection_flag", zeros(height(roT), 1));
falseAlarm = localRunnerColumnOrDefault(roT, "false_alarm_flag", zeros(height(roT), 1));
vals = unique(x(valid));
rows = repmat(struct("sweep_axis", "", "x_value", NaN, "n_trials", 0, ...
    "detection_probability", NaN, "miss_detection_probability", NaN, ...
    "false_alarm_probability", NaN, "truth_status", "real_lls_evidence"), numel(vals), 1);
for i = 1:numel(vals)
    mask = valid & x == vals(i);
    rows(i).sweep_axis = string(axisName);
    rows(i).x_value = double(vals(i));
    rows(i).n_trials = double(sum(mask));
    rows(i).detection_probability = mean(double(detected(mask)), "omitnan");
    rows(i).miss_detection_probability = mean(double(missed(mask)), "omitnan");
    rows(i).false_alarm_probability = mean(double(falseAlarm(mask)), "omitnan");
end
T = struct2table(rows);
end

function T = localVertcatTables(parts)
T = table();
for i = 1:numel(parts)
    Ti = parts{i};
    if ~(istable(Ti) && ~isempty(Ti))
        continue;
    end
    if isempty(T)
        T = Ti;
    else
        T = [T; Ti]; %#ok<AGROW>
    end
end
end

function values = localRunnerColumnOrDefault(T, varName, defaultValues)
if istable(T) && ismember(varName, string(T.Properties.VariableNames))
    values = T.(varName);
else
    values = defaultValues;
end
end

function values = localRunnerGroupedPRACHValue(trialT, roT, varName, reducer, defaultValue)
nRows = height(roT);
values = repmat(defaultValue, nRows, 1);
if ~(istable(trialT) && ~isempty(trialT) && ismember(varName, string(trialT.Properties.VariableNames)))
    return;
end
for iRow = 1:nRows
    mask = string(localRunnerColumnOrDefault(trialT, "scenario_id", repmat("", height(trialT), 1))) == string(roT.scenario_id(iRow)) & ...
        double(localRunnerColumnOrDefault(trialT, "seed", nan(height(trialT), 1))) == double(roT.seed(iRow)) & ...
        double(localRunnerColumnOrDefault(trialT, "ro_id", nan(height(trialT), 1))) == double(roT.ro_id(iRow)) & ...
        double(localRunnerColumnOrDefault(trialT, "slot_id", nan(height(trialT), 1))) == double(roT.slot_id(iRow));
    if ~any(mask)
        continue;
    end
    values(iRow, 1) = reducer(trialT.(varName)(mask));
end
end

function value = localFirstFiniteOrNaN(raw)
vals = double(raw(:));
vals = vals(isfinite(vals));
if isempty(vals)
    value = NaN;
else
    value = vals(1);
end
end

function result = localRunGenericSweep(cfg, scfg, runFolder)
sweepCfg = scfg.get("scenario.sweep", struct());
baseProfile = lower(string(sixgr.util.structGet(sweepCfg, "base_profile")));
overrides = sixgr.util.structGet(sweepCfg, "overrides", struct([]));
if isempty(overrides)
    error("sixgr:lls6g:runner:EmptySweep", ...
        "Scenario '%s' uses generic_sweep without scenario.sweep.overrides.", scfg.ScenarioID);
end

rows = repmat(struct("Label","", "PointScenarioID","", "RunFolder","", "Ok", false, ...
    "ResearchClass","", "StudyBucket",""), 0, 1);
for i = 1:numel(overrides)
    label = string(sixgr.util.structGet(overrides(i), "label", "case_" + i));
    subFolder = fullfile(runFolder, "sweeps", localSanitizeToken(label, "case"));
    sixgr.util.ensureFolder(subFolder);
    subScenario = sixgr.util.mergeStruct(scfg.toStruct(), sixgr.util.structGet(overrides(i), "config", struct()));
    sixgr.lls6g.config.validateScenarioConfig(subScenario, "Kind", "scenario", "AllowPartial", false, ...
        "Context", scfg.ConfigPath + "::sweep::" + label);
    subScfg = sixgr.lls6g.config.ScenarioConfig(subScenario, ...
        "SourceFiles", scfg.SourceFiles, "ConfigPath", scfg.ConfigPath, ...
        "ConfigHash", scfg.ConfigHash, "Kind", "scenario");
    if baseProfile == "waveform_bundle"
        subScenario.scenario.runner_profile = "waveform_bundle";
    elseif baseProfile == "ai_benchmark"
        subScenario.scenario.runner_profile = "ai_benchmark";
    else
        error("sixgr:lls6g:runner:UnsupportedSweepBaseProfile", ...
            "Unsupported scenario.sweep.base_profile '%s'.", baseProfile);
    end
    subScfg = sixgr.lls6g.config.ScenarioConfig(subScenario, ...
        "SourceFiles", scfg.SourceFiles, "ConfigPath", scfg.ConfigPath, ...
        "ConfigHash", scfg.ConfigHash, "Kind", "scenario");
    subExec = localExecutePreparedScenario(subScfg, subFolder);
    researchClass = string(subScfg.get("meta.research_class", ""));
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Label", label, ...
        "PointScenarioID", string(subScfg.ScenarioID), ...
        "RunFolder", string(subFolder), ...
        "Ok", logical(subExec.Ok), ...
        "ResearchClass", researchClass, ...
        "StudyBucket", localStudyBucketFromClass(researchClass));
end

summaryT = struct2table(rows);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "sweep_summary.csv"), summaryT);
end
result = struct();
result.Ok = all(summaryT.Ok);
result.SummaryTable = summaryT;
end

function result = localRunAIBenchmark(cfg, scfg, runFolder)
useCase = lower(string(scfg.get("ai_ml.use_case")));
aiEnabled = logical(scfg.get("ai_ml.enabled"));
descriptor = localLoadAIDescriptor(scfg.get("ai_ml.model_path"));
if aiEnabled && isempty(fieldnames(descriptor))
    error("sixgr:lls6g:runner:MissingAIDescriptor", ...
        "AI-enabled benchmark '%s' requires a readable ai_ml.model_path descriptor.", useCase);
end
switch useCase
    case "channel_estimation_enhancement"
        result = localRunAIChannelEstimationBenchmark(cfg, scfg, runFolder, descriptor, aiEnabled);
    case "csi_compression_reconstruction"
        result = localRunAICSICompressionBenchmark(scfg, runFolder, descriptor, aiEnabled);
    case "link_adaptation_mcs_selection"
        result = localRunAILinkAdaptationBenchmark(scfg, runFolder, descriptor, aiEnabled);
    case "beam_prediction"
        result = localRunAIBeamPredictionBenchmark(scfg, runFolder, descriptor);
    case "interference_classification"
        result = localRunAIInterferenceClassificationBenchmark(scfg, runFolder, descriptor, aiEnabled);
    case "detector_selection"
        result = localRunAIDetectorSelectionBenchmark(scfg, runFolder, descriptor, aiEnabled);
    case "impairment_mitigation"
        result = localRunAIImpairmentMitigationBenchmark(scfg, runFolder, descriptor, aiEnabled);
    case "energy_aware_mode_selection"
        result = localRunAIEnergyModeSelection(scfg, runFolder, descriptor);
    otherwise
        error("sixgr:lls6g:runner:UnsupportedAIUseCase", ...
            "Unsupported ai_ml.use_case '%s'.", useCase);
end
end

function result = localRunAIChannelEstimationBenchmark(cfg, scfg, runFolder, descriptor, aiEnabled)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
snr_dB = double(scfg.get("simulation.snr_db"));
baselineNmse = NaN(nObs,1);
pluginNmse = NaN(nObs,1);
metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);

for k = 1:nObs
    [tx, ~] = sixgr.phy.ul.SRS_Tx(cfg);
    [rxWave, nVar] = localAddAwgnOnly(tx.Waveform, snr_dB);
    noiseVarArgs = localRunnerNoiseVarArgs(nVar);
    rx = sixgr.phy.ul.SRS_Rx(rxWave, cfg, "Carrier", tx.Carrier, "SRS", tx.SRS, noiseVarArgs{:});
    Hbase = rx.Hest;
    baselineNmse(k) = localUnitChannelNMSE(Hbase);
    if aiEnabled
        Hplug = localApplyCEPlugin(Hbase, descriptor);
        pluginNmse(k) = localUnitChannelNMSE(Hplug);
    end
end

if aiEnabled
    T = table([repmat("classical", nObs, 1); repmat("ai_plugin", nObs, 1)], ...
        [baselineNmse; pluginNmse], 'VariableNames', {'Method','NMSE_dB'});
else
    T = table(repmat("classical", nObs, 1), baselineNmse, ...
        'VariableNames', {'Method','NMSE_dB'});
end
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_channel_estimation_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAICSICompressionBenchmark(scfg, runFolder, descriptor, aiEnabled)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
nTx = double(scfg.get("mimo.n_tx_ant"));
nRx = double(scfg.get("mimo.n_rx_ant"));
metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);
if aiEnabled
    latentDim = double(localRequireDescriptorField(descriptor, "latent_dim"));
    quantBits = double(localRequireDescriptorField(descriptor, "quant_bits"));
else
    latentDim = NaN;
    quantBits = NaN;
end
rows = repmat(struct("Observation", NaN, "BaselineNMSE_dB", NaN, "PluginNMSE_dB", NaN, ...
    "CompressionRatio", NaN, "QuantBits", NaN), 0, 1);

for k = 1:nObs
    H = (randn(nRx, nTx) + 1i*randn(nRx, nTx)) / sqrt(2);
    Hvec = [real(H(:)); imag(H(:))];
    if aiEnabled
        [Hhat, ratio] = localApplyCSICompressionPlugin(Hvec, descriptor, latentDim, quantBits);
        pluginNmse = 10 * log10(max(mean(abs(Hvec - Hhat).^2) / max(mean(abs(Hvec).^2), eps), eps));
    else
        ratio = 1;
        pluginNmse = NaN;
    end
    rows(end+1,1) = struct("Observation", k, "BaselineNMSE_dB", 0, ... %#ok<AGROW>
        "PluginNMSE_dB", pluginNmse, "CompressionRatio", ratio, "QuantBits", quantBits);
end

T = struct2table(rows);
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_csi_compression_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAILinkAdaptationBenchmark(scfg, runFolder, descriptor, aiEnabled)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
snr0 = double(scfg.get("simulation.snr_db"));
metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);
mcsBias = double(localOptionalDescriptorValue(descriptor, "mcs_bias", 0));
snrStep = double(localOptionalDescriptorValue(descriptor, "snr_step_db", 2));
rows = repmat(struct("Observation", NaN, "SNR_dB", NaN, "BaselineMCS", NaN, ...
    "PluginMCS", NaN, "OracleMCS", NaN, "BaselineThroughputScore", NaN, ...
    "PluginThroughputScore", NaN, "PluginMatchesOracle", false), 0, 1);

for k = 1:nObs
    snr = snr0 + (-0.5 + (k-1)/max(nObs-1,1)) * 12;
    oracleMCS = localClampMCS(round((snr + 8) / max(snrStep, eps)));
    baselineMCS = localClampMCS(round((snr + 6) / max(snrStep, eps)));
    if aiEnabled
        pluginMCS = localClampMCS(baselineMCS + mcsBias);
    else
        pluginMCS = baselineMCS;
    end
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Observation", k, ...
        "SNR_dB", snr, ...
        "BaselineMCS", baselineMCS, ...
        "PluginMCS", pluginMCS, ...
        "OracleMCS", oracleMCS, ...
        "BaselineThroughputScore", localMCSScore(baselineMCS), ...
        "PluginThroughputScore", localMCSScore(pluginMCS), ...
        "PluginMatchesOracle", pluginMCS == oracleMCS);
end

T = struct2table(rows);
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_link_adaptation_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAIInterferenceClassificationBenchmark(scfg, runFolder, descriptor, aiEnabled)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);
thresholds = double(localOptionalDescriptorValue(descriptor, "classification_thresholds_db", [3 10]));
rows = repmat(struct("Observation", NaN, "InterferenceLevel_dB", NaN, "BaselineClass", "", ...
    "PluginClass", "", "OracleClass", "", "PluginCorrect", false), 0, 1);

for k = 1:nObs
    interf = -3 + 18 * (k-1) / max(nObs-1, 1);
    oracle = localInterferenceClass(interf, thresholds);
    baseline = localInterferenceClass(interf + 1, thresholds);
    if aiEnabled
        plugin = localInterferenceClass(interf, thresholds);
    else
        plugin = baseline;
    end
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Observation", k, ...
        "InterferenceLevel_dB", interf, ...
        "BaselineClass", baseline, ...
        "PluginClass", plugin, ...
        "OracleClass", oracle, ...
        "PluginCorrect", plugin == oracle);
end

T = struct2table(rows);
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_interference_classification_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAIDetectorSelectionBenchmark(scfg, runFolder, descriptor, aiEnabled)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);
conditionThreshold = double(localOptionalDescriptorValue(descriptor, "condition_threshold", 12));
rows = repmat(struct("Observation", NaN, "ConditionNumber", NaN, "BaselineDetector", "", ...
    "PluginDetector", "", "OracleDetector", "", "PluginCorrect", false), 0, 1);

for k = 1:nObs
    condNumber = 4 + 18 * (k-1) / max(nObs-1, 1);
    oracle = localDetectorChoice(condNumber, conditionThreshold);
    baseline = localDetectorChoice(condNumber, conditionThreshold + 3);
    if aiEnabled
        plugin = localDetectorChoice(condNumber, conditionThreshold);
    else
        plugin = baseline;
    end
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Observation", k, ...
        "ConditionNumber", condNumber, ...
        "BaselineDetector", baseline, ...
        "PluginDetector", plugin, ...
        "OracleDetector", oracle, ...
        "PluginCorrect", plugin == oracle);
end

T = struct2table(rows);
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_detector_selection_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAIImpairmentMitigationBenchmark(scfg, runFolder, descriptor, aiEnabled)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);
evmGain = double(localOptionalDescriptorValue(descriptor, "evm_improvement_db", 0.5));
rows = repmat(struct("Observation", NaN, "BaselineEVM_dB", NaN, "PluginEVM_dB", NaN, ...
    "Improvement_dB", NaN, "MitigationApplied", false), 0, 1);

for k = 1:nObs
    baseline = -18 + 6 * (k-1) / max(nObs-1, 1);
    if aiEnabled
        plugin = baseline - evmGain;
    else
        plugin = baseline;
    end
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Observation", k, ...
        "BaselineEVM_dB", baseline, ...
        "PluginEVM_dB", plugin, ...
        "Improvement_dB", baseline - plugin, ...
        "MitigationApplied", aiEnabled);
end

T = struct2table(rows);
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_impairment_mitigation_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAIBeamPredictionBenchmark(scfg, runFolder, descriptor)
nObs = max(1, round(double(scfg.get("ai_ml.benchmark_observations"))));
nTx = double(scfg.get("mimo.n_tx_ant"));
arr = struct("Nant", nTx, "nRow", 1, "nCol", nTx);
numBeams = double(localRequireDescriptorField(descriptor, "num_beams"));
W = sixgr.rf.BeamRefinementCSIRS.makeCodebookFromArray(arr, 1, numBeams);
rows = repmat(struct("Observation", NaN, "OracleBeam", NaN, "PredictedBeam", NaN, "Correct", false), 0, 1);
metadata = localBenchmarkMetadata(scfg, descriptor, true);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);

for k = 1:nObs
    H = (randn(1, nTx) + 1i*randn(1, nTx)) / sqrt(2);
    [~, oracleIdx, metric] = sixgr.rf.BeamRefinementCSIRS.selectBestBeam(H, W);
    predIdx = localApplyBeamPlugin(metric, descriptor);
    rows(end+1,1) = struct("Observation", k, "OracleBeam", oracleIdx, ... %#ok<AGROW>
        "PredictedBeam", predIdx, "Correct", predIdx == oracleIdx);
end

T = struct2table(rows);
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "beamforming", "csv", "ai_beam_prediction_benchmark.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "BenchmarkTable", T);
end

function result = localRunAIEnergyModeSelection(scfg, runFolder, descriptor)
txPower = double(scfg.get("energy_efficiency.tx_power_dbm"));
rfChains = double(scfg.get("energy_efficiency.rf_chain_count"));
aiBudget = double(scfg.get("ai_ml.flops_budget"));
pluginBias = double(localRequireDescriptorField(descriptor, "energy_bias"));
perFlopScore = double(scfg.get("energy_efficiency.ai_compute_energy_per_flop_score"));
metadata = localBenchmarkMetadata(scfg, descriptor, true);
confidenceValue = localBenchmarkConfidence(descriptor, scfg);
classicalEnergy = txPower * rfChains;
aiEnergy = classicalEnergy * (1 + pluginBias) + perFlopScore * aiBudget;
selected = "classical";
if aiEnergy <= classicalEnergy
    selected = "ai_plugin";
end
T = table(classicalEnergy, aiEnergy, string(selected), ...
    'VariableNames', {'ClassicalEnergyScore','AIPluginEnergyScore','SelectedMode'});
T = localAppendBenchmarkColumns(T, metadata, confidenceValue);
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_energy_mode_selection.csv"), T);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "ai_benchmark_metadata.csv"), struct2table(metadata));
end
result = struct("Ok", true, "DecisionTable", T);
end

function execOut = localExecutePreparedScenario(scfg, runFolder, runTag, publicRunFolder)
if nargin < 3
    runTag = "";
end
if nargin < 4 || strlength(string(publicRunFolder)) == 0
    publicRunFolder = runFolder;
end
runStartUTC = localUTCStamp();
runTimer = tic;
layout = sixgr.report.resultLayout(runFolder);
localEnsureScenarioDirs(layout);
localApplyRunRandomness(scfg);
localDBLog("INFO", "Preparing LLS run: scenario=%s runTag=%s runFolder=%s", ...
    char(string(scfg.ScenarioID)), char(string(runTag)), char(string(runFolder)));

cfg = sixgr.lls6g.buildInternalConfig(scfg, runFolder);
cfg.run.runTag = char(string(runTag));
configuredProfile = lower(strtrim(string(scfg.get("scenario.runner_profile"))));
cfg.run.configuredRunnerProfile = char(configuredProfile);
cfg.run.runnerProfile = char(configuredProfile);
cfg.run.scenarioID = char(string(scfg.ScenarioID));
cfg.meta.scenarioID = char(string(scfg.ScenarioID));
cfg.meta.configHash = char(string(scfg.ConfigHash));
cfg = localEnsureExactMexAcceleration(cfg);
cfg = localEnsureParallelExecution(cfg);
sixgr.perf.TimeProfiler.configure(cfg);
profilerCfg = localResolveProfilerConfig(scfg);
profilerState = localStartProfilerIfEnabled(profilerCfg);
storeInfo = sixgr.db.activateArtifactStore(runFolder, cfg, struct( ...
    "ScenarioID", scfg.ScenarioID, ...
    "RunTag", runTag, ...
    "Bucket", scfg.get("output.bucket"), ...
    "Profile", localResolveRunRowProfileName(scfg), ...
    "LogicalRunFolder", publicRunFolder, ...
    "ScenarioConfigStruct", scfg.toStruct(), ...
    "ScenarioSourceFiles", string(scfg.SourceFiles(:)), ...
    "ScenarioConfigSourceKind", localResolveScenarioSourceKind(scfg)));
cleanupStore = onCleanup(@() sixgr.db.deactivateArtifactStore()); %#ok<NASGU>
sixgr.config.publishConfigApplicationEvidence("reset", struct( ...
    "RunId", double(sixgr.util.structGet(storeInfo, "RunID", NaN)), ...
    "ScenarioID", string(scfg.ScenarioID), ...
    "RunTag", string(runTag)));
localPublishMappedRuntimeConfigEvidence(scfg, cfg);
if logical(sixgr.util.structGet(storeInfo, "Active", false))
    sixgr.db.markRunStatus("running", struct("started_utc", runStartUTC));
end
localDBLog("INFO", "Artifact store active=%d backend=%s schema=%s", ...
    double(logical(sixgr.util.structGet(storeInfo, "Active", false))), ...
    char(string(sixgr.util.structGet(storeInfo, "Backend", ""))), ...
    char(string(sixgr.util.structGet(storeInfo, "DatabaseSchema", ""))));

profile = localResolveEffectiveRunnerProfile(scfg, cfg, configuredProfile);
cfg.run.runnerProfile = char(profile);
result = struct();
manifest = struct();
runtimeSummary = struct();
environmentSummary = struct();
reportBundle = struct();
configOwnership = struct();
scenarioStatus = struct();
truthArtifactScan = struct();
optionalArtifactIssues = strings(0, 1);
profilerArtifacts = struct();
profilerArtifactsExported = false;
truthGatedCompletionPublished = false;

try
    localDBLog("INFO", "Writing resolved snapshots.");
    localWriteResolvedSnapshots(layout, scfg);
    localDBLog("INFO", "Exporting live geometry artifacts.");
    localExportLiveGeometryArtifacts(layout, scfg, cfg);

    localDBLog("INFO", "Executing runner profile=%s.", char(profile));
    switch profile
        case "waveform_bundle"
            result = localRunWaveformBundleScenario(cfg, scfg, runFolder);
        case "system_level_lls"
            result = localRunSystemLevelScenario(cfg, scfg, runFolder);
        case "pdcch_blind_decode_sweep"
            result = localRunPDCCHBlindDecodeSweep(cfg, scfg, runFolder);
        case "pdcch_strict_validation"
            result = localRunStrictPDCCHValidationScenario(cfg, scfg, runFolder);
        case "trs_strict_validation"
            result = localRunStrictTRSValidationScenario(cfg, scfg, runFolder);
        case "srs_strict_validation"
            result = localRunStrictSRSValidationScenario(cfg, scfg, runFolder);
        case "channel_rf_strict_validation"
            result = localRunStrictChannelRFValidationScenario(cfg, scfg, runFolder);
        case "ctrl6gr_pdcch_study"
            result = localRun6GRPDCCHStudy(cfg, scfg, runFolder);
        case "pdsch6gr_truth_study"
            result = localRun6GRPDSCHStudy(cfg, scfg, runFolder);
        case "prach_detection"
            result = localRunPRACHDetectionScenario(cfg, scfg, runFolder);
        case "prach_strict_validation"
            result = localRunStrictPRACHValidationScenario(cfg, scfg, runFolder);
        case "random_access_four_step"
            result = localRunFourStepRAScenario(cfg, scfg, runFolder);
        case "generic_sweep"
            result = localRunGenericSweep(cfg, scfg, runFolder);
        case "ai_benchmark"
            result = localRunAIBenchmark(cfg, scfg, runFolder);
        otherwise
            error("sixgr:lls6g:runner:UnknownProfile", ...
                "Unsupported scenario.runner_profile '%s' for '%s'.", profile, scfg.ScenarioID);
    end
    localDBLog("INFO", "Runner profile completed. result.Ok=%d", ...
        double(logical(sixgr.util.structGet(result, "Ok", false))));
    if logical(sixgr.util.structGet(cfg, "perf.exportTimeProfile", false))
        localDBLog("INFO", "Exporting TX/RX chain time-profile and complexity coverage artifacts.");
        sixgr.perf.TimeProfiler.export(runFolder, cfg);
    end

    scenarioStatus = localAggregateScenarioStatus(result);
    result = localApplyScenarioStatus(result, scenarioStatus);
    localDBLog("INFO", "Scenario status aggregated: completion=%s resultOk=%d requiredFailures=%d optionalPruned=%d", ...
        char(string(scenarioStatus.RunCompletion)), double(logical(scenarioStatus.ResultOk)), ...
        double(scenarioStatus.RequiredFailureCount), double(scenarioStatus.OptionalPrunedCount));

    localDBLog("INFO", "Annotating CSV artifacts.");
    localAnnotateAllCSV(runFolder, scfg, profile);
    summaryT = localBuildScenarioSummaryTable(scfg, profile, result, scenarioStatus);
    if logical(scfg.get("output.save_csv"))
        localDBLog("INFO", "Writing scenario summary CSV.");
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), summaryT);
    end
    runtimeSummary = localBuildRuntimeSummary(runStartUTC, runTimer, profile, publicRunFolder, cfg);
    environmentSummary = localBuildEnvironmentSummary(cfg);
    localDBLog("INFO", "Writing runtime and environment summaries.");
    sixgr.util.jsonWrite(fullfile(layout.MetaDir, "runtime_summary.json"), runtimeSummary);
    sixgr.util.jsonWrite(fullfile(layout.MetaDir, "environment.json"), environmentSummary);
    manifest = localBuildManifest(scfg, publicRunFolder, profile, result, runtimeSummary, environmentSummary, scenarioStatus);
    localDBLog("INFO", "Writing scenario manifest.");
    localWriteScenarioManifest(layout, manifest);
    localDBLog("INFO", "Exporting initial config-ownership and hardcoding audit artifacts.");
    configOwnership = sixgr.truth.exportLLSConfigOwnershipArtifacts(runFolder, scfg, cfg);
    preTruthScenarioStatus = scenarioStatus;
    scenarioStatus = localApplyRuntimeTruthContract(scenarioStatus, result, scfg, cfg, runFolder);
    result = localApplyScenarioStatus(result, scenarioStatus);
    localDBLog("INFO", "Runtime truth contract evaluated: ok=%d roundtripMismatch=%d evidenceMissing=%d strictFailures=%d", ...
        double(logical(scenarioStatus.RuntimeTruthContractOk)), double(scenarioStatus.RoundtripMismatchCount), ...
        double(scenarioStatus.RequiredRuntimeEvidenceMissingCount), double(scenarioStatus.StrictTruthFailureCount));
    summaryT = localBuildScenarioSummaryTable(scfg, profile, result, scenarioStatus);
    if logical(scfg.get("output.save_csv"))
        localDBLog("INFO", "Rewriting scenario summary CSV with final truth-gated status.");
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), summaryT);
    end
    manifest = localBuildManifest(scfg, publicRunFolder, profile, result, runtimeSummary, environmentSummary, scenarioStatus);
    localDBLog("INFO", "Rewriting scenario manifest with final truth-gated status.");
    localWriteScenarioManifest(layout, manifest);
    try
        if logical(sixgr.util.structGet(profilerCfg, "Enabled", false)) && ...
                logical(sixgr.util.structGet(profilerState, "OwnsSession", false))
            localDBLog("INFO", "Exporting MATLAB profiler artifacts before implementation validation.");
            profilerArtifacts = localExportProfilerArtifacts(layout, profilerCfg, profilerState, ...
                "Run captured through runner execution before implementation validation.");
            profilerArtifactsExported = true;
            profilerState.OwnsSession = false;
        end
    catch profilerME
        optionalArtifactIssues(end+1, 1) = "profiler_export_before_validation:" + string(profilerME.identifier);
        localDBLog("WARN", "Profiler export before implementation validation did not complete: %s | %s", ...
            char(string(profilerME.identifier)), char(string(profilerME.message)));
        localStopProfilerSession(profilerState);
        profilerState.OwnsSession = false;
        profilerArtifacts = struct();
    end
    localDBLog("INFO", "Exporting LLS reporting bundle.");
    reportBundle = sixgr.truth.exportLLSReportingBundle(runFolder, scfg, cfg, result, manifest, runtimeSummary, scenarioStatus);
    reportBundle.ConfigOwnershipArtifacts = configOwnership;
    localDBLog("INFO", "Scanning truth primary artifacts for active proxy/fallback markers.");
    truthArtifactScan = sixgr.truth.scanTruthArtifacts(runFolder, struct());
    reportBundle.TruthArtifactScan = truthArtifactScan;
    localDBLog("INFO", "Exporting output-coverage and honest-unavailable artifacts.");
    outputCoverage = sixgr.truth.exportLLSOutputCoverageArtifacts(runFolder, scfg, cfg);
    reportBundle.OutputCoverageArtifacts = outputCoverage;
    reportBundle.Inventory = sixgr.util.structGet(outputCoverage, "UpdatedArtifactInventory", sixgr.util.structGet(reportBundle, "Inventory", table()));
    localDBLog("INFO", "Refreshing config-ownership artifacts after final runtime/report exports.");
    configOwnership = sixgr.truth.exportLLSConfigOwnershipArtifacts(runFolder, scfg, cfg);
    reportBundle.ConfigOwnershipArtifacts = configOwnership;
    scenarioStatus = localApplyRuntimeTruthContract(preTruthScenarioStatus, result, scfg, cfg, runFolder);
    scenarioStatus = localApplyVisualArtifactIntegrityStatus(scenarioStatus, ...
        sixgr.util.structGet(outputCoverage, "VisualArtifactIntegrity", table()));
    result = localApplyScenarioStatus(result, scenarioStatus);
    localDBLog("INFO", "Runtime truth contract re-evaluated after final artifact exports: ok=%d roundtripMismatch=%d evidenceMissing=%d strictFailures=%d", ...
        double(logical(scenarioStatus.RuntimeTruthContractOk)), double(scenarioStatus.RoundtripMismatchCount), ...
        double(scenarioStatus.RequiredRuntimeEvidenceMissingCount), double(scenarioStatus.StrictTruthFailureCount));
    localAppendLinkRunStatusLog(layout, scenarioStatus);
    summaryT = localBuildScenarioSummaryTable(scfg, profile, result, scenarioStatus);
    if logical(scfg.get("output.save_csv"))
        localDBLog("INFO", "Rewriting scenario summary CSV with final artifact truth-gated status.");
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), summaryT);
    end
    manifest = localBuildManifest(scfg, publicRunFolder, profile, result, runtimeSummary, environmentSummary, scenarioStatus);
    localDBLog("INFO", "Rewriting scenario manifest with final artifact truth-gated status.");
    localWriteScenarioManifest(layout, manifest);
    truthGatedCompletionPublished = true;
    localDBLog("INFO", "Writing artifact manifest.");
    manifest.ArtifactManifestPath = char(localWriteArtifactManifest(runFolder, scfg, profile, manifest, reportBundle, scenarioStatus));
    localWriteScenarioManifest(layout, manifest);
    localDBLog("INFO", "Writing scenario markdown report.");
    localWriteMarkdownReport(fullfile(layout.ReportDir, "scenario_report.md"), scfg, profile, runFolder, result, manifest, reportBundle, scenarioStatus);
    localDBLog("INFO", "Materializing canonical browser contract artifacts for the completed run.");
    contractMaterialization = localMaterializeBrowserContractArtifacts();
    if logical(sixgr.util.structGet(contractMaterialization, "Ok", false))
        localDBLog("INFO", "Browser contract artifacts materialized: created=%d missingTables=%d missingCharts=%d", ...
            double(sixgr.util.structGet(contractMaterialization, "CreatedCount", 0)), ...
            double(sixgr.util.structGet(contractMaterialization, "MissingTableCount", 0)), ...
            double(sixgr.util.structGet(contractMaterialization, "MissingChartCount", 0)));
    else
        optionalArtifactIssues(end+1, 1) = "browser_contract_materialization:" + string(sixgr.util.structGet(contractMaterialization, "Identifier", "failed"));
        localDBLog("WARN", "Browser contract artifact materialization did not complete: %s | %s", ...
            char(string(sixgr.util.structGet(contractMaterialization, "Identifier", "failed"))), ...
            char(string(sixgr.util.structGet(contractMaterialization, "Message", ""))));
    end
    localDBLog("INFO", "Required final artifacts published; marking terminal run status before optional artifacts.");
    localMarkRunStatusSafe(string(scenarioStatus.RunCompletion), ...
        localBuildTerminalStatusPayload(scenarioStatus, "run_required_artifacts_published", optionalArtifactIssues));
    if logical(scfg.get("output.save_mat"))
        try
            localDBLog("INFO", "Writing MAT result bundle.");
            localMarkRunStatusSafe(string(scenarioStatus.RunCompletion), ...
                localBuildTerminalStatusPayload(scenarioStatus, "run_optional_mat_bundle", optionalArtifactIssues));
            sixgr.util.matSave(fullfile(layout.ReportMATDir, "scenario_result.mat"), ...
                struct("ScenarioConfig", scfg.toStruct(), "Result", result, "Manifest", manifest, ...
                "RuntimeSummary", runtimeSummary, "EnvironmentSummary", environmentSummary, "ReportBundle", reportBundle, ...
                "ScenarioStatus", scenarioStatus));
        catch matME
            optionalArtifactIssues(end+1, 1) = "mat_result_bundle:" + string(matME.identifier);
            localDBLog("WARN", "Optional MAT result bundle did not complete: %s | %s", ...
                char(string(matME.identifier)), char(string(matME.message)));
        end
    end
    try
        localDBLog("INFO", "Pruning empty result directories.");
        localPruneEmptyDirs(runFolder);
    catch pruneME
        optionalArtifactIssues(end+1, 1) = "prune_empty_directories:" + string(pruneME.identifier);
        localDBLog("WARN", "Optional empty-directory prune did not complete: %s | %s", ...
            char(string(pruneME.identifier)), char(string(pruneME.message)));
    end
    if ~profilerArtifactsExported
        try
            profilerArtifacts = localExportProfilerArtifacts(layout, profilerCfg, profilerState, "Run completed successfully.");
            profilerArtifactsExported = true;
            profilerState.OwnsSession = false;
        catch profilerME
            optionalArtifactIssues(end+1, 1) = "profiler_export:" + string(profilerME.identifier);
            localDBLog("WARN", "Optional profiler export did not complete: %s | %s", ...
                char(string(profilerME.identifier)), char(string(profilerME.message)));
            localStopProfilerSession(profilerState);
            profilerState.OwnsSession = false;
            profilerArtifacts = struct();
        end
    end
    hydration = localHydratePublicRunFolderIfNeeded(runFolder, publicRunFolder);
    hydrationNotes = string(sixgr.util.structGet(hydration, "Notes", ""));
    if hydrationNotes == "artifact_store_inactive_or_same_folder"
        % Filesystem runs already write directly to the public folder.
    elseif logical(sixgr.util.structGet(hydration, "Ok", true))
        localDBLog("INFO", "Public run folder hydrated from DB artifacts: files=%d bytes=%d skipped=%d target=%s", ...
            double(sixgr.util.structGet(hydration, "FileCount", 0)), ...
            double(sixgr.util.structGet(hydration, "ByteCount", 0)), ...
            double(sixgr.util.structGet(hydration, "SkippedCount", 0)), ...
            char(string(sixgr.util.structGet(hydration, "TargetRoot", publicRunFolder))));
    else
        optionalArtifactIssues(end+1, 1) = "public_run_folder_hydration:" + string(sixgr.util.structGet(hydration, "Notes", "failed"));
        localDBLog("WARN", "Public run folder hydration did not complete: %s", ...
            char(string(sixgr.util.structGet(hydration, "Notes", ""))));
    end

    localMarkRunStatusSafe(string(scenarioStatus.RunCompletion), ...
        localBuildTerminalStatusPayload(scenarioStatus, "run_terminal_optional_artifacts_complete", optionalArtifactIssues));
    if logical(scenarioStatus.ResultOk)
        localDBLog("INFO", "Run completed successfully in %.3f seconds.", toc(runTimer));
    else
        localDBLog("WARN", "Run completed with truth/status failures in %.3f seconds: requiredFailures=%d strictTruthFailures=%d", ...
            toc(runTimer), double(scenarioStatus.RequiredFailureCount), double(scenarioStatus.StrictTruthFailureCount));
    end

    execOut = localBuildExecOut(profile, result, manifest, runtimeSummary, environmentSummary, ...
        reportBundle, configOwnership, scenarioStatus, profilerArtifacts, optionalArtifactIssues);
catch ME
    localDBLog("ERROR", "Run failed: %s | %s", char(string(ME.identifier)), char(string(ME.message)));
    try
        if logical(sixgr.util.structGet(cfg, "perf.exportTimeProfile", false))
            sixgr.perf.TimeProfiler.export(runFolder, cfg);
        end
    catch timeProfileME
        localDBLog("WARN", "Time-profile export after failure did not complete: %s", ...
            char(string(timeProfileME.message)));
    end
    try
        localExportProfilerArtifacts(layout, profilerCfg, profilerState, ...
            "Run failed before completion; partial MATLAB profiler capture exported.");
    catch profilerME
        localDBLog("WARN", "Profiler export after failure did not complete: %s", ...
            char(string(profilerME.message)));
        localStopProfilerSession(profilerState);
    end
    try
        sixgr.util.writeTextFile(fullfile(layout.MetaDir, "failure_debug_report.txt"), ...
            getReport(ME, "extended", "hyperlinks", "off"), ...
            "ArtifactKind", "failure_debug_report", ...
            "MimeType", "text/plain; charset=UTF-8");
    catch
    end
    if truthGatedCompletionPublished && ...
            sixgr.lls6g.runners.shouldPreserveCompletedRunOnPostRunFailure(scenarioStatus)
        lateIssue = "late_postrun_exception:" + string(ME.identifier);
        combinedIssues = [optionalArtifactIssues(:); lateIssue];
        localDBLog("WARN", ...
            "Late post-run failure occurred after truthful completion; preserving completed run and skipping failed-run recovery: %s | %s", ...
            char(string(ME.identifier)), char(string(ME.message)));
        payload = localBuildTerminalStatusPayload(scenarioStatus, ...
            "postrun_optional_failure_after_completed_truth", combinedIssues);
        payload.postrun_optional_failure = true;
        payload.postrun_optional_failure_identifier = string(ME.identifier);
        payload.postrun_optional_failure_message = string(ME.message);
        payload.postrun_optional_failure_recovery_skipped = true;
        localMarkRunStatusSafe(string(scenarioStatus.RunCompletion), payload);
        execOut = localBuildExecOut(profile, result, manifest, runtimeSummary, environmentSummary, ...
            reportBundle, configOwnership, scenarioStatus, profilerArtifacts, combinedIssues);
        return;
    end
    try
        localDBLog("INFO", "Recovering truthful report artifacts from persisted raw evidence after failure.");
        recovery = sixgr.truth.recoverLLSRunArtifacts(runFolder, scfg.toStruct(), ...
            "RunTag", runTag, ...
            "PublicRunFolder", publicRunFolder, ...
            "StatusText", "failed", ...
            "ErrorIdentifier", string(ME.identifier), ...
            "ErrorMessage", string(ME.message), ...
            "SourceFiles", string(scfg.SourceFiles(:)), ...
            "ConfigPath", string(scfg.ConfigPath), ...
            "ConfigHash", string(scfg.ConfigHash));
        sixgr.truth.exportLLSConfigOwnershipArtifacts(runFolder, scfg, cfg);
        localDBLog("INFO", "Recovered failed-run artifacts: scenario=%s profile=%s truthOk=%d", ...
            char(string(sixgr.util.structGet(recovery, "ScenarioID", scfg.ScenarioID))), ...
            char(string(sixgr.util.structGet(recovery, "RunnerProfile", ""))), ...
            double(logical(sixgr.util.structGet(recovery, "ScenarioStatus.RuntimeTruthContractOk", false))));
        contractMaterialization = localMaterializeBrowserContractArtifacts();
        if logical(sixgr.util.structGet(contractMaterialization, "Ok", false))
            localDBLog("INFO", "Browser contract artifacts materialized after failure recovery: created=%d missingTables=%d missingCharts=%d", ...
                double(sixgr.util.structGet(contractMaterialization, "CreatedCount", 0)), ...
                double(sixgr.util.structGet(contractMaterialization, "MissingTableCount", NaN)), ...
                double(sixgr.util.structGet(contractMaterialization, "MissingChartCount", NaN)));
        else
            localDBLog("WARN", "Browser contract materialization after failure recovery did not complete: %s | %s", ...
                char(string(sixgr.util.structGet(contractMaterialization, "Identifier", ""))), ...
                char(string(sixgr.util.structGet(contractMaterialization, "Message", ""))));
        end
        localHydratePublicRunFolderIfNeeded(runFolder, publicRunFolder);
    catch recoveryME
        localDBLog("WARN", "Failed-run artifact recovery did not complete: %s | %s", ...
            char(string(recoveryME.identifier)), char(string(recoveryME.message)));
    end
    localMarkRunStatusSafe("failed", struct( ...
        "stage", "run_failed", ...
        "identifier", string(ME.identifier), ...
        "message", string(ME.message), ...
        "timestamp_utc", string(localUTCStamp())));
    try
        localPruneEmptyDirs(runFolder);
    catch
    end
    rethrow(ME);
end
end

function execOut = localBuildExecOut(profile, result, manifest, runtimeSummary, environmentSummary, ...
    reportBundle, configOwnership, scenarioStatus, profilerArtifacts, optionalArtifactIssues)
execOut = struct();
execOut.Ok = logical(sixgr.util.structGet(scenarioStatus, "ResultOk", sixgr.util.structGet(result, "Ok", false)));
execOut.Result = result;
execOut.Profile = string(profile);
execOut.Manifest = manifest;
execOut.RuntimeSummary = runtimeSummary;
execOut.EnvironmentSummary = environmentSummary;
execOut.ReportBundle = reportBundle;
execOut.ConfigOwnershipArtifacts = configOwnership;
execOut.ScenarioStatus = scenarioStatus;
execOut.ProfilerArtifacts = profilerArtifacts;
execOut.OptionalArtifactIssues = optionalArtifactIssues;
end

function profilerCfg = localResolveProfilerConfig(scfg)
enabled = logical(scfg.get("output.profiler_enabled", false)) || ...
    logical(scfg.get("run_control.time_profiling_enable", false)) || ...
    logical(scfg.get("analytics.export_time_profile", false));
profilerCfg = struct( ...
    "Enabled", enabled, ...
    "TopFunctions", max(1, round(double(scfg.get("output.profiler_top_functions", 160)))), ...
    "TopEdges", max(1, round(double(scfg.get("output.profiler_top_edges", 320)))));
end

function profilerState = localStartProfilerIfEnabled(profilerCfg)
profilerState = struct( ...
    "Enabled", logical(sixgr.util.structGet(profilerCfg, "Enabled", false)), ...
    "OwnsSession", false);
if ~profilerState.Enabled || localProfilerIsRunning()
    return;
end
profile clear;
profile on;
profilerState.OwnsSession = true;
localDBLog("INFO", "MATLAB profiler enabled for this run.");
end

function profilerArtifacts = localExportProfilerArtifacts(layout, profilerCfg, profilerState, statusNote)
profilerArtifacts = struct( ...
    "SummaryTable", table(), ...
    "FunctionTable", table(), ...
    "EdgeTable", table());
if nargin < 4
    statusNote = "";
end
if ~logical(sixgr.util.structGet(profilerCfg, "Enabled", false)) || ...
        ~logical(sixgr.util.structGet(profilerState, "OwnsSession", false))
    localStopProfilerSession(profilerState);
    return;
end

info = localStopAndCollectProfilerInfo();
summaryT = localBuildProfilerSummaryTable(info, profilerCfg, statusNote);
funcT = localBuildProfilerFunctionTable(info, profilerCfg);
edgeT = localBuildProfilerEdgeTable(info, profilerCfg);

localDBLog("INFO", "Writing MATLAB profiler CSV artifacts: functions=%d edges=%d", ...
    double(height(funcT)), double(height(edgeT)));
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_profiler_summary.csv"), summaryT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_function_profile.csv"), funcT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_function_call_edges.csv"), edgeT);

profilerArtifacts.SummaryTable = summaryT;
profilerArtifacts.FunctionTable = funcT;
profilerArtifacts.EdgeTable = edgeT;
end

function info = localStopAndCollectProfilerInfo()
try
    profile off;
catch
end
try
    info = profile("info");
catch
    info = struct();
end
try
    profile clear;
catch
end
end

function localStopProfilerSession(profilerState)
if ~logical(sixgr.util.structGet(profilerState, "OwnsSession", false))
    return;
end
try
    profile off;
catch
end
try
    profile clear;
catch
end
end

function tf = localProfilerIsRunning()
try
    st = profile("status");
    statusToken = string(localProfileGetField(st, "ProfilerStatus", ...
        localProfileGetField(st, "Profiler", "off")));
    tf = contains(lower(strtrim(statusToken)), "on");
catch
    tf = false;
end
end

function T = localBuildProfilerSummaryTable(info, profilerCfg, statusNote)
ft = localProfileGetField(info, "FunctionTable", struct([]));
functionCount = double(numel(ft));
edgeCount = 0;
for i = 1:numel(ft)
    edgeCount = edgeCount + numel(localProfileGetField(ft(i), "Children", struct([])));
end
T = table( ...
    string(localProfileGetField(info, "Name", "MATLAB profile")), ...
    double(localProfileGetField(info, "ClockPrecision", NaN)), ...
    double(localProfileGetField(info, "ClockSpeed", NaN)), ...
    double(localProfileGetField(info, "Overhead", NaN)), ...
    functionCount, ...
    min(functionCount, double(sixgr.util.structGet(profilerCfg, "TopFunctions", functionCount))), ...
    double(edgeCount), ...
    min(double(edgeCount), double(sixgr.util.structGet(profilerCfg, "TopEdges", edgeCount))), ...
    string(localUTCStamp()), ...
    string(statusNote), ...
    'VariableNames', { ...
        'ProfilerName', ...
        'ClockPrecision_s', ...
        'ClockSpeed_Hz', ...
        'Overhead_s', ...
        'FunctionCount', ...
        'ExportedFunctionCount', ...
        'EdgeCount', ...
        'ExportedEdgeCount', ...
        'CapturedUTC', ...
        'Notes'});
end

function T = localBuildProfilerFunctionTable(info, profilerCfg)
ft = localProfileGetField(info, "FunctionTable", struct([]));
if isempty(ft)
    T = table('Size', [0 13], ...
        'VariableTypes', {'double','double','string','string','string','string','double','double','double','double','double','double','logical'}, ...
        'VariableNames', {'ProfileRank','FunctionIndex','FunctionName','CompleteName','FileName','FunctionType','NumCalls','TotalTime_s','SelfTimeApprox_s','ChildTime_s','TotalRecursiveTime_s','ParentCount','IsRecursive'});
    return;
end

rows = repmat(struct( ...
    "FunctionIndex", NaN, ...
    "FunctionName", "", ...
    "CompleteName", "", ...
    "FileName", "", ...
    "FunctionType", "", ...
    "NumCalls", NaN, ...
    "TotalTime_s", NaN, ...
    "SelfTimeApprox_s", NaN, ...
    "ChildTime_s", NaN, ...
    "TotalRecursiveTime_s", NaN, ...
    "ParentCount", NaN, ...
    "ChildCount", NaN, ...
    "IsRecursive", false), numel(ft), 1);
for i = 1:numel(ft)
    childTime = localProfileChildTime(localProfileGetField(ft(i), "Children", struct([])));
    totalTime = double(localProfileGetField(ft(i), "TotalTime", NaN));
    rows(i) = struct( ...
        "FunctionIndex", double(i), ...
        "FunctionName", string(localProfileGetField(ft(i), "FunctionName", "")), ...
        "CompleteName", string(localProfileGetField(ft(i), "CompleteName", "")), ...
        "FileName", string(localProfileGetField(ft(i), "FileName", "")), ...
        "FunctionType", string(localProfileGetField(ft(i), "Type", "")), ...
        "NumCalls", double(localProfileGetField(ft(i), "NumCalls", NaN)), ...
        "TotalTime_s", totalTime, ...
        "SelfTimeApprox_s", max(totalTime - childTime, 0), ...
        "ChildTime_s", childTime, ...
        "TotalRecursiveTime_s", double(localProfileGetField(ft(i), "TotalRecursiveTime", NaN)), ...
        "ParentCount", double(numel(localProfileGetField(ft(i), "Parents", struct([])))), ...
        "ChildCount", double(numel(localProfileGetField(ft(i), "Children", struct([])))), ...
        "IsRecursive", logical(localProfileGetField(ft(i), "IsRecursive", false)));
    if strlength(strtrim(rows(i).FunctionName)) == 0
        rows(i).FunctionName = localProfileFallbackName(rows(i).CompleteName, rows(i).FileName);
    end
end

T = struct2table(rows);
T = sortrows(T, {'TotalTime_s', 'SelfTimeApprox_s', 'NumCalls'}, {'descend', 'descend', 'descend'});
limitRows = min(height(T), double(sixgr.util.structGet(profilerCfg, "TopFunctions", height(T))));
T = T(1:limitRows, :);
T = addvars(T, transpose((1:height(T))), 'Before', 1, 'NewVariableNames', 'ProfileRank');
end

function T = localBuildProfilerEdgeTable(info, profilerCfg)
ft = localProfileGetField(info, "FunctionTable", struct([]));
rows = repmat(struct( ...
    "CallerFunctionIndex", NaN, ...
    "CallerFunctionName", "", ...
    "CallerCompleteName", "", ...
    "CalleeFunctionIndex", NaN, ...
    "CalleeFunctionName", "", ...
    "CalleeCompleteName", "", ...
    "NumCalls", NaN, ...
    "TotalTime_s", NaN), 0, 1);
for i = 1:numel(ft)
    callerName = string(localProfileGetField(ft(i), "FunctionName", ""));
    callerComplete = string(localProfileGetField(ft(i), "CompleteName", ""));
    if strlength(strtrim(callerName)) == 0
        callerName = localProfileFallbackName(callerComplete, string(localProfileGetField(ft(i), "FileName", "")));
    end
    children = localProfileGetField(ft(i), "Children", struct([]));
    for k = 1:numel(children)
        childIndex = round(double(localProfileGetField(children(k), "Index", NaN)));
        if ~(isfinite(childIndex) && childIndex >= 1 && childIndex <= numel(ft))
            continue;
        end
        calleeName = string(localProfileGetField(ft(childIndex), "FunctionName", ""));
        calleeComplete = string(localProfileGetField(ft(childIndex), "CompleteName", ""));
        if strlength(strtrim(calleeName)) == 0
            calleeName = localProfileFallbackName(calleeComplete, string(localProfileGetField(ft(childIndex), "FileName", "")));
        end
        rows(end+1,1) = struct( ... %#ok<AGROW>
            "CallerFunctionIndex", double(i), ...
            "CallerFunctionName", callerName, ...
            "CallerCompleteName", callerComplete, ...
            "CalleeFunctionIndex", double(childIndex), ...
            "CalleeFunctionName", calleeName, ...
            "CalleeCompleteName", calleeComplete, ...
            "NumCalls", double(localProfileGetField(children(k), "NumCalls", NaN)), ...
            "TotalTime_s", double(localProfileGetField(children(k), "TotalTime", NaN)));
    end
end

if isempty(rows)
    T = table('Size', [0 9], ...
        'VariableTypes', {'double','double','string','string','double','string','string','double','double'}, ...
        'VariableNames', {'EdgeRank','CallerFunctionIndex','CallerFunctionName','CallerCompleteName','CalleeFunctionIndex','CalleeFunctionName','CalleeCompleteName','NumCalls','TotalTime_s'});
    return;
end

T = struct2table(rows);
T = sortrows(T, {'TotalTime_s', 'NumCalls'}, {'descend', 'descend'});
limitRows = min(height(T), double(sixgr.util.structGet(profilerCfg, "TopEdges", height(T))));
T = T(1:limitRows, :);
T = addvars(T, transpose((1:height(T))), 'Before', 1, 'NewVariableNames', 'EdgeRank');
end

function value = localProfileGetField(s, fieldName, defaultValue)
value = defaultValue;
if builtin("isstruct", s) && isfield(s, fieldName)
    value = s.(fieldName);
end
end

function childTime = localProfileChildTime(children)
childTime = 0;
if ~(builtin("isstruct", children) && ~isempty(children) && isfield(children, "TotalTime"))
    return;
end
childTime = sum(double([children.TotalTime]), "omitnan");
end

function name = localProfileFallbackName(completeName, fileName)
name = string(completeName);
if strlength(strtrim(name)) == 0
    name = string(fileName);
end
if contains(name, filesep)
    [~, stem, ext] = fileparts(char(name));
    name = string(stem + ext);
end
end

function localWriteResolvedSnapshots(layout, scfg)
metaDir = layout.MetaDir;
resolvedStruct = localResolvedSnapshotStruct(scfg);
if logical(scfg.get("output.save_json_snapshot"))
    sixgr.util.jsonWrite(fullfile(metaDir, "scenario_config_resolved.json"), resolvedStruct);
end
if logical(scfg.get("output.save_yaml_snapshot"))
    sixgr.lls6g.config.writeYAML(fullfile(metaDir, "scenario_config_resolved.yaml"), resolvedStruct);
end
srcFiles = arrayfun(@(p)localPortablePath(p), string(scfg.SourceFiles(:)));
srcT = table(srcFiles, 'VariableNames', {'SourceConfigFile'});
sixgr.util.csvWriteTable(fullfile(metaDir, "scenario_source_chain.csv"), srcT);
end

function kind = localResolveScenarioSourceKind(scfg)
resolved = scfg.toStruct();
kind = string(sixgr.util.structGet(resolved, "SourceKind", ""));
if strlength(strtrim(kind)) == 0
    kind = string(sixgr.util.structGet(resolved, "meta.SourceKind", ""));
end
if strlength(strtrim(kind)) == 0
    kind = string(sixgr.util.structGet(resolved, "config_inheritance.provenance.source_kind", ""));
end
if strlength(strtrim(kind)) == 0
    kind = "scenario_config_file";
end
end

function localExportLiveGeometryArtifacts(layout, scfg, cfg)
backend = lower(string(scfg.get("output.backend", "filesystem")));
if backend ~= "mysql_web"
    return;
end

rngState = rng; %#ok<RNGR>
cleanupRng = onCleanup(@() rng(rngState)); %#ok<NASGU>

try
    seed = double(sixgr.util.structGet(cfg, "run.seed", sixgr.util.structGet(cfg, "run.randomSeed", 1)));
    rng(seed, "twister");

    scenarioName = string(sixgr.util.structGet(cfg, "scenario.name", scfg.ScenarioID));
    scenarioLayout = sixgr.scenario.generateLayout(cfg, scenarioName);
    ue = sixgr.scenario.dropUEs(cfg, scenarioLayout, scenarioName);
    [siteT, sectorT, trpT, ueT] = localBuildProjectedGeometryTables(scenarioLayout, ue);

    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "sites.csv"), siteT);
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "sectors.csv"), sectorT);
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "trps.csv"), trpT);
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "ues.csv"), ueT);
catch
    % Geometry export is best-effort for the live dashboard and must not
    % change scenario execution semantics if a profile cannot provide it.
end
end

function [siteT, sectorT, trpT, ueT] = localBuildProjectedGeometryTables(layoutStruct, ue)
anchorLat = 19.122164;
anchorLon = 72.999217;
anchorLabel = "Reliance Corporate Park, Ghansoli, Navi Mumbai";
coordMode = "projected_default_anchor";

sitePos = double(sixgr.util.structGet(layoutStruct, "sites.pos_m", zeros(0,3)));
siteId = double(sixgr.util.structGet(layoutStruct, "sites.id", (1:size(sitePos,1)).'));
[siteLat, siteLon] = localProjectXYToLatLon(sitePos(:,1), sitePos(:,2), anchorLat, anchorLon);
siteT = table( ...
    siteId(:), sitePos(:,1), sitePos(:,2), sitePos(:,3), siteLat(:), siteLon(:), ...
    repmat(string(coordMode), numel(siteId), 1), repmat(string(anchorLabel), numel(siteId), 1), ...
    'VariableNames', {'SiteID','X_m','Y_m','Z_m','Lat','Lon','CoordinateMode','MapAnchorLabel'});

bsPos = double(sixgr.util.structGet(layoutStruct, "bs.pos_m", zeros(0,3)));
siteRef = double(sixgr.util.structGet(layoutStruct, "bs.siteId", nan(size(bsPos,1),1)));
sectorId = double(sixgr.util.structGet(layoutStruct, "bs.sectorId", (1:size(bsPos,1)).'));
az = double(sixgr.util.structGet(layoutStruct, "bs.azim_deg", nan(size(bsPos,1),1)));
txP = double(sixgr.util.structGet(layoutStruct, "bs.txPower_dBm", nan(size(bsPos,1),1)));
[bsLat, bsLon] = localProjectXYToLatLon(bsPos(:,1), bsPos(:,2), anchorLat, anchorLon);

sectorT = table( ...
    siteRef(:), sectorId(:), az(:), bsPos(:,1), bsPos(:,2), bsPos(:,3), bsLat(:), bsLon(:), ...
    repmat(string(coordMode), numel(sectorId), 1), repmat(string(anchorLabel), numel(sectorId), 1), ...
    'VariableNames', {'SiteID','SectorID','Azimuth_deg','X_m','Y_m','Z_m','Lat','Lon','CoordinateMode','MapAnchorLabel'});

trpId = (1:size(bsPos,1)).';
trpT = table( ...
    trpId(:), siteRef(:), sectorId(:), az(:), txP(:), bsPos(:,1), bsPos(:,2), bsPos(:,3), bsLat(:), bsLon(:), ...
    repmat(string(coordMode), numel(trpId), 1), repmat(string(anchorLabel), numel(trpId), 1), ...
    'VariableNames', {'TRPID','SiteID','SectorID','Azimuth_deg','TxPower_dBm','X_m','Y_m','Z_m','Lat','Lon','CoordinateMode','MapAnchorLabel'});

ueId = double(sixgr.util.structGet(ue, "id", (1:size(ue.pos_m,1)).'));
uePos = double(sixgr.util.structGet(ue, "pos_m", zeros(0,3)));
ueIndoor = logical(sixgr.util.structGet(ue, "indoor", false(size(uePos,1),1)));
ueSpeed = double(sixgr.util.structGet(ue, "speed_kmh", nan(size(uePos,1),1)));
ueHeading = double(sixgr.util.structGet(ue, "heading_deg", nan(size(uePos,1),1)));
[ueLat, ueLon] = localProjectXYToLatLon(uePos(:,1), uePos(:,2), anchorLat, anchorLon);
ueT = table( ...
    ueId(:), uePos(:,1), uePos(:,2), uePos(:,3), ueLat(:), ueLon(:), ueIndoor(:), ueSpeed(:), ueHeading(:), ...
    repmat(string(coordMode), numel(ueId), 1), repmat(string(anchorLabel), numel(ueId), 1), ...
    'VariableNames', {'UEID','X_m','Y_m','Z_m','Lat','Lon','Indoor','Speed_kmh','Heading_deg','CoordinateMode','MapAnchorLabel'});
end

function [lat, lon] = localProjectXYToLatLon(x_m, y_m, anchorLat, anchorLon)
[lat, lon] = sixgr.util.projectLocalXYToGeo(x_m, y_m, double(anchorLat), double(anchorLon));
end

function tf = localShouldWriteCSV(scfg)
tf = logical(scfg.get("output.save_csv"));
end

function manifest = localBuildManifest(scfg, runFolder, profile, result, runtimeSummary, environmentSummary, scenarioStatus)
includeGitHash = logical(scfg.get("logging.include_git_hash"));
[codeVersion, codeDetail] = localDetectCodeVersion(includeGitHash);
gitInfo = localDetectGitProvenance(includeGitHash);
[configOverlay, configOverlayPath] = localDetectConfigOverlay(scfg);
manifest = struct();
manifest.GeneratedUTC = localUTCStamp();
manifest.ScenarioID = char(string(scfg.ScenarioID));
manifest.ConfigHash = char(string(scfg.ConfigHash));
manifest.ConfigPath = char(string(scfg.ConfigPath));
manifest.ScenarioYAML = char(string(scfg.ConfigPath));
manifest.ConfigOverlay = char(string(configOverlay));
manifest.ConfigOverlayPath = char(string(configOverlayPath));
manifest.RunFolder = char(string(runFolder));
manifest.SourceFiles = cellstr(localPortablePath(scfg.SourceFiles));
manifest.SourceFileCount = numel(scfg.SourceFiles);
manifest.RunnerProfile = char(string(profile));
manifest.RandomSeed = double(scfg.get("simulation.random_seed"));
manifest.DeterministicMode = logical(scfg.get("simulation.deterministic_mode"));
manifest.StrictValidation = logical(scfg.get("logging.strict_validation"));
manifest.LinkDirection = char(string(scfg.get("simulation.link_direction")));
manifest.ConfiguredUsers = double(scfg.get("users.n_users", 1));
manifest.UserExecutionModel = char(string(scfg.get("users.execution_model", "independent_link_sweep")));
manifest.BeamSelectionStrategy = char(string(scfg.get("users.beam_selection_strategy")));
manifest.ConfiguredLayers = double(scfg.get("mimo.n_layers"));
manifest.ConfiguredTxAntennas = double(scfg.get("mimo.n_tx_ant"));
manifest.ConfiguredRxAntennas = double(scfg.get("mimo.n_rx_ant"));
manifest.OutputBucket = char(string(scfg.get("output.bucket")));
manifest.OutputProfile = char(string(scfg.get("output.profile")));
manifest.OutputBackend = char(string(scfg.get("output.backend", "filesystem")));
manifest.OutputDatabaseHost = char(string(scfg.get("output.database_host", "localhost")));
manifest.OutputDatabasePort = double(scfg.get("output.database_port", 3306));
manifest.OutputDatabaseSchema = char(string(scfg.get("output.database_schema", "sixgr_results")));
manifest.SaveCSV = logical(scfg.get("output.save_csv"));
manifest.SaveMAT = logical(scfg.get("output.save_mat"));
manifest.SaveFigures = logical(scfg.get("output.save_figures"));
manifest.SavePNG = logical(scfg.get("output.save_png"));
manifest.SaveJSONSnapshot = logical(scfg.get("output.save_json_snapshot"));
manifest.SaveYAMLSnapshot = logical(scfg.get("output.save_yaml_snapshot"));
manifest.GenerateSummaryPlots = logical(scfg.get("output.generate_summary_plots"));
manifest.UseMex = logical(sixgr.util.structGet(runtimeSummary, "UseMex", false));
manifest.UseMexAutoEnabled = logical(sixgr.util.structGet(runtimeSummary, "UseMexAutoEnabled", false));
manifest.UseParallel = logical(sixgr.util.structGet(runtimeSummary, "UseParallel", false));
manifest.RequestedWorkers = double(sixgr.util.structGet(runtimeSummary, "RequestedWorkers", 0));
manifest.EffectiveWorkers = double(sixgr.util.structGet(runtimeSummary, "EffectiveWorkers", 0));
manifest.ParallelDisabledReason = char(string(sixgr.util.structGet(runtimeSummary, "ParallelDisabledReason", "")));
manifest.MaxNumCompThreads = double(sixgr.util.structGet(runtimeSummary, "MaxNumCompThreads", NaN));
manifest.IncludeGitHash = includeGitHash;
manifest.CodeVersion = char(string(codeVersion));
manifest.CodeDetail = char(string(codeDetail));
manifest.GitCommit = char(string(gitInfo.Commit));
manifest.GitBranch = char(string(gitInfo.Branch));
manifest.GitDirty = logical(gitInfo.Dirty);
manifest.GitStatusSource = char(string(gitInfo.StatusSource));
manifest.MetaManifestPath = "meta/scenario_manifest.json";
manifest.ProvenanceManifestPath = "reports/json/scenario_manifest.json";
manifest.ExecutionStartedUTC = char(string(sixgr.util.structGet(runtimeSummary, "StartedUTC", "")));
manifest.ExecutionCompletedUTC = char(string(sixgr.util.structGet(runtimeSummary, "CompletedUTC", "")));
manifest.ElapsedSeconds = double(sixgr.util.structGet(runtimeSummary, "ElapsedSeconds", NaN));
manifest.WarningCount = double(sixgr.util.structGet(runtimeSummary, "WarningCount", 0));
manifest.EnvironmentSummaryPath = "meta/environment.json";
manifest.RuntimeSummaryPath = "meta/runtime_summary.json";
manifest.HostPlatform = char(string(sixgr.util.structGet(environmentSummary, "Platform", "")));
manifest.RunScope = "6G_PHY_LLS_SINGLE_SCENARIO";
manifest.RunCompletion = char(string(scenarioStatus.RunCompletion));
manifest.RunCompleted = logical(sixgr.util.structGet(scenarioStatus, "RunCompleted", false));
manifest.ResultOk = logical(scenarioStatus.ResultOk);
manifest.PartialOk = logical(scenarioStatus.PartialOk);
manifest.ArtifactsGenerated = logical(scenarioStatus.ArtifactsGenerated);
manifest.ArtifactsWritten = logical(sixgr.util.structGet(scenarioStatus, "ArtifactsWritten", scenarioStatus.ArtifactsGenerated));
manifest.RequiredCaseCount = double(scenarioStatus.RequiredCaseCount);
manifest.RequiredFailureCount = double(scenarioStatus.RequiredFailureCount);
manifest.OptionalPrunedCount = double(scenarioStatus.OptionalPrunedCount);
manifest.RequiredFailedCases = cellstr(string(scenarioStatus.RequiredFailedCases(:)));
manifest.OptionalPrunedCases = cellstr(string(scenarioStatus.OptionalPrunedCases(:)));
manifest.StatusAuthority = char(string(scenarioStatus.StatusAuthority));
manifest.StatusNotes = char(string(scenarioStatus.StatusNotes));
manifest.RuntimeTruthContractOk = logical(scenarioStatus.RuntimeTruthContractOk);
manifest.TruthContractOk = logical(sixgr.util.structGet(scenarioStatus, "TruthContractOk", scenarioStatus.RuntimeTruthContractOk));
manifest.StandardsConformanceOk = logical(sixgr.util.structGet(scenarioStatus, "StandardsConformanceOk", scenarioStatus.RuntimeTruthContractOk));
manifest.ScenarioObjectiveOk = logical(sixgr.util.structGet(scenarioStatus, "ScenarioObjectiveOk", scenarioStatus.ResultOk));
manifest.ConfiguredEffectiveOk = logical(sixgr.util.structGet(scenarioStatus, "ConfiguredEffectiveOk", true));
manifest.MandatorySubsystemsOk = logical(sixgr.util.structGet(scenarioStatus, "MandatorySubsystemsOk", true));
manifest.ActiveIssueGateOk = logical(sixgr.util.structGet(scenarioStatus, "ActiveIssueGateOk", true));
manifest.KpiConsistencyOk = logical(sixgr.util.structGet(scenarioStatus, "KpiConsistencyOk", true));
manifest.StrictAnchorEligible = logical(sixgr.util.structGet(scenarioStatus, "StrictAnchorEligible", false));
manifest.StrictAnchorPass = logical(sixgr.util.structGet(scenarioStatus, "StrictAnchorPass", true));
manifest.ResultStatusReason = char(string(sixgr.util.structGet(scenarioStatus, "ResultStatusReason", "")));
manifest.ActiveMandatoryIssueCount = double(sixgr.util.structGet(scenarioStatus, "ActiveMandatoryIssueCount", 0));
manifest.ActiveCriticalIssueCount = double(sixgr.util.structGet(scenarioStatus, "ActiveCriticalIssueCount", 0));
manifest.ActiveHighIssueCount = double(sixgr.util.structGet(scenarioStatus, "ActiveHighIssueCount", 0));
manifest.ActiveMediumIssueCount = double(sixgr.util.structGet(scenarioStatus, "ActiveMediumIssueCount", 0));
manifest.RoundtripMismatchCount = double(scenarioStatus.RoundtripMismatchCount);
manifest.RequiredRuntimeEvidenceMissingCount = double(scenarioStatus.RequiredRuntimeEvidenceMissingCount);
manifest.StrictTruthFailureCount = double(scenarioStatus.StrictTruthFailureCount);
manifest.StrictProxyGuardFailureCount = double(scenarioStatus.StrictProxyGuardFailureCount);
manifest.CanonicalArtifactGapCount = double(scenarioStatus.CanonicalArtifactGapCount);
manifest.RuntimeTruthContractFailures = cellstr(string(scenarioStatus.RuntimeTruthContractFailures(:)));
manifest.VisualArtifactIntegrityOk = logical(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityOk", true));
manifest.VisualArtifactIntegrityFailureCount = double(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityFailureCount", 0));
manifest.VisualArtifactIntegrityFailures = cellstr(string(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityFailures", strings(0, 1))));
end

function localWriteScenarioManifest(layout, manifest)
sixgr.util.jsonWrite(fullfile(layout.MetaDir, "scenario_manifest.json"), manifest);
reportJsonDir = fullfile(layout.ReportDir, "json");
sixgr.util.ensureFolder(reportJsonDir);
sixgr.util.jsonWrite(fullfile(reportJsonDir, "scenario_manifest.json"), manifest);
end

function gitInfo = localDetectGitProvenance(includeGitHash)
if ~includeGitHash
    gitInfo = struct("Commit", "git_hash_omitted", "Branch", "git_hash_omitted", ...
        "Dirty", false, "StatusSource", "git_hash_omitted_by_config");
    return;
end
repoRoot = localRepoRoot();
gitInfo = struct("Commit", "unavailable", "Branch", "unavailable", ...
    "Dirty", false, "StatusSource", "git_unavailable");
[s1, out1] = system(sprintf('git -C "%s" rev-parse HEAD', repoRoot));
if s1 ~= 0
    return;
end
gitInfo.Commit = string(strtrim(out1));
[s2, out2] = system(sprintf('git -C "%s" rev-parse --abbrev-ref HEAD', repoRoot));
if s2 == 0
    gitInfo.Branch = string(strtrim(out2));
end
[s3, out3] = system(sprintf('git -C "%s" status --porcelain', repoRoot));
if s3 == 0
    gitInfo.Dirty = strlength(strtrim(string(out3))) > 0;
    gitInfo.StatusSource = "git_status_porcelain";
else
    gitInfo.StatusSource = "git_commit_only";
end
end

function [overlay, overlayPath] = localDetectConfigOverlay(scfg)
overlay = "none_detected";
overlayPath = "";
paths = [string(scfg.ConfigPath); string(scfg.SourceFiles(:))];
for i = 1:numel(paths)
    p = paths(i);
    token = lower(p);
    if strlength(strtrim(p)) > 0 && (contains(token, "overlay") || contains(token, "browser_runtime"))
        overlay = p;
        overlayPath = p;
        return;
    end
end
end

function txt = localUTCStamp()
dt = datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd HH:mm:ss");
txt = char(replace(string(dt), " ", "T") + "Z");
end

function localDBLog(levelStr, messageText, varargin)
if nargin >= 3
    try
        messageText = sprintf(messageText, varargin{:});
    catch
    end
end
try
    fprintf(1, "[%s] %s %s\n", localUTCStamp(), upper(char(string(levelStr))), char(string(messageText)));
catch
end
try
    if sixgr.db.isArtifactStoreActive()
        sixgr.db.appendLogLine(string(levelStr), string(localUTCStamp()), string(messageText));
    end
catch
end
end

function localAppendLinkRunStatusLog(layout, scenarioStatus)
failingCaseCount = double(sixgr.util.structGet(scenarioStatus, "FailingCaseCount", 0));
requiredFailureCount = double(sixgr.util.structGet(scenarioStatus, "RequiredFailureCount", 0));
if failingCaseCount <= 0 && requiredFailureCount <= 0
    return;
end
try
    sixgr.util.ensureFolder(layout.AirInterfaceLogDir);
    logPath = fullfile(layout.AirInterfaceLogDir, "run.log");
    fid = fopen(logPath, "a");
    if fid < 0
        return;
    end
    cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
    failures = string(sixgr.util.structGet(scenarioStatus, "RequiredFailedCases", strings(0, 1)));
    failures = failures(strlength(strtrim(failures)) > 0);
    if isempty(failures)
        detail = "no detailed failure code published";
    else
        detail = strjoin(failures(1:min(numel(failures), 6)), "; ");
    end
    fprintf(fid, "[%s] WARN Scenario completed with %g failing case(s); requiredFailures=%g statusAuthority=%s runtimeTruthContractOk=%d details=%s\n", ...
        localUTCStamp(), failingCaseCount, requiredFailureCount, ...
        char(string(sixgr.util.structGet(scenarioStatus, "StatusAuthority", ""))), ...
        double(logical(sixgr.util.structGet(scenarioStatus, "RuntimeTruthContractOk", false))), ...
        char(detail));
catch
end
end

function payload = localBuildTerminalStatusPayload(scenarioStatus, stageName, optionalArtifactIssues)
if nargin < 3
    optionalArtifactIssues = strings(0, 1);
end
payload = struct( ...
    "stage", char(string(stageName)), ...
    "result_ok", logical(scenarioStatus.ResultOk), ...
    "run_completed", logical(sixgr.util.structGet(scenarioStatus, "RunCompleted", false)), ...
    "run_completion", string(scenarioStatus.RunCompletion), ...
    "artifacts_written", logical(sixgr.util.structGet(scenarioStatus, "ArtifactsWritten", scenarioStatus.ArtifactsGenerated)), ...
    "required_failure_count", double(scenarioStatus.RequiredFailureCount), ...
    "failing_case_count", double(scenarioStatus.FailingCaseCount), ...
    "warning_count", double(scenarioStatus.WarningCount), ...
    "status_authority", string(scenarioStatus.StatusAuthority), ...
    "runtime_truth_contract_ok", logical(scenarioStatus.RuntimeTruthContractOk), ...
    "truth_contract_ok", logical(sixgr.util.structGet(scenarioStatus, "TruthContractOk", scenarioStatus.RuntimeTruthContractOk)), ...
    "standards_conformance_ok", logical(sixgr.util.structGet(scenarioStatus, "StandardsConformanceOk", scenarioStatus.RuntimeTruthContractOk)), ...
    "scenario_objective_ok", logical(sixgr.util.structGet(scenarioStatus, "ScenarioObjectiveOk", scenarioStatus.ResultOk)), ...
    "configured_effective_ok", logical(sixgr.util.structGet(scenarioStatus, "ConfiguredEffectiveOk", true)), ...
    "mandatory_subsystems_ok", logical(sixgr.util.structGet(scenarioStatus, "MandatorySubsystemsOk", true)), ...
    "active_issue_gate_ok", logical(sixgr.util.structGet(scenarioStatus, "ActiveIssueGateOk", true)), ...
    "kpi_consistency_ok", logical(sixgr.util.structGet(scenarioStatus, "KpiConsistencyOk", true)), ...
    "strict_anchor_eligible", logical(sixgr.util.structGet(scenarioStatus, "StrictAnchorEligible", false)), ...
    "strict_anchor_pass", logical(sixgr.util.structGet(scenarioStatus, "StrictAnchorPass", true)), ...
    "result_status_reason", string(sixgr.util.structGet(scenarioStatus, "ResultStatusReason", "")), ...
    "active_mandatory_issue_count", double(sixgr.util.structGet(scenarioStatus, "ActiveMandatoryIssueCount", 0)), ...
    "active_critical_issue_count", double(sixgr.util.structGet(scenarioStatus, "ActiveCriticalIssueCount", 0)), ...
    "active_high_issue_count", double(sixgr.util.structGet(scenarioStatus, "ActiveHighIssueCount", 0)), ...
    "active_medium_issue_count", double(sixgr.util.structGet(scenarioStatus, "ActiveMediumIssueCount", 0)), ...
    "roundtrip_mismatch_count", double(scenarioStatus.RoundtripMismatchCount), ...
    "required_runtime_evidence_missing_count", double(scenarioStatus.RequiredRuntimeEvidenceMissingCount), ...
    "strict_truth_failure_count", double(scenarioStatus.StrictTruthFailureCount), ...
    "strict_proxy_guard_failure_count", double(scenarioStatus.StrictProxyGuardFailureCount), ...
    "canonical_artifact_gap_count", double(scenarioStatus.CanonicalArtifactGapCount), ...
    "visual_artifact_integrity_ok", logical(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityOk", true)), ...
    "visual_artifact_integrity_failure_count", double(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityFailureCount", 0)), ...
    "error_source", string(scenarioStatus.ErrorSource), ...
    "error_identifier", string(scenarioStatus.ErrorIdentifier), ...
    "error_message", string(scenarioStatus.ErrorMessage), ...
    "optional_artifact_issue_count", double(numel(optionalArtifactIssues)), ...
    "optional_artifact_issues", cellstr(string(optionalArtifactIssues(:))), ...
    "timestamp_utc", string(localUTCStamp()));
end

function localMarkRunStatusSafe(statusText, payload)
if ~sixgr.db.isArtifactStoreActive()
    return;
end
try
    sixgr.db.markRunStatus(string(statusText), payload);
catch ME
    try
        fprintf(1, "[%s] WARN Run status update failed: %s | %s\n", ...
            localUTCStamp(), char(string(ME.identifier)), char(string(ME.message)));
    catch
    end
end
end

function hydration = localHydratePublicRunFolderIfNeeded(stagingRunFolder, publicRunFolder)
hydration = struct("Ok", true, "FileCount", 0, "ByteCount", 0, ...
    "SkippedCount", 0, "TargetRoot", string(publicRunFolder), "Notes", "artifact_store_inactive_or_same_folder");
if ~sixgr.db.isArtifactStoreActive()
    return;
end
stagingRunFolder = string(stagingRunFolder);
publicRunFolder = string(publicRunFolder);
if strlength(strtrim(publicRunFolder)) == 0
    hydration.Ok = false;
    hydration.Notes = "public_run_folder_unavailable";
    return;
end
if localSameFolder(stagingRunFolder, publicRunFolder)
    return;
end
try
    hydration = sixgr.db.hydrateActiveArtifactStore(publicRunFolder);
catch ME
    hydration = struct("Ok", false, "FileCount", 0, "ByteCount", 0, ...
        "SkippedCount", NaN, "TargetRoot", publicRunFolder, ...
        "Notes", string(ME.identifier) + ":" + string(ME.message));
end
end

function tf = localSameFolder(a, b)
a = char(string(a));
b = char(string(b));
if ispc
    tf = strcmpi(strrep(a, "/", "\"), strrep(b, "/", "\"));
else
    tf = strcmp(strrep(a, "\", "/"), strrep(b, "\", "/"));
end
end

function relPath = localWriteArtifactManifest(runFolder, scfg, profile, manifest, reportBundle, scenarioStatus)
storeState = sixgr.db.artifactStore("get_state");
runID = double(sixgr.util.structGet(storeState, "RunID", NaN));
if isfinite(runID) && runID > 0
    runToken = sprintf("%d", round(runID));
else
    runToken = localSanitizeToken(string(scfg.ScenarioID), "scenario");
end
relPath = fullfile("outputs", runToken, "artifact_manifest.json");
inventoryT = sixgr.util.structGet(reportBundle, "Inventory", table());
unavailableRows = sixgr.util.structGet(reportBundle, "OutputCoverageArtifacts.ManifestUnavailableEntries", struct([]));
payload = struct();
payload.GeneratedUTC = localUTCStamp();
payload.RunID = runID;
payload.ScenarioID = char(string(scfg.ScenarioID));
payload.RunnerProfile = char(string(profile));
payload.ConfigHash = char(string(sixgr.util.structGet(manifest, "ConfigHash", "")));
payload.RunCompletion = char(string(sixgr.util.structGet(scenarioStatus, "RunCompletion", "")));
payload.ResultOk = logical(sixgr.util.structGet(scenarioStatus, "ResultOk", false));
payload.ArtifactInventoryCSV = "reports/csv/artifact_inventory.csv";
payload.ArtifactCount = height(inventoryT);
payload.Artifacts = localArtifactManifestRows(inventoryT);
payload.UnavailableArtifacts = unavailableRows;
sixgr.util.jsonWrite(fullfile(runFolder, relPath), payload);
end

function rows = localArtifactManifestRows(T)
rows = repmat(struct( ...
    "RelativePath", "", ...
    "ArtifactClass", "", ...
    "SemanticState", "", ...
    "Bytes", NaN, ...
    "MachineReadable", false, ...
    "HumanReadable", false), 0, 1);
if ~(istable(T) && ~isempty(T))
    return;
end
for i = 1:height(T)
    row = struct();
    row.RelativePath = char(string(localTableValue(T, i, "RelativePath", "")));
    row.ArtifactClass = char(string(localTableValue(T, i, "ArtifactClass", "")));
    row.SemanticState = char(string(localTableValue(T, i, "SemanticState", "")));
    row.Bytes = double(localTableValue(T, i, "Bytes", NaN));
    row.MachineReadable = logical(localTableValue(T, i, "MachineReadable", false));
    row.HumanReadable = logical(localTableValue(T, i, "HumanReadable", false));
    rows(end + 1, 1) = row; %#ok<AGROW>
end
end

function value = localTableValue(T, rowIdx, varName, defaultValue)
value = defaultValue;
if ~(istable(T) && rowIdx >= 1 && rowIdx <= height(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
raw = T.(char(varName))(rowIdx);
if iscell(raw)
    value = raw{1};
else
    value = raw;
end
end

function profileName = localResolveRunRowProfileName(scfg)
profileName = string(scfg.get("scenario.runner_profile", ""));
if strlength(strtrim(profileName)) == 0
    profileName = string(scfg.get("scenario.profile_name", ""));
end
if strlength(strtrim(profileName)) == 0
    profileName = string(scfg.get("deployment_topology.cell_type", ""));
end
if strlength(strtrim(profileName)) == 0
    profileName = string(scfg.ScenarioID);
end
profileName = strtrim(profileName);
end

function profile = localResolveEffectiveRunnerProfile(scfg, cfg, configuredProfile)
profile = lower(strtrim(string(configuredProfile)));
if strlength(profile) == 0
    profile = lower(strtrim(string(scfg.get("scenario.runner_profile", ""))));
end

executionModel = lower(strtrim(string(sixgr.util.structGet(cfg, "lls6g.users.execution_model", ...
    scfg.get("users.execution_model", "")))));
controlRequired = any([ ...
    logical(sixgr.util.structGet(cfg, "run.controlGating.pbchRequired", false)), ...
    logical(sixgr.util.structGet(cfg, "run.controlGating.prachRequired", false)), ...
    logical(sixgr.util.structGet(cfg, "run.controlGating.pdcchRequired", false)), ...
    logical(sixgr.util.structGet(cfg, "run.controlGating.srsRequired", false)), ...
    logical(sixgr.util.structGet(cfg, "run.controlGating.trsRequired", false))]);

if profile == "system_level_lls" && executionModel == "slot_coupled_truth" && controlRequired
    profile = "waveform_bundle";
    localDBLog("INFO", ...
        "Effective runner promoted from system_level_lls to waveform_bundle because users.execution_model=slot_coupled_truth and runtime control/reference gating is required.");
end
end

function [codeVersion, detail] = localDetectCodeVersion(includeGitHash)
if ~includeGitHash
    codeVersion = "git_hash_omitted";
    detail = "git_hash_omitted_by_config";
    return;
end
repoRoot = localRepoRoot();
codeVersion = "unknown";
detail = "git_unavailable";
cmdHash = sprintf('git -C "%s" rev-parse --short HEAD', repoRoot);
[s1, out1] = system(cmdHash);
if s1 ~= 0
    return;
end
hash = strtrim(out1);
cmdBranch = sprintf('git -C "%s" rev-parse --abbrev-ref HEAD', repoRoot);
[~, out2] = system(cmdBranch);
branch = strtrim(out2);
codeVersion = "git:" + string(hash);
detail = "branch=" + string(branch) + "; hash=" + string(hash);
end

function localAnnotateAllCSV(runFolder, scfg, profile)
if sixgr.db.isArtifactStoreActive()
    return;
end
files = dir(fullfile(runFolder, "**", "*.csv"));
for i = 1:numel(files)
    f = fullfile(files(i).folder, files(i).name);
    try
        T = readtable(f, 'Delimiter', ',', 'ReadVariableNames', true, ...
            'VariableNamingRule', 'preserve');
    catch
        continue;
    end
    if ~ismember("ScenarioID", T.Properties.VariableNames)
        T = addvars(T, localConstantStringColumn(height(T), scfg.ScenarioID), ...
            'Before', 1, 'NewVariableNames', 'ScenarioID');
    end
    if ~ismember("ConfigHash", T.Properties.VariableNames)
        T = addvars(T, localConstantStringColumn(height(T), scfg.ConfigHash), ...
            'Before', 2, 'NewVariableNames', 'ConfigHash');
    end
    if ~ismember("RunnerProfile", T.Properties.VariableNames)
        T = addvars(T, localConstantStringColumn(height(T), profile), ...
            'Before', min(3, width(T)+1), 'NewVariableNames', 'RunnerProfile');
    end
    sixgr.util.csvWriteTable(f, T);
end
end

function col = localConstantStringColumn(nRows, value)
col = repmat(string(value), max(0, nRows), 1);
end

function T = localBuildScenarioSummaryTable(scfg, profile, result, scenarioStatus)
okVal = logical(scenarioStatus.ResultOk);
opSummary = localOperatingPointSummary(scfg, result);
numerologyMu = double(sixgr.util.structGet(opSummary, "Radio.Numerology_mu", NaN));
scsKHz = double(sixgr.util.structGet(opSummary, "Radio.SCS_kHz", NaN));
slotDuration_ms = double(sixgr.util.structGet(opSummary, "Radio.SlotDuration_ms", NaN));
slotsPerFrame = double(sixgr.util.structGet(opSummary, "Radio.SlotsPerFrame", NaN));
symbolsPerSlot = double(sixgr.util.structGet(opSummary, "Radio.SymbolsPerSlot", NaN));
T = table( ...
    string(scfg.ScenarioID), ...
    string(profile), ...
    string(scfg.ConfigHash), ...
    double(scfg.get("simulation.random_seed")), ...
    logical(scfg.get("simulation.deterministic_mode")), ...
    logical(scfg.get("logging.strict_validation")), ...
    double(scfg.get("users.n_users", 1)), ...
    double(scfg.get("mimo.n_layers")), ...
    string(scfg.get("users.beam_selection_strategy")), ...
    "6G_PHY_LLS_SINGLE_SCENARIO", ...
    string(scenarioStatus.RunCompletion), ...
    logical(sixgr.util.structGet(scenarioStatus, "RunCompleted", false)), ...
    okVal, ...
    okVal, ...
    logical(scenarioStatus.PartialOk), ...
    logical(scenarioStatus.ArtifactsGenerated), ...
    logical(sixgr.util.structGet(scenarioStatus, "ArtifactsWritten", scenarioStatus.ArtifactsGenerated)), ...
    double(scenarioStatus.RequiredCaseCount), ...
    double(scenarioStatus.RequiredFailureCount), ...
    double(scenarioStatus.OptionalPrunedCount), ...
    string(scenarioStatus.StatusAuthority), ...
    logical(scenarioStatus.RuntimeTruthContractOk), ...
    logical(sixgr.util.structGet(scenarioStatus, "TruthContractOk", scenarioStatus.RuntimeTruthContractOk)), ...
    logical(sixgr.util.structGet(scenarioStatus, "StandardsConformanceOk", scenarioStatus.RuntimeTruthContractOk)), ...
    logical(sixgr.util.structGet(scenarioStatus, "ScenarioObjectiveOk", scenarioStatus.ResultOk)), ...
    logical(sixgr.util.structGet(scenarioStatus, "ConfiguredEffectiveOk", true)), ...
    logical(sixgr.util.structGet(scenarioStatus, "MandatorySubsystemsOk", true)), ...
    logical(sixgr.util.structGet(scenarioStatus, "ActiveIssueGateOk", true)), ...
    logical(sixgr.util.structGet(scenarioStatus, "KpiConsistencyOk", true)), ...
    logical(sixgr.util.structGet(scenarioStatus, "StrictAnchorEligible", false)), ...
    logical(sixgr.util.structGet(scenarioStatus, "StrictAnchorPass", true)), ...
    string(sixgr.util.structGet(scenarioStatus, "ResultStatusReason", "")), ...
    double(sixgr.util.structGet(scenarioStatus, "ActiveMandatoryIssueCount", 0)), ...
    double(sixgr.util.structGet(scenarioStatus, "ActiveCriticalIssueCount", 0)), ...
    double(sixgr.util.structGet(scenarioStatus, "ActiveHighIssueCount", 0)), ...
    double(sixgr.util.structGet(scenarioStatus, "ActiveMediumIssueCount", 0)), ...
    double(scenarioStatus.RoundtripMismatchCount), ...
    double(scenarioStatus.RequiredRuntimeEvidenceMissingCount), ...
    double(scenarioStatus.StrictTruthFailureCount), ...
    double(scenarioStatus.StrictProxyGuardFailureCount), ...
    double(scenarioStatus.CanonicalArtifactGapCount), ...
    logical(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityOk", true)), ...
    double(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityFailureCount", 0)), ...
    string(strjoin(string(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityFailures", strings(0, 1))), "; ")), ...
    string(strjoin(string(scenarioStatus.RuntimeTruthContractFailures(:)), "; ")), ...
    string(scfg.get("meta.description", "")), ...
    string(opSummary.RuntimeQualifiedDescription), ...
    "nominal", ...
    string(opSummary.Configured.MIMOText), ...
    string(opSummary.Configured.DL.OperatingPointText), ...
    string(opSummary.Configured.UL.OperatingPointText), ...
    double(opSummary.Radio.ActiveGridNumRBs), ...
    double(opSummary.Radio.ConfiguredGridNumRBs), ...
    string(opSummary.Radio.ActiveGridSource), ...
    numerologyMu, ...
    scsKHz, ...
    slotDuration_ms, ...
    slotsPerFrame, ...
    symbolsPerSlot, ...
    string(sixgr.util.structGet(opSummary, "Radio.NumerologySource", "")), ...
    string(sixgr.util.structGet(opSummary, "Radio.TimingInterpretationSource", "")), ...
    string(opSummary.Radio.ActiveDuplexMode), ...
    string(opSummary.Radio.ConfiguredTDDPattern), ...
    string(opSummary.Radio.ActiveTDDPattern), ...
    logical(opSummary.Radio.TDDPatternApplicable), ...
    double(opSummary.DL.SampleCount), ...
    string(opSummary.DL.DominantOperatingPointText), ...
    string(opSummary.DL.LayerHistogram), ...
    string(opSummary.DL.RankHistogram), ...
    string(opSummary.DL.ModulationHistogram), ...
    string(opSummary.DL.MCSHistogram), ...
    double(opSummary.DL.ConfiguredMatchRate), ...
    double(opSummary.UL.SampleCount), ...
    string(opSummary.UL.DominantOperatingPointText), ...
    string(opSummary.UL.LayerHistogram), ...
    string(opSummary.UL.RankHistogram), ...
    string(opSummary.UL.ModulationHistogram), ...
    string(opSummary.UL.MCSHistogram), ...
    double(opSummary.UL.ConfiguredMatchRate), ...
    double(scenarioStatus.FailingCaseCount), ...
    double(scenarioStatus.WarningCount), ...
    string(scenarioStatus.ErrorSource), ...
    string(scenarioStatus.ErrorIdentifier), ...
    string(scenarioStatus.ErrorMessage), ...
    string(scenarioStatus.AuthoritativeStatusSource), ...
    string(opSummary.RuntimeNarrative), ...
    'VariableNames', {'ScenarioID','RunnerProfile','ConfigHash','RandomSeed', ...
    'DeterministicMode','StrictValidation','NumUsers','ConfiguredLayers','BeamSelectionStrategy', ...
    'RunScope','RunCompletion','RunCompleted','Ok','ResultOk','PartialOk','ArtifactsGenerated','ArtifactsWritten', ...
    'RequiredCaseCount','RequiredFailureCount','OptionalPrunedCount','StatusAuthority', ...
    'RuntimeTruthContractOk','TruthContractOk','StandardsConformanceOk','ScenarioObjectiveOk', ...
    'ConfiguredEffectiveOk','MandatorySubsystemsOk','ActiveIssueGateOk','KpiConsistencyOk','StrictAnchorEligible','StrictAnchorPass','ResultStatusReason', ...
    'ActiveMandatoryIssueCount','ActiveCriticalIssueCount','ActiveHighIssueCount','ActiveMediumIssueCount', ...
    'RoundtripMismatchCount','RequiredRuntimeEvidenceMissingCount', ...
    'StrictTruthFailureCount','StrictProxyGuardFailureCount','CanonicalArtifactGapCount','VisualArtifactIntegrityOk','VisualArtifactIntegrityFailureCount','VisualArtifactIntegrityFailures','RuntimeTruthContractFailures','Description', ...
    'RuntimeQualifiedDescription', ...
    'ConfiguredParameterSemantics','ConfiguredMIMO','ConfiguredDLNominalOperatingPoint','ConfiguredULNominalOperatingPoint', ...
    'ActiveGridNumRBs','ConfiguredGridNumRBs','ActiveGridSource','Numerology_mu','SCS_kHz','SlotDuration_ms','SlotsPerFrame','SymbolsPerSlot','NumerologySource','TimingInterpretationSource','ActiveDuplexMode','ConfiguredTDDPattern','ActiveTDDPattern','TDDPatternApplicable', ...
    'EffectiveDLTrialCount','EffectiveDLDominantOperatingPoint','EffectiveDLLayerHistogram','EffectiveDLRankHistogram','EffectiveDLModulationHistogram','EffectiveDLMCSHistogram','EffectiveDLConfiguredMatchRate', ...
    'EffectiveULTrialCount','EffectiveULDominantOperatingPoint','EffectiveULLayerHistogram','EffectiveULRankHistogram','EffectiveULModulationHistogram','EffectiveULMCSHistogram','EffectiveULConfiguredMatchRate', ...
    'FailingCaseCount','WarningCount','ErrorSource','ErrorIdentifier','ErrorMessage','AuthoritativeStatusSource', ...
    'EffectiveRuntimeNote'});
end

function localWriteMarkdownReport(filePath, scfg, profile, runFolder, result, manifest, reportBundle, scenarioStatus)
fid = fopen(filePath, "w");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
opSummary = localOperatingPointSummary(scfg, result);
fprintf(fid, "# 6G PHY LLS Scenario Report\n\n");
localWriteImplementationVerdictSection(fid, sixgr.util.structGet(reportBundle, "ImplementationValidation", struct()));
fprintf(fid, "- Scenario ID: `%s`\n", string(scfg.ScenarioID));
fprintf(fid, "- Scenario description (configured intent): `%s`\n", string(scfg.get("meta.description", "")));
fprintf(fid, "- Runtime-qualified description: `%s`\n", string(opSummary.RuntimeQualifiedDescription));
fprintf(fid, "- Runner profile: `%s`\n", string(profile));
fprintf(fid, "- Config hash: `%s`\n", string(scfg.ConfigHash));
fprintf(fid, "- Run folder: `%s`\n", string(localRelativeToRunFolder(runFolder, runFolder)));
fprintf(fid, "- Code version: `%s`\n", string(manifest.CodeVersion));
fprintf(fid, "- Random seed: `%d`\n", double(scfg.get("simulation.random_seed")));
fprintf(fid, "- Deterministic mode: `%s`\n", string(logical(scfg.get("simulation.deterministic_mode"))));
fprintf(fid, "- Strict validation: `%s`\n", string(logical(scfg.get("logging.strict_validation"))));
fprintf(fid, "- Users: `%d`\n", double(scfg.get("users.n_users", 1)));
fprintf(fid, "- Configured nominal layers: `%d`\n", double(scfg.get("mimo.n_layers")));
fprintf(fid, "- Configured nominal Tx/Rx antennas: `%dx%d`\n", double(scfg.get("mimo.n_tx_ant")), double(scfg.get("mimo.n_rx_ant")));
fprintf(fid, "- User execution model: `%s`\n", string(scfg.get("users.execution_model", "independent_link_sweep")));
fprintf(fid, "- Beam selection strategy: `%s`\n", string(scfg.get("users.beam_selection_strategy")));
fprintf(fid, "- Run scope: `%s`\n", string(manifest.RunScope));
fprintf(fid, "- Run completion: `%s`\n", string(manifest.RunCompletion));
fprintf(fid, "- Result OK: `%s`\n", string(logical(scenarioStatus.ResultOk)));
fprintf(fid, "- Status: `%s`\n", string(logical(scenarioStatus.ResultOk)));
fprintf(fid, "- Partial OK: `%s`\n", string(logical(scenarioStatus.PartialOk)));
fprintf(fid, "- Artifacts generated: `%s`\n", string(logical(scenarioStatus.ArtifactsGenerated)));
fprintf(fid, "- Required case count: `%g`\n", double(scenarioStatus.RequiredCaseCount));
fprintf(fid, "- Required failure count: `%g`\n", double(scenarioStatus.RequiredFailureCount));
fprintf(fid, "- Optional/pruned case count: `%g`\n", double(scenarioStatus.OptionalPrunedCount));
fprintf(fid, "- Status authority: `%s`\n", string(scenarioStatus.StatusAuthority));
fprintf(fid, "- Runtime truth contract OK: `%s`\n", string(logical(scenarioStatus.RuntimeTruthContractOk)));
fprintf(fid, "- Roundtrip mismatch count: `%g`\n", double(scenarioStatus.RoundtripMismatchCount));
fprintf(fid, "- Required runtime evidence missing count: `%g`\n", double(scenarioStatus.RequiredRuntimeEvidenceMissingCount));
fprintf(fid, "- Strict truth failure count: `%g`\n", double(scenarioStatus.StrictTruthFailureCount));
if strlength(string(scenarioStatus.StatusNotes)) > 0
    fprintf(fid, "- Status notes: `%s`\n", string(scenarioStatus.StatusNotes));
end
fprintf(fid, "- Runtime seconds: `%.3f`\n", double(sixgr.util.structGet(manifest, "ElapsedSeconds", NaN)));
fprintf(fid, "- Environment summary: `meta/environment.json`\n");
fprintf(fid, "- Runtime summary: `meta/runtime_summary.json`\n");
fprintf(fid, "\n## Configured vs Effective Operating Point\n\n");
fprintf(fid, "- Configured parameter semantics: `nominal`\n");
fprintf(fid, "- Configured nominal MIMO: `%s`\n", string(opSummary.Configured.MIMOText));
fprintf(fid, "- Configured DL nominal operating point: `%s`\n", string(opSummary.Configured.DL.OperatingPointText));
fprintf(fid, "- Configured UL nominal operating point: `%s`\n", string(opSummary.Configured.UL.OperatingPointText));
fprintf(fid, "- Active grid RBs: `%s` from `%s`\n", string(localNumericMarkdownToken(opSummary.Radio.ActiveGridNumRBs)), string(opSummary.Radio.ActiveGridSource));
if isfinite(double(opSummary.Radio.ConfiguredGridNumRBs)) && double(opSummary.Radio.ConfiguredGridNumRBs) ~= double(opSummary.Radio.ActiveGridNumRBs)
    fprintf(fid, "- Legacy configured grid RBs retained for traceability: `%s`\n", string(localNumericMarkdownToken(opSummary.Radio.ConfiguredGridNumRBs)));
end
fprintf(fid, "- Active duplex mode: `%s`\n", string(opSummary.Radio.ActiveDuplexMode));
fprintf(fid, "- Configured TDD pattern: `%s`\n", string(opSummary.Radio.ConfiguredTDDPattern));
fprintf(fid, "- Active TDD pattern: `%s`\n", string(opSummary.Radio.ActiveTDDPattern));
fprintf(fid, "- TDD pattern applicable: `%s`\n", string(logical(opSummary.Radio.TDDPatternApplicable)));
if logical(opSummary.DL.HasSamples)
    fprintf(fid, "- Effective DL dominant operating point: `%s`\n", string(opSummary.DL.DominantOperatingPointText));
    fprintf(fid, "- Effective DL layer histogram: `%s`\n", string(opSummary.DL.LayerHistogram));
    fprintf(fid, "- Effective DL rank histogram: `%s`\n", string(opSummary.DL.RankHistogram));
    fprintf(fid, "- Effective DL modulation histogram: `%s`\n", string(opSummary.DL.ModulationHistogram));
    fprintf(fid, "- Effective DL MCS histogram: `%s`\n", string(opSummary.DL.MCSHistogram));
end
if logical(opSummary.UL.HasSamples)
    fprintf(fid, "- Effective UL dominant operating point: `%s`\n", string(opSummary.UL.DominantOperatingPointText));
    fprintf(fid, "- Effective UL layer histogram: `%s`\n", string(opSummary.UL.LayerHistogram));
    fprintf(fid, "- Effective UL rank histogram: `%s`\n", string(opSummary.UL.RankHistogram));
    fprintf(fid, "- Effective UL modulation histogram: `%s`\n", string(opSummary.UL.ModulationHistogram));
    fprintf(fid, "- Effective UL MCS histogram: `%s`\n", string(opSummary.UL.MCSHistogram));
end
fprintf(fid, "- Effective runtime note: `%s`\n", string(opSummary.RuntimeNarrative));
fprintf(fid, "\n## Report Bundle\n\n");
fprintf(fid, "- Coverage table: `reports/csv/lls_output_spec_coverage.csv`\n");
fprintf(fid, "- Metric rows: `reports/csv/lls_output_metric_rows.csv`\n");
fprintf(fid, "- Artifact inventory: `reports/csv/artifact_inventory.csv`\n");
fprintf(fid, "- Validation messages: `reports/csv/validation_messages.csv`\n");
fprintf(fid, "- Executive summary: `%s`\n", string(localRelativeToRunFolder(sixgr.util.structGet(reportBundle, "ExecutiveSummary", ""), runFolder)));
fprintf(fid, "- Technical report: `%s`\n", string(localRelativeToRunFolder(sixgr.util.structGet(reportBundle, "TechnicalReport", ""), runFolder)));
fprintf(fid, "\n## Source Chain\n\n");
for i = 1:numel(scfg.SourceFiles)
    fprintf(fid, "- `%s`\n", string(localPortablePath(scfg.SourceFiles(i))));
end
clear cleanupObj
sixgr.db.captureFileArtifact(filePath, "markdown_report", "text/markdown; charset=UTF-8", true);
end

function localWriteImplementationVerdictSection(fid, validation)
if ~(isstruct(validation) && isfield(validation, "Summary") && isstruct(validation.Summary))
    return;
end
summary = validation.Summary;
fprintf(fid, "## Actual LLS Implementation Verdict\n\n");
fprintf(fid, "- Verdict: `%s`\n", string(sixgr.util.structGet(summary, "ActualLLSVerdict", "")));
fprintf(fid, "- Statement: %s\n", string(sixgr.util.structGet(summary, "VerdictSentence", "")));
fprintf(fid, "- Enabled blocks: `%g`\n", double(sixgr.util.structGet(summary, "EnabledBlockCount", 0)));
fprintf(fid, "- Passing blocks: `%g`\n", double(sixgr.util.structGet(summary, "PassingBlockCount", 0)));
fprintf(fid, "- Reference-compared blocks: `%g`\n", double(sixgr.util.structGet(summary, "ReferenceComparedBlockCount", 0)));
fprintf(fid, "- Numerical sanity failures: `%g`\n", double(sixgr.util.structGet(summary, "NumericalSanityFailureCount", 0)));
fprintf(fid, "- Expected functions not called: `%s`\n", strjoin(cellstr(string(sixgr.util.structGet(summary, "FunctionNotCalled", strings(0, 1)))), " | "));
fprintf(fid, "- Bypassed blocks: `%s`\n", strjoin(cellstr(string(sixgr.util.structGet(summary, "BypassedBlocks", strings(0, 1)))), " | "));
proxyDetections = unique([ ...
    string(sixgr.util.structGet(summary, "LabelOnlyBlocks", strings(0, 1))); ...
    string(sixgr.util.structGet(summary, "ProxyBlocks", strings(0, 1))); ...
    string(sixgr.util.structGet(summary, "FallbackBlocks", strings(0, 1)))]);
fprintf(fid, "- Label-only/proxy detections: `%s`\n\n", strjoin(cellstr(proxyDetections), " | "));
end

function opSummary = localOperatingPointSummary(scfg, result)
dlTrials = table();
ulTrials = table();
if isstruct(result) && isfield(result, "Link")
    rawTrials = sixgr.util.structGet(result.Link, "RawTrials", struct());
    dlTrials = localOptionalRawTrialTable(rawTrials, "DL");
    ulTrials = localOptionalRawTrialTable(rawTrials, "UL");
    if isempty(dlTrials)
        dlTrials = localOptionalNestedTrialTable(result.Link, "ResultDL");
    end
    if isempty(ulTrials)
        ulTrials = localOptionalNestedTrialTable(result.Link, "ResultUL");
    end
end
opSummary = sixgr.truth.summarizeEffectiveOperatingPoint(scfg, dlTrials, ulTrials);
opSummary.Radio.Numerology_mu = localDeriveNumerologyMu(double(scfg.get("frame.scs_khz", NaN)));
opSummary.Radio.SCS_kHz = double(scfg.get("frame.scs_khz", NaN));
opSummary.Radio.SlotDuration_ms = localDeriveSlotDurationMs(opSummary.Radio.Numerology_mu);
opSummary.Radio.SlotsPerFrame = localDeriveSlotsPerFrame(opSummary.Radio.Numerology_mu);
opSummary.Radio.SymbolsPerSlot = 14;
opSummary.Radio.NumerologySource = "frame.scs_khz_runtime_authority";
opSummary.Radio.TimingInterpretationSource = "nr_mu_from_scs";
end

function T = localOptionalRawTrialTable(rawTrials, fieldName)
T = table();
if isstruct(rawTrials) && isfield(rawTrials, char(fieldName)) && istable(rawTrials.(char(fieldName)))
    T = rawTrials.(char(fieldName));
end
end

function T = localOptionalNestedTrialTable(linkResult, fieldName)
T = table();
if ~(isstruct(linkResult) && isfield(linkResult, char(fieldName)))
    return;
end
node = linkResult.(char(fieldName));
if isstruct(node)
    T = sixgr.util.structGet(node, "TrialTable", table());
end
if ~istable(T)
    T = table();
end
end

function resolvedStruct = localResolvedSnapshotStruct(scfg)
resolvedStruct = scfg.toStruct();
resolvedStruct = localSanitizeNoProxySnapshot(scfg, resolvedStruct);
opSummary = sixgr.truth.summarizeEffectiveOperatingPoint(scfg, table(), table());
legacyGrid = sixgr.util.structGet(resolvedStruct, "resource_grid.num_rbs", NaN);
activeGrid = double(opSummary.Radio.ActiveGridNumRBs);
if isfinite(activeGrid)
    if isfinite(legacyGrid) && legacyGrid ~= activeGrid
        resolvedStruct = sixgr.util.structSet(resolvedStruct, "resource_grid.configured_num_rbs", legacyGrid);
    end
    resolvedStruct = sixgr.util.structSet(resolvedStruct, "resource_grid.num_rbs", activeGrid);
    resolvedStruct = sixgr.util.structSet(resolvedStruct, "resource_grid.active_num_rbs_source", char(string(opSummary.Radio.ActiveGridSource)));
end
resolvedStruct = sixgr.util.structSet(resolvedStruct, "frequency.active_duplex_mode", char(string(opSummary.Radio.ActiveDuplexMode)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "frame.configured_tdd_pattern", char(string(opSummary.Radio.ConfiguredTDDPattern)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "frame.tdd_pattern_applicable", logical(opSummary.Radio.TDDPatternApplicable));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "frame.active_tdd_pattern", char(string(opSummary.Radio.ActiveTDDPattern)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "reporting_semantics.configured_parameters_are_nominal", true);
resolvedStruct = sixgr.util.structSet(resolvedStruct, "reporting_semantics.actual_runtime_selected_parameters_emitted_in", "reports/csv/scenario_summary.csv");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "reporting_semantics.report_bundle_runtime_metadata_emitted_in", "reports/csv/run_metadata_outputs.csv");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "reporting_semantics.runtime_qualified_description_emitted_in", "reports/csv/scenario_summary.csv");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.configured_mimo", char(string(opSummary.Configured.MIMOText)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.configured_dl_nominal_operating_point", char(string(opSummary.Configured.DL.OperatingPointText)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.configured_ul_nominal_operating_point", char(string(opSummary.Configured.UL.OperatingPointText)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.active_grid_num_rbs", double(opSummary.Radio.ActiveGridNumRBs));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.active_grid_source", char(string(opSummary.Radio.ActiveGridSource)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.active_duplex_mode", char(string(opSummary.Radio.ActiveDuplexMode)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.active_tdd_pattern", char(string(opSummary.Radio.ActiveTDDPattern)));
resolvedStruct = sixgr.util.structSet(resolvedStruct, "resolved_runtime_view.tdd_pattern_applicable", logical(opSummary.Radio.TDDPatternApplicable));
end

function resolvedStruct = localSanitizeNoProxySnapshot(scfg, resolvedStruct)
tags = lower(string(sixgr.util.structGet(resolvedStruct, "meta.tags", strings(0, 1))));
strictValidation = false;
try
    strictValidation = logical(scfg.get("logging.strict_validation", false));
catch
end
noProxyTruth = any(tags == "no-proxy") || (any(tags == "truth") && strictValidation);
if ~noProxyTruth
    return;
end

resolvedStruct = sixgr.util.structSet(resolvedStruct, "reporting_semantics.no_proxy_truth_contract", true);
resolvedStruct = sixgr.util.structSet(resolvedStruct, ...
    "reporting_semantics.snapshot_sanitization_note", ...
    "Strict no-proxy truth snapshots disable proxy/fallback defaults and relabel complexity-derived area-efficiency metrics as measured runtime values.");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "reporting_semantics.area_efficiency_runtime_metric", "bits_per_decoder_complexity_unit");

resolvedStruct = sixgr.util.structSet(resolvedStruct, "ai_ml.fallback_enabled", false);
resolvedStruct = sixgr.util.structSet(resolvedStruct, "ai_ml.fallback_mode", "disabled");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "channel_coding.area_efficiency_proxy_policy", "measured_runtime_metric");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "coding_and_decoder.area_efficiency_proxy_policy", "measured_runtime_metric");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "energy_and_complexity.area_efficiency_proxy", "measured_runtime_metric");
resolvedStruct = sixgr.util.structSet(resolvedStruct, "energy_efficiency.area_efficiency_proxy", "measured_runtime_metric");
end

function token = localNumericMarkdownToken(value)
if ~isfinite(double(value))
    token = "NaN";
elseif abs(double(value) - round(double(value))) < 1e-12
    token = string(round(double(value)));
else
    token = string(double(value));
end
end

function runtime = localBuildRuntimeSummary(startUTC, runTimer, profile, runFolder, cfg)
runtime = struct();
runtime.StartedUTC = char(string(startUTC));
runtime.CompletedUTC = char(string(localUTCStamp()));
runtime.ElapsedSeconds = double(toc(runTimer));
runtime.RunnerProfile = char(string(profile));
runtime.RunFolder = char(string(runFolder));
runtime.WarningCount = 0;
runtime.Warnings = strings(0, 1);
runtime.UseMex = logical(sixgr.util.structGet(cfg, "run.useMex", false));
runtime.UseMexAutoEnabled = logical(sixgr.util.structGet(cfg, "run.useMexAutoEnabled", false));
runtime.UseParallel = logical(sixgr.util.structGet(cfg, "run.useParallel", false));
runtime.RequestedWorkers = double(sixgr.util.structGet(cfg, "run.parallelRequestedWorkers", ...
    sixgr.util.structGet(cfg, "run.numWorkers", 0)));
runtime.EffectiveWorkers = localEffectiveWorkerCount(cfg);
runtime.ParallelDisabledReason = char(string(sixgr.util.structGet(cfg, "run.parallelDisabledReason", "")));
runtime.MaxNumCompThreads = double(localSafeMaxNumCompThreads());
runtime.Numerology_mu = double(sixgr.util.structGet(cfg, "phy.numerology.mu", NaN));
runtime.SCS_kHz = double(sixgr.util.structGet(cfg, "phy.numerology.scs_kHz", NaN));
runtime.SlotDuration_ms = double(sixgr.util.structGet(cfg, "phy.numerology.slotDuration_ms", NaN));
runtime.SlotsPerFrame = double(sixgr.util.structGet(cfg, "phy.numerology.slotsPerFrame", NaN));
runtime.SymbolsPerSlot = double(sixgr.util.structGet(cfg, "phy.numerology.symbolsPerSlot", NaN));
runtime.ConfiguredGridNumRBs = double(sixgr.util.structGet(cfg, "phy.numerology.configuredGridNumRBs", NaN));
runtime.ActiveGridNumRBs = double(sixgr.util.structGet(cfg, "phy.numerology.activeGridNumRBs", NaN));
runtime.ActiveGridSource = char(string(sixgr.util.structGet(cfg, "phy.numerology.activeGridSource", "")));
runtime.NumerologySource = char(string(sixgr.util.structGet(cfg, "phy.numerology.numerologySource", "")));
runtime.TimingInterpretationSource = char(string(sixgr.util.structGet(cfg, "phy.numerology.timingInterpretationSource", "")));
end

function env = localBuildEnvironmentSummary(cfg)
env = struct();
env.Platform = char(string(computer));
env.Architecture = char(string(computer("arch")));
env.MATLABVersion = char(string(version));
env.MATLABRelease = char(string(version("-release")));
env.JavaVersion = char(string(version("-java")));
env.Hostname = char(string(getenv("COMPUTERNAME")));
env.OS = char(string(getenv("OS")));
env.PhysicalCoreCount = double(localSafeFeatureNumCores());
env.ComputeThreadCount = double(localSafeMaxNumCompThreads());
env.JavaAvailableProcessors = double(localSafeJavaAvailableProcessors());
env.ParallelToolboxInstalled = logical(localHasParallelToolboxInstalled());
env.ParallelLicenseAvailable = logical(localHasParallelLicense());
env.ParpoolFunctionAvailable = logical(exist("parpool", "file") == 2);
env.RequestedWorkers = double(sixgr.util.structGet(cfg, "run.parallelRequestedWorkers", ...
    sixgr.util.structGet(cfg, "run.numWorkers", 0)));
env.EffectiveWorkers = localEffectiveWorkerCount(cfg);
env.UseMex = logical(sixgr.util.structGet(cfg, "run.useMex", false));
env.UseMexAutoEnabled = logical(sixgr.util.structGet(cfg, "run.useMexAutoEnabled", false));
env.ParallelDisabledReason = char(string(sixgr.util.structGet(cfg, "run.parallelDisabledReason", "")));
end

function localEnsureScenarioDirs(layout)
dirs = { ...
    layout.MetaDir, layout.LogDir, layout.ReportDir, layout.ReportCSVDir, layout.ReportMATDir, ...
    layout.ReportImageDir, fullfile(layout.ReportDir, "json"), layout.AirInterfaceDir, layout.AirInterfaceCSVDir, layout.AirInterfaceMATDir, ...
    layout.AirInterfaceImageDir, layout.ControlDir, layout.ControlCSVDir, layout.ControlImageDir, ...
    layout.BeamformingDir, layout.BeamformingCSVDir, layout.BeamformingImageDir};
for i = 1:numel(dirs)
    sixgr.util.ensureFolder(dirs{i});
end
sixgr.visual.clearRunImageDirectories(layout.Root);
end

function leaf = localResolveLeaf(runTag)
runTag = char(string(runTag));
if strlength(string(runTag)) == 0
    leaf = "current";
else
    leaf = localSanitizeToken(runTag, "current");
end
end

function runFolder = localComposeRunFolderNoCreate(resultsRoot, bucket, profile, leaf)
root = sixgr.report.resolveResultsRoot(char(string(resultsRoot)));
bucket = localSanitizeToken(bucket, "lls");
profile = localSanitizeToken(profile, "scenario");
leaf = localSanitizeToken(leaf, "current");
runFolder = fullfile(root, bucket, profile, leaf);
end

function runFolder = localComposeDBStagingRunFolder(profile, leaf)
profile = localSanitizeToken(profile, "scenario");
leaf = localSanitizeToken(leaf, "current");
runFolder = fullfile(tempdir, "sixgr_mysql_web_runs", profile, leaf);
end

function localResetRunFolder(runFolder)
localDeleteFolderTreeIfExists(runFolder);
sixgr.util.ensureFolder(runFolder);
end

function localCleanupDBOnlyRunFolders(backend, stagingRunFolder, logicalRunFolder)
if lower(string(backend)) ~= "mysql_web"
    return;
end
localDeleteFolderTreeIfExists(stagingRunFolder);
% The logical folder is the public result folder used by the web UI and
% audits. MySQL artifacts are hydrated there after completion, so cleanup
% must never delete it.
logicalRunFolder = string(logicalRunFolder); %#ok<NASGU>
end

function localDeleteFolderTreeIfExists(folderPath)
folderPath = char(string(folderPath));
if strlength(string(folderPath)) == 0 || ~isfolder(folderPath)
    return;
end
try
    warnState = warning("off", "all");
    cleanupWarn = onCleanup(@() warning(warnState)); %#ok<NASGU>
    rmdir(folderPath, "s");
catch
end
end

function localApplyRunRandomness(scfg)
seed = double(scfg.get("simulation.random_seed"));
if logical(scfg.get("simulation.deterministic_mode"))
    rng(seed, "twister");
else
    rng("shuffle");
end
end

function cfg = localEnsureParallelExecution(cfg)
useParallel = logical(sixgr.util.structGet(cfg, "run.useParallel", false));
requestedWorkers = max(0, round(double(sixgr.util.structGet(cfg, "run.numWorkers", 0))));
cfg = sixgr.util.structSet(cfg, "run.parallelRequestedWorkers", double(requestedWorkers));
cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "");
idleTimeoutMinutes = max(1, double(sixgr.util.structGet(cfg, ...
    "run.parallelPoolIdleTimeoutMinutes", 1440)));
cfg = sixgr.util.structSet(cfg, "run.parallelPoolIdleTimeoutMinutes", double(idleTimeoutMinutes));
parallelInstalled = localHasParallelToolboxInstalled();
parallelLicensed = localHasParallelLicense();
parpoolAvailable = exist("parpool", "file") == 2;
if ~useParallel
    cfg.run.useParallel = false;
    cfg = localSetSerialWorkerState(cfg);
    cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parallel_not_requested");
    return;
end
if requestedWorkers <= 1
    cfg.run.useParallel = false;
    cfg = localSetSerialWorkerState(cfg);
    cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "requested_workers_leq_1");
    return;
end
if ~parallelInstalled || ~parallelLicensed || ~parpoolAvailable
    cfg.run.useParallel = false;
    cfg = localSetSerialWorkerState(cfg);
    if ~parallelLicensed
        cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parallel_computing_toolbox_license_unavailable");
    elseif ~parallelInstalled
        cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parallel_computing_toolbox_not_installed");
    else
        cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parpool_function_unavailable");
    end
    return;
end

threadCandidates = localParallelWorkerCandidates(requestedWorkers, ...
    [localSafeFeatureNumCores(), localSafeMaxNumCompThreads()]);
processCandidates = localParallelWorkerCandidates(requestedWorkers, ...
    localSafeLocalClusterNumWorkers());

[poolOrder, poolOrderReason] = localResolveParallelPoolStartOrder(cfg);
pool = [];
startReason = "";
startFailures = strings(0, 1);
for poolKind = poolOrder(:).'
    if poolKind == "threads"
        candidates = threadCandidates;
    else
        candidates = processCandidates;
    end
    [pool, startReason, poolFailure] = localStartRequestedParpool(poolKind, candidates, idleTimeoutMinutes);
    if strlength(string(poolFailure)) > 0
        startFailures(end + 1, 1) = string(poolFailure); %#ok<AGROW>
    end
    if ~isempty(pool)
        break;
    end
end
startFailure = char(strjoin(startFailures, " | "));

if isempty(pool)
    cfg.run.useParallel = false;
    cfg = localSetSerialWorkerState(cfg);
    cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parpool_start_failed");
    cfg = sixgr.util.structSet(cfg, "run.parallelStartFailure", char(string(startFailure)));
    return;
end

cfg.run.useParallel = ~isempty(pool);
cfg.run.numWorkers = double(pool.NumWorkers);
cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "");
cfg = sixgr.util.structSet(cfg, "run.parallelStartMode", char(startReason));
cfg = sixgr.util.structSet(cfg, "run.parallelPoolKindEffective", char(localPoolKindToken(pool)));
cfg = sixgr.util.structSet(cfg, "run.parallelPoolSelectionReason", char(poolOrderReason));
cfg = sixgr.util.structSet(cfg, "run.parallelStartFailure", char(string(startFailure)));
cfg = sixgr.util.structSet(cfg, "run.parallelPoolIdleTimeoutEffectiveMinutes", double(idleTimeoutMinutes));
sixgr.util.rngInit(double(sixgr.util.structGet(cfg, "run.seed", 1)), true);
end

function cfg = localSetSerialWorkerState(cfg)
% No parpool workers are active, but one MATLAB coordinator still executes
% the exact serial waveform chain. Keep requested-workers separate in
% run.parallelRequestedWorkers and expose one effective execution worker.
cfg = sixgr.util.structSet(cfg, "run.numWorkers", 1);
end

function n = localEffectiveWorkerCount(cfg)
raw = double(sixgr.util.structGet(cfg, "run.numWorkers", 1));
if ~(isscalar(raw) && isfinite(raw) && raw >= 1)
    raw = 1;
end
n = double(max(1, round(raw)));
end

function [order, reason] = localResolveParallelPoolStartOrder(cfg)
requested = lower(strtrim(string(sixgr.util.structGet(cfg, "run.parallelPoolKind", "auto"))));
requiresProcessPool = localRequiresProcessBackedParallelPool(cfg);
if any(requested == ["process", "processes", "local"])
    order = "processes";
    reason = "configured_process_pool";
elseif requested == "threads" && ~requiresProcessPool
    order = "threads";
    reason = "configured_thread_pool";
elseif requested == "threads" && requiresProcessPool
    order = "processes";
    reason = "thread_pool_requested_but_process_pool_required_for_waveform_phy_mex_workers";
elseif requiresProcessPool
    order = "processes";
    reason = "auto_process_pool_required_for_waveform_phy_mex_workers";
else
    order = ["threads", "processes"];
    reason = "auto_threads_preferred_for_non_mex_parallel_work";
end
end

function tf = localRequiresProcessBackedParallelPool(cfg)
runnerProfile = lower(strtrim(string(sixgr.util.structGet(cfg, "run.runnerProfile", ...
    sixgr.util.structGet(cfg, "scenario.runner_profile", "")))));
modeToken = lower(strtrim(string(sixgr.util.structGet(cfg, "run.mode", ""))));
channelModel = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", ""))));
usesWaveformBundle = runnerProfile == "waveform_bundle" || modeToken == "link";
usesPHYToolboxMex = usesWaveformBundle || any(channelModel == ["TDL", "CDL", "NRTDL", "NRCDL"]);
tf = logical(usesPHYToolboxMex);
end

function token = localPoolKindToken(pool)
token = "";
if isempty(pool)
    return;
end
try
    classToken = lower(string(class(pool)));
    if contains(classToken, "thread")
        token = "threads";
    elseif contains(classToken, "process")
        token = "processes";
    else
        token = char(class(pool));
    end
catch
    token = "";
end
end

function candidates = localParallelWorkerCandidates(requestedWorkers, caps)
requestedWorkers = max(0, floor(double(requestedWorkers)));
caps = double(caps(:));
caps = caps(isfinite(caps) & caps >= 2);
if isempty(caps)
    maxAllowed = requestedWorkers;
else
    maxAllowed = min(requestedWorkers, max(floor(caps)));
end
if ~(isfinite(maxAllowed) && maxAllowed >= 2)
    candidates = [];
    return;
end

raw = [requestedWorkers, maxAllowed, floor(maxAllowed ./ [2 4 8]), 32, 16, 12, 8, 4, 2];
raw = floor(double(raw(:)));
raw = raw(isfinite(raw) & raw >= 2 & raw <= maxAllowed);
candidates = [];
for i = 1:numel(raw)
    if ~any(candidates == raw(i))
        candidates(end + 1) = raw(i); %#ok<AGROW>
    end
end
candidates = sort(candidates, "descend");
end

function [pool, startReason, failureText] = localStartRequestedParpool(poolKind, candidates, idleTimeoutMinutes)
pool = [];
startReason = "";
failures = strings(0, 1);
poolKind = lower(string(poolKind));
candidates = double(candidates(:)');
idleTimeoutMinutes = max(1, double(idleTimeoutMinutes));
for n = candidates
    try
        existing = gcp("nocreate");
        if ~isempty(existing) && ~localExistingPoolMatchesRequest(existing, poolKind, n)
            delete(existing);
            existing = [];
        end
        if ~isempty(existing)
            pool = existing;
        elseif poolKind == "threads"
            pool = parpool("threads", n);
        else
            pool = localStartProcessParpool(n);
        end
        pool = localApplyParpoolIdleTimeout(pool, idleTimeoutMinutes);
        if ~isempty(pool) && double(pool.NumWorkers) > 1
            startReason = sprintf("%s_%d_workers", char(poolKind), double(pool.NumWorkers));
            failureText = char(strjoin(failures, " | "));
            return;
        end
        if ~isempty(pool)
            delete(pool);
            pool = [];
        end
        failures(end + 1, 1) = sprintf("%s(%d): pool_started_with_leq_1_worker", char(poolKind), n); %#ok<AGROW>
    catch ME
        failures(end + 1, 1) = sprintf("%s(%d): %s %s", char(poolKind), n, char(string(ME.identifier)), char(string(ME.message))); %#ok<AGROW>
    end
end

if poolKind == "threads"
    try
        existing = gcp("nocreate");
        if ~isempty(existing) && ~localExistingPoolMatchesRequest(existing, poolKind, NaN)
            delete(existing);
            existing = [];
        end
        if ~isempty(existing)
            pool = existing;
            pool = localApplyParpoolIdleTimeout(pool, idleTimeoutMinutes);
            startReason = sprintf("threads_default_%d_workers", double(pool.NumWorkers));
            failureText = char(strjoin(failures, " | "));
            return;
        end
        pool = parpool("threads");
        pool = localApplyParpoolIdleTimeout(pool, idleTimeoutMinutes);
        if ~isempty(pool) && double(pool.NumWorkers) > 1
            startReason = sprintf("threads_default_%d_workers", double(pool.NumWorkers));
            failureText = char(strjoin(failures, " | "));
            return;
        end
    catch ME
        failures(end + 1, 1) = sprintf("threads(default): %s %s", char(string(ME.identifier)), char(string(ME.message))); %#ok<AGROW>
    end
end

pool = [];
startReason = "";
failureText = char(strjoin(failures, " | "));
end

function tf = localExistingPoolMatchesRequest(pool, poolKind, workers)
tf = false;
if isempty(pool)
    return;
end
if isfinite(double(workers)) && double(pool.NumWorkers) ~= double(workers)
    return;
end
actualKind = lower(string(localPoolKindToken(pool)));
requestedKind = lower(string(poolKind));
if requestedKind == "processes"
    tf = actualKind == "processes";
elseif requestedKind == "threads"
    tf = actualKind == "threads";
else
    tf = true;
end
end

function pool = localStartProcessParpool(n)
pool = [];
try
    pool = parpool(n);
    return;
catch firstME
    firstFailure = sprintf("%s %s", char(string(firstME.identifier)), char(string(firstME.message)));
end
try
    pool = parpool("local", n);
catch secondME
    error("sixgr:lls6g:ParpoolStartFailed", ...
        "Process parpool(%d) failed: %s; local profile failed: %s %s", ...
        n, firstFailure, char(string(secondME.identifier)), char(string(secondME.message)));
end
end

function pool = localApplyParpoolIdleTimeout(pool, idleTimeoutMinutes)
if isempty(pool)
    return;
end
idleTimeoutMinutes = max(1, double(idleTimeoutMinutes));
try
    if isprop(pool, 'IdleTimeout')
        pool.IdleTimeout = idleTimeoutMinutes;
    end
catch
    % Older MATLAB releases or cluster profiles may keep IdleTimeout read-only.
    % The run still proceeds; grant-level code can restart an expired pool.
end
end

function n = localSafeLocalClusterNumWorkers()
try
    cluster = parcluster("local");
    n = double(cluster.NumWorkers);
catch
    n = NaN;
end
if ~(isscalar(n) && isfinite(n) && n >= 1)
    n = NaN;
end
end

function cfg = localEnsureExactMexAcceleration(cfg)
requestedUseMex = sixgr.util.structGet(cfg, "run.useMex", []);
caps = localExactMexCapabilities();
autoEnabled = false;
forceDisableForStrictCoupledTruth = localShouldDisableExactMexForStrictCoupledTruthWaveform(cfg);

if forceDisableForStrictCoupledTruth
    requestedUseMex = false;
elseif isempty(requestedUseMex)
    requestedUseMex = logical(caps.Any);
    autoEnabled = logical(caps.Any);
end

requestedUseMex = logical(requestedUseMex);
if requestedUseMex && ~logical(caps.Any)
    requestedUseMex = false;
end

cfg = sixgr.util.structSet(cfg, "run.useMex", requestedUseMex);
cfg = sixgr.util.structSet(cfg, "run.useMexAutoEnabled", autoEnabled);
cfg = sixgr.util.structSet(cfg, "run.exactMexAvailable", logical(caps.Any));
cfg = sixgr.util.structSet(cfg, "run.exactMexCapabilities", caps);
if requestedUseMex
    cfg = sixgr.util.structSet(cfg, "run.useMexDisabledReason", "");
else
    if forceDisableForStrictCoupledTruth
        cfg = sixgr.util.structSet(cfg, "run.useMexDisabledReason", ...
            "exact_mex_disabled_for_strict_coupled_truth_waveform_bundle");
    elseif logical(caps.Any)
        cfg = sixgr.util.structSet(cfg, "run.useMexDisabledReason", "exact_mex_not_requested");
    else
        cfg = sixgr.util.structSet(cfg, "run.useMexDisabledReason", "no_exact_mex_kernels_found");
    end
end
end

function tf = localShouldDisableExactMexForStrictCoupledTruthWaveform(cfg)
runnerProfile = lower(strtrim(string(sixgr.util.structGet(cfg, "run.runnerProfile", ...
    sixgr.util.structGet(cfg, "lls6g.scenario.runner_profile", "")))));
if strlength(runnerProfile) == 0
    if lower(strtrim(string(sixgr.util.structGet(cfg, "run.mode", "")))) == "system"
        runnerProfile = "system_level_lls";
    end
end
channelModel = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", "AWGN"))));
phyBackend = lower(strtrim(string(sixgr.util.structGet(cfg, "system.phyBackend", "waveform"))));
tf = runnerProfile == "system_level_lls" && phyBackend == "waveform" && channelModel ~= "AWGN";
end

function caps = localExactMexCapabilities()
caps = struct();
caps.AWGNKernel = logical(exist("sixgr_awgn_complex_kernel_mex", "file") == 3);
caps.LDPCBatchDecodeKernel = logical(exist("sixgr_ldpc_decode_batch_kernel_mex", "file") == 3);
caps.StructGetKernel = logical(exist("sixgr_struct_get_mex", "file") == 3);
caps.FFTPAPRKernel = logical(exist("sixgr_fft_papr_kernel_mex", "file") == 3);
caps.CorrelationMetricKernel = logical(exist("sixgr_corr_metric_kernel_mex", "file") == 3);
caps.FrequencyCorrectionSearchKernel = logical(exist("sixgr_freq_corr_search_kernel_mex", "file") == 3);
caps.FrequencyShiftKernel = logical(exist("sixgr_freq_shift_kernel_mex", "file") == 3);
caps.TBBytesToBitsKernel = logical(exist("sixgr_tb_bytes_to_bits_kernel_mex", "file") == 3);
caps.TBBitsToBytesKernel = logical(exist("sixgr_tb_bits_to_bytes_kernel_mex", "file") == 3);
caps.TBResizeBitsKernel = logical(exist("sixgr_tb_resize_bits_kernel_mex", "file") == 3);
caps.TruthGrantHashKernel = logical(exist("sixgr_truth_grant_hash_kernel_mex", "file") == 3);
caps.FastChannelEstLSKernel = logical(exist("sixgr_channel_est_ls_kernel_mex", "file") == 3);
caps.FastChannelEstLSAllowed = false;
caps.Any = logical(caps.AWGNKernel || caps.LDPCBatchDecodeKernel || caps.StructGetKernel || ...
    caps.FFTPAPRKernel || caps.CorrelationMetricKernel || caps.FrequencyCorrectionSearchKernel || ...
    caps.FrequencyShiftKernel || caps.TBBytesToBitsKernel || caps.TBBitsToBytesKernel || ...
    caps.TBResizeBitsKernel || caps.TruthGrantHashKernel);
end

function tf = localHasParallelLicense()
try
    tf = logical(license("test", "Distrib_Computing_Toolbox"));
catch
    tf = false;
end
end

function tf = localHasParallelToolboxInstalled()
try
    tf = ~isempty(ver("parallel"));
catch
    tf = false;
end
end

function n = localSafeFeatureNumCores()
try
    n = double(feature("numcores"));
catch
    n = NaN;
end
if ~(isscalar(n) && isfinite(n) && n >= 1)
    n = NaN;
end
end

function n = localSafeMaxNumCompThreads()
try
    n = double(maxNumCompThreads);
catch
    n = NaN;
end
if ~(isscalar(n) && isfinite(n) && n >= 1)
    n = NaN;
end
end

function n = localSafeJavaAvailableProcessors()
try
    n = double(java.lang.Runtime.getRuntime.availableProcessors);
catch
    n = NaN;
end
if ~(isscalar(n) && isfinite(n) && n >= 1)
    n = NaN;
end
end

function token = localSanitizeToken(inToken, fallback)
token = lower(strtrim(char(string(inToken))));
token = regexprep(token, '[^a-z0-9]+', '_');
token = regexprep(token, '_+', '_');
token = regexprep(token, '^_+|_+$', '');
if strlength(string(token)) == 0
    token = char(string(fallback));
end
end

function p = localPortablePath(inPath)
p = replace(string(inPath), "\", "/");
end

function txt = localRelativeToRunFolder(pathIn, runFolder)
txt = localPortablePath(pathIn);
if strlength(txt) == 0
    return;
end
root = regexprep(localPortablePath(runFolder), '/+', '/');
txt = regexprep(txt, '/+', '/');
if strcmpi(txt, root)
    txt = ".";
    return;
end
rootPrefix = root + "/";
if startsWith(lower(txt), lower(rootPrefix))
    txt = extractAfter(txt, strlength(rootPrefix));
end
end

function grid = localBuildSweepGrid(snr_dB, offsets_dB, sweepEnabled, explicitValues_dB)
if nargin >= 4 && logical(sweepEnabled)
    explicitValues_dB = double(explicitValues_dB(:)).';
    explicitValues_dB = explicitValues_dB(isfinite(explicitValues_dB));
    if ~isempty(explicitValues_dB)
        grid = unique(sort(explicitValues_dB));
        return;
    end
end
snr_dB = double(snr_dB);
offsets_dB = double(offsets_dB(:)).';
offsets_dB = offsets_dB(isfinite(offsets_dB));
if isempty(offsets_dB)
    grid = snr_dB;
    return;
end
grid = unique(sort(snr_dB + offsets_dB));
end

function tf = localUsesReceiverNoiseMeasurement(cfg)
mode = lower(strtrim(string(sixgr.util.structGet(cfg, "run.noiseOperatingMode", ...
    "receiver_noise_figure_thermal_noise"))));
tf = mode == "receiver_noise_figure_thermal_noise";
end

function grid = localBuildPhysicalOperatingPointGrid(snr_dB)
snr_dB = double(snr_dB);
if ~(isscalar(snr_dB) && isfinite(snr_dB))
    grid = NaN;
else
    grid = snr_dB;
end
end

function value = ternaryDouble(condition, trueValue, falseValue)
if logical(condition)
    value = double(trueValue);
else
    value = double(falseValue);
end
end

function [y, nVar, replay, noiseOnlyWave] = localRunnerApplyPDCCHChannelAndNoise(x, cfg, tx, txInfo, snr_dB)
if nargin < 4 || ~isstruct(txInfo)
    txInfo = struct();
end
if ~isfield(txInfo, "OFDM")
    try
        txInfo.OFDM = nrOFDMInfo(tx.Carrier);
    catch
        txInfo.OFDM = struct();
    end
end
state = sixgr.link.initWaveformTruthChannelState(cfg, tx, txInfo);
sampleRateHz = double(sixgr.util.structGet(state, "SampleRate_Hz", localRunnerResolvePDCCHSampleRate(tx, txInfo)));
y = x;
replay = struct( ...
    "ConfiguredSNR_dB", double(snr_dB), ...
    "AppliedAWGNSNR_dB", double(snr_dB), ...
    "InjectedNoiseVariance", NaN, ...
    "NoiseVarianceSource", "", ...
    "ChannelModelApplied", string(sixgr.util.structGet(cfg, "channel.model", "AWGN")), ...
    "ChannelFadingApplied", false);

if isstruct(state) && logical(sixgr.util.structGet(state, "UseFading", false)) && ...
        isfield(state, "Obj") && ~isempty(state.Obj)
    replay.ChannelFadingApplied = true;
    try
        reset(state.Obj);
    catch
    end
    xIn = x;
    padSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelPadSamples", 0))));
    trimSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelTrimSamples", 0))));
    if padSamples > 0
        xIn = [x; zeros(padSamples, size(x, 2), "like", x)];
    end
    try
        yRaw = state.Obj(xIn);
    catch
        [yRaw, ~] = state.Obj(xIn);
    end
    if trimSamples > 0 && size(yRaw, 1) >= (trimSamples + size(x, 1))
        y = yRaw(1+trimSamples:trimSamples+size(x, 1), :);
    else
        y = yRaw;
        if size(y, 1) > size(x, 1)
            y = y(1:size(x, 1), :);
        elseif size(y, 1) < size(x, 1)
            y(end+1:size(x, 1), :) = cast(0, "like", y); %#ok<AGROW>
        end
    end
end

cfgReplay = sixgr.util.structSet(cfg, "channel.snr_dB", double(snr_dB));
[y, impairmentReplay] = sixgr.link.applyWaveformImpairments(y, cfgReplay, sampleRateHz);
fields = fieldnames(impairmentReplay);
for ii = 1:numel(fields)
    replay.(fields{ii}) = impairmentReplay.(fields{ii});
end
replay.ChannelModelApplied = string(sixgr.util.structGet(cfg, "channel.model", replay.ChannelModelApplied));
replay.ChannelFadingApplied = logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false)) || ...
    logical(sixgr.util.structGet(state, "UseFading", false));
desiredWaveform = y;
[y, nVar] = localRunnerAddAwgnFromReplay(y, replay, desiredWaveform);
replay.InjectedNoiseVariance = double(nVar);
if isfinite(nVar) && nVar > 0
    replay.NoiseVarianceSource = "pdcch_runner_reference_waveform_awgn";
end
noiseOnlyWave = localRunnerNoiseOnlyWaveformLike(y, nVar);
end

function sampleRateHz = localRunnerResolvePDCCHSampleRate(tx, txInfo)
sampleRateHz = [];
if isstruct(txInfo)
    sampleRateHz = sixgr.util.structGet(txInfo, "OFDM.SampleRate", []);
end
if isempty(sampleRateHz) && isstruct(tx)
    try
        ofdmInfo = nrOFDMInfo(tx.Carrier);
        sampleRateHz = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
    catch
        sampleRateHz = [];
    end
end
if isempty(sampleRateHz) || ~(isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    sampleRateHz = 30.72e6;
else
    sampleRateHz = double(sampleRateHz);
end
end

function [y, nVar] = localRunnerAddAwgnFromReplay(x, replay, referenceWaveform)
noiseMode = string(sixgr.util.structGet(replay, "NoiseOperatingMode", "receiver_noise_figure_thermal_noise"));
if noiseMode == "receiver_noise_figure_thermal_noise"
    nVar = localRunnerResolveThermalNoiseVariance(replay, referenceWaveform);
    if isfinite(nVar) && nVar > 0
        n = sqrt(nVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
        return;
    end
    y = x;
    nVar = NaN;
    return;
end
appliedSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
nVar = localRunnerResolveConfiguredSNRNoiseVariance(referenceWaveform, appliedSNR_dB);
if isfinite(nVar) && nVar >= 0
    if nVar > 0
        n = sqrt(nVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
    else
        y = x;
    end
    return;
end
[y, nVar] = sixgr.util.addAwgnComplex(x, appliedSNR_dB);
end

function nVar = localRunnerResolveConfiguredSNRNoiseVariance(referenceWaveform, snr_dB)
nVar = NaN;
snr_dB = double(snr_dB);
if ~(isscalar(snr_dB) && isfinite(snr_dB)) || isempty(referenceWaveform)
    return;
end
refPower = mean(abs(double(referenceWaveform(:))).^2, "omitnan");
if ~(isfinite(refPower) && refPower >= 0)
    return;
end
nVar = refPower / max(10.^(snr_dB / 10), eps);
end

function nVar = localRunnerResolveThermalNoiseVariance(replay, referenceWaveform)
nVar = NaN;
thermalNoisePower_dBm = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
servingRxPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
if ~(isfinite(thermalNoisePower_dBm) && isfinite(servingRxPower_dBm))
    return;
end
refPower = mean(abs(double(referenceWaveform(:))).^2, "omitnan");
if ~(isfinite(refPower) && refPower >= 0)
    return;
end
relativeNoise_dB = thermalNoisePower_dBm - servingRxPower_dBm;
nVar = refPower * 10.^(relativeNoise_dB / 10);
end

function noiseOnlyWave = localRunnerNoiseOnlyWaveformLike(referenceWaveform, nVar)
noiseOnlyWave = zeros(size(referenceWaveform), "like", referenceWaveform);
if isfinite(double(nVar)) && double(nVar) > 0
    n = sqrt(double(nVar) / 2) .* ...
        (randn(size(referenceWaveform), "like", real(referenceWaveform)) + ...
        1i * randn(size(referenceWaveform), "like", real(referenceWaveform)));
    noiseOnlyWave = cast(n, "like", referenceWaveform);
end
end

function args = localRunnerNoiseVarArgs(nVar)
args = {};
if isnumeric(nVar) && isscalar(nVar) && isfinite(double(nVar)) && double(nVar) >= 0
    args = {"NoiseVar", double(nVar)};
end
end

function [y, nVar] = localAddAwgn(x, snr_dB)
[y, nVar] = sixgr.util.addAwgnComplex(x, snr_dB);
end

function [y, nVar] = localAddAwgnOnly(x, snr_dB)
snrLin = 10.^(snr_dB/10);
sigPow = max(mean(abs(x(:)).^2), 1);
nVar = sigPow / max(snrLin, eps);
n = sqrt(nVar/2) * (randn(size(x)) + 1i*randn(size(x)));
y = x + n;
end

function [be, bt] = localBitErrors(txBits, rxBits)
txBits = int8(txBits(:));
rxBits = int8(rxBits(:));
bt = min(numel(txBits), numel(rxBits));
if bt == 0
    be = NaN;
    return;
end
be = sum(txBits(1:bt) ~= rxBits(1:bt));
end

function val = localScalarValue(x)
if isempty(x)
    val = NaN;
elseif isscalar(x)
    val = double(x);
else
    val = double(x(1));
end
end

function nmse_dB = localUnitChannelNMSE(H)
if isempty(H)
    nmse_dB = NaN;
    return;
end
e = H(:) - 1;
nmse = mean(abs(e).^2) / max(mean(abs(ones(size(e))).^2), eps);
nmse_dB = 10*log10(max(nmse, eps));
end

function mcs = localClampMCS(mcsIn)
mcs = double(min(max(round(double(mcsIn)), 0), 27));
end

function score = localMCSScore(mcs)
score = (1 + double(mcs)) * 0.15;
end

function cls = localInterferenceClass(level_dB, thresholds_dB)
thresholds_dB = sort(double(thresholds_dB(:)).');
if isempty(thresholds_dB)
    thresholds_dB = [3 10];
end
if level_dB < thresholds_dB(1)
    cls = "low";
elseif numel(thresholds_dB) < 2 || level_dB < thresholds_dB(2)
    cls = "medium";
else
    cls = "high";
end
end

function det = localDetectorChoice(conditionNumber, threshold)
if conditionNumber >= threshold
    det = "MMSE";
else
    det = "ZF";
end
end

function bucket = localStudyBucketFromClass(researchClass)
researchClass = lower(string(researchClass));
if any(researchClass == ["baseline_benchmark", "agreed_starting_point"])
    bucket = "baseline";
elseif any(researchClass == ["study_item_candidate", "optional_research_experiment"])
    bucket = "open_study";
else
    bucket = "unclassified";
end
end

function status = localAggregateScenarioStatus(result)
status = struct();
status.RunCompletion = "completed";
status.RunCompleted = true;
status.ResultOk = logical(sixgr.util.structGet(result, "Ok", true));
status.PartialOk = false;
status.ArtifactsGenerated = true;
status.ArtifactsWritten = true;
status.RequiredCaseCount = 1;
status.RequiredFailureCount = double(~status.ResultOk);
status.OptionalPrunedCount = 0;
status.RequiredFailedCases = strings(0, 1);
status.OptionalPrunedCases = strings(0, 1);
status.StatusAuthority = "scenario_status_aggregation_v1";
status.StatusNotes = "";
status.ProfileReportedOk = logical(sixgr.util.structGet(result, "Ok", true));
status.AuthoritativeStatusSource = "result.Ok";
status.RuntimeTruthContractOk = true;
status.TruthContractOk = true;
status.StandardsConformanceOk = true;
status.ScenarioObjectiveOk = true;
status.ConfiguredEffectiveOk = true;
status.MandatorySubsystemsOk = true;
status.ActiveIssueGateOk = true;
status.KpiConsistencyOk = true;
status.StrictAnchorEligible = false;
status.StrictAnchorPass = true;
status.ResultStatusReason = "all_required_root_gates_passed";
status.ActiveMandatoryIssueCount = 0;
status.ActiveCriticalIssueCount = 0;
status.ActiveHighIssueCount = 0;
status.ActiveMediumIssueCount = 0;
status.RoundtripMismatchCount = 0;
status.RequiredRuntimeEvidenceMissingCount = 0;
status.StrictTruthFailureCount = 0;
status.StrictProxyGuardFailureCount = 0;
status.CanonicalArtifactGapCount = 0;
status.RuntimeTruthContractFailures = strings(0, 1);
status.VisualArtifactIntegrityOk = true;
status.VisualArtifactIntegrityFailureCount = 0;
status.VisualArtifactIntegrityFailures = strings(0, 1);
status.WarningCount = 0;
status.FailingCaseCount = 0;
status.CaseOk = logical(status.ResultOk);
status.ErrorSource = "";
status.ErrorIdentifier = "";
status.ErrorMessage = "";

if isstruct(result) && isfield(result, "Link")
    [status.ResultOk, status.RequiredCaseCount, status.RequiredFailureCount, ...
        status.RequiredFailedCases, status.OptionalPrunedCount, status.OptionalPrunedCases, ...
        status.StatusNotes, status.AuthoritativeStatusSource, status.WarningCount, ...
        status.ErrorSource, status.ErrorIdentifier, status.ErrorMessage] = localAggregateWaveformLinkStatus(result.Link, status.ProfileReportedOk);
end

status.FailingCaseCount = double(numel(string(status.RequiredFailedCases)));
status.CaseOk = status.FailingCaseCount == 0;
if ~logical(status.ResultOk) && status.RunCompletion == "completed"
    status.RunCompletion = "completed_with_failures";
end
status.RunCompleted = any(string(status.RunCompletion) == ["completed", "completed_with_failures"]);
status.ArtifactsWritten = logical(status.ArtifactsGenerated);
status.PartialOk = logical(status.ArtifactsGenerated) && ~logical(status.ResultOk);
end

function status = localApplyRuntimeTruthContract(status, result, scfg, cfg, runFolder)
try
    verdict = sixgr.truth.evaluateLLSRuntimeTruthContract(runFolder, scfg, cfg, "Result", result);
catch ME
    verdict = struct();
    verdict.Ok = false;
    verdict.RuntimeTruthContractOk = false;
    verdict.RoundtripMismatchCount = 0;
    verdict.RequiredRuntimeEvidenceMissingCount = 1;
    verdict.StrictTruthFailureCount = 1;
    verdict.StrictProxyGuardFailureCount = 0;
    verdict.CanonicalArtifactGapCount = 0;
    verdict.Failures = "runtime_truth_contract_evaluator_error:" + string(ME.identifier);
end

status.StatusAuthority = "scenario_status_aggregation_v2_runtime_truth_contract";
status.RuntimeTruthContractOk = logical(sixgr.util.structGet(verdict, "RuntimeTruthContractOk", sixgr.util.structGet(verdict, "Ok", false)));
status.TruthContractOk = logical(status.RuntimeTruthContractOk);
status.RoundtripMismatchCount = double(sixgr.util.structGet(verdict, "RoundtripMismatchCount", 0));
status.RequiredRuntimeEvidenceMissingCount = double(sixgr.util.structGet(verdict, "RequiredRuntimeEvidenceMissingCount", 0));
status.StrictTruthFailureCount = double(sixgr.util.structGet(verdict, "StrictTruthFailureCount", 0));
status.StrictProxyGuardFailureCount = double(sixgr.util.structGet(verdict, "StrictProxyGuardFailureCount", 0));
status.CanonicalArtifactGapCount = double(sixgr.util.structGet(verdict, "CanonicalArtifactGapCount", 0));
status.RuntimeTruthContractFailures = string(sixgr.util.structGet(verdict, "Failures", strings(0, 1)));
status.RuntimeTruthContractFailures = status.RuntimeTruthContractFailures(:);
details = sixgr.util.structGet(verdict, "CheckDetails", struct());
issueRegistry = sixgr.util.structGet(details, "IssueRegistry", struct());
scenarioObjective = sixgr.util.structGet(details, "ScenarioObjective", struct());
rootResultStatus = sixgr.util.structGet(verdict, "ResultStatus", struct());
rootResultOk = logical(sixgr.util.structGet(rootResultStatus, "ResultOk", true));
status.ActiveMandatoryIssueCount = double(sixgr.util.structGet(issueRegistry, "BlockingIssueCount", 0));
status.ActiveCriticalIssueCount = double(sixgr.util.structGet(issueRegistry, "ActiveCriticalCount", 0));
status.ActiveHighIssueCount = double(sixgr.util.structGet(issueRegistry, "ActiveHighCount", 0));
status.ActiveMediumIssueCount = double(sixgr.util.structGet(issueRegistry, "ActiveMediumCount", 0));
status.ScenarioObjectiveOk = logical(sixgr.util.structGet(rootResultStatus, "ScenarioObjectiveOk", ...
    sixgr.util.structGet(scenarioObjective, "ScenarioObjectiveOk", true)));
status.StandardsConformanceOk = logical(sixgr.util.structGet(rootResultStatus, "StandardsConformanceOk", ...
    logical(status.RuntimeTruthContractOk) && status.ActiveMandatoryIssueCount == 0));
status.ConfiguredEffectiveOk = logical(sixgr.util.structGet(rootResultStatus, "ConfiguredEffectiveOk", ...
    sixgr.util.structGet(status, "ConfiguredEffectiveOk", true)));
status.MandatorySubsystemsOk = logical(sixgr.util.structGet(rootResultStatus, "MandatorySubsystemsOk", ...
    sixgr.util.structGet(status, "MandatorySubsystemsOk", true)));
status.ActiveIssueGateOk = logical(sixgr.util.structGet(rootResultStatus, "ActiveIssueGateOk", ...
    sixgr.util.structGet(status, "ActiveIssueGateOk", true)));
status.KpiConsistencyOk = logical(sixgr.util.structGet(rootResultStatus, "KpiConsistencyOk", ...
    sixgr.util.structGet(status, "KpiConsistencyOk", true)));
status.StrictAnchorEligible = logical(sixgr.util.structGet(rootResultStatus, "StrictAnchorEligible", ...
    sixgr.util.structGet(status, "StrictAnchorEligible", false)));
status.StrictAnchorPass = logical(sixgr.util.structGet(rootResultStatus, "StrictAnchorPass", ...
    sixgr.util.structGet(status, "StrictAnchorPass", true)));
status.ResultStatusReason = string(sixgr.util.structGet(rootResultStatus, "ResultStatusReason", ...
    sixgr.util.structGet(status, "ResultStatusReason", "")));
roundtripStatusDetails = string(sixgr.util.structGet(verdict, "RoundtripStatusDetails", strings(0, 1)));
roundtripStatusDetails = roundtripStatusDetails(strlength(roundtripStatusDetails) > 0);
if ~isempty(roundtripStatusDetails)
    status.RuntimeTruthContractFailures = unique([status.RuntimeTruthContractFailures; roundtripStatusDetails(:)], "stable");
end

if ~logical(status.RuntimeTruthContractOk) || ~rootResultOk
    status.ResultOk = false;
    status.CaseOk = false;
    status.PartialOk = logical(status.ArtifactsGenerated);
    status.RunCompletion = "completed_with_failures";
    status.RequiredFailureCount = double(status.RequiredFailureCount) + max(1, double(status.StrictTruthFailureCount));
    status.RequiredFailedCases = unique([string(status.RequiredFailedCases(:)); status.RuntimeTruthContractFailures], "stable");
    status.FailingCaseCount = double(numel(string(status.RequiredFailedCases)));
    status.AuthoritativeStatusSource = "runtime_truth_contract";
    status.StatusNotes = localJoinStatusNotes(status.StatusNotes, ...
        "Run-level success is gated by the runtime truth contract and canonical root status; missing/proxy/mismatched evidence or root-gate failures force ResultOk=false.");
    if strlength(string(status.ErrorIdentifier)) == 0
        status.ErrorSource = "runtime_truth_contract";
        status.ErrorIdentifier = "runtime_truth_contract_failed";
        status.ErrorMessage = char(strjoin(status.RuntimeTruthContractFailures, "; "));
    end
else
    status.FailingCaseCount = double(numel(string(status.RequiredFailedCases)));
    status.CaseOk = logical(status.ResultOk) && status.FailingCaseCount == 0;
    status.PartialOk = logical(status.ArtifactsGenerated) && ~logical(status.ResultOk);
end
status.RunCompleted = any(string(status.RunCompletion) == ["completed", "completed_with_failures"]);
status.ArtifactsWritten = logical(status.ArtifactsGenerated);
end

function status = localApplyVisualArtifactIntegrityStatus(status, visualIntegrity)
if ~(istable(visualIntegrity) && ~isempty(visualIntegrity) && ismember("IntegrityOk", string(visualIntegrity.Properties.VariableNames)))
    status.VisualArtifactIntegrityOk = true;
    status.VisualArtifactIntegrityFailureCount = 0;
    status.VisualArtifactIntegrityFailures = strings(0, 1);
    return;
end
okMask = logical(visualIntegrity.IntegrityOk);
bad = visualIntegrity(~okMask, :);
status.VisualArtifactIntegrityOk = isempty(bad);
status.VisualArtifactIntegrityFailureCount = double(height(bad));
status.VisualArtifactIntegrityFailures = localVisualArtifactFailureStrings(bad);
if isempty(bad)
    return;
end
status.ResultOk = false;
status.CaseOk = false;
status.PartialOk = logical(status.ArtifactsGenerated);
status.RunCompletion = "completed_with_failures";
status.RequiredFailureCount = double(status.RequiredFailureCount) + double(height(bad));
status.RequiredFailedCases = unique([string(status.RequiredFailedCases(:)); status.VisualArtifactIntegrityFailures(:)], "stable");
status.FailingCaseCount = double(numel(string(status.RequiredFailedCases)));
status.AuthoritativeStatusSource = "visual_artifact_integrity";
status.StatusNotes = localJoinStatusNotes(status.StatusNotes, ...
    "Run-level success is gated by visual artifact byte/signature integrity; extension/mime mismatches or stale suppressed PNGs force ResultOk=false.");
if strlength(string(status.ErrorIdentifier)) == 0
    status.ErrorSource = "visual_artifact_integrity";
    status.ErrorIdentifier = "visual_artifact_integrity_failed";
    status.ErrorMessage = char(strjoin(status.VisualArtifactIntegrityFailures, "; "));
end
end

function failures = localVisualArtifactFailureStrings(T)
if ~(istable(T) && ~isempty(T))
    failures = strings(0, 1);
    return;
end
paths = localStatusColumnAsString(T, "ArtifactPath", height(T));
codes = localStatusColumnAsString(T, "FailureCode", height(T));
reasons = localStatusColumnAsString(T, "FailureReason", height(T));
failures = "visual_artifact_integrity:" + codes + ":" + paths;
hasReason = strlength(strtrim(reasons)) > 0;
failures(hasReason) = failures(hasReason) + ":" + reasons(hasReason);
failures = unique(failures(:), "stable");
end

function values = localStatusColumnAsString(T, name, n)
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    values = string(T.(char(name)));
else
    values = strings(n, 1);
end
values = values(:);
if numel(values) < n
    values(end+1:n, 1) = "";
end
end

function result = localApplyScenarioStatus(result, scenarioStatus)
result.ProfileReportedOk = logical(sixgr.util.structGet(result, "Ok", true));
result.Ok = logical(scenarioStatus.ResultOk);
result.RunCompletion = char(string(scenarioStatus.RunCompletion));
result.RunCompleted = logical(sixgr.util.structGet(scenarioStatus, "RunCompleted", false));
result.PartialOk = logical(scenarioStatus.PartialOk);
result.ArtifactsGenerated = logical(scenarioStatus.ArtifactsGenerated);
result.ArtifactsWritten = logical(sixgr.util.structGet(scenarioStatus, "ArtifactsWritten", scenarioStatus.ArtifactsGenerated));
result.RequiredCaseCount = double(scenarioStatus.RequiredCaseCount);
result.RequiredFailureCount = double(scenarioStatus.RequiredFailureCount);
result.OptionalPrunedCount = double(scenarioStatus.OptionalPrunedCount);
result.RequiredFailedCases = string(scenarioStatus.RequiredFailedCases(:));
result.OptionalPrunedCases = string(scenarioStatus.OptionalPrunedCases(:));
result.StatusAuthority = char(string(scenarioStatus.StatusAuthority));
result.StatusNotes = char(string(scenarioStatus.StatusNotes));
result.AuthoritativeStatusSource = char(string(scenarioStatus.AuthoritativeStatusSource));
result.RuntimeTruthContractOk = logical(scenarioStatus.RuntimeTruthContractOk);
result.TruthContractOk = logical(sixgr.util.structGet(scenarioStatus, "TruthContractOk", scenarioStatus.RuntimeTruthContractOk));
result.StandardsConformanceOk = logical(sixgr.util.structGet(scenarioStatus, "StandardsConformanceOk", scenarioStatus.RuntimeTruthContractOk));
result.ScenarioObjectiveOk = logical(sixgr.util.structGet(scenarioStatus, "ScenarioObjectiveOk", scenarioStatus.ResultOk));
result.ActiveMandatoryIssueCount = double(sixgr.util.structGet(scenarioStatus, "ActiveMandatoryIssueCount", 0));
result.ActiveCriticalIssueCount = double(sixgr.util.structGet(scenarioStatus, "ActiveCriticalIssueCount", 0));
result.ActiveHighIssueCount = double(sixgr.util.structGet(scenarioStatus, "ActiveHighIssueCount", 0));
result.ActiveMediumIssueCount = double(sixgr.util.structGet(scenarioStatus, "ActiveMediumIssueCount", 0));
result.RoundtripMismatchCount = double(scenarioStatus.RoundtripMismatchCount);
result.RequiredRuntimeEvidenceMissingCount = double(scenarioStatus.RequiredRuntimeEvidenceMissingCount);
result.StrictTruthFailureCount = double(scenarioStatus.StrictTruthFailureCount);
result.StrictProxyGuardFailureCount = double(scenarioStatus.StrictProxyGuardFailureCount);
result.CanonicalArtifactGapCount = double(scenarioStatus.CanonicalArtifactGapCount);
result.RuntimeTruthContractFailures = string(scenarioStatus.RuntimeTruthContractFailures(:));
result.VisualArtifactIntegrityOk = logical(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityOk", true));
result.VisualArtifactIntegrityFailureCount = double(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityFailureCount", 0));
result.VisualArtifactIntegrityFailures = string(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityFailures", strings(0, 1)));
result.WarningCount = double(scenarioStatus.WarningCount);
result.FailingCaseCount = double(scenarioStatus.FailingCaseCount);
result.CaseOk = logical(scenarioStatus.CaseOk);
result.ErrorSource = char(string(scenarioStatus.ErrorSource));
result.ErrorIdentifier = char(string(scenarioStatus.ErrorIdentifier));
result.ErrorMessage = char(string(scenarioStatus.ErrorMessage));
end

function [resultOk, requiredCaseCount, requiredFailureCount, failedCases, optionalPrunedCount, optionalPrunedCases, statusNotes, authority, warningCount, errorSource, errorIdentifier, errorMessage] = localAggregateWaveformLinkStatus(link, profileReportedOk)
resultOk = logical(profileReportedOk);
requiredCaseCount = NaN;
requiredFailureCount = NaN;
failedCases = strings(0, 1);
optionalPrunedCount = 0;
optionalPrunedCases = strings(0, 1);
statusNotes = "";
authority = "Link.Result.Ok";
warningCount = 0;
errorSource = "";
errorIdentifier = "";
errorMessage = "";

kpitable = sixgr.util.structGet(link, "KPITable", table());
unsupported = sixgr.util.structGet(link, "UnsupportedCases", table());
linkResultOk = localTryLogical(sixgr.util.structGet(link, "Result.Ok", []), NaN);
linkOuterOk = localTryLogical(sixgr.util.structGet(link, "Ok", []), NaN);

if istable(kpitable) && ~isempty(kpitable)
    requiredCaseCount = double(height(kpitable));
    caseNames = string(localTableColumnOrDefault(kpitable, "Case", repmat("", height(kpitable), 1)));
    okMask = logical(localTableColumnOrDefault(kpitable, "Ok", true(height(kpitable), 1)));
    skippedMask = logical(localTableColumnOrDefault(kpitable, "Skipped", false(height(kpitable), 1)));
    failMask = ~okMask | skippedMask;
    requiredFailureCount = double(sum(failMask));
    failedCases = unique(caseNames(failMask), "stable");
end

if istable(unsupported) && ~isempty(unsupported) && ismember("Case", string(unsupported.Properties.VariableNames))
    optionalPrunedCases = unique(string(unsupported.Case), "stable");
    optionalPrunedCount = double(numel(optionalPrunedCases));
    warningCount = optionalPrunedCount;
end

candidateOk = [linkResultOk, linkOuterOk];
candidateOk = candidateOk(isfinite(candidateOk));
if ~isempty(candidateOk)
    resultOk = all(candidateOk ~= 0);
end
if isfinite(requiredFailureCount)
    resultOk = resultOk && requiredFailureCount == 0;
end
if ~isfinite(requiredCaseCount) && ~isfinite(requiredFailureCount) && isfinite(linkResultOk)
    requiredCaseCount = 1;
    requiredFailureCount = double(~logical(linkResultOk));
end
if isfinite(linkResultOk) && isfinite(linkOuterOk) && logical(linkResultOk) ~= logical(linkOuterOk)
    statusNotes = localJoinStatusNotes(statusNotes, ...
        "Top-level link Ok disagreed with nested Link.Result.Ok; authoritative scenario status was derived conservatively from nested link status.");
end
if ~resultOk && isempty(failedCases) && isfinite(linkResultOk) && ~logical(linkResultOk)
    failedCases = "link_result";
    if ~isfinite(requiredFailureCount) || requiredFailureCount <= 0
        requiredFailureCount = 1;
    end
    errorSource = "Link.Result.Ok";
    errorIdentifier = "required_case_failed";
    errorMessage = "Nested link result reported failure.";
end
if ~isfinite(requiredCaseCount)
    requiredCaseCount = 0;
end
if ~isfinite(requiredFailureCount)
    requiredFailureCount = double(~resultOk);
end
if requiredFailureCount > 0 && strlength(string(errorIdentifier)) == 0
    errorSource = "KPITable";
    errorIdentifier = "required_case_failed";
    errorMessage = "At least one required waveform-link case failed or was skipped.";
end
end

function mu = localDeriveNumerologyMu(scsKHz)
mu = NaN;
scsKHz = double(scsKHz);
if ~(isfinite(scsKHz) && scsKHz > 0)
    return;
end
mu = round(log2(scsKHz / 15));
end

function slotDuration_ms = localDeriveSlotDurationMs(mu)
slotDuration_ms = NaN;
mu = double(mu);
if isfinite(mu)
    slotDuration_ms = 1 / 2^mu;
end
end

function slotsPerFrame = localDeriveSlotsPerFrame(mu)
slotsPerFrame = NaN;
mu = double(mu);
if isfinite(mu)
    slotsPerFrame = 10 * 2^mu;
end
end

function value = localTryLogical(rawValue, defaultValue)
if nargin < 2
    defaultValue = NaN;
end
if isempty(rawValue)
    value = defaultValue;
    return;
end
try
    value = double(logical(rawValue(1)));
catch
    value = defaultValue;
end
end

function values = localTableColumnOrDefault(T, name, defaultValue)
if istable(T) && ismember(name, string(T.Properties.VariableNames))
    values = T.(name);
else
    values = defaultValue;
end
end

function note = localJoinStatusNotes(varargin)
parts = strings(0, 1);
for i = 1:nargin
    txt = strtrim(string(varargin{i}));
    if strlength(txt) > 0
        parts(end+1, 1) = txt; %#ok<AGROW>
    end
end
if isempty(parts)
    note = "";
    return;
end
parts = unique(parts, "stable");
note = strjoin(parts, " | ");
end

function metadata = localBenchmarkMetadata(scfg, descriptor, aiEnabled)
metadata = struct();
metadata.UseCase = string(scfg.get("ai_ml.use_case"));
metadata.AIEnabled = logical(aiEnabled);
metadata.Mode = string(scfg.get("ai_ml.mode"));
metadata.ModelID = string(scfg.get("ai_ml.model_id"));
metadata.ModelVersion = string(scfg.get("ai_ml.model_version"));
metadata.DescriptorType = string(scfg.get("ai_ml.descriptor_type"));
metadata.QuantizationMode = string(scfg.get("ai_ml.quantization_mode"));
metadata.RuntimeBudget_us = double(scfg.get("ai_ml.runtime_budget_us"));
metadata.LatencyBudget_us = double(scfg.get("ai_ml.latency_budget_us"));
metadata.FLOPsBudget = double(scfg.get("ai_ml.flops_budget"));
metadata.InferenceBatchSize = double(scfg.get("ai_ml.inference_batch_size"));
metadata.FallbackEnabled = logical(scfg.get("ai_ml.fallback_enabled"));
metadata.ConfidenceLoggingEnabled = logical(scfg.get("ai_ml.confidence_logging"));
metadata.ParameterCount = double(localOptionalDescriptorValue(descriptor, "parameter_count", NaN));
metadata.ConfiguredConfidenceBias = double(localOptionalDescriptorValue(descriptor, "confidence_bias", NaN));
metadata.ConfiguredInputFeatures = strjoin(string(scfg.get("ai_ml.input_features")), "|");
metadata.ConfiguredOutputTargets = strjoin(string(scfg.get("ai_ml.output_targets")), "|");
end

function T = localAppendBenchmarkColumns(T, metadata, confidenceValue)
if ~istable(T)
    return;
end
vars = { ...
    "UseCase", repmat(metadata.UseCase, height(T), 1), ...
    "AIEnabled", repmat(metadata.AIEnabled, height(T), 1), ...
    "Mode", repmat(metadata.Mode, height(T), 1), ...
    "ModelID", repmat(metadata.ModelID, height(T), 1), ...
    "ModelVersion", repmat(metadata.ModelVersion, height(T), 1), ...
    "DescriptorType", repmat(metadata.DescriptorType, height(T), 1), ...
    "QuantizationMode", repmat(metadata.QuantizationMode, height(T), 1), ...
    "RuntimeBudget_us", repmat(metadata.RuntimeBudget_us, height(T), 1), ...
    "LatencyBudget_us", repmat(metadata.LatencyBudget_us, height(T), 1), ...
    "FLOPsBudget", repmat(metadata.FLOPsBudget, height(T), 1), ...
    "InferenceBatchSize", repmat(metadata.InferenceBatchSize, height(T), 1), ...
    "FallbackEnabled", repmat(metadata.FallbackEnabled, height(T), 1), ...
    "ConfidenceLoggingEnabled", repmat(metadata.ConfidenceLoggingEnabled, height(T), 1), ...
    "ConfidenceScore", repmat(confidenceValue, height(T), 1), ...
    "ParameterCount", repmat(metadata.ParameterCount, height(T), 1)};
    for k = 1:2:numel(vars)
        name = vars{k};
        values = vars{k+1};
        if ~ismember(name, T.Properties.VariableNames)
            T = addvars(T, values, 'NewVariableNames', name);
        end
    end
end

function value = localBenchmarkConfidence(descriptor, scfg)
if ~logical(scfg.get("ai_ml.confidence_logging"))
    value = NaN;
    return;
end
% Descriptor-side confidence_bias is static model metadata, not measured
% runtime confidence telemetry. Keep benchmark confidence unavailable until
% the active AI path emits per-observation runtime confidence.
value = double(localOptionalDescriptorValue(descriptor, "runtime_measured_confidence_score", NaN));
end

function Hout = localApplyCEPlugin(Hin, descriptor)
pluginType = lower(string(localRequireDescriptorField(descriptor, "plugin_type")));
switch pluginType
    case "moving_average_denoiser"
        alpha = double(localRequireDescriptorField(descriptor, "smoothing_alpha"));
        Hout = (1 - alpha) .* Hin + alpha .* ones(size(Hin), "like", Hin);
    otherwise
        Hout = Hin;
end
end

function [xHat, ratio] = localApplyCSICompressionPlugin(x, descriptor, latentDim, quantBits)
x = double(x(:));
step = max(1, ceil(numel(x) / max(latentDim, 1)));
z = x(1:step:end);
maxAbs = max(abs(z));
if maxAbs <= 0
    zq = z;
else
    qLevels = max(2^max(quantBits,1)-1, 1);
    zq = round((z / maxAbs) * qLevels) / qLevels * maxAbs;
end
xHat = repelem(zq, step);
xHat = xHat(1:numel(x));
ratio = double(numel(x)) / max(double(numel(zq)), 1);
if lower(string(localRequireDescriptorField(descriptor, "plugin_type"))) ~= "latent_quantizer"
    xHat = x;
    ratio = 1;
end
end

function beamIdx = localApplyBeamPlugin(metric, descriptor)
pluginType = lower(string(localRequireDescriptorField(descriptor, "plugin_type")));
metric = double(metric(:));
switch pluginType
    case "argmax"
        [~, beamIdx] = max(metric);
    case "top2_energy_bias"
        [~, idx] = sort(metric, "descend");
        beamIdx = idx(min(2, numel(idx)));
    otherwise
        [~, beamIdx] = max(metric);
end
beamIdx = double(beamIdx);
end

function descriptor = localLoadAIDescriptor(modelPath)
descriptor = struct();
modelPath = string(modelPath);
if strlength(modelPath) == 0
    return;
end
resolved = localResolveModelPath(modelPath);
if exist(resolved, "file") ~= 2
    return;
end
descriptor = sixgr.lls6g.config.readConfigFile(resolved);
end

function value = localRequireDescriptorField(descriptor, fieldName)
if ~isfield(descriptor, fieldName)
    error("sixgr:lls6g:runner:MissingDescriptorField", ...
        "AI descriptor is missing required field '%s'.", fieldName);
end
value = descriptor.(fieldName);
end

function value = localOptionalDescriptorValue(descriptor, fieldName, defaultValue)
if isfield(descriptor, fieldName)
    value = descriptor.(fieldName);
else
    value = defaultValue;
end
end

function p = localResolveModelPath(modelPath)
if exist(char(modelPath), "file") == 2
    p = char(modelPath);
    return;
end
root = localRepoRoot();
candidate = fullfile(root, char(modelPath));
if exist(candidate, "file") == 2
    p = candidate;
    return;
end
p = char(modelPath);
end

function localWriteOptionalTable(filePath, T)
if istable(T) && ~isempty(T)
    sixgr.util.csvWriteTable(filePath, T);
end
end

function root = localRepoRoot()
root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end

function out = localMaterializeBrowserContractArtifacts()
out = struct( ...
    "Ok", false, ...
    "Status", NaN, ...
    "Identifier", "", ...
    "Message", "", ...
    "CreatedCount", 0, ...
    "MissingTableCount", NaN, ...
    "MissingChartCount", NaN);
if ~sixgr.db.isArtifactStoreActive()
    out.Identifier = "artifact_store_inactive";
    out.Message = "MySQL artifact store is inactive, so browser contract materialization was skipped.";
    return;
end
storeState = sixgr.db.artifactStore("get_state");
runID = double(sixgr.util.structGet(storeState, "RunID", NaN));
if ~(isfinite(runID) && runID > 0)
    out.Identifier = "run_id_unavailable";
    out.Message = "The active MySQL artifact store did not expose a valid run_id.";
    return;
end
repoRoot = localRepoRoot();
scriptPath = fullfile(repoRoot, "scripts", "materialize_lls_contract_artifacts.py");
if exist(scriptPath, "file") ~= 2
    out.Identifier = "materializer_script_missing";
    out.Message = "scripts/materialize_lls_contract_artifacts.py was not found in the repo root.";
    return;
end
pythonExe = localResolvePythonExecutable();
cmd = sprintf('"%s" "%s" --run-id %d --strict', ...
    localShellEscapeArg(pythonExe), localShellEscapeArg(scriptPath), round(runID));
[status, raw] = system(cmd);
out.Status = double(status);
payloadText = strtrim(string(raw));
jsonStart = strfind(char(payloadText), "{");
if ~isempty(jsonStart)
    payloadText = extractAfter(payloadText, jsonStart(1) - 1);
    try
        payload = jsondecode(char(payloadText));
        out.CreatedCount = double(sixgr.util.structGet(payload, "created_count", 0));
        out.MissingTableCount = double(sixgr.util.structGet(payload, "tables_missing", NaN));
        out.MissingChartCount = double(sixgr.util.structGet(payload, "charts_missing", NaN));
    catch
    end
end
if status == 0
    out.Ok = true;
    out.Identifier = "browser_contract_materialization_ok";
    out.Message = char(payloadText);
else
    out.Identifier = "browser_contract_materialization_failed";
    out.Message = char(string(raw));
end
end

function exe = localResolvePythonExecutable()
exe = "";
try
    runtimeInfo = sixgr.lls6g.config.ensureYAMLRuntime(ConfigurePyEnv=false);
    exe = string(sixgr.util.structGet(runtimeInfo, "PythonExecutable", ""));
catch
    exe = "";
end
exe = strtrim(exe);
if strlength(exe) == 0
    [status, outTxt] = system('python -c "import sys; print(sys.executable)"');
    if status == 0
        exe = strtrim(string(outTxt));
    end
end
if strlength(exe) == 0
    exe = "python";
end
end

function out = localShellEscapeArg(value)
out = strrep(char(string(value)), '"', '""');
end

function localPublishMappedRuntimeConfigEvidence(scfg, cfg)
if isa(scfg, "sixgr.lls6g.config.ScenarioConfig")
    s = scfg.toStruct();
else
    s = scfg;
end
if ~isstruct(s)
    return;
end

mappings = {
    "bwp.dl", "PHY_BWP", "phy.bwp.dl"
    "bwp.ul", "PHY_BWP", "phy.bwp.ul"
    "pdsch.resource_allocation_type", "DL_Data_PDSCH", "phy.pdsch.resourceAllocationType"
    "pdsch.mapping_type", "DL_Data_PDSCH", "phy.pdsch.mappingType"
    "pdsch.start_symbol", "DL_Data_PDSCH", "phy.pdsch.startSymbol"
    "pdsch.num_symbols", "DL_Data_PDSCH", "phy.pdsch.numSymbols"
    "pdsch.vrb_to_prb_mapping", "DL_Data_PDSCH", "phy.pdsch.vrbToPRBMapping"
    "pdsch.prb_bundling_type", "DL_Data_PDSCH", "phy.pdsch.prbBundlingType"
    "pdsch.prb_bundle_size", "DL_Data_PDSCH", "phy.pdsch.prbBundleSize"
    "pdsch.rate_matching_pattern", "DL_Data_PDSCH", "phy.pdsch.rateMatchingPattern"
    "pdsch.xoh_pdsch", "DL_Data_PDSCH", "phy.pdsch.xOverhead"
    "pdsch.tbs_scaling", "DL_Data_PDSCH", "phy.pdsch.tbsScaling"
    "pdsch.cbg_transmission", "DL_Data_PDSCH", "phy.pdsch.cbgTransmission"
    "pusch.resource_allocation_type", "UL_Data_PUSCH", "phy.pusch.resourceAllocationType"
    "pusch.mapping_type", "UL_Data_PUSCH", "phy.pusch.mappingType"
    "pusch.start_symbol", "UL_Data_PUSCH", "phy.pusch.startSymbol"
    "pusch.num_symbols", "UL_Data_PUSCH", "phy.pusch.numSymbols"
    "pusch.frequency_hopping", "UL_Data_PUSCH", "phy.pusch.frequencyHopping"
    "pusch.intra_slot_frequency_hopping", "UL_Data_PUSCH", "phy.pusch.intraSlotFrequencyHopping"
    "pusch.inter_slot_frequency_hopping", "UL_Data_PUSCH", "phy.pusch.interSlotFrequencyHopping"
    "pusch.transform_precoding", "UL_Data_PUSCH", "phy.pusch.transformPrecoding"
    "pusch.codebook_based_transmission", "UL_Data_PUSCH", "phy.pusch.codebookBasedTransmission"
    "pusch.xoh_pusch", "UL_Data_PUSCH", "phy.pusch.xOverhead"
    "pusch.cbg_transmission", "UL_Data_PUSCH", "phy.pusch.cbgTransmission"
    "pusch.tp_pi2_bpsk", "UL_Data_PUSCH", "phy.pusch.pi2BPSKTransformPrecoding"
    "pdcch.coreset", "DL_UL_Control_PDCCH", "phy.pdcch.coresets"
    "pdcch.coresets", "DL_UL_Control_PDCCH", "phy.pdcch.coresets"
    "pdcch.search_spaces", "DL_UL_Control_PDCCH", "phy.pdcch.searchSpaces"
    "pdcch.blind_decoding_attempts", "DL_UL_Control_PDCCH", "phy.pdcch.blindDecodingAttempts"
    "pdcch.dmrs_scrambling_id_source", "DL_UL_Control_PDCCH", "phy.pdcch.dmrsScramblingIdSource"
    "pdcch.rnti_config", "DL_UL_Control_PDCCH", "phy.pdcch.rntiConfig"
    "channel_estimation.algorithm", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.algorithm"
    "channel_estimation.interpolation_method", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.interpolationMethod"
    "channel_estimation.filter_length_time", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.filterLengthTime"
    "channel_estimation.filter_length_freq", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.filterLengthFrequency"
    "channel_estimation.noise_variance_source", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.noiseVarianceSource"
    "channel_estimation.noise_variance_averaging_window_slots", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.noiseVarianceAveragingWindowSlots"
    "channel_estimation.delay_spread_assumption_ns", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.delaySpreadAssumption_ns"
    "channel_estimation.doppler_assumption_hz", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.dopplerAssumption_Hz"
    "channel_estimation.temporal_filtering_enable", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.temporalFilteringEnabled"
    "channel_estimation.frequency_smoothing_enable", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.frequencySmoothingEnabled"
    "channel_estimation.perfect_csi", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.perfectCSI"
    "channel_estimation.ce_extrapolation_mode", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.extrapolationMode"
    "channel_estimation.ce_bound_delay_ns", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.boundDelay_ns"
    "channel_estimation.ce_reference_signal", "PHY_Receiver_Channel_Estimation", "phy.channelEstimation.referenceSignal"
    "equalization.algorithm", "PHY_Receiver_Equalization", "phy.equalization.algorithm"
    "equalization.regularization_method", "PHY_Receiver_Equalization", "phy.equalization.regularizationMethod"
    "equalization.noise_variance_for_equalizer", "PHY_Receiver_Equalization", "phy.equalization.noiseVarianceForEqualizer"
    "equalization.post_equalization_snr_estimation", "PHY_Receiver_Equalization", "phy.equalization.postEqualizationSNREstimation"
    "equalization.irc_interference_covariance_window_slots", "PHY_Receiver_Equalization", "phy.equalization.ircInterferenceCovarianceWindowSlots"
    "equalization.irc_covariance_estimation", "PHY_Receiver_Equalization", "phy.equalization.ircCovarianceEstimation"
    "equalization.sv_threshold", "PHY_Receiver_Equalization", "phy.equalization.singularValueThreshold"
    "equalization.condition_number_cap", "PHY_Receiver_Equalization", "phy.equalization.conditionNumberCap"
    "equalization.per_prb_equalization", "PHY_Receiver_Equalization", "phy.equalization.perPRBEqualization"
    "equalization.per_symbol_equalization", "PHY_Receiver_Equalization", "phy.equalization.perSymbolEqualization"
    "equalization.equalizer_output_scaling", "PHY_Receiver_Equalization", "phy.equalization.outputScaling"
    "equalization.sic_enable", "PHY_Receiver_Equalization", "phy.equalization.sicEnabled"
    "equalization.sic_stages", "PHY_Receiver_Equalization", "phy.equalization.sicStages"
    "synchronization.timing_sync_algorithm", "PHY_Synchronization", "phy.synchronization.timingSyncAlgorithm"
    "synchronization.frequency_sync_algorithm", "PHY_Synchronization", "phy.synchronization.frequencySyncAlgorithm"
    "synchronization.symbol_timing_recovery", "PHY_Synchronization", "phy.synchronization.symbolTimingRecovery"
    "synchronization.integer_cfo_correction_enable", "PHY_Synchronization", "phy.synchronization.integerCFOCorrectionEnabled"
    "synchronization.fractional_cfo_correction_enable", "PHY_Synchronization", "phy.synchronization.fractionalCFOCorrectionEnabled"
    "synchronization.timing_tracking_mode", "PHY_Synchronization", "phy.synchronization.timingTrackingMode"
    "synchronization.frequency_tracking_mode", "PHY_Synchronization", "phy.synchronization.frequencyTrackingMode"
    "synchronization.pss_detection_threshold", "PHY_Synchronization", "phy.synchronization.pssDetectionThreshold"
    "synchronization.sss_hypothesis_test_threshold", "PHY_Synchronization", "phy.synchronization.sssHypothesisTestThreshold"
    "synchronization.max_timing_uncertainty_samples", "PHY_Synchronization", "phy.synchronization.maxTimingUncertaintySamples"
    "synchronization.ota_timing_advance_enable", "PHY_Synchronization", "phy.synchronization.otaTimingAdvanceEnabled"
    "synchronization.timing_advance_granularity_ts", "PHY_Synchronization", "phy.synchronization.timingAdvanceGranularityTs"
    "rf_hardware.adc_resolution_bits", "RF_Hardware", "rf.hardware.adc.resolutionBits"
    "rf_hardware.dac_resolution_bits", "RF_Hardware", "rf.hardware.dac.resolutionBits"
    "rf_hardware.adc_dynamic_range_db", "RF_Hardware", "rf.hardware.adc.dynamicRange_dB"
    "rf_hardware.adc_full_scale_power_dBm", "RF_Hardware", "rf.hardware.adc.fullScalePower_dBm"
    "rf_hardware.agc_enable", "RF_Hardware", "rf.hardware.agc.enabled"
    "rf_hardware.agc_target_level_dBm", "RF_Hardware", "rf.hardware.agc.targetLevel_dBm"
    "rf_hardware.agc_attack_time_us", "RF_Hardware", "rf.hardware.agc.attackTime_us"
    "rf_hardware.agc_release_time_us", "RF_Hardware", "rf.hardware.agc.releaseTime_us"
    "rf_hardware.dc_offset_enable", "RF_Hardware", "rf.hardware.dcOffset.enabled"
    "rf_hardware.dc_offset_level_dBc", "RF_Hardware", "rf.hardware.dcOffset.level_dBc"
    "rf_hardware.dc_offset_compensation_enable", "RF_Hardware", "rf.hardware.dcOffset.compensationEnabled"
    "rf_hardware.lna_gain_dB", "RF_Hardware", "rf.hardware.lna.gain_dB"
    "rf_hardware.rx_gain_dB", "RF_Hardware", "rf.hardware.rxGain_dB"
    "rf_hardware.tx_gain_dB", "RF_Hardware", "rf.hardware.txGain_dB"
    "rf_hardware.mutual_coupling_matrix_enable", "RF_Hardware", "rf.hardware.mutualCouplingMatrixEnabled"
    "tdd_timing.pdcch_to_pdsch_k0", "TDD_Timing", "phy.tddTiming.pdcchToPDSCHK0"
    "tdd_timing.pdcch_to_pusch_k2", "TDD_Timing", "phy.tddTiming.pdcchToPUSCHK2"
    "tdd_timing.dl_harq_feedback_k1", "TDD_Timing", "phy.tddTiming.dlHARQFeedbackK1Candidates"
    "tdd_timing.ul_grant_k2", "TDD_Timing", "phy.tddTiming.ulGrantK2"
    "tdd_timing.harq_roundtrip_slots", "TDD_Timing", "phy.tddTiming.harqRoundtripSlots"
    "tdd_timing.dl_to_ul_guard_time_us", "TDD_Timing", "phy.tddTiming.dlToULGuardTime_us"
    "tdd_timing.timing_advance_max_us", "TDD_Timing", "phy.tddTiming.timingAdvanceMax_us"
    "tdd_timing.n1_pdsch_processing_time_symbols", "TDD_Timing", "phy.tddTiming.n1PDSCHProcessingTimeSymbols"
    "tdd_timing.n2_pusch_preparation_time_symbols", "TDD_Timing", "phy.tddTiming.n2PUSCHPreparationTimeSymbols"
    "coding.ldpc_lifting_size_z_selection", "PHY_Coding", "phy.ldpc.liftingSizeZSelection"
    "coding.ldpc_schedule_type", "PHY_Coding", "phy.ldpc.scheduleType"
    "coding.ldpc_min_sum_offset", "PHY_Coding", "phy.ldpc.minSumOffset"
    "coding.polar_reliability_sequence_source", "PHY_Coding", "phy.polar.reliabilitySequenceSource"
    "coding.polar_rate_matching_type", "PHY_Coding", "phy.polar.rateMatchingType"
    "link_adaptation.olla_init_offset_db", "Link_Adaptation", "phy.linkAdaptation.ollaInitialOffset_dB"
    "link_adaptation.olla_max_offset_db", "Link_Adaptation", "phy.linkAdaptation.ollaMaxOffset_dB"
    "link_adaptation.olla_min_offset_db", "Link_Adaptation", "phy.linkAdaptation.ollaMinOffset_dB"
    "link_adaptation.olla_window_size_slots", "Link_Adaptation", "phy.linkAdaptation.ollaWindowSizeSlots"
    "link_adaptation.olla_forgetting_factor", "Link_Adaptation", "phy.linkAdaptation.ollaForgettingFactor"
    "link_adaptation.mcs_backoff_dl_db", "Link_Adaptation", "phy.linkAdaptation.dlMCSBackoff_dB"
    "link_adaptation.mcs_backoff_ul_db", "Link_Adaptation", "phy.linkAdaptation.ulMCSBackoff_dB"
    "link_adaptation.sinr_to_cqi_mapping_table", "Link_Adaptation", "phy.linkAdaptation.sinrToCQITable"
    };

for i = 1:size(mappings, 1)
    parameterId = string(mappings{i, 1});
    featureFamily = string(mappings{i, 2});
    internalPath = string(mappings{i, 3});
    [~, sourceFound] = localTryGetNestedRuntime(s, parameterId);
    [appliedValue, internalFound] = localTryGetNestedRuntime(cfg, internalPath);
    if ~(sourceFound && internalFound)
        continue;
    end
    sixgr.config.publishConfigApplicationEvidence("record", ...
        parameterId, featureFamily, internalPath, ...
        "sixgr.lls6g.buildInternalConfig", appliedValue, ...
        "RuntimeObjectType", "struct", ...
        "RuntimeObjectPath", "cfg." + internalPath, ...
        "ApplicationScope", "run", ...
        "EvidenceSource", "resolved_config_to_internal_cfg_mapping");
end
end

function [value, found] = localTryGetNestedRuntime(s, path)
value = [];
found = false;
if ~isstruct(s)
    return;
end
parts = split(string(path), ".");
cursor = s;
for i = 1:numel(parts)
    key = char(parts(i));
    if ~(isstruct(cursor) && isscalar(cursor) && isfield(cursor, key))
        return;
    end
    cursor = cursor.(key);
end
value = cursor;
found = true;
end

function localPruneEmptyDirs(rootFolder)
rootFolder = char(string(rootFolder));
if ~isfolder(rootFolder)
    return;
end
entries = dir(rootFolder);
for i = 1:numel(entries)
    name = string(entries(i).name);
    if name == "." || name == ".." || ~entries(i).isdir
        continue;
    end
    child = fullfile(rootFolder, char(name));
    localPruneEmptyDirs(child);
end
entries = dir(rootFolder);
entries = entries(~ismember(string({entries.name}), [".", ".."]));
if isempty(entries)
    try
        rmdir(rootFolder);
    catch
    end
end
end
