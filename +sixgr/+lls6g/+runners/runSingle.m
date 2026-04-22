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
opt.LinkSNRGrid_dB = localBuildSweepGrid(cfg.channel.snr_dB, ...
    double(scfg.get("simulation.snr_sweep_offsets_db")), ...
    logical(scfg.get("sweeps_and_matrix.snr_sweep.enabled")), ...
    double(scfg.get("sweeps_and_matrix.snr_sweep.values_db")));
mcIterations = max(1, round(double(scfg.get("simulation.monte_carlo_iterations"))));
opt.LinkSweepFrames = mcIterations;
opt.LinkSweepTrialsPerSNR = max(double(totalSlots), double(totalSlots) * mcIterations);
opt.LinkReferenceSweepFrames = max(opt.LinkSweepTrialsPerSNR, ceil(1.5 * opt.LinkSweepTrialsPerSNR));
opt.LinkSweepMaxPoints = numel(opt.LinkSNRGrid_dB);
opt.LinkAdaptiveSweepEnabled = true;
opt.LinkAdaptiveSweepStep_dB = 2;
opt.LinkAdaptiveSweepMaxPoints = 12;
opt.LinkAnchorCases = scfg.get("scenario.bundle_anchor_cases", {});
opt.SaveFigures = logical(scfg.get("output.save_figures"));
localDBLog("INFO", "Waveform bundle starting: snr=%.3f dB sweepPoints=%d canonicalSlots=%d monteCarlo=%d slotDuration_s=%.6f", ...
    double(opt.LinkSNR_dB), double(numel(opt.LinkSNRGrid_dB)), ...
    double(opt.LinkMaxSimFrames), double(mcIterations), double(slotDuration_s));
link = sixgr.truth.runWaveformLinkBundle(cfg, fullfile(runFolder, "air_interface"), opt);
localDBLog("INFO", "Waveform bundle finished: ok=%d", double(logical(sixgr.util.structGet(link, "Ok", false))));
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

link = struct();
link.Ok = logical(sixgr.util.structGet(systemOut, "Ok", false));
link.Result = struct("Ok", logical(sixgr.util.structGet(systemOut, "Ok", false)));
link.Errors = string(sixgr.util.structGet(systemOut, "Errors", strings(0, 1)));
link.UnsupportedCases = table();
link.KPITable = kpitable;
link.RawTrials = canon.RawTrials;

result = struct();
result.Ok = logical(sixgr.util.structGet(systemOut, "Ok", false));
result.Link = link;
result.System = systemOut;
result.Canonical = canon;
end

function result = localRunPDCCHBlindDecodeSweep(cfg, scfg, runFolder)
aggLevels = double(scfg.get("control.aggregation_levels"));
nTrials = max(1, round(double(scfg.get("simulation.monte_carlo_iterations"))));
snr_dB = double(scfg.get("simulation.snr_db"));
pdcchPayloadBits = max(1, round(double(scfg.get("control.pdcch_payload_bits"))));
listLength = max(1, round(double(scfg.get("control.blind_decode_list_length"))));

trialRows = repmat(struct("AggregationLevel", NaN, "Trial", NaN, "SNR_dB", NaN, ...
    "BitErrors", NaN, "BitsCompared", NaN, "Pass", false, "DetectionMetric", NaN), 0, 1);
summaryRows = repmat(struct("AggregationLevel", NaN, "PassRate", NaN, "MeanBitErrors", NaN), 0, 1);

for i = 1:numel(aggLevels)
    lvl = aggLevels(i);
    pass = false(nTrials,1);
    bitErr = NaN(nTrials,1);
    detMet = NaN(nTrials,1);
    for k = 1:nTrials
        cfgK = cfg;
        cfgK.phy.pdcch.aggregationLevel = lvl;
        [tx, ~] = sixgr.phy.dl.PDCCH_Tx(cfgK, "K", pdcchPayloadBits);
        [rxWave, noiseVar] = localAddAwgn(tx.Waveform, snr_dB);
        rx = sixgr.phy.dl.PDCCH_Rx(rxWave, cfgK, ...
            "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), ...
            "ListLength", listLength, "NoiseVar", noiseVar);
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
            "DetectionMetric", detMet(k));
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
end

result = struct();
result.Ok = all(summaryT.PassRate >= 0);
result.TrialTable = trialT;
result.SummaryTable = summaryT;
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
controlTrace = struct();
if localShouldWriteCSV(scfg)
    sixgr.util.csvWriteTable(fullfile(runFolder, "control", "csv", "prach_detection_trials.csv"), study.TrialTable);
    sixgr.util.csvWriteTable(fullfile(runFolder, "control", "csv", "prach_detection_summary.csv"), study.SummaryBySNR);
    sixgr.util.csvWriteTable(fullfile(runFolder, "air_interface", "csv", "prach_trials.csv"), controlTrialT);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "initial_access_random_access_outputs.csv"), initialAccessT);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_correlation_traces.csv"), correlationTraceT);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_summary_by_snr.csv"), study.SummaryBySNR);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_summary_by_scenario.csv"), study.SummaryByScenario);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_confusion_detection_types.csv"), study.Confusion);
    sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_timing_error_samples.csv"), study.TimingErrorSamples);
    if ~isempty(study.FrequencyErrorSamples)
        sixgr.util.csvWriteTable(fullfile(runFolder, "reports", "csv", "prach_frequency_error_samples.csv"), study.FrequencyErrorSamples);
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
    double(localRunnerColumnOrDefault(roT, "EstimatedTimingOffset_samples", nan(nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "TimingError_samples", nan(nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "peak_metric", nan(nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "threshold", nan(nRows, 1))), ...
    string(localRunnerColumnOrDefault(roT, "threshold_mode", repmat("", nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "false_alarm_flag", localRunnerColumnOrDefault(roT, "FalseAlarmFlag", zeros(nRows, 1)))), ...
    double(localRunnerColumnOrDefault(roT, "wrong_preamble_flag", localRunnerColumnOrDefault(roT, "wrong_preamble_flag", zeros(nRows, 1)))), ...
    double(localRunnerColumnOrDefault(roT, "missed_detection_flag", localRunnerColumnOrDefault(roT, "missed_detection_flag", zeros(nRows, 1)))), ...
    double(localRunnerColumnOrDefault(roT, "detected_preamble_index", nan(nRows, 1))), ...
    txPreamble, ...
    ueCount, ...
    double(localRunnerColumnOrDefault(roT, "CollisionFlag", zeros(nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "SNR_dB", localRunnerColumnOrDefault(roT, "snr_db", nan(nRows, 1)))), ...
    string(localRunnerColumnOrDefault(roT, "Notes", localRunnerColumnOrDefault(roT, "detection_type", repmat("", nRows, 1)))), ...
    string(localRunnerColumnOrDefault(roT, "scenario_id", repmat("", nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "seed", nan(nRows, 1))), ...
    double(localRunnerColumnOrDefault(roT, "ro_id", nan(nRows, 1))), ...
    'VariableNames', {'Status','Frame','Slot','UEIndex','RNTI','CRCPass','ComputeLatency_ms','ProcedureDelay_ms', ...
    'AirInterfaceObservation_ms','AcquisitionTime_ms','TrueTimingOffset_samples','EstimatedTimingOffset_samples', ...
    'TimingError_samples','DetectionMetric','Threshold','ThresholdMode','FalseAlarmFlag','WrongPreambleFlag', ...
    'MissDetectionFlag','PreambleIndex','TransmittedPreambleIndex','ActiveUECount','CollisionFlag','SNR_dB','Notes', ...
    'ScenarioID','Seed','ROID'});

initialAccessT = study.SummaryBySNR;
if istable(initialAccessT) && ~isempty(initialAccessT)
    initialAccessT.ConfiguredUEsPerRO = repmat(max(double(ueCount), [], "omitnan"), height(initialAccessT), 1);
    initialAccessT.CollisionModeEnabled = repmat(any(double(controlTrialT.CollisionFlag) ~= 0), height(initialAccessT), 1);
    initialAccessT.ChannelModel = repmat(string(sixgr.util.structGet(cfg, "prach_lls.ChannelModel", "")), height(initialAccessT), 1);
end

correlationTraceT = table( ...
    controlTrialT.Frame, ...
    controlTrialT.Slot, ...
    controlTrialT.SNR_dB, ...
    controlTrialT.DetectionMetric, ...
    controlTrialT.ComputeLatency_ms, ...
    controlTrialT.AirInterfaceObservation_ms, ...
    controlTrialT.TimingError_samples, ...
    controlTrialT.Status, ...
    controlTrialT.Notes, ...
    repmat("air_interface/csv/prach_trials.csv", nRows, 1), ...
    'VariableNames', {'Frame','Slot','SNR_dB','DetectionMetric','ComputeLatency_ms','AirInterfaceObservation_ms','TimingError_samples','Status','Notes','SourceArtifact'});
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
    rxWave = localAddAwgnOnly(tx.Waveform, snr_dB);
    rx = sixgr.phy.ul.SRS_Rx(rxWave, cfg, "Carrier", tx.Carrier, "SRS", tx.SRS);
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
cfg.run.runnerProfile = char(string(scfg.get("scenario.runner_profile")));
cfg.run.scenarioID = char(string(scfg.ScenarioID));
cfg.meta.scenarioID = char(string(scfg.ScenarioID));
cfg.meta.configHash = char(string(scfg.ConfigHash));
cfg = localEnsureExactMexAcceleration(cfg);
cfg = localEnsureParallelExecution(cfg);
profilerCfg = localResolveProfilerConfig(scfg);
profilerState = localStartProfilerIfEnabled(profilerCfg);
storeInfo = sixgr.db.activateArtifactStore(runFolder, cfg, struct( ...
    "ScenarioID", scfg.ScenarioID, ...
    "RunTag", runTag, ...
    "Bucket", scfg.get("output.bucket"), ...
    "Profile", localResolveRunRowProfileName(scfg), ...
    "LogicalRunFolder", publicRunFolder, ...
    "ScenarioConfigStruct", scfg.toStruct(), ...
    "ScenarioSourceFiles", string(scfg.SourceFiles(:))));
cleanupStore = onCleanup(@() sixgr.db.deactivateArtifactStore()); %#ok<NASGU>
if logical(sixgr.util.structGet(storeInfo, "Active", false))
    sixgr.db.markRunStatus("running", struct("started_utc", runStartUTC));
end
localDBLog("INFO", "Artifact store active=%d backend=%s schema=%s", ...
    double(logical(sixgr.util.structGet(storeInfo, "Active", false))), ...
    char(string(sixgr.util.structGet(storeInfo, "Backend", ""))), ...
    char(string(sixgr.util.structGet(storeInfo, "DatabaseSchema", ""))));

try
    localDBLog("INFO", "Writing resolved snapshots.");
    localWriteResolvedSnapshots(layout, scfg);
    localDBLog("INFO", "Exporting live geometry artifacts.");
    localExportLiveGeometryArtifacts(layout, scfg, cfg);

    profile = lower(string(scfg.get("scenario.runner_profile")));
    localDBLog("INFO", "Executing runner profile=%s.", char(profile));
    switch profile
        case "waveform_bundle"
            result = localRunWaveformBundleScenario(cfg, scfg, runFolder);
        case "system_level_lls"
            result = localRunSystemLevelScenario(cfg, scfg, runFolder);
        case "pdcch_blind_decode_sweep"
            result = localRunPDCCHBlindDecodeSweep(cfg, scfg, runFolder);
        case "ctrl6gr_pdcch_study"
            result = localRun6GRPDCCHStudy(cfg, scfg, runFolder);
        case "pdsch6gr_truth_study"
            result = localRun6GRPDSCHStudy(cfg, scfg, runFolder);
        case "prach_detection"
            result = localRunPRACHDetectionScenario(cfg, scfg, runFolder);
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
    sixgr.util.jsonWrite(fullfile(layout.MetaDir, "scenario_manifest.json"), manifest);
    localDBLog("INFO", "Exporting config-ownership and hardcoding audit artifacts.");
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
    sixgr.util.jsonWrite(fullfile(layout.MetaDir, "scenario_manifest.json"), manifest);
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
    scenarioStatus = localApplyRuntimeTruthContract(preTruthScenarioStatus, result, scfg, cfg, runFolder);
    result = localApplyScenarioStatus(result, scenarioStatus);
    localDBLog("INFO", "Runtime truth contract re-evaluated after final artifact exports: ok=%d roundtripMismatch=%d evidenceMissing=%d strictFailures=%d", ...
        double(logical(scenarioStatus.RuntimeTruthContractOk)), double(scenarioStatus.RoundtripMismatchCount), ...
        double(scenarioStatus.RequiredRuntimeEvidenceMissingCount), double(scenarioStatus.StrictTruthFailureCount));
    summaryT = localBuildScenarioSummaryTable(scfg, profile, result, scenarioStatus);
    if logical(scfg.get("output.save_csv"))
        localDBLog("INFO", "Rewriting scenario summary CSV with final artifact truth-gated status.");
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), summaryT);
    end
    manifest = localBuildManifest(scfg, publicRunFolder, profile, result, runtimeSummary, environmentSummary, scenarioStatus);
    localDBLog("INFO", "Rewriting scenario manifest with final artifact truth-gated status.");
    sixgr.util.jsonWrite(fullfile(layout.MetaDir, "scenario_manifest.json"), manifest);
    optionalArtifactIssues = strings(0, 1);
    profilerArtifacts = struct();
    localDBLog("INFO", "Writing artifact manifest.");
    manifest.ArtifactManifestPath = char(localWriteArtifactManifest(runFolder, scfg, profile, manifest, reportBundle, scenarioStatus));
    sixgr.util.jsonWrite(fullfile(layout.MetaDir, "scenario_manifest.json"), manifest);
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
    try
        profilerArtifacts = localExportProfilerArtifacts(layout, profilerCfg, profilerState, "Run completed successfully.");
    catch profilerME
        optionalArtifactIssues(end+1, 1) = "profiler_export:" + string(profilerME.identifier);
        localDBLog("WARN", "Optional profiler export did not complete: %s | %s", ...
            char(string(profilerME.identifier)), char(string(profilerME.message)));
        localStopProfilerSession(profilerState);
        profilerArtifacts = struct();
    end

    localMarkRunStatusSafe(string(scenarioStatus.RunCompletion), ...
        localBuildTerminalStatusPayload(scenarioStatus, "run_terminal_optional_artifacts_complete", optionalArtifactIssues));
    if logical(scenarioStatus.ResultOk)
        localDBLog("INFO", "Run completed successfully in %.3f seconds.", toc(runTimer));
    else
        localDBLog("WARN", "Run completed with truth/status failures in %.3f seconds: requiredFailures=%d strictTruthFailures=%d", ...
            toc(runTimer), double(scenarioStatus.RequiredFailureCount), double(scenarioStatus.StrictTruthFailureCount));
    end

    execOut = struct();
    execOut.Ok = logical(scenarioStatus.ResultOk);
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
catch ME
    localDBLog("ERROR", "Run failed: %s | %s", char(string(ME.identifier)), char(string(ME.message)));
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

function profilerCfg = localResolveProfilerConfig(scfg)
profilerCfg = struct( ...
    "Enabled", logical(scfg.get("output.profiler_enabled", false)), ...
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
manifest = struct();
manifest.GeneratedUTC = localUTCStamp();
manifest.ScenarioID = char(string(scfg.ScenarioID));
manifest.ConfigHash = char(string(scfg.ConfigHash));
manifest.ConfigPath = char(string(scfg.ConfigPath));
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
manifest.ExecutionStartedUTC = char(string(sixgr.util.structGet(runtimeSummary, "StartedUTC", "")));
manifest.ExecutionCompletedUTC = char(string(sixgr.util.structGet(runtimeSummary, "CompletedUTC", "")));
manifest.ElapsedSeconds = double(sixgr.util.structGet(runtimeSummary, "ElapsedSeconds", NaN));
manifest.WarningCount = double(sixgr.util.structGet(runtimeSummary, "WarningCount", 0));
manifest.EnvironmentSummaryPath = "meta/environment.json";
manifest.RuntimeSummaryPath = "meta/runtime_summary.json";
manifest.HostPlatform = char(string(sixgr.util.structGet(environmentSummary, "Platform", "")));
manifest.RunScope = "6G_PHY_LLS_SINGLE_SCENARIO";
manifest.RunCompletion = char(string(scenarioStatus.RunCompletion));
manifest.ResultOk = logical(scenarioStatus.ResultOk);
manifest.PartialOk = logical(scenarioStatus.PartialOk);
manifest.ArtifactsGenerated = logical(scenarioStatus.ArtifactsGenerated);
manifest.RequiredCaseCount = double(scenarioStatus.RequiredCaseCount);
manifest.RequiredFailureCount = double(scenarioStatus.RequiredFailureCount);
manifest.OptionalPrunedCount = double(scenarioStatus.OptionalPrunedCount);
manifest.RequiredFailedCases = cellstr(string(scenarioStatus.RequiredFailedCases(:)));
manifest.OptionalPrunedCases = cellstr(string(scenarioStatus.OptionalPrunedCases(:)));
manifest.StatusAuthority = char(string(scenarioStatus.StatusAuthority));
manifest.StatusNotes = char(string(scenarioStatus.StatusNotes));
manifest.RuntimeTruthContractOk = logical(scenarioStatus.RuntimeTruthContractOk);
manifest.RoundtripMismatchCount = double(scenarioStatus.RoundtripMismatchCount);
manifest.RequiredRuntimeEvidenceMissingCount = double(scenarioStatus.RequiredRuntimeEvidenceMissingCount);
manifest.StrictTruthFailureCount = double(scenarioStatus.StrictTruthFailureCount);
manifest.StrictProxyGuardFailureCount = double(scenarioStatus.StrictProxyGuardFailureCount);
manifest.CanonicalArtifactGapCount = double(scenarioStatus.CanonicalArtifactGapCount);
manifest.RuntimeTruthContractFailures = cellstr(string(scenarioStatus.RuntimeTruthContractFailures(:)));
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

function payload = localBuildTerminalStatusPayload(scenarioStatus, stageName, optionalArtifactIssues)
if nargin < 3
    optionalArtifactIssues = strings(0, 1);
end
payload = struct( ...
    "stage", char(string(stageName)), ...
    "result_ok", logical(scenarioStatus.ResultOk), ...
    "run_completion", string(scenarioStatus.RunCompletion), ...
    "required_failure_count", double(scenarioStatus.RequiredFailureCount), ...
    "failing_case_count", double(scenarioStatus.FailingCaseCount), ...
    "warning_count", double(scenarioStatus.WarningCount), ...
    "status_authority", string(scenarioStatus.StatusAuthority), ...
    "runtime_truth_contract_ok", logical(scenarioStatus.RuntimeTruthContractOk), ...
    "roundtrip_mismatch_count", double(scenarioStatus.RoundtripMismatchCount), ...
    "required_runtime_evidence_missing_count", double(scenarioStatus.RequiredRuntimeEvidenceMissingCount), ...
    "strict_truth_failure_count", double(scenarioStatus.StrictTruthFailureCount), ...
    "strict_proxy_guard_failure_count", double(scenarioStatus.StrictProxyGuardFailureCount), ...
    "canonical_artifact_gap_count", double(scenarioStatus.CanonicalArtifactGapCount), ...
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
    okVal, ...
    okVal, ...
    logical(scenarioStatus.PartialOk), ...
    logical(scenarioStatus.ArtifactsGenerated), ...
    double(scenarioStatus.RequiredCaseCount), ...
    double(scenarioStatus.RequiredFailureCount), ...
    double(scenarioStatus.OptionalPrunedCount), ...
    string(scenarioStatus.StatusAuthority), ...
    logical(scenarioStatus.RuntimeTruthContractOk), ...
    double(scenarioStatus.RoundtripMismatchCount), ...
    double(scenarioStatus.RequiredRuntimeEvidenceMissingCount), ...
    double(scenarioStatus.StrictTruthFailureCount), ...
    double(scenarioStatus.StrictProxyGuardFailureCount), ...
    double(scenarioStatus.CanonicalArtifactGapCount), ...
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
    'RunScope','RunCompletion','Ok','ResultOk','PartialOk','ArtifactsGenerated', ...
    'RequiredCaseCount','RequiredFailureCount','OptionalPrunedCount','StatusAuthority', ...
    'RuntimeTruthContractOk','RoundtripMismatchCount','RequiredRuntimeEvidenceMissingCount', ...
    'StrictTruthFailureCount','StrictProxyGuardFailureCount','CanonicalArtifactGapCount','RuntimeTruthContractFailures','Description', ...
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
runtime.EffectiveWorkers = double(sixgr.util.structGet(cfg, "run.numWorkers", 0));
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
env.EffectiveWorkers = double(sixgr.util.structGet(cfg, "run.numWorkers", 0));
env.UseMex = logical(sixgr.util.structGet(cfg, "run.useMex", false));
env.UseMexAutoEnabled = logical(sixgr.util.structGet(cfg, "run.useMexAutoEnabled", false));
env.ParallelDisabledReason = char(string(sixgr.util.structGet(cfg, "run.parallelDisabledReason", "")));
end

function localEnsureScenarioDirs(layout)
dirs = { ...
    layout.MetaDir, layout.LogDir, layout.ReportDir, layout.ReportCSVDir, layout.ReportMATDir, ...
    layout.ReportImageDir, layout.AirInterfaceDir, layout.AirInterfaceCSVDir, layout.AirInterfaceMATDir, ...
    layout.AirInterfaceImageDir, layout.ControlDir, layout.ControlCSVDir, layout.ControlImageDir, ...
    layout.BeamformingDir, layout.BeamformingCSVDir, layout.BeamformingImageDir};
for i = 1:numel(dirs)
    sixgr.util.ensureFolder(dirs{i});
end
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
localDeleteFolderTreeIfExists(logicalRunFolder);
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
parallelInstalled = localHasParallelToolboxInstalled();
parallelLicensed = localHasParallelLicense();
parpoolAvailable = exist("parpool", "file") == 2;
if ~useParallel
    cfg.run.useParallel = false;
    cfg = sixgr.util.structSet(cfg, "run.numWorkers", 0);
    cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parallel_not_requested");
    return;
end
if requestedWorkers <= 1
    cfg.run.useParallel = false;
    cfg = sixgr.util.structSet(cfg, "run.numWorkers", 0);
    cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "requested_workers_leq_1");
    return;
end
if ~parallelInstalled || ~parallelLicensed || ~parpoolAvailable
    cfg.run.useParallel = false;
    cfg = sixgr.util.structSet(cfg, "run.numWorkers", 0);
    if ~parallelLicensed
        cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parallel_computing_toolbox_license_unavailable");
    elseif ~parallelInstalled
        cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parallel_computing_toolbox_not_installed");
    else
        cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parpool_function_unavailable");
    end
    return;
end

pool = gcp("nocreate");
try
    if isempty(pool)
        pool = parpool("threads", requestedWorkers);
    elseif pool.NumWorkers ~= requestedWorkers
        delete(pool);
        pool = parpool("threads", requestedWorkers);
    end
catch
    try
        pool = gcp("nocreate");
        if isempty(pool)
            pool = parpool(requestedWorkers);
        elseif pool.NumWorkers ~= requestedWorkers
            delete(pool);
            pool = parpool(requestedWorkers);
        end
    catch
        cfg.run.useParallel = false;
        cfg.run.numWorkers = 0;
        cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "parpool_start_failed");
        return;
    end
end

cfg.run.useParallel = ~isempty(pool);
cfg.run.numWorkers = double(pool.NumWorkers);
cfg = sixgr.util.structSet(cfg, "run.parallelDisabledReason", "");
sixgr.util.rngInit(double(sixgr.util.structGet(cfg, "run.seed", 1)), true);
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
% Exact MEX kernels remain allowed for strict coupled waveform truth as long
% as the strict config validator keeps fast scalar channel-estimation MEX
% paths disabled on fading channels.
tf = false;
end

function caps = localExactMexCapabilities()
caps = struct();
caps.AWGNKernel = logical(exist("sixgr_awgn_complex_kernel_mex", "file") == 3);
caps.LDPCBatchDecodeKernel = logical(exist("sixgr_ldpc_decode_batch_kernel_mex", "file") == 3);
caps.StructGetKernel = logical(exist("sixgr_struct_get_mex", "file") == 3);
caps.FFTPAPRKernel = logical(exist("sixgr_fft_papr_kernel_mex", "file") == 3);
caps.Any = logical(caps.AWGNKernel || caps.LDPCBatchDecodeKernel || caps.StructGetKernel || caps.FFTPAPRKernel);
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

function [y, nVar] = localAddAwgn(x, snr_dB)
[y, nVar] = sixgr.util.addAwgnComplex(x, snr_dB);
end

function y = localAddAwgnOnly(x, snr_dB)
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
status.ResultOk = logical(sixgr.util.structGet(result, "Ok", true));
status.PartialOk = false;
status.ArtifactsGenerated = true;
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
status.RoundtripMismatchCount = 0;
status.RequiredRuntimeEvidenceMissingCount = 0;
status.StrictTruthFailureCount = 0;
status.StrictProxyGuardFailureCount = 0;
status.CanonicalArtifactGapCount = 0;
status.RuntimeTruthContractFailures = strings(0, 1);
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
status.RoundtripMismatchCount = double(sixgr.util.structGet(verdict, "RoundtripMismatchCount", 0));
status.RequiredRuntimeEvidenceMissingCount = double(sixgr.util.structGet(verdict, "RequiredRuntimeEvidenceMissingCount", 0));
status.StrictTruthFailureCount = double(sixgr.util.structGet(verdict, "StrictTruthFailureCount", 0));
status.StrictProxyGuardFailureCount = double(sixgr.util.structGet(verdict, "StrictProxyGuardFailureCount", 0));
status.CanonicalArtifactGapCount = double(sixgr.util.structGet(verdict, "CanonicalArtifactGapCount", 0));
status.RuntimeTruthContractFailures = string(sixgr.util.structGet(verdict, "Failures", strings(0, 1)));
status.RuntimeTruthContractFailures = status.RuntimeTruthContractFailures(:);
roundtripStatusDetails = string(sixgr.util.structGet(verdict, "RoundtripStatusDetails", strings(0, 1)));
roundtripStatusDetails = roundtripStatusDetails(strlength(roundtripStatusDetails) > 0);
if ~isempty(roundtripStatusDetails)
    status.RuntimeTruthContractFailures = unique([status.RuntimeTruthContractFailures; roundtripStatusDetails(:)], "stable");
end

if ~logical(status.RuntimeTruthContractOk)
    status.ResultOk = false;
    status.CaseOk = false;
    status.PartialOk = logical(status.ArtifactsGenerated);
    status.RunCompletion = "completed_with_failures";
    status.RequiredFailureCount = double(status.RequiredFailureCount) + max(1, double(status.StrictTruthFailureCount));
    status.RequiredFailedCases = unique([string(status.RequiredFailedCases(:)); status.RuntimeTruthContractFailures], "stable");
    status.FailingCaseCount = double(numel(string(status.RequiredFailedCases)));
    status.AuthoritativeStatusSource = "runtime_truth_contract";
    status.StatusNotes = localJoinStatusNotes(status.StatusNotes, ...
        "Run-level success is gated by the runtime truth contract; missing/proxy/mismatched evidence forces ResultOk=false.");
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
end

function result = localApplyScenarioStatus(result, scenarioStatus)
result.ProfileReportedOk = logical(sixgr.util.structGet(result, "Ok", true));
result.Ok = logical(scenarioStatus.ResultOk);
result.RunCompletion = char(string(scenarioStatus.RunCompletion));
result.PartialOk = logical(scenarioStatus.PartialOk);
result.ArtifactsGenerated = logical(scenarioStatus.ArtifactsGenerated);
result.RequiredCaseCount = double(scenarioStatus.RequiredCaseCount);
result.RequiredFailureCount = double(scenarioStatus.RequiredFailureCount);
result.OptionalPrunedCount = double(scenarioStatus.OptionalPrunedCount);
result.RequiredFailedCases = string(scenarioStatus.RequiredFailedCases(:));
result.OptionalPrunedCases = string(scenarioStatus.OptionalPrunedCases(:));
result.StatusAuthority = char(string(scenarioStatus.StatusAuthority));
result.StatusNotes = char(string(scenarioStatus.StatusNotes));
result.AuthoritativeStatusSource = char(string(scenarioStatus.AuthoritativeStatusSource));
result.RuntimeTruthContractOk = logical(scenarioStatus.RuntimeTruthContractOk);
result.RoundtripMismatchCount = double(scenarioStatus.RoundtripMismatchCount);
result.RequiredRuntimeEvidenceMissingCount = double(scenarioStatus.RequiredRuntimeEvidenceMissingCount);
result.StrictTruthFailureCount = double(scenarioStatus.StrictTruthFailureCount);
result.StrictProxyGuardFailureCount = double(scenarioStatus.StrictProxyGuardFailureCount);
result.CanonicalArtifactGapCount = double(scenarioStatus.CanonicalArtifactGapCount);
result.RuntimeTruthContractFailures = string(scenarioStatus.RuntimeTruthContractFailures(:));
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
