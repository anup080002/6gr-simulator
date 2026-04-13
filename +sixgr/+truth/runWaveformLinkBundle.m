function out = runWaveformLinkBundle(cfg, runFolder, opt)
%RUNWAVEFORMLINKBUNDLE Run strict waveform link/control validation exports.

cfgL = cfg;
cfgL.run.mode = "link";
cfgL.run.shortRun = false;
cfgL.outputs.saveCSV = false;
cfgL.outputs.saveMAT = false;
cfgL.outputs.saveFigures = false;
cfgL.outputs.saveFIG = false;
cfgL.outputs.savePNG = true;
cfgL.channel.snr_dB = double(sixgr.util.structGet(opt, "LinkSNR_dB", 30));
multiUser = localResolveMultiUserSpec(cfgL);
cfgExec = localPrepareUserCfg(cfgL, multiUser, 1);

sixgr.util.ensureFolder(runFolder);
sixgr.util.ensureFolder(fullfile(runFolder, "csv"));
sixgr.util.ensureFolder(fullfile(runFolder, "mat"));
sixgr.util.ensureFolder(fullfile(runFolder, "image"));

ctx = sixgr.core.SimContext(cfgExec, "RunFolder", runFolder);
ctx.Logger.EchoToConsole = false;

slotDur_s = localSlotDuration(cfgExec);
reqFrames = ceil(double(sixgr.util.structGet(opt, "LinkDuration_s", 0.02)) / max(slotDur_s, eps));
numFrames = max(8, min(round(double(sixgr.util.structGet(opt, "LinkMaxSimFrames", 8))), reqFrames));

params = struct();
params.NumFrames = numFrames;
params.ForceLong = true;

localLogStage(ctx, "Starting strict waveform LLS bundle: frames=" + string(numFrames) + ...
    ", snr_anchor_db=" + string(double(sixgr.util.structGet(opt, "LinkSNR_dB", 30))));
res = sixgr.link.LinkLevelRunner.run(ctx, params);
unsupportedCases = table();
[res, unsupportedCases] = localPruneUnsupportedTruthCases(res);
if istable(unsupportedCases) && ~isempty(unsupportedCases)
    localLogStage(ctx, "Pruned unsupported truth-only cases from KPI table: " + string(height(unsupportedCases)));
end
sweepPlan = localResolveSweepPlan(opt, numFrames);
snrGrid = localReduceSweepGrid( ...
    double(sixgr.util.structGet(opt, "LinkSNRGrid_dB", [-30 -20 -10 0 10 20 30 40])), ...
    double(sweepPlan.MaxSweepPoints), ...
    double(sixgr.util.structGet(opt, "LinkSNR_dB", 30)));
localLogStage(ctx, "Exporting raw truth trial tables across SNR grid [" + ...
    strjoin(string(round(snrGrid(:).', 6)), ", ") + "].");
rawTrials = localExportLinkRawTrialTables(cfgExec, runFolder, res, sweepPlan.PrimaryTrialsPerSNR, snrGrid(:), multiUser);
localLogStage(ctx, "Building primary SNR sweep from raw truth trials.");
res.SNRSweep = localBuildSNRSweepFromRawTrials(rawTrials, cfgExec, snrGrid(:));
refinedGrid = localBuildAdaptiveRefinedGrid(res.SNRSweep, snrGrid(:), cfgExec, opt);
if ~isempty(refinedGrid)
    localLogStage(ctx, "Refining truth SNR sweep near the observed waterfall at [" + ...
        strjoin(string(round(refinedGrid(:).', 6)), ", ") + "].");
    rawTrials = localAugmentRawTrialsWithRefinedSweep(cfgExec, runFolder, rawTrials, sweepPlan.PrimaryTrialsPerSNR, refinedGrid(:), multiUser);
    snrGrid = unique(sort([double(snrGrid(:)); double(refinedGrid(:))]));
    res.SNRSweep = localBuildSNRSweepFromRawTrials(rawTrials, cfgExec, snrGrid(:));
end
localLogStage(ctx, "Running fixed-reference SNR sweep.");
res.ReferenceSweep = localRunReferenceLinkSNRSweep(cfgExec, snrGrid(:), sweepPlan.ReferenceTrialsPerSNR, multiUser, sweepPlan);
localLogStage(ctx, "Applying primary sweep results to the authoritative KPI table.");
res = localApplyPrimarySweepResults(res, rawTrials, cfgExec, snrGrid(:));
res.PAPRCCDF = localBuildPAPRCCDFTable(rawTrials);
if logical(multiUser.Enabled)
    res.MultiUserMode = string(multiUser.ExecutionModel);
    res.MultiUserEnabled = logical(multiUser.Enabled);
    res.MultiUserCount = double(multiUser.NumUsers);
end
localLogStage(ctx, "Writing primary and reference sweep CSV artifacts.");
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_snr_sweep.csv"), res.SNRSweep);
if istable(res.ReferenceSweep) && ~isempty(res.ReferenceSweep)
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_reference_snr_sweep.csv"), res.ReferenceSweep);
end
saveFigures = logical(sixgr.util.structGet(opt, "SaveFigures", true));
localLogStage(ctx, "Exporting HARQ diagnostics.");
harqArtifacts = sixgr.truth.exportLLSHARQDiagnostics(cfgExec, runFolder, opt);
localLogStage(ctx, "Exporting beamforming diagnostics.");
beamArtifacts = localExportBeamformingDiagnostics(cfgExec, runFolder, rawTrials, saveFigures);
localLogStage(ctx, "Exporting RF and energy diagnostics.");
energyArtifacts = sixgr.truth.exportLLSEnergyDiagnostics(cfgExec, runFolder, rawTrials);
localLogStage(ctx, "Exporting trial diagnostic plots.");
trialPlots = localExportTrialDiagnosticPlots(runFolder, rawTrials, saveFigures);

localLogStage(ctx, "Checking primary-link export integrity.");
[kpi, integrity] = sixgr.link.enforcePrimaryLinkExportIntegrity(cfgExec, sixgr.util.structGet(res, "KPITable", table()), rawTrials);
res.KPITable = kpi;
localLogStage(ctx, "Exporting structured link KPI bundle and report inputs.");
arts = sixgr.link.exportLinkKPIs(runFolder, kpi, res, ...
    "SaveCSV", true, ...
    "SaveMAT", true, ...
    "SaveFigures", logical(sixgr.util.structGet(opt, "SaveFigures", true)), ...
    "SavePNG", true, ...
    "FigurePrefix", "link_truth_validation", ...
    "PlotVisible", false, ...
    "FigureResolution", 140);

out = struct();
out.Ok = logical(localLinkKPITableHealthy(kpi));
out.RunFolder = runFolder;
out.Result = res;
out.KPITable = kpi;
out.SNRSweep = res.SNRSweep;
out.ReferenceSweep = sixgr.util.structGet(res, "ReferenceSweep", table());
out.RawTrials = rawTrials;
out.Artifacts = arts;
out.BeamformingArtifacts = beamArtifacts;
out.HARQArtifacts = harqArtifacts;
out.EnergyArtifacts = energyArtifacts;
out.TrialDiagnosticPlots = trialPlots;
out.Integrity = integrity;
out.Errors = sixgr.util.structGet(res, "Errors", strings(0,1));
out.UnsupportedCases = unsupportedCases;
out.MultiUser = multiUser;
localLogStage(ctx, "Strict waveform LLS bundle completed.");
end

function localLogStage(ctx, msg)
if ~(isa(ctx, "sixgr.core.SimContext") && isprop(ctx, "Logger") && ~isempty(ctx.Logger))
    return;
end
try
    ctx.Logger.info(string(msg));
catch
end
end

function [res, unsupported] = localPruneUnsupportedTruthCases(res)
unsupported = table();
if ~(isstruct(res) && isfield(res, "KPITable") && istable(res.KPITable) && ~isempty(res.KPITable))
    return;
end
caseCol = string(res.KPITable.Case);
noteCol = strings(height(res.KPITable), 1);
if ismember("Notes", string(res.KPITable.Properties.VariableNames))
    noteCol = lower(string(res.KPITable.Notes));
end
mask = strcmpi(caseCol, "PRACH_Detection") & ( ...
    contains(noteCol, "cfg.phy.prach.enable=false") | ...
    contains(noteCol, "nrprach/nrprachdetect unavailable") | ...
    contains(noteCol, "prach waveform is empty"));
if any(mask)
    unsupported = res.KPITable(mask, :);
    if ismember("Notes", string(unsupported.Properties.VariableNames))
        unsupported.Notes = string(unsupported.Notes) + "|unsupported_in_truth_validation_profile";
    end
    res.KPITable = res.KPITable(~mask, :);
end
end

function T = localRunLinkSNRSweep(cfg, snrGrid, nFrames, multiUser)
if nargin < 4 || ~isstruct(multiUser)
    multiUser = localResolveMultiUserSpec(cfg);
end
if logical(sixgr.util.structGet(multiUser, "Enabled", false))
    rows = repmat(struct("UEIndex", NaN, "RNTI", NaN, "SNR_dB", NaN, ...
        "DL_BER", NaN, "DL_BLER", NaN, "DL_Throughput_Mbps", NaN, ...
        "DL_OfferedThroughput_Mbps", NaN, "DL_Goodput_Mbps", NaN, ...
        "DL_CodeBlockBLER", NaN, "DL_CBG_BLER", NaN, ...
        "UL_BER", NaN, "UL_BLER", NaN, "UL_Throughput_Mbps", NaN, ...
        "UL_OfferedThroughput_Mbps", NaN, "UL_Goodput_Mbps", NaN, ...
        "UL_CodeBlockBLER", NaN, "UL_CBG_BLER", NaN, ...
        "SRS_NMSE_dB", NaN, "BeamSelectionStrategy", "", ...
        "ExecutionModel", ""), 0, 1);
    for ueIdx = 1:max(1, round(double(multiUser.NumUsers)))
        cfgU = localPrepareUserCfg(cfg, multiUser, ueIdx);
        Tu = localRunLinkSNRSweep(cfgU, snrGrid, nFrames, localSingleUserSpec(multiUser));
        if isempty(Tu)
            continue;
        end
        for r = 1:height(Tu)
            rows(end+1,1) = struct( ... %#ok<AGROW>
                "UEIndex", double(ueIdx), ...
                "RNTI", double(localUserRNTI(multiUser, ueIdx)), ...
                "SNR_dB", double(Tu.SNR_dB(r)), ...
                "DL_BER", double(Tu.DL_BER(r)), ...
                "DL_BLER", double(Tu.DL_BLER(r)), ...
                "DL_Throughput_Mbps", double(Tu.DL_Throughput_Mbps(r)), ...
                "DL_OfferedThroughput_Mbps", double(Tu.DL_OfferedThroughput_Mbps(r)), ...
                "DL_Goodput_Mbps", double(Tu.DL_Goodput_Mbps(r)), ...
                "DL_CodeBlockBLER", double(Tu.DL_CodeBlockBLER(r)), ...
                "DL_CBG_BLER", double(Tu.DL_CBG_BLER(r)), ...
                "UL_BER", double(Tu.UL_BER(r)), ...
                "UL_BLER", double(Tu.UL_BLER(r)), ...
                "UL_Throughput_Mbps", double(Tu.UL_Throughput_Mbps(r)), ...
                "UL_OfferedThroughput_Mbps", double(Tu.UL_OfferedThroughput_Mbps(r)), ...
                "UL_Goodput_Mbps", double(Tu.UL_Goodput_Mbps(r)), ...
                "UL_CodeBlockBLER", double(Tu.UL_CodeBlockBLER(r)), ...
                "UL_CBG_BLER", double(Tu.UL_CBG_BLER(r)), ...
                "SRS_NMSE_dB", double(Tu.SRS_NMSE_dB(r)), ...
                "BeamSelectionStrategy", string(multiUser.BeamSelectionStrategy), ...
                "ExecutionModel", string(multiUser.ExecutionModel));
        end
    end
    if isempty(rows)
        T = table();
    else
        T = struct2table(rows);
    end
    return;
end

n = numel(snrGrid);
rows = repmat(localEmptySweepSummaryRow(0), n, 1);
nFrames = max(1, round(double(nFrames)));
useParallelSweep = localCanParallelizeSweep(cfg, n);
seedBase = double(sixgr.util.structGet(cfg, "run.seed", 1));
if useParallelSweep
    rows = cell(n,1);
    parfor i = 1:n
        rows{i} = localRunSweepPointDeterministic(cfg, double(snrGrid(i)), nFrames, seedBase + 1000 + i);
    end
    rows = vertcat(rows{:});
else
    for i = 1:n
        rows(i,1) = localRunSweepPointDeterministic(cfg, double(snrGrid(i)), nFrames, seedBase + 1000 + i);
    end
end
T = struct2table(rows);
end

function tf = localCanParallelizeSweep(cfg, nPoints)
tf = logical(sixgr.util.structGet(cfg, "run.useParallel", false)) && ...
    double(sixgr.util.structGet(cfg, "run.numWorkers", 0)) > 1 && ...
    nPoints > 1 && exist("gcp", "file") == 2 && ~isempty(gcp("nocreate"));
end

function row = localRunSweepPointDeterministic(cfg, snr, nFrames, seed)
row = localEmptySweepSummaryRow(snr);

try
    rng(double(seed), "twister");
    dl = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", nFrames, "SNR_dB", snr);
    if ~logical(sixgr.util.structGet(dl, "Skipped", false))
        dlTrials = localEnsureLinkTrialTable(sixgr.util.structGet(dl, "TrialTable", table()), "DL", snr, cfg);
        dlStats = localSummarizeLinkTrialTable(dlTrials, cfg);
        row = localApplyLinkSweepStats(row, "DL", dlStats);
    end
catch
end

try
    rng(double(seed) + 10000, "twister");
    ul = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", nFrames, "SNR_dB", snr);
    if ~logical(sixgr.util.structGet(ul, "Skipped", false))
        ulTrials = localEnsureLinkTrialTable(sixgr.util.structGet(ul, "TrialTable", table()), "UL", snr, cfg);
        ulStats = localSummarizeLinkTrialTable(ulTrials, cfg);
        row = localApplyLinkSweepStats(row, "UL", ulStats);
    end
catch
end

try
    rng(double(seed) + 20000, "twister");
    srs = sixgr.link.runSRSChannelEstimation(cfg, "SNR_dB", snr);
    if ~logical(sixgr.util.structGet(srs, "Skipped", false))
        nmse = double(sixgr.util.structGet(srs, "NMSE_dB", NaN));
        if isfinite(nmse)
            row.SRS_NMSE_dB = nmse;
            row.SRS_NMSE_CI_Low = nmse;
            row.SRS_NMSE_CI_High = nmse;
            row.SRS_TrialCount = 1;
        end
    end
catch
end
end

function out = localExportLinkRawTrialTables(cfg, runFolder, linkRes, nFrames, snrGrid_dB, multiUser)
if nargin < 6 || ~isstruct(multiUser)
    multiUser = localResolveMultiUserSpec(cfg);
end
csvDir = fullfile(runFolder, "csv");
sixgr.util.ensureFolder(csvDir);

nTrials = max(8, round(double(nFrames)));
snrGrid = unique(sort(double(snrGrid_dB(:))));
if isempty(snrGrid)
    snrGrid = double(sixgr.util.structGet(cfg, "channel.snr_dB", 30));
end

if logical(multiUser.Enabled)
    [dlTrials, dlUserSummary] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, "DL", nTrials, snrGrid);
    dlConst = table();
else
    [dlTrials, dlConst] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, "DL", nTrials, snrGrid);
    dlUserSummary = table();
end
fDL = fullfile(csvDir, "dl_pdsch_trials.csv");
sixgr.util.csvWriteTable(fDL, dlTrials);

if logical(multiUser.Enabled)
    [ulTrials, ulUserSummary] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, "UL", nTrials, snrGrid);
    ulConst = table();
else
    [ulTrials, ulConst] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, "UL", nTrials, snrGrid);
    ulUserSummary = table();
end
fUL = fullfile(csvDir, "ul_pusch_trials.csv");
sixgr.util.csvWriteTable(fUL, ulTrials);

if istable(dlConst) && ~isempty(dlConst)
    outDLConst = fullfile(csvDir, "dl_constellation_samples.csv");
    sixgr.util.csvWriteTable(outDLConst, dlConst);
else
    outDLConst = "";
end

if istable(ulConst) && ~isempty(ulConst)
    outULConst = fullfile(csvDir, "ul_constellation_samples.csv");
    sixgr.util.csvWriteTable(outULConst, ulConst);
else
    outULConst = "";
end

pbchTrials = localCollectTrialsAcrossSweep(@(snr) localCollectPBCHTrials(cfg, snr, max(4, ceil(nTrials/4))), snrGrid);
fPBCH = fullfile(csvDir, "pbch_trials.csv");
sixgr.util.csvWriteTable(fPBCH, pbchTrials);

prachTrials = localCollectTrialsAcrossSweep(@(snr) localCollectPRACHTrials(cfg, snr, max(4, ceil(nTrials/4))), snrGrid);
fPRACH = fullfile(csvDir, "prach_trials.csv");
sixgr.util.csvWriteTable(fPRACH, prachTrials);

pdcchTrials = localCollectTrialsAcrossSweep(@(snr) localCollectPDCCHTrials(cfg, snr, max(8, ceil(nTrials/2))), snrGrid);
fPDCCH = fullfile(csvDir, "pdcch_trials.csv");
sixgr.util.csvWriteTable(fPDCCH, pdcchTrials);

pucchTrials = localCollectTrialsAcrossSweep(@(snr) localCollectPUCCHTrials(cfg, snr, max(8, ceil(nTrials/2))), snrGrid);
fPUCCH = fullfile(csvDir, "pucch_trials.csv");
sixgr.util.csvWriteTable(fPUCCH, pucchTrials);

srsTrials = localCollectTrialsAcrossSweep(@(snr) localCollectSRSTrials(cfg, snr, max(6, ceil(nTrials/3))), snrGrid);
fSRS = fullfile(csvDir, "srs_trials.csv");
sixgr.util.csvWriteTable(fSRS, srsTrials);

trsTrials = localCollectTrialsAcrossSweep(@(snr) localCollectTRSTrials(cfg, snr, max(6, ceil(nTrials/3))), snrGrid);
fTRS = fullfile(csvDir, "trs_trials.csv");
sixgr.util.csvWriteTable(fTRS, trsTrials);

out = struct();
out.DL = dlTrials;
out.UL = ulTrials;
out.PBCH = pbchTrials;
out.PRACH = prachTrials;
out.PDCCH = pdcchTrials;
out.PUCCH = pucchTrials;
out.SRS = srsTrials;
out.TRS = trsTrials;
out.DLPath = fDL;
out.ULPath = fUL;
out.DLConstellation = dlConst;
out.ULConstellation = ulConst;
out.DLConstellationPath = outDLConst;
out.ULConstellationPath = outULConst;
out.PBCHPath = fPBCH;
out.PRACHPath = fPRACH;
out.PDCCHPath = fPDCCH;
out.PUCCHPath = fPUCCH;
out.SRSPath = fSRS;
out.TRSPath = fTRS;
out.MultiUserDL = dlUserSummary;
out.MultiUserUL = ulUserSummary;
if logical(multiUser.Enabled) && logical(multiUser.SaveUserTables)
    out.MultiUserSummaryPath = fullfile(csvDir, "multiuser_user_summary.csv");
    userSummary = localMergeMultiUserSummaries(dlUserSummary, ulUserSummary, multiUser);
    sixgr.util.csvWriteTable(out.MultiUserSummaryPath, userSummary);
end
end

function out = localAugmentRawTrialsWithRefinedSweep(cfg, runFolder, rawTrials, nFrames, snrGrid_dB, multiUser)
out = rawTrials;
snrGrid = unique(sort(double(snrGrid_dB(:))));
if isempty(snrGrid)
    return;
end
csvDir = fullfile(runFolder, "csv");
sixgr.util.ensureFolder(csvDir);

if logical(multiUser.Enabled)
    [dlTrials, dlUserSummary] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, "DL", nFrames, snrGrid);
    [ulTrials, ulUserSummary] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, "UL", nFrames, snrGrid);
    out.MultiUserDL = localAppendCompatTable(sixgr.util.structGet(rawTrials, "MultiUserDL", table()), dlUserSummary);
    out.MultiUserUL = localAppendCompatTable(sixgr.util.structGet(rawTrials, "MultiUserUL", table()), ulUserSummary);
else
    [dlTrials, ~] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, "DL", nFrames, snrGrid);
    [ulTrials, ~] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, "UL", nFrames, snrGrid);
end

srsTrials = localCollectTrialsAcrossSweep(@(snr) localCollectSRSTrials(cfg, snr, max(6, ceil(nFrames/3))), snrGrid);

out.DL = localAppendCompatTable(rawTrials.DL, dlTrials);
out.UL = localAppendCompatTable(rawTrials.UL, ulTrials);
out.SRS = localAppendCompatTable(sixgr.util.structGet(rawTrials, "SRS", table()), srsTrials);

out.DL = localSortTrialTableBySweep(out.DL);
out.UL = localSortTrialTableBySweep(out.UL);
out.SRS = localSortTrialTableBySweep(out.SRS);

sixgr.util.csvWriteTable(fullfile(csvDir, "dl_pdsch_trials.csv"), out.DL);
sixgr.util.csvWriteTable(fullfile(csvDir, "ul_pusch_trials.csv"), out.UL);
if istable(out.SRS) && ~isempty(out.SRS)
    sixgr.util.csvWriteTable(fullfile(csvDir, "srs_trials.csv"), out.SRS);
end
if logical(multiUser.Enabled) && isfield(out, "MultiUserSummaryPath") && strlength(string(out.MultiUserSummaryPath)) > 0
    userSummary = localMergeMultiUserSummaries(out.MultiUserDL, out.MultiUserUL, multiUser);
    sixgr.util.csvWriteTable(char(string(out.MultiUserSummaryPath)), userSummary);
end
end

function T = localGetCaseTrialTable(linkRes, caseField)
T = table();
caseStruct = localGetCaseStruct(linkRes, caseField);
if isempty(fieldnames(caseStruct))
    return;
end
try
    T = sixgr.util.structGet(caseStruct, "TrialTable", table());
catch
    T = table();
end
if ~istable(T)
    T = table();
end
end

function caseStruct = localGetCaseStruct(linkRes, caseField)
caseStruct = struct();
if ~(builtin("isstruct", linkRes) && isscalar(linkRes))
    return;
end
cases = sixgr.util.structGet(linkRes, "Cases", struct());
if ~(builtin("isstruct", cases) && isscalar(cases) && isfield(cases, char(caseField)))
    return;
end
try
    caseStruct = cases.(char(caseField));
catch
    caseStruct = struct();
end
end

function [T, constT] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, direction, nTrials, snrGrid)
T = localEmptyLinkTrialTable(0);
constT = table();
direction = upper(string(direction));
snrGrid = unique(sort(double(snrGrid(:))));
for i = 1:numel(snrGrid)
    snr = double(snrGrid(i));
    if direction == "DL"
        res = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", nTrials, "SNR_dB", snr);
    else
        res = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", nTrials, "SNR_dB", snr);
    end
    Ti = localEnsureLinkTrialTable(sixgr.util.structGet(res, "TrialTable", table()), direction, snr, cfg);
    T = localAppendCompatTable(T, Ti);
    constT = localAppendCompatTable(constT, sixgr.util.structGet(res, "ConstellationSamples", table()));
end
end

function [T, summaryT] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, direction, nTrials, snrGrid)
T = localEmptyLinkTrialTable(0);
parts = {};
snrGrid = unique(sort(double(snrGrid(:))));
for i = 1:numel(snrGrid)
    [Ti, Si] = localCollectMultiUserLinkTrials(cfg, multiUser, direction, nTrials, double(snrGrid(i)));
    T = localAppendCompatTable(T, Ti);
    if istable(Si) && ~isempty(Si)
        parts{end+1} = Si; %#ok<AGROW>
    end
end
if isempty(parts)
    summaryT = table();
else
    summaryT = vertcat(parts{:});
end
end

function T = localCollectTrialsAcrossSweep(collectorFcn, snrGrid)
T = table();
snrGrid = unique(sort(double(snrGrid(:))));
for i = 1:numel(snrGrid)
    Ti = collectorFcn(double(snrGrid(i)));
    T = localAppendCompatTable(T, Ti);
end
end

function Tout = localAppendCompatTable(Ta, Tb)
if ~(istable(Ta) && ~isempty(Ta))
    if istable(Tb)
        Tout = Tb;
    else
        Tout = table();
    end
    return;
end
if ~(istable(Tb) && ~isempty(Tb))
    Tout = Ta;
    return;
end
vars = union(string(Ta.Properties.VariableNames), string(Tb.Properties.VariableNames), "stable");
Ta = localEnsureTableVars(Ta, vars, Tb);
Tb = localEnsureTableVars(Tb, vars, Ta);
Tout = [Ta(:, cellstr(vars)); Tb(:, cellstr(vars))];
end

function T = localEnsureTableVars(T, vars, refT)
for i = 1:numel(vars)
    v = char(vars(i));
    if ~ismember(v, T.Properties.VariableNames)
        T.(v) = localDefaultColumnLike(refT, v, height(T));
    end
end
end

function col = localDefaultColumnLike(refT, varName, nRows)
if istable(refT) && ismember(varName, refT.Properties.VariableNames)
    refVal = refT.(varName);
    if isstring(refVal)
        col = strings(nRows, 1);
        return;
    end
    if islogical(refVal)
        col = false(nRows, 1);
        return;
    end
    if isnumeric(refVal)
        col = NaN(nRows, 1);
        return;
    end
end
col = strings(nRows, 1);
end

function T = localEnsureLinkTrialTable(Tin, direction, snr_dB, cfg)
vars = {'Direction','SNR_dB','Seed','Frame','Slot','MCS','PRBs','Layers','Modulation','TargetCodeRate','TBSize_bits', ...
    'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB', ...
    'DetectionMetric','MeasuredSINR_dB','WidebandCQI','RankIndicator','PMI','CRI','PMIType', ...
    'PMICodebookMode','CSIReportMode','CSIPayloadBitLength','CSIPayloadHex', ...
    'FalseAlarmFlag','BlockingFlag','BlindDecodeCount','AvailableCCECount','UsedCCECount', ...
    'NonOverlappedCCEUsage','AggregationLevel','DCISize_bits','ControlCapacityBits', ...
    'ControlCapacityUtilization','CORESETUtilization','ControlLatency_ms', ...
    'ChannelGain_dB','NoiseVariance','TimingOffset_samples','RankEstimate', ...
    'ConditionNumber_dB','NumRxAntennas','NumTxPorts', ...
    'SelectedBeamIndex','BestBeamIndex','BeamHit','TopKBeamHit','BeamCandidateCount', ...
    'SelectedBeamGain_dB','BestBeamGain_dB','BeamGainGap_dB', ...
    'ConfiguredPMI','ConfiguredCRI','BitErrors','BitsCompared', ...
    'OfferedBits','GoodBits','OfferedThroughput_Mbps','Goodput_Mbps', ...
    'ComputeLatency_ms','ProcedureDelay_ms','AirInterfaceTTI_ms','AirInterfaceObservation_ms', ...
    'Latency_ms','DecodeLatency_ms','EarlyStopRate','DecoderComplexityUnits','NormalizedDecoderComplexity','AreaEfficiencyProxy', ...
    'NumCodeBlocks','CodeBlockLength_bits','SegmentationOccurred','SegmentationPaddingBits','TBCRCLength_bits','TBLengthWithCRC_bits','BaseGraph', ...
    'EncodedBits','RateMatchedBits','RateMatchPunctureBits','RateMatchRepetitionBits', ...
    'CodeBlockErrors','CodeBlockCount','CodeBlockBLER','CBGErrors','CBGCount','CBGBLER', ...
    'PAPR_dB','PeakClippingEvents','SymbolErrors','SymbolsCompared','SymbolErrorRate', ...
    'ResidualInterferencePower_dB', ...
    'LLRMeanAbs','LLRStdAbs','LLRImbalance','ModulationMappingSensitivity', ...
    'ShapingRateLoss','DistributionMatchingLatency_ms','HighOrderRobustness', ...
    'DetectorComplexityUnits_Modulation','DataRECount','DMRSRECount','PTRSRECount','RSOverheadFraction', ...
    'InjectedCFO_Hz','EstimatedCFO_PreCorrection_Hz','ResidualCFO_PostCorrection_Hz', ...
    'EstimatedCFO_Hz','TrueCFO_Hz','CFOError_Hz', ...
    'InjectedTimingOffset_samples','EstimatedTimingOffset_PreCorrection_samples','ResidualTimingError_PostCorrection_samples', ...
    'TrueTimingOffset_samples','TimingError_samples', ...
    'InjectedDoppler_Hz','EstimatedDopplerHz','DopplerError_Hz','PhaseTrackingError_deg','QCLAccuracy', ...
    'ChannelAgingLoss_dB','InterpolationLoss_dB','MismatchSensitivity_dB','AcquisitionTime_ms','TrackingFailureProbability', ...
    'Status','Crash', ...
    'LinkAdaptationApplied','LinkAdaptationScheduled','IsWarmupFrame','Notes'};
if nargin < 1 || ~istable(Tin)
    Tin = table();
end
if isempty(Tin)
    T = localEmptyLinkTrialTable(0);
    return;
end
T = Tin;
for i = 1:numel(vars)
    v = vars{i};
    if ~ismember(v, T.Properties.VariableNames)
        switch v
            case {'Direction','ChannelModel','Status','Notes','PMIType','PMICodebookMode','CSIReportMode','Modulation','CSIPayloadHex'}
                T.(v) = strings(height(T),1);
            case 'Crash'
                T.(v) = false(height(T),1);
            case {'LinkAdaptationApplied','LinkAdaptationScheduled','IsWarmupFrame'}
                T.(v) = false(height(T),1);
            otherwise
                T.(v) = NaN(height(T),1);
        end
    end
end
T = T(:, vars);
if all(strlength(string(T.Direction)) == 0)
    T.Direction(:) = string(direction);
end
if all(~isfinite(double(T.SNR_dB)))
    T.SNR_dB(:) = double(snr_dB);
end
reqModel = localResolveRequestedLinkChannelModel(cfg);
if all(strlength(string(T.ChannelModel)) == 0)
    T.ChannelModel(:) = reqModel;
end
uCm = upper(strtrim(string(T.ChannelModel)));
maskTDL = (uCm == "TDL") & startsWith(reqModel, "TDL");
if any(maskTDL)
    T.ChannelModel(maskTDL) = reqModel;
end
maskCDL = (uCm == "CDL") & startsWith(reqModel, "CDL");
if any(maskCDL)
    T.ChannelModel(maskCDL) = reqModel;
end
if all(~isfinite(double(T.DopplerHz)))
    T.DopplerHz(:) = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
        sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 0))));
end
if all(~isfinite(double(T.InjectedDoppler_Hz))) && any(isfinite(double(T.DopplerHz)))
    T.InjectedDoppler_Hz = double(T.DopplerHz);
end
if all(~isfinite(double(T.Seed)))
    seed0 = double(sixgr.util.structGet(cfg, "run.seed", 1));
    T.Seed = seed0 + (0:height(T)-1).';
end
if all(~isfinite(double(T.Frame)))
    T.Frame = (1:height(T)).';
end
if all(~isfinite(double(T.Slot)))
    T.Slot = T.Frame;
end
if all(strlength(string(T.Status)) == 0)
    T.Status(:) = "NA";
end
if all(strlength(string(T.Notes)) == 0)
    T.Notes(:) = "";
end
if all(~isfinite(double(T.ComputeLatency_ms))) && any(isfinite(double(T.Latency_ms)))
    T.ComputeLatency_ms = double(T.Latency_ms);
end
if all(~isfinite(double(T.InjectedCFO_Hz))) && any(isfinite(double(T.TrueCFO_Hz)))
    T.InjectedCFO_Hz = double(T.TrueCFO_Hz);
end
if all(~isfinite(double(T.EstimatedCFO_PreCorrection_Hz))) && any(isfinite(double(T.EstimatedCFO_Hz)))
    T.EstimatedCFO_PreCorrection_Hz = double(T.EstimatedCFO_Hz);
end
if all(~isfinite(double(T.ResidualCFO_PostCorrection_Hz))) && any(isfinite(double(T.CFOError_Hz)))
    T.ResidualCFO_PostCorrection_Hz = double(T.CFOError_Hz);
end
if all(~isfinite(double(T.InjectedTimingOffset_samples))) && any(isfinite(double(T.TrueTimingOffset_samples)))
    T.InjectedTimingOffset_samples = double(T.TrueTimingOffset_samples);
end
if all(~isfinite(double(T.EstimatedTimingOffset_PreCorrection_samples))) && any(isfinite(double(T.TimingOffset_samples)))
    T.EstimatedTimingOffset_PreCorrection_samples = double(T.TimingOffset_samples);
end
if all(~isfinite(double(T.ResidualTimingError_PostCorrection_samples))) && any(isfinite(double(T.TimingError_samples)))
    T.ResidualTimingError_PostCorrection_samples = double(T.TimingError_samples);
end
warmMask = false(height(T), 1);
if ismember("LinkAdaptationScheduled", string(T.Properties.VariableNames)) && ...
        ismember("LinkAdaptationApplied", string(T.Properties.VariableNames))
    warmMask = logical(T.LinkAdaptationScheduled) & ~logical(T.LinkAdaptationApplied);
end
T.IsWarmupFrame = logical(warmMask);
end

function model = localResolveRequestedLinkChannelModel(cfg)
model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", "AWGN"))));
if strlength(model) == 0 || model == "NONE" || model == "OFF"
    model = "AWGN";
end
if model == "TDL"
    prof = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.tdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", "")))));
    if strlength(prof) > 0
        model = prof;
    end
elseif model == "CDL"
    prof = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.cdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", "")))));
    if strlength(prof) > 0
        model = prof;
    end
end
end

function T = localCollectPBCHTrials(cfg, snr_dB, nTrials)
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "DL", snr_dB, 1), nTrials, 1);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "DL", snr_dB, k);
    r.Status = "FAIL";
    try
        out = sixgr.link.runCellSearch_MIB_SIB1(cfg, "NumSubframes", 10);
        ok = logical(sixgr.util.structGet(out, "Ok", false)) && ~logical(sixgr.util.structGet(out, "Skipped", false));
        r.CRCPass = double(ok);
        r.InjectedCFO_Hz = double(sixgr.util.structGet(out, "InjectedCFO_Hz", NaN));
        r.EstimatedCFO_PreCorrection_Hz = double(sixgr.util.structGet(out, "EstimatedCFO_PreCorrection_Hz", NaN));
        r.ResidualCFO_PostCorrection_Hz = double(sixgr.util.structGet(out, "ResidualCFO_PostCorrection_Hz", NaN));
        r.EstimatedCFO_Hz = double(sixgr.util.structGet(out, "FreqOffsetEstimate_Hz", NaN));
        r.TrueCFO_Hz = double(sixgr.util.structGet(out, "TrueCFO_Hz", NaN));
        r.CFOError_Hz = double(sixgr.util.structGet(out, "CFOError_Hz", NaN));
        r.InjectedTimingOffset_samples = double(sixgr.util.structGet(out, "InjectedTimingOffset_samples", NaN));
        r.EstimatedTimingOffset_PreCorrection_samples = double(sixgr.util.structGet(out, "EstimatedTimingOffset_PreCorrection_samples", NaN));
        r.ResidualTimingError_PostCorrection_samples = double(sixgr.util.structGet(out, "ResidualTimingError_PostCorrection_samples", NaN));
        r.TimingOffset_samples = double(sixgr.util.structGet(out, "TimingOffset_samples", NaN));
        r.TrueTimingOffset_samples = double(sixgr.util.structGet(out, "TrueTimingOffset_samples", 0));
        r.TimingError_samples = double(sixgr.util.structGet(out, "TimingError_samples", NaN));
        r.ComputeLatency_ms = double(sixgr.util.structGet(out, "ComputeLatency_ms", NaN));
        r.ProcedureDelay_ms = double(sixgr.util.structGet(out, "ProcedureDelay_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(out, "AirInterfaceObservation_ms", NaN));
        r.AcquisitionTime_ms = double(sixgr.util.structGet(out, "AcquisitionTime_ms", NaN));
        r.TrackingFailureProbability = double(~ok);
        if ok
            r.DetectionMetric = 1;
            r.Status = "PASS";
        end
        r.Notes = string(sixgr.util.structGet(out, "Notes", ""));
    catch ME
        r.Crash = true;
        r.CRCPass = 0;
        r.Status = "CRASH";
        r.Notes = string(ME.message);
    end
    rows(k) = r;
end
T = struct2table(rows);
end

function T = localCollectPRACHTrials(cfg, snr_dB, nTrials)
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "UL", snr_dB, 1), nTrials, 1);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "UL", snr_dB, k);
    r.Status = "FAIL";
    try
        out = sixgr.link.runPRACHDetection(cfg, "SNR_dB", snr_dB);
        completed = logical(sixgr.util.structGet(out, "Ok", false)) && ~logical(sixgr.util.structGet(out, "Skipped", false));
        detected = logical(sixgr.util.structGet(out, "Detected", false));
        r.CRCPass = double(detected);
        r.DetectionMetric = double(sixgr.util.structGet(out, "DetectionMetric", double(detected)));
        r.TimingError_samples = double(sixgr.util.structGet(out, "TimingOffset_samples", NaN));
        r.ComputeLatency_ms = double(sixgr.util.structGet(out, "ComputeLatency_ms", NaN));
        r.ProcedureDelay_ms = double(sixgr.util.structGet(out, "ProcedureDelay_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(out, "AirInterfaceObservation_ms", NaN));
        r.AcquisitionTime_ms = double(sixgr.util.structGet(out, "AcquisitionTime_ms", NaN));
        if completed && detected
            r.Status = "PASS";
        elseif logical(sixgr.util.structGet(out, "Skipped", false))
            r.CRCPass = NaN;
            r.DetectionMetric = NaN;
            r.Status = "NA";
        end
        r.Notes = string(sixgr.util.structGet(out, "Notes", ""));
    catch ME
        r.Crash = true;
        r.CRCPass = 0;
        r.Status = "CRASH";
        r.Notes = string(ME.message);
    end
    rows(k) = r;
end
T = struct2table(rows);
end

function T = localCollectPDCCHTrials(cfg, snr_dB, nTrials)
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "DL", snr_dB, 1), nTrials, 1);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "DL", snr_dB, k);
    r.Status = "FAIL";
    try
        [tx, txInfo] = sixgr.phy.dl.PDCCH_Tx(cfg, "K", 64);
        [rxWave, nVar] = localAddAwgn(tx.Waveform, snr_dB);
        tDecode = tic;
        [rx, rxInfo] = sixgr.phy.dl.PDCCH_Rx(rxWave, cfg, ...
            "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), ...
            "ListLength", 16, "NoiseVar", nVar);
        controlLatency_ms = toc(tDecode) * 1e3;
        radioTTI_ms = localSlotDuration(cfg) * 1e3;
        noiseOnly = sqrt(max(double(nVar), eps)/2) * (randn(size(tx.Waveform)) + 1i*randn(size(tx.Waveform)));
        [rxNoise, ~] = sixgr.phy.dl.PDCCH_Rx(noiseOnly, cfg, ...
            "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), ...
            "ListLength", 16, "NoiseVar", nVar);
        [be, bt] = localBitErrors(tx.DCIBits, rx.DCIBits);
        ok = logical(sixgr.util.structGet(rx, "Ok", false)) && (be == 0);
        aggLevel = localPDCCHScalar(tx.PDCCH, "AggregationLevel", NaN);
        usedCCEs = aggLevel;
        availCCEs = localPDCCHAvailableCCEs(tx.PDCCH);
        controlBits = double(sixgr.util.structGet(txInfo, "E", NaN));
        r.TBSize_bits = double(numel(tx.DCIBits));
        r.DCISize_bits = double(numel(tx.DCIBits));
        r.BitsCompared = double(bt);
        r.BitErrors = double(be);
        r.CRCPass = double(ok);
        r.DetectionMetric = 1 - (double(be) / max(double(bt), 1));
        r.FalseAlarmFlag = double(logical(sixgr.util.structGet(rxNoise, "Ok", false)));
        r.BlockingFlag = double(isfinite(aggLevel) && isfinite(availCCEs) && aggLevel > availCCEs);
        r.BlindDecodeCount = double(sixgr.util.structGet(rxInfo, "NumCandidatesTried", NaN));
        r.AvailableCCECount = availCCEs;
        r.UsedCCECount = usedCCEs;
        r.NonOverlappedCCEUsage = usedCCEs / max(availCCEs, 1);
        r.AggregationLevel = aggLevel;
        r.ControlCapacityBits = controlBits;
        r.ControlCapacityUtilization = double(numel(tx.DCIBits)) / max(controlBits, 1);
        r.CORESETUtilization = usedCCEs / max(availCCEs, 1);
        r.ComputeLatency_ms = controlLatency_ms;
        r.ProcedureDelay_ms = NaN;
        r.AirInterfaceTTI_ms = radioTTI_ms;
        % Legacy alias preserved for backward compatibility with older exports.
        % It mirrors the control opportunity duration, not wall-clock decode runtime.
        r.ControlLatency_ms = radioTTI_ms;
        if ok
            r.Status = "PASS";
        end
    catch ME
        r.Crash = true;
        r.CRCPass = 0;
        r.Status = "CRASH";
        r.Notes = string(ME.message);
    end
    rows(k) = r;
end
T = struct2table(rows);
end

function availCCEs = localPDCCHAvailableCCEs(pdcch)
availCCEs = NaN;
if isempty(pdcch)
    return;
end
core = [];
try
    core = pdcch.CORESET;
catch
end
if isempty(core)
    return;
end
freqResources = localPDCCHScalar(core, "FrequencyResources", []);
duration = localPDCCHScalar(core, "Duration", NaN);
if isempty(freqResources) || ~isfinite(duration) || duration <= 0
    return;
end
numREG = 6 * sum(freqResources ~= 0) * duration;
availCCEs = floor(numREG / 6);
end

function value = localPDCCHScalar(obj, propName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    value = obj.(propName);
catch
    return;
end
if isnumeric(value)
    value = double(value);
elseif islogical(value)
    value = double(value);
end
end

function T = localCollectPUCCHTrials(cfg, snr_dB, nTrials)
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "UL", snr_dB, 1), nTrials, 1);
radioTTI_ms = localSlotDuration(cfg) * 1e3;
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "UL", snr_dB, k);
    r.Status = "FAIL";
    uci = int8(randi([0 1], 20, 1));
    try
        [tx, ~] = sixgr.phy.ul.PUCCH_Tx(cfg, uci, "Format", 2);
        [rxWave, nVar] = localAddAwgn(tx.Waveform, snr_dB);
        tDecode = tic;
        [rx, ~] = sixgr.phy.ul.PUCCH_Rx(rxWave, cfg, ...
            "Carrier", tx.Carrier, "PUCCH", tx.PUCCH, "Format", 2, ...
            "NumUCIBits", numel(uci), "ExpectedUCIBits", uci, "NoiseVar", nVar);
        computeLatency_ms = toc(tDecode) * 1e3;
        [be, bt] = localBitErrors(uci, rx.UCIBits);
        ok = logical(sixgr.util.structGet(rx, "Ok", true)) && (be == 0);
        r.TBSize_bits = double(numel(uci));
        r.BitsCompared = double(bt);
        r.BitErrors = double(be);
        r.CRCPass = double(ok);
        r.DetectionMetric = 1 - (double(be) / max(double(bt), 1));
        r.ComputeLatency_ms = computeLatency_ms;
        r.DecodeLatency_ms = computeLatency_ms;
        r.AirInterfaceTTI_ms = radioTTI_ms;
        r.ProcedureDelay_ms = NaN;
        if ok
            r.Status = "PASS";
        end
    catch ME
        r.Crash = true;
        r.CRCPass = 0;
        r.Status = "CRASH";
        r.Notes = string(ME.message);
    end
    rows(k) = r;
end
T = struct2table(rows);
end

function T = localCollectSRSTrials(cfg, snr_dB, nTrials)
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "UL", snr_dB, 1), nTrials, 1);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "UL", snr_dB, k);
    r.Status = "FAIL";
    try
        outSRS = sixgr.link.runSRSChannelEstimation(cfg, "SNR_dB", snr_dB);
        ok = logical(sixgr.util.structGet(outSRS, "Ok", false)) && ~logical(sixgr.util.structGet(outSRS, "Skipped", false));
        r.NMSE_dB = double(sixgr.util.structGet(outSRS, "NMSE_dB", NaN));
        r.DetectionMetric = -r.NMSE_dB;
        r.InjectedDoppler_Hz = double(sixgr.util.structGet(outSRS, "InjectedDoppler_Hz", r.DopplerHz));
        r.QCLAccuracy = double(sixgr.util.structGet(outSRS, "QCLAccuracy", NaN));
        r.InterpolationLoss_dB = double(sixgr.util.structGet(outSRS, "InterpolationLoss_dB", NaN));
        r.MismatchSensitivity_dB = double(sixgr.util.structGet(outSRS, "MismatchSensitivity_dB", NaN));
        r.ComputeLatency_ms = double(sixgr.util.structGet(outSRS, "ComputeLatency_ms", NaN));
        r.ProcedureDelay_ms = double(sixgr.util.structGet(outSRS, "ProcedureDelay_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(outSRS, "AirInterfaceObservation_ms", NaN));
        r.AcquisitionTime_ms = double(sixgr.util.structGet(outSRS, "AcquisitionTime_ms", NaN));
        r.TrackingFailureProbability = double(sixgr.util.structGet(outSRS, "TrackingFailure", NaN));
        r.CRCPass = NaN;
        if ok
            r.Status = "PASS";
        end
        r.Notes = string(sixgr.util.structGet(outSRS, "Notes", ""));
    catch ME
        r.Crash = true;
        r.CRCPass = NaN;
        r.Status = "CRASH";
        r.Notes = string(ME.message);
    end
    rows(k) = r;
end
T = struct2table(rows);
end

function T = localCollectTRSTrials(cfg, snr_dB, nTrials)
if ~logical(sixgr.util.structGet(cfg, "phy.trs.enable", false))
    T = localEmptyLinkTrialTable(0);
    return;
end
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "DL", snr_dB, 1), nTrials, 1);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "DL", snr_dB, k);
    r.Status = "FAIL";
    try
        out = sixgr.link.runTRSTracking(cfg, "SNR_dB", snr_dB);
        ok = logical(sixgr.util.structGet(out, "Ok", false)) && ~logical(sixgr.util.structGet(out, "Skipped", false));
        r.CRCPass = NaN;
        r.NMSE_dB = double(sixgr.util.structGet(out, "NMSE_dB", NaN));
        r.DetectionMetric = double(sixgr.util.structGet(out, "DetectionMetric", NaN));
        r.InjectedDoppler_Hz = double(sixgr.util.structGet(out, "InjectedDoppler_Hz", r.DopplerHz));
        r.PhaseTrackingError_deg = double(sixgr.util.structGet(out, "PhaseError_deg", NaN));
        r.EstimatedDopplerHz = double(sixgr.util.structGet(out, "EstimatedDoppler_Hz", NaN));
        r.DopplerError_Hz = r.EstimatedDopplerHz - r.InjectedDoppler_Hz;
        r.QCLAccuracy = double(sixgr.util.structGet(out, "QCLAccuracy", NaN));
        r.InterpolationLoss_dB = double(sixgr.util.structGet(out, "InterpolationLoss_dB", NaN));
        r.MismatchSensitivity_dB = double(sixgr.util.structGet(out, "MismatchSensitivity_dB", NaN));
        r.ComputeLatency_ms = double(sixgr.util.structGet(out, "ComputeLatency_ms", NaN));
        r.ProcedureDelay_ms = double(sixgr.util.structGet(out, "ProcedureDelay_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(out, "AirInterfaceObservation_ms", NaN));
        r.AcquisitionTime_ms = double(sixgr.util.structGet(out, "AcquisitionTime_ms", NaN));
        r.TrackingFailureProbability = double(sixgr.util.structGet(out, "TrackingFailure", NaN));
        if ok
            r.Status = "PASS";
        end
        r.Notes = string(sixgr.util.structGet(out, "Notes", ""));
    catch ME
        r.Crash = true;
        r.CRCPass = NaN;
        r.Status = "CRASH";
        r.Notes = string(ME.message);
    end
    rows(k) = r;
end
T = struct2table(rows);
end

function row = localMakeLinkTrialRow(cfg, direction, snr_dB, trialIdx)
seed0 = double(sixgr.util.structGet(cfg, "run.seed", 1));
dopp = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 0))));
row = struct();
row.Direction = string(direction);
row.SNR_dB = double(snr_dB);
row.Seed = seed0 + double(trialIdx) - 1;
row.Frame = double(trialIdx);
row.Slot = double(trialIdx);
row.MCS = NaN;
row.PRBs = NaN;
row.Layers = NaN;
row.Modulation = "";
row.TargetCodeRate = NaN;
row.TBSize_bits = NaN;
row.ChannelModel = localResolveRequestedLinkChannelModel(cfg);
row.DopplerHz = dopp;
row.CRCPass = NaN;
row.DecoderIterations = NaN;
row.EVM_rms = NaN;
row.NMSE_dB = NaN;
row.DetectionMetric = NaN;
row.MeasuredSINR_dB = NaN;
row.WidebandCQI = NaN;
row.RankIndicator = NaN;
row.PMI = NaN;
row.CRI = NaN;
row.PMIType = "";
row.PMICodebookMode = "";
row.CSIReportMode = "";
row.CSIPayloadBitLength = NaN;
row.CSIPayloadHex = "";
row.FalseAlarmFlag = NaN;
row.BlockingFlag = NaN;
row.BlindDecodeCount = NaN;
row.AvailableCCECount = NaN;
row.UsedCCECount = NaN;
row.NonOverlappedCCEUsage = NaN;
row.AggregationLevel = NaN;
row.DCISize_bits = NaN;
row.ControlCapacityBits = NaN;
row.ControlCapacityUtilization = NaN;
row.CORESETUtilization = NaN;
row.ControlLatency_ms = NaN;
row.ChannelGain_dB = NaN;
row.NoiseVariance = NaN;
row.TimingOffset_samples = NaN;
row.RankEstimate = NaN;
row.ConditionNumber_dB = NaN;
row.NumRxAntennas = NaN;
row.NumTxPorts = NaN;
row.SelectedBeamIndex = NaN;
row.BestBeamIndex = NaN;
row.BeamHit = NaN;
row.TopKBeamHit = NaN;
row.BeamCandidateCount = NaN;
row.SelectedBeamGain_dB = NaN;
row.BestBeamGain_dB = NaN;
row.BeamGainGap_dB = NaN;
row.ConfiguredPMI = NaN;
row.ConfiguredCRI = NaN;
row.BitErrors = NaN;
row.BitsCompared = NaN;
row.OfferedBits = NaN;
row.GoodBits = NaN;
row.OfferedThroughput_Mbps = NaN;
row.Goodput_Mbps = NaN;
row.ComputeLatency_ms = NaN;
row.ProcedureDelay_ms = NaN;
row.AirInterfaceTTI_ms = NaN;
row.AirInterfaceObservation_ms = NaN;
row.Latency_ms = NaN;
row.DecodeLatency_ms = NaN;
row.EarlyStopRate = NaN;
row.DecoderComplexityUnits = NaN;
row.NormalizedDecoderComplexity = NaN;
row.AreaEfficiencyProxy = NaN;
row.NumCodeBlocks = NaN;
row.CodeBlockLength_bits = NaN;
row.SegmentationOccurred = NaN;
row.SegmentationPaddingBits = NaN;
row.TBCRCLength_bits = NaN;
row.TBLengthWithCRC_bits = NaN;
row.BaseGraph = NaN;
row.EncodedBits = NaN;
row.RateMatchedBits = NaN;
row.RateMatchPunctureBits = NaN;
row.RateMatchRepetitionBits = NaN;
row.CodeBlockErrors = NaN;
row.CodeBlockCount = NaN;
row.CodeBlockBLER = NaN;
row.CBGErrors = NaN;
row.CBGCount = NaN;
row.CBGBLER = NaN;
row.PAPR_dB = NaN;
row.PeakClippingEvents = NaN;
row.SymbolErrors = NaN;
row.SymbolsCompared = NaN;
row.SymbolErrorRate = NaN;
row.ResidualInterferencePower_dB = NaN;
row.LLRMeanAbs = NaN;
row.LLRStdAbs = NaN;
row.LLRImbalance = NaN;
row.ModulationMappingSensitivity = NaN;
row.ShapingRateLoss = NaN;
row.DistributionMatchingLatency_ms = NaN;
row.HighOrderRobustness = NaN;
row.DetectorComplexityUnits_Modulation = NaN;
row.DataRECount = NaN;
row.DMRSRECount = NaN;
row.PTRSRECount = NaN;
row.RSOverheadFraction = NaN;
row.InjectedCFO_Hz = NaN;
row.EstimatedCFO_PreCorrection_Hz = NaN;
row.ResidualCFO_PostCorrection_Hz = NaN;
row.EstimatedCFO_Hz = NaN;
row.TrueCFO_Hz = NaN;
row.CFOError_Hz = NaN;
row.InjectedTimingOffset_samples = 0;
row.EstimatedTimingOffset_PreCorrection_samples = NaN;
row.ResidualTimingError_PostCorrection_samples = NaN;
row.TrueTimingOffset_samples = 0;
row.TimingError_samples = NaN;
row.InjectedDoppler_Hz = dopp;
row.EstimatedDopplerHz = NaN;
row.DopplerError_Hz = NaN;
row.PhaseTrackingError_deg = NaN;
row.QCLAccuracy = NaN;
row.ChannelAgingLoss_dB = NaN;
row.InterpolationLoss_dB = NaN;
row.MismatchSensitivity_dB = NaN;
row.AcquisitionTime_ms = NaN;
row.TrackingFailureProbability = NaN;
row.Status = "NA";
row.Crash = false;
row.LinkAdaptationApplied = false;
row.LinkAdaptationScheduled = false;
row.IsWarmupFrame = false;
row.Notes = "";
end

function T = localEmptyLinkTrialTable(nRows)
nRows = max(0, round(double(nRows)));
rows = repmat(localMakeLinkTrialRow(struct(), "", NaN, 1), nRows, 1);
T = struct2table(rows);
end

function spec = localResolveMultiUserSpec(cfg)
userCfg = sixgr.util.structGet(cfg, "lls6g.users", struct());
hasUsersCfg = isstruct(userCfg) && isscalar(userCfg) && ~isempty(fieldnames(userCfg));
if hasUsersCfg
    numUsers = max(1, round(double(sixgr.util.structGet(userCfg, "n_users", 1))));
    enabled = logical(sixgr.util.structGet(userCfg, "enabled", false)) || numUsers > 1;
else
    numUsers = 1;
    enabled = false;
end
spec = struct();
spec.Enabled = enabled;
spec.NumUsers = numUsers;
spec.RNTIStart = max(1, round(double(sixgr.util.structGet(userCfg, "rnti_start", 1))));
spec.SeedStride = max(1, round(double(sixgr.util.structGet(userCfg, "seed_stride", 101))));
spec.ExecutionModel = string(sixgr.util.structGet(userCfg, "execution_model", "independent_link_sweep"));
spec.BeamSelectionStrategy = lower(string(sixgr.util.structGet(userCfg, "beam_selection_strategy", "fixed_first_beam")));
spec.SaveUserTables = logical(sixgr.util.structGet(userCfg, "save_user_tables", true));
end

function spec = localSingleUserSpec(specIn)
spec = specIn;
spec.Enabled = false;
spec.NumUsers = 1;
end

function cfgU = localPrepareUserCfg(cfg, multiUser, userIdx)
cfgU = cfg;
if ~logical(sixgr.util.structGet(multiUser, "Enabled", false)) && ...
        max(1, round(double(sixgr.util.structGet(multiUser, "NumUsers", 1)))) == 1 && ...
        double(userIdx) == 1
    return;
end

seedBase = double(sixgr.util.structGet(cfg, "run.seed", 1));
cfgU.run.seed = seedBase + (double(userIdx) - 1) * double(multiUser.SeedStride);
cfgU.scenario.nUE = 1;
cfgU.scenario.ue.nUE = 1;

rnti = localUserRNTI(multiUser, userIdx);
cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.RNTI", rnti);
cfgU = sixgr.util.structSet(cfgU, "phy.pusch.RNTI", rnti);

[W, beamMeta] = localSelectUserBeamforming(cfgU, multiUser, userIdx);
cfgU = sixgr.util.structSet(cfgU, "lls6g.userContext", beamMeta);
if ~isempty(W)
    cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.precoding.matrix", W);
    cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.numPorts", size(W, 1));
    cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.nPorts", size(W, 1));
    cfgU.phy.nTxAnt = size(W, 1);
end
end

function rnti = localUserRNTI(multiUser, userIdx)
rnti = max(1, round(double(multiUser.RNTIStart + double(userIdx) - 1)));
end

function [W, meta] = localSelectUserBeamforming(cfg, multiUser, userIdx)
W = [];
meta = struct( ...
    "UEIndex", double(userIdx), ...
    "RNTI", double(localUserRNTI(multiUser, userIdx)), ...
    "ConfiguredTxAntennas", double(sixgr.util.structGet(cfg, "phy.nTxAnt", 1)), ...
    "ConfiguredRxAntennas", double(sixgr.util.structGet(cfg, "phy.nRxAnt", 1)), ...
    "ConfiguredLayers", double(localConfiguredLayerCount(cfg, "DL")), ...
    "BeamSelectionStrategy", string(multiUser.BeamSelectionStrategy), ...
    "BeamIndexSet", "", ...
    "BeamformingApplied", false, ...
    "PrecoderSource", "none");

nTx = max(1, round(double(sixgr.util.structGet(cfg, "phy.nTxAnt", 1))));
nLayers = max(1, round(double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1))));
beamSweepEnabled = logical(sixgr.util.structGet(cfg, "phy.beamManagement.enabled", false));
precoderType = lower(string(sixgr.util.structGet(cfg, "lls6g.mimo.precoder_type", sixgr.util.structGet(cfg, "mimo.precoder_type", "wideband"))));
if nTx <= 1 || (nLayers <= 1 && ~beamSweepEnabled && ~logical(multiUser.Enabled))
    return;
end
if precoderType == "none"
    return;
end

beamCount = max(nLayers, round(double(sixgr.util.structGet(cfg, "phy.beamManagement.beamCount", nTx))));
arr = localInferArrayGeometry(cfg, nTx);
codebook = sixgr.rf.BeamRefinementCSIRS.makeCodebookFromArray(arr, arr.nRow, min(arr.nCol, beamCount));
if isempty(codebook)
    return;
end
numBeams = size(codebook, 2);
if numBeams < nLayers
    return;
end

switch string(multiUser.BeamSelectionStrategy)
    case "round_robin_codebook"
        startIdx = 1 + mod((double(userIdx) - 1) * max(nLayers, 1), numBeams);
        beamIdx = zeros(1, nLayers);
        for k = 1:nLayers
            beamIdx(k) = 1 + mod(startIdx + k - 2, numBeams);
        end
    otherwise
        beamIdx = 1:nLayers;
end
beamIdx = unique(max(1, min(numBeams, round(beamIdx))), "stable");
if numel(beamIdx) < nLayers
    unused = setdiff(1:numBeams, beamIdx, "stable");
    need = nLayers - numel(beamIdx);
    beamIdx = [beamIdx unused(1:min(need, numel(unused)))]; %#ok<AGROW>
end
beamIdx = beamIdx(1:nLayers);
W = codebook(:, beamIdx);

meta.BeamformingApplied = true;
meta.PrecoderSource = "codebook_dft";
meta.BeamIndexSet = join(string(beamIdx), "|");
end

function arr = localInferArrayGeometry(cfg, nTx)
panelCount = max(1, round(double(sixgr.util.structGet(cfg, "phy.beamManagement.panelCount", 1))));
nRow = max(1, floor(sqrt(double(nTx))));
nCol = max(1, ceil(double(nTx) / max(nRow, 1)));
if nRow * nCol ~= nTx
    if panelCount > 1 && mod(nTx, panelCount) == 0
        nRow = panelCount;
        nCol = nTx / panelCount;
    else
        nRow = 1;
        nCol = nTx;
    end
end
arr = struct("Nant", double(nTx), "nRow", double(nRow), "nCol", double(nCol));
end

function [T, summaryT] = localCollectMultiUserLinkTrials(cfg, multiUser, direction, nTrials, snr_dB)
rows = cell(max(1, round(double(multiUser.NumUsers))), 1);
summaryRows = repmat(struct("UEIndex", NaN, "RNTI", NaN, "Direction", "", ...
    "ConfiguredLayers", NaN, "ConfiguredTxAntennas", NaN, "ConfiguredRxAntennas", NaN, ...
    "BeamformingApplied", false, "BeamSelectionStrategy", "", "BeamIndexSet", "", ...
    "ExecutionModel", "", "Throughput_Mbps", NaN, "BLER", NaN, "BER", NaN, ...
    "PassRate", NaN, "MeanMeasuredSINR_dB", NaN, "MeanChannelGain_dB", NaN, "Ok", false), ...
    max(1, round(double(multiUser.NumUsers))), 1);

for ueIdx = 1:max(1, round(double(multiUser.NumUsers)))
    cfgU = localPrepareUserCfg(cfg, multiUser, ueIdx);
    userMeta = sixgr.util.structGet(cfgU, "lls6g.userContext", struct());
    if upper(string(direction)) == "DL"
        res = sixgr.link.runDLPDSCHThroughput(cfgU, "NumFrames", nTrials, "SNR_dB", snr_dB);
    else
        res = sixgr.link.runULPUSCHThroughput(cfgU, "NumFrames", nTrials, "SNR_dB", snr_dB);
    end
    Tu = localEnsureLinkTrialTable(sixgr.util.structGet(res, "TrialTable", table()), upper(string(direction)), snr_dB, cfgU);
    Tu = localAnnotateUserTrials(Tu, cfgU, multiUser, ueIdx, userMeta);
    rows{ueIdx} = Tu;

    passRate = NaN;
    if ismember("Status", string(Tu.Properties.VariableNames)) && ~isempty(Tu)
        passRate = mean(upper(strtrim(string(Tu.Status))) == "PASS");
    end
    summaryRows(ueIdx) = struct( ...
        "UEIndex", double(ueIdx), ...
        "RNTI", double(localUserRNTI(multiUser, ueIdx)), ...
        "Direction", string(direction), ...
        "ConfiguredLayers", double(localConfiguredLayerCount(cfgU, direction)), ...
        "ConfiguredTxAntennas", double(sixgr.util.structGet(cfgU, "phy.nTxAnt", 1)), ...
        "ConfiguredRxAntennas", double(sixgr.util.structGet(cfgU, "phy.nRxAnt", 1)), ...
        "BeamformingApplied", logical(sixgr.util.structGet(userMeta, "BeamformingApplied", false)), ...
        "BeamSelectionStrategy", string(sixgr.util.structGet(userMeta, "BeamSelectionStrategy", multiUser.BeamSelectionStrategy)), ...
        "BeamIndexSet", string(sixgr.util.structGet(userMeta, "BeamIndexSet", "")), ...
        "ExecutionModel", string(multiUser.ExecutionModel), ...
        "Throughput_Mbps", double(sixgr.util.structGet(res, "Throughput_Mbps", NaN)), ...
        "BLER", double(sixgr.util.structGet(res, "BLER", NaN)), ...
        "BER", double(sixgr.util.structGet(res, "BER", NaN)), ...
        "PassRate", double(passRate), ...
        "MeanMeasuredSINR_dB", double(localTableMean(Tu, "MeasuredSINR_dB")), ...
        "MeanChannelGain_dB", double(localTableMean(Tu, "ChannelGain_dB")), ...
        "Ok", logical(sixgr.util.structGet(res, "Ok", false)));
end

rows = rows(~cellfun(@isempty, rows));
if isempty(rows)
    T = table();
else
    T = vertcat(rows{:});
end
summaryT = struct2table(summaryRows);
end

function T = localAnnotateUserTrials(T, cfg, multiUser, ueIdx, userMeta)
if ~istable(T)
    T = table();
    return;
end
n = height(T);
T.UEIndex = repmat(double(ueIdx), n, 1);
T.RNTI = repmat(double(localUserRNTI(multiUser, ueIdx)), n, 1);
T.ConfiguredTxAntennas = repmat(double(sixgr.util.structGet(cfg, "phy.nTxAnt", 1)), n, 1);
T.ConfiguredRxAntennas = repmat(double(sixgr.util.structGet(cfg, "phy.nRxAnt", 1)), n, 1);
T.ConfiguredLayers = repmat(double(localConfiguredLayerCount(cfg, directionFromTable(T))), n, 1);
T.ExecutionModel = repmat(string(multiUser.ExecutionModel), n, 1);
T.BeamSelectionStrategy = repmat(string(sixgr.util.structGet(userMeta, "BeamSelectionStrategy", multiUser.BeamSelectionStrategy)), n, 1);
T.BeamIndexSet = repmat(string(sixgr.util.structGet(userMeta, "BeamIndexSet", "")), n, 1);
T.PrecoderSource = repmat(string(sixgr.util.structGet(userMeta, "PrecoderSource", "none")), n, 1);
T.BeamformingApplied = repmat(logical(sixgr.util.structGet(userMeta, "BeamformingApplied", false)), n, 1);
end

function summary = localMergeMultiUserSummaries(dlSummary, ulSummary, multiUser)
parts = {};
if istable(dlSummary) && ~isempty(dlSummary)
    parts{end+1} = dlSummary; %#ok<AGROW>
end
if istable(ulSummary) && ~isempty(ulSummary)
    parts{end+1} = ulSummary; %#ok<AGROW>
end
if isempty(parts)
    summary = table();
    return;
end
summary = vertcat(parts{:});
summary.NumUsersConfigured = repmat(double(multiUser.NumUsers), height(summary), 1);
end

function T = localBuildSNRSweepFromRawTrials(rawTrials, cfg, snrGrid)
snrSet = unique(sort(double(snrGrid(:))));
if isempty(snrSet)
    snrSet = unique(sort([ ...
        localTableUniqueFinite(rawTrials, "DL", "SNR_dB"); ...
        localTableUniqueFinite(rawTrials, "UL", "SNR_dB"); ...
        localTableUniqueFinite(rawTrials, "SRS", "SNR_dB")]));
end
if isempty(snrSet)
    T = table();
    return;
end

n = numel(snrSet);
rows = repmat(localEmptySweepSummaryRow(0), n, 1);

for i = 1:n
    snr = double(snrSet(i));
    row = localEmptySweepSummaryRow(snr);
    dlT = localSubsetTrialsBySNR(sixgr.util.structGet(rawTrials, "DL", table()), snr);
    if ~isempty(dlT)
        dlStats = localSummarizeLinkTrialTable(dlT, cfg);
        row = localApplyLinkSweepStats(row, "DL", dlStats);
    end

    ulT = localSubsetTrialsBySNR(sixgr.util.structGet(rawTrials, "UL", table()), snr);
    if ~isempty(ulT)
        ulStats = localSummarizeLinkTrialTable(ulT, cfg);
        row = localApplyLinkSweepStats(row, "UL", ulStats);
    end

    srsT = localSubsetTrialsBySNR(sixgr.util.structGet(rawTrials, "SRS", table()), snr);
    row = localApplyScalarSweepStats(row, "SRS_NMSE_dB", srsT, "NMSE_dB");
    rows(i) = row;
end

T = struct2table(rows);
end

function cfgRef = localBuildFixedReferenceCfg(cfg)
cfgRef = cfg;
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.mode", "fixed");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.dlPolicy", "fixed");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.ulPolicy", "fixed");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.rankPolicy", "fixed");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.beamPolicy", "fixed");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.deltaCQIPolicy", "none");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.deltaMCSPolicy", "none");
cfgRef = sixgr.util.structSet(cfgRef, "phy.pdsch.nLayers", 1);
cfgRef = sixgr.util.structSet(cfgRef, "phy.pdsch.numLayers", 1);
cfgRef = sixgr.util.structSet(cfgRef, "phy.pusch.nLayers", 1);
cfgRef = sixgr.util.structSet(cfgRef, "phy.pusch.numLayers", 1);
end

function T = localRunReferenceLinkSNRSweep(cfg, snrGrid, nFrames, multiUser, sweepPlan)
cfgRef = localBuildFixedReferenceCfg(cfg);
if nargin < 5 || ~isstruct(sweepPlan)
    sweepPlan = localResolveSweepPlan(struct(), nFrames);
end
snrGrid = localBuildReferenceSweepGrid(snrGrid, sweepPlan);
T = localRunLinkSNRSweep(cfgRef, snrGrid, nFrames, multiUser);
end

function res = localApplyPrimarySweepResults(res, rawTrials, cfg, snrGrid)
snrGrid = unique(sort(double(snrGrid(:))));
if isfield(rawTrials, "PBCH") && istable(rawTrials.PBCH)
    aggPBCH = localAggregatePrimaryPassFailCase(rawTrials.PBCH, "PBCH primary sweep", snrGrid);
    res = localReplaceCaseResult(res, "CellSearch_MIB_SIB1", aggPBCH);
end
if isfield(rawTrials, "PRACH") && istable(rawTrials.PRACH)
    aggPRACH = localAggregatePrimaryPassFailCase(rawTrials.PRACH, "PRACH primary sweep", snrGrid);
    res = localReplaceCaseResult(res, "PRACH_Detection", aggPRACH);
end
if isfield(rawTrials, "DL") && istable(rawTrials.DL)
    aggDL = localAggregatePrimaryLinkCase(rawTrials.DL, cfg, "DL primary sweep", snrGrid);
    res = localReplaceCaseResult(res, "DL_PDSCH_Throughput", aggDL);
end
if isfield(rawTrials, "UL") && istable(rawTrials.UL)
    aggUL = localAggregatePrimaryLinkCase(rawTrials.UL, cfg, "UL primary sweep", snrGrid);
    res = localReplaceCaseResult(res, "UL_PUSCH_Throughput", aggUL);
end
if isfield(rawTrials, "SRS") && istable(rawTrials.SRS)
    aggSRS = localAggregatePrimarySRSCase(rawTrials.SRS, snrGrid);
    res = localReplaceCaseResult(res, "UL_SRS_ChannelEst", aggSRS);
end
res.Ok = localLinkKPITableHealthy(res.KPITable);
end

function res = localApplyMultiUserPrimaryResults(res, rawTrials, multiUser, cfg)
if ~(isstruct(res) && isfield(res, "KPITable") && istable(res.KPITable))
    return;
end
if isfield(rawTrials, "DL") && istable(rawTrials.DL)
    aggDL = localAggregatePrimaryLinkCase(rawTrials.DL, cfg, "multi_user_" + string(multiUser.ExecutionModel), unique(double(rawTrials.DL.SNR_dB)));
    res = localReplaceCaseResult(res, "DL_PDSCH_Throughput", aggDL);
end
if isfield(rawTrials, "UL") && istable(rawTrials.UL)
    aggUL = localAggregatePrimaryLinkCase(rawTrials.UL, cfg, "multi_user_" + string(multiUser.ExecutionModel), unique(double(rawTrials.UL.SNR_dB)));
    res = localReplaceCaseResult(res, "UL_PUSCH_Throughput", aggUL);
end
res.MultiUserMode = string(multiUser.ExecutionModel);
res.MultiUserEnabled = logical(multiUser.Enabled);
res.MultiUserCount = double(multiUser.NumUsers);
res.Ok = localLinkKPITableHealthy(res.KPITable);
end

function agg = localAggregatePrimaryLinkCase(T, cfg, label, snrGrid)
agg = struct();
agg.Ok = false;
agg.Skipped = isempty(T);
agg.BER = NaN;
agg.BLER = NaN;
agg.Throughput_Mbps = NaN;
agg.EVM_rms = NaN;
agg.NMSE_dB = NaN;
agg.Notes = "";
agg.TrialTable = T;
if isempty(T)
    return;
end
stats = localSummarizeLinkTrialTable(T, cfg);
status = upper(strtrim(string(stats.Table.Status)));
passMask = status == "PASS";
observedMask = passMask | status == "FAIL" | status == "CRASH";
bits = double(stats.Table.BitsCompared);
bits(~isfinite(bits)) = 0;
bitErr = double(stats.Table.BitErrors);
bitErr(~isfinite(bitErr)) = 0;
agg.BER = sum(bitErr) / max(sum(bits), 1);
agg.BLER = stats.BLER;
agg.Throughput_Mbps = stats.Throughput_Mbps;
agg.EVM_rms = stats.EVM_rms;
agg.Ok = any(passMask);
if ~any(observedMask)
    agg.Skipped = true;
end
agg.Notes = string(label) + "; snr_grid_db=" + strjoin(string(round(snrGrid(:).', 6)), "|") + ...
    "; steady_state_warmup_rows_excluded=true";
end

function agg = localAggregatePrimaryPassFailCase(T, label, snrGrid)
agg = struct();
agg.Ok = false;
agg.Skipped = isempty(T);
agg.BER = NaN;
agg.BLER = NaN;
agg.Throughput_Mbps = NaN;
agg.EVM_rms = NaN;
agg.NMSE_dB = NaN;
agg.Notes = "";
agg.TrialTable = T;
if isempty(T)
    return;
end
Te = localEffectiveTrialRows(T);
status = upper(strtrim(string(Te.Status)));
failMask = status == "FAIL" | status == "CRASH";
passMask = status == "PASS";
observedMask = passMask | failMask;
agg.BLER = sum(failMask) / max(height(Te), 1);
agg.Ok = any(passMask);
if ~any(observedMask)
    agg.Skipped = true;
end
agg.Notes = string(label) + "; snr_grid_db=" + strjoin(string(round(snrGrid(:).', 6)), "|");
end

function agg = localAggregatePrimarySRSCase(T, snrGrid)
agg = struct();
agg.Ok = false;
agg.Skipped = isempty(T);
agg.BER = NaN;
agg.BLER = NaN;
agg.Throughput_Mbps = NaN;
agg.EVM_rms = NaN;
agg.NMSE_dB = NaN;
agg.Notes = "";
agg.TrialTable = T;
if isempty(T)
    return;
end
Te = localEffectiveTrialRows(T);
nmse = localFiniteColumn(Te, "NMSE_dB");
agg.NMSE_dB = mean(nmse, "omitnan");
agg.Ok = ~isempty(nmse);
agg.Notes = "SRS primary sweep; snr_grid_db=" + strjoin(string(round(snrGrid(:).', 6)), "|");
end

function stats = localSummarizeLinkTrialTable(T, cfg)
Te = localEffectiveTrialRows(T);
stats = struct( ...
    "Table", Te, ...
    "TrialCount", NaN, ...
    "FailureCount", NaN, ...
    "BER", NaN, ...
    "BER_CI_Low", NaN, ...
    "BER_CI_High", NaN, ...
    "BLER", NaN, ...
    "BLER_CI_Low", NaN, ...
    "BLER_CI_High", NaN, ...
    "Throughput_Mbps", NaN, ...
    "Throughput_CI_Low", NaN, ...
    "Throughput_CI_High", NaN, ...
    "OfferedThroughput_Mbps", NaN, ...
    "Goodput_Mbps", NaN, ...
    "CodeBlockBLER", NaN, ...
    "CBG_BLER", NaN, ...
    "EVM_rms", NaN, ...
    "DecodeLatency_ms", NaN, ...
    "DecoderComplexityUnits", NaN, ...
    "NormalizedDecoderComplexity", NaN);
if isempty(Te)
    return;
end
bits = double(Te.BitsCompared);
bits(~isfinite(bits)) = 0;
bitErr = double(Te.BitErrors);
bitErr(~isfinite(bitErr)) = 0;
status = upper(strtrim(string(Te.Status)));
failMask = status == "FAIL" | status == "CRASH";
stats.TrialCount = double(height(Te));
stats.FailureCount = double(sum(failMask));
goodBits = double(Te.GoodBits);
goodBits(~isfinite(goodBits)) = 0;
offeredBits = double(Te.OfferedBits);
offeredBits(~isfinite(offeredBits)) = 0;
stats.BER = sum(bitErr) / max(sum(bits), 1);
stats.BLER = sum(failMask) / max(height(Te), 1);
[stats.BER_CI_Low, stats.BER_CI_High] = localWilsonInterval(sum(bitErr), sum(bits));
[stats.BLER_CI_Low, stats.BLER_CI_High] = localWilsonInterval(sum(failMask), height(Te));
stats.Throughput_Mbps = localAggregateThroughputFromTrials(Te, cfg);
[stats.Throughput_CI_Low, stats.Throughput_CI_High] = localMeanConfidenceInterval(localTrialThroughputSamples(Te, cfg));
stats.OfferedThroughput_Mbps = (sum(offeredBits) / max(height(Te) * localSlotDuration(cfg), eps)) / 1e6;
stats.Goodput_Mbps = (sum(goodBits) / max(height(Te) * localSlotDuration(cfg), eps)) / 1e6;
stats.CodeBlockBLER = localRatioFromColumns(Te, "CodeBlockErrors", "CodeBlockCount");
stats.CBG_BLER = localRatioFromColumns(Te, "CBGErrors", "CBGCount");
stats.EVM_rms = localTableMean(Te, "EVM_rms");
stats.DecodeLatency_ms = localTableMean(Te, "DecodeLatency_ms");
stats.DecoderComplexityUnits = localTableMean(Te, "DecoderComplexityUnits");
stats.NormalizedDecoderComplexity = localTableMean(Te, "NormalizedDecoderComplexity");
end

function T = localEffectiveTrialRows(T)
if ~(istable(T) && ~isempty(T))
    T = table();
    return;
end
mask = true(height(T), 1);
if ismember("IsWarmupFrame", string(T.Properties.VariableNames))
    warmMask = logical(T.IsWarmupFrame);
    if any(~warmMask)
        mask = ~warmMask;
    end
end
T = T(mask, :);
end

function ratio = localRatioFromColumns(T, numVar, denVar)
ratio = NaN;
if ~(istable(T) && ~isempty(T) && all(ismember([numVar denVar], string(T.Properties.VariableNames))))
    return;
end
num = double(T.(numVar));
den = double(T.(denVar));
num(~isfinite(num)) = 0;
den(~isfinite(den)) = 0;
if sum(den) <= 0
    return;
end
ratio = sum(num) / sum(den);
end

function thr = localAggregateThroughputFromTrials(T, cfg)
thr = NaN;
if isempty(T)
    return;
end
samples = localTrialThroughputSamples(T, cfg);
if isempty(samples)
    return;
end
thr = mean(samples, "omitnan");
end

function samples = localTrialThroughputSamples(T, cfg)
samples = NaN(0, 1);
if isempty(T)
    return;
end
slotDur_s = localSlotDuration(cfg);
if ~(isfinite(slotDur_s) && slotDur_s > 0)
    return;
end
goodBits = double(T.GoodBits);
goodBits(~isfinite(goodBits)) = NaN;
if all(~isfinite(goodBits))
    bitTotals = double(T.TBSize_bits);
    bitTotals(~isfinite(bitTotals)) = 0;
    passMask = upper(strtrim(string(T.Status))) == "PASS";
    goodBits = zeros(size(bitTotals));
    goodBits(passMask) = bitTotals(passMask);
end
samples = (goodBits / slotDur_s) / 1e6;
samples = samples(isfinite(samples));
end

function [lo, hi] = localWilsonInterval(k, n)
lo = NaN;
hi = NaN;
n = double(n);
k = double(k);
if ~(isfinite(n) && n > 0 && isfinite(k) && k >= 0)
    return;
end
z = 1.95996398454005;
p = min(max(k / n, 0), 1);
den = 1 + (z^2 / n);
center = (p + z^2 / (2 * n)) / den;
spread = (z / den) * sqrt((p * (1 - p) / n) + (z^2 / (4 * n^2)));
lo = max(0, center - spread);
hi = min(1, center + spread);
end

function [lo, hi] = localMeanConfidenceInterval(x)
lo = NaN;
hi = NaN;
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    return;
end
m = mean(x, "omitnan");
if numel(x) < 2
    lo = m;
    hi = m;
    return;
end
z = 1.95996398454005;
se = std(x, 0, "omitnan") / sqrt(numel(x));
lo = m - z * se;
hi = m + z * se;
end

function row = localEmptySweepSummaryRow(snr)
row = struct( ...
    "SNR_dB", double(snr), ...
    "DL_BER", NaN, "DL_BER_CI_Low", NaN, "DL_BER_CI_High", NaN, ...
    "DL_BLER", NaN, "DL_BLER_CI_Low", NaN, "DL_BLER_CI_High", NaN, "DL_TrialCount", NaN, "DL_FailureCount", NaN, ...
    "DL_Throughput_Mbps", NaN, "DL_Throughput_CI_Low", NaN, "DL_Throughput_CI_High", NaN, ...
    "DL_OfferedThroughput_Mbps", NaN, "DL_Goodput_Mbps", NaN, "DL_CodeBlockBLER", NaN, "DL_CBG_BLER", NaN, ...
    "DL_DecodeLatency_ms", NaN, "DL_DecoderComplexityUnits", NaN, "DL_NormalizedDecoderComplexity", NaN, ...
    "UL_BER", NaN, "UL_BER_CI_Low", NaN, "UL_BER_CI_High", NaN, ...
    "UL_BLER", NaN, "UL_BLER_CI_Low", NaN, "UL_BLER_CI_High", NaN, "UL_TrialCount", NaN, "UL_FailureCount", NaN, ...
    "UL_Throughput_Mbps", NaN, "UL_Throughput_CI_Low", NaN, "UL_Throughput_CI_High", NaN, ...
    "UL_OfferedThroughput_Mbps", NaN, "UL_Goodput_Mbps", NaN, "UL_CodeBlockBLER", NaN, "UL_CBG_BLER", NaN, ...
    "UL_DecodeLatency_ms", NaN, "UL_DecoderComplexityUnits", NaN, "UL_NormalizedDecoderComplexity", NaN, ...
    "SRS_NMSE_dB", NaN, "SRS_NMSE_CI_Low", NaN, "SRS_NMSE_CI_High", NaN, "SRS_TrialCount", NaN);
end

function row = localApplyLinkSweepStats(row, prefix, stats)
prefix = upper(string(prefix));
row.(char(prefix + "_BER")) = double(sixgr.util.structGet(stats, "BER", NaN));
row.(char(prefix + "_BER_CI_Low")) = double(sixgr.util.structGet(stats, "BER_CI_Low", NaN));
row.(char(prefix + "_BER_CI_High")) = double(sixgr.util.structGet(stats, "BER_CI_High", NaN));
row.(char(prefix + "_BLER")) = double(sixgr.util.structGet(stats, "BLER", NaN));
row.(char(prefix + "_BLER_CI_Low")) = double(sixgr.util.structGet(stats, "BLER_CI_Low", NaN));
row.(char(prefix + "_BLER_CI_High")) = double(sixgr.util.structGet(stats, "BLER_CI_High", NaN));
row.(char(prefix + "_TrialCount")) = double(sixgr.util.structGet(stats, "TrialCount", NaN));
row.(char(prefix + "_FailureCount")) = double(sixgr.util.structGet(stats, "FailureCount", NaN));
row.(char(prefix + "_Throughput_Mbps")) = double(sixgr.util.structGet(stats, "Throughput_Mbps", NaN));
row.(char(prefix + "_Throughput_CI_Low")) = double(sixgr.util.structGet(stats, "Throughput_CI_Low", NaN));
row.(char(prefix + "_Throughput_CI_High")) = double(sixgr.util.structGet(stats, "Throughput_CI_High", NaN));
row.(char(prefix + "_OfferedThroughput_Mbps")) = double(sixgr.util.structGet(stats, "OfferedThroughput_Mbps", NaN));
row.(char(prefix + "_Goodput_Mbps")) = double(sixgr.util.structGet(stats, "Goodput_Mbps", NaN));
row.(char(prefix + "_CodeBlockBLER")) = double(sixgr.util.structGet(stats, "CodeBlockBLER", NaN));
row.(char(prefix + "_CBG_BLER")) = double(sixgr.util.structGet(stats, "CBG_BLER", NaN));
row.(char(prefix + "_DecodeLatency_ms")) = double(sixgr.util.structGet(stats, "DecodeLatency_ms", NaN));
row.(char(prefix + "_DecoderComplexityUnits")) = double(sixgr.util.structGet(stats, "DecoderComplexityUnits", NaN));
row.(char(prefix + "_NormalizedDecoderComplexity")) = double(sixgr.util.structGet(stats, "NormalizedDecoderComplexity", NaN));
end

function row = localApplyScalarSweepStats(row, fieldPrefix, trialT, valueVar)
trialT = localEffectiveTrialRows(trialT);
vals = [];
if istable(trialT) && ~isempty(trialT) && ismember(valueVar, string(trialT.Properties.VariableNames))
    vals = double(trialT.(valueVar));
    vals = vals(isfinite(vals));
end
base = string(fieldPrefix);
if isempty(vals)
    return;
end
[lo, hi] = localMeanConfidenceInterval(vals);
row.(char(base)) = mean(vals, "omitnan");
ciBase = base;
countName = base;
if endsWith(base, "_dB")
    ciBase = erase(base, "_dB");
end
row.(char(ciBase + "_CI_Low")) = lo;
row.(char(ciBase + "_CI_High")) = hi;
parts = split(ciBase, "_");
if ~isempty(parts) && strlength(parts(1)) > 0
    countName = parts(1);
end
row.(char(countName + "_TrialCount")) = double(numel(vals));
end

function vals = localTableUniqueFinite(rawTrials, fieldName, varName)
vals = [];
T = sixgr.util.structGet(rawTrials, fieldName, table());
if ~(istable(T) && ~isempty(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = double(T.(varName));
vals = unique(sort(x(isfinite(x))));
end

function T = localSubsetTrialsBySNR(T, snr)
if ~(istable(T) && ~isempty(T) && ismember("SNR_dB", string(T.Properties.VariableNames)))
    T = table();
    return;
end
mask = isfinite(double(T.SNR_dB)) & abs(double(T.SNR_dB) - double(snr)) < 1e-9;
T = T(mask, :);
end

function res = localReplaceCaseResult(res, caseName, agg)
fieldName = matlab.lang.makeValidName(char(caseName));
if isfield(res, "Cases")
    res.Cases.(fieldName) = agg;
end
if ~(isfield(res, "KPITable") && istable(res.KPITable) && ~isempty(res.KPITable))
    return;
end
mask = strcmpi(string(res.KPITable.Case), string(caseName));
if ~any(mask)
    return;
end
res.KPITable.Ok(mask) = logical(agg.Ok);
res.KPITable.Skipped(mask) = logical(sixgr.util.structGet(agg, "Skipped", false));
if ismember("BER", string(res.KPITable.Properties.VariableNames))
    res.KPITable.BER(mask) = double(sixgr.util.structGet(agg, "BER", NaN));
end
if ismember("BLER", string(res.KPITable.Properties.VariableNames))
    res.KPITable.BLER(mask) = double(sixgr.util.structGet(agg, "BLER", NaN));
end
if ismember("Throughput_Mbps", string(res.KPITable.Properties.VariableNames))
    res.KPITable.Throughput_Mbps(mask) = double(sixgr.util.structGet(agg, "Throughput_Mbps", NaN));
end
if ismember("EVM_rms", string(res.KPITable.Properties.VariableNames))
    res.KPITable.EVM_rms(mask) = double(sixgr.util.structGet(agg, "EVM_rms", NaN));
end
if ismember("NMSE_dB", string(res.KPITable.Properties.VariableNames))
    res.KPITable.NMSE_dB(mask) = double(sixgr.util.structGet(agg, "NMSE_dB", NaN));
end
if ismember("Notes", string(res.KPITable.Properties.VariableNames))
    res.KPITable.Notes(mask) = string(sixgr.util.structGet(agg, "Notes", ""));
end
end

function nLayers = localConfiguredLayerCount(cfg, direction)
direction = upper(string(direction));
switch direction
    case "UL"
        nLayers = double(sixgr.util.structGet(cfg, "phy.pusch.nLayers", sixgr.util.structGet(cfg, "phy.pusch.numLayers", 1)));
    otherwise
        nLayers = double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", sixgr.util.structGet(cfg, "phy.pdsch.numLayers", 1)));
end
if ~(isscalar(nLayers) && isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
nLayers = max(1, round(nLayers));
end

function direction = directionFromTable(T)
direction = "DL";
if istable(T) && ~isempty(T) && ismember("Direction", string(T.Properties.VariableNames))
    direction = string(T.Direction(1));
end
end

function T = localSortTrialTableBySweep(T)
if ~(istable(T) && ~isempty(T))
    return;
end
sortVars = string.empty(0,1);
if ismember("SNR_dB", string(T.Properties.VariableNames))
    sortVars(end+1,1) = "SNR_dB"; %#ok<AGROW>
end
if ismember("Frame", string(T.Properties.VariableNames))
    sortVars(end+1,1) = "Frame"; %#ok<AGROW>
end
if isempty(sortVars)
    return;
end
T = sortrows(T, cellstr(sortVars));
end

function v = localTableMean(T, varName)
v = NaN;
if ~(istable(T) && ~isempty(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = double(T.(varName));
x = x(isfinite(x));
if isempty(x)
    return;
end
v = mean(x, "omitnan");
end

function tf = localLinkKPITableHealthy(kpi)
tf = false;
if ~(istable(kpi) && ~isempty(kpi))
    return;
end
if ~all(ismember(["Ok","Skipped"], string(kpi.Properties.VariableNames)))
    return;
end
tf = all(logical(kpi.Ok) & ~logical(kpi.Skipped));
end

function g = localReduceSweepGrid(gridIn, maxPts, anchorSNR)
g = unique(double(gridIn(:)), "sorted");
if isempty(g)
    g = double(anchorSNR);
    return;
end
maxPts = max(3, round(double(maxPts)));
if numel(g) <= maxPts
    return;
end
anchorIdx = find(g <= anchorSNR, 1, "last");
if isempty(anchorIdx)
    anchorIdx = 1;
end
keep = unique([1; anchorIdx; numel(g)]);
if numel(keep) < maxPts
    need = maxPts - numel(keep);
    rem = setdiff((1:numel(g)).', keep(:), "stable");
    if ~isempty(rem)
        pickIdx = round(linspace(1, numel(rem), min(need, numel(rem))));
        keep = unique([keep(:); rem(pickIdx(:))], "stable");
    end
end
g = g(sort(keep));
end

function plan = localResolveSweepPlan(opt, numFrames)
if nargin < 1 || ~isstruct(opt)
    opt = struct();
end
baseTrials = max(8, round(double(numFrames)));
plan = struct();
defaultPrimaryTrials = max(12, min(32, 2 * baseTrials));
explicitTrials = round(double(sixgr.util.structGet(opt, "LinkSweepTrialsPerSNR", NaN)));
legacyIterations = round(double(sixgr.util.structGet(opt, "LinkSweepFrames", NaN)));
if isfinite(explicitTrials) && explicitTrials >= 1
    requestedPrimaryTrials = explicitTrials;
elseif isfinite(legacyIterations) && legacyIterations >= 1
    requestedPrimaryTrials = baseTrials * legacyIterations;
else
    requestedPrimaryTrials = defaultPrimaryTrials;
end
plan.PrimaryTrialsPerSNR = max(baseTrials, requestedPrimaryTrials);

defaultReferenceTrials = max(20, min(48, 3 * baseTrials));
requestedReferenceTrials = round(double(sixgr.util.structGet(opt, "LinkReferenceSweepFrames", NaN)));
if ~(isfinite(requestedReferenceTrials) && requestedReferenceTrials >= 1)
    requestedReferenceTrials = defaultReferenceTrials;
end
plan.ReferenceTrialsPerSNR = max(plan.PrimaryTrialsPerSNR, requestedReferenceTrials);
plan.MaxSweepPoints = max(3, round(double(sixgr.util.structGet(opt, "LinkSweepMaxPoints", 7))));
plan.ReferenceSweepStep_dB = max(1, double(sixgr.util.structGet(opt, "LinkReferenceSweepStep_dB", 5)));
plan.ReferenceSweepMargin_dB = max(plan.ReferenceSweepStep_dB * 3, double(sixgr.util.structGet(opt, "LinkReferenceSweepMargin_dB", 24)));
plan.ReferenceMaxSweepPoints = max(plan.MaxSweepPoints + 1, round(double(sixgr.util.structGet(opt, "LinkReferenceSweepMaxPoints", 8))));
end

function grid = localBuildAdaptiveRefinedGrid(sweepT, anchorGrid, cfg, opt)
grid = [];
if ~(istable(sweepT) && ~isempty(sweepT) && ismember("SNR_dB", string(sweepT.Properties.VariableNames)))
    return;
end
if ~logical(sixgr.util.structGet(opt, "LinkAdaptiveSweepEnabled", localShouldAdaptiveRefineTruthSweep(cfg)))
    return;
end
step = max(1, double(sixgr.util.structGet(opt, "LinkAdaptiveSweepStep_dB", 2)));
maxExtra = max(0, round(double(sixgr.util.structGet(opt, "LinkAdaptiveSweepMaxPoints", 12))));
if maxExtra == 0
    return;
end

anchorGrid = unique(sort(double(anchorGrid(:))));
if numel(anchorGrid) < 2
    return;
end

for prefix = ["DL","UL"]
    grid = [grid; localBuildDirectionAdaptiveGrid(sweepT, prefix, step)]; %#ok<AGROW>
end
grid = unique(sort(double(grid(:))));
grid = setdiff(grid, anchorGrid, "stable");
if isempty(grid)
    return;
end
if numel(grid) > maxExtra
    pick = round(linspace(1, numel(grid), maxExtra));
    grid = unique(grid(pick(:)), "stable");
end
end

function tf = localShouldAdaptiveRefineTruthSweep(cfg)
tf = logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
    logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false));
end

function grid = localBuildDirectionAdaptiveGrid(sweepT, prefix, step)
grid = [];
prefix = upper(string(prefix));
blCol = prefix + "_BLER";
thrCol = prefix + "_Throughput_Mbps";
if ~(all(ismember(["SNR_dB", blCol, thrCol], string(sweepT.Properties.VariableNames))))
    return;
end
x = double(sweepT.SNR_dB);
bler = double(sweepT.(blCol));
thr = double(sweepT.(thrCol));
[x, order] = sort(x(:));
bler = bler(order);
thr = thr(order);
maxThr = max(thr(isfinite(thr)), [], "omitnan");
if ~isfinite(maxThr)
    maxThr = NaN;
end
for i = 1:max(numel(x) - 1, 0)
    x1 = x(i);
    x2 = x(i + 1);
    if ~(isfinite(x1) && isfinite(x2) && x2 - x1 > step)
        continue;
    end
    b1 = bler(i);
    b2 = bler(i + 1);
    t1 = thr(i);
    t2 = thr(i + 1);
    largeBLERJump = all(isfinite([b1 b2])) && (abs(b2 - b1) >= 0.5 || (b1 >= 0.9 && b2 <= 0.1) || (b2 >= 0.9 && b1 <= 0.1));
    largeThrJump = isfinite(maxThr) && maxThr > 0 && all(isfinite([t1 t2])) && abs(t2 - t1) >= 0.25 * maxThr;
    if ~(largeBLERJump || largeThrJump)
        continue;
    end
    grid = [grid; (x1 + step:step:x2 - step).']; %#ok<AGROW>
end
end

function grid = localBuildReferenceSweepGrid(snrGrid, sweepPlan)
grid = unique(sort(double(snrGrid(:))));
if isempty(grid)
    return;
end
step = double(sweepPlan.ReferenceSweepStep_dB);
margin = double(sweepPlan.ReferenceSweepMargin_dB);
lo = min(grid) - margin;
hi = max(grid);
dense = (lo:step:hi).';
grid = unique(sort([grid; dense]));
grid = localReduceSweepGrid(grid, double(sweepPlan.ReferenceMaxSweepPoints), max(double(snrGrid(:))));
end

function slotDur_s = localSlotDuration(cfg)
scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
mu = log2(scs/15);
if ~isfinite(mu) || mu < 0
    mu = 0;
end
slotDur_s = 1e-3 / (2^mu);
end

function [y, nVar] = localAddAwgn(x, snr_dB)
[y, nVar] = sixgr.util.addAwgnComplex(x, snr_dB);
end

function [be, bt] = localBitErrors(txBits, rxBits)
txBits = int8(txBits(:));
rxBits = int8(rxBits(:));
L = min(numel(txBits), numel(rxBits));
if L <= 0
    be = numel(txBits);
    bt = max(numel(txBits), 1);
    return;
end
be = sum(txBits(1:L) ~= rxBits(1:L));
bt = max(numel(txBits), L);
end

function artifacts = localExportBeamformingDiagnostics(cfg, airInterfaceRunFolder, rawTrials, saveFigures)
artifacts = struct("CSV", "", "SummaryCSV", "", "TraceCSV", "", "Images", {{}}, "Table", table(), "SummaryTable", table(), "TraceTable", table());

rootRunFolder = fileparts(char(string(airInterfaceRunFolder)));
layout = sixgr.report.resultLayout(rootRunFolder);
sixgr.util.ensureFolder(layout.BeamformingCSVDir);
sixgr.util.ensureFolder(layout.BeamformingImageDir);

T = localBuildBeamformingTable(cfg, rawTrials);
if isempty(T)
    return;
end

csvPath = fullfile(layout.BeamformingCSVDir, "probe_beam_mimo.csv");
sixgr.util.csvWriteTable(csvPath, T);
artifacts.CSV = csvPath;
artifacts.Table = T;

summaryT = localBuildBeamManagementSummaryTable(T, cfg);
if ~isempty(summaryT)
    summaryPath = fullfile(layout.BeamformingCSVDir, "probe_beam_management.csv");
    sixgr.util.csvWriteTable(summaryPath, summaryT);
    artifacts.SummaryCSV = summaryPath;
    artifacts.SummaryTable = summaryT;
end

traceT = localBuildBeamScoreTraceTable(T, cfg);
if ~isempty(traceT)
    tracePath = fullfile(layout.BeamformingCSVDir, "beam_score_trace.csv");
    sixgr.util.csvWriteTable(tracePath, traceT);
    artifacts.TraceCSV = tracePath;
    artifacts.TraceTable = traceT;
end

if ~saveFigures
    return;
end

img1 = fullfile(layout.BeamformingImageDir, "beam_channel_sinr.png");
localWriteGroupedMetricPlot(T, "MeasuredSINR_dB", img1, "Measured SINR by Trial", "SINR (dB)");
if exist(img1, "file") == 2
    artifacts.Images{end+1} = img1;
end

img2 = fullfile(layout.BeamformingImageDir, "beam_condition_number.png");
localWriteGroupedMetricPlot(T, "ConditionNumber_dB", img2, "Channel Condition Number by Trial", "Condition Number (dB)");
if exist(img2, "file") == 2
    artifacts.Images{end+1} = img2;
end

img3 = fullfile(layout.BeamformingImageDir, "beam_gain_gap.png");
localWriteGroupedMetricPlot(T, "BeamGainGap_dB", img3, "Beam Gain Gap by Trial", "Gain gap (dB)");
if exist(img3, "file") == 2
    artifacts.Images{end+1} = img3;
end
end

function T = localBuildBeamformingTable(cfg, rawTrials)
T = table();
beamSweepEnabled = logical(sixgr.util.structGet(cfg, "phy.beamManagement.enabled", false));
beamCount = double(sixgr.util.structGet(cfg, "phy.beamManagement.beamCount", NaN));
tables = {};
if isstruct(rawTrials)
    if isfield(rawTrials, "DL")
        Tdl = localResolveTrialTable(rawTrials.DL);
        if istable(Tdl) && ~isempty(Tdl)
            tables{end+1} = Tdl; %#ok<AGROW>
        end
    end
    if isfield(rawTrials, "UL")
        Tul = localResolveTrialTable(rawTrials.UL);
        if istable(Tul) && ~isempty(Tul)
            tables{end+1} = Tul; %#ok<AGROW>
        end
    end
end
if isempty(tables)
    return;
end

keepVars = ["UEIndex","RNTI","Direction","SNR_dB","Frame","Slot","MCS","PRBs","Layers", ...
    "ConfiguredLayers","ConfiguredTxAntennas","ConfiguredRxAntennas", ...
    "MeasuredSINR_dB","WidebandCQI","RankIndicator","PMI","ChannelGain_dB","ConditionNumber_dB", ...
    "RankEstimate","NumRxAntennas","NumTxPorts","SelectedBeamIndex","BestBeamIndex", ...
    "BeamHit","TopKBeamHit","BeamCandidateCount","SelectedBeamGain_dB","BestBeamGain_dB","BeamGainGap_dB", ...
    "BeamSelectionStrategy","BeamIndexSet", ...
    "PrecoderSource","BeamformingApplied","ExecutionModel","Status"];

chunks = cell(numel(tables), 1);
for i = 1:numel(tables)
    Ti = tables{i};
    if ~all(ismember(["MeasuredSINR_dB","ConditionNumber_dB","ChannelGain_dB"], string(Ti.Properties.VariableNames)))
        continue;
    end
    hasMetrics = isfinite(double(Ti.MeasuredSINR_dB)) | isfinite(double(Ti.ConditionNumber_dB)) | isfinite(double(Ti.ChannelGain_dB));
    Ti = Ti(hasMetrics, :);
    if isempty(Ti)
        continue;
    end
    Ti = Ti(:, keepVars(ismember(keepVars, string(Ti.Properties.VariableNames))));
    Ti.BeamSweepEnabled = repmat(beamSweepEnabled, height(Ti), 1);
    Ti.BeamCount = repmat(beamCount, height(Ti), 1);
    chunks{i} = Ti;
end

chunks = chunks(~cellfun(@isempty, chunks));
if isempty(chunks)
    return;
end
T = vertcat(chunks{:});
end

function summaryT = localBuildBeamManagementSummaryTable(T, cfg)
summaryT = localEmptyProbeMetricTable();
if ~(istable(T) && ~isempty(T))
    return;
end
dirs = localUniqueDirections(T);
slotDur_s = localSlotDuration(cfg);
numTRPs = max(1, round(double(sixgr.util.structGet(cfg, "scenario.nTRP", ...
    sixgr.util.structGet(cfg, "deployment_topology.num_trps", 1)))));
for i = 1:numel(dirs)
    dirMask = string(T.Direction) == dirs(i);
    Ti = T(dirMask, :);
    if isempty(Ti)
        continue;
    end
    beamDetected = isfinite(double(Ti.BestBeamIndex));
    beamHit = localFiniteMaskValue(Ti, "BeamHit");
    topKHit = localFiniteMaskValue(Ti, "TopKBeamHit");
    beamGap = localFiniteColumn(Ti, "BeamGainGap_dB");
    beamCount = localFiniteColumn(Ti, "BeamCandidateCount");
    selectedBeam = localFiniteColumn(Ti, "SelectedBeamIndex");
    meanSwitchSlots = localMeanBeamSwitchInterval(selectedBeam);
    meanTrialsToHit = localMeanTrialsToFirstHit(Ti);
    failureRate = NaN;
    if ~isempty(beamGap)
        failureRate = mean(beamGap > 3, "omitnan");
    end
    overhead = NaN;
    if ~isempty(beamCount)
        overhead = mean(beamCount, "omitnan");
    end
    predictionAccuracy = mean(beamHit, "omitnan");
    if numTRPs <= 1
        mtrpGain = 0;
        mtrpNote = "Single-TRP runtime; mTRP beam-selection gain is zero by construction for this scenario.";
    else
        mtrpGain = mean(max(beamGap, 0), "omitnan");
        mtrpNote = "Multi-TRP beam-selection proxy from measured selected-vs-best beam gain gap.";
    end
    summaryT = [summaryT; ... %#ok<AGROW>
        localProbeMetricRow("beam_detection_probability", dirs(i), "rate", mean(beamDetected), "", "fraction", "Measured from finite best-beam detections."); ...
        localProbeMetricRow("beam_index_hit_rate", dirs(i), "rate", mean(beamHit, "omitnan"), "", "fraction", "Selected beam matches the best measured beam."); ...
        localProbeMetricRow("top_k_beam_hit_rate", dirs(i), "top2_rate", mean(topKHit, "omitnan"), "", "fraction", "Selected beam lies within the top-2 measured beam set."); ...
        localProbeMetricRow("beam_switch_latency", dirs(i), "mean_between_switches", meanSwitchSlots * slotDur_s, "", "s", "Measured mean interval between selected-beam changes across runtime trials."); ...
        localProbeMetricRow("beam_misalignment_probability", dirs(i), "rate", 1 - mean(beamHit, "omitnan"), "", "fraction", "Selected beam differs from the best measured beam."); ...
        localProbeMetricRow("beam_prediction_accuracy", dirs(i), "rate", predictionAccuracy, "", "fraction", "Measured selected-beam accuracy under the active runtime beam-selection strategy."); ...
        localProbeMetricRow("beam_refinement_convergence", dirs(i), "mean_trials_to_first_hit", meanTrialsToHit, "", "trials", "Measured trials-to-first-hit from the runtime beam-selection sequence."); ...
        localProbeMetricRow("beam_failure_rate", dirs(i), "rate", failureRate, "", "fraction", "Beam gain gap exceeds 3 dB relative to the best measured beam."); ...
        localProbeMetricRow("mtrp_beam_selection_gain", dirs(i), "delta_dB", mtrpGain, "", "dB", mtrpNote); ...
        localProbeMetricRow("beam_management_overhead", dirs(i), "mean_beams_evaluated", overhead, "", "beams", "Average number of candidate beams evaluated per trial.")];
end
end

function paprT = localBuildPAPRCCDFTable(rawTrials)
paprT = table();
if ~isstruct(rawTrials)
    return;
end

dirs = ["DL","UL"];
chunks = cell(numel(dirs), 1);
for i = 1:numel(dirs)
    if ~isfield(rawTrials, dirs(i))
        continue;
    end
    Ti = localResolveTrialTable(rawTrials.(dirs(i)));
    if ~(istable(Ti) && ismember("PAPR_dB", string(Ti.Properties.VariableNames)))
        continue;
    end
    samples = double(Ti.PAPR_dB);
    samples = samples(isfinite(samples));
    if isempty(samples)
        continue;
    end
    lo = floor(min(samples) * 2) / 2;
    hi = ceil(max(samples) * 2) / 2;
    if ~isfinite(lo) || ~isfinite(hi)
        continue;
    end
    if hi <= lo
        grid = lo;
    else
        grid = linspace(lo, hi, min(64, max(16, numel(unique(round(samples, 2)))))).';
    end
    ccdf = arrayfun(@(thr) mean(samples >= thr, "omitnan"), grid);
    chunks{i} = table(repmat(dirs(i), numel(grid), 1), grid, ccdf, ...
        'VariableNames', {'Direction','PAPR_dB','CCDF'});
end

chunks = chunks(~cellfun(@isempty, chunks));
if isempty(chunks)
    return;
end
paprT = vertcat(chunks{:});
end

function traceT = localBuildBeamScoreTraceTable(T, cfg)
traceT = table();
if ~(istable(T) && ~isempty(T))
    return;
end
vars = ["Direction","SNR_dB","Frame","Slot","UEIndex","RNTI","SelectedBeamIndex","BestBeamIndex", ...
    "BeamHit","TopKBeamHit","BeamCandidateCount","SelectedBeamGain_dB","BestBeamGain_dB", ...
    "BeamGainGap_dB","MeasuredSINR_dB","ChannelGain_dB","BeamSelectionStrategy","BeamIndexSet", ...
    "PrecoderSource","BeamformingApplied","ExecutionModel","Status"];
vars = vars(ismember(vars, string(T.Properties.VariableNames)));
traceT = T(:, vars);
traceT.BeamSweepEnabled = repmat(logical(sixgr.util.structGet(cfg, "phy.beamManagement.enabled", false)), height(traceT), 1);
traceT.BeamCountConfigured = repmat(double(sixgr.util.structGet(cfg, "phy.beamManagement.beamCount", NaN)), height(traceT), 1);
end

function T = localResolveTrialTable(v)
T = table();
if istable(v)
    T = v;
    return;
end
if isstring(v) || ischar(v)
    p = char(string(v));
    if exist(p, "file") == 2
        T = readtable(p, "VariableNamingRule", "preserve");
    end
end
end

function images = localExportTrialDiagnosticPlots(airInterfaceRunFolder, rawTrials, saveFigures)
images = {};
if ~saveFigures
    return;
end
imgDir = fullfile(airInterfaceRunFolder, "image");
sixgr.util.ensureFolder(imgDir);

if isstruct(rawTrials) && isfield(rawTrials, "DL")
    Tdl = localResolveTrialTable(rawTrials.DL);
else
    Tdl = table();
end
if isstruct(rawTrials) && isfield(rawTrials, "DLConstellation")
    TdlConst = localResolveTrialTable(rawTrials.DLConstellation);
else
    TdlConst = table();
end
if istable(Tdl) && ~isempty(Tdl)
    img = fullfile(imgDir, "dl_trial_sinr.png");
    localWriteTrialMetricPlot(Tdl, "MeasuredSINR_dB", img, "DL Trial SINR", "SINR (dB)");
    if exist(img, "file") == 2
        images{end+1} = img; %#ok<AGROW>
    end

    img = fullfile(imgDir, "dl_trial_channel_gain.png");
    localWriteTrialMetricPlot(Tdl, "ChannelGain_dB", img, "DL Trial Channel Gain", "Gain (dB)");
    if exist(img, "file") == 2
        images{end+1} = img; %#ok<AGROW>
    end
end
if istable(TdlConst) && ~isempty(TdlConst)
    img = fullfile(imgDir, "dl_constellation_scatter.png");
    localWriteConstellationScatterPlot(TdlConst, img, "DL Constellation Scatter");
    if exist(img, "file") == 2
        images{end+1} = img; %#ok<AGROW>
    end
end

if isstruct(rawTrials) && isfield(rawTrials, "UL")
    Tul = localResolveTrialTable(rawTrials.UL);
else
    Tul = table();
end
if isstruct(rawTrials) && isfield(rawTrials, "ULConstellation")
    TulConst = localResolveTrialTable(rawTrials.ULConstellation);
else
    TulConst = table();
end
if istable(Tul) && ~isempty(Tul)
    img = fullfile(imgDir, "ul_trial_sinr.png");
    localWriteTrialMetricPlot(Tul, "MeasuredSINR_dB", img, "UL Trial SINR", "SINR (dB)");
    if exist(img, "file") == 2
        images{end+1} = img; %#ok<AGROW>
    end

    img = fullfile(imgDir, "ul_trial_channel_gain.png");
    localWriteTrialMetricPlot(Tul, "ChannelGain_dB", img, "UL Trial Channel Gain", "Gain (dB)");
    if exist(img, "file") == 2
        images{end+1} = img; %#ok<AGROW>
    end
end
if istable(TulConst) && ~isempty(TulConst)
    img = fullfile(imgDir, "ul_constellation_scatter.png");
    localWriteConstellationScatterPlot(TulConst, img, "UL Constellation Scatter");
    if exist(img, "file") == 2
        images{end+1} = img; %#ok<AGROW>
    end
end
end

function localWriteTrialMetricPlot(T, metricName, outPath, plotTitle, yLabel)
if ~(istable(T) && ~isempty(T) && ismember(metricName, string(T.Properties.VariableNames)))
    return;
end
if ismember("UEIndex", string(T.Properties.VariableNames)) && numel(unique(double(T.UEIndex))) > 1
    localWriteGroupedMetricPlot(T, metricName, outPath, plotTitle, yLabel);
    return;
end
[x, xLabel] = localResolveTrialPlotXAxis(T, 1, 1);
y = double(T.(metricName));
mask = isfinite(x) & isfinite(y);
if ~any(mask)
    return;
end
multiSweep = localHasMultipleSweepPoints(T);
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
if multiSweep
    scatter(ax, x(mask), y(mask), 16, "MarkerEdgeColor", [0 0.447 0.741], ...
        "MarkerFaceColor", "none", "DisplayName", plotTitle);
else
    plot(ax, x(mask), y(mask), "o-", "LineWidth", 1.25, "MarkerSize", 4);
end
grid(ax, "on");
xlabel(ax, xLabel);
ylabel(ax, yLabel);
title(ax, plotTitle);
localApplySweepXAxis(ax, T, xLabel);
exportgraphics(fig, outPath, "Resolution", 160);
end

function localWriteGroupedMetricPlot(T, metricName, outPath, plotTitle, yLabel)
if ~(istable(T) && ~isempty(T) && ismember(metricName, string(T.Properties.VariableNames)))
    return;
end
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
groupValues = strings(0,1);
groupMask = cell(0,1);
if ismember("UEIndex", string(T.Properties.VariableNames))
    ues = unique(double(T.UEIndex));
    for i = 1:numel(ues)
        mask = double(T.UEIndex) == ues(i);
        if ismember("Direction", string(T.Properties.VariableNames))
            dirVals = unique(string(T.Direction(mask)));
            for d = 1:numel(dirVals)
                maskDir = mask & string(T.Direction) == dirVals(d);
                groupValues(end+1,1) = dirVals(d) + " UE" + string(ues(i)); %#ok<AGROW>
                groupMask{end+1,1} = maskDir; %#ok<AGROW>
            end
        else
            groupValues(end+1,1) = "UE" + string(ues(i)); %#ok<AGROW>
            groupMask{end+1,1} = mask; %#ok<AGROW>
        end
    end
elseif ismember("Direction", string(T.Properties.VariableNames))
    dirs = unique(string(T.Direction));
    for i = 1:numel(dirs)
        groupValues(end+1,1) = dirs(i); %#ok<AGROW>
        groupMask{end+1,1} = string(T.Direction) == dirs(i); %#ok<AGROW>
    end
else
    localWriteTrialMetricPlot(T, metricName, outPath, plotTitle, yLabel);
    return;
end

multiSweep = localHasMultipleSweepPoints(T);
made = false;
xLabel = "Frame";
for i = 1:numel(groupValues)
    maskDir = groupMask{i};
    [xAll, xLabel] = localResolveTrialPlotXAxis(T, i, numel(groupValues));
    x = xAll(maskDir);
    y = double(T.(metricName)(maskDir));
    mask = isfinite(x) & isfinite(y);
    if ~any(mask)
        continue;
    end
    seriesColor = ax.ColorOrder(1 + mod(i - 1, size(ax.ColorOrder, 1)), :);
    if multiSweep
        scatter(ax, x(mask), y(mask), 16, "MarkerEdgeColor", seriesColor, ...
            "MarkerFaceColor", "none", "DisplayName", char(groupValues(i)));
    else
        plot(ax, x(mask), y(mask), "o-", "LineWidth", 1.25, "MarkerSize", 4, "DisplayName", char(groupValues(i)));
    end
    made = true;
end
if ~made
    return;
end
grid(ax, "on");
xlabel(ax, xLabel);
ylabel(ax, yLabel);
title(ax, plotTitle);
localApplySweepXAxis(ax, T, xLabel);
if numel(groupValues) <= 12
    legend(ax, "Location", "best");
end
exportgraphics(fig, outPath, "Resolution", 160);
end

function [x, xLabel] = localResolveTrialPlotXAxis(T, groupIndex, groupCount)
multiSweep = localHasMultipleSweepPoints(T);
if multiSweep && ismember("SNR_dB", string(T.Properties.VariableNames))
    x = double(T.SNR_dB);
    if nargin >= 3 && groupCount > 1
        x = x + localSymmetricGroupOffset(groupIndex, groupCount, 0.35);
    end
    xLabel = "Configured SNR (dB)";
    return;
end
if ismember("Frame", string(T.Properties.VariableNames))
    x = double(T.Frame);
    xLabel = "Frame";
else
    x = (1:height(T)).';
    xLabel = "Trial";
end
end

function offset = localSymmetricGroupOffset(groupIndex, groupCount, maxMagnitude)
if nargin < 3
    maxMagnitude = 0.35;
end
if groupCount <= 1
    offset = 0;
    return;
end
centers = linspace(-double(maxMagnitude), double(maxMagnitude), groupCount);
offset = centers(groupIndex);
end

function localApplySweepXAxis(ax, T, xLabel)
if ~(strcmpi(string(xLabel), "Configured SNR (dB)") && istable(T) && ismember("SNR_dB", string(T.Properties.VariableNames)))
    return;
end
snrVals = unique(double(T.SNR_dB), "sorted");
snrVals = snrVals(isfinite(snrVals));
if isempty(snrVals)
    return;
end
xticks(ax, snrVals.');
if numel(snrVals) >= 2
    xlim(ax, [min(snrVals) - 1, max(snrVals) + 1]);
else
    xlim(ax, [snrVals(1) - 1, snrVals(1) + 1]);
end
end

function tf = localHasMultipleSweepPoints(T)
tf = false;
if ~(istable(T) && ismember("SNR_dB", string(T.Properties.VariableNames)))
    return;
end
snrVals = double(T.SNR_dB);
snrVals = unique(snrVals(isfinite(snrVals)));
tf = numel(snrVals) > 1;
end

function localWriteConstellationScatterPlot(T, outPath, plotTitle)
vars = ["EqualizedReal","EqualizedImag"];
if ~(istable(T) && ~isempty(T) && all(ismember(vars, string(T.Properties.VariableNames))))
    return;
end
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
eqMask = isfinite(double(T.EqualizedReal)) & isfinite(double(T.EqualizedImag));
if any(eqMask)
    scatter(ax, double(T.EqualizedReal(eqMask)), double(T.EqualizedImag(eqMask)), 12, ...
        "filled", "MarkerFaceAlpha", 0.35, "DisplayName", "Aligned equalized");
end
hardRealName = "HardDecisionReal";
hardImagName = "HardDecisionImag";
if ~ismember(hardRealName, string(T.Properties.VariableNames))
    hardRealName = "DecisionReal";
end
if ~ismember(hardImagName, string(T.Properties.VariableNames))
    hardImagName = "DecisionImag";
end
decMask = isfinite(double(T.(hardRealName))) & isfinite(double(T.(hardImagName)));
if any(decMask)
    scatter(ax, double(T.(hardRealName)(decMask)), double(T.(hardImagName)(decMask)), 18, ...
        "x", "DisplayName", "Hard decision");
end
refRealName = "ReferenceSymbolReal";
refImagName = "ReferenceSymbolImag";
if ~ismember(refRealName, string(T.Properties.VariableNames))
    refRealName = "TxReal";
end
if ~ismember(refImagName, string(T.Properties.VariableNames))
    refImagName = "TxImag";
end
refMask = isfinite(double(T.(refRealName))) & isfinite(double(T.(refImagName)));
if any(refMask)
    scatter(ax, double(T.(refRealName)(refMask)), double(T.(refImagName)(refMask)), 14, ...
        "+", "DisplayName", "Reference");
end
grid(ax, "on");
axis(ax, "equal");
xlabel(ax, "In-phase");
ylabel(ax, "Quadrature");
title(ax, plotTitle + " (aligned equalized / hard decision)");
legend(ax, "Location", "best");
exportgraphics(fig, outPath, "Resolution", 160);
end

function T = localEmptyProbeMetricTable()
T = table('Size', [0 7], ...
    'VariableTypes', {'string','string','string','double','string','string','string'}, ...
    'VariableNames', {'MetricKey','Entity','Statistic','Value','TextValue','Unit','Notes'});
end

function T = localProbeMetricRow(metricKey, entity, statistic, value, textValue, unit, notes)
T = table(string(metricKey), string(entity), string(statistic), double(value), string(textValue), string(unit), string(notes), ...
    'VariableNames', {'MetricKey','Entity','Statistic','Value','TextValue','Unit','Notes'});
end

function dirs = localUniqueDirections(T)
dirs = strings(0, 1);
if ~(istable(T) && ismember("Direction", string(T.Properties.VariableNames)))
    return;
end
dirs = unique(string(T.Direction), "stable");
end

function vals = localFiniteMaskValue(T, varName)
vals = [];
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = double(T.(varName));
vals = x(isfinite(x));
end

function vals = localFiniteColumn(T, varName)
vals = [];
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = double(T.(varName));
vals = x(isfinite(x));
end

function count = localBeamSwitchCount(selectedBeam)
count = 0;
if isempty(selectedBeam)
    return;
end
selectedBeam = double(selectedBeam(:));
selectedBeam = selectedBeam(isfinite(selectedBeam));
if numel(selectedBeam) <= 1
    return;
end
count = sum(abs(diff(selectedBeam)) > 0);
end

function meanInterval = localMeanBeamSwitchInterval(selectedBeam)
meanInterval = NaN;
if isempty(selectedBeam)
    return;
end
selectedBeam = double(selectedBeam(:));
selectedBeam = selectedBeam(isfinite(selectedBeam));
if numel(selectedBeam) <= 1
    meanInterval = 0;
    return;
end
switchIdx = find(abs(diff(selectedBeam)) > 0) + 1;
if isempty(switchIdx)
    meanInterval = numel(selectedBeam);
    return;
end
intervals = diff([1; switchIdx(:)]);
meanInterval = mean(double(intervals), "omitnan");
end

function meanTrials = localMeanTrialsToFirstHit(T)
meanTrials = NaN;
if ~(istable(T) && ismember("BeamHit", string(T.Properties.VariableNames)))
    return;
end
hits = double(T.BeamHit);
hits = hits(isfinite(hits));
if isempty(hits)
    return;
end
firstHit = find(hits > 0, 1, "first");
if isempty(firstHit)
    meanTrials = numel(hits);
else
    meanTrials = double(firstHit);
end
end
