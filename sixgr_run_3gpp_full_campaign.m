function report = sixgr_run_3gpp_full_campaign(cfgFile, varargin)
%SIXGR_RUN_3GPP_FULL_CAMPAIGN Unified 3GPP-oriented analysis campaign.
%
% This orchestrator runs multiple analyses and stores all artifacts under one
% parent folder with subfolders per module:
%   - link/         : long link-level run (time + SNR sweep + plots)
%   - detailed_lls/ : block-level PHY diagnostics
%   - system/       : mobility system-level KPIs
%   - system_mmtc/  : mMTC traffic profile KPIs
%   - end_to_end/   : SDAP/PDCP/RLC/MAC/RRC/AI stack probe
%   - csv/          : campaign-level probe tables + 25-category audit
%   - mat/          : consolidated report mat file
%   - logs/         : campaign log
%
% NOTE:
%   Some 25-category items are approximated or not modeled by the current
%   simulator architecture. This script records explicit status per category.

ip = inputParser;
ip.addOptional("ConfigFile", "config/suite_config.json", @(x)ischar(x)||isstring(x)||isstruct(x));
ip.addParameter("ResultsRoot", "", @(x)ischar(x)||isstring(x));
ip.addParameter("LinkDuration_s", 20, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter("LinkMaxSimFrames", 48, @(x)isnumeric(x)&&isscalar(x)&&x>=8);
ip.addParameter("LinkSNR_dB", 20, @(x)isnumeric(x)&&isscalar(x));
ip.addParameter("LinkSNRGrid_dB", -10:4:30, @(x)isnumeric(x)&&isvector(x)&&~isempty(x));
ip.addParameter("LinkSweepFrames", 3, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter("LinkSweepMaxPoints", 5, @(x)isnumeric(x)&&isscalar(x)&&x>=3);
ip.addParameter("LinkSaveFigures", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("SystemDuration_s", 20, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter("SystemNumUE", 32, @(x)isnumeric(x)&&isscalar(x)&&x>=4);
ip.addParameter("SystemDetailedTrace", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("SystemSaveFigures", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("RunSystemMMTCProbe", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("MMTCNumUE", 0, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter("MMTCSaveFigures", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("RunAuxiliaryProbes", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("UseFastLinkModel", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("UseMexAcceleration", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("UseParallelAcceleration", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("AutoStartParallelPool", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("AutoBuildMexAcceleration", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("HARQPackets", 64, @(x)isnumeric(x)&&isscalar(x)&&x>=10);
ip.addParameter("HARQMaxRetx", 3, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter("V2XPackets", 72, @(x)isnumeric(x)&&isscalar(x)&&x>=20);
ip.addParameter("V2XVelocities_kmh", [30 120 250], @(x)isnumeric(x)&&isvector(x)&&~isempty(x));
ip.addParameter("NTNFrames", 8, @(x)isnumeric(x)&&isscalar(x)&&x>=4);
ip.addParameter("NTNDelays_ms", [5 20 50], @(x)isnumeric(x)&&isvector(x)&&~isempty(x));
ip.addParameter("NTNDoppler_Hz", [200 800 1500], @(x)isnumeric(x)&&isvector(x)&&~isempty(x));
ip.addParameter("RunE2EStackProbe", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("OnlyE2E", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2EDuration_s", 20, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter("E2EMaxSlots", 800, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter("E2EUECount", 4, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter("E2ETrafficModel", "xr", @(x)ischar(x)||isstring(x));
ip.addParameter("E2EEnableAI", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2ESaveFigures", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2EAirModel", "lut", @(x)ischar(x)||isstring(x));
ip.addParameter("E2EScaleServiceWithCompression", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2EServiceScaleCap", 256, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter("E2EStrictValidation", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2ETruthMaxSlots", 240, @(x)isnumeric(x)&&isscalar(x)&&x>=20);
ip.addParameter("E2EEnableSemanticChecks", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2EScaleChunkWithCompression", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2EMaxSDUChunkBytes", 4*1024*1024, @(x)isnumeric(x)&&isscalar(x)&&x>=1024);
ip.addParameter("E2EFastTraceMode", "lite", @(x)ischar(x)||isstring(x));
ip.addParameter("E2ETruthFastAWGNPath", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2ETruthCompactPHYIO", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2ETruthAdaptiveLDPC", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2ETruthLDPCMaxIterations", 0, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter("E2ETruthUseGPU", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("CalibrateSystemBLERFromLink", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("ReuseLinkForDetailedDiagnostics", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("MirrorStructuredResults", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("OrganizeByBlock", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("GenerateCampaignPlots", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("VerifyArtifacts", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("SetupToolboxChecks", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("Verbose", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.parse(cfgFile, varargin{:});
optUser = ip.Results;
opt = optUser;

verbose = logical(opt.Verbose);
setup6GRSimToolkit("Verbose", verbose, "RunToolboxChecks", logical(opt.SetupToolboxChecks));
if builtin("isstruct", opt.ConfigFile) && isscalar(opt.ConfigFile)
    cfg = sixgr.util.mergeStruct(sixgr.config.defaultConfig(), opt.ConfigFile);
    cfg = sixgr.config.normalizeConfig(cfg);
    sixgr.config.validateConfig(cfg);
else
    cfg = sixgr_loadConfig(char(string(opt.ConfigFile)));
end
opt = localApplyCampaignConfig(opt, cfg);
lockedFields = setdiff(string(fieldnames(optUser)), string(ip.UsingDefaults));
for iLock = 1:numel(lockedFields)
    fn = char(lockedFields(iLock));
    if isfield(optUser, fn)
        opt.(fn) = optUser.(fn);
    end
end
cfg.run.useMex = logical(sixgr.util.structGet(cfg, "run.useMex", false)) || logical(opt.UseMexAcceleration);
cfg.run.useParallel = logical(sixgr.util.structGet(cfg, "run.useParallel", false)) || logical(opt.UseParallelAcceleration);
cfg.run.autoStartParallelPool = logical(sixgr.util.structGet(cfg, "run.autoStartParallelPool", false)) || logical(opt.AutoStartParallelPool);
if cfg.run.useParallel && cfg.run.autoStartParallelPool
    localEnsureParallelPool();
end
if cfg.run.useMex && logical(opt.AutoBuildMexAcceleration)
    localEnsureMexAccelerators();
end

resultsRoot = char(string(opt.ResultsRoot));
if strlength(string(resultsRoot)) == 0
    resultsRoot = char(string(sixgr.util.structGet(cfg, "run.resultsRoot", "results")));
end
resultsRoot = localResolveResultsRoot(resultsRoot);
cfg.run.resultsRoot = resultsRoot;
opt.ResultsRoot = resultsRoot;
runFolder = fullfile(resultsRoot, "full3gpp_" + string(sixgr.util.timeStamp()));
sixgr.util.ensureDir(runFolder);
sixgr.util.ensureDir(fullfile(runFolder, "csv"));
sixgr.util.ensureDir(fullfile(runFolder, "mat"));
sixgr.util.ensureDir(fullfile(runFolder, "logs"));

logFile = fullfile(runFolder, "logs", "full_campaign.log");
L = sixgr.core.Logger(logFile, "Level", 3, "EchoToConsole", verbose);
L.info("Starting full 3GPP campaign");
L.info("Run folder: " + string(runFolder));
onlyE2E = logical(opt.OnlyE2E);
runMMTC = logical(opt.RunSystemMMTCProbe);
runAux = logical(opt.RunAuxiliaryProbes);
organizeByBlock = logical(opt.OrganizeByBlock);

% Save resolved config snapshot.
try
    sixgr.util.jsonWrite(fullfile(runFolder, "config_resolved_full_campaign.json"), cfg);
catch
end

% -------------------------------------------------------------------------
% 1) Link-level campaign (main)
% -------------------------------------------------------------------------
linkFolder = fullfile(runFolder, "link");
detailDst = fullfile(runFolder, "detailed_lls");
sysDst = fullfile(runFolder, "system");
e2eAirLUT = struct();
sysBlerLUT = struct();
if onlyE2E
    L.info("OnlyE2E=true: skipping link/system/auxiliary probes and running E2E stack only.");
    link = struct("Ok", false, "RunFolder", linkFolder, "Result", struct(), ...
        "KPITable", table(), "SNRSweep", table(), "Errors", strings(0,1), ...
        "Artifacts", struct("csv",{{}}, "mat",{{}}, "fig",{{}}, "m",{{}}));
    detailed = struct("Ok", false, "RunFolder", detailDst, "Result", struct(), ...
        "Table", table(), "Errors", strings(0,1));
    sys = struct("Ok", false, "RunFolder", sysDst, "Result", struct(), ...
        "KPITable", table(), "Errors", strings(0,1));
    mmtc = struct("Ok", false, "Result", struct(), "Table", table());
    harq = struct("Ok", false, "PacketTable", table(), "SummaryTable", table());
    syncCtrl = struct("Ok", false, "Table", table());
    v2x = struct("Ok", false, "Table", table());
    ntn = struct("Ok", false, "Table", table());
    interf = struct("Ok", false, "Table", table());
    rfp = struct("Ok", false, "Table", table());
    numProbe = struct("Ok", false, "Table", table());
    beam = struct("Ok", false, "Table", table());
else
    L.info("Running link-level campaign");
    link = localRunLinkCampaign(cfg, linkFolder, opt);
    if logical(opt.CalibrateSystemBLERFromLink)
        e2eAirLUT = localBuildDualDirectionBLERLUTFromSweep(sixgr.util.structGet(link, "SNRSweep", table()));
        sysBlerLUT = sixgr.util.structGet(e2eAirLUT, "System", struct());
    end

    % ---------------------------------------------------------------------
    % 2) Detailed link-level diagnostics
    % ---------------------------------------------------------------------
    L.info("Running detailed link-level diagnostics");
    detailed = localRunDetailedDiagnostics(cfg, detailDst, opt, link);

    % ---------------------------------------------------------------------
    % 3) System mobility campaign
    % ---------------------------------------------------------------------
    L.info("Running system mobility campaign");
    sys = localRunSystemMobilityCampaign(cfg, sysDst, opt, sysBlerLUT);

    % ---------------------------------------------------------------------
    % 4) mMTC system probe
    % ---------------------------------------------------------------------
    if runMMTC
        L.info("Running mMTC probe");
        mmtc = localRunMMTCProbe(cfg, fullfile(runFolder, "system_mmtc"), opt, sysBlerLUT);
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_mmtc_kpis.csv"), mmtc.Table);
    else
        mmtc = struct("Ok", false, "Result", struct(), "Table", table(), "Notes", "Skipped by RunSystemMMTCProbe=false");
    end

    if runAux
        % -----------------------------------------------------------------
        % 5) HARQ probe
        % -----------------------------------------------------------------
        L.info("Running HARQ probe");
        harq = localRunHARQProbe(cfg, double(opt.LinkSNR_dB), round(double(opt.HARQPackets)), round(double(opt.HARQMaxRetx)));
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_harq_packets.csv"), harq.PacketTable);
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_harq_summary.csv"), harq.SummaryTable);

        % -----------------------------------------------------------------
        % 6) Sync/control probe
        % -----------------------------------------------------------------
        L.info("Running synchronization/control probe");
        syncCtrl = localRunSyncControlProbe(cfg, double(opt.LinkSNR_dB));
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_sync_control.csv"), syncCtrl.Table);

        % -----------------------------------------------------------------
        % 7) V2X sidelink probe
        % -----------------------------------------------------------------
        L.info("Running V2X sidelink probe");
        v2x = localRunV2XProbe(cfg, opt, double(opt.LinkSNR_dB));
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_v2x_sidelink.csv"), v2x.Table);

        % -----------------------------------------------------------------
        % 8) NTN delay/doppler probe
        % -----------------------------------------------------------------
        L.info("Running NTN delay/doppler probe");
        ntn = localRunNTNProbe(cfg, opt, double(opt.LinkSNR_dB));
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_ntn_delay_doppler.csv"), ntn.Table);

        % -----------------------------------------------------------------
        % 9) Interference probe
        % -----------------------------------------------------------------
        L.info("Running interference probe");
        interf = localRunInterferenceProbe(cfg, [-10 -5 0 5 10 15], 8);
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_interference_sir_bler.csv"), interf.Table);

        % -----------------------------------------------------------------
        % 10) RF impairment + energy probe
        % -----------------------------------------------------------------
        L.info("Running RF/energy probe");
        rfp = localRunRFProbe(cfg);
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_rf_energy.csv"), rfp.Table);

        % -----------------------------------------------------------------
        % 11) Numerology probe
        % -----------------------------------------------------------------
        L.info("Running numerology probe");
        numProbe = localRunNumerologyProbe(cfg, double(opt.LinkSNR_dB), [15 30 60], 8);
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_numerology.csv"), numProbe.Table);

        % -----------------------------------------------------------------
        % 12) Beam/MIMO probe
        % -----------------------------------------------------------------
        L.info("Running beam/MIMO probe");
        beam = localRunBeamMIMOProbe(cfg, double(opt.LinkSNR_dB));
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_beam_mimo.csv"), beam.Table);
    else
        harq = struct("Ok", false, "PacketTable", table(), "SummaryTable", table(), "Notes", "Skipped by RunAuxiliaryProbes=false");
        syncCtrl = struct("Ok", false, "Table", table(), "Notes", "Skipped by RunAuxiliaryProbes=false");
        v2x = struct("Ok", false, "Table", table(), "Notes", "Skipped by RunAuxiliaryProbes=false");
        ntn = struct("Ok", false, "Table", table(), "Notes", "Skipped by RunAuxiliaryProbes=false");
        interf = struct("Ok", false, "Table", table(), "Notes", "Skipped by RunAuxiliaryProbes=false");
        rfp = struct("Ok", false, "Table", table(), "Notes", "Skipped by RunAuxiliaryProbes=false");
        numProbe = struct("Ok", false, "Table", table(), "Notes", "Skipped by RunAuxiliaryProbes=false");
        beam = struct("Ok", false, "Table", table(), "Notes", "Skipped by RunAuxiliaryProbes=false");
    end
end

% -------------------------------------------------------------------------
% 13) End-to-end stack probe (SDAP/PDCP/RLC/MAC/RRC/AI hooks)
% -------------------------------------------------------------------------
if logical(opt.RunE2EStackProbe)
    L.info("Running end-to-end stack probe");
    e2e = localRunEndToEndProbe(cfg, fullfile(runFolder, "end_to_end"), opt, e2eAirLUT);
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_e2e_slot_metrics.csv"), e2e.SlotTable);
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_e2e_component_io.csv"), e2e.ComponentIOTable);
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_e2e_component_checks.csv"), e2e.CheckTable);
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_e2e_packet_integrity.csv"), e2e.PacketIntegrityTable);
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_e2e_summary.csv"), e2e.SummaryTable);
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_e2e_ai_metrics.csv"), e2e.AITable);
else
    e2e = struct();
    e2e.Ok = false;
    e2e.RunFolder = "";
    e2e.SlotTable = table();
    e2e.ComponentIOTable = table();
    e2e.CheckTable = table();
    e2e.PacketIntegrityTable = table();
    e2e.PacketTraceTable = table();
    e2e.FlowSummaryTable = table();
    e2e.BearerSummaryTable = table();
    e2e.AttachTraceTable = table();
    e2e.HARQTraceTable = table();
    e2e.SchedulerTraceTable = table();
    e2e.DropCauseTable = table();
    e2e.SummaryTable = table();
    e2e.AITable = table();
    e2e.Notes = "Skipped by RunE2EStackProbe=false";
end

% -------------------------------------------------------------------------
% 13b) Control-plane detailed trace package
% -------------------------------------------------------------------------
controlTrace = localExportControlPlaneTraces(runFolder, link, e2e, syncCtrl);

% -------------------------------------------------------------------------
% 14) Calibration artifact package (BLER DB + metadata/coverage/validation)
% -------------------------------------------------------------------------
calibration = struct("Ok", false, "CalibrationFolder", "", "BLERDBMat", "", ...
    "MetadataJSON", "", "CoverageCSV", "", "ValidationCSV", "", ...
    "Source", "", "CoveragePct", NaN, "MissingPoints", NaN, "TotalPoints", NaN);
try
    calibPayload = localBuildCampaignCalibrationPayload(cfg, e2eAirLUT, link);
    trialCounts = localCollectCalibrationTrialCounts(runFolder);
    calibration = sixgr.hybrid.ExportCalibrationArtifacts(runFolder, calibPayload, ...
        "StrictMode", logical(sixgr.util.structGet(cfg, "run.strictMode", false)), ...
        "SourceRun", runFolder, ...
        "TrialCounts", trialCounts);
    calibration.Ok = true;
catch ME
    calibration.Ok = false;
    calibration.Notes = string(ME.message);
    L.warn("Calibration artifact export failed: " + string(ME.message));
end

% -------------------------------------------------------------------------
% 15) 25-category audit
% -------------------------------------------------------------------------
audit = localBuild25CategoryAudit(link, sys, mmtc, harq, syncCtrl, v2x, ntn, interf, rfp, numProbe, beam, e2e);
csvAudit = fullfile(runFolder, "csv", "full_3gpp_category_audit.csv");
sixgr.util.csvWriteTable(csvAudit, audit);

% Campaign report.
summary = struct();
summary.RunFolder = runFolder;
summary.LinkRunFolder = linkFolder;
summary.DetailRunFolder = detailDst;
summary.SystemRunFolder = sysDst;
summary.MMTCFolder = fullfile(runFolder, "system_mmtc");
summary.E2EFolder = fullfile(runFolder, "end_to_end");
summary.ControlTraceFolder = string(sixgr.util.structGet(controlTrace, "Folder", fullfile(runFolder, "control", "csv")));
summary.CalibrationFolder = sixgr.util.structGet(calibration, "CalibrationFolder", "");
summary.CalibrationDBMat = sixgr.util.structGet(calibration, "BLERDBMat", "");
summary.CalibrationMetadataJSON = sixgr.util.structGet(calibration, "MetadataJSON", "");
summary.CalibrationCoverageCSV = sixgr.util.structGet(calibration, "CoverageCSV", "");
summary.CalibrationValidationCSV = sixgr.util.structGet(calibration, "ValidationCSV", "");
summary.CalibrationSource = string(sixgr.util.structGet(calibration, "Source", ""));
summary.AuditCSV = csvAudit;
summary.LogFile = logFile;
summary.MetaFolder = fullfile(runFolder, "meta");
if onlyE2E
    summary.Ok = logical((~logical(opt.RunE2EStackProbe) || sixgr.util.structGet(e2e, "Ok", false)));
else
    summary.Ok = logical( ...
        sixgr.util.structGet(link, "Ok", false) && ...
        sixgr.util.structGet(detailed, "Ok", false) && ...
        sixgr.util.structGet(sys, "Ok", false) && ...
        (~runMMTC || sixgr.util.structGet(mmtc, "Ok", false)) && ...
        (~runAux || sixgr.util.structGet(harq, "Ok", false)) && ...
        (~runAux || sixgr.util.structGet(syncCtrl, "Ok", false)) && ...
        (~runAux || sixgr.util.structGet(v2x, "Ok", false)) && ...
        (~runAux || sixgr.util.structGet(ntn, "Ok", false)) && ...
        (~runAux || sixgr.util.structGet(interf, "Ok", false)) && ...
        (~runAux || sixgr.util.structGet(rfp, "Ok", false)) && ...
        (~runAux || sixgr.util.structGet(numProbe, "Ok", false)) && ...
        (~runAux || sixgr.util.structGet(beam, "Ok", false)) && ...
        (~logical(opt.RunE2EStackProbe) || sixgr.util.structGet(e2e, "Ok", false)));
end

% Build block-wise structured analysis tree for easier review.
structured = struct();
structured.Ok = false;
structured.StructuredFolder = "";
structured.ManifestCSV = "";
structured.ManifestJSON = "";
structured.NumRecords = 0;
structured.MirrorFolder = "";
if organizeByBlock
    try
        structured = sixgr.report.OrganizeRunResults(runFolder, ...
            "ResultsRoot", resultsRoot, ...
            "MirrorToResultsRoot", logical(opt.MirrorStructuredResults));
    catch ME
        L.warn("Structured organization failed: " + string(ME.message));
    end
end
summary.StructuredFolder = sixgr.util.structGet(structured, "StructuredFolder", "");
summary.StructuredMirrorFolder = sixgr.util.structGet(structured, "MirrorFolder", "");
summary.StructuredManifestCSV = sixgr.util.structGet(structured, "ManifestCSV", "");

% Generate campaign-level summary plots (root fig folder) to improve
% readability across probes and ensure consistent graph exports.
plotSummary = struct("Ok", false, "NumPlots", 0, "FigureFolder", "", "GeneratedFiles", strings(0,1));
if logical(opt.GenerateCampaignPlots)
    try
        plotSummary = localGenerateCampaignPlots(runFolder);
    catch ME
        L.warn("Campaign plot generation failed: " + string(ME.message));
    end
end
summary.CampaignPlotFolder = sixgr.util.structGet(plotSummary, "FigureFolder", "");
summary.CampaignPlotCount = double(sixgr.util.structGet(plotSummary, "NumPlots", 0));

% Verify artifact completeness (CSV/MAT/fig/log) against expected set.
% NOTE: run verification after provisional MAT/MD are written so checklist
% can include those top-level report artifacts.
artifactCheck = struct("Ok", false, "Table", table(), "CSV", "", "MD", "", "Coverage_pct", NaN, "MissingCount", NaN);
summary.ArtifactChecklistCSV = "";
summary.ArtifactChecklistMD = "";
summary.ArtifactCoverage_pct = NaN;
summary.ArtifactMissingCount = NaN;

metaRepro = localWriteReproducibilityMeta(runFolder, cfg, opt, summary, audit, calibration, artifactCheck);
summary.MetaRunManifestJSON = sixgr.util.structGet(metaRepro, "RunManifestJSON", "");
summary.MetaEnvironmentJSON = sixgr.util.structGet(metaRepro, "EnvironmentJSON", "");
summary.MetaSeedsCSV = sixgr.util.structGet(metaRepro, "SeedsCSV", "");
summary.MetaApproximationsCSV = sixgr.util.structGet(metaRepro, "ApproximationsCSV", "");
summary.MetaCalibrationSourceJSON = sixgr.util.structGet(metaRepro, "CalibrationSourceJSON", "");

matFile = fullfile(runFolder, "mat", "full_campaign_report.mat");
mdFile = fullfile(runFolder, "full_campaign_report.md");
localSaveCampaignMAT(matFile, summary, link, detailed, sys, mmtc, harq, syncCtrl, v2x, ntn, interf, rfp, numProbe, beam, e2e, calibration, audit, plotSummary, artifactCheck);
localWriteMarkdown(mdFile, summary, audit);

if logical(opt.VerifyArtifacts)
    try
        artifactCheck = localVerifyArtifacts(runFolder, logical(opt.GenerateCampaignPlots), opt);
    catch ME
        L.warn("Artifact verification failed: " + string(ME.message));
    end
    summary.ArtifactChecklistCSV = sixgr.util.structGet(artifactCheck, "CSV", "");
    summary.ArtifactChecklistMD = sixgr.util.structGet(artifactCheck, "MD", "");
    summary.ArtifactCoverage_pct = double(sixgr.util.structGet(artifactCheck, "Coverage_pct", NaN));
    summary.ArtifactMissingCount = double(sixgr.util.structGet(artifactCheck, "MissingCount", NaN));

    metaRepro = localWriteReproducibilityMeta(runFolder, cfg, opt, summary, audit, calibration, artifactCheck);
    summary.MetaRunManifestJSON = sixgr.util.structGet(metaRepro, "RunManifestJSON", "");
    summary.MetaEnvironmentJSON = sixgr.util.structGet(metaRepro, "EnvironmentJSON", "");
    summary.MetaSeedsCSV = sixgr.util.structGet(metaRepro, "SeedsCSV", "");
    summary.MetaApproximationsCSV = sixgr.util.structGet(metaRepro, "ApproximationsCSV", "");
    summary.MetaCalibrationSourceJSON = sixgr.util.structGet(metaRepro, "CalibrationSourceJSON", "");

    % Overwrite report files with finalized artifact stats.
    localWriteMarkdown(mdFile, summary, audit);
    localSaveCampaignMAT(matFile, summary, link, detailed, sys, mmtc, harq, syncCtrl, v2x, ntn, interf, rfp, numProbe, beam, e2e, calibration, audit, plotSummary, artifactCheck);
end

if logical(opt.VerifyArtifacts)
    summary.Ok = logical(summary.Ok) && logical(sixgr.util.structGet(artifactCheck, "Ok", false));
    if isnan(double(sixgr.util.structGet(summary, "ArtifactCoverage_pct", NaN))) || ...
            isnan(double(sixgr.util.structGet(summary, "ArtifactMissingCount", NaN)))
        summary.Ok = false;
    end
    % Persist final status after artifact gating so report files are consistent.
    localWriteMarkdown(mdFile, summary, audit);
    localSaveCampaignMAT(matFile, summary, link, detailed, sys, mmtc, harq, syncCtrl, v2x, ntn, interf, rfp, numProbe, beam, e2e, calibration, audit, plotSummary, artifactCheck);
end

% Refresh structured block organization after final metadata/report files are
% written so analysis_by_block captures complete campaign artifacts.
if organizeByBlock
    try
        structured = sixgr.report.OrganizeRunResults(runFolder, ...
            "ResultsRoot", resultsRoot, ...
            "MirrorToResultsRoot", logical(opt.MirrorStructuredResults));
        summary.StructuredFolder = sixgr.util.structGet(structured, "StructuredFolder", "");
        summary.StructuredMirrorFolder = sixgr.util.structGet(structured, "MirrorFolder", "");
        summary.StructuredManifestCSV = sixgr.util.structGet(structured, "ManifestCSV", "");
    catch ME
        L.warn("Structured organization refresh failed: " + string(ME.message));
    end
end

report = struct();
report.Ok = summary.Ok;
report.RunFolder = runFolder;
report.LogFile = logFile;
report.Summary = summary;
report.Audit = audit;
report.Link = link;
report.Detailed = detailed;
report.System = sys;
report.MMTC = mmtc;
report.HARQ = harq;
report.SyncControl = syncCtrl;
report.V2X = v2x;
report.NTN = ntn;
report.Interference = interf;
report.RF = rfp;
report.Numerology = numProbe;
report.Beam = beam;
report.E2E = e2e;
report.ControlTrace = controlTrace;
report.Calibration = calibration;
report.Reproducibility = metaRepro;
report.Structured = structured;
report.PlotSummary = plotSummary;
report.ArtifactCheck = artifactCheck;
report.Artifacts = struct();
report.Artifacts.csv = { ...
    fullfile(runFolder, "csv", "probe_mmtc_kpis.csv"), ...
    fullfile(runFolder, "csv", "probe_harq_packets.csv"), ...
    fullfile(runFolder, "csv", "probe_harq_summary.csv"), ...
    fullfile(runFolder, "csv", "probe_sync_control.csv"), ...
    fullfile(runFolder, "csv", "probe_v2x_sidelink.csv"), ...
    fullfile(runFolder, "csv", "probe_ntn_delay_doppler.csv"), ...
    fullfile(runFolder, "csv", "probe_interference_sir_bler.csv"), ...
    fullfile(runFolder, "csv", "probe_rf_energy.csv"), ...
    fullfile(runFolder, "csv", "probe_numerology.csv"), ...
    fullfile(runFolder, "csv", "probe_beam_mimo.csv"), ...
    fullfile(runFolder, "csv", "probe_e2e_slot_metrics.csv"), ...
    fullfile(runFolder, "csv", "probe_e2e_component_io.csv"), ...
    fullfile(runFolder, "csv", "probe_e2e_component_checks.csv"), ...
    fullfile(runFolder, "csv", "probe_e2e_packet_integrity.csv"), ...
    fullfile(runFolder, "csv", "probe_e2e_summary.csv"), ...
    fullfile(runFolder, "csv", "probe_e2e_ai_metrics.csv"), ...
    fullfile(runFolder, "end_to_end", "csv", "e2e_packet_trace.csv"), ...
    fullfile(runFolder, "end_to_end", "csv", "e2e_flow_summary.csv"), ...
    fullfile(runFolder, "end_to_end", "csv", "e2e_bearer_summary.csv"), ...
    fullfile(runFolder, "end_to_end", "csv", "e2e_attach_trace.csv"), ...
    fullfile(runFolder, "end_to_end", "csv", "e2e_harq_trace.csv"), ...
    fullfile(runFolder, "end_to_end", "csv", "e2e_scheduler_trace.csv"), ...
    fullfile(runFolder, "end_to_end", "csv", "e2e_drop_causes.csv"), ...
    fullfile(runFolder, "control", "csv", "cell_search_trials.csv"), ...
    fullfile(runFolder, "control", "csv", "pbch_recovery_trials.csv"), ...
    fullfile(runFolder, "control", "csv", "prach_trials.csv"), ...
    fullfile(runFolder, "control", "csv", "pdcch_trials.csv"), ...
    fullfile(runFolder, "control", "csv", "pucch_trials.csv"), ...
    fullfile(runFolder, "control", "csv", "attach_state_trace.csv"), ...
    fullfile(runFolder, "control", "csv", "rrc_message_trace.csv"), ...
    fullfile(runFolder, "meta", "seeds.csv"), ...
    fullfile(runFolder, "meta", "approximations_used.csv"), ...
    fullfile(runFolder, "calibration", "calibration_coverage.csv"), ...
    fullfile(runFolder, "calibration", "calibration_validation.csv"), ...
    fullfile(runFolder, "csv", "full_3gpp_artifact_checklist.csv"), ...
    csvAudit};
report.Artifacts.mat = {matFile, fullfile(runFolder, "calibration", "bler_db.mat")};
report.Artifacts.logs = {logFile, mdFile, fullfile(runFolder, "calibration", "bler_db_metadata.json"), ...
    fullfile(runFolder, "meta", "run_manifest.json"), ...
    fullfile(runFolder, "meta", "environment.json"), ...
    fullfile(runFolder, "meta", "calibration_source.json")};
report.Artifacts.structured = { ...
    sixgr.util.structGet(structured, "StructuredFolder", ""), ...
    sixgr.util.structGet(structured, "MirrorFolder", ""), ...
    sixgr.util.structGet(structured, "ManifestCSV", "")};
report.Artifacts.meta = { ...
    fullfile(runFolder, "meta", "run_manifest.json"), ...
    fullfile(runFolder, "meta", "environment.json"), ...
    fullfile(runFolder, "meta", "seeds.csv"), ...
    fullfile(runFolder, "meta", "approximations_used.csv"), ...
    fullfile(runFolder, "meta", "calibration_source.json")};

L.info("Full 3GPP campaign completed.");
L.close();
end

function localSaveCampaignMAT(matFile, summary, link, detailed, sys, mmtc, harq, syncCtrl, v2x, ntn, interf, rfp, numProbe, beam, e2e, calibration, audit, plotSummary, artifactCheck)
sixgr.util.matSave(matFile, struct( ...
    "summary", summary, ...
    "link", link, ...
    "detailed", detailed, ...
    "system", sys, ...
    "mmtc", mmtc, ...
    "harq", harq, ...
    "syncControl", syncCtrl, ...
    "v2x", v2x, ...
    "ntn", ntn, ...
    "interference", interf, ...
    "rf", rfp, ...
    "numerology", numProbe, ...
    "beam", beam, ...
    "e2e", e2e, ...
    "calibration", calibration, ...
    "audit", audit, ...
    "plotSummary", plotSummary, ...
    "artifactCheck", artifactCheck));
end

function out = localWriteReproducibilityMeta(runFolder, cfg, opt, summary, audit, calibration, artifactCheck)
metaDir = fullfile(runFolder, "meta");
sixgr.util.ensureDir(metaDir);

runManifestFile = fullfile(metaDir, "run_manifest.json");
envFile = fullfile(metaDir, "environment.json");
seedFile = fullfile(metaDir, "seeds.csv");
approxFile = fullfile(metaDir, "approximations_used.csv");
calSrcFile = fullfile(metaDir, "calibration_source.json");

cfgHash = localComputeConfigHash(cfg);
repoRoot = fileparts(mfilename("fullpath"));
[codeVersion, codeVersionDetail] = localDetectCodeVersion(repoRoot);
strictMode = logical(sixgr.util.structGet(cfg, "run.strictMode", false));

env = localBuildEnvironmentStruct(codeVersion, codeVersionDetail, repoRoot);
sixgr.util.jsonWrite(envFile, env);

seedTable = localBuildSeedTable(cfg, opt);
sixgr.util.csvWriteTable(seedFile, seedTable);

approxTable = localBuildApproximationsUsedTable(audit, runFolder, calibration);
sixgr.util.csvWriteTable(approxFile, approxTable);

calSrc = struct();
calSrc.Source = char(string(sixgr.util.structGet(calibration, "Source", "")));
calSrc.StrictMode = strictMode;
calSrc.BLERDBMat = char(string(sixgr.util.structGet(calibration, "BLERDBMat", "")));
calSrc.MetadataJSON = char(string(sixgr.util.structGet(calibration, "MetadataJSON", "")));
calSrc.CoverageCSV = char(string(sixgr.util.structGet(calibration, "CoverageCSV", "")));
calSrc.ValidationCSV = char(string(sixgr.util.structGet(calibration, "ValidationCSV", "")));
calSrc.CoveragePct = double(sixgr.util.structGet(calibration, "CoveragePct", NaN));
calSrc.MissingPoints = double(sixgr.util.structGet(calibration, "MissingPoints", NaN));
calSrc.TotalPoints = double(sixgr.util.structGet(calibration, "TotalPoints", NaN));
calSrc.GeneratedUTC = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
sixgr.util.jsonWrite(calSrcFile, calSrc);

[~, runName] = fileparts(runFolder);
manifest = struct();
manifest.SchemaVersion = "sixgr_meta_v1";
manifest.RunName = string(runName);
manifest.RunFolder = string(runFolder);
manifest.GeneratedUTC = string(char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')));
manifest.StrictMode = strictMode;
manifest.ConfigResolvedJSON = string(fullfile(runFolder, "config_resolved_full_campaign.json"));
manifest.ConfigHash = string(cfgHash);
manifest.CodeVersion = string(codeVersion);
manifest.CodeVersionDetail = string(codeVersionDetail);
manifest.VerifyArtifactsEnabled = logical(sixgr.util.structGet(opt, "VerifyArtifacts", false));
manifest.E2EAirModel = string(sixgr.util.structGet(opt, "E2EAirModel", ""));
manifest.UseMexAcceleration = logical(sixgr.util.structGet(opt, "UseMexAcceleration", false));
manifest.SummaryOk = logical(sixgr.util.structGet(summary, "Ok", false));
manifest.ArtifactCoverage_pct = double(sixgr.util.structGet(summary, "ArtifactCoverage_pct", NaN));
manifest.ArtifactMissingCount = double(sixgr.util.structGet(summary, "ArtifactMissingCount", NaN));
manifest.ArtifactChecklistCSV = string(sixgr.util.structGet(summary, "ArtifactChecklistCSV", ""));
manifest.CalibrationSource = string(sixgr.util.structGet(summary, "CalibrationSource", ""));
manifest.ApproximationsCount = height(approxTable);
manifest.SeedRows = height(seedTable);
manifest.MetaFiles = struct( ...
    "run_manifest", string(runManifestFile), ...
    "environment", string(envFile), ...
    "seeds", string(seedFile), ...
    "approximations_used", string(approxFile), ...
    "calibration_source", string(calSrcFile));
manifest.TopLevelFiles = struct( ...
    "report_md", string(fullfile(runFolder, "full_campaign_report.md")), ...
    "report_mat", string(fullfile(runFolder, "mat", "full_campaign_report.mat")), ...
    "category_audit_csv", string(fullfile(runFolder, "csv", "full_3gpp_category_audit.csv")));
manifest.CalibrationFiles = struct( ...
    "bler_db_mat", string(sixgr.util.structGet(calibration, "BLERDBMat", "")), ...
    "metadata_json", string(sixgr.util.structGet(calibration, "MetadataJSON", "")), ...
    "coverage_csv", string(sixgr.util.structGet(calibration, "CoverageCSV", "")), ...
    "validation_csv", string(sixgr.util.structGet(calibration, "ValidationCSV", "")));
if isstruct(artifactCheck) && isfield(artifactCheck, "Ok")
    manifest.ArtifactCheck = struct( ...
        "Ok", logical(sixgr.util.structGet(artifactCheck, "Ok", false)), ...
        "Coverage_pct", double(sixgr.util.structGet(artifactCheck, "Coverage_pct", NaN)), ...
        "MissingCount", double(sixgr.util.structGet(artifactCheck, "MissingCount", NaN)), ...
        "CSV", string(sixgr.util.structGet(artifactCheck, "CSV", "")), ...
        "MD", string(sixgr.util.structGet(artifactCheck, "MD", "")));
end
sixgr.util.jsonWrite(runManifestFile, manifest);

out = struct();
out.Folder = metaDir;
out.RunManifestJSON = runManifestFile;
out.EnvironmentJSON = envFile;
out.SeedsCSV = seedFile;
out.ApproximationsCSV = approxFile;
out.CalibrationSourceJSON = calSrcFile;
out.ConfigHash = string(cfgHash);
out.CodeVersion = string(codeVersion);
end

function env = localBuildEnvironmentStruct(codeVersion, codeVersionDetail, repoRoot)
host = getenv("COMPUTERNAME");
if strlength(string(host)) == 0
    host = getenv("HOSTNAME");
end
user = getenv("USERNAME");
if strlength(string(user)) == 0
    user = getenv("USER");
end
osName = getenv("OS");
if strlength(string(osName)) == 0
    osName = computer;
end
tz = "";
try
    tz = char(datetime('now','TimeZone','local').TimeZone);
catch
    tz = "";
end
javaVersion = "";
try
    javaVersion = version("-java");
catch
    javaVersion = "";
end

tb = ver;
toolboxes = repmat(struct("Name","","Version","","Release",""), 0, 1);
for i = 1:numel(tb)
    toolboxes(end+1,1) = struct( ... %#ok<AGROW>
        "Name", char(string(tb(i).Name)), ...
        "Version", char(string(tb(i).Version)), ...
        "Release", char(string(tb(i).Release)));
end

env = struct();
env.GeneratedUTC = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
env.TimeZoneLocal = char(string(tz));
env.HostName = char(string(host));
env.UserName = char(string(user));
env.OS = char(string(osName));
env.Computer = char(string(computer));
env.Arch = char(string(computer("arch")));
env.MATLAB = struct( ...
    "Version", char(string(version)), ...
    "Release", char(string(version("-release"))), ...
    "Java", char(string(javaVersion)));
env.CodeVersion = char(string(codeVersion));
env.CodeVersionDetail = char(string(codeVersionDetail));
env.RepoRoot = char(string(repoRoot));
env.Toolboxes = toolboxes;
end

function T = localBuildSeedTable(cfg, opt)
baseSeed = double(sixgr.util.structGet(cfg, "run.seed", 1));
strictMode = logical(sixgr.util.structGet(cfg, "run.strictMode", false));
useMex = logical(sixgr.util.structGet(opt, "UseMexAcceleration", false));
rows = repmat(struct("Component","","Seed",NaN,"SeedExpression","","Notes",""), 0, 1);

rows(end+1,1) = localSeedRow("global_campaign", baseSeed, "cfg.run.seed", "Master seed for campaign reproducibility.");
rows(end+1,1) = localSeedRow("link_campaign", baseSeed, "cfg.run.seed", "Link-level modules consume deterministic streams from base seed.");
rows(end+1,1) = localSeedRow("detailed_lls", baseSeed, "cfg.run.seed", "Detailed PHY diagnostics seeded from base.");
rows(end+1,1) = localSeedRow("system_campaign", baseSeed, "cfg.run.seed", "System-level runner base seed.");
rows(end+1,1) = localSeedRow("system_phy_decode", baseSeed + 31, "cfg.run.seed + 31", "PHY decoder RNG in system-level path.");
rows(end+1,1) = localSeedRow("e2e_probe", baseSeed, "cfg.run.seed", "E2E stack scheduling/queue randomness.");
rows(end+1,1) = localSeedRow("sync_control_probes", baseSeed, "cfg.run.seed", "PBCH/PRACH/PDCCH/PUCCH trial traces.");
rows(end+1,1) = localSeedRow("calibration_export", baseSeed, "cfg.run.seed", "Calibration artifact generation context.");
rows(end+1,1) = localSeedRow("mode_flags", NaN, "N/A", "strictMode=" + string(strictMode) + ", useMex=" + string(useMex));

T = struct2table(rows);
T.Component = string(T.Component);
T.SeedExpression = string(T.SeedExpression);
T.Notes = string(T.Notes);
end

function r = localSeedRow(component, seed, expr, notes)
r = struct();
r.Component = string(component);
r.Seed = double(seed);
r.SeedExpression = string(expr);
r.Notes = string(notes);
end

function T = localBuildApproximationsUsedTable(audit, runFolder, calibration)
rows = repmat(struct("Area","","Component","","ApproximationMode","","Evidence","","Notes",""), 0, 1);

if istable(audit) && ~isempty(audit) && all(ismember(["Category","Status","Evidence","Notes"], string(audit.Properties.VariableNames)))
    status = lower(string(audit.Status));
    mask = status == "approximated" | status == "not_modeled";
    idx = find(mask);
    for i = 1:numel(idx)
        k = idx(i);
        rows(end+1,1) = struct( ... %#ok<AGROW>
            "Area", string(audit.Category(k)), ...
            "Component", string(audit.Category(k)), ...
            "ApproximationMode", string(audit.Status(k)), ...
            "Evidence", string(audit.Evidence(k)), ...
            "Notes", string(audit.Notes(k)));
    end
end

e2eFile = fullfile(runFolder, "csv", "probe_e2e_summary.csv");
if exist(e2eFile, "file") == 2
    try
        E = readtable(e2eFile, "VariableNamingRule", "preserve");
        if ~isempty(E)
            backend = "";
            phyMode = "";
            airMode = "";
            airSrc = "";
            if ismember("ExecutionBackend", string(E.Properties.VariableNames)), backend = string(E.ExecutionBackend(1)); end
            if ismember("PHYMode", string(E.Properties.VariableNames)), phyMode = string(E.PHYMode(1)); end
            if ismember("E2EAirModel", string(E.Properties.VariableNames)), airMode = string(E.E2EAirModel(1)); end
            if ismember("E2EAirModelSource", string(E.Properties.VariableNames)), airSrc = string(E.E2EAirModelSource(1)); end
            if contains(upper(backend), "FAST_PROXY") || contains(upper(phyMode), "PROXY") || lower(airMode) ~= "truth"
                rows(end+1,1) = struct( ... %#ok<AGROW>
                    "Area", "E2E", ...
                    "Component", "end_to_end_radio_delivery", ...
                    "ApproximationMode", "proxy_model", ...
                    "Evidence", "csv/probe_e2e_summary.csv", ...
                    "Notes", "ExecutionBackend=" + backend + "; PHYMode=" + phyMode + "; AirModel=" + airMode + "; Source=" + airSrc);
            end
        end
    catch
    end
end

sysFile = fullfile(runFolder, "system", "csv", "system_kpis.csv");
if exist(sysFile, "file") == 2
    try
        S = readtable(sysFile, "VariableNamingRule", "preserve");
        if ~isempty(S)
            backend = "";
            phyMode = "";
            if ismember("ExecutionBackend", string(S.Properties.VariableNames)), backend = string(S.ExecutionBackend(1)); end
            if ismember("PHYMode", string(S.Properties.VariableNames)), phyMode = string(S.PHYMode(1)); end
            if contains(upper(backend), "FAST_PROXY") || contains(upper(phyMode), "PROXY")
                rows(end+1,1) = struct( ... %#ok<AGROW>
                    "Area", "System", ...
                    "Component", "system_level_phy_service", ...
                    "ApproximationMode", "proxy_model", ...
                    "Evidence", "system/csv/system_kpis.csv", ...
                    "Notes", "ExecutionBackend=" + backend + "; PHYMode=" + phyMode);
            end
        end
    catch
    end
end

calSrc = lower(string(sixgr.util.structGet(calibration, "Source", "")));
if strlength(calSrc) > 0 && (contains(calSrc, "synthetic") || contains(calSrc, "analytic") || contains(calSrc, "fallback"))
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Area", "Calibration", ...
        "Component", "bler_database", ...
        "ApproximationMode", "synthetic_adjustment", ...
        "Evidence", "calibration/bler_db_metadata.json", ...
        "Notes", "Calibration source=" + calSrc);
end

if isempty(rows)
    rows(end+1,1) = struct( ...
        "Area", "Run", ...
        "Component", "none_detected", ...
        "ApproximationMode", "none", ...
        "Evidence", "", ...
        "Notes", "No approximations flagged.");
end

T = struct2table(rows);
T.Area = string(T.Area);
T.Component = string(T.Component);
T.ApproximationMode = string(T.ApproximationMode);
T.Evidence = string(T.Evidence);
T.Notes = string(T.Notes);
end

function h = localComputeConfigHash(cfg)
txt = "";
try
    txt = jsonencode(cfg);
catch
    try
        txt = evalc("disp(cfg)");
    catch
        txt = "cfg_unavailable";
    end
end
h = localSHA256Hex(txt);
end

function [codeVersion, detail] = localDetectCodeVersion(repoRoot)
codeVersion = "unknown";
detail = "git_unavailable";
if nargin < 1 || strlength(string(repoRoot)) == 0
    repoRoot = pwd;
end
repoRoot = char(string(repoRoot));
try
    cmdHash = sprintf('git -C "%s" rev-parse --short HEAD', repoRoot);
    [s1, out1] = system(cmdHash);
    if s1 ~= 0
        return;
    end
    hash = strtrim(out1);
    cmdBranch = sprintf('git -C "%s" rev-parse --abbrev-ref HEAD', repoRoot);
    [s2, out2] = system(cmdBranch);
    if s2 == 0
        branch = strtrim(out2);
    else
        branch = "";
    end
    cmdDirty = sprintf('git -C "%s" status --porcelain --untracked-files=no', repoRoot);
    [s3, out3] = system(cmdDirty);
    dirty = (s3 == 0) && ~isempty(strtrim(out3));
    suffix = "";
    if dirty
        suffix = "+dirty";
    end
    codeVersion = "git:" + string(hash) + string(suffix);
    detail = "branch=" + string(branch) + "; hash=" + string(hash) + "; dirty=" + string(dirty);
catch
end
end

function h = localSHA256Hex(x)
txt = char(string(x));
try
    md = java.security.MessageDigest.getInstance("SHA-256");
    md.update(uint8(txt));
    d = typecast(md.digest(), "uint8");
    h = lower(reshape(dec2hex(d, 2).', 1, []));
catch
    u = uint8(txt);
    s = sum(double(u) .* double(1:numel(u)));
    h = sprintf("fallback_%08X_%d", uint32(mod(s, 2^32)), numel(u));
end
h = char(string(h));
end

function out = localRunLinkCampaign(cfg, runFolder, opt)
cfgL = cfg;
cfgL.run.mode = "link";
cfgL.run.shortRun = false;
cfgL.outputs.saveCSV = true;
cfgL.outputs.saveMAT = true;
cfgL.outputs.saveFigures = logical(opt.LinkSaveFigures);
cfgL.outputs.saveFIG = cfgL.outputs.saveFigures;
cfgL.channel.snr_dB = double(opt.LinkSNR_dB);

if logical(opt.UseFastLinkModel) && (exist("sixgr_link_fast_core_kernel_mex","file") == 3 || exist("sixgr_link_fast_core_kernel","file") == 2)
    out = localRunLinkCampaignFast(cfgL, runFolder, opt);
    return;
end

ctx = sixgr.core.SimContext(cfgL, "RunFolder", runFolder);
ctx.Logger.EchoToConsole = false;

slotDur_s = localSlotDuration(cfgL);
reqFrames = ceil(double(opt.LinkDuration_s) / max(slotDur_s, eps));
numFrames = max(8, min(round(double(opt.LinkMaxSimFrames)), reqFrames));

params = struct();
params.NumFrames = numFrames;
params.ForceLong = true;

res = sixgr.link.LinkLevelRunner.run(ctx, params);
cfgLinkUsed = cfgL;
kpi = sixgr.util.structGet(res, "KPITable", table());
if ~localLinkKPITableHealthy(kpi)
    % Fallback for unsupported/unstable channel settings in current release.
    cfgLF = localBuildDLTraceFallbackCfg(cfgL);
    try
        ctxF = sixgr.core.SimContext(cfgLF, "RunFolder", runFolder);
        ctxF.Logger.EchoToConsole = false;
        resF = sixgr.link.LinkLevelRunner.run(ctxF, params);
        kpiF = sixgr.util.structGet(resF, "KPITable", table());
        if localLinkKPITableHealthy(kpiF)
            res = resF;
            kpi = kpiF;
            cfgLinkUsed = cfgLF;
            if isfield(res, "Cases")
                fn = string(fieldnames(res.Cases));
                for iFn = 1:numel(fn)
                    c = res.Cases.(char(fn(iFn)));
                    note = string(sixgr.util.structGet(c, "Notes", ""));
                    c.Notes = "link_campaign_fallback_awgn|" + note;
                    res.Cases.(char(fn(iFn))) = c;
                end
            end
        end
    catch
    end
end

if ~isempty(kpi)
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_kpi_summary.csv"), kpi);
elseif exist(fullfile(runFolder, "csv", "link_kpis.csv"), "file")
    copyfile(fullfile(runFolder, "csv", "link_kpis.csv"), fullfile(runFolder, "csv", "lls_kpi_summary.csv"));
end

snrGrid = localReduceSweepGrid(double(opt.LinkSNRGrid_dB(:)), round(double(opt.LinkSweepMaxPoints)), double(opt.LinkSNR_dB));
sweep = localRunLinkSNRSweep(cfgLinkUsed, snrGrid, round(double(opt.LinkSweepFrames)));
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_snr_sweep.csv"), sweep);
rawTrials = localExportLinkRawTrialTables(cfgLinkUsed, runFolder, res, numFrames, double(opt.LinkSNR_dB));

out = struct();
out.Ok = logical(sixgr.util.structGet(res, "Ok", false));
out.RunFolder = runFolder;
out.Result = res;
out.KPITable = kpi;
out.SNRSweep = sweep;
out.RawTrials = rawTrials;
out.Errors = sixgr.util.structGet(res, "Errors", strings(0,1));
out.Artifacts = sixgr.util.structGet(res, "Artifacts", struct("csv",{{}}, "mat",{{}}, "fig",{{}}, "m",{{}}));
out.ConfigUsed = cfgLinkUsed;
end

function out = localRunLinkCampaignFast(cfgL, runFolder, opt)
sixgr.util.ensureDir(runFolder);
sixgr.util.ensureDir(fullfile(runFolder, "csv"));
sixgr.util.ensureDir(fullfile(runFolder, "mat"));
sixgr.util.ensureDir(fullfile(runFolder, "fig"));
sixgr.util.ensureDir(fullfile(runFolder, "logs"));

slotDur_s = localSlotDuration(cfgL);
reqFrames = ceil(double(opt.LinkDuration_s) / max(slotDur_s, eps));
numFrames = max(8, min(round(double(opt.LinkMaxSimFrames)), reqFrames));
bw_Hz = double(sixgr.util.structGet(cfgL, "channel.bandwidth_Hz", 20e6));
snrMain = double(opt.LinkSNR_dB);

[dlBer, dlBler, dlThr, ulBer, ulBler, ulThr, srsNmse, paprCP, paprDFTs, paprGain] = ...
    localRunLinkFastKernel(snrMain, numFrames, slotDur_s, bw_Hz);

cs = localFastLinkCaseStruct(true, NaN, NaN, NaN, NaN, NaN, NaN, NaN, "Skipped in fast-link MEX mode");
pr = localFastLinkCaseStruct(true, NaN, NaN, NaN, NaN, NaN, NaN, NaN, "Skipped in fast-link MEX mode");
dl = localFastLinkCaseStruct(false, dlBer, dlBler, dlThr, NaN, NaN, NaN, NaN, "Fast-link MEX abstraction");
ul = localFastLinkCaseStruct(false, ulBer, ulBler, ulThr, NaN, NaN, NaN, NaN, "Fast-link MEX abstraction");
srs = localFastLinkCaseStruct(false, NaN, NaN, NaN, NaN, NaN, NaN, srsNmse, "Fast-link MEX abstraction");
papr = localFastLinkCaseStruct(false, NaN, NaN, NaN, NaN, paprCP, paprDFTs, NaN, "Fast-link MEX abstraction");
papr.PAPR_Gain_dB = paprGain;

kpi = table( ...
    ["CellSearch_MIB_SIB1"; "PRACH_Detection"; "DL_PDSCH_Throughput"; "UL_PUSCH_Throughput"; "UL_SRS_ChannelEst"; "UL_LowPAPR"], ...
    [cs.Ok; pr.Ok; dl.Ok; ul.Ok; srs.Ok; papr.Ok], ...
    [cs.Skipped; pr.Skipped; dl.Skipped; ul.Skipped; srs.Skipped; papr.Skipped], ...
    [cs.BER; pr.BER; dl.BER; ul.BER; srs.BER; papr.BER], ...
    [cs.BLER; pr.BLER; dl.BLER; ul.BLER; srs.BLER; papr.BLER], ...
    [cs.Throughput_Mbps; pr.Throughput_Mbps; dl.Throughput_Mbps; ul.Throughput_Mbps; srs.Throughput_Mbps; papr.Throughput_Mbps], ...
    [cs.EVM_rms; pr.EVM_rms; dl.EVM_rms; ul.EVM_rms; srs.EVM_rms; papr.EVM_rms], ...
    [cs.PAPR_CP_dB; pr.PAPR_CP_dB; dl.PAPR_CP_dB; ul.PAPR_CP_dB; srs.PAPR_CP_dB; papr.PAPR_CP_dB], ...
    [cs.PAPR_DFTs_dB; pr.PAPR_DFTs_dB; dl.PAPR_DFTs_dB; ul.PAPR_DFTs_dB; srs.PAPR_DFTs_dB; papr.PAPR_DFTs_dB], ...
    [cs.PAPR_Gain_dB; pr.PAPR_Gain_dB; dl.PAPR_Gain_dB; ul.PAPR_Gain_dB; srs.PAPR_Gain_dB; papr.PAPR_Gain_dB], ...
    [cs.NMSE_dB; pr.NMSE_dB; dl.NMSE_dB; ul.NMSE_dB; srs.NMSE_dB; papr.NMSE_dB], ...
    string([cs.Notes; pr.Notes; dl.Notes; ul.Notes; srs.Notes; papr.Notes]), ...
    'VariableNames', {'Case','Ok','Skipped','BER','BLER','Throughput_Mbps','EVM_rms','PAPR_CP_dB','PAPR_DFTs_dB','PAPR_Gain_dB','NMSE_dB','Notes'});

snrGrid = localReduceSweepGrid(double(opt.LinkSNRGrid_dB(:)), round(double(opt.LinkSweepMaxPoints)), snrMain);
sweep = localRunLinkSNRSweepFast(snrGrid, round(double(opt.LinkSweepFrames)), slotDur_s, bw_Hz);

sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "link_kpis.csv"), kpi);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_kpi_summary.csv"), kpi);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_snr_sweep.csv"), sweep);
sixgr.util.matSave(fullfile(runFolder, "mat", "link_results.mat"), struct( ...
    "kpiTable", kpi, "details", struct("FastCore", true, "NumFrames", numFrames, "SNR_dB", snrMain)));

res = struct();
res.Ok = true;
res.Skipped = false;
res.Errors = strings(0,1);
res.Cases = struct( ...
    "CellSearch_MIB_SIB1", cs, ...
    "PRACH_Detection", pr, ...
    "DL_PDSCH_Throughput", dl, ...
    "UL_PUSCH_Throughput", ul, ...
    "UL_SRS_ChannelEst", srs, ...
    "UL_LowPAPR", papr);
res.KPITable = kpi;
res.Artifacts = struct("csv", {{fullfile(runFolder, "csv", "link_kpis.csv")}}, ...
    "mat", {{fullfile(runFolder, "mat", "link_results.mat")}});

out = struct();
out.Ok = true;
out.RunFolder = runFolder;
out.Result = res;
out.KPITable = kpi;
out.SNRSweep = sweep;
out.RawTrials = localExportLinkRawTrialTables(cfgL, runFolder, res, numFrames, snrMain);
out.Errors = strings(0,1);
out.Artifacts = struct("csv", {{fullfile(runFolder, "csv", "link_kpis.csv"), fullfile(runFolder, "csv", "lls_snr_sweep.csv")}}, ...
    "mat", {{fullfile(runFolder, "mat", "link_results.mat")}}, "fig", {{}}, "m", {{}});
end

function T = localRunLinkSNRSweepFast(snrGrid, nFrames, slotDur_s, bw_Hz)
[dlBer, dlBler, dlThr, ulBer, ulBler, ulThr, srsNmse] = ...
    localRunLinkFastKernel(snrGrid(:), nFrames, slotDur_s, bw_Hz);
T = table(double(snrGrid(:)), dlBer(:), dlBler(:), dlThr(:), ulBer(:), ulBler(:), ulThr(:), srsNmse(:), ...
    'VariableNames', {'SNR_dB','DL_BER','DL_BLER','DL_Throughput_Mbps', ...
                      'UL_BER','UL_BLER','UL_Throughput_Mbps','SRS_NMSE_dB'});
end

function [dlBer, dlBler, dlThr, ulBer, ulBler, ulThr, srsNmse, paprCP, paprDFTs, paprGain] = ...
    localRunLinkFastKernel(snrGrid_dB, nFrames, slotDur_s, bw_Hz)
snrGrid_dB = double(snrGrid_dB(:));
nFrames = max(1, round(double(nFrames)));
slotDur_s = double(slotDur_s);
bw_Hz = double(bw_Hz);
if exist("sixgr_link_fast_core_kernel_mex", "file") == 3
    [dlBer, dlBler, dlThr, ulBer, ulBler, ulThr, srsNmse, paprCP, paprDFTs, paprGain] = ...
        sixgr_link_fast_core_kernel_mex(snrGrid_dB, nFrames, slotDur_s, bw_Hz);
else
    [dlBer, dlBler, dlThr, ulBer, ulBler, ulThr, srsNmse, paprCP, paprDFTs, paprGain] = ...
        sixgr_link_fast_core_kernel(snrGrid_dB, nFrames, slotDur_s, bw_Hz);
end
end

function s = localFastLinkCaseStruct(skipped, ber, bler, thr, evm, paprCP, paprDFTs, nmse, notes)
s = struct();
s.Ok = true;
s.Skipped = logical(skipped);
s.BER = double(ber);
s.BLER = double(bler);
s.Throughput_Mbps = double(thr);
s.EVM_rms = double(evm);
s.PAPR_CP_dB = double(paprCP);
s.PAPR_DFTs_dB = double(paprDFTs);
s.PAPR_Gain_dB = double(paprCP) - double(paprDFTs);
s.NMSE_dB = double(nmse);
s.Notes = string(notes);
end

function tf = localLinkKPITableHealthy(kpi)
tf = false;
if ~(istable(kpi) && ~isempty(kpi))
    return;
end
if ~all(ismember(["Ok","Skipped"], string(kpi.Properties.VariableNames)))
    return;
end
ok = logical(kpi.Ok);
sk = logical(kpi.Skipped);
tf = all(ok | sk);
end

function T = localRunLinkSNRSweep(cfg, snrGrid, nFrames)
n = numel(snrGrid);
dlBer = NaN(n,1); dlBler = NaN(n,1); dlThr = NaN(n,1);
ulBer = NaN(n,1); ulBler = NaN(n,1); ulThr = NaN(n,1);
srsNmse = NaN(n,1);
nFrames = max(1, round(double(nFrames)));

for i = 1:n
    snr = snrGrid(i);
    try
        dl = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", nFrames, "SNR_dB", snr);
        if ~logical(sixgr.util.structGet(dl, "Skipped", false))
            dlBer(i) = double(sixgr.util.structGet(dl, "BER", NaN));
            dlBler(i) = double(sixgr.util.structGet(dl, "BLER", NaN));
            dlThr(i) = double(sixgr.util.structGet(dl, "Throughput_Mbps", NaN));
        end
    catch
    end
    try
        ul = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", nFrames, "SNR_dB", snr);
        if ~logical(sixgr.util.structGet(ul, "Skipped", false))
            ulBer(i) = double(sixgr.util.structGet(ul, "BER", NaN));
            ulBler(i) = double(sixgr.util.structGet(ul, "BLER", NaN));
            ulThr(i) = double(sixgr.util.structGet(ul, "Throughput_Mbps", NaN));
        end
    catch
    end
    try
        srs = sixgr.link.runSRSChannelEstimation(cfg, "SNR_dB", snr);
        if ~logical(sixgr.util.structGet(srs, "Skipped", false))
            srsNmse(i) = double(sixgr.util.structGet(srs, "NMSE_dB", NaN));
        end
    catch
    end
end

T = table(snrGrid(:), dlBer, dlBler, dlThr, ulBer, ulBler, ulThr, srsNmse, ...
    'VariableNames', {'SNR_dB','DL_BER','DL_BLER','DL_Throughput_Mbps', ...
                      'UL_BER','UL_BLER','UL_Throughput_Mbps','SRS_NMSE_dB'});
end

function out = localExportLinkRawTrialTables(cfg, runFolder, linkRes, nFrames, snr_dB)
csvDir = fullfile(runFolder, "csv");
sixgr.util.ensureDir(csvDir);

nTrials = max(8, min(128, round(double(nFrames))));

dlTrials = localGetCaseTrialTable(linkRes, "DL_PDSCH_Throughput");
if isempty(dlTrials)
    try
        dlRun = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", nTrials, "SNR_dB", snr_dB);
        dlTrials = sixgr.util.structGet(dlRun, "TrialTable", table());
    catch
        dlTrials = table();
    end
end
if localAllTrialsCrash(dlTrials)
    cfgDL = localBuildDLTraceFallbackCfg(cfg);
    try
        dlRun = sixgr.link.runDLPDSCHThroughput(cfgDL, "NumFrames", nTrials, "SNR_dB", snr_dB);
        dlTrials = sixgr.util.structGet(dlRun, "TrialTable", table());
        if istable(dlTrials) && ~isempty(dlTrials)
            if ismember("Notes", dlTrials.Properties.VariableNames)
                dlTrials.Notes = "fallback_awgn_profile|" + string(dlTrials.Notes);
            end
        end
    catch
    end
end
dlTrials = localEnsureLinkTrialTable(dlTrials, "DL", snr_dB, cfg);
fDL = fullfile(csvDir, "dl_pdsch_trials.csv");
sixgr.util.csvWriteTable(fDL, dlTrials);

ulTrials = localGetCaseTrialTable(linkRes, "UL_PUSCH_Throughput");
if isempty(ulTrials)
    try
        ulRun = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", nTrials, "SNR_dB", snr_dB);
        ulTrials = sixgr.util.structGet(ulRun, "TrialTable", table());
    catch
        ulTrials = table();
    end
end
if localAllTrialsCrash(ulTrials)
    cfgUL = localBuildULTraceFallbackCfg(cfg);
    try
        ulRun = sixgr.link.runULPUSCHThroughput(cfgUL, "NumFrames", nTrials, "SNR_dB", snr_dB);
        ulTrials = sixgr.util.structGet(ulRun, "TrialTable", table());
        if istable(ulTrials) && ~isempty(ulTrials) && ismember("Notes", ulTrials.Properties.VariableNames)
            ulTrials.Notes = "fallback_valid_tdl_profile|" + string(ulTrials.Notes);
        end
    catch
    end
end
ulTrials = localEnsureLinkTrialTable(ulTrials, "UL", snr_dB, cfg);
fUL = fullfile(csvDir, "ul_pusch_trials.csv");
sixgr.util.csvWriteTable(fUL, ulTrials);

pbchTrials = localCollectPBCHTrials(cfg, snr_dB, max(4, ceil(nTrials/4)));
fPBCH = fullfile(csvDir, "pbch_trials.csv");
sixgr.util.csvWriteTable(fPBCH, pbchTrials);

prachTrials = localCollectPRACHTrials(cfg, snr_dB, max(4, ceil(nTrials/4)));
fPRACH = fullfile(csvDir, "prach_trials.csv");
sixgr.util.csvWriteTable(fPRACH, prachTrials);

pdcchTrials = localCollectPDCCHTrials(cfg, snr_dB, max(8, ceil(nTrials/2)));
fPDCCH = fullfile(csvDir, "pdcch_trials.csv");
sixgr.util.csvWriteTable(fPDCCH, pdcchTrials);

pucchTrials = localCollectPUCCHTrials(cfg, snr_dB, max(8, ceil(nTrials/2)));
fPUCCH = fullfile(csvDir, "pucch_trials.csv");
sixgr.util.csvWriteTable(fPUCCH, pucchTrials);

srsTrials = localCollectSRSTrials(cfg, snr_dB, max(6, ceil(nTrials/3)));
fSRS = fullfile(csvDir, "srs_trials.csv");
sixgr.util.csvWriteTable(fSRS, srsTrials);

out = struct();
out.DL = fDL;
out.UL = fUL;
out.PBCH = fPBCH;
out.PRACH = fPRACH;
out.PDCCH = fPDCCH;
out.PUCCH = fPUCCH;
out.SRS = fSRS;
end

function out = localExportControlPlaneTraces(runFolder, link, e2e, syncCtrl)
controlDir = fullfile(runFolder, "control", "csv");
sixgr.util.ensureDir(controlDir);

linkCsvDir = fullfile(runFolder, "link", "csv");
pbchTrials = localReadControlTrialTable(fullfile(linkCsvDir, "pbch_trials.csv"));
prachTrials = localReadControlTrialTable(fullfile(linkCsvDir, "prach_trials.csv"));
pdcchTrials = localReadControlTrialTable(fullfile(linkCsvDir, "pdcch_trials.csv"));
pucchTrials = localReadControlTrialTable(fullfile(linkCsvDir, "pucch_trials.csv"));

if isempty(pucchTrials)
    if builtin("isstruct", link) && isscalar(link)
        raw = sixgr.util.structGet(link, "RawTrials", struct());
        if builtin("isstruct", raw) && isfield(raw, "PUCCH")
            pucchTrials = localReadControlTrialTable(char(string(raw.PUCCH)));
        end
    end
end

if isempty(pbchTrials)
    pbchTrials = localEmptyLinkTrialTable(0);
end
if isempty(prachTrials)
    prachTrials = localEmptyLinkTrialTable(0);
end
if isempty(pdcchTrials)
    pdcchTrials = localEmptyLinkTrialTable(0);
end
if isempty(pucchTrials)
    pucchTrials = localEmptyLinkTrialTable(0);
end

cellSearchTrials = pbchTrials;
pbchRecoveryTrials = pbchTrials;
if ~isempty(cellSearchTrials)
    cellSearchTrials.ControlStage = repmat("CELL_SEARCH", height(cellSearchTrials), 1);
end
if ~isempty(pbchRecoveryTrials)
    pbchRecoveryTrials.ControlStage = repmat("PBCH_RECOVERY", height(pbchRecoveryTrials), 1);
end
if ~isempty(prachTrials)
    prachTrials.ControlStage = repmat("PRACH_ACCESS", height(prachTrials), 1);
end
if ~isempty(pdcchTrials)
    pdcchTrials.ControlStage = repmat("PDCCH_CONTROL", height(pdcchTrials), 1);
end
if ~isempty(pucchTrials)
    pucchTrials.ControlStage = repmat("PUCCH_CONTROL", height(pucchTrials), 1);
end

fCell = fullfile(controlDir, "cell_search_trials.csv");
fPBCH = fullfile(controlDir, "pbch_recovery_trials.csv");
fPRACH = fullfile(controlDir, "prach_trials.csv");
fPDCCH = fullfile(controlDir, "pdcch_trials.csv");
fPUCCH = fullfile(controlDir, "pucch_trials.csv");
sixgr.util.csvWriteTable(fCell, cellSearchTrials);
sixgr.util.csvWriteTable(fPBCH, pbchRecoveryTrials);
sixgr.util.csvWriteTable(fPRACH, prachTrials);
sixgr.util.csvWriteTable(fPDCCH, pdcchTrials);
sixgr.util.csvWriteTable(fPUCCH, pucchTrials);

attachTrace = table();
if builtin("isstruct", e2e) && isscalar(e2e)
    attachTrace = sixgr.util.structGet(e2e, "AttachTraceTable", table());
end
if ~(istable(attachTrace) && ~isempty(attachTrace))
    try
        attachTrace = readtable(fullfile(runFolder, "end_to_end", "csv", "e2e_attach_trace.csv"), "VariableNamingRule", "preserve");
    catch
        attachTrace = table();
    end
end
if isempty(attachTrace)
    attachTrace = localBuildE2EAttachTraceTable(repmat(struct("Slot",NaN,"Time_s",NaN,"Direction","","Event","","Message","", ...
        "UE",NaN,"CellID",NaN,"TempCRNTI",NaN,"Success",false,"Cause",""), 0, 1));
end

attachStateTrace = localBuildAttachStateTraceTable(attachTrace);
rrcMessageTrace = localBuildRRCMessageTraceTable(attachTrace);
fAttachState = fullfile(controlDir, "attach_state_trace.csv");
fRRCMsg = fullfile(controlDir, "rrc_message_trace.csv");
sixgr.util.csvWriteTable(fAttachState, attachStateTrace);
sixgr.util.csvWriteTable(fRRCMsg, rrcMessageTrace);

if builtin("isstruct", syncCtrl) && isscalar(syncCtrl)
    syncTable = sixgr.util.structGet(syncCtrl, "Table", table());
    if istable(syncTable) && ~isempty(syncTable)
        try
            sixgr.util.csvWriteTable(fullfile(controlDir, "sync_control_probe.csv"), syncTable);
        catch
        end
    end
end

out = struct();
out.Folder = controlDir;
out.CellSearchTrialsCSV = fCell;
out.PBCHRecoveryTrialsCSV = fPBCH;
out.PRACHTrialsCSV = fPRACH;
out.PDCCHTrialsCSV = fPDCCH;
out.PUCCHTrialsCSV = fPUCCH;
out.AttachStateTraceCSV = fAttachState;
out.RRCMessageTraceCSV = fRRCMsg;
end

function T = localReadControlTrialTable(filePath)
T = table();
if nargin < 1 || strlength(string(filePath)) == 0
    return;
end
if exist(char(string(filePath)), "file") ~= 2
    return;
end
try
    T = readtable(char(string(filePath)), "VariableNamingRule", "preserve");
catch
    T = table();
end
end

function T = localBuildAttachStateTraceTable(attachTrace)
if ~(istable(attachTrace) && ~isempty(attachTrace))
    T = table([], [], [], [], [], string.empty(0,1), string.empty(0,1), string.empty(0,1), false(0,1), string.empty(0,1), ...
        'VariableNames', {'Step','Slot','Time_s','UE','CellID','Direction','Event','State','Success','Cause'});
    return;
end

A = attachTrace;
n = height(A);
step = (1:n).';
state = strings(n,1);
for i = 1:n
    evt = "";
    msg = "";
    if ismember("Event", A.Properties.VariableNames)
        evt = string(A.Event(i));
    end
    if ismember("Message", A.Properties.VariableNames)
        msg = string(A.Message(i));
    end
    state(i) = localAttachEventToState(evt, msg);
end

slotCol = localNumericColumn(A, "Slot", NaN(n,1));
timeCol = localNumericColumn(A, "Time_s", NaN(n,1));
ueCol = localNumericColumn(A, "UE", NaN(n,1));
cellCol = localNumericColumn(A, "CellID", NaN(n,1));
dirCol = localStringColumn(A, "Direction", strings(n,1));
evtCol = localStringColumn(A, "Event", strings(n,1));
okCol = localLogicalColumn(A, "Success", false(n,1));
causeCol = localStringColumn(A, "Cause", strings(n,1));

T = table(step, slotCol, timeCol, ueCol, cellCol, dirCol, evtCol, state, okCol, causeCol, ...
    'VariableNames', {'Step','Slot','Time_s','UE','CellID','Direction','Event','State','Success','Cause'});
end

function T = localBuildRRCMessageTraceTable(attachTrace)
if ~(istable(attachTrace) && ~isempty(attachTrace))
    T = table([], [], [], [], [], [], string.empty(0,1), string.empty(0,1), string.empty(0,1), false(0,1), string.empty(0,1), ...
        'VariableNames', {'Step','Slot','Time_s','UE','CellID','TempCRNTI','Direction','Event','Message','Success','Cause'});
    return;
end

A = attachTrace;
n = height(A);
msgCol = localStringColumn(A, "Message", strings(n,1));
evtCol = localStringColumn(A, "Event", strings(n,1));
uMsg = upper(msgCol);
uEvt = upper(evtCol);
isMsg = strlength(msgCol) > 0 & ( ...
    startsWith(uEvt, "MSG") | ...
    startsWith(uMsg, "RRC") | ...
    ismember(uMsg, ["PRACH","RAR","PUCCH_ACKNACK"]));

if ~any(isMsg)
    T = table([], [], [], [], [], [], string.empty(0,1), string.empty(0,1), string.empty(0,1), false(0,1), string.empty(0,1), ...
        'VariableNames', {'Step','Slot','Time_s','UE','CellID','TempCRNTI','Direction','Event','Message','Success','Cause'});
    return;
end

idx = find(isMsg);
slotCol = localNumericColumn(A, "Slot", NaN(n,1));
timeCol = localNumericColumn(A, "Time_s", NaN(n,1));
ueCol = localNumericColumn(A, "UE", NaN(n,1));
cellCol = localNumericColumn(A, "CellID", NaN(n,1));
tmpRntiCol = localNumericColumn(A, "TempCRNTI", NaN(n,1));
dirCol = localStringColumn(A, "Direction", strings(n,1));
okCol = localLogicalColumn(A, "Success", false(n,1));
causeCol = localStringColumn(A, "Cause", strings(n,1));

T = table( ...
    idx(:), ...
    slotCol(idx), ...
    timeCol(idx), ...
    ueCol(idx), ...
    cellCol(idx), ...
    tmpRntiCol(idx), ...
    dirCol(idx), ...
    evtCol(idx), ...
    msgCol(idx), ...
    okCol(idx), ...
    causeCol(idx), ...
    'VariableNames', {'Step','Slot','Time_s','UE','CellID','TempCRNTI','Direction','Event','Message','Success','Cause'});
end

function state = localAttachEventToState(eventName, messageName)
uEvt = upper(strtrim(char(string(eventName))));
uMsg = upper(strtrim(char(string(messageName))));
switch uEvt
    case "ATTACH_START"
        state = "START";
    case "MSG1_TX"
        state = "PRACH_SENT";
    case "MSG2_RX"
        state = "RAR_RECEIVED";
    case "MSG2_MISS"
        state = "RAR_MISSED";
    case "MSG3_TX"
        state = "RRC_SETUP_REQUEST_SENT";
    case "MSG3_ACK_ERR"
        state = "MSG3_ACK_ERROR";
    case "MSG4_RX"
        state = "RRC_SETUP_RECEIVED";
    case "MSG4_MISS"
        state = "RRC_SETUP_MISSED";
    case "MSG5_TX"
        state = "RRC_SETUP_COMPLETE_SENT";
    case "MSG5_ACK_ERR"
        state = "MSG5_ACK_ERROR";
    case "ATTACH_RETRY"
        state = "RETRY";
    case "ATTACH_CONNECTED"
        state = "CONNECTED";
    case "ATTACH_FAILED"
        state = "FAILED";
    case "ATTACH_EXCEPTION"
        state = "EXCEPTION";
    otherwise
        if startsWith(uMsg, "RRC")
            state = "RRC_SIGNALING";
        elseif strcmp(uMsg, "PRACH")
            state = "PRACH";
        elseif strcmp(uMsg, "RAR")
            state = "RAR";
        else
            state = "UNSPECIFIED";
        end
end
state = string(state);
end

function v = localNumericColumn(T, name, fallback)
if ismember(name, T.Properties.VariableNames)
    try
        v = double(T.(name));
        return;
    catch
    end
end
v = double(fallback);
end

function v = localLogicalColumn(T, name, fallback)
if ismember(name, T.Properties.VariableNames)
    try
        v = logical(T.(name));
        return;
    catch
    end
end
v = logical(fallback);
end

function v = localStringColumn(T, name, fallback)
if ismember(name, T.Properties.VariableNames)
    try
        v = string(T.(name));
        return;
    catch
    end
end
v = string(fallback);
end

function tf = localAllTrialsCrash(T)
tf = false;
if ~(istable(T) && ~isempty(T))
    return;
end
if ismember("Crash", T.Properties.VariableNames)
    try
        tf = all(logical(T.Crash));
        return;
    catch
    end
end
if ismember("Status", T.Properties.VariableNames)
    try
        tf = all(upper(string(T.Status)) == "CRASH");
    catch
        tf = false;
    end
end
end

function cfgF = localBuildDLTraceFallbackCfg(cfg)
cfgF = cfg;
cfgF.channel.model = "AWGN";
cfgF.channel.awgnOnly = true;
cfgF.channel.doppler_Hz = 0;
cfgF.channel.dopplerHz = 0;
cfgF.phy.nTxAnt = 1;
cfgF.phy.nRxAnt = 1;
cfgF.phy.carrier.NSizeGrid = min(52, max(25, round(double(sixgr.util.structGet(cfgF, "phy.carrier.NSizeGrid", 52)))));
cfgF.phy.pdsch.numLayers = 1;
cfgF.phy.pdsch.NumLayers = 1;
cfgF.phy.pdsch.nLayers = 1;
end

function cfgF = localBuildULTraceFallbackCfg(cfg)
cfgF = cfg;
cfgF.channel.awgnOnly = false;
cfgF.channel.model = "TDL-C";
cfgF.channel.fading.enable = true;
cfgF.channel.fading.model = "TDL";
cfgF.channel.fading.profile = "TDL-C";
cfgF.channel.doppler_Hz = max(0, double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 70)))));
cfgF.channel.dopplerHz = cfgF.channel.doppler_Hz;
end

function T = localGetCaseTrialTable(linkRes, caseField)
T = table();
if ~(builtin("isstruct", linkRes) && isscalar(linkRes))
    return;
end
cases = sixgr.util.structGet(linkRes, "Cases", struct());
if ~(builtin("isstruct", cases) && isscalar(cases) && isfield(cases, char(caseField)))
    return;
end
try
    T = sixgr.util.structGet(cases.(char(caseField)), "TrialTable", table());
catch
    T = table();
end
if ~istable(T)
    T = table();
end
end

function T = localEnsureLinkTrialTable(Tin, direction, snr_dB, cfg)
vars = {'Direction','SNR_dB','Seed','Frame','Slot','MCS','PRBs','Layers','TBSize_bits', ...
    'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB', ...
    'DetectionMetric','BitErrors','BitsCompared','Status','Crash','Notes'};

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
            case {'Direction','ChannelModel','Status','Notes'}
                T.(v) = strings(height(T),1);
            case 'Crash'
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
if all(strlength(string(T.ChannelModel)) == 0)
    T.ChannelModel(:) = string(sixgr.util.structGet(cfg, "channel.model", "AWGN"));
end
uCm = upper(strtrim(string(T.ChannelModel)));
maskTDL = (uCm == "TDL");
if any(maskTDL)
    T.ChannelModel(maskTDL) = "TDL-C";
    if ismember("Notes", T.Properties.VariableNames)
        T.Notes(maskTDL) = string(T.Notes(maskTDL)) + "|normalized_channel_model=TDL-C";
    end
end
if all(~isfinite(double(T.DopplerHz)))
    T.DopplerHz(:) = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
        sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 0))));
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
end

function T = localCollectPBCHTrials(cfg, snr_dB, nTrials)
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "DL", snr_dB, 1), nTrials, 1);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "DL", snr_dB, k);
    r.Status = "FAIL";
    try
        out = sixgr.link.runCellSearch_MIB_SIB1(cfg, "NumSubframes", 10);
        ok = logical(sixgr.util.structGet(out, "Ok", false));
        r.CRCPass = double(ok);
        r.DetectionMetric = double(ok);
        if ok, r.Status = "PASS"; end
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
        ok = logical(sixgr.util.structGet(out, "Ok", false));
        r.CRCPass = double(ok);
        r.DetectionMetric = double(ok);
        if ok, r.Status = "PASS"; end
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
        [tx, ~] = sixgr.phy.dl.PDCCH_Tx(cfg, "K", 64);
        [rxWave, nVar] = localAddAwgn(tx.Waveform, snr_dB);
        [rx, ~] = sixgr.phy.dl.PDCCH_Rx(rxWave, cfg, ...
            "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), ...
            "ListLength", 16, "NoiseVar", nVar);
        [be, bt] = localBitErrors(tx.DCIBits, rx.DCIBits);
        ok = logical(sixgr.util.structGet(rx, "Ok", false)) && (be == 0);
        r.TBSize_bits = double(numel(tx.DCIBits));
        r.BitsCompared = double(bt);
        r.BitErrors = double(be);
        r.CRCPass = double(ok);
        r.DetectionMetric = 1 - (double(be) / max(double(bt), 1));
        if ok, r.Status = "PASS"; end
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

function T = localCollectPUCCHTrials(cfg, snr_dB, nTrials)
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "UL", snr_dB, 1), nTrials, 1);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "UL", snr_dB, k);
    r.Status = "FAIL";
    uci = int8(randi([0 1], 20, 1));
    try
        [tx, ~] = sixgr.phy.ul.PUCCH_Tx(cfg, uci, "Format", 2);
        [rxWave, nVar] = localAddAwgn(tx.Waveform, snr_dB);
        [rx, ~] = sixgr.phy.ul.PUCCH_Rx(rxWave, cfg, ...
            "Carrier", tx.Carrier, "PUCCH", tx.PUCCH, "Format", 2, ...
            "NumUCIBits", numel(uci), "ExpectedUCIBits", uci, "NoiseVar", nVar);
        [be, bt] = localBitErrors(uci, rx.UCIBits);
        ok = logical(sixgr.util.structGet(rx, "Ok", true)) && (be == 0);
        r.TBSize_bits = double(numel(uci));
        r.BitsCompared = double(bt);
        r.BitErrors = double(be);
        r.CRCPass = double(ok);
        r.DetectionMetric = 1 - (double(be) / max(double(bt), 1));
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
        [tx, ~] = sixgr.phy.ul.SRS_Tx(cfg);
        [rxWave, ~] = localAddAwgn(tx.Waveform, snr_dB);
        [rx, ~] = sixgr.phy.ul.SRS_Rx(rxWave, cfg, "Carrier", tx.Carrier, "SRS", tx.SRS);
        if ~isempty(rx.Hest)
            e = rx.Hest(:) - 1;
            nmse = mean(abs(e).^2) / max(mean(abs(ones(size(e))).^2), eps);
            r.NMSE_dB = 10 * log10(max(nmse, eps));
            r.DetectionMetric = -r.NMSE_dB;
            r.Status = "PASS";
        else
            r.NMSE_dB = NaN;
            r.DetectionMetric = NaN;
        end
        r.CRCPass = NaN;
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
row.TBSize_bits = NaN;
row.ChannelModel = string(sixgr.util.structGet(cfg, "channel.model", "AWGN"));
row.DopplerHz = dopp;
row.CRCPass = NaN;
row.DecoderIterations = NaN;
row.EVM_rms = NaN;
row.NMSE_dB = NaN;
row.DetectionMetric = NaN;
row.BitErrors = NaN;
row.BitsCompared = NaN;
row.Status = "NA";
row.Crash = false;
row.Notes = "";
end

function T = localEmptyLinkTrialTable(nRows)
if nargin < 1
    nRows = 0;
end
nRows = max(0, round(double(nRows)));
T = table(strings(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), ...
    NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), strings(nRows,1), NaN(nRows,1), ...
    NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), NaN(nRows,1), ...
    strings(nRows,1), false(nRows,1), strings(nRows,1), ...
    'VariableNames', {'Direction','SNR_dB','Seed','Frame','Slot','MCS','PRBs','Layers','TBSize_bits', ...
    'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB','DetectionMetric', ...
    'BitErrors','BitsCompared','Status','Crash','Notes'});
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
        pick = rem(round(linspace(1, numel(rem), need)));
        keep = unique([keep(:); pick(:)]);
    end
end
g = g(sort(keep));
end

function out = localRunDetailedDiagnostics(cfg, runFolder, opt, linkRef)
if nargin < 4
    linkRef = struct();
end

% Reuse already computed link-level results to avoid rerunning the same PHY
% cases in the detailed stage.
if logical(opt.ReuseLinkForDetailedDiagnostics) && builtin("isstruct", linkRef) && isscalar(linkRef) ...
        && logical(sixgr.util.structGet(linkRef, "Ok", false))
    sixgr.util.ensureDir(fullfile(runFolder, "csv"));
    sixgr.util.ensureDir(fullfile(runFolder, "mat"));
    sixgr.util.ensureDir(fullfile(runFolder, "fig"));
    sixgr.util.ensureDir(fullfile(runFolder, "logs"));

    T = sixgr.util.structGet(linkRef, "KPITable", table());
    res = sixgr.util.structGet(linkRef, "Result", struct());

    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "detailed_lls_summary.csv"), T);
    if ~isempty(T)
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "link_kpis.csv"), T);
    end
    sixgr.util.matSave(fullfile(runFolder, "mat", "link_results.mat"), struct("result", res, "reusedFromLink", true));
    sixgr.util.matSave(fullfile(runFolder, "mat", "detailed_lls_summary.mat"), ...
        struct("summary", T, "result", res, "reusedFromLink", true));

    out = struct();
    out.Ok = true;
    out.RunFolder = runFolder;
    out.Result = res;
    out.Table = T;
    out.Errors = strings(0,1);
    out.ReusedFromLink = true;
    return;
end

cfgD = cfg;
cfgD.run.mode = "link";
cfgD.run.shortRun = false;
cfgD.outputs.saveCSV = true;
cfgD.outputs.saveMAT = true;
cfgD.outputs.saveFigures = logical(opt.LinkSaveFigures);
cfgD.outputs.saveFIG = cfgD.outputs.saveFigures;
cfgD.channel.snr_dB = double(opt.LinkSNR_dB);

ctx = sixgr.core.SimContext(cfgD, "RunFolder", runFolder);
ctx.Logger.EchoToConsole = false;

params = struct();
params.NumFrames = max(8, round(double(opt.LinkSweepFrames)));
params.ForceLong = true;
res = sixgr.link.LinkLevelRunner.run(ctx, params);

T = sixgr.util.structGet(res, "KPITable", table());
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "detailed_lls_summary.csv"), T);
if ~isempty(T)
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "link_kpis.csv"), T);
end
sixgr.util.matSave(fullfile(runFolder, "mat", "detailed_lls_summary.mat"), struct("summary", T, "result", res, "reusedFromLink", false));

out = struct();
out.Ok = logical(sixgr.util.structGet(res, "Ok", false));
out.RunFolder = runFolder;
out.Result = res;
out.Table = T;
out.Errors = sixgr.util.structGet(res, "Errors", strings(0,1));
out.ReusedFromLink = false;
end

function out = localRunSystemMobilityCampaign(cfg, runFolder, opt, blerLUT)
if nargin < 4
    blerLUT = struct();
end
strictSLS = logical(sixgr.util.structGet(cfg, "run.strictMode", false));
numSites = max(1, round(double(sixgr.util.structGet(cfg, "scenario.layout.nSites", 1))));
numSectors = max(1, round(double(sixgr.util.structGet(cfg, "scenario.layout.nSectorsPerSite", 1))));
multiCellRequested = (numSites * numSectors) > 1;
handoverRequested = logical(sixgr.util.structGet(cfg, "system.handover.enable", false));
detailedTraceRequested = logical(sixgr.util.structGet(opt, "SystemDetailedTrace", false));
requireFullSystem = multiCellRequested || handoverRequested || detailedTraceRequested;
if logical(opt.UseMexAcceleration) && ~strictSLS && ~requireFullSystem && ...
        (exist("sixgr_system_fast_core_kernel_mex","file") == 3 || exist("sixgr_system_fast_core_kernel","file") == 2)
    out = localRunSystemMobilityCampaignFast(cfg, runFolder, opt);
    return;
end

cfgS = cfg;
cfgS.run.mode = "system";
cfgS.run.shortRun = false;
cfgS.outputs.saveCSV = true;
cfgS.outputs.saveMAT = true;
cfgS.outputs.saveFigures = logical(opt.SystemSaveFigures);
cfgS.outputs.saveFIG = cfgS.outputs.saveFigures;
cfgS.scenario.mobility.enable = true;
cfgS.scenario.mobility.model = "randomWaypoint";
cfgS.scenario.ue.nUE = round(double(opt.SystemNumUE));
cfgS.scenario.nUE = round(double(opt.SystemNumUE));

ctx = sixgr.core.SimContext(cfgS, "RunFolder", runFolder);
ctx.Logger.EchoToConsole = false;

params = struct();
params.SimDuration_s = double(opt.SystemDuration_s);
params.TTI_s = 1.0;
params.NumTTI = max(100, ceil(double(opt.SystemDuration_s)));
params.ForceLong = true;
params.DetailedTrace = logical(opt.SystemDetailedTrace);
if ~isempty(fieldnames(blerLUT))
    params.BLERLUT = blerLUT;
end

res = sixgr.system.SystemLevelRunner.run(ctx, params);

out = struct();
out.Ok = logical(sixgr.util.structGet(res, "Ok", false));
out.RunFolder = runFolder;
out.Result = res;
out.KPITable = sixgr.util.structGet(res, "KPITable", table());
out.Errors = sixgr.util.structGet(res, "Errors", strings(0,1));
end

function out = localRunSystemMobilityCampaignFast(cfg, runFolder, opt)
cfgS = cfg;
cfgS.run.mode = "system";
cfgS.run.shortRun = false;
cfgS.outputs.saveCSV = true;
cfgS.outputs.saveMAT = true;
cfgS.outputs.saveFigures = false;
cfgS.outputs.saveFIG = cfgS.outputs.saveFigures;
cfgS.scenario.mobility.enable = true;
cfgS.scenario.ue.nUE = round(double(opt.SystemNumUE));
cfgS.scenario.nUE = round(double(opt.SystemNumUE));
sixgr.util.ensureDir(runFolder);
sixgr.util.ensureDir(fullfile(runFolder, "csv"));
sixgr.util.ensureDir(fullfile(runFolder, "mat"));
sixgr.util.ensureDir(fullfile(runFolder, "fig"));
sixgr.util.ensureDir(fullfile(runFolder, "logs"));

nUE = max(1, round(double(opt.SystemNumUE)));
tti_s = 1.0;
nTTI = max(20, ceil(double(opt.SystemDuration_s) / max(tti_s, eps)));
simDur_s = nTTI * tti_s;
bw_Hz = double(sixgr.util.structGet(cfgS, "channel.bandwidth_Hz", 20e6));
qMaxBits = double(sixgr.util.structGet(cfgS, "system.queueMaxBits", 5e7));

try
    traffic = sixgr.system.TrafficFactory.generate(cfgS, nUE, nTTI, tti_s);
catch
    traffic = struct();
    traffic.OfferedBitsDL = max(0, round(6e4 + 2e4*randn(nTTI, nUE)));
    traffic.OfferedBitsUL = max(0, round(2e4 + 1e4*randn(nTTI, nUE)));
end
offeredDL = localExpandTrafficBits(sixgr.util.structGet(traffic, "OfferedBitsDL", zeros(nTTI,nUE)), nTTI, nUE, "OfferedBitsDL");
offeredUL = localExpandTrafficBits(sixgr.util.structGet(traffic, "OfferedBitsUL", zeros(nTTI,nUE)), nTTI, nUE, "OfferedBitsUL");
offeredDL = max(0, round(double(offeredDL)));
offeredUL = max(0, round(double(offeredUL)));

sinrBase = double(sixgr.util.structGet(cfgS, "channel.snr_dB", 20));
ulOff = double(sixgr.util.structGet(cfgS, "system.ulSinrOffset_dB", -1.0));
sinrDL = sinrBase + 2.0*randn(nTTI, nUE);
sinrUL = sinrDL + ulOff;

schedType = lower(char(string(sixgr.util.structGet(cfgS, "mac.scheduler.type", "rr"))));
schedMode = uint8(0);
if contains(schedType, "pf")
    schedMode = uint8(1);
end

if exist("sixgr_system_fast_core_kernel_mex","file") == 3
    [servedDL, servedUL, droppedDL, droppedUL, activeUE, schedDL, schedUL, meanQ, meanSINR] = ...
        sixgr_system_fast_core_kernel_mex(offeredDL, offeredUL, sinrDL, sinrUL, tti_s, bw_Hz, qMaxBits, schedMode);
else
    [servedDL, servedUL, droppedDL, droppedUL, activeUE, schedDL, schedUL, meanQ, meanSINR] = ...
        sixgr_system_fast_core_kernel(offeredDL, offeredUL, sinrDL, sinrUL, tti_s, bw_Hz, qMaxBits, schedMode);
end

servedTotDL = sum(servedDL);
servedTotUL = sum(servedUL);
dropTotDL = sum(droppedDL);
dropTotUL = sum(droppedUL);
offTotDL = sum(offeredDL, "all");
offTotUL = sum(offeredUL, "all");
offTot = offTotDL + offTotUL;
servedTot = servedTotDL + servedTotUL;

throughputDL = servedTotDL / max(simDur_s, eps) / 1e6;
throughputUL = servedTotUL / max(simDur_s, eps) / 1e6;
throughput = throughputDL + throughputUL;
packetLossDL = dropTotDL / max(offTotDL, 1);
packetLossUL = dropTotUL / max(offTotUL, 1);
packetLoss = (dropTotDL + dropTotUL) / max(offTot, 1);

kpi = table(throughput, throughputDL, throughputUL, packetLoss, packetLossDL, packetLossUL, ...
    NaN, NaN, mean(meanQ), mean(meanSINR), NaN, NaN, NaN, NaN, NaN, ...
    throughput*1e6/max(bw_Hz,1), throughputDL*1e6/max(bw_Hz,1), throughputUL*1e6/max(bw_Hz,1), ...
    servedTot/max(offTot,1), mean(activeUE), mean((schedDL>0)|(schedUL>0)), ...
    mean(meanQ)/max(mean(offeredDL+offeredUL,"all")/max(tti_s,eps),1)*1e3, nUE, nTTI, simDur_s, ...
    'VariableNames', {'Throughput_Mbps','ThroughputDL_Mbps','ThroughputUL_Mbps', ...
                      'PacketLoss','PacketLossDL','PacketLossUL','AvgBLER','JainFairness', ...
                      'MeanQueue_bits','MeanSINR_dB','MeanRSRP_dBm','MeanEbNo_dB', ...
                      'P05SINR_dB','P50SINR_dB','P95SINR_dB', ...
                      'SpectralEfficiency_bpsHz','SpectralEfficiencyDL_bpsHz','SpectralEfficiencyUL_bpsHz', ...
                      'Utilization','AvgActiveUE','ScheduleUtilization', ...
                      'ApproxDelay_ms','NumUE','NumTTI','SimDuration_s'});
kpi.ExecutionBackend = repmat("FAST_PROXY_KERNEL", height(kpi), 1);
kpi.PHYMode = repmat("SINR_SHANNON_LOGISTIC_PROXY", height(kpi), 1);

slot = (1:nTTI).';
ts = table(slot*tti_s, sum(offeredDL+offeredUL,2)/max(tti_s,eps)/1e6, (servedDL+servedUL)/max(tti_s,eps)/1e6, ...
    (droppedDL+droppedUL)/max(tti_s,eps)/1e6, activeUE, meanSINR, meanQ, ...
    'VariableNames', {'Time_s','Offered_Mbps','Throughput_Mbps','Dropped_Mbps','ActiveUE','MeanSINR_dB','MeanQueue_bits'});
ueSummary = table((1:nUE).', zeros(nUE,1), zeros(nUE,1), repmat("mixed",nUE,1), ...
    'VariableNames', {'UE','Throughput_Mbps','DropRatio','TrafficClass'});
algo = table(["Engine";"Scheduler";"NumTTI"], [string("MEX_FAST_CORE"); string(schedType); string(nTTI)], ...
    'VariableNames', {'Name','Value'});

fastTraces = localBuildFastSystemTraceArtifacts( ...
    nTTI, nUE, tti_s, slot, offeredDL, offeredUL, servedDL, servedUL, ...
    droppedDL, droppedUL, schedDL, schedUL, sinrDL, sinrUL, meanQ, bw_Hz);

sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "system_kpis.csv"), kpi);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "system_time_series.csv"), ts);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "system_ue_summary.csv"), ueSummary);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "system_algo_processing.csv"), algo);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "system_scheduler_grants.csv"), fastTraces.SchedulerGrants);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "system_harq_processes.csv"), fastTraces.HARQProcesses);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "system_cell_load.csv"), fastTraces.CellLoad);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "system_interference_detail.csv"), fastTraces.InterferenceDetail);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "system_handover_events.csv"), fastTraces.HandoverEvents);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "system_beam_events.csv"), fastTraces.BeamEvents);
sixgr.util.matSave(fullfile(runFolder, "mat", "system_results.mat"), struct("kpi", kpi, "details", struct("TimeSeries", ts)));

res = struct();
res.Ok = true;
res.KPITable = kpi;
res.Details = struct("TimeSeries", ts, "ScheduledUE_DL", schedDL, "ScheduledUE_UL", schedUL, ...
    "ExecutionBackend", "FAST_PROXY_KERNEL", "PHYMode", "SINR_SHANNON_LOGISTIC_PROXY", ...
    "SchedulerGrants", fastTraces.SchedulerGrants, ...
    "HARQProcesses", fastTraces.HARQProcesses, ...
    "CellLoad", fastTraces.CellLoad, ...
    "InterferenceDetail", fastTraces.InterferenceDetail, ...
    "HandoverEvents", fastTraces.HandoverEvents, ...
    "BeamEvents", fastTraces.BeamEvents);
res.Errors = strings(0,1);

out = struct();
out.Ok = true;
out.RunFolder = runFolder;
out.Result = res;
out.KPITable = kpi;
out.Errors = strings(0,1);
out.Notes = "System run used FAST_PROXY_KERNEL (queue/scheduler abstraction).";
end

function traces = localBuildFastSystemTraceArtifacts( ...
    nTTI, nUE, tti_s, slot, offeredDL, offeredUL, servedDL, servedUL, ...
    droppedDL, droppedUL, schedDL, schedUL, sinrDL, sinrUL, meanQ, bw_Hz)

time_s = (double(slot(:)) - 1) * double(tti_s);
nDL = sum(schedDL(:) > 0);
nUL = sum(schedUL(:) > 0);
nGrant = nDL + nUL;

if nGrant <= 0
    schedulerGrants = table([], [], string.empty(0,1), string.empty(0,1), [], [], [], [], [], [], [], [], [], [], [], [], [], ...
        false(0,1), [], [], [], false(0,1), [], [], [], [], [], [], [], [], [], string.empty(0,1), ...
        'VariableNames', {'TTI','Time_s','Direction','SlotDirection','CellID','UE','PRBStart','PRBCount', ...
        'SymbolStart','NumSymbols','TBSBits','CQIUsed','MCSIndex','NumLayers','TargetCodeRate', ...
        'SINR_dB','BLER','Ack','HarqID','RV','NDI','IsRetransmission','DAI','K1','K2', ...
        'SearchSpaceID','CORESETID','BWPId','HeadOfLineDelay_ms','BufferBytesBefore','BufferBytesAfter','GrantReason'});
else
    TTI = zeros(nGrant,1);
    Time_s = zeros(nGrant,1);
    Direction = strings(nGrant,1);
    SlotDirection = repmat("FDD_DLUL", nGrant, 1);
    CellID = ones(nGrant,1);
    UE = ones(nGrant,1);
    PRBStart = zeros(nGrant,1);
    PRBCount = zeros(nGrant,1);
    SymbolStart = zeros(nGrant,1);
    NumSymbols = repmat(14, nGrant, 1);
    TBSBits = zeros(nGrant,1);
    CQIUsed = zeros(nGrant,1);
    MCSIndex = zeros(nGrant,1);
    NumLayers = ones(nGrant,1);
    TargetCodeRate = repmat(0.5, nGrant, 1);
    SINR_dB = zeros(nGrant,1);
    BLER = ones(nGrant,1);
    Ack = false(nGrant,1);
    HarqID = zeros(nGrant,1);
    RV = zeros(nGrant,1);
    NDI = ones(nGrant,1);
    IsRetransmission = false(nGrant,1);
    DAI = ones(nGrant,1);
    K1 = repmat(4, nGrant, 1);
    K2 = ones(nGrant,1);
    SearchSpaceID = zeros(nGrant,1);
    CORESETID = zeros(nGrant,1);
    BWPId = zeros(nGrant,1);
    HeadOfLineDelay_ms = zeros(nGrant,1);
    BufferBytesBefore = zeros(nGrant,1);
    BufferBytesAfter = zeros(nGrant,1);
    GrantReason = repmat("fast_proxy_slot", nGrant, 1);

    idx = 0;
    for t = 1:nTTI
        if schedDL(t) > 0
            idx = idx + 1;
            TTI(idx) = t;
            Time_s(idx) = time_s(t);
            Direction(idx) = "DL";
            PRBCount(idx) = max(1, round(double(schedDL(t))));
            TBSBits(idx) = max(0, round(double(servedDL(t))));
            SINR_dB(idx) = mean(double(sinrDL(t,:)), "omitnan");
            CQIUsed(idx) = localFastSINRToCQI(SINR_dB(idx));
            MCSIndex(idx) = localFastCQIToMCS(CQIUsed(idx));
            Ack(idx) = logical(TBSBits(idx) > 0);
            BLER(idx) = double(~Ack(idx));
            HarqID(idx) = mod(t - 1, 16);
        end
        if schedUL(t) > 0
            idx = idx + 1;
            TTI(idx) = t;
            Time_s(idx) = time_s(t);
            Direction(idx) = "UL";
            PRBCount(idx) = max(1, round(double(schedUL(t))));
            TBSBits(idx) = max(0, round(double(servedUL(t))));
            SINR_dB(idx) = mean(double(sinrUL(t,:)), "omitnan");
            CQIUsed(idx) = localFastSINRToCQI(SINR_dB(idx));
            MCSIndex(idx) = localFastCQIToMCS(CQIUsed(idx));
            Ack(idx) = logical(TBSBits(idx) > 0);
            BLER(idx) = double(~Ack(idx));
            HarqID(idx) = mod(t - 1, 16);
        end
    end

    schedulerGrants = table(TTI, Time_s, Direction, SlotDirection, CellID, UE, PRBStart, PRBCount, ...
        SymbolStart, NumSymbols, TBSBits, CQIUsed, MCSIndex, NumLayers, TargetCodeRate, ...
        SINR_dB, BLER, Ack, HarqID, RV, NDI, IsRetransmission, DAI, K1, K2, ...
        SearchSpaceID, CORESETID, BWPId, HeadOfLineDelay_ms, BufferBytesBefore, BufferBytesAfter, GrantReason, ...
        'VariableNames', {'TTI','Time_s','Direction','SlotDirection','CellID','UE','PRBStart','PRBCount', ...
        'SymbolStart','NumSymbols','TBSBits','CQIUsed','MCSIndex','NumLayers','TargetCodeRate', ...
        'SINR_dB','BLER','Ack','HarqID','RV','NDI','IsRetransmission','DAI','K1','K2', ...
        'SearchSpaceID','CORESETID','BWPId','HeadOfLineDelay_ms','BufferBytesBefore','BufferBytesAfter','GrantReason'});
end

if isempty(schedulerGrants)
    harqTable = table([], [], string.empty(0,1), [], [], [], [], [], false(0,1), false(0,1), string.empty(0,1), [], [], [], [], ...
        'VariableNames', {'TTI','Time_s','Direction','CellID','UE','HarqID','RV','NDI', ...
        'IsRetransmission','Ack','Outcome','TBSBits','MCSIndex','CQIUsed','BLER'});
else
    outcome = repmat("NACK", height(schedulerGrants), 1);
    outcome(logical(schedulerGrants.Ack)) = "ACK";
    harqTable = table(schedulerGrants.TTI, schedulerGrants.Time_s, schedulerGrants.Direction, ...
        schedulerGrants.CellID, schedulerGrants.UE, schedulerGrants.HarqID, ...
        schedulerGrants.RV, schedulerGrants.NDI, schedulerGrants.IsRetransmission, ...
        schedulerGrants.Ack, outcome, schedulerGrants.TBSBits, ...
        schedulerGrants.MCSIndex, schedulerGrants.CQIUsed, schedulerGrants.BLER, ...
        'VariableNames', {'TTI','Time_s','Direction','CellID','UE','HarqID','RV','NDI', ...
        'IsRetransmission','Ack','Outcome','TBSBits','MCSIndex','CQIUsed','BLER'});
end

qDL = 0;
qUL = 0;
cellTTI = (1:nTTI).';
cellTime = time_s;
queueDLStart = zeros(nTTI,1);
queueULStart = zeros(nTTI,1);
queueDLEnd = zeros(nTTI,1);
queueULEnd = zeros(nTTI,1);
offDL = sum(double(offeredDL), 2);
offUL = sum(double(offeredUL), 2);
srvDL = double(servedDL(:));
srvUL = double(servedUL(:));
drpDL = double(droppedDL(:));
drpUL = double(droppedUL(:));
activeDL = sum(double(offeredDL) > 0, 2);
activeUL = sum(double(offeredUL) > 0, 2);
grantDL = double(schedDL(:) > 0);
grantUL = double(schedUL(:) > 0);
for t = 1:nTTI
    queueDLStart(t) = qDL;
    queueULStart(t) = qUL;
    qDL = max(qDL + offDL(t) - srvDL(t) - drpDL(t), 0);
    qUL = max(qUL + offUL(t) - srvUL(t) - drpUL(t), 0);
    queueDLEnd(t) = qDL;
    queueULEnd(t) = qUL;
end

cellLoad = table(cellTTI, cellTime, ones(nTTI,1), repmat("FDD_DLUL", nTTI, 1), ...
    activeDL, activeUL, grantDL, grantUL, offDL, offUL, ...
    queueDLStart, queueULStart, srvDL, srvUL, drpDL, drpUL, queueDLEnd, queueULEnd, ...
    'VariableNames', {'TTI','Time_s','CellID','SlotDirection','ActiveUE_DL','ActiveUE_UL', ...
    'GrantCountDL','GrantCountUL','OfferedBitsDL','OfferedBitsUL', ...
    'QueueBitsDL_Begin','QueueBitsUL_Begin','ServedBitsDL','ServedBitsUL', ...
    'DroppedBitsDL','DroppedBitsUL','QueueBitsDL_End','QueueBitsUL_End'});

intrfRows = nTTI * nUE;
intrfTTI = repelem((1:nTTI).', nUE, 1);
intrfTime = repelem(time_s, nUE, 1);
intrfUE = repmat((1:nUE).', nTTI, 1);
noise_dBm = -174 + 10*log10(max(double(bw_Hz), 1)) + 7;
interfDetail = table(intrfTTI, intrfTime, intrfUE, ones(intrfRows,1), ...
    NaN(intrfRows,1), NaN(intrfRows,1), repmat(noise_dBm, intrfRows, 1), ...
    zeros(intrfRows,1), zeros(intrfRows,1), zeros(intrfRows,1), ...
    reshape(double(sinrDL).', [], 1), reshape(double(sinrUL).', [], 1), NaN(intrfRows,1), ...
    'VariableNames', {'TTI','Time_s','UE','ServingCell','Pathloss_dB','RxPower_dBm', ...
    'Noise_dBm','InterferenceMargin_dB','SmallScaleFading_dB','InterferenceVariation_dB', ...
    'SINR_DL_dB','SINR_UL_dB','RSRP_dBm'});

hoEvents = table([], [], [], [], [], [], [], string.empty(0,1), string.empty(0,1), ...
    'VariableNames', {'UE','FromCell','ToCell','TriggerTTI','StartTTI','CompleteTTI','Interruption_ms','Status','Reason'});
beamEvents = table([], [], [], [], [], [], [], [], string.empty(0,1), ...
    'VariableNames', {'TTI','Time_s','UE','ServingCell','PrevBeamIndex','NewBeamIndex', ...
    'PrevBeamGain_dB','NewBeamGain_dB','EventType'});

traces = struct();
traces.SchedulerGrants = schedulerGrants;
traces.HARQProcesses = harqTable;
traces.CellLoad = cellLoad;
traces.InterferenceDetail = interfDetail;
traces.HandoverEvents = hoEvents;
traces.BeamEvents = beamEvents;
traces.MeanQueue = double(meanQ(:));
end

function cqi = localFastSINRToCQI(sinr_dB)
cqi = max(1, min(15, floor((double(sinr_dB) + 8) / 2)));
end

function mcs = localFastCQIToMCS(cqi)
mcs = max(0, min(27, round(double(cqi) * 1.8)));
end

function out = localRunMMTCProbe(cfg, runFolder, opt, blerLUT)
if nargin < 4
    blerLUT = struct();
end
cfgM = cfg;
cfgM.run.mode = "system";
cfgM.run.shortRun = false;
cfgM.traffic.model = "mmtc";
cfgM.outputs.saveCSV = true;
cfgM.outputs.saveMAT = true;
cfgM.outputs.saveFigures = logical(opt.MMTCSaveFigures);
cfgM.outputs.saveFIG = cfgM.outputs.saveFigures;
cfgM.scenario.mobility.enable = true;
mmtcUE = round(double(opt.MMTCNumUE));
if ~(isfinite(mmtcUE) && mmtcUE >= 1)
    mmtcUE = max(120, round(double(opt.SystemNumUE) * 1.25));
end
cfgM.scenario.ue.nUE = mmtcUE;
cfgM.scenario.nUE = mmtcUE;

ctx = sixgr.core.SimContext(cfgM, "RunFolder", runFolder);
ctx.Logger.EchoToConsole = false;

nTTI = max(100, ceil(double(opt.SystemDuration_s)));
params = struct();
params.NumTTI = nTTI;
params.TTI_s = 1.0;
params.ForceLong = true;
params.DetailedTrace = logical(opt.SystemDetailedTrace);
if ~isempty(fieldnames(blerLUT))
    params.BLERLUT = blerLUT;
end

res = sixgr.system.SystemLevelRunner.run(ctx, params);

connDensity = cfgM.scenario.ue.nUE;
accSuccess = NaN;
if isfield(res, "Details")
    okN = double(sixgr.util.structGet(res.Details, "DecodeOK", 0));
    failN = double(sixgr.util.structGet(res.Details, "DecodeFail", 0));
    accSuccess = okN / max(okN + failN, 1);
end

T = table(connDensity, accSuccess, ...
    'VariableNames', {'ConnectionDensity_DevicesPerCell','AccessSuccessProbability'});

out = struct();
out.Ok = res.Ok;
out.Result = res;
out.Table = T;
end

function out = localRunHARQProbe(cfg, snr_dB, nPackets, maxRetx)
slotDur_s = localSlotDuration(cfg);
rvSeq = double(sixgr.util.structGet(cfg, "phy.harq.rvSequence", [0 2 3 1]));
if isempty(rvSeq)
    rvSeq = [0 2 3 1];
end
ackErrProb = double(sixgr.util.structGet(cfg, "phy.harq.ackNackErrorProb", 1e-3));
ackErrProb = min(max(ackErrProb, 0), 0.5);

modes = ["NoComb"; "Chase"; "IR"];
pktCell = cell(numel(modes),1);
sumRows = repmat(struct("Mode","","HARQ_RetxProbability",NaN,"HARQ_MeanRetx",NaN, ...
    "HARQ_ResidualBLER",NaN,"HARQ_ThroughputEfficiency",NaN, ...
    "HARQ_MeanRTT_ms",NaN,"ACKNACK_ErrorRate",NaN, ...
    "SoftCombiningGain_dB",NaN), numel(modes), 1);

for iMode = 1:numel(modes)
    mode = modes(iMode);
    [pktTable, row] = localSimHARQMode(cfg, snr_dB, nPackets, maxRetx, mode, rvSeq, ackErrProb, slotDur_s);
    pktCell{iMode} = pktTable;
    sumRows(iMode) = row;
end

% Soft combining gain relative to no-comb baseline (residual BLER improvement).
baseBLER = sumRows(1).HARQ_ResidualBLER;
for iMode = 2:numel(modes)
    cur = sumRows(iMode).HARQ_ResidualBLER;
    sumRows(iMode).SoftCombiningGain_dB = 10*log10(max(baseBLER,1e-6) / max(cur,1e-6));
end
sumRows(1).SoftCombiningGain_dB = 0;

pktTableAll = vertcat(pktCell{:});
summary = struct2table(sumRows);

out = struct();
out.PacketTable = pktTableAll;
out.SummaryTable = summary;
out.Ok = true;
end

function [pktTable, row] = localSimHARQMode(cfg, snr_dB, nPackets, maxRetx, mode, rvSeq, ackErrProb, slotDur_s)
pktId = (1:nPackets).';
retx = zeros(nPackets,1);
success = false(nPackets,1);
bitErr = zeros(nPackets,1);
procMs = zeros(nPackets,1);
ackErr = zeros(nPackets,1);
modeStr = repmat(string(mode), nPackets, 1);
decoderIter = NaN(nPackets,1);

maxIter = double(sixgr.util.structGet(cfg, "phy.ldpc.maxIterations", 12));
alg = char(string(sixgr.util.structGet(cfg, "phy.ldpc.algorithm", "Normalized min-sum")));

for p = 1:nPackets
    [tx0, ~] = sixgr.phy.dl.PDSCH_Tx(cfg);
    tb = int8(tx0.TransportBlock(:));
    trBlkSize = double(tx0.TransportBlockSize);
    tcr = double(tx0.TargetCodeRate);
    [bgn,~] = localDLBgn(trBlkSize, tcr);

    llrAccum = [];
    pass = false;
    beLast = numel(tb);
    itLast = NaN;
    attempts = 0;
    ackErrCount = 0;

    t0 = tic;
    for r = 0:maxRetx
        attempts = r + 1;
        rv = localSelectHARQRV(mode, rvSeq, r);

        tx = sixgr.phy.dl.PDSCH_Tx(cfg, ...
            "Carrier", tx0.Carrier, ...
            "PDSCH", tx0.PDSCH, ...
            "TransportBlockBits", tb, ...
            "RV", rv, ...
            "TargetCodeRate", tcr);

        rxWave = localAddAwgn(tx.Waveform, snr_dB);
        [rx, ~] = sixgr.phy.dl.PDSCH_Rx(rxWave, cfg, ...
            "Carrier", tx.Carrier, ...
            "PDSCH", tx.PDSCH, ...
            "PDSCHIndices", tx.PDSCHIndices, ...
            "TransportBlockSize", trBlkSize, ...
            "TargetCodeRate", tcr, ...
            "RV", rv);

        if mode == "NoComb"
            [be, ~] = localBitErrors(tb, rx.TransportBlock);
            pass = logical(rx.Ok) && (be == 0);
            beLast = be;
            itLast = NaN;
        else
            rr = sixgr.util.structGet(rx, "RecLLR", []);
            llrAccum = localCombineRecLLR(llrAccum, rr);
            [pass, be, itMean] = localDecodeCombinedDL(llrAccum, tb, trBlkSize, tcr, bgn, maxIter, alg);
            beLast = be;
            itLast = itMean;
        end

        feedback = pass;
        if rand < ackErrProb
            feedback = ~feedback;
            ackErrCount = ackErrCount + 1;
        end

        % Sender stops on received ACK; otherwise retransmits.
        if feedback
            break;
        end
    end

    procMs(p) = 1e3 * toc(t0);
    retx(p) = attempts - 1;
    success(p) = pass;
    bitErr(p) = beLast;
    ackErr(p) = ackErrCount;
    decoderIter(p) = itLast;
end

rtt_ms = (retx + 1) * slotDur_s * 1e3;
pktTable = table(modeStr, pktId, success, retx, bitErr, rtt_ms, procMs, ackErr, decoderIter, ...
    'VariableNames', {'Mode','Packet','Success','NumRetx','BitErrMin','HARQ_RTT_ms', ...
                      'ProcessingDelay_ms','ACKNACK_Errors','DecoderIterations'});

reTxProb = mean(retx > 0);
residualBler = mean(~success);
meanRetx = mean(retx);
meanRTT = mean(rtt_ms);
% Throughput efficiency normalized by total transmission attempts.
throughputEff = sum(double(success)) / max(sum(retx + 1), 1);
ackErrRate = sum(ackErr) / max(sum(retx + 1), 1);

row = struct();
row.Mode = string(mode);
row.HARQ_RetxProbability = reTxProb;
row.HARQ_MeanRetx = meanRetx;
row.HARQ_ResidualBLER = residualBler;
row.HARQ_ThroughputEfficiency = throughputEff;
row.HARQ_MeanRTT_ms = meanRTT;
row.ACKNACK_ErrorRate = ackErrRate;
row.SoftCombiningGain_dB = NaN;
end

function rv = localSelectHARQRV(mode, rvSeq, r)
switch char(mode)
    case 'NoComb'
        rv = rvSeq(1);
    case 'Chase'
        rv = rvSeq(1);
    otherwise % IR
        rv = rvSeq(mod(r, numel(rvSeq)) + 1);
end
end

function [bgn, dlschInfo] = localDLBgn(trBlkSize, tcr)
dlschInfo = struct();
try
    dlschInfo = nrDLSCHInfo(trBlkSize, tcr);
    bgn = double(dlschInfo.BGN);
catch
    bgn = 2;
end
end

function acc = localCombineRecLLR(acc, rr)
if isempty(rr)
    return;
end
if isvector(rr)
    rr = rr(:);
end
if isempty(acc)
    acc = rr;
    return;
end
[r1,c1] = size(acc);
[r2,c2] = size(rr);
rrMin = min(r1, r2);
ccMin = min(c1, c2);
acc = acc(1:rrMin,1:ccMin) + rr(1:rrMin,1:ccMin);
end

function [ok, be, iterMean] = localDecodeCombinedDL(recLLR, txBits, trBlkSize, tcr, bgn, maxIter, alg)
ok = false;
be = numel(txBits);
iterMean = NaN;
if isempty(recLLR)
    return;
end

C = size(recLLR, 2);
decCells = cell(C,1);
itVec = NaN(C,1);
maxLen = 0;
for c = 1:C
    [d, it, ~] = sixgr.phy.phycode.ldpcDecode(recLLR(:,c), bgn, maxIter, alg);
    d = int8(d(:));
    decCells{c} = d;
    maxLen = max(maxLen, numel(d));
    if ~isempty(it)
        itVec(c) = double(it(1));
    end
end

decCbs = zeros(maxLen, C, 'int8');
for c = 1:C
    d = decCells{c};
    decCbs(1:numel(d), c) = d;
end

B = trBlkSize + 24;
tbCrcRx = sixgr.phy.tb.desegmentLDPC(decCbs, bgn, B);
[tbRx, crcOk, ~] = sixgr.phy.tb.checkCRC(tbCrcRx, '24A');
[be, ~] = localBitErrors(txBits, tbRx);
ok = logical(crcOk) && (be == 0);
iterMean = mean(itVec, "omitnan");
end

function out = localRunSyncControlProbe(cfg, snr_dB)
cfgC = cfg;
cfgC.phy.pdcch.enable = true;
cfgC.phy.pucch.enable = true;
cfgC.phy.prach.enable = true;
cfgC.phy.carrier.NSizeGrid = min(double(sixgr.util.structGet(cfgC, "phy.carrier.NSizeGrid", 51)), 51);

snrGrid = unique([snr_dB-10, snr_dB, snr_dB+10]);
nPdcch = 8;
nPucch = 8;
nSync = 4;
fs = double(sixgr.util.structGet(cfgC, "channel.sampleRate_Hz", 30.72e6));
ssbPattern = char(string(sixgr.util.structGet(cfgC, "phy.ssb.BlockPattern", "Case B")));

n = numel(snrGrid);
pbchDet = NaN(n,1);
prachDet = NaN(n,1);
pdcchBler = NaN(n,1);
pdcchBer = NaN(n,1);
pucchBler = NaN(n,1);
pucchBer = NaN(n,1);
timingOffset = NaN(n,1);
cfoErr = NaN(n,1);

for i = 1:n
    snr = snrGrid(i);
    cfgS = cfgC;
    cfgS.channel.snr_dB = snr;

    % PBCH/SSB detect probability.
    okCnt = 0;
    for k = 1:nSync
        try
            r = sixgr.link.runCellSearch_MIB_SIB1(cfgS, "NumSubframes", 10);
            okCnt = okCnt + double(logical(sixgr.util.structGet(r, "Ok", false)));
        catch
        end
    end
    pbchDet(i) = okCnt / max(nSync,1);

    % PRACH detect probability.
    okCnt = 0;
    for k = 1:nSync
        try
            r = sixgr.link.runPRACHDetection(cfgS, "SNR_dB", snr);
            okCnt = okCnt + double(logical(sixgr.util.structGet(r, "Ok", false)));
        catch
        end
    end
    prachDet(i) = okCnt / max(nSync,1);

    % PDCCH BLER/BER.
    fail = 0;
    errBits = 0;
    totBits = 0;
    for k = 1:nPdcch
        try
            [tx, ~] = sixgr.phy.dl.PDCCH_Tx(cfgS, "K", 64);
            [rxWave, nVar] = localAddAwgn(tx.Waveform, snr);
            [rx, ~] = sixgr.phy.dl.PDCCH_Rx(rxWave, cfgS, ...
                "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), ...
                "ListLength", 16, "NoiseVar", nVar);
            [be, bt] = localBitErrors(tx.DCIBits, rx.DCIBits);
            errBits = errBits + be;
            totBits = totBits + bt;
            if ~(logical(sixgr.util.structGet(rx, "Ok", false)) && be == 0)
                fail = fail + 1;
            end
        catch
            fail = fail + 1;
            errBits = errBits + 64;
            totBits = totBits + 64;
        end
    end
    pdcchBler(i) = fail / max(nPdcch,1);
    pdcchBer(i) = errBits / max(totBits,1);

    % PUCCH BLER/BER.
    fail = 0;
    errBits = 0;
    totBits = 0;
    for k = 1:nPucch
        uci = int8(randi([0 1], 20, 1));
        try
            [tx, ~] = sixgr.phy.ul.PUCCH_Tx(cfgS, uci, "Format", 2);
            [rxWave, nVar] = localAddAwgn(tx.Waveform, snr);
            [rx, ~] = sixgr.phy.ul.PUCCH_Rx(rxWave, cfgS, ...
                "Carrier", tx.Carrier, "PUCCH", tx.PUCCH, "Format", 2, ...
                "NumUCIBits", numel(uci), "ExpectedUCIBits", uci, "NoiseVar", nVar);
            [be, bt] = localBitErrors(uci, rx.UCIBits);
            errBits = errBits + be;
            totBits = totBits + bt;
            if ~(logical(sixgr.util.structGet(rx, "Ok", true)) && be == 0)
                fail = fail + 1;
            end
        catch
            fail = fail + 1;
            errBits = errBits + numel(uci);
            totBits = totBits + numel(uci);
        end
    end
    pucchBler(i) = fail / max(nPucch,1);
    pucchBer(i) = errBits / max(totBits,1);

    % Timing offset from PDSCH receiver.
    try
        [tx, ~] = sixgr.phy.dl.PDSCH_Tx(cfgS);
        [rxWave, nVar] = localAddAwgn(tx.Waveform, snr);
        [rx, ~] = sixgr.phy.dl.PDSCH_Rx(rxWave, cfgS, ...
            "Carrier", tx.Carrier, "PDSCH", tx.PDSCH, "PDSCHIndices", tx.PDSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, "NoiseVar", nVar);
        timingOffset(i) = double(sixgr.util.structGet(rx, "TimingOffset", NaN));
    catch
    end

    % CFO estimation error from sync estimator.
    cfoErrVec = NaN(nSync,1);
    for k = 1:nSync
        trueCfo = 200 + 100*k;
        try
            [ssbWave, ~, txCfg] = sixgr.phy.dl.SSB_Tx(cfgS, "NumSubframes", 5, "SSBBlockPattern", ssbPattern);
            fsUse = double(sixgr.util.structGet(txCfg, "SampleRate_Hz", fs));
            wf = localApplyFrequencyOffset(ssbWave, trueCfo, fsUse);
            [wf, ~] = localAddAwgn(wf, snr);
            [~, estCfo, ~, ~] = sixgr.phy.sync.freqOffsetCorrect(wf, ssbPattern, fsUse);
            cfoErrVec(k) = abs(estCfo - trueCfo);
        catch
            cfoErrVec(k) = NaN;
        end
    end
    cfoErr(i) = mean(cfoErrVec, "omitnan");
end

T = table(snrGrid(:), pbchDet, prachDet, pdcchBler, pdcchBer, pucchBler, pucchBer, timingOffset, cfoErr, ...
    'VariableNames', {'SNR_dB','PBCH_DetectProb','PRACH_DetectProb','PDCCH_BLER','PDCCH_BER', ...
                      'PUCCH_BLER','PUCCH_BER','TimingOffset_samples','CFO_EstError_Hz'});
out = struct("Ok", true, "Table", T);
end

function out = localRunInterferenceProbe(cfg, sirGrid_dB, nFramesPerPoint)
n = numel(sirGrid_dB);
bler = NaN(n,1);
for i = 1:n
    sir = sirGrid_dB(i);
    fail = 0;
    for k = 1:nFramesPerPoint
        [tx, ~] = sixgr.phy.dl.PDSCH_Tx(cfg);
        sigPow = mean(abs(tx.Waveform(:)).^2);
        intPow = sigPow / max(10^(sir/10), eps);
        interf = sqrt(intPow/2) * (randn(size(tx.Waveform)) + 1i*randn(size(tx.Waveform)));
        rxWave = tx.Waveform + interf;
        [rx, ~] = sixgr.phy.dl.PDSCH_Rx(rxWave, cfg, ...
            "Carrier", tx.Carrier, "PDSCH", tx.PDSCH, "PDSCHIndices", tx.PDSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, "TargetCodeRate", tx.TargetCodeRate, "RV", tx.RV);
        if ~rx.Ok
            fail = fail + 1;
        end
    end
    bler(i) = fail / max(nFramesPerPoint,1);
end
T = table(sirGrid_dB(:), bler, ...
    'VariableNames', {'SIR_dB','BLER'});
out = struct("Ok", true, "Table", T);
end

function out = localRunRFProbe(cfg)
cfgR = cfg;
cfgR.rf.enable = true;
cfgR.rf.iqImbalance.enable = true;
cfgR.rf.iqImbalance.gainImbalance_dB = 1.0;
cfgR.rf.iqImbalance.phaseImbalance_deg = 3.0;
cfgR.rf.phaseNoise.enable = true;
cfgR.rf.phaseNoise.level_dBcHz = -80;
cfgR.rf.cfo_Hz = 150;
cfgR.rf.dcOffset = 0.01 + 0.01i;

[tx, ~] = sixgr.phy.dl.PDSCH_Tx(cfgR);
fs = double(sixgr.util.structGet(cfgR, "channel.sampleRate_Hz", 30.72e6));
rf = sixgr.rf.RFImpairments(cfgR, fs, 3);
y = rf.applyTx(tx.Waveform);

evmRF = sqrt(mean(abs(y(:) - tx.Waveform(:)).^2) / max(mean(abs(tx.Waveform(:)).^2), eps));
paprTx = localPapr(tx.Waveform);
paprRF = localPapr(y);

bs = sixgr.rf.EnergyModelBS(cfgR);
ue = sixgr.rf.EnergyModelUE(cfgR);
pBS = bs.power('active', 1, 0.5, 10);
pUE = ue.power('tx', 0.2);

T = table(evmRF, paprTx, paprRF, pBS.totalW, pUE.totalW, ...
    'VariableNames', {'RF_Impairment_EVM','PAPR_Tx_dB','PAPR_WithRF_dB','BS_Power_W','UE_Power_W'});
out = struct("Ok", true, "Table", T);
end

function out = localRunNumerologyProbe(cfg, snr_dB, scsList_kHz, nFrames)
n = numel(scsList_kHz);
ber = NaN(n,1); bler = NaN(n,1); thr = NaN(n,1);
for i = 1:n
    c = cfg;
    c.phy.carrier.SubcarrierSpacing = scsList_kHz(i);
    c.channel.subcarrierSpacing_kHz = scsList_kHz(i);
    r = sixgr.link.runDLPDSCHThroughput(c, "NumFrames", nFrames, "SNR_dB", snr_dB);
    ber(i) = double(sixgr.util.structGet(r, "BER", NaN));
    bler(i) = double(sixgr.util.structGet(r, "BLER", NaN));
    thr(i) = double(sixgr.util.structGet(r, "Throughput_Mbps", NaN));
end
T = table(scsList_kHz(:), ber, bler, thr, ...
    'VariableNames', {'SCS_kHz','DL_BER','DL_BLER','DL_Throughput_Mbps'});
out = struct("Ok", true, "Table", T);
end

function out = localRunBeamMIMOProbe(cfg, snr_dB)
arr = sixgr.rf.AntennaArrayFactory.build(cfg, 'bs');
W = sixgr.rf.BeamRefinementCSIRS.makeCodebookFromArray(arr);
nt = size(W,1);
h = (randn(1,nt)+1i*randn(1,nt))/sqrt(2);
[~, idxBest, metric] = sixgr.rf.BeamRefinementCSIRS.selectBestBeam(h, W);
bestGain = metric(idxBest);
meanGain = mean(metric);

nRx = max(1, round(double(sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", 2))));
nTx = max(1, round(double(sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", 8))));
nRx = min(nRx, 8); nTx = min(nTx, 16);
H = (randn(nRx,nTx)+1i*randn(nRx,nTx))/sqrt(2);
s = svd(H);
condNum = max(s)/max(min(s), 1e-9);
rho = 10^(snr_dB/10);
cap = real(log2(det(eye(nRx) + (rho/nTx)*(H*H'))));

T = table(cap, condNum, double(bestGain), double(meanGain), ...
    'VariableNames', {'MIMO_Capacity_bpsHz','ChannelConditionNumber', ...
                      'BestBeamMetric','MeanBeamMetric'});
out = struct("Ok", true, "Table", T);
end

function out = localRunV2XProbe(cfg, opt, snr_dB)
cfgV = cfg;
cfgV.phy.pusch.enable = true;
cfgV.phy.pusch.modulation = "QPSK";
cfgV.phy.pusch.numLayers = 1;
cfgV.phy.pusch.codeRate = 0.35;
cfgV.phy.pusch.transformPrecoding = true;

velGrid = double(opt.V2XVelocities_kmh(:));
nVel = numel(velGrid);
nPkt = round(double(opt.V2XPackets));

fc = double(sixgr.util.structGet(cfg, "channel.fc_Hz", 3.5e9));
c0 = 299792458;
slotDur_s = localSlotDuration(cfgV);
fs = double(sixgr.util.structGet(cfgV, "channel.sampleRate_Hz", 30.72e6));

prr = NaN(nVel,1);
prrNoComp = NaN(nVel,1);
ipg_s = NaN(nVel,1);
lat_ms = NaN(nVel,1);
dopHz = NaN(nVel,1);
velErr = NaN(nVel,1);
sidelinkBler = NaN(nVel,1);
dopEstErr = NaN(nVel,1);

for i = 1:nVel
    v_kmh = velGrid(i);
    v_mps = v_kmh / 3.6;
    doppler = (v_mps/c0) * fc;
    dopHz(i) = doppler;

    interval_s = 0.1; % CAM-like periodic packeting
    rxTimes = NaN(nPkt,1);
    succ = false(nPkt,1);
    succNoComp = false(nPkt,1);
    perPktLatency = NaN(nPkt,1);
    perPktVelErr = NaN(nPkt,1);
    perPktDopErr = NaN(nPkt,1);

    for p = 1:nPkt
        tAbs = (p-1) * interval_s;
        [tx, ~] = sixgr.phy.ul.PUSCH_Tx(cfgV);
        wf = localApplyFrequencyOffset(tx.Waveform, doppler, fs);
        [wf, nVar] = localAddAwgn(wf, snr_dB);

        % Baseline decode without Doppler compensation.
        rx0 = sixgr.phy.ul.PUSCH_Rx(wf, cfgV, ...
            "Carrier", tx.Carrier, "PUSCH", tx.PUSCH, "PUSCHIndices", tx.PUSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, "NoiseVar", nVar);
        [be0, ~] = localBitErrors(tx.TransportBlock, rx0.TransportBlock);
        succNoComp(p) = logical(rx0.Ok) && (be0 == 0);

        % Doppler estimate/compensation (sidelink receiver tracking proxy).
        estErrStd = max(5.0, 0.08*abs(doppler)) / max(sqrt(10^(snr_dB/10)), 1);
        dopEst = doppler + estErrStd*randn();
        perPktDopErr(p) = abs(dopEst - doppler);
        wfComp = localApplyFrequencyOffset(wf, -dopEst, fs);

        [rx, ~] = sixgr.phy.ul.PUSCH_Rx(wfComp, cfgV, ...
            "Carrier", tx.Carrier, "PUSCH", tx.PUSCH, "PUSCHIndices", tx.PUSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, "NoiseVar", nVar);
        [be, ~] = localBitErrors(tx.TransportBlock, rx.TransportBlock);
        ok = logical(rx.Ok) && (be == 0);
        succ(p) = ok;
        if ok
            rxTimes(p) = tAbs + slotDur_s;
        end
        perPktLatency(p) = 1e3 * slotDur_s;

        % Relative velocity estimation proxy from Doppler with noise.
        vEst = abs(dopEst) * c0 / max(fc, eps) * 3.6;
        perPktVelErr(p) = abs(vEst - v_kmh);
    end

    prr(i) = mean(succ);
    prrNoComp(i) = mean(succNoComp);
    sidelinkBler(i) = 1 - prr(i);
    rt = rxTimes(isfinite(rxTimes));
    if numel(rt) >= 2
        ipg_s(i) = mean(diff(rt));
    else
        ipg_s(i) = NaN;
    end
    lat_ms(i) = mean(perPktLatency, "omitnan");
    velErr(i) = mean(perPktVelErr, "omitnan");
    dopEstErr(i) = mean(perPktDopErr, "omitnan");
end

T = table(velGrid, dopHz, prrNoComp, prr, sidelinkBler, ipg_s, lat_ms, velErr, dopEstErr, ...
    'VariableNames', {'Velocity_kmh','Doppler_Hz','PacketReceptionRatio', ...
                      'PacketReceptionRatio_WithComp','Sidelink_BLER','InterPacketGap_s','Latency_ms', ...
                      'RelVelocityEstError_kmh','DopplerEstError_Hz'});
T.Properties.VariableNames{3} = 'PacketReceptionRatio_NoComp';
out = struct("Ok", true, "Table", T);
end

function out = localRunNTNProbe(cfg, opt, snr_dB)
cfgN = cfg;
cfgN.phy.pdsch.enable = true;
cfgN.phy.pdsch.modulation = "QPSK";
cfgN.phy.pdsch.numLayers = 1;
cfgN.phy.pdsch.codeRate = 0.4;

delays_ms = double(opt.NTNDelays_ms(:));
dops_Hz = double(opt.NTNDoppler_Hz(:));
nFrames = round(double(opt.NTNFrames));
if isempty(delays_ms), delays_ms = 20; end
if isempty(dops_Hz), dops_Hz = 800; end
nCases = max(numel(delays_ms), numel(dops_Hz));

fs = double(sixgr.util.structGet(cfg, "channel.sampleRate_Hz", 30.72e6));
blerNo = NaN(nCases,1);
blerComp = NaN(nCases,1);
taSamples = NaN(nCases,1);
taEstSamples = NaN(nCases,1);
capDelaySamples = NaN(nCases,1);
resDopp = NaN(nCases,1);
resDelay = NaN(nCases,1);

for i = 1:nCases
    dms = delays_ms(min(i, numel(delays_ms)));
    dop = dops_Hz(min(i, numel(dops_Hz)));
    ta = round(dms * 1e-3 * fs);
    taSamples(i) = ta;
    capN = min(ta, 4096); % prevent oversized waveforms in campaign runtime
    capDelaySamples(i) = capN;

    failNo = 0;
    failYes = 0;
    dopErrAcc = NaN(nFrames,1);
    delayErrAcc = NaN(nFrames,1);
    taEstAcc = NaN(nFrames,1);
    for k = 1:nFrames
        [tx, ~] = sixgr.phy.dl.PDSCH_Tx(cfgN);

        wf = tx.Waveform;
        if capN > 0
            wf = [zeros(capN, size(wf,2)); wf];
        end
        wf = localApplyFrequencyOffset(wf, dop, fs);
        [wf, nVar] = localAddAwgn(wf, snr_dB);

        % No compensation
        rxNo = localTryPDSCHDecode(wf, cfgN, tx, nVar);
        failNo = failNo + double(~rxNo);

        % Delay+Doppler compensation with imperfect estimates.
        dopErrStd = max(10.0, 0.08*abs(dop)) / max(sqrt(10^(snr_dB/10)), 1);
        dopEst = dop + dopErrStd*randn();
        taErrStd = max(1.0, 0.02*max(capN,1));
        taEst = round(capN + taErrStd*randn());
        taEst = min(max(taEst, 0), max(size(wf,1)-1, 0));

        dopErrAcc(k) = abs(dop - dopEst);
        delayErrAcc(k) = abs(capN - taEst);
        taEstAcc(k) = taEst;

        wfComp = wf;
        wfComp = localApplyFrequencyOffset(wfComp, -dopEst, fs);
        if taEst > 0 && (taEst+1) <= size(wfComp,1)
            wfComp = wfComp((taEst+1):end, :);
        end
        rxComp = localTryPDSCHDecode(wfComp, cfgN, tx, nVar);
        % Receiver can select the better hypothesis (with/without compensation).
        rxYes = rxNo || rxComp;
        failYes = failYes + double(~rxYes);
    end

    blerNo(i) = failNo / max(nFrames,1);
    blerComp(i) = failYes / max(nFrames,1);
    resDopp(i) = mean(dopErrAcc, "omitnan");
    resDelay(i) = mean(delayErrAcc, "omitnan");
    taEstSamples(i) = mean(taEstAcc, "omitnan");
end

delayCase = delays_ms(min((1:nCases).', numel(delays_ms)));
doppCase = dops_Hz(min((1:nCases).', numel(dops_Hz)));
gain = blerNo - blerComp;

T = table(delayCase, doppCase, taSamples, taEstSamples, capDelaySamples, blerNo, blerComp, gain, resDelay, resDopp, ...
    'VariableNames', {'PropagationDelay_ms','Doppler_Hz','TimingAdvance_samples', ...
                      'TimingAdvanceEst_samples','AppliedDelay_samples','BLER_NoComp','BLER_WithComp', ...
                      'CompensationGain','ResidualDelay_samples','ResidualDoppler_Hz'});
out = struct("Ok", true, "Table", T);
end

function ok = localTryPDSCHDecode(rxWave, cfg, tx, noiseVar)
ok = false;
try
    [rx, ~] = sixgr.phy.dl.PDSCH_Rx(rxWave, cfg, ...
        "Carrier", tx.Carrier, "PDSCH", tx.PDSCH, "PDSCHIndices", tx.PDSCHIndices, ...
        "TransportBlockSize", tx.TransportBlockSize, "TargetCodeRate", tx.TargetCodeRate, ...
        "RV", tx.RV, "NoiseVar", noiseVar);
    [be, ~] = localBitErrors(tx.TransportBlock, rx.TransportBlock);
    ok = logical(rx.Ok) && (be == 0);
catch
    ok = false;
end
end

function out = localRunEndToEndProbe(cfg, runFolder, opt, e2eAirLUT)
if nargin < 4
    e2eAirLUT = struct();
end
strictValidation = logical(opt.E2EStrictValidation);
airModeReq = lower(char(string(sixgr.util.structGet(opt, "E2EAirModel", "lut"))));
if logical(opt.UseMexAcceleration) && ~strictValidation && ~strcmp(airModeReq, "truth") && ...
        (exist("sixgr_e2e_fast_core_kernel_mex","file") == 3 || exist("sixgr_e2e_fast_core_kernel","file") == 2)
    out = localRunEndToEndProbeFast(cfg, runFolder, opt, e2eAirLUT);
    return;
end

sixgr.util.ensureDir(runFolder);
sixgr.util.ensureDir(fullfile(runFolder, "csv"));
sixgr.util.ensureDir(fullfile(runFolder, "mat"));
sixgr.util.ensureDir(fullfile(runFolder, "fig"));
sixgr.util.ensureDir(fullfile(runFolder, "logs"));

slotDurBase_s = localSlotDuration(cfg);
nSlotsRaw = max(20, ceil(double(opt.E2EDuration_s) / max(slotDurBase_s, eps)));
maxSlots = max(0, round(double(opt.E2EMaxSlots)));
if strictValidation && maxSlots <= 0
    % Keep strict runs tractable while preserving timing semantics.
    maxSlots = min(nSlotsRaw, 6000);
end
compression = 1;
if maxSlots > 0 && nSlotsRaw > maxSlots
    compression = ceil(nSlotsRaw / maxSlots);
end
slotDur_s = slotDurBase_s * compression;
nSlots = max(20, ceil(nSlotsRaw / compression));
serviceScale = 1;
if logical(opt.E2EScaleServiceWithCompression)
    scaleCap = max(1, round(double(opt.E2EServiceScaleCap)));
    serviceScale = min(max(1, compression), scaleCap);
end
if strictValidation
    compression = 1;
    slotDur_s = slotDurBase_s;
    nSlots = nSlotsRaw;
    serviceScale = 1;
end
if strcmp(airModeReq, "truth")
    truthMaxSlots = max(20, round(double(sixgr.util.structGet(opt, "E2ETruthMaxSlots", 240))));
    if nSlots > truthMaxSlots
        if strictValidation
            error("sixgr:e2e:TruthMaxSlotsExceeded", ...
                "Truth PHY replay requires %d slots, exceeding E2ETruthMaxSlots=%d. Reduce E2EDuration_s or raise E2ETruthMaxSlots intentionally.", ...
                nSlots, truthMaxSlots);
        end
        nSlots = truthMaxSlots;
    end
end
semanticSlotDur_s = slotDurBase_s;
nUE = max(1, round(double(opt.E2EUECount)));
snr_dB = double(opt.LinkSNR_dB);
ulSnrOffset_dB = double(sixgr.util.structGet(cfg, "system.ulSinrOffset_dB", -1.0));
trafficModel = lower(char(string(opt.E2ETrafficModel)));
if strlength(string(trafficModel)) == 0
    trafficModel = "xr";
end

cfgE = cfg;
cfgE.scenario.ue.nUE = nUE;
cfgE.scenario.nUE = nUE;
cfgE.traffic.model = trafficModel;
cfgE.run.shortRun = false;
cfgE.run.strictMode = strictValidation;
cfgE.run.useMex = logical(sixgr.util.structGet(cfgE, "run.useMex", false)) || logical(opt.UseMexAcceleration);
cfgE.phy.ldpc.useMexBatchDecode = logical(sixgr.util.structGet(cfgE, "phy.ldpc.useMexBatchDecode", false)) || logical(opt.UseMexAcceleration);
cfgE.phy.rx.useFastChannelEstMex = logical(sixgr.util.structGet(cfgE, "phy.rx.useFastChannelEstMex", false)) || logical(opt.UseMexAcceleration);
if strictValidation
    % Validation mode: exercise broader control/sounding chains with fading.
    cfgE.channel.awgnOnly = false;
    cfgE.channel.dopplerHz = max(double(sixgr.util.structGet(cfgE, "channel.dopplerHz", 0)), 50);
    cfgE.channel.rayTracing.enable = logical(sixgr.util.structGet(cfgE, "channel.rayTracing.enable", false));
    cfgE.phy.ssb.Enable = true;
    cfgE.phy.ul.prach.Enable = true;
    cfgE.phy.dl.pdcch.Enable = true;
    cfgE.phy.ul.pucch.Enable = true;
    cfgE.phy.ul.srs.Enable = true;
end
duplexMode = upper(string(sixgr.util.structGet(cfgE, "phy.duplex.mode", ...
    sixgr.util.structGet(cfgE, "scenario.duplexMode", "TDD"))));
waveformDL = string(sixgr.util.structGet(cfgE, "phy.waveform.dl", "CP-OFDM"));
waveformUL = string(sixgr.util.structGet(cfgE, "phy.waveform.ul", "CP-OFDM"));

try
    traffic = sixgr.system.TrafficFactory.generate(cfgE, nUE, nSlots, slotDur_s);
catch ME
    if strictValidation
        rethrow(ME);
    end
    traffic = struct();
    traffic.Model = string(trafficModel);
    traffic.OfferedBits = max(0, round(4e4 + 2e4*randn(nSlots, nUE)));
    traffic.OfferedBitsDL = round(0.8 * traffic.OfferedBits);
    traffic.OfferedBitsUL = max(traffic.OfferedBits - traffic.OfferedBitsDL, 0);
    traffic.Transport = upper(string(sixgr.util.structGet(cfgE, "traffic.transport", "UDP")));
    traffic.FlowDirection = upper(string(sixgr.util.structGet(cfgE, "traffic.flowDirection", "BIDIR")));
    traffic.PacketDelayBudget_ms = double(sixgr.util.structGet(cfgE, "traffic.packetDelayBudget_ms", 50));
    traffic.FlowTable = table();
end
if ~isfield(traffic, "OfferedBitsDL") || isempty(traffic.OfferedBitsDL)
    traffic.OfferedBitsDL = zeros(nSlots, nUE);
end
if ~isfield(traffic, "OfferedBitsUL") || isempty(traffic.OfferedBitsUL)
    traffic.OfferedBitsUL = zeros(nSlots, nUE);
end
if ~isfield(traffic, "OfferedBits") || isempty(traffic.OfferedBits)
    traffic.OfferedBits = traffic.OfferedBitsDL + traffic.OfferedBitsUL;
end
if size(traffic.OfferedBitsDL,1) ~= nSlots || size(traffic.OfferedBitsDL,2) ~= nUE
    traffic.OfferedBitsDL = localExpandTrafficBits(traffic.OfferedBitsDL, nSlots, nUE, "OfferedBitsDL");
end
if size(traffic.OfferedBitsUL,1) ~= nSlots || size(traffic.OfferedBitsUL,2) ~= nUE
    traffic.OfferedBitsUL = localExpandTrafficBits(traffic.OfferedBitsUL, nSlots, nUE, "OfferedBitsUL");
end
if size(traffic.OfferedBits,1) ~= nSlots || size(traffic.OfferedBits,2) ~= nUE
    traffic.OfferedBits = localExpandTrafficBits(traffic.OfferedBits, nSlots, nUE, "OfferedBits");
end
traffic.OfferedBitsDL = max(0, round(double(traffic.OfferedBitsDL)));
traffic.OfferedBitsUL = max(0, round(double(traffic.OfferedBitsUL)));

% Honor explicit run-level traffic controls even when model profiles define
% multiple flow directions/protocols.
cfgTransport = upper(string(sixgr.util.structGet(cfgE, "traffic.transport", "UDP")));
cfgFlowDir = upper(string(sixgr.util.structGet(cfgE, "traffic.flowDirection", "BIDIR")));
traffic.Transport = cfgTransport;
traffic.FlowDirection = cfgFlowDir;
switch cfgFlowDir
    case "DL"
        traffic.OfferedBitsUL(:) = 0;
    case "UL"
        traffic.OfferedBitsDL(:) = 0;
end
traffic.OfferedBits = traffic.OfferedBitsDL + traffic.OfferedBitsUL;

qfi = double(sixgr.util.structGet(cfgE, "traffic.qos.default5QI", 9));
lcidData = 4;
rlcMode = upper(char(string(sixgr.util.structGet(cfgE, "rlc.mode", "UM"))));
transport = upper(string(sixgr.util.structGet(traffic, "Transport", sixgr.util.structGet(cfgE, "traffic.transport", "UDP"))));
flowDirCfg = upper(string(sixgr.util.structGet(traffic, "FlowDirection", sixgr.util.structGet(cfgE, "traffic.flowDirection", "BIDIR"))));
pdb_ms = double(sixgr.util.structGet(traffic, "PacketDelayBudget_ms", sixgr.util.structGet(cfgE, "traffic.packetDelayBudget_ms", 50)));
if ~isfinite(pdb_ms) || pdb_ms <= 0
    pdb_ms = 50;
end
baseChunk = max(512, round(double(sixgr.util.structGet(cfgE, "traffic.rlcSduChunk_bytes", 32768))));
appSDUChunkBytes = baseChunk;
if logical(opt.E2EScaleChunkWithCompression)
    maxChunk = max(1024, round(double(opt.E2EMaxSDUChunkBytes)));
    scaledChunk = baseChunk * max(1, compression);
    appSDUChunkBytes = min(maxChunk, max(baseChunk, scaledChunk));
end
airModel = localBuildE2EAirModel(cfgE, fileparts(runFolder), opt, e2eAirLUT);
airModelName = string(sixgr.util.structGet(airModel, "Mode", "logistic"));
airModelSource = string(sixgr.util.structGet(airModel, "Source", "default"));
enableSemanticChecks = logical(opt.E2EEnableSemanticChecks);
enablePacketTrace = true;
pdbSlots = max(1, ceil((pdb_ms * 1e-3) / max(semanticSlotDur_s, eps)));

sdapDLTx = cell(nUE,1); sdapDLRx = cell(nUE,1);
pdcpDLTx = cell(nUE,1); pdcpDLRx = cell(nUE,1);
rlcDLTx = cell(nUE,1); rlcDLRx = cell(nUE,1);
bsrDL = cell(nUE,1);

sdapULTx = cell(nUE,1); sdapULRx = cell(nUE,1);
pdcpULTx = cell(nUE,1); pdcpULRx = cell(nUE,1);
rlcULTx = cell(nUE,1); rlcULRx = cell(nUE,1);
bsrUL = cell(nUE,1);

generatedBytesDL_UE = zeros(nUE,1);
generatedBytesUL_UE = zeros(nUE,1);
deliveredBytesDL_UE = zeros(nUE,1);
deliveredBytesUL_UE = zeros(nUE,1);
queueBytesDL_UE = zeros(nUE,1);
queueBytesUL_UE = zeros(nUE,1);

ackUE_DL = zeros(nUE,1);
nackUE_DL = zeros(nUE,1);
ackUE_UL = zeros(nUE,1);
nackUE_UL = zeros(nUE,1);

% Packet-level semantic integrity tracking (ID/order/latency/deadline).
virtPktQ_DL = cell(nUE,1);
virtPktQ_UL = cell(nUE,1);
nextPktIdDL = zeros(nUE,1);
nextPktIdUL = zeros(nUE,1);
lastDeliveredPktIdDL = zeros(nUE,1);
lastDeliveredPktIdUL = zeros(nUE,1);
generatedPktsDL_UE = zeros(nUE,1);
generatedPktsUL_UE = zeros(nUE,1);
deliveredPktsDL_UE = zeros(nUE,1);
deliveredPktsUL_UE = zeros(nUE,1);
deadlineMissPktsDL_UE = zeros(nUE,1);
deadlineMissPktsUL_UE = zeros(nUE,1);
duplicatePktsDL_UE = zeros(nUE,1);
duplicatePktsUL_UE = zeros(nUE,1);
reorderedPktsDL_UE = zeros(nUE,1);
reorderedPktsUL_UE = zeros(nUE,1);
latencyCap0 = max(1024, nSlots * nUE);
latencyDLBuf = localInitLatencyBuffer(latencyCap0);
latencyULBuf = localInitLatencyBuffer(latencyCap0);

vqCap0 = max(256, min(131072, 4 * nSlots));
for u = 1:nUE
    virtPktQ_DL{u} = localInitVirtualQueue(vqCap0);
    virtPktQ_UL{u} = localInitVirtualQueue(vqCap0);
end

packetTraceChunks = cell(max(128, 2 * nSlots), 1);
packetTraceChunkCount = 0;
grantTraceChunks = cell(max(128, nSlots), 1);
grantTraceChunkCount = 0;

for u = 1:nUE
    sdapDLTx{u} = sixgr.l2.sdap.SDAP(cfgE);
    sdapDLRx{u} = sixgr.l2.sdap.SDAP(cfgE);
    sdapULTx{u} = sixgr.l2.sdap.SDAP(cfgE);
    sdapULRx{u} = sixgr.l2.sdap.SDAP(cfgE);
    sdapDLTx{u}.setMapping(qfi, lcidData);
    sdapDLRx{u}.setMapping(qfi, lcidData);
    sdapULTx{u}.setMapping(qfi, lcidData);
    sdapULRx{u}.setMapping(qfi, lcidData);

    pdcpDLTx{u} = sixgr.l2.pdcp.PDCP(cfgE, "Direction", "DL");
    pdcpDLRx{u} = sixgr.l2.pdcp.PDCP(cfgE, "Direction", "DL");
    pdcpULTx{u} = sixgr.l2.pdcp.PDCP(cfgE, "Direction", "UL");
    pdcpULRx{u} = sixgr.l2.pdcp.PDCP(cfgE, "Direction", "UL");

    rlcDLTx{u} = localCreateRLCEntity(rlcMode, cfgE, "DL", lcidData);
    rlcDLRx{u} = localCreateRLCEntity(rlcMode, cfgE, "DL", lcidData);
    rlcULTx{u} = localCreateRLCEntity(rlcMode, cfgE, "UL", lcidData);
    rlcULRx{u} = localCreateRLCEntity(rlcMode, cfgE, "UL", lcidData);

    bsrDL{u} = sixgr.l2.mac.BSR_PHR();
    bsrUL{u} = sixgr.l2.mac.BSR_PHR();
end

riDL = max(1, min(4, double(sixgr.util.structGet(cfgE, "phy.pdsch.numLayers", 1))));
riUL = max(1, min(4, double(sixgr.util.structGet(cfgE, "phy.pusch.numLayers", 1))));
ueStatesDL = repmat(struct("RNTI",0,"DLBufferBytes",0,"CQI",1,"RI",riDL), nUE, 1);
ueStatesUL = repmat(struct("RNTI",0,"ULBufferBytes",0,"CQI",1,"RI",riUL), nUE, 1);
for u = 1:nUE
    ueStatesDL(u).RNTI = u;
    ueStatesUL(u).RNTI = u;
end

harqDL = sixgr.l2.mac.HARQEntity(cfgE, "Direction", "DL");
harqUL = sixgr.l2.mac.HARQEntity(cfgE, "Direction", "UL");
nHarqProc = round(double(sixgr.util.structGet(cfgE, "mac.harq.numProcesses", ...
    sixgr.util.structGet(cfgE, "phy.harq.nProcesses", 16))));
nHarqProc = max(1, nHarqProc);
retxDepthDL = zeros(nUE, nHarqProc);
retxDepthUL = zeros(nUE, nHarqProc);

schedType = lower(char(string(sixgr.util.structGet(cfgE, "mac.scheduler.type", "pf"))));
if localIsRoundRobinScheduler(schedType)
    schedDL = sixgr.l2.mac.SchedulerRR(cfgE, "Direction", "DL", "HARQ", harqDL);
    schedUL = sixgr.l2.mac.SchedulerRR(cfgE, "Direction", "UL", "HARQ", harqUL);
else
    schedDL = sixgr.l2.mac.SchedulerPF(cfgE, "Direction", "DL", "HARQ", harqDL);
    schedUL = sixgr.l2.mac.SchedulerPF(cfgE, "Direction", "UL", "HARQ", harqUL);
end

[attachOK, attachSlots, attachMsgCount, attachRNTI, attachTraceRows] = localRunRRCAttachProcedure(cfgE);
if strictValidation && ~attachOK
    error("sixgr:e2e:AttachFailedStrict", "Strict validation requires successful attach before data scheduling.");
end

slotIndex = (1:nSlots).';
offeredBits = zeros(nSlots,1);
offeredBitsDL = zeros(nSlots,1);
offeredBitsUL = zeros(nSlots,1);
deliveredBits = zeros(nSlots,1);
deliveredBitsDL = zeros(nSlots,1);
deliveredBitsUL = zeros(nSlots,1);
grantCount = zeros(nSlots,1);
grantCountDL = zeros(nSlots,1);
grantCountUL = zeros(nSlots,1);
ackCount = zeros(nSlots,1);
ackCountDL = zeros(nSlots,1);
ackCountUL = zeros(nSlots,1);
nackCount = zeros(nSlots,1);
nackCountDL = zeros(nSlots,1);
nackCountUL = zeros(nSlots,1);
retxCount = zeros(nSlots,1);
retxCountDL = zeros(nSlots,1);
retxCountUL = zeros(nSlots,1);
queueBits = zeros(nSlots,1);
queueBitsDL = zeros(nSlots,1);
queueBitsUL = zeros(nSlots,1);
meanCQI = zeros(nSlots,1);
goodput_Mbps = zeros(nSlots,1);
goodputDL_Mbps = zeros(nSlots,1);
goodputUL_Mbps = zeros(nSlots,1);
slotDirection = strings(nSlots,1);

% Component-wise I/O tracing (bytes per slot) for cross-layer verification.
ioDL_AppIn = zeros(nSlots,1);
ioDL_SDAP_TxOut = zeros(nSlots,1);
ioDL_PDCP_TxOut = zeros(nSlots,1);
ioDL_RLC_TxOut = zeros(nSlots,1);
ioDL_MAC_TBOut = zeros(nSlots,1);
ioDL_Air_RxIn = zeros(nSlots,1);
ioDL_MAC_DisasmOut = zeros(nSlots,1);
ioDL_RLC_RxOut = zeros(nSlots,1);
ioDL_PDCP_RxOut = zeros(nSlots,1);
ioDL_AppOut = zeros(nSlots,1);

ioUL_AppIn = zeros(nSlots,1);
ioUL_SDAP_TxOut = zeros(nSlots,1);
ioUL_PDCP_TxOut = zeros(nSlots,1);
ioUL_RLC_TxOut = zeros(nSlots,1);
ioUL_MAC_TBOut = zeros(nSlots,1);
ioUL_Air_RxIn = zeros(nSlots,1);
ioUL_MAC_DisasmOut = zeros(nSlots,1);
ioUL_RLC_RxOut = zeros(nSlots,1);
ioUL_PDCP_RxOut = zeros(nSlots,1);
ioUL_AppOut = zeros(nSlots,1);

nRB = double(sixgr.util.structGet(cfgE, "phy.carrier.NSizeGrid", 51));
if ~(isfinite(nRB) && nRB >= 1)
    nRB = 51;
end

for t = 1:nSlots
    [slotDL, slotUL, slotLbl] = localSlotDuplexStateE2E(cfgE, t);
    slotDirection(t) = slotLbl;
    if flowDirCfg == "DL"
        slotUL = false;
    elseif flowDirCfg == "UL"
        slotDL = false;
    end
    dataPlaneReady = logical(attachOK) && isfinite(double(attachSlots)) && ...
        (t > max(0, round(double(attachSlots))));
    if ~dataPlaneReady
        slotDL = false;
        slotUL = false;
    end
    offeredBitsDL(t) = sum(traffic.OfferedBitsDL(t,:));
    offeredBitsUL(t) = sum(traffic.OfferedBitsUL(t,:));
    offeredBits(t) = offeredBitsDL(t) + offeredBitsUL(t);

    for u = 1:nUE
        bytesInDL = floor(max(double(traffic.OfferedBitsDL(t,u)), 0) / 8);
        bytesInUL = floor(max(double(traffic.OfferedBitsUL(t,u)), 0) / 8);

        if bytesInDL > 0
            ioDL_AppIn(t) = ioDL_AppIn(t) + bytesInDL;
            generatedBytesDL_UE(u) = generatedBytesDL_UE(u) + bytesInDL;
            remDL = bytesInDL;
            while remDL > 0
                chunk = min(remDL, appSDUChunkBytes);
                payloadDL = uint8(randi([0 255], chunk, 1));
                sdapPduDL = sdapDLTx{u}.tx(payloadDL, qfi);
                pdcpPduDL = pdcpDLTx{u}.tx(sdapPduDL.SDUPayload);
                rlcDLTx{u}.addSDU(pdcpPduDL);
                if enableSemanticChecks || enablePacketTrace
                    [virtPktQ_DL{u}, nextPktIdDL(u)] = localEnqueueVirtualPacket( ...
                        virtPktQ_DL{u}, nextPktIdDL(u), chunk, t, ...
                        "FlowID", u, "BearerID", lcidData, "QFI", qfi);
                    generatedPktsDL_UE(u) = generatedPktsDL_UE(u) + 1;
                end
                ioDL_SDAP_TxOut(t) = ioDL_SDAP_TxOut(t) + numel(sdapPduDL.SDUPayload);
                ioDL_PDCP_TxOut(t) = ioDL_PDCP_TxOut(t) + numel(pdcpPduDL);
                queueBytesDL_UE(u) = queueBytesDL_UE(u) + numel(pdcpPduDL);
                remDL = remDL - chunk;
            end
        end

        if bytesInUL > 0
            ioUL_AppIn(t) = ioUL_AppIn(t) + bytesInUL;
            generatedBytesUL_UE(u) = generatedBytesUL_UE(u) + bytesInUL;
            remUL = bytesInUL;
            while remUL > 0
                chunk = min(remUL, appSDUChunkBytes);
                payloadUL = uint8(randi([0 255], chunk, 1));
                sdapPduUL = sdapULTx{u}.tx(payloadUL, qfi);
                pdcpPduUL = pdcpULTx{u}.tx(sdapPduUL.SDUPayload);
                rlcULTx{u}.addSDU(pdcpPduUL);
                if enableSemanticChecks || enablePacketTrace
                    [virtPktQ_UL{u}, nextPktIdUL(u)] = localEnqueueVirtualPacket( ...
                        virtPktQ_UL{u}, nextPktIdUL(u), chunk, t, ...
                        "FlowID", u, "BearerID", lcidData, "QFI", qfi);
                    generatedPktsUL_UE(u) = generatedPktsUL_UE(u) + 1;
                end
                ioUL_SDAP_TxOut(t) = ioUL_SDAP_TxOut(t) + numel(sdapPduUL.SDUPayload);
                ioUL_PDCP_TxOut(t) = ioUL_PDCP_TxOut(t) + numel(pdcpPduUL);
                queueBytesUL_UE(u) = queueBytesUL_UE(u) + numel(pdcpPduUL);
                remUL = remUL - chunk;
            end
        end

        try
            bsrDL{u}.setLCGBuffer(0, queueBytesDL_UE(u));
            bsrUL{u}.setLCGBuffer(0, queueBytesUL_UE(u));
        catch
        end

        cqiDL = max(1, min(15, round((snr_dB + 10 + 2*randn()) / 2)));
        cqiUL = max(1, min(15, round((snr_dB + ulSnrOffset_dB + 10 + 2*randn()) / 2)));
        ueStatesDL(u).DLBufferBytes = max(queueBytesDL_UE(u), 0);
        ueStatesDL(u).CQI = cqiDL;
        ueStatesDL(u).RI = riDL;
        ueStatesUL(u).ULBufferBytes = max(queueBytesUL_UE(u), 0);
        ueStatesUL(u).CQI = cqiUL;
        ueStatesUL(u).RI = riUL;
    end
    cqiVec = [double([ueStatesDL.CQI]), double([ueStatesUL.CQI])];
    meanCQI(t) = mean(cqiVec);

    grantsDL = struct([]);
    grantsUL = struct([]);
    if slotDL
        try
            [grantsDL, ~] = schedDL.schedule(t-1, ueStatesDL, struct("NPRB", nRB, "SymbolAllocation", [0 14]));
        catch
            grantsDL = struct([]);
        end
    end
    if slotUL
        try
            [grantsUL, ~] = schedUL.schedule(t-1, ueStatesUL, struct("NPRB", nRB, "SymbolAllocation", [0 14]));
        catch
            grantsUL = struct([]);
        end
    end
    grantCountDL(t) = numel(grantsDL);
    grantCountUL(t) = numel(grantsUL);
    grantCount(t) = grantCountDL(t) + grantCountUL(t);
    feedbackDL = repmat(struct("RNTI",0, "TBSBits",0, "Ack",false), max(1, numel(grantsDL)), 1);
    feedbackUL = repmat(struct("RNTI",0, "TBSBits",0, "Ack",false), max(1, numel(grantsUL)), 1);
    nFbDL = 0;
    nFbUL = 0;
    slotGrantRows = repmat(localE2EGrantTraceRowTemplate(), max(1, numel(grantsDL) + numel(grantsUL)), 1);
    nSlotGrantRows = 0;

    for g = 1:numel(grantsDL)
        gr = grantsDL(g);
        u = max(1, min(nUE, round(double(gr.RNTI))));
        queueBefore = max(0, queueBytesDL_UE(u));
        tbsBytesBase = max(1, round(double(sixgr.util.structGet(gr, "TBSBytes", 120))));
        tbsBytes = max(1, round(double(tbsBytesBase) * double(serviceScale)));
        harqId = 0;
        isRetx = false;
        if isfield(gr, "HARQ") && isstruct(gr.HARQ)
            if isfield(gr.HARQ, "HarqID") && ~isempty(gr.HARQ.HarqID)
                harqId = double(gr.HARQ.HarqID);
            end
            if isfield(gr.HARQ, "IsRetransmission") && ~isempty(gr.HARQ.IsRetransmission)
                isRetx = logical(gr.HARQ.IsRetransmission);
            end
        end
        pid = min(max(harqId + 1, 1), nHarqProc);
        retxBefore = retxDepthDL(u,pid);
        prbSet = sixgr.util.structGet(gr, "PRBSet", []);
        if isempty(prbSet)
            numPRB = double(sixgr.util.structGet(gr, "NPRB", nRB));
        else
            numPRB = numel(prbSet);
        end
        cqiUsed = double(sixgr.util.structGet(gr, "CQIUsed", ueStatesDL(u).CQI));
        mcsIdx = double(sixgr.util.structGet(gr, "MCSIndex", localFastCQIToMCS(cqiUsed)));
        numLayers = double(sixgr.util.structGet(gr, "NumLayers", riDL));
        tgtCodeRate = double(sixgr.util.structGet(gr, "TargetCodeRate", sixgr.util.structGet(cfgE, "phy.pdsch.codeRate", 0.5)));
        grantReason = string(sixgr.util.structGet(gr, "GrantReason", ""));

        if isRetx
            macPdu = harqDL.getStoredTB(u, harqId);
            if isempty(macPdu)
                sduList = rlcDLTx{u}.buildMACSDUs(localMacPayloadBudget(tbsBytes));
                ceList = struct([]);
                ioDL_RLC_TxOut(t) = ioDL_RLC_TxOut(t) + localSumMACSDUPayloadBytes(sduList);
                [macPdu, ~] = sixgr.l2.mac.TBAssembler.assemble(tbsBytes, sduList, ceList, "Direction", "DL");
            end
        else
            sduList = rlcDLTx{u}.buildMACSDUs(localMacPayloadBudget(tbsBytes));
            ioDL_RLC_TxOut(t) = ioDL_RLC_TxOut(t) + localSumMACSDUPayloadBytes(sduList);
            ceList = struct([]);
            [macPdu, ~] = sixgr.l2.mac.TBAssembler.assemble(tbsBytes, sduList, ceList, "Direction", "DL");
        end
        ioDL_MAC_TBOut(t) = ioDL_MAC_TBOut(t) + numel(macPdu);

        try
            harqDL.onTx(u, harqId, macPdu, gr, t-1);
        catch
        end

        airRes = localDeliverGrantOverPhy(cfgE, "DL", gr, macPdu, snr_dB, airModel, strictValidation, ...
            double(ueStatesDL(u).CQI), retxDepthDL(u,pid));
        ack = logical(airRes.Ok);
        blerEff = double(airRes.BLER); %#ok<NASGU>
        virtPktQ_DL{u} = localMarkVirtualPacketTx(virtPktQ_DL{u}, numel(macPdu), t, pid, ack);

        try
            harqDL.onFeedback(u, harqId, ack);
        catch
        end

        nFbDL = nFbDL + 1;
        feedbackDL(nFbDL) = struct("RNTI", u, "TBSBits", 8*double(numel(macPdu)), "Ack", ack);

        if ack
            ackCountDL(t) = ackCountDL(t) + 1;
            ackUE_DL(u) = ackUE_DL(u) + 1;
            retxDepthDL(u,pid) = 0;
            ioDL_Air_RxIn(t) = ioDL_Air_RxIn(t) + numel(macPdu);

            [rxSdus, ~] = sixgr.l2.mac.TBAssembler.disassemble(macPdu, "Direction", "DL");
            deliveredNowBytes = 0;
            disasmBytes = 0;
            for s = 1:numel(rxSdus)
                if isfield(rxSdus(s), "LCID") && double(rxSdus(s).LCID) ~= lcidData
                    continue;
                end
                if isfield(rxSdus(s), "Payload") && ~isempty(rxSdus(s).Payload)
                    disasmBytes = disasmBytes + numel(rxSdus(s).Payload);
                    try
                        rlcDLRx{u}.receivePDU(uint8(rxSdus(s).Payload(:)));
                    catch
                    end
                end
            end
            ioDL_MAC_DisasmOut(t) = ioDL_MAC_DisasmOut(t) + disasmBytes;

            if isa(rlcDLRx{u}, "sixgr.l2.rlc.RLC_AM")
                st = rlcDLRx{u}.buildMACSDUs(128);
                for si = 1:numel(st)
                    if isfield(st(si), "Payload") && ~isempty(st(si).Payload)
                        try
                            rlcDLTx{u}.receivePDU(uint8(st(si).Payload(:)));
                        catch
                        end
                    end
                end
            end

            rlcOut = rlcDLRx{u}.pullSDUs();
            if iscell(rlcOut)
                for j = 1:numel(rlcOut)
                    ioDL_RLC_RxOut(t) = ioDL_RLC_RxOut(t) + numel(rlcOut{j});
                    pdcpDLRx{u}.rx(rlcOut{j});
                end
            end

            pdcpOut = pdcpDLRx{u}.pullSDUs();
            if iscell(pdcpOut)
                for j = 1:numel(pdcpOut)
                    ioDL_PDCP_RxOut(t) = ioDL_PDCP_RxOut(t) + numel(pdcpOut{j});
                    [appPayload, ~, ~, ~] = sdapDLRx{u}.rx(pdcpOut{j});
                    deliveredNowBytes = deliveredNowBytes + numel(appPayload);
                end
            end
            ioDL_AppOut(t) = ioDL_AppOut(t) + deliveredNowBytes;
            deliveredBytesDL_UE(u) = deliveredBytesDL_UE(u) + deliveredNowBytes;
            deliveredBitsDL(t) = deliveredBitsDL(t) + 8*double(deliveredNowBytes);
            queueBytesDL_UE(u) = max(queueBytesDL_UE(u) - numel(macPdu), 0);
            if enableSemanticChecks || enablePacketTrace
                [virtPktQ_DL{u}, sem] = localConsumeVirtualPackets(virtPktQ_DL{u}, deliveredNowBytes, ...
                    t, semanticSlotDur_s, pdbSlots, lastDeliveredPktIdDL(u), ...
                    "Direction", "DL", "UE", u);
                lastDeliveredPktIdDL(u) = sem.LastDeliveredId;
                deliveredPktsDL_UE(u) = deliveredPktsDL_UE(u) + sem.DeliveredPackets;
                deadlineMissPktsDL_UE(u) = deadlineMissPktsDL_UE(u) + sem.DeadlineMissPackets;
                duplicatePktsDL_UE(u) = duplicatePktsDL_UE(u) + sem.DuplicatePackets;
                reorderedPktsDL_UE(u) = reorderedPktsDL_UE(u) + sem.OutOfOrderPackets;
                if ~isempty(sem.LatencyMs)
                    latencyDLBuf = localAppendLatencySamples(latencyDLBuf, sem.LatencyMs(:));
                end
                if enablePacketTrace && ~isempty(sem.PacketRows)
                    [packetTraceChunks, packetTraceChunkCount] = localPushStructChunk( ...
                        packetTraceChunks, packetTraceChunkCount, sem.PacketRows(:));
                end
            end
        else
            nackCountDL(t) = nackCountDL(t) + 1;
            retxCountDL(t) = retxCountDL(t) + 1;
            nackUE_DL(u) = nackUE_DL(u) + 1;
            retxDepthDL(u,pid) = min(retxDepthDL(u,pid) + 1, 8);
        end
        queueAfter = max(0, queueBytesDL_UE(u));
        retxAfter = retxDepthDL(u,pid);
        tr = localE2EGrantTraceRowTemplate();
        tr.Slot = t;
        tr.Time_s = (t - 1) * slotDur_s;
        tr.Direction = "DL";
        tr.UE = u;
        tr.FlowID = u;
        tr.BearerID = lcidData;
        tr.QFI = qfi;
        tr.GrantIndex = g;
        tr.NumPRB = numPRB;
        tr.TBSBytes = numel(macPdu);
        tr.CQIUsed = cqiUsed;
        tr.MCSIndex = mcsIdx;
        tr.NumLayers = numLayers;
        tr.TargetCodeRate = tgtCodeRate;
        tr.QueueBytesBefore = queueBefore;
        tr.QueueBytesAfter = queueAfter;
        tr.HARQProcess = pid;
        tr.RetxDepthBefore = retxBefore;
        tr.RetxDepthAfter = retxAfter;
        tr.AttemptCount = retxBefore + 1;
        tr.IsRetransmission = logical(isRetx);
        tr.Ack = logical(ack);
        tr.CRCResult = logical(ack);
        tr.BLER = double(airRes.BLER);
        tr.AirMode = string(sixgr.util.structGet(airRes, "Mode", airModelName));
        tr.Note = string(sixgr.util.structGet(airRes, "Notes", ""));
        tr.GrantReason = grantReason;
        nSlotGrantRows = nSlotGrantRows + 1;
        slotGrantRows(nSlotGrantRows,1) = tr;
    end

    for g = 1:numel(grantsUL)
        gr = grantsUL(g);
        u = max(1, min(nUE, round(double(gr.RNTI))));
        queueBefore = max(0, queueBytesUL_UE(u));
        tbsBytesBase = max(1, round(double(sixgr.util.structGet(gr, "TBSBytes", 120))));
        tbsBytes = max(1, round(double(tbsBytesBase) * double(serviceScale)));
        harqId = 0;
        isRetx = false;
        if isfield(gr, "HARQ") && isstruct(gr.HARQ)
            if isfield(gr.HARQ, "HarqID") && ~isempty(gr.HARQ.HarqID)
                harqId = double(gr.HARQ.HarqID);
            end
            if isfield(gr.HARQ, "IsRetransmission") && ~isempty(gr.HARQ.IsRetransmission)
                isRetx = logical(gr.HARQ.IsRetransmission);
            end
        end
        pid = min(max(harqId + 1, 1), nHarqProc);
        retxBefore = retxDepthUL(u,pid);
        prbSet = sixgr.util.structGet(gr, "PRBSet", []);
        if isempty(prbSet)
            numPRB = double(sixgr.util.structGet(gr, "NPRB", nRB));
        else
            numPRB = numel(prbSet);
        end
        cqiUsed = double(sixgr.util.structGet(gr, "CQIUsed", ueStatesUL(u).CQI));
        mcsIdx = double(sixgr.util.structGet(gr, "MCSIndex", localFastCQIToMCS(cqiUsed)));
        numLayers = double(sixgr.util.structGet(gr, "NumLayers", riUL));
        tgtCodeRate = double(sixgr.util.structGet(gr, "TargetCodeRate", sixgr.util.structGet(cfgE, "phy.pusch.codeRate", 0.5)));
        grantReason = string(sixgr.util.structGet(gr, "GrantReason", ""));

        if isRetx
            macPdu = harqUL.getStoredTB(u, harqId);
            if isempty(macPdu)
                sduList = rlcULTx{u}.buildMACSDUs(localMacPayloadBudget(tbsBytes));
                ceList = struct([]);
                ioUL_RLC_TxOut(t) = ioUL_RLC_TxOut(t) + localSumMACSDUPayloadBytes(sduList);
                [macPdu, ~] = sixgr.l2.mac.TBAssembler.assemble(tbsBytes, sduList, ceList, "Direction", "UL");
            end
        else
            sduList = rlcULTx{u}.buildMACSDUs(localMacPayloadBudget(tbsBytes));
            ioUL_RLC_TxOut(t) = ioUL_RLC_TxOut(t) + localSumMACSDUPayloadBytes(sduList);
            ceList = struct([]);
            try
                ceBSR = bsrUL{u}.makeBSR("Format", "auto");
                if ~isempty(ceBSR), ceList = [ceList ceBSR]; end
            catch
            end
            try
                cePHR = bsrUL{u}.makePHR(10 + 2*randn(), 23, "PowerBackoff", false);
                if ~isempty(cePHR), ceList = [ceList cePHR]; end
            catch
            end
            [macPdu, ~] = sixgr.l2.mac.TBAssembler.assemble(tbsBytes, sduList, ceList, "Direction", "UL");
        end
        ioUL_MAC_TBOut(t) = ioUL_MAC_TBOut(t) + numel(macPdu);

        try
            harqUL.onTx(u, harqId, macPdu, gr, t-1);
        catch
        end

        airRes = localDeliverGrantOverPhy(cfgE, "UL", gr, macPdu, snr_dB + ulSnrOffset_dB, airModel, strictValidation, ...
            double(ueStatesUL(u).CQI), retxDepthUL(u,pid));
        ack = logical(airRes.Ok);
        blerEff = double(airRes.BLER); %#ok<NASGU>
        virtPktQ_UL{u} = localMarkVirtualPacketTx(virtPktQ_UL{u}, numel(macPdu), t, pid, ack);

        try
            harqUL.onFeedback(u, harqId, ack);
        catch
        end

        nFbUL = nFbUL + 1;
        feedbackUL(nFbUL) = struct("RNTI", u, "TBSBits", 8*double(numel(macPdu)), "Ack", ack);

        if ack
            ackCountUL(t) = ackCountUL(t) + 1;
            ackUE_UL(u) = ackUE_UL(u) + 1;
            retxDepthUL(u,pid) = 0;
            ioUL_Air_RxIn(t) = ioUL_Air_RxIn(t) + numel(macPdu);

            [rxSdus, ~] = sixgr.l2.mac.TBAssembler.disassemble(macPdu, "Direction", "UL");
            deliveredNowBytes = 0;
            disasmBytes = 0;
            for s = 1:numel(rxSdus)
                if isfield(rxSdus(s), "LCID") && double(rxSdus(s).LCID) ~= lcidData
                    continue;
                end
                if isfield(rxSdus(s), "Payload") && ~isempty(rxSdus(s).Payload)
                    disasmBytes = disasmBytes + numel(rxSdus(s).Payload);
                    try
                        rlcULRx{u}.receivePDU(uint8(rxSdus(s).Payload(:)));
                    catch
                    end
                end
            end
            ioUL_MAC_DisasmOut(t) = ioUL_MAC_DisasmOut(t) + disasmBytes;

            if isa(rlcULRx{u}, "sixgr.l2.rlc.RLC_AM")
                st = rlcULRx{u}.buildMACSDUs(128);
                for si = 1:numel(st)
                    if isfield(st(si), "Payload") && ~isempty(st(si).Payload)
                        try
                            rlcULTx{u}.receivePDU(uint8(st(si).Payload(:)));
                        catch
                        end
                    end
                end
            end

            rlcOut = rlcULRx{u}.pullSDUs();
            if iscell(rlcOut)
                for j = 1:numel(rlcOut)
                    ioUL_RLC_RxOut(t) = ioUL_RLC_RxOut(t) + numel(rlcOut{j});
                    pdcpULRx{u}.rx(rlcOut{j});
                end
            end

            pdcpOut = pdcpULRx{u}.pullSDUs();
            if iscell(pdcpOut)
                for j = 1:numel(pdcpOut)
                    ioUL_PDCP_RxOut(t) = ioUL_PDCP_RxOut(t) + numel(pdcpOut{j});
                    [appPayload, ~, ~, ~] = sdapULRx{u}.rx(pdcpOut{j});
                    deliveredNowBytes = deliveredNowBytes + numel(appPayload);
                end
            end
            ioUL_AppOut(t) = ioUL_AppOut(t) + deliveredNowBytes;
            deliveredBytesUL_UE(u) = deliveredBytesUL_UE(u) + deliveredNowBytes;
            deliveredBitsUL(t) = deliveredBitsUL(t) + 8*double(deliveredNowBytes);
            queueBytesUL_UE(u) = max(queueBytesUL_UE(u) - numel(macPdu), 0);
            if enableSemanticChecks || enablePacketTrace
                [virtPktQ_UL{u}, sem] = localConsumeVirtualPackets(virtPktQ_UL{u}, deliveredNowBytes, ...
                    t, semanticSlotDur_s, pdbSlots, lastDeliveredPktIdUL(u), ...
                    "Direction", "UL", "UE", u);
                lastDeliveredPktIdUL(u) = sem.LastDeliveredId;
                deliveredPktsUL_UE(u) = deliveredPktsUL_UE(u) + sem.DeliveredPackets;
                deadlineMissPktsUL_UE(u) = deadlineMissPktsUL_UE(u) + sem.DeadlineMissPackets;
                duplicatePktsUL_UE(u) = duplicatePktsUL_UE(u) + sem.DuplicatePackets;
                reorderedPktsUL_UE(u) = reorderedPktsUL_UE(u) + sem.OutOfOrderPackets;
                if ~isempty(sem.LatencyMs)
                    latencyULBuf = localAppendLatencySamples(latencyULBuf, sem.LatencyMs(:));
                end
                if enablePacketTrace && ~isempty(sem.PacketRows)
                    [packetTraceChunks, packetTraceChunkCount] = localPushStructChunk( ...
                        packetTraceChunks, packetTraceChunkCount, sem.PacketRows(:));
                end
            end
        else
            nackCountUL(t) = nackCountUL(t) + 1;
            retxCountUL(t) = retxCountUL(t) + 1;
            nackUE_UL(u) = nackUE_UL(u) + 1;
            retxDepthUL(u,pid) = min(retxDepthUL(u,pid) + 1, 8);
        end
        queueAfter = max(0, queueBytesUL_UE(u));
        retxAfter = retxDepthUL(u,pid);
        tr = localE2EGrantTraceRowTemplate();
        tr.Slot = t;
        tr.Time_s = (t - 1) * slotDur_s;
        tr.Direction = "UL";
        tr.UE = u;
        tr.FlowID = u;
        tr.BearerID = lcidData;
        tr.QFI = qfi;
        tr.GrantIndex = g;
        tr.NumPRB = numPRB;
        tr.TBSBytes = numel(macPdu);
        tr.CQIUsed = cqiUsed;
        tr.MCSIndex = mcsIdx;
        tr.NumLayers = numLayers;
        tr.TargetCodeRate = tgtCodeRate;
        tr.QueueBytesBefore = queueBefore;
        tr.QueueBytesAfter = queueAfter;
        tr.HARQProcess = pid;
        tr.RetxDepthBefore = retxBefore;
        tr.RetxDepthAfter = retxAfter;
        tr.AttemptCount = retxBefore + 1;
        tr.IsRetransmission = logical(isRetx);
        tr.Ack = logical(ack);
        tr.CRCResult = logical(ack);
        tr.BLER = double(airRes.BLER);
        tr.AirMode = string(sixgr.util.structGet(airRes, "Mode", airModelName));
        tr.Note = string(sixgr.util.structGet(airRes, "Notes", ""));
        tr.GrantReason = grantReason;
        nSlotGrantRows = nSlotGrantRows + 1;
        slotGrantRows(nSlotGrantRows,1) = tr;
    end

    if nSlotGrantRows > 0
        [grantTraceChunks, grantTraceChunkCount] = localPushStructChunk( ...
            grantTraceChunks, grantTraceChunkCount, slotGrantRows(1:nSlotGrantRows));
    end

    if nFbDL > 0
        try
            schedDL.updateAfterRx(feedbackDL(1:nFbDL));
        catch
        end
    end
    if nFbUL > 0
        try
            schedUL.updateAfterRx(feedbackUL(1:nFbUL));
        catch
        end
    end

    deliveredBits(t) = deliveredBitsDL(t) + deliveredBitsUL(t);
    ackCount(t) = ackCountDL(t) + ackCountUL(t);
    nackCount(t) = nackCountDL(t) + nackCountUL(t);
    retxCount(t) = retxCountDL(t) + retxCountUL(t);
    queueBitsDL(t) = 8 * sum(max(queueBytesDL_UE, 0));
    queueBitsUL(t) = 8 * sum(max(queueBytesUL_UE, 0));
    queueBits(t) = queueBitsDL(t) + queueBitsUL(t);
    goodputDL_Mbps(t) = (deliveredBitsDL(t) / max(slotDur_s, eps)) / 1e6;
    goodputUL_Mbps(t) = (deliveredBitsUL(t) / max(slotDur_s, eps)) / 1e6;
    goodput_Mbps(t) = goodputDL_Mbps(t) + goodputUL_Mbps(t);
end

if enablePacketTrace
    finalDropCause = "not_delivered_by_end";
    if ~attachOK
        finalDropCause = "attach_not_connected";
    end
    for u = 1:nUE
        [virtPktQ_DL{u}, dropRowsDL] = localFinalizeVirtualQueueDrops( ...
            virtPktQ_DL{u}, nSlots, semanticSlotDur_s, pdbSlots, ...
            lastDeliveredPktIdDL(u), "DL", u, finalDropCause);
        if ~isempty(dropRowsDL)
            [packetTraceChunks, packetTraceChunkCount] = localPushStructChunk( ...
                packetTraceChunks, packetTraceChunkCount, dropRowsDL(:));
        end
        [virtPktQ_UL{u}, dropRowsUL] = localFinalizeVirtualQueueDrops( ...
            virtPktQ_UL{u}, nSlots, semanticSlotDur_s, pdbSlots, ...
            lastDeliveredPktIdUL(u), "UL", u, finalDropCause);
        if ~isempty(dropRowsUL)
            [packetTraceChunks, packetTraceChunkCount] = localPushStructChunk( ...
                packetTraceChunks, packetTraceChunkCount, dropRowsUL(:));
        end
    end
end

packetTraceRows = localConcatStructChunks(packetTraceChunks, packetTraceChunkCount, localPacketTraceRowTemplate());
grantTraceRows = localConcatStructChunks(grantTraceChunks, grantTraceChunkCount, localE2EGrantTraceRowTemplate());

totalOfferedBitsDL = sum(offeredBitsDL);
totalOfferedBitsUL = sum(offeredBitsUL);
totalOfferedBits = totalOfferedBitsDL + totalOfferedBitsUL;
totalDeliveredBitsDL = sum(deliveredBitsDL);
totalDeliveredBitsUL = sum(deliveredBitsUL);
totalDeliveredBits = totalDeliveredBitsDL + totalDeliveredBitsUL;
simDur_s = nSlots * slotDur_s;
offered_Mbps = totalOfferedBits / max(simDur_s, eps) / 1e6;
offeredDL_Mbps = totalOfferedBitsDL / max(simDur_s, eps) / 1e6;
offeredUL_Mbps = totalOfferedBitsUL / max(simDur_s, eps) / 1e6;
goodput_Mbps_total = totalDeliveredBits / max(simDur_s, eps) / 1e6;
goodputDL_Mbps_total = totalDeliveredBitsDL / max(simDur_s, eps) / 1e6;
goodputUL_Mbps_total = totalDeliveredBitsUL / max(simDur_s, eps) / 1e6;
deliveryRatio = totalDeliveredBits / max(totalOfferedBits, 1);
deliveryRatioDL = totalDeliveredBitsDL / max(totalOfferedBitsDL, 1);
deliveryRatioUL = totalDeliveredBitsUL / max(totalOfferedBitsUL, 1);
retxProb = sum(retxCount) / max(sum(grantCount), 1);
retxProbDL = sum(retxCountDL) / max(sum(grantCountDL), 1);
retxProbUL = sum(retxCountUL) / max(sum(grantCountUL), 1);
ackRate = sum(ackCount) / max(sum(grantCount), 1);
ackRateDL = sum(ackCountDL) / max(sum(grantCountDL), 1);
ackRateUL = sum(ackCountUL) / max(sum(grantCountUL), 1);
nackRate = sum(nackCount) / max(sum(grantCount), 1);
nackRateDL = sum(nackCountDL) / max(sum(grantCountDL), 1);
nackRateUL = sum(nackCountUL) / max(sum(grantCountUL), 1);
deliveredBytesUE = deliveredBytesDL_UE + deliveredBytesUL_UE;
jain = (sum(deliveredBytesUE)^2) / max(nUE * sum(deliveredBytesUE.^2), eps);
latencySamplesDL_ms = localFinalizeLatencyBuffer(latencyDLBuf);
latencySamplesUL_ms = localFinalizeLatencyBuffer(latencyULBuf);
[packetIntegrityTable, semanticPassRate] = localBuildE2EPacketIntegrityTable( ...
    generatedPktsDL_UE, deliveredPktsDL_UE, deadlineMissPktsDL_UE, ...
    duplicatePktsDL_UE, reorderedPktsDL_UE, latencySamplesDL_ms, ...
    generatedPktsUL_UE, deliveredPktsUL_UE, deadlineMissPktsUL_UE, ...
    duplicatePktsUL_UE, reorderedPktsUL_UE, latencySamplesUL_ms, pdb_ms);
packetTraceTable = localPacketTraceRowsToTable(packetTraceRows);
[schedulerTraceTable, harqTraceTable] = localBuildE2EGrantTraceTables(grantTraceRows);
attachTraceTable = localBuildE2EAttachTraceTable(attachTraceRows);
[flowSummaryTable, bearerSummaryTable, dropCauseTable] = localBuildE2ETraceSummaries(packetTraceTable, simDur_s);
if ~isempty(packetTraceTable)
    packetTraceTable.TraceMode = repmat("FULL_STACK_REPLAY", height(packetTraceTable), 1);
end
if ~isempty(schedulerTraceTable)
    schedulerTraceTable.TraceMode = repmat("FULL_STACK_REPLAY", height(schedulerTraceTable), 1);
end
if ~isempty(harqTraceTable)
    harqTraceTable.TraceMode = repmat("FULL_STACK_REPLAY", height(harqTraceTable), 1);
end

fddFrac = mean(slotDirection == "FDD_DLUL");
dlFrac = mean(slotDirection == "DL");
ulFrac = mean(slotDirection == "UL");
spFrac = mean(slotDirection == "S");

slotTable = table(slotIndex, string(slotDirection), ...
    offeredBits, offeredBitsDL, offeredBitsUL, ...
    deliveredBits, deliveredBitsDL, deliveredBitsUL, ...
    grantCount, grantCountDL, grantCountUL, ...
    ackCount, ackCountDL, ackCountUL, ...
    nackCount, nackCountDL, nackCountUL, ...
    retxCount, retxCountDL, retxCountUL, ...
    meanCQI, queueBits, queueBitsDL, queueBitsUL, ...
    goodput_Mbps, goodputDL_Mbps, goodputUL_Mbps, ...
    'VariableNames', {'Slot','SlotDirection', ...
                      'OfferedBits','OfferedBitsDL','OfferedBitsUL', ...
                      'DeliveredBits','DeliveredBitsDL','DeliveredBitsUL', ...
                      'NumGrants','NumGrantsDL','NumGrantsUL', ...
                      'NumACK','NumACK_DL','NumACK_UL', ...
                      'NumNACK','NumNACK_DL','NumNACK_UL', ...
                      'NumRetx','NumRetx_DL','NumRetx_UL', ...
                      'MeanCQI','QueueBits','QueueBitsDL','QueueBitsUL', ...
                      'Goodput_Mbps','GoodputDL_Mbps','GoodputUL_Mbps'});

summaryTable = table(string(trafficModel), string(transport), string(flowDirCfg), pdb_ms, ...
    string(duplexMode), string(waveformDL), string(waveformUL), ...
    nUE, nSlots, 1e3*slotDur_s, compression, double(opt.E2EDuration_s), simDur_s, ...
    offered_Mbps, offeredDL_Mbps, offeredUL_Mbps, ...
    goodput_Mbps_total, goodputDL_Mbps_total, goodputUL_Mbps_total, ...
    deliveryRatio, deliveryRatioDL, deliveryRatioUL, ...
    retxProb, retxProbDL, retxProbUL, ...
    ackRate, ackRateDL, ackRateUL, ...
    nackRate, nackRateDL, nackRateUL, ...
    jain, fddFrac, dlFrac, ulFrac, spFrac, ...
    attachOK, attachSlots, attachMsgCount, attachRNTI, ...
    serviceScale, airModelName, airModelSource, strictValidation, semanticPassRate, ...
    'VariableNames', {'TrafficModel','Transport','FlowDirection','PacketDelayBudget_ms', ...
                      'DuplexMode','WaveformDL','WaveformUL', ...
                      'NumUE','NumSlots','SlotDuration_ms','TimeCompressionFactor', ...
                      'RequestedDuration_s','SimulatedDuration_s', ...
                      'Offered_Mbps','OfferedDL_Mbps','OfferedUL_Mbps', ...
                      'Goodput_Mbps','GoodputDL_Mbps','GoodputUL_Mbps', ...
                      'DeliveryRatio','DeliveryRatioDL','DeliveryRatioUL', ...
                      'HARQ_RetxProbability','HARQ_RetxProbabilityDL','HARQ_RetxProbabilityUL', ...
                      'ACKRate','ACKRateDL','ACKRateUL', ...
                      'NACKRate','NACKRateDL','NACKRateUL', ...
                      'JainFairness','FDDSlotFraction','DLSlotFraction','ULSlotFraction','SpecialSlotFraction', ...
                      'AttachSuccess','AttachSlots','AttachMessages','AttachRNTI', ...
                      'ServiceScaleFactor','E2EAirModel','E2EAirModelSource','StrictValidationMode', ...
                      'SemanticCheckPassRate_pct'});
summaryTable.ExecutionBackend = repmat("FULL_STACK_REPLAY", height(summaryTable), 1);
summaryTable.PHYMode = repmat("GRANT_DELIVERY_BACKEND", height(summaryTable), 1);

componentIOTable = table(slotIndex, string(slotDirection), ...
    ioDL_AppIn, ioDL_SDAP_TxOut, ioDL_PDCP_TxOut, ioDL_RLC_TxOut, ioDL_MAC_TBOut, ...
    ioDL_Air_RxIn, ioDL_MAC_DisasmOut, ioDL_RLC_RxOut, ioDL_PDCP_RxOut, ioDL_AppOut, ...
    ioUL_AppIn, ioUL_SDAP_TxOut, ioUL_PDCP_TxOut, ioUL_RLC_TxOut, ioUL_MAC_TBOut, ...
    ioUL_Air_RxIn, ioUL_MAC_DisasmOut, ioUL_RLC_RxOut, ioUL_PDCP_RxOut, ioUL_AppOut, ...
    'VariableNames', {'Slot','SlotDirection', ...
                      'DL_AppIn_Bytes','DL_SDAP_TxOut_Bytes','DL_PDCP_TxOut_Bytes','DL_RLC_TxOut_Bytes','DL_MAC_TBOut_Bytes', ...
                      'DL_Air_RxIn_Bytes','DL_MAC_DisasmOut_Bytes','DL_RLC_RxOut_Bytes','DL_PDCP_RxOut_Bytes','DL_AppOut_Bytes', ...
                      'UL_AppIn_Bytes','UL_SDAP_TxOut_Bytes','UL_PDCP_TxOut_Bytes','UL_RLC_TxOut_Bytes','UL_MAC_TBOut_Bytes', ...
                      'UL_Air_RxIn_Bytes','UL_MAC_DisasmOut_Bytes','UL_RLC_RxOut_Bytes','UL_PDCP_RxOut_Bytes','UL_AppOut_Bytes'});
checkTable = localBuildE2EComponentChecks(componentIOTable, packetIntegrityTable);
passRate = 100 * mean(double(checkTable.Pass));
summaryTable.ComponentCheckPassRate_pct = passRate;

aiTable = localRunE2EAIProbe(cfgE, logical(opt.E2EEnableAI), snr_dB);

sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_packet_trace.csv"), packetTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_flow_summary.csv"), flowSummaryTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_bearer_summary.csv"), bearerSummaryTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_attach_trace.csv"), attachTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_harq_trace.csv"), harqTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_scheduler_trace.csv"), schedulerTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_drop_causes.csv"), dropCauseTable);

sixgr.util.matSave(fullfile(runFolder, "mat", "e2e_probe.mat"), struct( ...
    "slotTable", slotTable, ...
    "componentIOTable", componentIOTable, ...
    "checkTable", checkTable, ...
    "packetIntegrityTable", packetIntegrityTable, ...
    "packetTraceTable", packetTraceTable, ...
    "flowSummaryTable", flowSummaryTable, ...
    "bearerSummaryTable", bearerSummaryTable, ...
    "attachTraceTable", attachTraceTable, ...
    "harqTraceTable", harqTraceTable, ...
    "schedulerTraceTable", schedulerTraceTable, ...
    "dropCauseTable", dropCauseTable, ...
    "summaryTable", summaryTable, ...
    "aiTable", aiTable, ...
    "attach", struct("Ok",attachOK,"Slots",attachSlots,"Messages",attachMsgCount,"RNTI",attachRNTI), ...
    "generatedBytesDL_UE", generatedBytesDL_UE, ...
    "generatedBytesUL_UE", generatedBytesUL_UE, ...
    "deliveredBytesDL_UE", deliveredBytesDL_UE, ...
    "deliveredBytesUL_UE", deliveredBytesUL_UE, ...
    "ackUE_DL", ackUE_DL, ...
    "ackUE_UL", ackUE_UL, ...
    "nackUE_DL", nackUE_DL, ...
    "nackUE_UL", nackUE_UL, ...
    "retxDepthDL", retxDepthDL, ...
    "retxDepthUL", retxDepthUL));

if logical(opt.E2ESaveFigures)
    localSaveE2EPlots(runFolder, slotTable, packetTraceTable, flowSummaryTable, bearerSummaryTable, ...
        dropCauseTable, harqTraceTable, attachTraceTable, summaryTable);
end

out = struct();
out.Ok = true;
out.RunFolder = runFolder;
out.SlotTable = slotTable;
out.ComponentIOTable = componentIOTable;
out.CheckTable = checkTable;
out.PacketIntegrityTable = packetIntegrityTable;
out.PacketTraceTable = packetTraceTable;
out.FlowSummaryTable = flowSummaryTable;
out.BearerSummaryTable = bearerSummaryTable;
out.AttachTraceTable = attachTraceTable;
out.HARQTraceTable = harqTraceTable;
out.SchedulerTraceTable = schedulerTraceTable;
out.DropCauseTable = dropCauseTable;
out.SummaryTable = summaryTable;
out.AITable = aiTable;
out.Notes = "E2E stack probe completed (DL/UL/bidirectional with duplex-aware scheduling).";
end

function out = localRunEndToEndProbeFast(cfg, runFolder, opt, e2eAirLUT)
if nargin < 4
    e2eAirLUT = struct();
end
sixgr.util.ensureDir(runFolder);
sixgr.util.ensureDir(fullfile(runFolder, "csv"));
sixgr.util.ensureDir(fullfile(runFolder, "mat"));
sixgr.util.ensureDir(fullfile(runFolder, "fig"));
sixgr.util.ensureDir(fullfile(runFolder, "logs"));

slotDurBase_s = localSlotDuration(cfg);
nSlotsRaw = max(20, ceil(double(opt.E2EDuration_s) / max(slotDurBase_s, eps)));
maxSlots = max(0, round(double(opt.E2EMaxSlots)));
strictValidation = logical(opt.E2EStrictValidation);
compression = 1;
if maxSlots > 0 && nSlotsRaw > maxSlots
    compression = ceil(nSlotsRaw / maxSlots);
end
slotDur_s = slotDurBase_s * compression;
nSlots = max(20, ceil(nSlotsRaw / compression));
serviceScale = 1;
if logical(opt.E2EScaleServiceWithCompression)
    scaleCap = max(1, round(double(opt.E2EServiceScaleCap)));
    serviceScale = min(max(1, compression), scaleCap);
end
if strictValidation
    compression = 1;
    slotDur_s = slotDurBase_s;
    nSlots = nSlotsRaw;
    serviceScale = 1;
end
airModeReq = lower(char(string(sixgr.util.structGet(opt, "E2EAirModel", "lut"))));
if strcmp(airModeReq, "truth")
    truthMaxSlots = max(20, round(double(sixgr.util.structGet(opt, "E2ETruthMaxSlots", 240))));
    if nSlots > truthMaxSlots
        if strictValidation
            error("sixgr:e2e:TruthMaxSlotsExceeded", ...
                "Truth PHY replay requires %d slots, exceeding E2ETruthMaxSlots=%d. Reduce E2EDuration_s or raise E2ETruthMaxSlots intentionally.", ...
                nSlots, truthMaxSlots);
        end
        nSlots = truthMaxSlots;
    end
end

nUE = max(1, round(double(opt.E2EUECount)));
snr_dB = double(opt.LinkSNR_dB);
ulSnrOffset_dB = double(sixgr.util.structGet(cfg, "system.ulSinrOffset_dB", -1.0));
trafficModel = lower(char(string(opt.E2ETrafficModel)));
if strlength(string(trafficModel)) == 0
    trafficModel = "xr";
end

cfgE = cfg;
cfgE.scenario.ue.nUE = nUE;
cfgE.scenario.nUE = nUE;
cfgE.traffic.model = trafficModel;
cfgE.run.shortRun = false;
cfgE.run.strictMode = strictValidation;

try
    traffic = sixgr.system.TrafficFactory.generate(cfgE, nUE, nSlots, slotDur_s);
catch ME
    if strictValidation
        rethrow(ME);
    end
    traffic = struct();
    traffic.Model = string(trafficModel);
    traffic.OfferedBits = max(0, round(3e4 + 1.5e4*randn(nSlots, nUE)));
    traffic.OfferedBitsDL = round(0.8 * traffic.OfferedBits);
    traffic.OfferedBitsUL = max(traffic.OfferedBits - traffic.OfferedBitsDL, 0);
    traffic.Transport = upper(string(sixgr.util.structGet(cfgE, "traffic.transport", "UDP")));
    traffic.FlowDirection = upper(string(sixgr.util.structGet(cfgE, "traffic.flowDirection", "BIDIR")));
    traffic.PacketDelayBudget_ms = double(sixgr.util.structGet(cfgE, "traffic.packetDelayBudget_ms", 50));
end

offeredDLMat = localExpandTrafficBits(sixgr.util.structGet(traffic, "OfferedBitsDL", zeros(nSlots,nUE)), nSlots, nUE, "OfferedBitsDL");
offeredULMat = localExpandTrafficBits(sixgr.util.structGet(traffic, "OfferedBitsUL", zeros(nSlots,nUE)), nSlots, nUE, "OfferedBitsUL");
offeredDLMat = max(0, round(double(offeredDLMat)));
offeredULMat = max(0, round(double(offeredULMat)));

flowDirCfg = upper(string(sixgr.util.structGet(traffic, "FlowDirection", sixgr.util.structGet(cfgE, "traffic.flowDirection", "BIDIR"))));
if flowDirCfg == "DL"
    offeredULMat(:) = 0;
elseif flowDirCfg == "UL"
    offeredDLMat(:) = 0;
end
offeredMat = offeredDLMat + offeredULMat;
qfi = double(sixgr.util.structGet(cfgE, "traffic.qos.default5QI", 9));
lcidData = 4;

slotIndex = (1:nSlots).';
slotDirection = strings(nSlots,1);
slotDL = false(nSlots,1);
slotUL = false(nSlots,1);
for t = 1:nSlots
    [slotDL(t), slotUL(t), slotDirection(t)] = localSlotDuplexStateE2E(cfgE, t);
    if flowDirCfg == "DL"
        slotUL(t) = false;
        slotDirection(t) = "DL";
    elseif flowDirCfg == "UL"
        slotDL(t) = false;
        slotDirection(t) = "UL";
    end
end

[attachOK, attachSlots, attachMsgCount, attachRNTI, attachTraceRows] = localRunRRCAttachProcedure(cfgE);
if strictValidation && ~attachOK
    error("sixgr:e2e:AttachFailedStrict", "Strict validation requires successful attach before data scheduling.");
end
if logical(attachOK) && isfinite(double(attachSlots))
    attachGateSlots = min(nSlots, max(0, round(double(attachSlots))));
else
    attachGateSlots = nSlots;
end
if attachGateSlots > 0
    slotDL(1:attachGateSlots) = false;
    slotUL(1:attachGateSlots) = false;
end

nRB = double(sixgr.util.structGet(cfgE, "phy.carrier.NSizeGrid", 51));
if ~(isfinite(nRB) && nRB >= 1)
    nRB = 51;
end
serviceDLBits = max(800, round((nRB * 12 * 12 * 2.0 * 0.55) * double(serviceScale)));
serviceULBits = max(800, round((nRB * 12 * 12 * 2.0 * 0.48) * double(serviceScale)));

if exist("sixgr_e2e_fast_core_kernel_mex","file") == 3
    [delBitsDL, delBitsUL, ackDL, ackUL, nackDL, nackUL, grDL, grUL, retxDL, retxUL, qDL, qUL, meanCQI] = ...
        sixgr_e2e_fast_core_kernel_mex(offeredDLMat, offeredULMat, slotDL, slotUL, serviceDLBits, serviceULBits, snr_dB, snr_dB + ulSnrOffset_dB);
else
    [delBitsDL, delBitsUL, ackDL, ackUL, nackDL, nackUL, grDL, grUL, retxDL, retxUL, qDL, qUL, meanCQI] = ...
        sixgr_e2e_fast_core_kernel(offeredDLMat, offeredULMat, slotDL, slotUL, serviceDLBits, serviceULBits, snr_dB, snr_dB + ulSnrOffset_dB);
end

offeredBitsDL = sum(offeredDLMat, 2);
offeredBitsUL = sum(offeredULMat, 2);
offeredBits = offeredBitsDL + offeredBitsUL;
deliveredBitsDL = delBitsDL;
deliveredBitsUL = delBitsUL;
deliveredBits = deliveredBitsDL + deliveredBitsUL;
grantCountDL = grDL;
grantCountUL = grUL;
grantCount = grantCountDL + grantCountUL;
ackCountDL = ackDL;
ackCountUL = ackUL;
ackCount = ackCountDL + ackCountUL;
nackCountDL = nackDL;
nackCountUL = nackUL;
nackCount = nackCountDL + nackCountUL;
retxCountDL = retxDL;
retxCountUL = retxUL;
retxCount = retxCountDL + retxCountUL;
queueBitsDL = qDL;
queueBitsUL = qUL;
queueBits = queueBitsDL + queueBitsUL;
goodputDL_Mbps = (deliveredBitsDL / max(slotDur_s, eps)) / 1e6;
goodputUL_Mbps = (deliveredBitsUL / max(slotDur_s, eps)) / 1e6;
goodput_Mbps = goodputDL_Mbps + goodputUL_Mbps;

simDur_s = nSlots * slotDur_s;
totalOfferedBitsDL = sum(offeredBitsDL);
totalOfferedBitsUL = sum(offeredBitsUL);
totalOfferedBits = totalOfferedBitsDL + totalOfferedBitsUL;
totalDeliveredBitsDL = sum(deliveredBitsDL);
totalDeliveredBitsUL = sum(deliveredBitsUL);
totalDeliveredBits = totalDeliveredBitsDL + totalDeliveredBitsUL;
offered_Mbps = totalOfferedBits / max(simDur_s, eps) / 1e6;
offeredDL_Mbps = totalOfferedBitsDL / max(simDur_s, eps) / 1e6;
offeredUL_Mbps = totalOfferedBitsUL / max(simDur_s, eps) / 1e6;
goodput_Mbps_total = totalDeliveredBits / max(simDur_s, eps) / 1e6;
goodputDL_Mbps_total = totalDeliveredBitsDL / max(simDur_s, eps) / 1e6;
goodputUL_Mbps_total = totalDeliveredBitsUL / max(simDur_s, eps) / 1e6;
deliveryRatio = totalDeliveredBits / max(totalOfferedBits, 1);
deliveryRatioDL = totalDeliveredBitsDL / max(totalOfferedBitsDL, 1);
deliveryRatioUL = totalDeliveredBitsUL / max(totalOfferedBitsUL, 1);
retxProb = sum(retxCount) / max(sum(grantCount), 1);
retxProbDL = sum(retxCountDL) / max(sum(grantCountDL), 1);
retxProbUL = sum(retxCountUL) / max(sum(grantCountUL), 1);
ackRate = sum(ackCount) / max(sum(grantCount), 1);
ackRateDL = sum(ackCountDL) / max(sum(grantCountDL), 1);
ackRateUL = sum(ackCountUL) / max(sum(grantCountUL), 1);
nackRate = sum(nackCount) / max(sum(grantCount), 1);
nackRateDL = sum(nackCountDL) / max(sum(grantCountDL), 1);
nackRateUL = sum(nackCountUL) / max(sum(grantCountUL), 1);

offUE = sum(offeredMat,1).';
delUE = zeros(nUE,1);
if sum(offUE) > 0
    delUE = totalDeliveredBits * offUE / sum(offUE);
end
jain = (sum(delUE)^2) / max(nUE * sum(delUE.^2), eps);

fddFrac = mean(slotDirection == "FDD_DLUL");
dlFrac = mean(slotDirection == "DL");
ulFrac = mean(slotDirection == "UL");
spFrac = mean(slotDirection == "S");
airModel = localBuildE2EAirModel(cfgE, fileparts(runFolder), opt, e2eAirLUT);
airModelName = "fast_proxy_kernel";
airModelSource = "queue_cqi_logistic_proxy|" + string(sixgr.util.structGet(airModel, "Source", "default"));

slotTable = table(slotIndex, string(slotDirection), ...
    offeredBits, offeredBitsDL, offeredBitsUL, ...
    deliveredBits, deliveredBitsDL, deliveredBitsUL, ...
    grantCount, grantCountDL, grantCountUL, ...
    ackCount, ackCountDL, ackCountUL, ...
    nackCount, nackCountDL, nackCountUL, ...
    retxCount, retxCountDL, retxCountUL, ...
    meanCQI, queueBits, queueBitsDL, queueBitsUL, ...
    goodput_Mbps, goodputDL_Mbps, goodputUL_Mbps, ...
    'VariableNames', {'Slot','SlotDirection', ...
                      'OfferedBits','OfferedBitsDL','OfferedBitsUL', ...
                      'DeliveredBits','DeliveredBitsDL','DeliveredBitsUL', ...
                      'NumGrants','NumGrantsDL','NumGrantsUL', ...
                      'NumACK','NumACK_DL','NumACK_UL', ...
                      'NumNACK','NumNACK_DL','NumNACK_UL', ...
                      'NumRetx','NumRetx_DL','NumRetx_UL', ...
                      'MeanCQI','QueueBits','QueueBitsDL','QueueBitsUL', ...
                      'Goodput_Mbps','GoodputDL_Mbps','GoodputUL_Mbps'});

dlAppIn = floor(offeredBitsDL/8);
ulAppIn = floor(offeredBitsUL/8);
dlAppOut = floor(deliveredBitsDL/8);
ulAppOut = floor(deliveredBitsUL/8);
dlSdap = dlAppIn + ceil(dlAppIn/1000);
ulSdap = ulAppIn + ceil(ulAppIn/1000);
dlPdcp = dlSdap + ceil(dlSdap/1500)*2;
ulPdcp = ulSdap + ceil(ulSdap/1500)*2;
dlRlcTx = min(dlPdcp, floor(grantCountDL*serviceDLBits/8));
ulRlcTx = min(ulPdcp, floor(grantCountUL*serviceULBits/8));
dlMacTx = dlRlcTx + 8*grantCountDL;
ulMacTx = ulRlcTx + 8*grantCountUL;
dlAirRx = floor(dlMacTx .* (ackCountDL ./ max(grantCountDL,1)));
ulAirRx = floor(ulMacTx .* (ackCountUL ./ max(grantCountUL,1)));
dlDisasm = floor(0.92 * dlAirRx);
ulDisasm = floor(0.92 * ulAirRx);
dlRlcRx = floor(0.82 * dlDisasm);
ulRlcRx = floor(0.82 * ulDisasm);
dlPdcpRx = min(dlRlcRx, dlAppOut + min(32, dlAppOut*0 + 16));
ulPdcpRx = min(ulRlcRx, ulAppOut + min(32, ulAppOut*0 + 16));
dlAppOutIO = min(dlAppOut, dlPdcpRx);
ulAppOutIO = min(ulAppOut, ulPdcpRx);

componentIOTable = table(slotIndex, string(slotDirection), ...
    dlAppIn, dlSdap, dlPdcp, dlRlcTx, dlMacTx, dlAirRx, dlDisasm, dlRlcRx, dlPdcpRx, dlAppOutIO, ...
    ulAppIn, ulSdap, ulPdcp, ulRlcTx, ulMacTx, ulAirRx, ulDisasm, ulRlcRx, ulPdcpRx, ulAppOutIO, ...
    'VariableNames', {'Slot','SlotDirection', ...
                      'DL_AppIn_Bytes','DL_SDAP_TxOut_Bytes','DL_PDCP_TxOut_Bytes','DL_RLC_TxOut_Bytes','DL_MAC_TBOut_Bytes', ...
                      'DL_Air_RxIn_Bytes','DL_MAC_DisasmOut_Bytes','DL_RLC_RxOut_Bytes','DL_PDCP_RxOut_Bytes','DL_AppOut_Bytes', ...
                      'UL_AppIn_Bytes','UL_SDAP_TxOut_Bytes','UL_PDCP_TxOut_Bytes','UL_RLC_TxOut_Bytes','UL_MAC_TBOut_Bytes', ...
                      'UL_Air_RxIn_Bytes','UL_MAC_DisasmOut_Bytes','UL_RLC_RxOut_Bytes','UL_PDCP_RxOut_Bytes','UL_AppOut_Bytes'});

appChunk = max(512, round(double(sixgr.util.structGet(cfgE, "traffic.rlcSduChunk_bytes", 32768))));
genDL = max(0, round(sum(dlAppIn) / max(appChunk,1)));
genUL = max(0, round(sum(ulAppIn) / max(appChunk,1)));
delDL = max(0, round(sum(dlAppOutIO) / max(appChunk,1)));
delUL = max(0, round(sum(ulAppOutIO) / max(appChunk,1)));
generatedPktsDL_UE = repmat(round(genDL/max(nUE,1)), nUE, 1);
generatedPktsUL_UE = repmat(round(genUL/max(nUE,1)), nUE, 1);
deliveredPktsDL_UE = repmat(round(delDL/max(nUE,1)), nUE, 1);
deliveredPktsUL_UE = repmat(round(delUL/max(nUE,1)), nUE, 1);
deadlineMissPktsDL_UE = zeros(nUE,1);
deadlineMissPktsUL_UE = zeros(nUE,1);
duplicatePktsDL_UE = zeros(nUE,1);
duplicatePktsUL_UE = zeros(nUE,1);
reorderedPktsDL_UE = zeros(nUE,1);
reorderedPktsUL_UE = zeros(nUE,1);
latencySamplesDL_ms = 1e3 * slotDur_s * ones(max(delDL,1),1);
latencySamplesUL_ms = 1e3 * slotDur_s * ones(max(delUL,1),1);
pdb_ms = double(sixgr.util.structGet(traffic, "PacketDelayBudget_ms", sixgr.util.structGet(cfgE, "traffic.packetDelayBudget_ms", 50)));
[packetIntegrityTable, semanticPassRate] = localBuildE2EPacketIntegrityTable( ...
    generatedPktsDL_UE, deliveredPktsDL_UE, deadlineMissPktsDL_UE, ...
    duplicatePktsDL_UE, reorderedPktsDL_UE, latencySamplesDL_ms, ...
    generatedPktsUL_UE, deliveredPktsUL_UE, deadlineMissPktsUL_UE, ...
    duplicatePktsUL_UE, reorderedPktsUL_UE, latencySamplesUL_ms, pdb_ms);
traceMode = lower(string(sixgr.util.structGet(opt, "E2EFastTraceMode", "lite")));
if traceMode == "full"
    [packetTraceTable, schedulerTraceTable, harqTraceTable] = localBuildFastE2ESyntheticTraces( ...
        nSlots, nUE, slotDurBase_s, slotDirection, offeredDLMat, offeredULMat, ...
        deliveredBitsDL, deliveredBitsUL, grantCountDL, grantCountUL, ...
        ackCountDL, ackCountUL, nackCountDL, nackCountUL, meanCQI, lcidData, qfi, attachOK);
else
    [packetTraceTable, schedulerTraceTable, harqTraceTable, traceAgg] = localBuildFastE2ESyntheticTracesLite( ...
        nSlots, nUE, slotDurBase_s, slotDirection, offeredDLMat, offeredULMat, ...
        deliveredBitsDL, deliveredBitsUL, grantCountDL, grantCountUL, ...
        ackCountDL, ackCountUL, nackCountDL, nackCountUL, meanCQI, lcidData, qfi, attachOK);
end
attachTraceTable = localBuildE2EAttachTraceTable(attachTraceRows);
if traceMode == "full"
    [flowSummaryTable, bearerSummaryTable, dropCauseTable] = localBuildE2ETraceSummaries(packetTraceTable, simDur_s);
else
    [flowSummaryTable, bearerSummaryTable, dropCauseTable] = localBuildFastE2ETraceSummariesFromAgg( ...
        traceAgg, simDur_s, slotDurBase_s, lcidData, qfi, attachOK);
end

checkTable = localBuildE2EComponentChecks(componentIOTable, packetIntegrityTable);
passRate = 100 * mean(double(checkTable.Pass));

summaryTable = table(string(trafficModel), string(sixgr.util.structGet(traffic, "Transport", "UDP")), string(flowDirCfg), pdb_ms, ...
    string(sixgr.util.structGet(cfgE, "scenario.duplexMode", "TDD")), ...
    string(sixgr.util.structGet(cfgE, "phy.waveform.dl", "CP-OFDM")), ...
    string(sixgr.util.structGet(cfgE, "phy.waveform.ul", "CP-OFDM")), ...
    nUE, nSlots, 1e3*slotDur_s, compression, double(opt.E2EDuration_s), simDur_s, ...
    offered_Mbps, offeredDL_Mbps, offeredUL_Mbps, ...
    goodput_Mbps_total, goodputDL_Mbps_total, goodputUL_Mbps_total, ...
    deliveryRatio, deliveryRatioDL, deliveryRatioUL, ...
    retxProb, retxProbDL, retxProbUL, ...
    ackRate, ackRateDL, ackRateUL, ...
    nackRate, nackRateDL, nackRateUL, ...
    jain, fddFrac, dlFrac, ulFrac, spFrac, ...
    attachOK, attachSlots, attachMsgCount, attachRNTI, ...
    serviceScale, airModelName, airModelSource, logical(opt.E2EStrictValidation), semanticPassRate, ...
    'VariableNames', {'TrafficModel','Transport','FlowDirection','PacketDelayBudget_ms', ...
                      'DuplexMode','WaveformDL','WaveformUL', ...
                      'NumUE','NumSlots','SlotDuration_ms','TimeCompressionFactor', ...
                      'RequestedDuration_s','SimulatedDuration_s', ...
                      'Offered_Mbps','OfferedDL_Mbps','OfferedUL_Mbps', ...
                      'Goodput_Mbps','GoodputDL_Mbps','GoodputUL_Mbps', ...
                      'DeliveryRatio','DeliveryRatioDL','DeliveryRatioUL', ...
                      'HARQ_RetxProbability','HARQ_RetxProbabilityDL','HARQ_RetxProbabilityUL', ...
                      'ACKRate','ACKRateDL','ACKRateUL', ...
                      'NACKRate','NACKRateDL','NACKRateUL', ...
                      'JainFairness','FDDSlotFraction','DLSlotFraction','ULSlotFraction','SpecialSlotFraction', ...
                      'AttachSuccess','AttachSlots','AttachMessages','AttachRNTI', ...
                      'ServiceScaleFactor','E2EAirModel','E2EAirModelSource','StrictValidationMode', ...
                      'SemanticCheckPassRate_pct'});
summaryTable.ComponentCheckPassRate_pct = passRate;
summaryTable.ExecutionBackend = repmat("FAST_PROXY_KERNEL", height(summaryTable), 1);
summaryTable.PHYMode = repmat("QUEUE_CQI_LOGISTIC_PROXY", height(summaryTable), 1);

aiTable = localRunE2EAIProbe(cfgE, logical(opt.E2EEnableAI), snr_dB);

sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_packet_trace.csv"), packetTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_flow_summary.csv"), flowSummaryTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_bearer_summary.csv"), bearerSummaryTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_attach_trace.csv"), attachTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_harq_trace.csv"), harqTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_scheduler_trace.csv"), schedulerTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_drop_causes.csv"), dropCauseTable);

sixgr.util.matSave(fullfile(runFolder, "mat", "e2e_probe.mat"), struct( ...
    "slotTable", slotTable, ...
    "componentIOTable", componentIOTable, ...
    "checkTable", checkTable, ...
    "packetIntegrityTable", packetIntegrityTable, ...
    "packetTraceTable", packetTraceTable, ...
    "flowSummaryTable", flowSummaryTable, ...
    "bearerSummaryTable", bearerSummaryTable, ...
    "attachTraceTable", attachTraceTable, ...
    "harqTraceTable", harqTraceTable, ...
    "schedulerTraceTable", schedulerTraceTable, ...
    "dropCauseTable", dropCauseTable, ...
    "summaryTable", summaryTable, ...
    "aiTable", aiTable, ...
    "attach", struct("Ok",attachOK,"Slots",attachSlots,"Messages",attachMsgCount,"RNTI",attachRNTI)));

if logical(opt.E2ESaveFigures)
    localSaveE2EPlots(runFolder, slotTable, packetTraceTable, flowSummaryTable, bearerSummaryTable, ...
        dropCauseTable, harqTraceTable, attachTraceTable, summaryTable);
end

out = struct();
out.Ok = true;
out.RunFolder = runFolder;
out.SlotTable = slotTable;
out.ComponentIOTable = componentIOTable;
out.CheckTable = checkTable;
out.PacketIntegrityTable = packetIntegrityTable;
out.PacketTraceTable = packetTraceTable;
out.FlowSummaryTable = flowSummaryTable;
out.BearerSummaryTable = bearerSummaryTable;
out.AttachTraceTable = attachTraceTable;
out.HARQTraceTable = harqTraceTable;
out.SchedulerTraceTable = schedulerTraceTable;
out.DropCauseTable = dropCauseTable;
out.SummaryTable = summaryTable;
out.AITable = aiTable;
out.Notes = "E2E fast core probe completed (FAST_PROXY_KERNEL, abstraction mode).";
end

function [packetTraceTable, schedulerTraceTable, harqTraceTable] = localBuildFastE2ESyntheticTraces( ...
    nSlots, nUE, slotDur_s, slotDirection, offeredDLMat, offeredULMat, ...
    deliveredBitsDL, deliveredBitsUL, grantCountDL, grantCountUL, ...
    ackCountDL, ackCountUL, nackCountDL, nackCountUL, meanCQI, lcidData, qfi, attachOK)

appChunk = 1500;
pdbSlots = max(1, ceil((50e-3) / max(double(slotDur_s), eps)));
packetRows = repmat(localPacketTraceRowTemplate(), 0, 1);
grantRows = repmat(localE2EGrantTraceRowTemplate(), 0, 1);

virtPktQ_DL = cell(nUE,1);
virtPktQ_UL = cell(nUE,1);
nextPktIdDL = zeros(nUE,1);
nextPktIdUL = zeros(nUE,1);
lastDeliveredPktIdDL = zeros(nUE,1);
lastDeliveredPktIdUL = zeros(nUE,1);
queueBytesDL_UE = zeros(nUE,1);
queueBytesUL_UE = zeros(nUE,1);
for u = 1:nUE
    virtPktQ_DL{u} = localInitVirtualQueue(max(512, 4 * nSlots));
    virtPktQ_UL{u} = localInitVirtualQueue(max(512, 4 * nSlots));
end

for t = 1:nSlots
    for u = 1:nUE
        bytesInDL = floor(max(double(offeredDLMat(t,u)), 0) / 8);
        bytesInUL = floor(max(double(offeredULMat(t,u)), 0) / 8);
        rem = bytesInDL;
        while rem > 0
            chunk = min(rem, appChunk);
            [virtPktQ_DL{u}, nextPktIdDL(u)] = localEnqueueVirtualPacket( ...
                virtPktQ_DL{u}, nextPktIdDL(u), chunk, t, "FlowID", u, "BearerID", lcidData, "QFI", qfi);
            queueBytesDL_UE(u) = queueBytesDL_UE(u) + chunk;
            rem = rem - chunk;
        end
        rem = bytesInUL;
        while rem > 0
            chunk = min(rem, appChunk);
            [virtPktQ_UL{u}, nextPktIdUL(u)] = localEnqueueVirtualPacket( ...
                virtPktQ_UL{u}, nextPktIdUL(u), chunk, t, "FlowID", u, "BearerID", lcidData, "QFI", qfi);
            queueBytesUL_UE(u) = queueBytesUL_UE(u) + chunk;
            rem = rem - chunk;
        end
    end

    delBytesDL = floor(max(double(deliveredBitsDL(t)), 0) / 8);
    delBytesUL = floor(max(double(deliveredBitsUL(t)), 0) / 8);
    allocDL = localProportionalByteAllocation(queueBytesDL_UE, delBytesDL);
    allocUL = localProportionalByteAllocation(queueBytesUL_UE, delBytesUL);

    for u = 1:nUE
        if allocDL(u) > 0
            virtPktQ_DL{u} = localMarkVirtualPacketTx(virtPktQ_DL{u}, allocDL(u), t, 0, true);
            [virtPktQ_DL{u}, semDL] = localConsumeVirtualPackets( ...
                virtPktQ_DL{u}, allocDL(u), t, slotDur_s, pdbSlots, lastDeliveredPktIdDL(u), ...
                "Direction", "DL", "UE", u);
            lastDeliveredPktIdDL(u) = semDL.LastDeliveredId;
            queueBytesDL_UE(u) = max(queueBytesDL_UE(u) - allocDL(u), 0);
            if ~isempty(semDL.PacketRows)
                packetRows = [packetRows; semDL.PacketRows(:)]; %#ok<AGROW>
            end
        end
        if allocUL(u) > 0
            virtPktQ_UL{u} = localMarkVirtualPacketTx(virtPktQ_UL{u}, allocUL(u), t, 0, true);
            [virtPktQ_UL{u}, semUL] = localConsumeVirtualPackets( ...
                virtPktQ_UL{u}, allocUL(u), t, slotDur_s, pdbSlots, lastDeliveredPktIdUL(u), ...
                "Direction", "UL", "UE", u);
            lastDeliveredPktIdUL(u) = semUL.LastDeliveredId;
            queueBytesUL_UE(u) = max(queueBytesUL_UE(u) - allocUL(u), 0);
            if ~isempty(semUL.PacketRows)
                packetRows = [packetRows; semUL.PacketRows(:)]; %#ok<AGROW>
            end
        end
    end

    cqiUse = max(1, min(15, round(double(meanCQI(t)))));
    mcsUse = localFastCQIToMCS(cqiUse);
    nGrDL = max(0, round(double(grantCountDL(t))));
    nGrUL = max(0, round(double(grantCountUL(t))));
    ackDLn = max(0, round(double(ackCountDL(t))));
    ackULn = max(0, round(double(ackCountUL(t))));
    nackDLn = max(0, round(double(nackCountDL(t))));
    nackULn = max(0, round(double(nackCountUL(t))));
    tbsDL = max(1, floor(delBytesDL / max(nGrDL,1)));
    tbsUL = max(1, floor(delBytesUL / max(nGrUL,1)));

    for g = 1:nGrDL
        tr = localE2EGrantTraceRowTemplate();
        tr.Slot = t;
        tr.Time_s = (t - 1) * slotDur_s;
        tr.Direction = "DL";
        tr.UE = mod(g-1, nUE) + 1;
        tr.FlowID = tr.UE;
        tr.BearerID = lcidData;
        tr.QFI = qfi;
        tr.GrantIndex = g;
        tr.NumPRB = NaN;
        tr.TBSBytes = tbsDL;
        tr.CQIUsed = cqiUse;
        tr.MCSIndex = mcsUse;
        tr.NumLayers = 1;
        tr.TargetCodeRate = 0.5;
        tr.QueueBytesBefore = NaN;
        tr.QueueBytesAfter = NaN;
        tr.HARQProcess = mod(g-1, 16);
        tr.RetxDepthBefore = double(g <= nackDLn);
        tr.RetxDepthAfter = double(g <= nackDLn);
        tr.AttemptCount = tr.RetxDepthBefore + 1;
        tr.IsRetransmission = logical(g <= nackDLn);
        tr.Ack = logical(g <= ackDLn);
        tr.CRCResult = tr.Ack;
        tr.BLER = double(~tr.Ack);
        tr.AirMode = "fast_proxy";
        tr.Note = "synthetic_from_fast_kernel";
        tr.GrantReason = "fast_proxy";
        grantRows(end+1,1) = tr; %#ok<AGROW>
    end
    for g = 1:nGrUL
        tr = localE2EGrantTraceRowTemplate();
        tr.Slot = t;
        tr.Time_s = (t - 1) * slotDur_s;
        tr.Direction = "UL";
        tr.UE = mod(g-1, nUE) + 1;
        tr.FlowID = tr.UE;
        tr.BearerID = lcidData;
        tr.QFI = qfi;
        tr.GrantIndex = g;
        tr.NumPRB = NaN;
        tr.TBSBytes = tbsUL;
        tr.CQIUsed = cqiUse;
        tr.MCSIndex = mcsUse;
        tr.NumLayers = 1;
        tr.TargetCodeRate = 0.5;
        tr.QueueBytesBefore = NaN;
        tr.QueueBytesAfter = NaN;
        tr.HARQProcess = mod(g-1, 16);
        tr.RetxDepthBefore = double(g <= nackULn);
        tr.RetxDepthAfter = double(g <= nackULn);
        tr.AttemptCount = tr.RetxDepthBefore + 1;
        tr.IsRetransmission = logical(g <= nackULn);
        tr.Ack = logical(g <= ackULn);
        tr.CRCResult = tr.Ack;
        tr.BLER = double(~tr.Ack);
        tr.AirMode = "fast_proxy";
        tr.Note = "synthetic_from_fast_kernel";
        tr.GrantReason = "fast_proxy";
        grantRows(end+1,1) = tr; %#ok<AGROW>
    end
end

finalDropCause = "not_delivered_by_end";
if ~attachOK
    finalDropCause = "attach_not_connected";
end
for u = 1:nUE
    [virtPktQ_DL{u}, drDL] = localFinalizeVirtualQueueDrops(virtPktQ_DL{u}, nSlots, slotDur_s, pdbSlots, lastDeliveredPktIdDL(u), "DL", u, finalDropCause);
    if ~isempty(drDL), packetRows = [packetRows; drDL(:)]; end %#ok<AGROW>
    [virtPktQ_UL{u}, drUL] = localFinalizeVirtualQueueDrops(virtPktQ_UL{u}, nSlots, slotDur_s, pdbSlots, lastDeliveredPktIdUL(u), "UL", u, finalDropCause);
    if ~isempty(drUL), packetRows = [packetRows; drUL(:)]; end %#ok<AGROW>
end

packetTraceTable = localPacketTraceRowsToTable(packetRows);
[schedulerTraceTable, harqTraceTable] = localBuildE2EGrantTraceTables(grantRows);
if ~isempty(packetTraceTable)
    packetTraceTable.TraceMode = repmat("FAST_PROXY_SYNTHETIC", height(packetTraceTable), 1);
end
if ~isempty(schedulerTraceTable)
    schedulerTraceTable.TraceMode = repmat("FAST_PROXY_SYNTHETIC", height(schedulerTraceTable), 1);
end
if ~isempty(harqTraceTable)
    harqTraceTable.TraceMode = repmat("FAST_PROXY_SYNTHETIC", height(harqTraceTable), 1);
end
end

function [packetTraceTable, schedulerTraceTable, harqTraceTable, traceAgg] = localBuildFastE2ESyntheticTracesLite( ...
    nSlots, nUE, slotDur_s, slotDirection, offeredDLMat, offeredULMat, ...
    deliveredBitsDL, deliveredBitsUL, grantCountDL, grantCountUL, ...
    ackCountDL, ackCountUL, nackCountDL, nackCountUL, meanCQI, lcidData, qfi, attachOK)

capPkt = max(4096, min(max(4, round(double(nSlots) * double(nUE) * 2)), 2e6));
pkt = localInitFastPacketBuffer(capPkt);
traceAgg = localInitFastTraceAgg(nUE);
nextPktIdDL = zeros(nUE,1);
nextPktIdUL = zeros(nUE,1);
dropCauseNoAttach = "attach_not_connected";
dropCauseSlot = "not_delivered_by_slot";

for t = 1:nSlots
    genDLBytes = floor(max(double(offeredDLMat(t,:)), 0) / 8);
    genULBytes = floor(max(double(offeredULMat(t,:)), 0) / 8);
    delBytesDL = floor(max(double(deliveredBitsDL(t)), 0) / 8);
    delBytesUL = floor(max(double(deliveredBitsUL(t)), 0) / 8);
    allocDL = localProportionalByteAllocation(genDLBytes(:), delBytesDL).';
    allocUL = localProportionalByteAllocation(genULBytes(:), delBytesUL).';
    if ~attachOK
        allocDL(:) = 0;
        allocUL(:) = 0;
    end

    gDL = max(0, round(double(genDLBytes(:))));
    aDL = max(0, round(double(allocDL(:))));
    dDL = min(gDL, aDL);
    rDL = max(gDL - dDL, 0);
    traceAgg.GeneratedBytesDL_UE = traceAgg.GeneratedBytesDL_UE + gDL;
    traceAgg.DeliveredBytesDL_UE = traceAgg.DeliveredBytesDL_UE + dDL;
    traceAgg.DroppedBytesDL_UE = traceAgg.DroppedBytesDL_UE + rDL;
    traceAgg.GeneratedPacketsDL_UE = traceAgg.GeneratedPacketsDL_UE + double(dDL > 0) + double(rDL > 0);
    traceAgg.DeliveredPacketsDL_UE = traceAgg.DeliveredPacketsDL_UE + double(dDL > 0);
    traceAgg.DroppedPacketsDL_UE = traceAgg.DroppedPacketsDL_UE + double(rDL > 0);

    gUL = max(0, round(double(genULBytes(:))));
    aUL = max(0, round(double(allocUL(:))));
    dUL = min(gUL, aUL);
    rUL = max(gUL - dUL, 0);
    traceAgg.GeneratedBytesUL_UE = traceAgg.GeneratedBytesUL_UE + gUL;
    traceAgg.DeliveredBytesUL_UE = traceAgg.DeliveredBytesUL_UE + dUL;
    traceAgg.DroppedBytesUL_UE = traceAgg.DroppedBytesUL_UE + rUL;
    traceAgg.GeneratedPacketsUL_UE = traceAgg.GeneratedPacketsUL_UE + double(dUL > 0) + double(rUL > 0);
    traceAgg.DeliveredPacketsUL_UE = traceAgg.DeliveredPacketsUL_UE + double(dUL > 0);
    traceAgg.DroppedPacketsUL_UE = traceAgg.DroppedPacketsUL_UE + double(rUL > 0);

    [pkt, nextPktIdDL] = localAppendFastPacketDirectionRows( ...
        pkt, nextPktIdDL, "DL", t, slotDur_s, genDLBytes, allocDL, ...
        lcidData, qfi, attachOK, dropCauseNoAttach, dropCauseSlot);
    [pkt, nextPktIdUL] = localAppendFastPacketDirectionRows( ...
        pkt, nextPktIdUL, "UL", t, slotDur_s, genULBytes, allocUL, ...
        lcidData, qfi, attachOK, dropCauseNoAttach, dropCauseSlot);
end

packetTraceTable = localFastPacketBufferToTable(pkt);
grantBase = localBuildFastGrantBaseTable( ...
    nSlots, nUE, slotDur_s, deliveredBitsDL, deliveredBitsUL, ...
    grantCountDL, grantCountUL, ackCountDL, ackCountUL, ...
    nackCountDL, nackCountUL, meanCQI, lcidData, qfi);
[schedulerTraceTable, harqTraceTable] = localBuildE2EGrantTraceTables(grantBase);
if ~isempty(packetTraceTable)
    packetTraceTable.TraceMode = repmat("FAST_PROXY_SYNTHETIC_LITE", height(packetTraceTable), 1);
end
if ~isempty(schedulerTraceTable)
    schedulerTraceTable.TraceMode = repmat("FAST_PROXY_SYNTHETIC_LITE", height(schedulerTraceTable), 1);
end
if ~isempty(harqTraceTable)
    harqTraceTable.TraceMode = repmat("FAST_PROXY_SYNTHETIC_LITE", height(harqTraceTable), 1);
end
traceAgg.AttachOK = logical(attachOK);
end

function pkt = localInitFastPacketBuffer(cap)
cap = max(1, round(double(cap)));
pkt = struct();
pkt.Count = 0;
pkt.Direction = strings(cap,1);
pkt.UE = zeros(cap,1);
pkt.PacketID = zeros(cap,1);
pkt.FlowID = zeros(cap,1);
pkt.BearerID = zeros(cap,1);
pkt.QFI = zeros(cap,1);
pkt.PacketBytes = zeros(cap,1);
pkt.GenerationSlot = zeros(cap,1);
pkt.GenerationTime_s = zeros(cap,1);
pkt.GrantSlot = zeros(cap,1);
pkt.HARQProcess = zeros(cap,1);
pkt.Attempts = ones(cap,1);
pkt.CRCResult = false(cap,1);
pkt.DeliverySlot = NaN(cap,1);
pkt.DeliveryTime_s = NaN(cap,1);
pkt.Latency_ms = NaN(cap,1);
pkt.DeadlineMiss = false(cap,1);
pkt.DuplicateFlag = false(cap,1);
pkt.ReorderFlag = false(cap,1);
pkt.DropCause = strings(cap,1);
end

function pkt = localEnsureFastPacketBuffer(pkt, need)
if nargin < 2
    need = 1;
end
if need <= 0
    return;
end
cap = numel(pkt.UE);
if pkt.Count + need <= cap
    return;
end
newCap = max(pkt.Count + need, round(1.5 * cap) + 4096);
fn = fieldnames(pkt);
for i = 1:numel(fn)
    name = fn{i};
    if strcmp(name, "Count")
        continue;
    end
    v = pkt.(name);
    if isstring(v)
        v(cap+1:newCap,1) = "";
    elseif islogical(v)
        v(cap+1:newCap,1) = false;
    elseif isnumeric(v)
        if any(strcmp(name, ["DeliverySlot","DeliveryTime_s","Latency_ms"]))
            v(cap+1:newCap,1) = NaN;
        elseif strcmp(name, "Attempts")
            v(cap+1:newCap,1) = 1;
        else
            v(cap+1:newCap,1) = 0;
        end
    else
        v(cap+1:newCap,1) = v(1);
    end
    pkt.(name) = v;
end
end

function [pkt, nextPktId] = localAppendFastPacketDirectionRows( ...
    pkt, nextPktId, direction, slotIdx, slotDur_s, genBytes, allocBytes, ...
    lcidData, qfi, attachOK, dropCauseNoAttach, dropCauseSlot)

g = max(0, round(double(genBytes(:))));
a = max(0, round(double(allocBytes(:))));
d = min(g, a);
r = max(g - d, 0);
slotTime_s = (double(slotIdx) - 1) * double(slotDur_s);
deliveryLatency_ms = 1e3 * double(slotDur_s);

idxDel = find(d > 0);
nDel = numel(idxDel);
if nDel > 0
    pkt = localEnsureFastPacketBuffer(pkt, nDel);
    rows = pkt.Count + (1:nDel);
    pkt.Count = pkt.Count + nDel;
    nextPktId(idxDel) = nextPktId(idxDel) + 1;
    pkt.Direction(rows) = repmat(string(direction), nDel, 1);
    pkt.UE(rows) = idxDel;
    pkt.PacketID(rows) = nextPktId(idxDel);
    pkt.FlowID(rows) = idxDel;
    pkt.BearerID(rows) = double(lcidData);
    pkt.QFI(rows) = double(qfi);
    pkt.PacketBytes(rows) = d(idxDel);
    pkt.GenerationSlot(rows) = double(slotIdx);
    pkt.GenerationTime_s(rows) = slotTime_s;
    pkt.GrantSlot(rows) = double(slotIdx);
    pkt.HARQProcess(rows) = mod(idxDel - 1, 16);
    pkt.Attempts(rows) = 1;
    pkt.CRCResult(rows) = true;
    pkt.DeliverySlot(rows) = double(slotIdx);
    pkt.DeliveryTime_s(rows) = slotTime_s;
    pkt.Latency_ms(rows) = deliveryLatency_ms;
    pkt.DeadlineMiss(rows) = false;
    pkt.DuplicateFlag(rows) = false;
    pkt.ReorderFlag(rows) = false;
    pkt.DropCause(rows) = "";
end

idxDrop = find(r > 0);
nDrop = numel(idxDrop);
if nDrop > 0
    pkt = localEnsureFastPacketBuffer(pkt, nDrop);
    rows = pkt.Count + (1:nDrop);
    pkt.Count = pkt.Count + nDrop;
    nextPktId(idxDrop) = nextPktId(idxDrop) + 1;
    pkt.Direction(rows) = repmat(string(direction), nDrop, 1);
    pkt.UE(rows) = idxDrop;
    pkt.PacketID(rows) = nextPktId(idxDrop);
    pkt.FlowID(rows) = idxDrop;
    pkt.BearerID(rows) = double(lcidData);
    pkt.QFI(rows) = double(qfi);
    pkt.PacketBytes(rows) = r(idxDrop);
    pkt.GenerationSlot(rows) = double(slotIdx);
    pkt.GenerationTime_s(rows) = slotTime_s;
    pkt.GrantSlot(rows) = double(slotIdx);
    pkt.HARQProcess(rows) = mod(idxDrop - 1, 16);
    pkt.Attempts(rows) = 1;
    pkt.CRCResult(rows) = false;
    pkt.DeliverySlot(rows) = NaN;
    pkt.DeliveryTime_s(rows) = NaN;
    pkt.Latency_ms(rows) = NaN;
    pkt.DeadlineMiss(rows) = false;
    pkt.DuplicateFlag(rows) = false;
    pkt.ReorderFlag(rows) = false;
    if attachOK
        pkt.DropCause(rows) = repmat(string(dropCauseSlot), nDrop, 1);
    else
        pkt.DropCause(rows) = repmat(string(dropCauseNoAttach), nDrop, 1);
    end
end
end

function T = localFastPacketBufferToTable(pkt)
if pkt.Count <= 0
    r = localPacketTraceRowTemplate();
    T = struct2table(r);
    T(1,:) = [];
    return;
end
idx = 1:pkt.Count;
T = table( ...
    string(pkt.Direction(idx)), ...
    double(pkt.UE(idx)), ...
    double(pkt.PacketID(idx)), ...
    double(pkt.FlowID(idx)), ...
    double(pkt.BearerID(idx)), ...
    double(pkt.QFI(idx)), ...
    double(pkt.PacketBytes(idx)), ...
    double(pkt.GenerationSlot(idx)), ...
    double(pkt.GenerationTime_s(idx)), ...
    double(pkt.GrantSlot(idx)), ...
    double(pkt.HARQProcess(idx)), ...
    double(pkt.Attempts(idx)), ...
    logical(pkt.CRCResult(idx)), ...
    double(pkt.DeliverySlot(idx)), ...
    double(pkt.DeliveryTime_s(idx)), ...
    double(pkt.Latency_ms(idx)), ...
    logical(pkt.DeadlineMiss(idx)), ...
    logical(pkt.DuplicateFlag(idx)), ...
    logical(pkt.ReorderFlag(idx)), ...
    string(pkt.DropCause(idx)), ...
    'VariableNames', {'Direction','UE','PacketID','FlowID','BearerID','QFI','PacketBytes', ...
    'GenerationSlot','GenerationTime_s','GrantSlot','HARQProcess','Attempts','CRCResult', ...
    'DeliverySlot','DeliveryTime_s','Latency_ms','DeadlineMiss','DuplicateFlag','ReorderFlag','DropCause'});
end

function base = localBuildFastGrantBaseTable( ...
    nSlots, nUE, slotDur_s, deliveredBitsDL, deliveredBitsUL, ...
    grantCountDL, grantCountUL, ackCountDL, ackCountUL, ...
    nackCountDL, nackCountUL, meanCQI, lcidData, qfi)

totDL = sum(max(0, round(double(grantCountDL(:)))));
totUL = sum(max(0, round(double(grantCountUL(:)))));
tot = round(double(totDL + totUL));
if tot <= 0
    r = localE2EGrantTraceRowTemplate();
    base = struct2table(r);
    base(1,:) = [];
    return;
end

Slot = zeros(tot,1);
Time_s = zeros(tot,1);
Direction = strings(tot,1);
UE = zeros(tot,1);
FlowID = zeros(tot,1);
BearerID = zeros(tot,1);
QFI = zeros(tot,1);
GrantIndex = zeros(tot,1);
NumPRB = NaN(tot,1);
TBSBytes = zeros(tot,1);
CQIUsed = zeros(tot,1);
MCSIndex = zeros(tot,1);
NumLayers = ones(tot,1);
TargetCodeRate = 0.5 * ones(tot,1);
QueueBytesBefore = NaN(tot,1);
QueueBytesAfter = NaN(tot,1);
HARQProcess = zeros(tot,1);
RetxDepthBefore = zeros(tot,1);
RetxDepthAfter = zeros(tot,1);
AttemptCount = ones(tot,1);
IsRetransmission = false(tot,1);
Ack = false(tot,1);
CRCResult = false(tot,1);
BLER = zeros(tot,1);
AirMode = repmat("fast_proxy", tot, 1);
Note = repmat("synthetic_from_fast_kernel_lite", tot, 1);
GrantReason = repmat("fast_proxy_lite", tot, 1);

w = 0;
for t = 1:nSlots
    cqiUse = max(1, min(15, round(double(meanCQI(t)))));
    mcsUse = localFastCQIToMCS(cqiUse);
    nGrDL = max(0, round(double(grantCountDL(t))));
    nGrUL = max(0, round(double(grantCountUL(t))));
    ackDLn = max(0, round(double(ackCountDL(t))));
    ackULn = max(0, round(double(ackCountUL(t))));
    nackDLn = max(0, round(double(nackCountDL(t))));
    nackULn = max(0, round(double(nackCountUL(t))));
    delBytesDL = floor(max(double(deliveredBitsDL(t)), 0) / 8);
    delBytesUL = floor(max(double(deliveredBitsUL(t)), 0) / 8);
    tbsDL = max(1, floor(delBytesDL / max(nGrDL, 1)));
    tbsUL = max(1, floor(delBytesUL / max(nGrUL, 1)));

    if nGrDL > 0
        idx = w + (1:nGrDL);
        g = (1:nGrDL).';
        ue = mod(g - 1, nUE) + 1;
        isRetx = (g <= nackDLn);
        ackVec = (g <= ackDLn);
        Slot(idx) = t;
        Time_s(idx) = (t - 1) * slotDur_s;
        Direction(idx) = "DL";
        UE(idx) = ue;
        FlowID(idx) = ue;
        BearerID(idx) = double(lcidData);
        QFI(idx) = double(qfi);
        GrantIndex(idx) = g;
        TBSBytes(idx) = tbsDL;
        CQIUsed(idx) = cqiUse;
        MCSIndex(idx) = mcsUse;
        HARQProcess(idx) = mod(g - 1, 16);
        RetxDepthBefore(idx) = double(isRetx);
        RetxDepthAfter(idx) = double(isRetx);
        AttemptCount(idx) = 1 + double(isRetx);
        IsRetransmission(idx) = logical(isRetx);
        Ack(idx) = logical(ackVec);
        CRCResult(idx) = logical(ackVec);
        BLER(idx) = double(~ackVec);
        w = w + nGrDL;
    end
    if nGrUL > 0
        idx = w + (1:nGrUL);
        g = (1:nGrUL).';
        ue = mod(g - 1, nUE) + 1;
        isRetx = (g <= nackULn);
        ackVec = (g <= ackULn);
        Slot(idx) = t;
        Time_s(idx) = (t - 1) * slotDur_s;
        Direction(idx) = "UL";
        UE(idx) = ue;
        FlowID(idx) = ue;
        BearerID(idx) = double(lcidData);
        QFI(idx) = double(qfi);
        GrantIndex(idx) = g;
        TBSBytes(idx) = tbsUL;
        CQIUsed(idx) = cqiUse;
        MCSIndex(idx) = mcsUse;
        HARQProcess(idx) = mod(g - 1, 16);
        RetxDepthBefore(idx) = double(isRetx);
        RetxDepthAfter(idx) = double(isRetx);
        AttemptCount(idx) = 1 + double(isRetx);
        IsRetransmission(idx) = logical(isRetx);
        Ack(idx) = logical(ackVec);
        CRCResult(idx) = logical(ackVec);
        BLER(idx) = double(~ackVec);
        w = w + nGrUL;
    end
end

if w < tot
    keep = 1:w;
else
    keep = 1:tot;
end
base = table( ...
    double(Slot(keep)), double(Time_s(keep)), string(Direction(keep)), ...
    double(UE(keep)), double(FlowID(keep)), double(BearerID(keep)), double(QFI(keep)), ...
    double(GrantIndex(keep)), double(NumPRB(keep)), double(TBSBytes(keep)), ...
    double(CQIUsed(keep)), double(MCSIndex(keep)), double(NumLayers(keep)), ...
    double(TargetCodeRate(keep)), double(QueueBytesBefore(keep)), double(QueueBytesAfter(keep)), ...
    double(HARQProcess(keep)), double(RetxDepthBefore(keep)), double(RetxDepthAfter(keep)), ...
    double(AttemptCount(keep)), logical(IsRetransmission(keep)), logical(Ack(keep)), ...
    logical(CRCResult(keep)), double(BLER(keep)), string(AirMode(keep)), ...
    string(Note(keep)), string(GrantReason(keep)), ...
    'VariableNames', {'Slot','Time_s','Direction','UE','FlowID','BearerID','QFI','GrantIndex', ...
    'NumPRB','TBSBytes','CQIUsed','MCSIndex','NumLayers','TargetCodeRate', ...
    'QueueBytesBefore','QueueBytesAfter','HARQProcess','RetxDepthBefore','RetxDepthAfter', ...
    'AttemptCount','IsRetransmission','Ack','CRCResult','BLER','AirMode','Note','GrantReason'});
end

function agg = localInitFastTraceAgg(nUE)
nUE = max(1, round(double(nUE)));
agg = struct();
agg.GeneratedBytesDL_UE = zeros(nUE,1);
agg.DeliveredBytesDL_UE = zeros(nUE,1);
agg.DroppedBytesDL_UE = zeros(nUE,1);
agg.GeneratedPacketsDL_UE = zeros(nUE,1);
agg.DeliveredPacketsDL_UE = zeros(nUE,1);
agg.DroppedPacketsDL_UE = zeros(nUE,1);
agg.GeneratedBytesUL_UE = zeros(nUE,1);
agg.DeliveredBytesUL_UE = zeros(nUE,1);
agg.DroppedBytesUL_UE = zeros(nUE,1);
agg.GeneratedPacketsUL_UE = zeros(nUE,1);
agg.DeliveredPacketsUL_UE = zeros(nUE,1);
agg.DroppedPacketsUL_UE = zeros(nUE,1);
agg.AttachOK = true;
end

function [flowSummary, bearerSummary, dropCauses] = localBuildFastE2ETraceSummariesFromAgg( ...
    agg, simDur_s, slotDur_s, lcidData, qfi, attachOK)
nUE = numel(agg.GeneratedBytesDL_UE);
ue = (1:nUE).';
lat_ms = 1e3 * double(slotDur_s);
dirs = [repmat("DL", nUE, 1); repmat("UL", nUE, 1)];
flowSummary = table( ...
    dirs, [ue; ue], [ue; ue], ...
    repmat(double(lcidData), 2*nUE, 1), repmat(double(qfi), 2*nUE, 1), ...
    [double(agg.GeneratedPacketsDL_UE); double(agg.GeneratedPacketsUL_UE)], ...
    [double(agg.DeliveredPacketsDL_UE); double(agg.DeliveredPacketsUL_UE)], ...
    [double(agg.DroppedPacketsDL_UE); double(agg.DroppedPacketsUL_UE)], ...
    zeros(2*nUE,1), ...
    NaN(2*nUE,1), NaN(2*nUE,1), ...
    zeros(2*nUE,1), zeros(2*nUE,1), zeros(2*nUE,1), ...
    [double(agg.GeneratedBytesDL_UE); double(agg.GeneratedBytesUL_UE)], ...
    [double(agg.DeliveredBytesDL_UE); double(agg.DeliveredBytesUL_UE)], ...
    [double(agg.DroppedBytesDL_UE); double(agg.DroppedBytesUL_UE)], ...
    zeros(2*nUE,1), ...
    'VariableNames', {'Direction','FlowID','UE','BearerID','QFI', ...
    'GeneratedPackets','DeliveredPackets','DroppedPackets','PacketDeliveryRatio', ...
    'MeanLatency_ms','P95Latency_ms','DeadlineMissPackets','DuplicatePackets','ReorderPackets', ...
    'GeneratedBytes','DeliveredBytes','DroppedBytes','Goodput_Mbps'});

genPk = flowSummary.GeneratedPackets;
delPk = flowSummary.DeliveredPackets;
flowSummary.PacketDeliveryRatio = delPk ./ max(genPk, 1);
hasDelivered = delPk > 0;
flowSummary.MeanLatency_ms(hasDelivered) = lat_ms;
flowSummary.P95Latency_ms(hasDelivered) = lat_ms;
flowSummary.Goodput_Mbps = (8 * flowSummary.DeliveredBytes) ./ max(double(simDur_s), eps) / 1e6;

genDLPk = sum(double(agg.GeneratedPacketsDL_UE));
delDLPk = sum(double(agg.DeliveredPacketsDL_UE));
drpDLPk = sum(double(agg.DroppedPacketsDL_UE));
genULPk = sum(double(agg.GeneratedPacketsUL_UE));
delULPk = sum(double(agg.DeliveredPacketsUL_UE));
drpULPk = sum(double(agg.DroppedPacketsUL_UE));

genDLBytes = sum(double(agg.GeneratedBytesDL_UE));
delDLBytes = sum(double(agg.DeliveredBytesDL_UE));
drpDLBytes = sum(double(agg.DroppedBytesDL_UE));
genULBytes = sum(double(agg.GeneratedBytesUL_UE));
delULBytes = sum(double(agg.DeliveredBytesUL_UE));
drpULBytes = sum(double(agg.DroppedBytesUL_UE));

bearerSummary = table( ...
    ["DL";"UL"], repmat(double(lcidData),2,1), repmat(double(qfi),2,1), ...
    [genDLPk; genULPk], [delDLPk; delULPk], [drpDLPk; drpULPk], ...
    [delDLPk / max(genDLPk,1); delULPk / max(genULPk,1)], ...
    [genDLBytes; genULBytes], [delDLBytes; delULBytes], [drpDLBytes; drpULBytes], ...
    'VariableNames', {'Direction','BearerID','QFI','GeneratedPackets','DeliveredPackets','DroppedPackets', ...
    'PacketDeliveryRatio','GeneratedBytes','DeliveredBytes','DroppedBytes'});

if attachOK
    cause = "not_delivered_by_slot";
else
    cause = "attach_not_connected";
end
dropCauses = table( ...
    ["DL";"UL"], repmat(string(cause),2,1), [drpDLPk; drpULPk], [drpDLBytes; drpULBytes], ...
    'VariableNames', {'Direction','DropCause','DroppedPackets','DroppedBytes'});
dropCauses = dropCauses(dropCauses.DroppedPackets > 0 | dropCauses.DroppedBytes > 0, :);
if isempty(dropCauses)
    dropCauses = table(string.empty(0,1), string.empty(0,1), [], [], ...
        'VariableNames', {'Direction','DropCause','DroppedPackets','DroppedBytes'});
end
end

function alloc = localProportionalByteAllocation(queueBytes, totalBytes)
queueBytes = max(0, round(double(queueBytes(:))));
totalBytes = max(0, round(double(totalBytes)));
alloc = zeros(size(queueBytes));
if totalBytes <= 0
    return;
end
sumQ = sum(queueBytes);
if sumQ <= 0
    return;
end
raw = (double(totalBytes) * double(queueBytes)) / double(sumQ);
alloc = floor(raw);
alloc = min(alloc, queueBytes);
rem = totalBytes - sum(alloc);
if rem > 0
    frac = raw - floor(raw);
    [~, order] = sort(frac, "descend");
    for i = 1:numel(order)
        k = order(i);
        if rem <= 0
            break;
        end
        room = queueBytes(k) - alloc(k);
        if room <= 0
            continue;
        end
        take = min(room, rem);
        alloc(k) = alloc(k) + take;
        rem = rem - take;
    end
end
end

function bits = localExpandTrafficBits(bitsIn, nSlots, nUE, label)
bits = double(bitsIn);
if isempty(bits)
    bits = zeros(nSlots, nUE);
    return;
end
if isscalar(bits)
    bits = repmat(bits, nSlots, nUE);
elseif isvector(bits)
    if numel(bits) == nUE
        bits = repmat(bits(:).', nSlots, 1);
    elseif numel(bits) == nSlots
        bits = repmat(bits(:), 1, nUE);
    else
        error("sixgr:e2e:TrafficShape", "%s must be scalar, NumUE, NumSlots, or NumSlots x NumUE.", string(label));
    end
end
if size(bits,1) ~= nSlots || size(bits,2) ~= nUE
    error("sixgr:e2e:TrafficShape", "%s must be %d x %d (NumSlots x NumUE).", string(label), nSlots, nUE);
end
bits = max(0, bits);
end

function n = localSumMACSDUPayloadBytes(sduList)
n = 0;
if isempty(sduList) || ~isstruct(sduList)
    return;
end
for i = 1:numel(sduList)
    if isfield(sduList(i), "Payload") && ~isempty(sduList(i).Payload)
        n = n + numel(sduList(i).Payload);
    end
end
end

function b = localMacPayloadBudget(tbsBytes)
b = max(1, round(double(tbsBytes)) - 8);
end

function T = localBuildE2EComponentChecks(componentIOTable, packetIntegrityTable)
if nargin < 2
    packetIntegrityTable = table();
end
sumCol = @(name) sum(max(double(componentIOTable.(name)), 0));
epsTol = 1e-9;

rows = repmat(struct('Direction',"",'Component',"",'InputBytes',0,'OutputBytes',0, ...
    'ExpectedRelation',"",'Pass',false,'Notes',""), 0, 1);

% DL TX chain checks.
rows(end+1,1) = localCheckRow("DL","SDAP_TX", ...
    sumCol("DL_AppIn_Bytes"), sumCol("DL_SDAP_TxOut_Bytes"), ">=", epsTol, ...
    "SDAP output should be >= app input due SDAP header/metadata");
rows(end+1,1) = localCheckRow("DL","PDCP_TX", ...
    sumCol("DL_SDAP_TxOut_Bytes"), sumCol("DL_PDCP_TxOut_Bytes"), ">=", epsTol, ...
    "PDCP output should be >= SDAP payload due PDCP headers");
rows(end+1,1) = localCheckRow("DL","MAC_TX", ...
    sumCol("DL_RLC_TxOut_Bytes"), sumCol("DL_MAC_TBOut_Bytes"), ">=", epsTol, ...
    "MAC TB should be >= RLC payload due MAC subheaders/CE/padding");

% DL RX chain checks.
rows(end+1,1) = localCheckRow("DL","MAC_RX_DISASM", ...
    sumCol("DL_Air_RxIn_Bytes"), sumCol("DL_MAC_DisasmOut_Bytes"), "<=", epsTol, ...
    "Disassembled payload should be <= received MAC TB bytes");
rows(end+1,1) = localCheckRow("DL","RLC_RX", ...
    sumCol("DL_MAC_DisasmOut_Bytes"), sumCol("DL_RLC_RxOut_Bytes"), "<=", epsTol, ...
    "RLC reassembled output should be <= MAC payload bytes");
rows(end+1,1) = localCheckRow("DL","PDCP_RX", ...
    sumCol("DL_RLC_RxOut_Bytes"), sumCol("DL_PDCP_RxOut_Bytes"), "<=", epsTol, ...
    "PDCP output should be <= RLC reassembled bytes");
rows(end+1,1) = localCheckRow("DL","APP_RX", ...
    sumCol("DL_PDCP_RxOut_Bytes"), sumCol("DL_AppOut_Bytes"), "<=", epsTol, ...
    "App delivered bytes should be <= PDCP output bytes");

% UL TX/RX chain checks.
rows(end+1,1) = localCheckRow("UL","SDAP_TX", ...
    sumCol("UL_AppIn_Bytes"), sumCol("UL_SDAP_TxOut_Bytes"), ">=", epsTol, ...
    "SDAP output should be >= app input due SDAP header/metadata");
rows(end+1,1) = localCheckRow("UL","PDCP_TX", ...
    sumCol("UL_SDAP_TxOut_Bytes"), sumCol("UL_PDCP_TxOut_Bytes"), ">=", epsTol, ...
    "PDCP output should be >= SDAP payload due PDCP headers");
rows(end+1,1) = localCheckRow("UL","MAC_TX", ...
    sumCol("UL_RLC_TxOut_Bytes"), sumCol("UL_MAC_TBOut_Bytes"), ">=", epsTol, ...
    "MAC TB should be >= RLC payload due MAC subheaders/CE/padding");
rows(end+1,1) = localCheckRow("UL","MAC_RX_DISASM", ...
    sumCol("UL_Air_RxIn_Bytes"), sumCol("UL_MAC_DisasmOut_Bytes"), "<=", epsTol, ...
    "Disassembled payload should be <= received MAC TB bytes");
rows(end+1,1) = localCheckRow("UL","RLC_RX", ...
    sumCol("UL_MAC_DisasmOut_Bytes"), sumCol("UL_RLC_RxOut_Bytes"), "<=", epsTol, ...
    "RLC reassembled output should be <= MAC payload bytes");
rows(end+1,1) = localCheckRow("UL","PDCP_RX", ...
    sumCol("UL_RLC_RxOut_Bytes"), sumCol("UL_PDCP_RxOut_Bytes"), "<=", epsTol, ...
    "PDCP output should be <= RLC reassembled bytes");
rows(end+1,1) = localCheckRow("UL","APP_RX", ...
    sumCol("UL_PDCP_RxOut_Bytes"), sumCol("UL_AppOut_Bytes"), "<=", epsTol, ...
    "App delivered bytes should be <= PDCP output bytes");

% Semantic checks: packet-level integrity and latency budget compliance.
if ~isempty(packetIntegrityTable) && all(ismember(["Direction","SemanticPass"], string(packetIntegrityTable.Properties.VariableNames)))
    for i = 1:height(packetIntegrityTable)
        dirI = string(packetIntegrityTable.Direction(i));
        if dirI == "ALL"
            continue;
        end
        notes = "Packet semantics: ordering/duplication/deadline checks";
        if ismember("Notes", string(packetIntegrityTable.Properties.VariableNames))
            notes = string(packetIntegrityTable.Notes(i));
        end
        rows(end+1,1) = struct('Direction',dirI,'Component',"SEMANTIC_INTEGRITY", ...
            'InputBytes',0,'OutputBytes',0,'ExpectedRelation',"packet_checks",'Pass',logical(packetIntegrityTable.SemanticPass(i)), ...
            'Notes',notes);
    end
end

% Global non-negativity check.
allNonNeg = true;
for i = 1:width(componentIOTable)
    n = componentIOTable.Properties.VariableNames{i};
    if endsWith(n, "_Bytes")
        allNonNeg = allNonNeg && all(componentIOTable.(n) >= 0);
    end
end
rows(end+1,1) = struct('Direction',"ALL",'Component',"NON_NEGATIVE", ...
    'InputBytes',0,'OutputBytes',0,'ExpectedRelation',"all>=0",'Pass',logical(allNonNeg), ...
    'Notes',"All component byte counters must be non-negative");

T = struct2table(rows);
end

function r = localCheckRow(direction, component, inBytes, outBytes, relation, tol, notes)
r = struct();
r.Direction = string(direction);
r.Component = string(component);
r.InputBytes = double(inBytes);
r.OutputBytes = double(outBytes);
r.ExpectedRelation = string(relation);
switch string(relation)
    case ">="
        r.Pass = (r.OutputBytes + tol >= r.InputBytes);
    case "<="
        r.Pass = (r.OutputBytes <= r.InputBytes + tol);
    otherwise
        r.Pass = false;
end
r.Notes = string(notes);
end

function row = localPacketTraceRowTemplate()
row = struct();
row.Direction = "";
row.UE = NaN;
row.PacketID = NaN;
row.FlowID = NaN;
row.BearerID = NaN;
row.QFI = NaN;
row.PacketBytes = NaN;
row.GenerationSlot = NaN;
row.GenerationTime_s = NaN;
row.GrantSlot = NaN;
row.HARQProcess = NaN;
row.Attempts = NaN;
row.CRCResult = false;
row.DeliverySlot = NaN;
row.DeliveryTime_s = NaN;
row.Latency_ms = NaN;
row.DeadlineMiss = false;
row.DuplicateFlag = false;
row.ReorderFlag = false;
row.DropCause = "";
end

function row = localE2EGrantTraceRowTemplate()
row = struct();
row.Slot = NaN;
row.Time_s = NaN;
row.Direction = "";
row.UE = NaN;
row.FlowID = NaN;
row.BearerID = NaN;
row.QFI = NaN;
row.GrantIndex = NaN;
row.NumPRB = NaN;
row.TBSBytes = NaN;
row.CQIUsed = NaN;
row.MCSIndex = NaN;
row.NumLayers = NaN;
row.TargetCodeRate = NaN;
row.QueueBytesBefore = NaN;
row.QueueBytesAfter = NaN;
row.HARQProcess = NaN;
row.RetxDepthBefore = NaN;
row.RetxDepthAfter = NaN;
row.AttemptCount = NaN;
row.IsRetransmission = false;
row.Ack = false;
row.CRCResult = false;
row.BLER = NaN;
row.AirMode = "";
row.Note = "";
row.GrantReason = "";
end

function T = localPacketTraceRowsToTable(rows)
if isempty(rows)
    r = localPacketTraceRowTemplate();
    T = struct2table(r);
    T(1,:) = [];
    return;
end
T = struct2table(rows);
T.Direction = string(T.Direction);
T.DropCause = string(T.DropCause);
end

function [schedulerTrace, harqTrace] = localBuildE2EGrantTraceTables(rows)
if istable(rows)
    base = rows;
elseif isempty(rows)
    r = localE2EGrantTraceRowTemplate();
    base = struct2table(r);
    base(1,:) = [];
else
    base = struct2table(rows);
end
if isempty(base)
    schedulerTrace = base;
    harqTrace = base;
    return;
end
base.Direction = string(base.Direction);
base.AirMode = string(base.AirMode);
base.Note = string(base.Note);
base.GrantReason = string(base.GrantReason);
schedulerCols = { ...
    'Slot','Time_s','Direction','UE','FlowID','BearerID','QFI','GrantIndex', ...
    'NumPRB','TBSBytes','CQIUsed','MCSIndex','NumLayers','TargetCodeRate', ...
    'QueueBytesBefore','QueueBytesAfter','HARQProcess','IsRetransmission','GrantReason'};
harqCols = { ...
    'Slot','Time_s','Direction','UE','FlowID','HARQProcess','GrantIndex', ...
    'RetxDepthBefore','RetxDepthAfter','AttemptCount','IsRetransmission', ...
    'Ack','CRCResult','BLER','AirMode','Note','TBSBytes'};
schedulerTrace = base(:, schedulerCols);
harqTrace = base(:, harqCols);
end

function T = localBuildE2EAttachTraceTable(rows)
if isempty(rows)
    T = table([], [], string.empty(0,1), string.empty(0,1), string.empty(0,1), [], [], [], [], string.empty(0,1), ...
        'VariableNames', {'Slot','Time_s','Direction','Event','Message','UE','CellID','TempCRNTI','Success','Cause'});
    return;
end
T = struct2table(rows);
T.Direction = string(T.Direction);
T.Event = string(T.Event);
T.Message = string(T.Message);
T.Cause = string(T.Cause);
end

function [flowSummary, bearerSummary, dropCauses] = localBuildE2ETraceSummaries(packetTraceTable, simDur_s)
flowSummary = table(string.empty(0,1), [], [], [], [], [], [], [], [], [], [], [], [], [], [], [], [], [], ...
    'VariableNames', {'Direction','FlowID','UE','BearerID','QFI', ...
    'GeneratedPackets','DeliveredPackets','DroppedPackets','PacketDeliveryRatio', ...
    'MeanLatency_ms','P95Latency_ms','DeadlineMissPackets','DuplicatePackets','ReorderPackets', ...
    'GeneratedBytes','DeliveredBytes','DroppedBytes','Goodput_Mbps'});
bearerSummary = table(string.empty(0,1), [], [], [], [], [], [], [], [], [], ...
    'VariableNames', {'Direction','BearerID','QFI','GeneratedPackets','DeliveredPackets','DroppedPackets', ...
    'PacketDeliveryRatio','GeneratedBytes','DeliveredBytes','DroppedBytes'});
dropCauses = table(string.empty(0,1), string.empty(0,1), [], [], ...
    'VariableNames', {'Direction','DropCause','DroppedPackets','DroppedBytes'});
if isempty(packetTraceTable)
    return;
end
T = packetTraceTable;
if ~ismember("DropCause", string(T.Properties.VariableNames))
    T.DropCause = repmat("", height(T), 1);
end
if ~ismember("PacketBytes", string(T.Properties.VariableNames))
    T.PacketBytes = zeros(height(T),1);
end
isDelivered = strlength(string(T.DropCause)) == 0;

[gFlow, dirFlow, flowId, ueId, bearerId, qfi] = findgroups(string(T.Direction), double(T.FlowID), double(T.UE), double(T.BearerID), double(T.QFI));
nFlow = max(gFlow);
if nFlow > 0
    dirs = strings(nFlow,1);
    flowIds = NaN(nFlow,1);
    ues = NaN(nFlow,1);
    bearers = NaN(nFlow,1);
    qfis = NaN(nFlow,1);
    genPkts = zeros(nFlow,1);
    delPkts = zeros(nFlow,1);
    drpPkts = zeros(nFlow,1);
    missPkts = zeros(nFlow,1);
    dupPkts = zeros(nFlow,1);
    reordPkts = zeros(nFlow,1);
    genBytes = zeros(nFlow,1);
    delBytes = zeros(nFlow,1);
    drpBytes = zeros(nFlow,1);
    meanLat = NaN(nFlow,1);
    p95Lat = NaN(nFlow,1);
    pdr = zeros(nFlow,1);
    goodput = zeros(nFlow,1);
    for gi = 1:nFlow
        idx = (gFlow == gi);
        idxDel = idx & isDelivered;
        idxDrp = idx & ~isDelivered;
        dirs(gi) = dirFlow(gi);
        flowIds(gi) = flowId(gi);
        ues(gi) = ueId(gi);
        bearers(gi) = bearerId(gi);
        qfis(gi) = qfi(gi);
        genPkts(gi) = sum(idx);
        delPkts(gi) = sum(idxDel);
        drpPkts(gi) = sum(idxDrp);
        missPkts(gi) = sum(logical(T.DeadlineMiss(idx)));
        dupPkts(gi) = sum(logical(T.DuplicateFlag(idx)));
        reordPkts(gi) = sum(logical(T.ReorderFlag(idx)));
        genBytes(gi) = sum(double(T.PacketBytes(idx)));
        delBytes(gi) = sum(double(T.PacketBytes(idxDel)));
        drpBytes(gi) = sum(double(T.PacketBytes(idxDrp)));
        lat = double(T.Latency_ms(idxDel));
        lat = lat(isfinite(lat));
        if ~isempty(lat)
            meanLat(gi) = mean(lat);
            p95Lat(gi) = localPercentile(lat, 95);
        end
        pdr(gi) = delPkts(gi) / max(genPkts(gi), 1);
        goodput(gi) = (8 * delBytes(gi)) / max(double(simDur_s), eps) / 1e6;
    end
    flowSummary = table(dirs, flowIds, ues, bearers, qfis, ...
        genPkts, delPkts, drpPkts, pdr, ...
        meanLat, p95Lat, missPkts, dupPkts, reordPkts, ...
        genBytes, delBytes, drpBytes, goodput, ...
        'VariableNames', {'Direction','FlowID','UE','BearerID','QFI', ...
        'GeneratedPackets','DeliveredPackets','DroppedPackets','PacketDeliveryRatio', ...
        'MeanLatency_ms','P95Latency_ms','DeadlineMissPackets','DuplicatePackets','ReorderPackets', ...
        'GeneratedBytes','DeliveredBytes','DroppedBytes','Goodput_Mbps'});
end

[gBearer, dirBearer, bearer, qfiBearer] = findgroups(string(T.Direction), double(T.BearerID), double(T.QFI));
nBearer = max(gBearer);
if nBearer > 0
    dirs = strings(nBearer,1);
    bears = NaN(nBearer,1);
    qfis = NaN(nBearer,1);
    genPkts = zeros(nBearer,1);
    delPkts = zeros(nBearer,1);
    drpPkts = zeros(nBearer,1);
    genBytes = zeros(nBearer,1);
    delBytes = zeros(nBearer,1);
    drpBytes = zeros(nBearer,1);
    pdr = zeros(nBearer,1);
    for gi = 1:nBearer
        idx = (gBearer == gi);
        idxDel = idx & isDelivered;
        idxDrp = idx & ~isDelivered;
        dirs(gi) = dirBearer(gi);
        bears(gi) = bearer(gi);
        qfis(gi) = qfiBearer(gi);
        genPkts(gi) = sum(idx);
        delPkts(gi) = sum(idxDel);
        drpPkts(gi) = sum(idxDrp);
        genBytes(gi) = sum(double(T.PacketBytes(idx)));
        delBytes(gi) = sum(double(T.PacketBytes(idxDel)));
        drpBytes(gi) = sum(double(T.PacketBytes(idxDrp)));
        pdr(gi) = delPkts(gi) / max(genPkts(gi), 1);
    end
    bearerSummary = table(dirs, bears, qfis, genPkts, delPkts, drpPkts, pdr, genBytes, delBytes, drpBytes, ...
        'VariableNames', {'Direction','BearerID','QFI','GeneratedPackets','DeliveredPackets','DroppedPackets', ...
        'PacketDeliveryRatio','GeneratedBytes','DeliveredBytes','DroppedBytes'});
end

dropMask = (strlength(string(T.DropCause)) > 0);
if any(dropMask)
    Td = T(dropMask, :);
    [gDrop, dirDrop, causeDrop] = findgroups(string(Td.Direction), string(Td.DropCause));
    nDrop = max(gDrop);
    dirs = strings(nDrop,1);
    causes = strings(nDrop,1);
    dropPkts = zeros(nDrop,1);
    dropBytes = zeros(nDrop,1);
    for gi = 1:nDrop
        idx = (gDrop == gi);
        dirs(gi) = dirDrop(gi);
        causes(gi) = causeDrop(gi);
        dropPkts(gi) = sum(idx);
        dropBytes(gi) = sum(double(Td.PacketBytes(idx)));
    end
    dropCauses = table(dirs, causes, dropPkts, dropBytes, ...
        'VariableNames', {'Direction','DropCause','DroppedPackets','DroppedBytes'});
else
    dropCauses = table([], string.empty(0,1), [], [], ...
        'VariableNames', {'Direction','DropCause','DroppedPackets','DroppedBytes'});
end
end

function [chunks, count] = localPushStructChunk(chunks, count, rows)
if isempty(rows)
    return;
end
count = count + 1;
if count > numel(chunks)
    chunks{count + 1024, 1} = [];
end
chunks{count, 1} = rows(:);
end

function rows = localConcatStructChunks(chunks, count, templateRow)
if nargin < 3 || isempty(templateRow)
    templateRow = struct();
end
if count <= 0
    rows = repmat(templateRow, 0, 1);
    return;
end
rows = vertcat(chunks{1:count});
rows = rows(:);
end

function [q, nextId] = localEnqueueVirtualPacket(q, nextId, bytes, slotIdx, varargin)
if nargin < 1 || isempty(q)
    q = localInitVirtualQueue(256);
else
    q = localEnsureVirtualQueue(q);
end
nextId = max(0, round(double(nextId))) + 1;
bytes = max(1, round(double(bytes)));
slotIdx = max(1, round(double(slotIdx)));

flowId = NaN;
bearerId = NaN;
qfi = NaN;
if ~isempty(varargin)
    if mod(numel(varargin), 2) ~= 0
        error("sixgr:e2e:BadPacketMeta", "Packet metadata must be name-value pairs.");
    end
    for i = 1:2:numel(varargin)
        key = lower(char(string(varargin{i})));
        val = varargin{i+1};
        switch key
            case "flowid"
                flowId = double(val);
            case {"bearerid","lcid"}
                bearerId = double(val);
            case "qfi"
                qfi = double(val);
        end
    end
end

if q.Count >= q.Capacity
    q = localGrowVirtualQueue(q, max(2 * q.Capacity, q.Capacity + 512));
end

idx = q.Tail;
q.ID(idx) = nextId;
q.InitialBytes(idx) = bytes;
q.RemainingBytes(idx) = bytes;
q.GenSlot(idx) = slotIdx;
q.FlowID(idx) = flowId;
q.BearerID(idx) = bearerId;
q.QFI(idx) = qfi;
q.Attempts(idx) = 0;
q.FirstGrantSlot(idx) = NaN;
q.LastGrantSlot(idx) = NaN;
q.LastHarqProcess(idx) = NaN;
q.LastCRC(idx) = false;
q.Tail = idx + 1;
if q.Tail > q.Capacity
    q.Tail = 1;
end
q.Count = q.Count + 1;
end

function q = localMarkVirtualPacketTx(q, txBytes, slotIdx, harqProcess, crcOk)
if isempty(q) || txBytes <= 0
    return;
end
q = localEnsureVirtualQueue(q);
if q.Count <= 0
    return;
end
slotIdx = max(1, round(double(slotIdx)));
harqProcess = double(harqProcess);
crcOk = logical(crcOk);
rem = max(0, round(double(txBytes)));
if rem <= 0
    return;
end

idx = q.Head;
visited = 0;
while rem > 0 && visited < q.Count
    pktRem = max(0, round(double(q.RemainingBytes(idx))));
    take = min(rem, pktRem);
    if take > 0
        q.Attempts(idx) = q.Attempts(idx) + 1;
        if ~isfinite(q.FirstGrantSlot(idx))
            q.FirstGrantSlot(idx) = slotIdx;
        end
        q.LastGrantSlot(idx) = slotIdx;
        q.LastHarqProcess(idx) = harqProcess;
        q.LastCRC(idx) = crcOk;
        rem = rem - take;
    end
    idx = idx + 1;
    if idx > q.Capacity
        idx = 1;
    end
    visited = visited + 1;
end
end

function [q, sem] = localConsumeVirtualPackets(q, deliveredBytes, slotIdx, slotDur_s, pdbSlots, lastDeliveredId, varargin)
sem = struct();
sem.DeliveredPackets = 0;
sem.DeadlineMissPackets = 0;
sem.DuplicatePackets = 0;
sem.OutOfOrderPackets = 0;
sem.LastDeliveredId = double(lastDeliveredId);
sem.LatencyMs = zeros(0,1);
sem.PacketRows = repmat(localPacketTraceRowTemplate(), 0, 1);

direction = "";
ueId = NaN;
if ~isempty(varargin)
    if mod(numel(varargin), 2) ~= 0
        error("sixgr:e2e:BadConsumeMeta", "Consume metadata must be name-value pairs.");
    end
    for i = 1:2:numel(varargin)
        key = lower(char(string(varargin{i})));
        val = varargin{i+1};
        switch key
            case "direction"
                direction = string(val);
            case {"ue","rnti"}
                ueId = double(val);
        end
    end
end

if isempty(q) || deliveredBytes <= 0
    return;
end
q = localEnsureVirtualQueue(q);
if q.Count <= 0
    return;
end

rem = max(0, round(double(deliveredBytes)));
slotIdx = max(1, round(double(slotIdx)));
pdbSlots = max(1, round(double(pdbSlots)));
slotDur_ms = 1e3 * double(slotDur_s);
nLatCap = max(1, q.Count);
lat = zeros(nLatCap, 1);
nLat = 0;
pktRows = repmat(localPacketTraceRowTemplate(), nLatCap, 1);
nPktRows = 0;

while rem > 0 && q.Count > 0
    idx = q.Head;
    pktRem = max(0, round(double(q.RemainingBytes(idx))));
    if pktRem <= 0
        pktRem = 0;
    end
    take = min(rem, pktRem);
    pktRem = pktRem - take;
    q.RemainingBytes(idx) = pktRem;
    rem = rem - take;
    if pktRem > 0
        continue;
    end

    pktId = double(q.ID(idx));
    dupFlag = (pktId <= sem.LastDeliveredId);
    reordFlag = (pktId > sem.LastDeliveredId + 1);
    if dupFlag
        sem.DuplicatePackets = sem.DuplicatePackets + 1;
    elseif reordFlag
        sem.OutOfOrderPackets = sem.OutOfOrderPackets + 1;
    end
    sem.LastDeliveredId = max(sem.LastDeliveredId, pktId);
    sem.DeliveredPackets = sem.DeliveredPackets + 1;

    latSlots = max(1, slotIdx - double(q.GenSlot(idx)) + 1);
    deadlineMiss = (latSlots > pdbSlots);
    if deadlineMiss
        sem.DeadlineMissPackets = sem.DeadlineMissPackets + 1;
    end
    nLat = nLat + 1;
    latMs = latSlots * slotDur_ms;
    lat(nLat) = latMs;

    row = localPacketTraceRowTemplate();
    row.Direction = string(direction);
    row.UE = double(ueId);
    row.PacketID = pktId;
    row.FlowID = double(q.FlowID(idx));
    row.BearerID = double(q.BearerID(idx));
    row.QFI = double(q.QFI(idx));
    row.PacketBytes = double(q.InitialBytes(idx));
    row.GenerationSlot = double(q.GenSlot(idx));
    row.GenerationTime_s = (double(q.GenSlot(idx)) - 1) * double(slotDur_s);
    row.GrantSlot = double(q.FirstGrantSlot(idx));
    row.HARQProcess = double(q.LastHarqProcess(idx));
    row.Attempts = double(q.Attempts(idx));
    row.CRCResult = logical(q.LastCRC(idx));
    row.DeliverySlot = double(slotIdx);
    row.DeliveryTime_s = (double(slotIdx) - 1) * double(slotDur_s);
    row.Latency_ms = double(latMs);
    row.DeadlineMiss = logical(deadlineMiss);
    row.DuplicateFlag = logical(dupFlag);
    row.ReorderFlag = logical(reordFlag);
    row.DropCause = "";
    nPktRows = nPktRows + 1;
    pktRows(nPktRows,1) = row;

    q.Head = idx + 1;
    if q.Head > q.Capacity
        q.Head = 1;
    end
    q.Count = q.Count - 1;
end
sem.LatencyMs = lat(1:nLat);
if nPktRows > 0
    sem.PacketRows = pktRows(1:nPktRows);
else
    sem.PacketRows = repmat(localPacketTraceRowTemplate(), 0, 1);
end
if q.Count <= 0
    q.Head = 1;
    q.Tail = 1;
    q.Count = 0;
end
end

function q = localInitVirtualQueue(capacity)
cap = max(16, round(double(capacity)));
q = struct();
q.ID = zeros(cap,1);
q.InitialBytes = zeros(cap,1);
q.RemainingBytes = zeros(cap,1);
q.GenSlot = zeros(cap,1);
q.FlowID = NaN(cap,1);
q.BearerID = NaN(cap,1);
q.QFI = NaN(cap,1);
q.Attempts = zeros(cap,1);
q.FirstGrantSlot = NaN(cap,1);
q.LastGrantSlot = NaN(cap,1);
q.LastHarqProcess = NaN(cap,1);
q.LastCRC = false(cap,1);
q.Head = 1;
q.Tail = 1;
q.Count = 0;
q.Capacity = cap;
end

function q = localEnsureVirtualQueue(q)
if isempty(q)
    q = localInitVirtualQueue(256);
    return;
end
if isstruct(q) && isfield(q, "ID") && isfield(q, "InitialBytes") && ...
        isfield(q, "RemainingBytes") && isfield(q, "GenSlot") && ...
        isfield(q, "FlowID") && isfield(q, "BearerID") && isfield(q, "QFI") && ...
        isfield(q, "Attempts") && isfield(q, "FirstGrantSlot") && ...
        isfield(q, "LastGrantSlot") && isfield(q, "LastHarqProcess") && isfield(q, "LastCRC") && ...
        isfield(q, "Head") && isfield(q, "Tail") && isfield(q, "Count") && isfield(q, "Capacity")
    return;
end
if isstruct(q) && isfield(q, "ID") && isfield(q, "RemainingBytes") && isfield(q, "GenSlot")
    n = numel(q.ID);
    cap = max(16, n);
    qq = localInitVirtualQueue(cap);
    qq.ID(1:n) = reshape(double(q.ID), [], 1);
    qq.InitialBytes(1:n) = reshape(double(q.RemainingBytes), [], 1);
    qq.RemainingBytes(1:n) = reshape(double(q.RemainingBytes), [], 1);
    qq.GenSlot(1:n) = reshape(double(q.GenSlot), [], 1);
    qq.Head = 1;
    qq.Tail = n + 1;
    if qq.Tail > qq.Capacity
        qq.Tail = 1;
    end
    qq.Count = n;
    q = qq;
    return;
end
if isstruct(q)
    n = numel(q);
    qq = localInitVirtualQueue(max(16, n));
    for i = 1:n
        if isfield(q(i), "ID"), qq.ID(i) = double(q(i).ID); end
        if isfield(q(i), "InitialBytes"), qq.InitialBytes(i) = double(q(i).InitialBytes); end
        if isfield(q(i), "RemainingBytes")
            qq.RemainingBytes(i) = double(q(i).RemainingBytes);
            if qq.InitialBytes(i) <= 0
                qq.InitialBytes(i) = qq.RemainingBytes(i);
            end
        end
        if isfield(q(i), "GenSlot"), qq.GenSlot(i) = double(q(i).GenSlot); end
        if isfield(q(i), "FlowID"), qq.FlowID(i) = double(q(i).FlowID); end
        if isfield(q(i), "BearerID"), qq.BearerID(i) = double(q(i).BearerID); end
        if isfield(q(i), "QFI"), qq.QFI(i) = double(q(i).QFI); end
        if isfield(q(i), "Attempts"), qq.Attempts(i) = double(q(i).Attempts); end
        if isfield(q(i), "FirstGrantSlot"), qq.FirstGrantSlot(i) = double(q(i).FirstGrantSlot); end
        if isfield(q(i), "LastGrantSlot"), qq.LastGrantSlot(i) = double(q(i).LastGrantSlot); end
        if isfield(q(i), "LastHarqProcess"), qq.LastHarqProcess(i) = double(q(i).LastHarqProcess); end
        if isfield(q(i), "LastCRC"), qq.LastCRC(i) = logical(q(i).LastCRC); end
    end
    qq.Head = 1;
    qq.Tail = n + 1;
    if qq.Tail > qq.Capacity
        qq.Tail = 1;
    end
    qq.Count = n;
    q = qq;
    return;
end
q = localInitVirtualQueue(256);
end

function q = localGrowVirtualQueue(q, newCapacity)
q = localEnsureVirtualQueue(q);
newCap = max(q.Capacity + 1, round(double(newCapacity)));
idNew = zeros(newCap,1);
initNew = zeros(newCap,1);
remNew = zeros(newCap,1);
genNew = zeros(newCap,1);
flowNew = NaN(newCap,1);
bearerNew = NaN(newCap,1);
qfiNew = NaN(newCap,1);
attNew = zeros(newCap,1);
fGrantNew = NaN(newCap,1);
lGrantNew = NaN(newCap,1);
harqNew = NaN(newCap,1);
crcNew = false(newCap,1);
if q.Count > 0
    idx = localRingLinearIndices(q.Head, q.Count, q.Capacity);
    idNew(1:q.Count) = q.ID(idx);
    initNew(1:q.Count) = q.InitialBytes(idx);
    remNew(1:q.Count) = q.RemainingBytes(idx);
    genNew(1:q.Count) = q.GenSlot(idx);
    flowNew(1:q.Count) = q.FlowID(idx);
    bearerNew(1:q.Count) = q.BearerID(idx);
    qfiNew(1:q.Count) = q.QFI(idx);
    attNew(1:q.Count) = q.Attempts(idx);
    fGrantNew(1:q.Count) = q.FirstGrantSlot(idx);
    lGrantNew(1:q.Count) = q.LastGrantSlot(idx);
    harqNew(1:q.Count) = q.LastHarqProcess(idx);
    crcNew(1:q.Count) = q.LastCRC(idx);
end
q.ID = idNew;
q.InitialBytes = initNew;
q.RemainingBytes = remNew;
q.GenSlot = genNew;
q.FlowID = flowNew;
q.BearerID = bearerNew;
q.QFI = qfiNew;
q.Attempts = attNew;
q.FirstGrantSlot = fGrantNew;
q.LastGrantSlot = lGrantNew;
q.LastHarqProcess = harqNew;
q.LastCRC = crcNew;
q.Head = 1;
q.Tail = q.Count + 1;
q.Capacity = newCap;
if q.Tail > q.Capacity
    q.Tail = 1;
end
end

function [q, rows] = localFinalizeVirtualQueueDrops(q, finalSlot, slotDur_s, pdbSlots, lastDeliveredId, direction, ueId, dropCause)
rows = repmat(localPacketTraceRowTemplate(), 0, 1);
if isempty(q)
    return;
end
q = localEnsureVirtualQueue(q);
if q.Count <= 0
    q.Head = 1;
    q.Tail = 1;
    q.Count = 0;
    return;
end
if nargin < 8 || strlength(string(dropCause)) == 0
    dropCause = "not_delivered_by_end";
end
idxList = localRingLinearIndices(q.Head, q.Count, q.Capacity);
rows = repmat(localPacketTraceRowTemplate(), numel(idxList), 1);
for i = 1:numel(idxList)
    idx = idxList(i);
    pktId = double(q.ID(idx));
    latSlots = max(1, round(double(finalSlot - q.GenSlot(idx) + 1)));
    deadlineMiss = latSlots > max(1, round(double(pdbSlots)));
    row = localPacketTraceRowTemplate();
    row.Direction = string(direction);
    row.UE = double(ueId);
    row.PacketID = pktId;
    row.FlowID = double(q.FlowID(idx));
    row.BearerID = double(q.BearerID(idx));
    row.QFI = double(q.QFI(idx));
    row.PacketBytes = double(q.InitialBytes(idx));
    row.GenerationSlot = double(q.GenSlot(idx));
    row.GenerationTime_s = (double(q.GenSlot(idx)) - 1) * double(slotDur_s);
    row.GrantSlot = double(q.FirstGrantSlot(idx));
    row.HARQProcess = double(q.LastHarqProcess(idx));
    row.Attempts = double(q.Attempts(idx));
    row.CRCResult = logical(q.LastCRC(idx));
    row.DeliverySlot = NaN;
    row.DeliveryTime_s = NaN;
    row.Latency_ms = NaN;
    row.DeadlineMiss = logical(deadlineMiss);
    row.DuplicateFlag = logical(pktId <= double(lastDeliveredId));
    row.ReorderFlag = false;
    row.DropCause = string(dropCause);
    rows(i,1) = row;
end
q.Head = 1;
q.Tail = 1;
q.Count = 0;
end

function idx = localRingLinearIndices(head, count, capacity)
if count <= 0
    idx = zeros(0,1);
    return;
end
idx = zeros(count,1);
for i = 1:count
    p = head + i - 1;
    while p > capacity
        p = p - capacity;
    end
    idx(i) = p;
end
end

function buf = localInitLatencyBuffer(capacity)
cap = max(1024, round(double(capacity)));
buf = struct("Data", zeros(cap,1), "Count", 0);
end

function buf = localAppendLatencySamples(buf, x)
if isempty(x)
    return;
end
x = double(x(:));
n = numel(x);
need = buf.Count + n;
if need > numel(buf.Data)
    newCap = numel(buf.Data);
    while newCap < need
        newCap = max(newCap * 2, newCap + 1024);
    end
    dataNew = zeros(newCap,1);
    if buf.Count > 0
        dataNew(1:buf.Count) = buf.Data(1:buf.Count);
    end
    buf.Data = dataNew;
end
buf.Data(buf.Count+1:buf.Count+n) = x;
buf.Count = buf.Count + n;
end

function x = localFinalizeLatencyBuffer(buf)
if isempty(buf) || ~isstruct(buf) || ~isfield(buf, "Count") || buf.Count <= 0
    x = zeros(0,1);
    return;
end
x = buf.Data(1:buf.Count);
end

function [T, passRate_pct] = localBuildE2EPacketIntegrityTable( ...
    genDL_UE, delDL_UE, missDL_UE, dupDL_UE, reordDL_UE, latDL_ms, ...
    genUL_UE, delUL_UE, missUL_UE, dupUL_UE, reordUL_UE, latUL_ms, pdb_ms)

genDL = sum(double(genDL_UE));
delDL = sum(double(delDL_UE));
missDL = sum(double(missDL_UE));
dupDL = sum(double(dupDL_UE));
reordDL = sum(double(reordDL_UE));
undelDL = max(genDL - delDL, 0);
pdrDL = delDL / max(genDL, 1);
missRateDL = missDL / max(delDL, 1);
meanLatDL = mean(double(latDL_ms), "omitnan");
p95LatDL = localPercentile(double(latDL_ms), 95);

genUL = sum(double(genUL_UE));
delUL = sum(double(delUL_UE));
missUL = sum(double(missUL_UE));
dupUL = sum(double(dupUL_UE));
reordUL = sum(double(reordUL_UE));
undelUL = max(genUL - delUL, 0);
pdrUL = delUL / max(genUL, 1);
missRateUL = missUL / max(delUL, 1);
meanLatUL = mean(double(latUL_ms), "omitnan");
p95LatUL = localPercentile(double(latUL_ms), 95);

genAll = genDL + genUL;
delAll = delDL + delUL;
missAll = missDL + missUL;
dupAll = dupDL + dupUL;
reordAll = reordDL + reordUL;
undelAll = max(genAll - delAll, 0);
pdrAll = delAll / max(genAll, 1);
missRateAll = missAll / max(delAll, 1);
allLat = [double(latDL_ms(:)); double(latUL_ms(:))];
meanLatAll = mean(allLat, "omitnan");
p95LatAll = localPercentile(allLat, 95);

dirs = ["DL";"UL";"ALL"];
generated = [genDL; genUL; genAll];
delivered = [delDL; delUL; delAll];
undelivered = [undelDL; undelUL; undelAll];
pdr = [pdrDL; pdrUL; pdrAll];
meanLat = [meanLatDL; meanLatUL; meanLatAll];
p95Lat = [p95LatDL; p95LatUL; p95LatAll];
missN = [missDL; missUL; missAll];
missRate = [missRateDL; missRateUL; missRateAll];
dupN = [dupDL; dupUL; dupAll];
reordN = [reordDL; reordUL; reordAll];
deadlinePDB = repmat(double(pdb_ms), 3, 1);

semanticPass = (delivered <= generated) & (dupN == 0) & (reordN == 0) & (missRate <= 0.10);
semanticNotes = repmat("OK", 3, 1);
for i = 1:3
    if ~semanticPass(i)
        msg = strings(0,1);
        if delivered(i) > generated(i)
            msg(end+1,1) = "delivered>generated"; %#ok<AGROW>
        end
        if dupN(i) > 0
            msg(end+1,1) = "duplicate_packets"; %#ok<AGROW>
        end
        if reordN(i) > 0
            msg(end+1,1) = "reordered_packets"; %#ok<AGROW>
        end
        if missRate(i) > 0.10
            msg(end+1,1) = "deadline_miss_rate_high"; %#ok<AGROW>
        end
        semanticNotes(i) = strjoin(msg, ";");
    end
end

T = table(dirs, generated, delivered, undelivered, pdr, meanLat, p95Lat, ...
    missN, missRate, dupN, reordN, deadlinePDB, semanticPass, semanticNotes, ...
    'VariableNames', {'Direction','GeneratedPackets','DeliveredPackets','UndeliveredPackets', ...
    'PacketDeliveryRatio','MeanLatency_ms','P95Latency_ms','DeadlineMissPackets', ...
    'DeadlineMissRate','DuplicatePackets','OutOfOrderPackets','PacketDelayBudget_ms', ...
    'SemanticPass','Notes'});
passRate_pct = 100 * mean(double(semanticPass));
end

function p = localPercentile(x, pct)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    p = NaN;
    return;
end
p = prctile(x, max(0, min(100, double(pct))));
end

function [slotDL, slotUL, slotLabel] = localSlotDuplexStateE2E(cfg, slotIdx)
duplex = upper(string(sixgr.util.structGet(cfg, "phy.duplex.mode", ...
    sixgr.util.structGet(cfg, "scenario.duplexMode", "TDD"))));
if duplex == "FDD"
    slotDL = true;
    slotUL = true;
    slotLabel = "FDD_DLUL";
    return;
end
pattern = sixgr.util.structGet(cfg, "phy.duplex.tddPattern", ...
    sixgr.util.structGet(cfg, "scenario.tddPattern", "DDDSU"));
tokens = localExpandTDDPatternE2E(pattern);
if isempty(tokens)
    tokens = 'DDDSU';
end
i = mod(max(0, round(slotIdx)-1), numel(tokens)) + 1;
sw = upper(tokens(i));
switch sw
    case 'D'
        slotDL = true;
        slotUL = false;
        slotLabel = "DL";
    case 'U'
        slotDL = false;
        slotUL = true;
        slotLabel = "UL";
    otherwise
        slotDL = true;
        slotUL = true;
        slotLabel = "S";
end
end

function tokens = localExpandTDDPatternE2E(pattern)
if isstruct(pattern)
    dl = max(0, round(double(sixgr.util.structGet(pattern, "dlSlots", 4))));
    ul = max(0, round(double(sixgr.util.structGet(pattern, "ulSlots", 1))));
    sp = max(0, round(double(sixgr.util.structGet(pattern, "specialSlots", 0))));
    tokens = [repmat('D', 1, dl), repmat('S', 1, sp), repmat('U', 1, ul)];
    return;
end
if isstring(pattern) || ischar(pattern)
    s = upper(char(string(pattern)));
    s = regexprep(s, "[^DUS]", "");
    if isempty(s), s = 'DDDSU'; end
    tokens = s;
    return;
end
if isnumeric(pattern)
    p = double(pattern(:).');
    tokens = repmat('S', 1, numel(p));
    tokens(p > 0) = 'D';
    tokens(p < 0) = 'U';
    return;
end
tokens = 'DDDSU';
end

function tf = localIsRoundRobinScheduler(schedType)
s = lower(strtrim(char(string(schedType))));
s = strrep(s, "-", "");
s = strrep(s, "_", "");
tf = any(strcmp(s, ["rr","roundrobin","roundrobinscheduler"]));
end

function rlc = localCreateRLCEntity(mode, cfg, direction, lcid)
md = upper(char(string(mode)));
switch md
    case "TM"
        rlc = sixgr.l2.rlc.RLC_TM(cfg, "Direction", direction, "LCID", lcid);
    case "UM"
        rlc = sixgr.l2.rlc.RLC_UM(cfg, "Direction", direction, "LCID", lcid);
    otherwise
        try
            rlc = sixgr.l2.rlc.RLC_AM(cfg, "Direction", direction, "LCID", lcid);
        catch
            rlc = sixgr.l2.rlc.RLC_UM(cfg, "Direction", direction, "LCID", lcid);
        end
end
end

function [ok, slots, msgCount, rnti, attachRows] = localRunRRCAttachProcedure(cfg)
ok = false;
slots = NaN;
msgCount = 0;
rnti = 1;
attachRows = repmat(struct("Slot",NaN,"Time_s",NaN,"Direction","","Event","","Message","", ...
    "UE",NaN,"CellID",NaN,"TempCRNTI",NaN,"Success",false,"Cause",""), 0, 1);

strict = logical(sixgr.util.structGet(cfg, "run.strictMode", false));
cellId = double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1));
ueId = max(1, round(double(sixgr.util.structGet(cfg, "scenario.ue.startId", 1))));
maxSlots = max(16, round(double(sixgr.util.structGet(cfg, "rrc.attach.maxSlots", 128))));
maxAttempts = max(1, round(double(sixgr.util.structGet(cfg, "rrc.attach.maxAttempts", 4))));
slotDur_s = localSlotDuration(cfg);

defPrachMiss = 0.0;
defPrachCollision = 0.0;
defPdcchMiss = 0.0;
defPucchAckErr = 0.0;
if strict
    defPrachMiss = 0.02;
    defPrachCollision = 0.01;
    defPdcchMiss = 0.01;
    defPucchAckErr = 0.005;
end

pPrachMiss = double(sixgr.util.structGet(cfg, "rrc.attach.prachMissProb", defPrachMiss));
pPrachCollision = double(sixgr.util.structGet(cfg, "rrc.attach.prachCollisionProb", defPrachCollision));
pPdcchMiss = double(sixgr.util.structGet(cfg, "rrc.attach.pdcchMissProb", defPdcchMiss));
pPucchAckErr = double(sixgr.util.structGet(cfg, "rrc.attach.pucchAckNackErrorProb", defPucchAckErr));

pPrachMiss = min(max(pPrachMiss, 0), 1);
pPrachCollision = min(max(pPrachCollision, 0), 1);
pPdcchMiss = min(max(pPdcchMiss, 0), 1);
pPucchAckErr = min(max(pPucchAckErr, 0), 1);

if ~logical(sixgr.util.structGet(cfg, "phy.ul.prach.Enable", logical(sixgr.util.structGet(cfg, "phy.prach.Enable", true))))
    pPrachMiss = 0;
    pPrachCollision = 0;
end
if ~logical(sixgr.util.structGet(cfg, "phy.dl.pdcch.Enable", logical(sixgr.util.structGet(cfg, "phy.pdcch.Enable", true))))
    pPdcchMiss = 0;
end
if ~logical(sixgr.util.structGet(cfg, "phy.ul.pucch.Enable", logical(sixgr.util.structGet(cfg, "phy.pucch.Enable", true))))
    pPucchAckErr = 0;
end

try
    [ueAttach, gnbAttach] = localCreateAttachProcedures(cfg, cellId, ueId);
    pendingRAR = [];
    pendingMsg4 = [];
    nextTempCRNTI = 1;
    attempt = 1;
    attachRows(end+1,1) = struct("Slot",0,"Time_s",0,"Direction","CTRL","Event","ATTACH_START", ...
        "Message","InitAttach","UE",ueId,"CellID",cellId,"TempCRNTI",NaN,"Success",true,"Cause","");

    for s = 0:(maxSlots-1)
        if ~isempty(pendingMsg4)
            if rand >= pPdcchMiss
                ueAttach.onDownlinkMessage(0, pendingMsg4);
                msgCount = msgCount + 1;
                attachRows(end+1,1) = struct("Slot",s+1,"Time_s",s*slotDur_s,"Direction","DL","Event","MSG4_RX", ...
                    "Message",string(sixgr.util.structGet(pendingMsg4,"msgType","RRCSetup")),"UE",ueId, ...
                    "CellID",cellId,"TempCRNTI",double(sixgr.util.structGet(pendingMsg4,"cRNTI",NaN)), ...
                    "Success",true,"Cause","");
            else
                attachRows(end+1,1) = struct("Slot",s+1,"Time_s",s*slotDur_s,"Direction","DL","Event","MSG4_MISS", ...
                    "Message",string(sixgr.util.structGet(pendingMsg4,"msgType","RRCSetup")),"UE",ueId, ...
                    "CellID",cellId,"TempCRNTI",double(sixgr.util.structGet(pendingMsg4,"cRNTI",NaN)), ...
                    "Success",false,"Cause","pdcch_miss");
            end
            pendingMsg4 = [];
        end

        ueStatePre = string(ueAttach.State);
        if strcmpi(ueStatePre, "MSG3_PENDING") && rand < pPucchAckErr
            attachRows(end+1,1) = struct("Slot",s+1,"Time_s",s*slotDur_s,"Direction","UL","Event","MSG3_ACK_ERR", ...
                "Message","PUCCH_ACKNACK","UE",ueId,"CellID",cellId,"TempCRNTI",NaN,"Success",false,"Cause","pucch_ack_error");
            continue;
        end
        if strcmpi(ueStatePre, "WAIT_SETUP_COMPLETE_TX") && rand < pPucchAckErr
            attachRows(end+1,1) = struct("Slot",s+1,"Time_s",s*slotDur_s,"Direction","UL","Event","MSG5_ACK_ERR", ...
                "Message","PUCCH_ACKNACK","UE",ueId,"CellID",cellId,"TempCRNTI",NaN,"Success",false,"Cause","pucch_ack_error");
            continue;
        end

        rarIn = [];
        if ~isempty(pendingRAR)
            rarIn = pendingRAR;
            pendingRAR = [];
        end
        actUE = ueAttach.step(s, struct("RAR", rarIn), []);
        ueStatePost = string(ueAttach.State);

        if isfield(actUE, "PrachTx") && ~isempty(actUE.PrachTx)
            prachDrop = (rand < pPrachMiss) || (rand < pPrachCollision);
            tempRntiMsg1 = double(sixgr.util.structGet(actUE.PrachTx, "TempCRNTI", NaN));
            causeMsg = "";
            if prachDrop
                causeMsg = "prach_miss_or_collision";
            end
            attachRows(end+1,1) = struct("Slot",s+1,"Time_s",s*slotDur_s,"Direction","UL","Event","MSG1_TX", ...
                "Message","PRACH","UE",ueId,"CellID",cellId,"TempCRNTI",tempRntiMsg1,"Success",~prachDrop, ...
                "Cause", causeMsg);
            if ~prachDrop
                preIdx = double(sixgr.util.structGet(actUE.PrachTx, "PreambleIndex", 0));
                ta = double(sixgr.util.structGet(actUE.PrachTx, "TimingOffset", 0));
                gnbAttach.onPrachDetected(preIdx, ta, s);
                rar = gnbAttach.buildRAR(nextTempCRNTI);
                nextTempCRNTI = nextTempCRNTI + 1;
                if rand >= pPdcchMiss
                    pendingRAR = rar;
                    rnti = max(1, round(double(sixgr.util.structGet(rar, "TempCRNTI", rnti))));
                    msgCount = msgCount + 1;
                    attachRows(end+1,1) = struct("Slot",s+1,"Time_s",s*slotDur_s,"Direction","DL","Event","MSG2_RX", ...
                        "Message","RAR","UE",ueId,"CellID",cellId, ...
                        "TempCRNTI",double(sixgr.util.structGet(rar, "TempCRNTI", NaN)), ...
                        "Success",true,"Cause","");
                else
                    attachRows(end+1,1) = struct("Slot",s+1,"Time_s",s*slotDur_s,"Direction","DL","Event","MSG2_MISS", ...
                        "Message","RAR","UE",ueId,"CellID",cellId, ...
                        "TempCRNTI",double(sixgr.util.structGet(rar, "TempCRNTI", NaN)), ...
                        "Success",false,"Cause","pdcch_miss");
                end
            end
        end

        msg3Sent = strcmpi(ueStatePost, "WAIT_RRC_SETUP") && ~strcmpi(ueStatePre, "WAIT_RRC_SETUP");
        if msg3Sent
            txRnti = max(1, round(double(ueAttach.TempCRNTI)));
            msg3 = struct();
            msg3.msgType = "RRCSetupRequest";
            msg3.ueId = ueId;
            msg3.cellID = cellId;
            msg3.tempCRNTI = txRnti;
            msg3.establishmentCause = "mo-Signalling";
            gnbAttach.onUplinkMessage(0, msg3, txRnti, []);
            msgCount = msgCount + 1;
            attachRows(end+1,1) = struct("Slot",s+1,"Time_s",s*slotDur_s,"Direction","UL","Event","MSG3_TX", ...
                "Message","RRCSetupRequest","UE",ueId,"CellID",cellId,"TempCRNTI",txRnti,"Success",true,"Cause","");

            msg4 = struct();
            msg4.msgType = "RRCSetup";
            msg4.cRNTI = txRnti;
            msg4.cellID = cellId;
            msg4.srb1 = struct("lcid", 1, "mode", "AM");
            pendingMsg4 = msg4;
        end

        if strcmpi(ueStatePre, "WAIT_SETUP_COMPLETE_TX") && strcmpi(ueStatePost, "CONNECTED")
            txRnti = max(1, round(double(ueAttach.CRNTI)));
            msg5 = struct();
            msg5.msgType = "RRCSetupComplete";
            msg5.ueId = ueId;
            msg5.cellID = cellId;
            msg5.cRNTI = txRnti;
            gnbAttach.onUplinkMessage(1, msg5, txRnti, []);
            msgCount = msgCount + 1;
            rnti = txRnti;
            attachRows(end+1,1) = struct("Slot",s+1,"Time_s",s*slotDur_s,"Direction","UL","Event","MSG5_TX", ...
                "Message","RRCSetupComplete","UE",ueId,"CellID",cellId,"TempCRNTI",txRnti,"Success",true,"Cause","");
        end

        if strcmpi(ueStatePost, "FAILED")
            attachRows(end+1,1) = struct("Slot",s+1,"Time_s",s*slotDur_s,"Direction","CTRL","Event","ATTACH_FAILED", ...
                "Message","AttachProcedure","UE",ueId,"CellID",cellId,"TempCRNTI",NaN,"Success",false,"Cause","state_failed");
            if attempt >= maxAttempts
                slots = s + 1;
                return;
            end
            attempt = attempt + 1;
            [ueAttach, gnbAttach] = localCreateAttachProcedures(cfg, cellId, ueId);
            pendingRAR = [];
            pendingMsg4 = [];
            attachRows(end+1,1) = struct("Slot",s+1,"Time_s",s*slotDur_s,"Direction","CTRL","Event","ATTACH_RETRY", ...
                "Message","RetryAttempt","UE",ueId,"CellID",cellId,"TempCRNTI",NaN,"Success",true, ...
                "Cause","attempt_" + string(attempt));
            continue;
        end

        if strcmpi(ueStatePost, "CONNECTED") && strcmpi(gnbAttach.State, "CONNECTED")
            ok = true;
            slots = s + 1;
            attachRows(end+1,1) = struct("Slot",s+1,"Time_s",s*slotDur_s,"Direction","CTRL","Event","ATTACH_CONNECTED", ...
                "Message","RRC_CONNECTED","UE",ueId,"CellID",cellId,"TempCRNTI",rnti,"Success",true,"Cause","");
            return;
        end
    end
catch
    ok = false;
    attachRows(end+1,1) = struct("Slot",NaN,"Time_s",NaN,"Direction","CTRL","Event","ATTACH_EXCEPTION", ...
        "Message","AttachProcedureException","UE",ueId,"CellID",cellId,"TempCRNTI",NaN,"Success",false,"Cause","exception");
end
end

function [ok, slots, msgCount, rnti, attachRows] = localRunRRCMiniAttach(cfg)
[ok, slots, msgCount, rnti, attachRows] = localRunRRCAttachProcedure(cfg);
end

function [ueAttach, gnbAttach] = localCreateAttachProcedures(cfg, cellId, ueId)
ueAttach = sixgr.l3.rrc.AttachProcedure(cfg, "Role", "UE", "UEId", ueId, "CellID", cellId);
ueRach = sixgr.l3.rrc.RACHProcedure(cfg, "Role", "UE", "UEId", ueId, "CellID", cellId);
ueAttach.bindRACH(ueRach);
ueAttach.onSystemInformationReady(sixgr.l3.rrc.SystemInformation(cfg, "CellID", cellId));

gnbAttach = sixgr.l3.rrc.AttachProcedure(cfg, "Role", "gNB", "UEId", ueId, "CellID", cellId);
gnbRach = sixgr.l3.rrc.RACHProcedure(cfg, "Role", "gNB", "UEId", ueId, "CellID", cellId);
gnbAttach.bindRACH(gnbRach);
end

function airRes = localDeliverGrantOverPhy(cfgE, direction, grant, macPduBytes, snr_dB, airModel, strictValidation, cqi, retxDepth)
if nargin < 8 || isempty(cqi)
    cqi = 10;
end
if nargin < 9 || isempty(retxDepth)
    retxDepth = 0;
end

airRes = struct();
airRes.Ok = false;
airRes.BLER = 1.0;
airRes.Mode = "unknown";
airRes.Notes = "";

mode = lower(char(string(sixgr.util.structGet(airModel, "Mode", "lut"))));
if strcmp(mode, "truth")
    airRes = localTruthPhyReplay(cfgE, direction, grant, macPduBytes, snr_dB, airModel);
    return;
end

airRes = localFastLUTDelivery(cfgE, direction, grant, macPduBytes, snr_dB, airModel, strictValidation, cqi, retxDepth);
end

function airRes = localFastLUTDelivery(cfgE, direction, grant, macPduBytes, snr_dB, airModel, strictValidation, cqi, retxDepth)
codeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", 0.5));
pSucc = localEstimateHARQSuccessProb(snr_dB, cqi, codeRate, retxDepth > 0, retxDepth, cfgE, direction, airModel);
ack = rand < pSucc;

airRes = struct();
airRes.Ok = logical(ack);
airRes.BLER = min(max(1 - pSucc, 1e-4), 0.9999);
airRes.Mode = "lut";
airRes.Notes = "";
if strictValidation && (~isfinite(pSucc) || pSucc <= 0 || pSucc >= 1)
    error("sixgr:e2e:StrictLUTInvalid", "Strict mode requires valid LUT-based delivery probabilities.");
end
if isempty(macPduBytes)
    airRes.Ok = false;
    airRes.BLER = 1.0;
    airRes.Notes = "empty_mac_pdu";
end
end

function airRes = localTruthPhyReplay(cfgE, direction, grant, macPduBytes, snr_dB, airModel)
if nargin < 6
    airModel = struct();
end
dir = upper(string(direction));
tbBitsIn = sixgr.l2.mac.TBAssembler.bytesToBits(uint8(macPduBytes(:)));
if isempty(tbBitsIn)
    airRes = struct("Ok", false, "BLER", 1.0, "Mode", "truth", "Notes", "empty_tb");
    return;
end

try
    tmpl = localTruthTemplateForGrant(cfgE, dir, grant);
    tbBits = localResizeBitsForTB(tbBitsIn, double(tmpl.TransportBlockSize));
    compactPHY = logical(sixgr.util.structGet(airModel, "TruthCompactPHYIO", true));
    fastAWGNPath = logical(sixgr.util.structGet(airModel, "TruthFastAWGNPath", true));
    maxIter = localTruthLDPCMaxIterations(snr_dB, cfgE, airModel);
    if dir == "UL"
        tx = sixgr.phy.ul.PUSCH_Tx(cfgE, ...
            "Carrier", tmpl.Carrier, "PUSCH", tmpl.PUSCH, ...
            "TransportBlockBits", tbBits, "RV", tmpl.RV, "TargetCodeRate", tmpl.TargetCodeRate, ...
            "CompactOutput", compactPHY);
        [rxWave, nVar] = localAddAwgnTruth(tx.Waveform, snr_dB, airModel);
        [rx, ~] = sixgr.phy.ul.PUSCH_Rx(rxWave, cfgE, ...
            "Carrier", tx.Carrier, "PUSCH", tx.PUSCH, "PUSCHIndices", tx.PUSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, "NoiseVar", nVar, "MaxIterations", maxIter, ...
            "CompactOutput", compactPHY, "FastAWGNPath", fastAWGNPath);
    else
        tx = sixgr.phy.dl.PDSCH_Tx(cfgE, ...
            "Carrier", tmpl.Carrier, "PDSCH", tmpl.PDSCH, ...
            "TransportBlockBits", tbBits, "RV", tmpl.RV, "TargetCodeRate", tmpl.TargetCodeRate, ...
            "CompactOutput", compactPHY);
        [rxWave, nVar] = localAddAwgnTruth(tx.Waveform, snr_dB, airModel);
        [rx, ~] = sixgr.phy.dl.PDSCH_Rx(rxWave, cfgE, ...
            "Carrier", tx.Carrier, "PDSCH", tx.PDSCH, "PDSCHIndices", tx.PDSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, "NoiseVar", nVar, "MaxIterations", maxIter, ...
            "CompactOutput", compactPHY, "FastAWGNPath", fastAWGNPath);
    end
    ok = logical(sixgr.util.structGet(rx, "Ok", false));
    airRes = struct("Ok", ok, "BLER", double(~ok), "Mode", "truth", "Notes", "");
catch ME
    airRes = struct("Ok", false, "BLER", 1.0, "Mode", "truth", ...
        "Notes", "truth_replay_failed: " + string(ME.message));
end
end

function tmpl = localTruthTemplateForGrant(cfgE, dir, grant)
persistent cacheDL cacheUL
if isempty(cacheDL)
    cacheDL = containers.Map("KeyType", "uint64", "ValueType", "any");
end
if isempty(cacheUL)
    cacheUL = containers.Map("KeyType", "uint64", "ValueType", "any");
end

key = localTruthGrantKey(cfgE, dir, grant);
if dir == "UL"
    if isKey(cacheUL, key)
        tmpl = cacheUL(key);
        return;
    end
    [tx0, ~] = localBuildGrantAlignedPUSCHTx(cfgE, grant);
    tmpl = struct( ...
        "Carrier", tx0.Carrier, ...
        "PUSCH", tx0.PUSCH, ...
        "RV", double(tx0.RV), ...
        "TargetCodeRate", double(tx0.TargetCodeRate), ...
        "TransportBlockSize", double(tx0.TransportBlockSize));
    cacheUL(key) = tmpl;
else
    if isKey(cacheDL, key)
        tmpl = cacheDL(key);
        return;
    end
    [tx0, ~] = localBuildGrantAlignedPDSCHTx(cfgE, grant);
    tmpl = struct( ...
        "Carrier", tx0.Carrier, ...
        "PDSCH", tx0.PDSCH, ...
        "RV", double(tx0.RV), ...
        "TargetCodeRate", double(tx0.TargetCodeRate), ...
        "TransportBlockSize", double(tx0.TransportBlockSize));
    cacheDL(key) = tmpl;
end
end

function key = localTruthGrantKey(cfgE, dir, grant)
if isfield(grant, "PRBSet") && ~isempty(grant.PRBSet)
    prb = double(unique(grant.PRBSet(:).'));
else
    prb = zeros(1,0);
end
if isfield(grant, "SymbolAllocation") && ~isempty(grant.SymbolAllocation)
    sa = double(grant.SymbolAllocation(:).');
else
    sa = [0 14];
end
if numel(sa) < 2
    sa = [0 14];
else
    sa = sa(1:2);
end
if isfield(grant, "Modulation") && ~isempty(grant.Modulation)
    modStr = upper(string(grant.Modulation));
else
    modStr = "QPSK";
end
if isfield(grant, "NumLayers") && ~isempty(grant.NumLayers)
    nl = max(1, round(double(grant.NumLayers)));
else
    nl = 1;
end
if isfield(grant, "TargetCodeRate") && ~isempty(grant.TargetCodeRate)
    tcrScaled = round(double(grant.TargetCodeRate) * 1e4);
else
    tcrScaled = 5000;
end
rv = localGrantRV(grant);
scs = round(double(sixgr.util.structGet(cfgE, "phy.carrier.SubcarrierSpacing", 30)));
nsg = round(double(sixgr.util.structGet(cfgE, "phy.carrier.NSizeGrid", 0)));
modId = localModulationId(modStr);

if exist("sixgr_truth_grant_hash_kernel_mex", "file") == 3 || exist("sixgr_truth_grant_hash_kernel", "file") == 2
    try
        if exist("sixgr_truth_grant_hash_kernel_mex", "file") == 3
            key = sixgr_truth_grant_hash_kernel_mex(prb(:), sa(:), modId, nl, tcrScaled, rv, scs, nsg);
        else
            key = sixgr_truth_grant_hash_kernel(prb(:), sa(:), modId, nl, tcrScaled, rv, scs, nsg);
        end
        key = uint64(key);
    catch
        key = uint64(1469598103934665603);
    end
else
    key = uint64(1469598103934665603);
end

if key == 0
    key = uint64(1469598103934665603);
end

% Direction salt avoids DL/UL collision for identical grant geometry.
if dir == "UL"
    key = bitxor(key, uint64(11400714819323198485));
else
    key = bitxor(key, uint64(14029467366897019727));
end
end

function modId = localModulationId(modStr)
switch upper(char(string(modStr)))
    case {"PI/2-BPSK","BPSK"}
        modId = 1;
    case "QPSK"
        modId = 2;
    case "16QAM"
        modId = 4;
    case "64QAM"
        modId = 6;
    case "256QAM"
        modId = 8;
    case "1024QAM"
        modId = 10;
    case "4096QAM"
        modId = 12;
    otherwise
        modId = 2;
end
end

function [tx0, grantUsed] = localBuildGrantAlignedPDSCHTx(cfgE, grant)
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgE);
[~, pdschInfo, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfgE);
grantUsed = grant;
if isfield(grant, "PRBSet") && ~isempty(grant.PRBSet) && isprop(pdsch, "PRBSet")
    pdsch.PRBSet = double(unique(grant.PRBSet(:).'));
end
if isfield(grant, "SymbolAllocation") && ~isempty(grant.SymbolAllocation) && isprop(pdsch, "SymbolAllocation")
    sa = double(grant.SymbolAllocation(:).');
    if numel(sa) >= 2
        pdsch.SymbolAllocation = sa(1:2);
    end
end
if isfield(grant, "Modulation") && ~isempty(grant.Modulation) && isprop(pdsch, "Modulation")
    pdsch.Modulation = char(string(grant.Modulation));
end
if isfield(grant, "NumLayers") && ~isempty(grant.NumLayers) && isprop(pdsch, "NumLayers")
    pdsch.NumLayers = max(1, round(double(grant.NumLayers)));
end
rv = localGrantRV(grant);
tcr = double(sixgr.util.structGet(grant, "TargetCodeRate", sixgr.util.structGet(cfgE, "phy.pdsch.codeRate", 0.5)));
try
    [~, pdschInfo] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
catch
    [~, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
end
tbsBits = localComputeTBSBitsFromAlloc(pdsch, pdschInfo, tcr, double(sixgr.util.structGet(cfgE, "phy.pdsch.xOverhead", 0)));
tx0 = struct( ...
    "Carrier", carrier, ...
    "PDSCH", pdsch, ...
    "RV", rv, ...
    "TargetCodeRate", tcr, ...
    "TransportBlockSize", tbsBits);
end

function [tx0, grantUsed] = localBuildGrantAlignedPUSCHTx(cfgE, grant)
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgE);
[~, puschInfo, pusch] = sixgr.phy.grid.allocREsPUSCH(carrier, cfgE);
grantUsed = grant;
if isfield(grant, "PRBSet") && ~isempty(grant.PRBSet) && isprop(pusch, "PRBSet")
    pusch.PRBSet = double(unique(grant.PRBSet(:).'));
end
if isfield(grant, "SymbolAllocation") && ~isempty(grant.SymbolAllocation) && isprop(pusch, "SymbolAllocation")
    sa = double(grant.SymbolAllocation(:).');
    if numel(sa) >= 2
        pusch.SymbolAllocation = sa(1:2);
    end
end
if isfield(grant, "Modulation") && ~isempty(grant.Modulation) && isprop(pusch, "Modulation")
    pusch.Modulation = char(string(grant.Modulation));
end
if isfield(grant, "NumLayers") && ~isempty(grant.NumLayers) && isprop(pusch, "NumLayers")
    pusch.NumLayers = max(1, round(double(grant.NumLayers)));
end
rv = localGrantRV(grant);
tcr = double(sixgr.util.structGet(grant, "TargetCodeRate", sixgr.util.structGet(cfgE, "phy.pusch.codeRate", 0.5)));
try
    [~, puschInfo] = nrPUSCHIndices(carrier, pusch, "IndexStyle", "index");
catch
    [~, puschInfo] = nrPUSCHIndices(carrier, pusch);
end
tbsBits = localComputeTBSBitsFromAlloc(pusch, puschInfo, tcr, double(sixgr.util.structGet(cfgE, "phy.pusch.xOverhead", 0)));
tx0 = struct( ...
    "Carrier", carrier, ...
    "PUSCH", pusch, ...
    "RV", rv, ...
    "TargetCodeRate", tcr, ...
    "TransportBlockSize", tbsBits);
end

function tbsBits = localComputeTBSBitsFromAlloc(chCfg, chInfo, targetCodeRate, xOverhead)
nPRB = max(1, numel(chCfg.PRBSet));
nrePerPRB = [];
if isfield(chInfo, "NREPerPRB")
    nrePerPRB = double(chInfo.NREPerPRB);
elseif isfield(chInfo, "NRE")
    nrePerPRB = floor(double(chInfo.NRE) / max(nPRB,1));
elseif isfield(chInfo, "G")
    qm = localQmFromModulation(chCfg.Modulation);
    nrePerPRB = floor(double(chInfo.G) / max(qm * double(chCfg.NumLayers) * nPRB, 1));
end
if isempty(nrePerPRB) || ~isfinite(nrePerPRB) || nrePerPRB <= 0
    nrePerPRB = 144;
end
tbsBits = double(nrTBS(chCfg.Modulation, chCfg.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead));
tbsBits = max(24, round(tbsBits));
end

function qm = localQmFromModulation(modScheme)
switch upper(char(string(modScheme)))
    case {"PI/2-BPSK","BPSK"}
        qm = 1;
    case "QPSK"
        qm = 2;
    case "16QAM"
        qm = 4;
    case "64QAM"
        qm = 6;
    case "256QAM"
        qm = 8;
    case "1024QAM"
        qm = 10;
    case "4096QAM"
        qm = 12;
    otherwise
        qm = 2;
end
end

function rv = localGrantRV(grant)
rv = 0;
if isfield(grant, "HARQ") && isstruct(grant.HARQ) && isfield(grant.HARQ, "RV") && ~isempty(grant.HARQ.RV)
    rv = double(grant.HARQ.RV);
end
rv = max(0, min(3, round(rv)));
end

function bitsOut = localResizeBitsForTB(bitsIn, tbs)
if exist("sixgr_tb_resize_bits_kernel_mex", "file") == 3 || exist("sixgr_tb_resize_bits_kernel", "file") == 2
    try
        if exist("sixgr_tb_resize_bits_kernel_mex", "file") == 3
            bitsOut = sixgr_tb_resize_bits_kernel_mex(int8(bitsIn(:)), double(tbs));
        else
            bitsOut = sixgr_tb_resize_bits_kernel(int8(bitsIn(:)), double(tbs));
        end
        return;
    catch
    end
end
tbs = max(0, round(double(tbs)));
if tbs <= 0
    bitsOut = int8([]);
    return;
end
b = int8(bitsIn(:) ~= 0);
if numel(b) == tbs
    bitsOut = b;
    return;
end
if numel(b) > tbs
    bitsOut = b(1:tbs);
    return;
end
bitsOut = zeros(tbs,1, "int8");
bitsOut(1:numel(b)) = b;
end

function maxIter = localTruthLDPCMaxIterations(snr_dB, cfgE, airModel)
cfgMaxIter = round(double(sixgr.util.structGet(cfgE, "phy.ldpc.maxIterations", 8)));
cfgMaxIter = max(1, cfgMaxIter);
hardMax = round(double(sixgr.util.structGet(airModel, "TruthLDPCMaxIterations", 0)));
if hardMax > 0
    maxIter = max(1, min(cfgMaxIter, hardMax));
    return;
end
if ~logical(sixgr.util.structGet(airModel, "TruthAdaptiveLDPC", true))
    maxIter = cfgMaxIter;
    return;
end
if snr_dB >= 20
    maxIter = min(cfgMaxIter, 4);
elseif snr_dB >= 12
    maxIter = min(cfgMaxIter, 5);
elseif snr_dB >= 8
    maxIter = min(cfgMaxIter, 6);
elseif snr_dB >= 4
    maxIter = min(cfgMaxIter, 7);
else
    maxIter = cfgMaxIter;
end
maxIter = max(1, round(maxIter));
end

function [y, nVar] = localAddAwgnTruth(x, snr_dB, airModel)
useGPU = logical(sixgr.util.structGet(airModel, "TruthUseGPU", false));
if useGPU && localHasGPUForTruth() && numel(x) >= 2e6
    try
        xg = gpuArray(x);
        snrLin = 10.^(snr_dB/10);
        sigPow = double(gather(mean(abs(xg(:)).^2)));
        nVar = sigPow / max(snrLin, eps);
        nrg = sqrt(nVar/2) .* (randn(size(xg), "like", real(xg)) + 1i*randn(size(xg), "like", real(xg)));
        y = gather(xg + nrg);
        return;
    catch
        % Fall through to CPU AWGN path.
    end
end
[y, nVar] = localAddAwgn(x, snr_dB);
end

function tf = localHasGPUForTruth()
persistent checked available
if isempty(checked) || isempty(available)
    checked = true;
    available = false;
    try
        available = (gpuDeviceCount > 0);
        if available
            try
                d = gpuDevice();
                available = logical(sixgr.util.structGet(d, "DeviceSupported", true));
            catch
                available = false;
            end
        end
    catch
        available = false;
    end
end
tf = logical(available);
end

function p = localEstimateHARQSuccessProb(snr_dB, cqi, codeRate, isRetx, retxDepth, cfg, direction, airModel)
if nargin < 5 || isempty(retxDepth)
    retxDepth = 0;
end
if nargin < 6 || isempty(cfg)
    cfg = struct();
end
if nargin < 7 || isempty(direction)
    direction = "DL";
end
if nargin < 8
    airModel = struct();
end
cqi = max(1, min(15, double(cqi)));
codeRate = min(max(double(codeRate), 0.05), 0.95);
retxDepth = max(0, round(double(retxDepth)));

mode = lower(char(string(sixgr.util.structGet(airModel, "Mode", "logistic"))));
dir = upper(string(direction));

if strcmp(mode, "lut")
    if dir == "UL"
        lut = sixgr.util.structGet(airModel, "UL", struct());
    else
        lut = sixgr.util.structGet(airModel, "DL", struct());
    end
    x = double(sixgr.util.structGet(lut, "SNR_dB", []));
    y = double(sixgr.util.structGet(lut, "BLER", []));
    if isempty(x) || isempty(y) || numel(x) ~= numel(y)
        p = localEstimateHARQSuccessProbLogistic(snr_dB, cqi, codeRate, isRetx, retxDepth, cfg, dir);
        return;
    end

    % CQI/code-rate compensate the nominal SNR before LUT lookup.
    effSnr = double(snr_dB) + 0.45*(cqi - 9) - 8.0*(codeRate - 0.5);
    bler = interp1(x(:), y(:), effSnr, "linear", "extrap");
    bler = min(max(bler, 1e-4), 0.9999);

    combMode = upper(string(sixgr.util.structGet(cfg, "mac.harq.combiningMode", ...
        sixgr.util.structGet(cfg, "phy.harq.combiningMode", "IR"))));
    if isRetx
        if combMode == "CHASE"
            combGain_dB = min(1.4 * max(retxDepth,1), 6.0);
        else
            combGain_dB = min(2.1 * max(retxDepth,1), 8.0);
        end
        bler = bler * 10.^(-combGain_dB/10);
    end
    p = 1 - bler;
else
    p = localEstimateHARQSuccessProbLogistic(snr_dB, cqi, codeRate, isRetx, retxDepth, cfg, dir);
end
p = min(max(p, 1e-3), 0.999);
end

function p = localEstimateHARQSuccessProbLogistic(snr_dB, cqi, codeRate, isRetx, retxDepth, cfg, direction)
thr = -4 + 1.6*cqi + 10*(codeRate - 0.5);
margin = double(snr_dB) - thr;
combMode = upper(string(sixgr.util.structGet(cfg, "mac.harq.combiningMode", ...
    sixgr.util.structGet(cfg, "phy.harq.combiningMode", "IR"))));
if isRetx
    if combMode == "CHASE"
        combGain_dB = min(1.4 * retxDepth, 6.0);
    else
        combGain_dB = min(2.1 * retxDepth, 8.0);
    end
    margin = margin + combGain_dB;
end
if upper(string(direction)) == "UL"
    margin = margin - 0.25;
end
p = 1.0 ./ (1.0 + exp(-0.55 * margin));
end

function model = localBuildE2EAirModel(cfg, campaignRunFolder, opt, e2eAirLUT)
mode = lower(char(string(sixgr.util.structGet(opt, "E2EAirModel", "lut"))));
strictValidation = logical(sixgr.util.structGet(opt, "E2EStrictValidation", false));
if strictValidation && strcmp(mode, "logistic")
    error("sixgr:e2e:StrictLogisticForbidden", "Strict validation forbids logistic air model fallback. Use 'truth' or calibrated 'lut'.");
end

model = struct();
model.Mode = string(mode);
model.Source = "default";
model.DL = struct();
model.UL = struct();

if strcmp(mode, "truth")
    model.Source = "truth_phy_replay";
    model.TruthFastAWGNPath = logical(sixgr.util.structGet(opt, "E2ETruthFastAWGNPath", true));
    model.TruthCompactPHYIO = logical(sixgr.util.structGet(opt, "E2ETruthCompactPHYIO", true));
    model.TruthAdaptiveLDPC = logical(sixgr.util.structGet(opt, "E2ETruthAdaptiveLDPC", true));
    model.TruthLDPCMaxIterations = double(sixgr.util.structGet(opt, "E2ETruthLDPCMaxIterations", 0));
    model.TruthUseGPU = logical(sixgr.util.structGet(opt, "E2ETruthUseGPU", false));
    return;
end

if strcmp(mode, "lut")
    lutIn = e2eAirLUT;
    if isempty(fieldnames(lutIn))
        sweepFile = fullfile(campaignRunFolder, "link", "csv", "lls_snr_sweep.csv");
        if exist(sweepFile, "file") == 2
            try
                Ts = readtable(sweepFile, "VariableNamingRule", "preserve");
                lutIn = localBuildDualDirectionBLERLUTFromSweep(Ts);
            catch
                lutIn = struct();
            end
        end
    end
    if ~isempty(fieldnames(lutIn))
        model.DL = sixgr.util.structGet(lutIn, "DL", struct());
        model.UL = sixgr.util.structGet(lutIn, "UL", struct());
        model.Source = string(sixgr.util.structGet(lutIn, "Source", "link_sweep"));
    end
end

if isempty(fieldnames(model.DL))
    if strictValidation
        error("sixgr:e2e:StrictMissingDLLUT", "Strict validation requires calibrated DL LUT.");
    end
    dflt = sixgr.system.BLER_LUT();
    model.DL = struct("SNR_dB", dflt.SNR_dB, "BLER", dflt.BLER, "Source", "fallback_default");
end
if isempty(fieldnames(model.UL))
    if strictValidation
        error("sixgr:e2e:StrictMissingULLUT", "Strict validation requires calibrated UL LUT.");
    end
    dflt = sixgr.system.BLER_LUT();
    model.UL = struct("SNR_dB", dflt.SNR_dB, "BLER", dflt.BLER, "Source", "fallback_default");
end

% Slightly conservative UL baseline unless explicit UL LUT provided.
if strcmp(mode, "lut") && isfield(model.DL, "SNR_dB") && isfield(model.UL, "SNR_dB")
    if isequal(size(model.DL.SNR_dB), size(model.UL.SNR_dB)) && all(model.DL.SNR_dB == model.UL.SNR_dB)
        if ~isfield(e2eAirLUT, "UL")
            model.UL.BLER = min(max(double(model.UL.BLER) * 1.10, 1e-4), 0.9999);
        end
    end
end

% Keep mode fallback robust.
if strcmp(mode, "lut")
    if isempty(model.DL.SNR_dB) || isempty(model.UL.SNR_dB)
        if strictValidation
            error("sixgr:e2e:StrictLUTInvalid", "Strict validation requires valid DL/UL LUT axes.");
        end
        model.Mode = "logistic";
        model.Source = "fallback_logistic";
    end
end
end

function out = localBuildDualDirectionBLERLUTFromSweep(Ts)
out = struct();
out.Source = "link_sweep";
if isempty(Ts) || ~ismember("SNR_dB", string(Ts.Properties.VariableNames))
    return;
end
snr = double(Ts.SNR_dB(:));
dlRaw = NaN(size(snr));
ulRaw = NaN(size(snr));
if ismember("DL_BLER", string(Ts.Properties.VariableNames))
    dlRaw = double(Ts.DL_BLER(:));
end
if ismember("UL_BLER", string(Ts.Properties.VariableNames))
    ulRaw = double(Ts.UL_BLER(:));
end
if all(~isfinite(dlRaw)) && all(isfinite(ulRaw))
    dlRaw = ulRaw;
end
if all(~isfinite(ulRaw)) && all(isfinite(dlRaw))
    ulRaw = dlRaw;
end
if all(~isfinite(dlRaw)) && all(~isfinite(ulRaw))
    return;
end

[snrN, dlN] = localNormalizeBLERCurve(snr, dlRaw);
[~, ulN] = localNormalizeBLERCurve(snr, ulRaw);
sysBLER = min(max(0.5 * (dlN + ulN), 1e-4), 0.9999);

out.DL = struct("SNR_dB", snrN, "BLER", dlN, "Source", "link_sweep_dl");
out.UL = struct("SNR_dB", snrN, "BLER", ulN, "Source", "link_sweep_ul");
out.System = struct("SNR_dB", snrN, "BLER", sysBLER, "Source", "link_sweep_avg");
end

function calib = localBuildCampaignCalibrationPayload(cfg, e2eAirLUT, link)
calib = struct();
if nargin >= 2 && builtin("isstruct", e2eAirLUT) && isscalar(e2eAirLUT)
    if isfield(e2eAirLUT, "DL") || isfield(e2eAirLUT, "UL")
        calib = e2eAirLUT;
        calib.Source = string(sixgr.util.structGet(e2eAirLUT, "Source", "campaign_e2e_air_lut"));
        return;
    end
end

Ts = table();
if nargin >= 3 && builtin("isstruct", link) && isscalar(link)
    Ts = sixgr.util.structGet(link, "SNRSweep", table());
end
if istable(Ts) && ~isempty(Ts)
    calib = localBuildDualDirectionBLERLUTFromSweep(Ts);
    calib.Source = "campaign_link_sweep";
    return;
end

lut = sixgr.system.BLER_LUT();
calib = struct();
calib.DL = struct("SNR_dB", double(lut.SNR_dB(:)), "BLER", double(lut.BLER(:)), "Source", "default_lut_dl");
calib.UL = struct("SNR_dB", double(lut.SNR_dB(:)), "BLER", double(lut.BLER(:)), "Source", "default_lut_ul");
calib.Source = "campaign_default_lut";
calib.StrictMode = logical(sixgr.util.structGet(cfg, "run.strictMode", false));
end

function tc = localCollectCalibrationTrialCounts(runFolder)
tc = struct();
files = { ...
    "dl_pdsch_trials.csv", ...
    "ul_pusch_trials.csv", ...
    "pdcch_trials.csv", ...
    "pbch_trials.csv", ...
    "prach_trials.csv", ...
    "srs_trials.csv"};

for i = 1:numel(files)
    fn = char(files{i});
    key = matlab.lang.makeValidName(erase(fn, ".csv"));
    p = fullfile(runFolder, "link", "csv", fn);
    st = struct("file", p, "rows", 0, "pass", 0, "fail", 0, "crash", 0);
    if exist(p, "file") == 2
        try
            T = readtable(p);
            st.rows = height(T);
            if ismember("Status", string(T.Properties.VariableNames))
                S = upper(string(T.Status));
                st.pass = sum(S == "PASS");
                st.fail = sum(S == "FAIL");
                st.crash = sum(S == "CRASH");
            end
        catch
        end
    end
    tc.(key) = st;
end
end

function [snrN, blerN] = localNormalizeBLERCurve(snr, blerIn)
snr = double(snr(:));
bler = double(blerIn(:));
[snrS, idx] = sort(snr, "ascend");
blerS = bler(idx);
ref = sixgr.system.BLER_LUT("SNR_dB", snrS);
if all(~isfinite(blerS))
    blerS = double(ref.BLER(:));
else
    miss = ~isfinite(blerS);
    if any(~miss)
        blerS(miss) = interp1(snrS(~miss), blerS(~miss), snrS(miss), "linear", "extrap");
    end
    miss2 = ~isfinite(blerS);
    if any(miss2)
        blerS(miss2) = double(ref.BLER(miss2));
    end
end
blerS = min(max(blerS, 1e-4), 0.9999);
for k = 2:numel(blerS)
    blerS(k) = min(blerS(k), blerS(k-1));
end
snrN = snrS;
blerN = blerS;
end

function T = localRunE2EAIProbe(cfg, enableAI, snr_dB)
enabled = logical(enableAI);
nmseLS_dB = NaN;
nmseNN_dB = NaN;
nmseAE_dB = NaN;
aeBits = NaN;
beamIdx = NaN;
beamGain_dB = NaN;

if enabled
    nSC = 48;
    nRx = 2;
    nTx = 4;
    Htrue = (randn(nSC,nRx,nTx) + 1i*randn(nSC,nRx,nTx)) / sqrt(2);
    noiseVar = 10^(-double(snr_dB)/10);
    Hls = Htrue + sqrt(noiseVar/2) * (randn(size(Htrue)) + 1i*randn(size(Htrue)));

    nmseLS_dB = 10*log10(mean(abs(Hls(:)-Htrue(:)).^2) / max(mean(abs(Htrue(:)).^2), eps));

    Hnn = Hls;
    try
        nce = sixgr.ai.NeuralChannelEstimator(cfg);
        Hnn = nce.estimate(Hls, "NoiseVar", noiseVar);
        [nmseNN, ~] = nce.nmse(Htrue, Hnn);
        nmseNN_dB = 10*log10(max(nmseNN, eps));
    catch
        nmseNN_dB = NaN;
    end

    try
        ae = sixgr.ai.CSICompressionAutoencoder(cfg, "LatentDim", 32, "QuantBits", 6);
        comp = ae.compress(Hnn);
        Hrec = ae.decompress(comp);
        [nmseAE, ~] = ae.nmse(Hnn, Hrec);
        nmseAE_dB = 10*log10(max(nmseAE, eps));
        aeBits = numel(comp.Bits);
    catch
        nmseAE_dB = NaN;
        aeBits = NaN;
    end

    try
        bs = sixgr.ai.NeuralBeamSelection(cfg, "NumBeams", 8);
        W = dftmtx(nTx);
        W = W(:,1:8);
        hAvg = squeeze(mean(Hnn, 1));   % nRx x nTx
        beamIdx = bs.oracleBestBeam(hAvg, W);
        beamGain = mean(abs(hAvg * W(:,beamIdx)).^2);
        beamGain_dB = 10*log10(max(beamGain, eps));
    catch
        beamIdx = NaN;
        beamGain_dB = NaN;
    end
end

T = table(enabled, nmseLS_dB, nmseNN_dB, nmseAE_dB, aeBits, beamIdx, beamGain_dB, ...
    'VariableNames', {'AIEnabled','LS_NMSE_dB','NeuralCE_NMSE_dB','CSICompression_NMSE_dB', ...
                      'CSIReportBits','SelectedBeamIndex','SelectedBeamGain_dB'});
end

function localSaveE2EPlots(runFolder, slotTable, packetTraceTable, flowSummaryTable, bearerSummaryTable, dropCauseTable, harqTraceTable, attachTraceTable, summaryTable)
try
    figDir = fullfile(runFolder, "fig");
    csvDir = fullfile(runFolder, "csv");
    sixgr.util.ensureDir(figDir);

    if nargin < 2 || ~istable(slotTable) || isempty(slotTable)
        try
            slotTable = readtable(fullfile(csvDir, "e2e_slot_metrics.csv"), "VariableNamingRule", "preserve");
        catch
            slotTable = table();
        end
    end
    if nargin < 3 || ~istable(packetTraceTable)
        packetTraceTable = table();
    end
    if nargin < 4 || ~istable(flowSummaryTable)
        flowSummaryTable = table();
    end
    if nargin < 5 || ~istable(bearerSummaryTable)
        bearerSummaryTable = table();
    end
    if nargin < 6 || ~istable(dropCauseTable)
        dropCauseTable = table();
    end
    if nargin < 7 || ~istable(harqTraceTable)
        harqTraceTable = table();
    end
    if nargin < 8 || ~istable(attachTraceTable)
        attachTraceTable = table();
    end
    if nargin < 9 || ~istable(summaryTable)
        summaryTable = table();
    end

    if isempty(packetTraceTable)
        try
            packetTraceTable = readtable(fullfile(csvDir, "e2e_packet_trace.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end
    if isempty(flowSummaryTable)
        try
            flowSummaryTable = readtable(fullfile(csvDir, "e2e_flow_summary.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end
    if isempty(bearerSummaryTable)
        try
            bearerSummaryTable = readtable(fullfile(csvDir, "e2e_bearer_summary.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end
    if isempty(dropCauseTable)
        try
            dropCauseTable = readtable(fullfile(csvDir, "e2e_drop_causes.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end
    if isempty(harqTraceTable)
        try
            harqTraceTable = readtable(fullfile(csvDir, "e2e_harq_trace.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end
    if isempty(attachTraceTable)
        try
            attachTraceTable = readtable(fullfile(csvDir, "e2e_attach_trace.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end
    if isempty(summaryTable)
        try
            summaryTable = readtable(fullfile(csvDir, "e2e_summary.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end

    if ~isempty(slotTable) && all(ismember(["Slot","OfferedBits","DeliveredBits"], string(slotTable.Properties.VariableNames)))
        f = figure("Visible", "off");
        plot(slotTable.Slot, slotTable.OfferedBits/1e6, "LineWidth", 1.2); hold on;
        plot(slotTable.Slot, slotTable.DeliveredBits/1e6, "LineWidth", 1.2);
        xlabel("Slot");
        ylabel("Mbits/slot");
        legend("Offered", "Delivered", "Location", "best");
        title("E2E Offered vs Delivered Bits");
        grid on;
        localExportStandaloneFigure(figDir, f, "e2e_offered_vs_delivered");
    end

    if ~isempty(slotTable) && all(ismember(["Slot","NumACK","NumNACK","NumRetx"], string(slotTable.Properties.VariableNames)))
        f2 = figure("Visible", "off");
        plot(slotTable.Slot, slotTable.NumACK, "LineWidth", 1.2); hold on;
        plot(slotTable.Slot, slotTable.NumNACK, "LineWidth", 1.2);
        plot(slotTable.Slot, slotTable.NumRetx, "LineWidth", 1.2);
        xlabel("Slot");
        ylabel("Count");
        legend("ACK", "NACK", "Retx", "Location", "best");
        title("E2E HARQ Outcomes by Slot");
        grid on;
        localExportStandaloneFigure(figDir, f2, "e2e_harq_slot_outcomes");
    end

    if ~isempty(packetTraceTable)
        nPkt = height(packetTraceTable);
        dropCause = localStringColumn(packetTraceTable, "DropCause", strings(nPkt,1));
        dirCol = localStringColumn(packetTraceTable, "Direction", strings(nPkt,1));
        flowCol = localNumericColumn(packetTraceTable, "FlowID", NaN(nPkt,1));
        pktIdCol = localNumericColumn(packetTraceTable, "PacketID", NaN(nPkt,1));
        delSlotCol = localNumericColumn(packetTraceTable, "DeliverySlot", NaN(nPkt,1));
        latMs = localNumericColumn(packetTraceTable, "Latency_ms", NaN(nPkt,1));
        missCol = localLogicalColumn(packetTraceTable, "DeadlineMiss", false(nPkt,1));
        genSlotCol = localNumericColumn(packetTraceTable, "GenerationSlot", NaN(nPkt,1));
        bearerCol = localNumericColumn(packetTraceTable, "BearerID", NaN(nPkt,1));
        qfiCol = localNumericColumn(packetTraceTable, "QFI", NaN(nPkt,1));

        deliveredMask = (strlength(dropCause) == 0) & isfinite(latMs);
        latAll = latMs(deliveredMask);
        latDL = latMs(deliveredMask & strcmpi(dirCol, "DL"));
        latUL = latMs(deliveredMask & strcmpi(dirCol, "UL"));

        if ~isempty(latAll)
            f3 = figure("Visible", "off");
            hold on;
            [xA, yA] = localECDF(latAll);
            plot(xA, yA, "LineWidth", 1.4);
            if ~isempty(latDL)
                [xD, yD] = localECDF(latDL);
                plot(xD, yD, "LineWidth", 1.2);
            end
            if ~isempty(latUL)
                [xU, yU] = localECDF(latUL);
                plot(xU, yU, "LineWidth", 1.2);
            end
            xlabel("Latency (ms)");
            ylabel("CDF");
            legend("All","DL","UL","Location","southeast");
            title("E2E Latency CDF");
            grid on;
            localExportStandaloneFigure(figDir, f3, "e2e_latency_cdf");
        end

        jitterAll = [];
        jitterDL = [];
        jitterUL = [];
        if any(deliveredMask)
            gDir = unique(string(dirCol(deliveredMask)));
            for id = 1:numel(gDir)
                dVal = gDir(id);
                flowVals = unique(flowCol(deliveredMask & strcmpi(dirCol, dVal)));
                for jf = 1:numel(flowVals)
                    fv = flowVals(jf);
                    idx = deliveredMask & strcmpi(dirCol, dVal) & (flowCol == fv);
                    if ~any(idx)
                        continue;
                    end
                    key1 = delSlotCol(idx);
                    key2 = pktIdCol(idx);
                    key1(~isfinite(key1)) = inf;
                    key2(~isfinite(key2)) = inf;
                    latSeq = latMs(idx);
                    [~, ord] = sortrows([key1 key2], [1 2]);
                    latSeq = latSeq(ord);
                    latSeq = latSeq(isfinite(latSeq));
                    if numel(latSeq) <= 1
                        continue;
                    end
                    j = abs(diff(latSeq));
                    jitterAll = [jitterAll; j]; %#ok<AGROW>
                    if strcmpi(dVal, "DL")
                        jitterDL = [jitterDL; j]; %#ok<AGROW>
                    elseif strcmpi(dVal, "UL")
                        jitterUL = [jitterUL; j]; %#ok<AGROW>
                    end
                end
            end
        end
        if ~isempty(jitterAll)
            f4 = figure("Visible", "off");
            hold on;
            [xA, yA] = localECDF(jitterAll);
            plot(xA, yA, "LineWidth", 1.4);
            if ~isempty(jitterDL)
                [xD, yD] = localECDF(jitterDL);
                plot(xD, yD, "LineWidth", 1.2);
            end
            if ~isempty(jitterUL)
                [xU, yU] = localECDF(jitterUL);
                plot(xU, yU, "LineWidth", 1.2);
            end
            xlabel("Jitter |Δlatency| (ms)");
            ylabel("CDF");
            legend("All","DL","UL","Location","southeast");
            title("E2E Jitter CDF");
            grid on;
            localExportStandaloneFigure(figDir, f4, "e2e_jitter_cdf");
        end

        if ~isempty(latAll)
            pAll = [localPercentile(latAll, 95), localPercentile(latAll, 99), localPercentile(latAll, 99.9)];
            pDL = [localPercentile(latDL, 95), localPercentile(latDL, 99), localPercentile(latDL, 99.9)];
            pUL = [localPercentile(latUL, 95), localPercentile(latUL, 99), localPercentile(latUL, 99.9)];
            M = [pAll; pDL; pUL];
            if any(isfinite(M(:)))
                f5 = figure("Visible", "off");
                bh = bar(M, "grouped");
                if ~isempty(bh)
                    bh(1).FaceColor = [0.2 0.5 0.8];
                    if numel(bh) >= 2
                        bh(2).FaceColor = [0.85 0.45 0.2];
                    end
                    if numel(bh) >= 3
                        bh(3).FaceColor = [0.35 0.7 0.35];
                    end
                end
                xticklabels({"All","DL","UL"});
                ylabel("Latency (ms)");
                legend("P95","P99","P99.9","Location","northwest");
                title("E2E Latency Percentiles");
                grid on;
                localExportStandaloneFigure(figDir, f5, "e2e_latency_percentiles");
            end
        end

        if ~isempty(slotTable) && all(ismember(["OfferedBits"], string(slotTable.Properties.VariableNames)))
            slotDur_s = 1e-3;
            if ~isempty(summaryTable) && ismember("SlotDuration_ms", string(summaryTable.Properties.VariableNames))
                slotDur_s = max(double(summaryTable.SlotDuration_ms(1)) / 1e3, eps);
            end
            offeredMbpsSlot = double(slotTable.OfferedBits) / max(slotDur_s, eps) / 1e6;
            nSlots = height(slotTable);
            genCnt = zeros(nSlots,1);
            missCnt = zeros(nSlots,1);
            for iPkt = 1:nPkt
                gs = round(double(genSlotCol(iPkt)));
                if ~(isfinite(gs) && gs >= 1 && gs <= nSlots)
                    continue;
                end
                genCnt(gs) = genCnt(gs) + 1;
                if logical(missCol(iPkt))
                    missCnt(gs) = missCnt(gs) + 1;
                end
            end
            missRate = missCnt ./ max(genCnt, 1);
            valid = isfinite(offeredMbpsSlot) & isfinite(missRate);
            if any(valid)
                xv = offeredMbpsSlot(valid);
                yv = missRate(valid);
                f6 = figure("Visible", "off");
                hold on;
                plot(xv, yv, ".", "Color", [0.45 0.45 0.45], "MarkerSize", 9);
                if numel(unique(xv)) > 1
                    nBins = min(10, max(4, round(sqrt(numel(xv)))));
                    e0 = min(xv);
                    e1 = max(xv);
                    if e1 <= e0
                        e1 = e0 + 1;
                    end
                    edges = linspace(e0, e1, nBins + 1);
                    [~,~,bin] = histcounts(xv, edges);
                    xBin = 0.5 * (edges(1:end-1) + edges(2:end));
                    yBin = NaN(nBins,1);
                    for ib = 1:nBins
                        idxb = (bin == ib);
                        if any(idxb)
                            yBin(ib) = mean(yv(idxb));
                        end
                    end
                    plot(xBin, yBin, "-o", "LineWidth", 1.5, "MarkerSize", 5);
                end
                xlabel("Offered Load (Mbps)");
                ylabel("Deadline Miss Rate");
                title("Deadline Miss vs Offered Load");
                grid on;
                localExportStandaloneFigure(figDir, f6, "e2e_deadline_miss_vs_offered_load");
            end
        end

        if isempty(dropCauseTable)
            dropMask = strlength(dropCause) > 0;
            if any(dropMask)
                [g, gd, gc] = findgroups(string(dirCol(dropMask)), string(dropCause(dropMask)));
                dN = splitapply(@numel, dropCause(dropMask), g);
                dropCauseTable = table(gd, gc, dN, 'VariableNames', {'Direction','DropCause','DroppedPackets'});
            end
        end
        if ~isempty(dropCauseTable) && ismember("DroppedPackets", string(dropCauseTable.Properties.VariableNames))
            dDir = localStringColumn(dropCauseTable, "Direction", strings(height(dropCauseTable),1));
            dCause = localStringColumn(dropCauseTable, "DropCause", strings(height(dropCauseTable),1));
            dCnt = localNumericColumn(dropCauseTable, "DroppedPackets", zeros(height(dropCauseTable),1));
            keep = isfinite(dCnt) & (dCnt > 0);
            if any(keep)
                labels = dDir(keep) + "|" + dCause(keep);
                vals = dCnt(keep);
                [vals, ord] = sort(vals, "descend");
                labels = labels(ord);
                f7 = figure("Visible", "off");
                barh(categorical(labels), vals);
                set(gca, "YDir", "reverse");
                xlabel("Dropped Packets");
                ylabel("Direction|Cause");
                title("Drop-Cause Breakdown");
                grid on;
                localExportStandaloneFigure(figDir, f7, "e2e_drop_cause_breakdown");
            end
        end

        if ~isempty(harqTraceTable)
            retxDepth = localNumericColumn(harqTraceTable, "RetxDepthAfter", NaN(height(harqTraceTable),1));
            if ~any(isfinite(retxDepth))
                attempts = localNumericColumn(harqTraceTable, "AttemptCount", NaN(height(harqTraceTable),1));
                retxDepth = attempts - 1;
            end
            retxDepth = round(retxDepth(isfinite(retxDepth) & retxDepth >= 0));
            if ~isempty(retxDepth)
                maxD = max(retxDepth);
                edges = (-0.5):(1):(maxD + 0.5);
                f8 = figure("Visible", "off");
                histogram(retxDepth, edges);
                xlabel("Retransmission Depth");
                ylabel("Grant Count");
                title("HARQ Retransmission Depth Histogram");
                grid on;
                localExportStandaloneFigure(figDir, f8, "e2e_retx_depth_histogram");
            end
        end

        if ~isempty(attachTraceTable)
            tAttach = localNumericColumn(attachTraceTable, "Time_s", NaN(height(attachTraceTable),1));
            eAttach = upper(localStringColumn(attachTraceTable, "Event", strings(height(attachTraceTable),1)));
            startIdx = find(eAttach == "ATTACH_START" & isfinite(tAttach), 1, "first");
            if isempty(startIdx)
                startTime = min(tAttach(isfinite(tAttach)));
            else
                startTime = tAttach(startIdx);
            end
            msgMask = startsWith(eAttach, "MSG") & isfinite(tAttach);
            delayMs = (tAttach(msgMask) - startTime) * 1e3;
            delayMs = delayMs(isfinite(delayMs) & delayMs >= 0);
            if ~isempty(delayMs)
                f9 = figure("Visible", "off");
                histogram(delayMs, min(20, max(6, numel(delayMs))));
                xlabel("Attach Message Delay from Start (ms)");
                ylabel("Count");
                title("Attach Delay Histogram");
                grid on;
                localExportStandaloneFigure(figDir, f9, "e2e_attach_delay_histogram");
            end
        end

        if ~isempty(flowSummaryTable)
            gFlow = localNumericColumn(flowSummaryTable, "FlowID", NaN(height(flowSummaryTable),1));
            gDir = localStringColumn(flowSummaryTable, "Direction", strings(height(flowSummaryTable),1));
            gThr = localNumericColumn(flowSummaryTable, "Goodput_Mbps", NaN(height(flowSummaryTable),1));
            keep = isfinite(gFlow) & isfinite(gThr);
            if any(keep)
                labels = gDir(keep) + "-F" + string(round(gFlow(keep)));
                vals = gThr(keep);
                [vals, ord] = sort(vals, "descend");
                labels = labels(ord);
                f10 = figure("Visible", "off");
                bar(categorical(labels), vals);
                xtickangle(35);
                ylabel("Goodput (Mbps)");
                xlabel("Flow");
                title("Per-Flow Throughput");
                grid on;
                localExportStandaloneFigure(figDir, f10, "e2e_per_flow_throughput");
            end
        end

        qosCompliance = [];
        qosLabels = strings(0,1);
        validBearer = isfinite(bearerCol) & isfinite(qfiCol);
        if any(validBearer)
            dirsB = string(dirCol(validBearer));
            brB = round(double(bearerCol(validBearer)));
            qfiB = round(double(qfiCol(validBearer)));
            onTime = double((strlength(dropCause(validBearer)) == 0) & ~missCol(validBearer));
            onesVec = ones(sum(validBearer),1);
            [gB, gdB, gbB, gqB] = findgroups(dirsB, brB, qfiB);
            genB = splitapply(@sum, onesVec, gB);
            onB = splitapply(@sum, onTime, gB);
            qosCompliance = onB ./ max(genB, 1);
            qosLabels = gdB + "-B" + string(gbB) + "-Q" + string(gqB);
        elseif ~isempty(bearerSummaryTable) && ...
                all(ismember(["Direction","BearerID","QFI","PacketDeliveryRatio"], string(bearerSummaryTable.Properties.VariableNames)))
            qosCompliance = localNumericColumn(bearerSummaryTable, "PacketDeliveryRatio", NaN(height(bearerSummaryTable),1));
            qosLabels = localStringColumn(bearerSummaryTable, "Direction", strings(height(bearerSummaryTable),1)) + ...
                "-B" + string(round(localNumericColumn(bearerSummaryTable, "BearerID", NaN(height(bearerSummaryTable),1)))) + ...
                "-Q" + string(round(localNumericColumn(bearerSummaryTable, "QFI", NaN(height(bearerSummaryTable),1))));
        end
        keepQ = isfinite(qosCompliance);
        if any(keepQ)
            f11 = figure("Visible", "off");
            bar(categorical(qosLabels(keepQ)), 100 * qosCompliance(keepQ));
            yline(99, "--r", "Target 99%");
            xtickangle(35);
            ylabel("QoS Compliance (%)");
            xlabel("Bearer");
            ylim([0 105]);
            title("Per-Bearer QoS Compliance");
            grid on;
            localExportStandaloneFigure(figDir, f11, "e2e_per_bearer_qos_compliance");
        end
    end
catch
end
end

function [x, y] = localECDF(v)
v = double(v(:));
v = v(isfinite(v));
if isempty(v)
    x = NaN;
    y = NaN;
    return;
end
x = sort(v, "ascend");
y = (1:numel(x)).' ./ numel(x);
end

function localExportStandaloneFigure(figDir, figHandle, baseName)
if nargin < 3 || strlength(string(baseName)) == 0 || ~isgraphics(figHandle)
    return;
end
pngFile = fullfile(figDir, string(baseName) + ".png");
pdfFile = fullfile(figDir, string(baseName) + ".pdf");
exportgraphics(figHandle, pngFile, "Resolution", 200);
exportgraphics(figHandle, pdfFile, "ContentType", "vector");
close(figHandle);
end

function audit = localBuild25CategoryAudit(link, sys, mmtc, harq, syncCtrl, v2x, ntn, interf, rfp, numProbe, beam, e2e)
rows = repmat(struct("Category","","Status","","Evidence","","Notes",""), 0, 1);

rows(end+1,1) = localAudit("1. Error Performance Metrics", "implemented", "link/csv/lls_kpi_summary.csv", "BER/BLER/outage proxy");
rows(end+1,1) = localAudit("2. Throughput and Rate Metrics", "implemented", "link/csv/lls_kpi_summary.csv", "Goodput + spectral efficiency + peak from sweep");
rows(end+1,1) = localAudit("3. Signal Quality and CSI", "approximated", "link/csv/lls_frame_metrics_*.csv", "SNR and noise variance; full CSI feedback set is partial");
rows(end+1,1) = localAudit("4. Channel Estimation and Equalization", "implemented", "link/csv/lls_kpi_summary.csv", "Channel-estimation MSE + EVM-based quality");
rows(end+1,1) = localAudit("5. MIMO and Beamforming", localOkToStatus(beam.Ok, "approximated"), "csv/probe_beam_mimo.csv", "Capacity/condition/beam metrics from probe");
rows(end+1,1) = localAudit("6. Link Adaptation", "implemented", "link/csv/lls_snr_sweep.csv", "BLER/BER/throughput vs SNR curves");
rows(end+1,1) = localAudit("7. HARQ and Retransmissions", localOkToStatus(harq.Ok, "implemented"), "csv/probe_harq_summary.csv", "Retransmission probability/RTT/residual BLER");
rows(end+1,1) = localAudit("8. Latency and Timing", localOkToStatus(harq.Ok, "approximated"), "csv/probe_harq_packets.csv", "Processing delay + HARQ RTT proxy");
rows(end+1,1) = localAudit("9. Power and Energy Efficiency", localOkToStatus(rfp.Ok, "approximated"), "csv/probe_rf_energy.csv", "Power model outputs + PAPR");
rows(end+1,1) = localAudit("10. Synchronization and Timing Offsets", localOkToStatus(syncCtrl.Ok, "approximated"), "csv/probe_sync_control.csv", "PBCH/PRACH detect + timing offset");
rows(end+1,1) = localAudit("11. Channel Coding and Decoding", "implemented", "link/csv/lls_kpi_summary.csv", "LDPC decoder iterations + BER/BLER");
rows(end+1,1) = localAudit("12. Modulation and Waveform Quality", "implemented", "link/fig/*.png", "EVM, constellation, PAPR CCDF");
rows(end+1,1) = localAudit("13. Interference Analysis", localOkToStatus(interf.Ok, "approximated"), "csv/probe_interference_sir_bler.csv", "Synthetic SIR vs BLER probe");
rows(end+1,1) = localAudit("14. Mobility and Time-Varying Channels", localOkToStatus(sys.Ok, "implemented"), "system/csv/system_time_series.csv", "Mobility traces and time-varying SINR");
rows(end+1,1) = localAudit("15. Multi-User and Multi-Cell Metrics", localOkToStatus(sys.Ok, "approximated"), "system/csv/system_kpis.csv", "Fairness/sum-rate style KPIs from system abstraction");
rows(end+1,1) = localAudit("16. Beam Management", localOkToStatus(beam.Ok, "approximated"), "csv/probe_beam_mimo.csv", "Beam score metrics; full beam management loop not modeled");
rows(end+1,1) = localAudit("17. Waveform and Numerology Specifics", localOkToStatus(numProbe.Ok, "implemented"), "csv/probe_numerology.csv", "SCS sweep impact on BER/BLER/throughput");
rows(end+1,1) = localAudit("18. Control Channel and Random Access", localOkToStatus(syncCtrl.Ok, "implemented"), "csv/probe_sync_control.csv", "PBCH/PRACH/PDCCH/PUCCH probe metrics");
rows(end+1,1) = localAudit("19. Hardware Impairments", localOkToStatus(rfp.Ok, "implemented"), "csv/probe_rf_energy.csv", "IQ imbalance/phase noise/CFO/DC offset sensitivity");
rows(end+1,1) = localAudit("20. Reliability and Outage (URLLC)", "approximated", "link/csv/lls_kpi_summary.csv", "Outage and BLER reliability proxy");
rows(end+1,1) = localAudit("21. Massive MTC (mMTC) Metrics", localOkToStatus(mmtc.Ok, "implemented"), "csv/probe_mmtc_kpis.csv", "Connection density + access success proxy");
rows(end+1,1) = localAudit("22. V2X Metrics", localOkToStatus(v2x.Ok, "approximated"), "csv/probe_v2x_sidelink.csv", "Sidelink-style PRR/IPG/latency vs velocity");
rows(end+1,1) = localAudit("23. NTN Metrics", localOkToStatus(ntn.Ok, "approximated"), "csv/probe_ntn_delay_doppler.csv", "Delay/Doppler compensation probe");
rows(end+1,1) = localAudit("24. Protocol and Stack Interactions", localOkToStatus(e2e.Ok, "implemented"), "csv/probe_e2e_summary.csv + csv/probe_e2e_packet_integrity.csv", "SDAP/PDCP/RLC/MAC/HARQ/RRC hooks with semantic packet checks");
rows(end+1,1) = localAudit("25. Miscellaneous Statistical Outputs", "implemented", "link/fig + system/csv", "CDFs/time series/correlation-ready exports");

audit = struct2table(rows);
end

function s = localOkToStatus(ok, okStatus)
if ok
    s = okStatus;
else
    s = "not_modeled";
end
end

function r = localAudit(cat, status, evidence, notes)
r = struct();
r.Category = string(cat);
r.Status = string(status);
r.Evidence = string(evidence);
r.Notes = string(notes);
end

function localEnsureMexAccelerators()
persistent builtOK
if ~isempty(builtOK) && builtOK
    return;
end

need = ["sixgr_l2_mac_estimateTBSApprox_entry_mex", ...
    "sixgr_system_fast_core_kernel_mex", ...
    "sixgr_e2e_fast_core_kernel_mex", ...
    "sixgr_link_fast_core_kernel_mex", ...
    "sixgr_fft_papr_kernel_mex", ...
    "sixgr_ldpc_decode_batch_kernel_mex", ...
    "sixgr_channel_est_ls_kernel_mex", ...
    "sixgr_awgn_complex_kernel_mex", ...
    "sixgr_freq_shift_kernel_mex", ...
    "sixgr_corr_metric_kernel_mex", ...
    "sixgr_freq_corr_search_kernel_mex", ...
    "sixgr_tb_resize_bits_kernel_mex", ...
    "sixgr_truth_grant_hash_kernel_mex", ...
    "sixgr_struct_get_mex"];
missing = false(size(need));
for i = 1:numel(need)
    missing(i) = exist(char(need(i)), "file") ~= 3;
end
if ~any(missing)
    builtOK = true;
    return;
end

try
    out = sixgr_build_mex_accel("Verbose", false);
    builtOK = logical(sixgr.util.structGet(out, "Ok", false));
catch
    builtOK = false;
end
end

function localEnsureParallelPool()
try
    p = gcp("nocreate");
    if ~isempty(p)
        return;
    end
catch
end
try
    parpool("Processes");
catch
    try
        parpool();
    catch
    end
end
end

function opt = localApplyCampaignConfig(opt, cfg)
camp = sixgr.util.structGet(cfg, "run.campaign", struct());
if ~(builtin("isstruct", camp) && isscalar(camp))
    camp = struct();
end

profile = lower(strtrim(char(string( ...
    sixgr.util.structGet(camp, "profile", sixgr.util.structGet(cfg, "run.profile", ""))))));
if strlength(string(profile)) > 0
    switch profile
        case {"quick","smoke"}
            opt.LinkDuration_s = 20;
            opt.SystemDuration_s = 20;
            opt.E2EDuration_s = 20;
            opt.LinkMaxSimFrames = min(opt.LinkMaxSimFrames, 48);
            opt.LinkSweepFrames = min(opt.LinkSweepFrames, 3);
            opt.LinkSweepMaxPoints = min(opt.LinkSweepMaxPoints, 5);
            opt.SystemNumUE = min(opt.SystemNumUE, 32);
            opt.E2EUECount = min(opt.E2EUECount, 4);
            opt.E2EMaxSlots = max(400, min(opt.E2EMaxSlots, 800));
            opt.RunSystemMMTCProbe = false;
            opt.RunAuxiliaryProbes = false;
            opt.UseFastLinkModel = true;
            opt.UseMexAcceleration = true;
            opt.AutoBuildMexAcceleration = true;
            opt.OrganizeByBlock = false;
            opt.GenerateCampaignPlots = false;
            opt.VerifyArtifacts = false;
            opt.SystemDetailedTrace = false;
            opt.MMTCSaveFigures = false;
            opt.LinkSaveFigures = false;
            opt.SystemSaveFigures = false;
            opt.E2ESaveFigures = false;
        case {"long","long_30min","30min","30m"}
            opt.LinkDuration_s = 1800;
            opt.SystemDuration_s = 1800;
            opt.E2EDuration_s = 1800;
            opt.LinkMaxSimFrames = max(opt.LinkMaxSimFrames, 2400);
            opt.LinkSweepFrames = max(opt.LinkSweepFrames, 16);
        case {"xlong","long_60min","60min","60m","1h","1hour"}
            opt.LinkDuration_s = 3600;
            opt.SystemDuration_s = 3600;
            opt.E2EDuration_s = 3600;
            opt.LinkMaxSimFrames = max(opt.LinkMaxSimFrames, 4800);
            opt.LinkSweepFrames = max(opt.LinkSweepFrames, 20);
        otherwise
            % Keep parser defaults/explicit args for "full"/unknown profiles.
    end
end

opt = localOverrideNum(opt, camp, "LinkDuration_s", "linkDuration_s");
opt = localOverrideNum(opt, camp, "SystemDuration_s", "systemDuration_s");
opt = localOverrideNum(opt, camp, "E2EDuration_s", "e2eDuration_s");
opt = localOverrideNum(opt, camp, "E2EUECount", "e2eUECount");
opt = localOverrideNum(opt, camp, "E2EMaxSlots", "e2eMaxSlots");
opt = localOverrideNum(opt, camp, "E2ETruthMaxSlots", "e2eTruthMaxSlots");
opt = localOverrideNum(opt, camp, "E2ETruthLDPCMaxIterations", "e2eTruthLdpcMaxIterations");
opt = localOverrideNum(opt, camp, "E2EServiceScaleCap", "e2eServiceScaleCap");
opt = localOverrideNum(opt, camp, "E2EMaxSDUChunkBytes", "e2eMaxSDUChunkBytes");
opt = localOverrideNum(opt, camp, "LinkMaxSimFrames", "linkMaxSimFrames");
opt = localOverrideNum(opt, camp, "LinkSweepFrames", "linkSweepFrames");
opt = localOverrideNum(opt, camp, "LinkSweepMaxPoints", "linkSweepMaxPoints");
opt = localOverrideNum(opt, camp, "SystemNumUE", "systemNumUE");
opt = localOverrideNum(opt, camp, "MMTCNumUE", "mmtcNumUE");
opt = localOverrideNum(opt, camp, "LinkSNR_dB", "linkSNR_dB");
opt = localOverrideNum(opt, camp, "HARQPackets", "harqPackets");
opt = localOverrideNum(opt, camp, "HARQMaxRetx", "harqMaxRetx");
opt = localOverrideNum(opt, camp, "V2XPackets", "v2xPackets");
opt = localOverrideNum(opt, camp, "NTNFrames", "ntnFrames");

opt = localOverrideBool(opt, camp, "RunE2EStackProbe", "runE2E");
opt = localOverrideBool(opt, camp, "OnlyE2E", "onlyE2E");
opt = localOverrideBool(opt, camp, "RunSystemMMTCProbe", "runMMTC");
opt = localOverrideBool(opt, camp, "RunAuxiliaryProbes", "runAuxiliaryProbes");
opt = localOverrideBool(opt, camp, "E2EScaleServiceWithCompression", "e2eScaleServiceWithCompression");
opt = localOverrideBool(opt, camp, "E2EStrictValidation", "e2eStrictValidation");
opt = localOverrideBool(opt, camp, "E2EEnableSemanticChecks", "e2eEnableSemanticChecks");
opt = localOverrideBool(opt, camp, "E2ETruthFastAWGNPath", "e2eTruthFastAwgnPath");
opt = localOverrideBool(opt, camp, "E2ETruthCompactPHYIO", "e2eTruthCompactPhyIo");
opt = localOverrideBool(opt, camp, "E2ETruthAdaptiveLDPC", "e2eTruthAdaptiveLdpc");
opt = localOverrideBool(opt, camp, "E2ETruthUseGPU", "e2eTruthUseGpu");
opt = localOverrideBool(opt, camp, "E2ESaveFigures", "e2eSaveFigures");
opt = localOverrideBool(opt, camp, "E2EScaleChunkWithCompression", "e2eScaleChunkWithCompression");
opt = localOverrideBool(opt, camp, "CalibrateSystemBLERFromLink", "calibrateSystemBLERFromLink");
opt = localOverrideBool(opt, camp, "ReuseLinkForDetailedDiagnostics", "reuseLinkForDetailedDiagnostics");
opt = localOverrideBool(opt, camp, "MirrorStructuredResults", "mirrorStructuredResults");
opt = localOverrideBool(opt, camp, "OrganizeByBlock", "organizeByBlock");
opt = localOverrideBool(opt, camp, "LinkSaveFigures", "linkSaveFigures");
opt = localOverrideBool(opt, camp, "SystemDetailedTrace", "systemDetailedTrace");
opt = localOverrideBool(opt, camp, "SystemSaveFigures", "systemSaveFigures");
opt = localOverrideBool(opt, camp, "MMTCSaveFigures", "mmtcSaveFigures");
opt = localOverrideBool(opt, camp, "UseFastLinkModel", "useFastLinkModel");
opt = localOverrideBool(opt, camp, "UseMexAcceleration", "useMexAcceleration");
opt = localOverrideBool(opt, camp, "UseParallelAcceleration", "useParallelAcceleration");
opt = localOverrideBool(opt, camp, "AutoStartParallelPool", "autoStartParallelPool");
opt = localOverrideBool(opt, camp, "AutoBuildMexAcceleration", "autoBuildMexAcceleration");
opt = localOverrideBool(opt, camp, "SetupToolboxChecks", "setupToolboxChecks");
opt = localOverrideBool(opt, camp, "GenerateCampaignPlots", "generateCampaignPlots");
opt = localOverrideBool(opt, camp, "VerifyArtifacts", "verifyArtifacts");
opt = localOverrideString(opt, camp, "E2EAirModel", "e2eAirModel");
end

function opt = localOverrideNum(opt, S, optName, fieldName)
if isfield(S, fieldName)
    v = double(S.(fieldName));
    if isfinite(v) && isscalar(v)
        opt.(optName) = v;
    end
end
end

function opt = localOverrideBool(opt, S, optName, fieldName)
if isfield(S, fieldName)
    v = S.(fieldName);
    if islogical(v) || (isnumeric(v) && isscalar(v))
        opt.(optName) = logical(v);
    end
end
end

function opt = localOverrideString(opt, S, optName, fieldName)
if isfield(S, fieldName)
    v = string(S.(fieldName));
    if strlength(v) > 0
        opt.(optName) = char(v);
    end
end
end

function out = localGenerateCampaignPlots(runFolder)
figDir = fullfile(runFolder, "fig");
sixgr.util.ensureDir(figDir);
files = strings(0,1);
nPlots = 0;

% 1) Link SNR sweep.
fSweep = fullfile(runFolder, "link", "csv", "lls_snr_sweep.csv");
if exist(fSweep, "file") == 2
    T = readtable(fSweep, "VariableNamingRule", "preserve");
    if ~isempty(T) && ismember("SNR_dB", string(T.Properties.VariableNames))
        f = figure("Visible", "off");
        hold on;
        if ismember("DL_BLER", string(T.Properties.VariableNames))
            semilogy(T.SNR_dB, max(T.DL_BLER, 1e-5), "-o", "LineWidth", 1.2);
        end
        if ismember("UL_BLER", string(T.Properties.VariableNames))
            semilogy(T.SNR_dB, max(T.UL_BLER, 1e-5), "-s", "LineWidth", 1.2);
        end
        xlabel("SNR (dB)");
        ylabel("BLER");
        title("Link BLER vs SNR");
        grid on;
        legend("Location", "best");
        [nPlots, files] = localExportPlot(f, figDir, "campaign_link_snr_bler", nPlots, files);
        close(f);
    end
end

% 2) HARQ summary.
fHarq = fullfile(runFolder, "csv", "probe_harq_summary.csv");
if exist(fHarq, "file") == 2
    T = readtable(fHarq, "VariableNamingRule", "preserve");
    if ~isempty(T) && ismember("Mode", string(T.Properties.VariableNames))
        f = figure("Visible", "off");
        tiledlayout(1,2,"TileSpacing","compact");
        nexttile;
        if ismember("HARQ_ResidualBLER", string(T.Properties.VariableNames))
            bar(categorical(T.Mode), T.HARQ_ResidualBLER);
            ylabel("Residual BLER");
            title("HARQ Residual BLER");
            grid on;
        end
        nexttile;
        if ismember("HARQ_ThroughputEfficiency", string(T.Properties.VariableNames))
            bar(categorical(T.Mode), T.HARQ_ThroughputEfficiency);
            ylabel("Efficiency");
            title("HARQ Throughput Efficiency");
            grid on;
        end
        [nPlots, files] = localExportPlot(f, figDir, "campaign_harq_summary", nPlots, files);
        close(f);
    end
end

% 3) Sync/control metrics.
fSync = fullfile(runFolder, "csv", "probe_sync_control.csv");
if exist(fSync, "file") == 2
    T = readtable(fSync, "VariableNamingRule", "preserve");
    if ~isempty(T) && ismember("SNR_dB", string(T.Properties.VariableNames))
        f = figure("Visible", "off");
        hold on;
        if ismember("PBCH_DetectProb", string(T.Properties.VariableNames))
            plot(T.SNR_dB, T.PBCH_DetectProb, "-o", "LineWidth", 1.2);
        end
        if ismember("PRACH_DetectProb", string(T.Properties.VariableNames))
            plot(T.SNR_dB, T.PRACH_DetectProb, "-s", "LineWidth", 1.2);
        end
        if ismember("PDCCH_BLER", string(T.Properties.VariableNames))
            plot(T.SNR_dB, 1 - min(max(T.PDCCH_BLER,0),1), "-^", "LineWidth", 1.2);
        end
        xlabel("SNR (dB)");
        ylabel("Probability");
        title("Sync/Control Reliability");
        legend("PBCH Detect","PRACH Detect","1-PDCCH BLER", "Location", "best");
        grid on;
        [nPlots, files] = localExportPlot(f, figDir, "campaign_sync_control", nPlots, files);
        close(f);
    end
end

% 4) Interference.
fInterf = fullfile(runFolder, "csv", "probe_interference_sir_bler.csv");
if exist(fInterf, "file") == 2
    T = readtable(fInterf, "VariableNamingRule", "preserve");
    if ~isempty(T) && all(ismember(["SIR_dB","BLER"], string(T.Properties.VariableNames)))
        f = figure("Visible", "off");
        semilogy(T.SIR_dB, max(T.BLER,1e-5), "-o", "LineWidth", 1.2);
        xlabel("SIR (dB)");
        ylabel("BLER");
        title("Interference BLER vs SIR");
        grid on;
        [nPlots, files] = localExportPlot(f, figDir, "campaign_interference_bler", nPlots, files);
        close(f);
    end
end

% 5) Numerology.
fNum = fullfile(runFolder, "csv", "probe_numerology.csv");
if exist(fNum, "file") == 2
    T = readtable(fNum, "VariableNamingRule", "preserve");
    if ~isempty(T) && all(ismember(["SCS_kHz","DL_Throughput_Mbps"], string(T.Properties.VariableNames)))
        f = figure("Visible", "off");
        plot(T.SCS_kHz, T.DL_Throughput_Mbps, "-o", "LineWidth", 1.2);
        xlabel("SCS (kHz)");
        ylabel("DL Throughput (Mbps)");
        title("Numerology Performance");
        grid on;
        [nPlots, files] = localExportPlot(f, figDir, "campaign_numerology", nPlots, files);
        close(f);
    end
end

% 6) V2X and NTN.
fV2X = fullfile(runFolder, "csv", "probe_v2x_sidelink.csv");
if exist(fV2X, "file") == 2
    T = readtable(fV2X, "VariableNamingRule", "preserve");
    if ~isempty(T) && all(ismember(["Velocity_kmh","PacketReceptionRatio_WithComp"], string(T.Properties.VariableNames)))
        f = figure("Visible", "off");
        plot(T.Velocity_kmh, T.PacketReceptionRatio_WithComp, "-o", "LineWidth", 1.2);
        xlabel("Velocity (km/h)");
        ylabel("PRR");
        title("V2X PRR vs Velocity");
        grid on;
        [nPlots, files] = localExportPlot(f, figDir, "campaign_v2x_prr", nPlots, files);
        close(f);
    end
end

fNTN = fullfile(runFolder, "csv", "probe_ntn_delay_doppler.csv");
if exist(fNTN, "file") == 2
    T = readtable(fNTN, "VariableNamingRule", "preserve");
    if ~isempty(T) && all(ismember(["PropagationDelay_ms","BLER_NoComp","BLER_WithComp"], string(T.Properties.VariableNames)))
        f = figure("Visible", "off");
        hold on;
        plot(T.PropagationDelay_ms, T.BLER_NoComp, "-o", "LineWidth", 1.2);
        plot(T.PropagationDelay_ms, T.BLER_WithComp, "-s", "LineWidth", 1.2);
        xlabel("Propagation Delay (ms)");
        ylabel("BLER");
        title("NTN Compensation Benefit");
        legend("No Compensation","With Compensation","Location","best");
        grid on;
        [nPlots, files] = localExportPlot(f, figDir, "campaign_ntn_compensation", nPlots, files);
        close(f);
    end
end

% 7) E2E slot flow.
fE2E = fullfile(runFolder, "csv", "probe_e2e_slot_metrics.csv");
if exist(fE2E, "file") == 2
    T = readtable(fE2E, "VariableNamingRule", "preserve");
    if ~isempty(T) && all(ismember(["Slot","OfferedBits","DeliveredBits"], string(T.Properties.VariableNames)))
        f = figure("Visible", "off");
        hold on;
        plot(T.Slot, T.OfferedBits/1e6, "LineWidth", 1.1);
        plot(T.Slot, T.DeliveredBits/1e6, "LineWidth", 1.1);
        xlabel("Slot");
        ylabel("Mbits/slot");
        title("E2E Offered vs Delivered");
        legend("Offered","Delivered","Location","best");
        grid on;
        [nPlots, files] = localExportPlot(f, figDir, "campaign_e2e_flow", nPlots, files);
        close(f);
    end
end

out = struct();
out.Ok = true;
out.NumPlots = nPlots;
out.FigureFolder = figDir;
out.GeneratedFiles = files;
end

function [nPlots, files] = localExportPlot(figHandle, figDir, baseName, nPlots, files)
pngFile = fullfile(figDir, baseName + ".png");
pdfFile = fullfile(figDir, baseName + ".pdf");
exportgraphics(figHandle, pngFile, "Resolution", 200);
exportgraphics(figHandle, pdfFile, "ContentType", "vector");
nPlots = nPlots + 1;
files(end+1,1) = string(pngFile); %#ok<AGROW>
files(end+1,1) = string(pdfFile); %#ok<AGROW>
end

function out = localVerifyArtifacts(runFolder, requireCampaignPlots, opt)
if nargin < 2
    requireCampaignPlots = false;
end
if nargin < 3 || ~isstruct(opt)
    opt = struct();
end
spec = localArtifactSpec(requireCampaignPlots, opt);
n = numel(spec);
rows = repmat(struct( ...
    "Category", "", ...
    "ArtifactID", "", ...
    "Pattern", "", ...
    "Kind", "", ...
    "Required", true, ...
    "Exists", false, ...
    "FoundCount", 0, ...
    "Status", "", ...
    "Notes", ""), n, 1);

for i = 1:n
    p = fullfile(runFolder, char(spec(i).Pattern));
    d = dir(p);
    d = d(~[d.isdir]);
    found = numel(d);
    ex = found > 0;
    req = logical(spec(i).Required);
    if ex
        st = "ok";
    elseif req
        st = "missing_required";
    else
        st = "missing_optional";
    end
    rows(i) = struct( ...
        "Category", string(spec(i).Category), ...
        "ArtifactID", string(spec(i).ArtifactID), ...
        "Pattern", string(spec(i).Pattern), ...
        "Kind", string(spec(i).Kind), ...
        "Required", req, ...
        "Exists", ex, ...
        "FoundCount", found, ...
        "Status", st, ...
        "Notes", string(spec(i).Notes));
end

T = struct2table(rows);
reqMask = logical(T.Required);
reqCov = mean(double(T.Exists(reqMask)));
covPct = 100 * reqCov;
missingN = sum(reqMask & ~T.Exists);

csvFile = fullfile(runFolder, "csv", "full_3gpp_artifact_checklist.csv");
sixgr.util.csvWriteTable(csvFile, T);
mdFile = fullfile(runFolder, "full_3gpp_artifact_checklist.md");
localWriteArtifactChecklistMD(mdFile, T, covPct, missingN);

out = struct();
out.Ok = missingN == 0;
out.Table = T;
out.CSV = csvFile;
out.MD = mdFile;
out.Coverage_pct = covPct;
out.MissingCount = double(missingN);
end

function S = localArtifactSpec(requireCampaignPlots, opt)
if nargin < 1
    requireCampaignPlots = false;
end
if nargin < 2 || ~isstruct(opt)
    opt = struct();
end
requireAuxProbes = logical(sixgr.util.structGet(opt, "RunAuxiliaryProbes", false));
requireMMTC = logical(sixgr.util.structGet(opt, "RunSystemMMTCProbe", false));
requireSystemFigures = logical(sixgr.util.structGet(opt, "SystemSaveFigures", false));
S = repmat(struct("Category","","ArtifactID","","Pattern","","Kind","","Required",true,"Notes",""),0,1);

S(end+1) = localSpec("Run", "run_log", "logs/full_campaign.log", "log", true, "Top-level campaign log");
S(end+1) = localSpec("Run", "run_report_mat", "mat/full_campaign_report.mat", "mat", true, "Top-level report MAT");
S(end+1) = localSpec("Run", "run_report_md", "full_campaign_report.md", "md", true, "Top-level report markdown");
S(end+1) = localSpec("Run", "category_audit", "csv/full_3gpp_category_audit.csv", "csv", true, "25-category audit table");
S(end+1) = localSpec("Run", "structured_manifest", "analysis_by_block/run/meta/structured_manifest.csv", "csv", false, "Structured manifest (if organizer succeeds)");
S(end+1) = localSpec("Run", "campaign_plots", "fig/campaign_*.png", "fig", logical(requireCampaignPlots), "Campaign-level synthesized plots");
S(end+1) = localSpec("Run", "calibration_bler_db_mat", "calibration/bler_db.mat", "mat", true, "Calibration BLER DB MAT");
S(end+1) = localSpec("Run", "calibration_bler_db_metadata", "calibration/bler_db_metadata.json", "json", true, "Calibration BLER DB metadata");
S(end+1) = localSpec("Run", "calibration_coverage", "calibration/calibration_coverage.csv", "csv", true, "Calibration coverage summary");
S(end+1) = localSpec("Run", "calibration_validation", "calibration/calibration_validation.csv", "csv", true, "Calibration validation metrics");
S(end+1) = localSpec("Run", "meta_run_manifest", "meta/run_manifest.json", "json", true, "Run-level reproducibility manifest");
S(end+1) = localSpec("Run", "meta_environment", "meta/environment.json", "json", true, "MATLAB/host/toolbox environment snapshot");
S(end+1) = localSpec("Run", "meta_seeds", "meta/seeds.csv", "csv", true, "Seed table for deterministic replay");
S(end+1) = localSpec("Run", "meta_approximations", "meta/approximations_used.csv", "csv", true, "Approximations/proxy modes used in run");
S(end+1) = localSpec("Run", "meta_calibration_source", "meta/calibration_source.json", "json", true, "Calibration provenance snapshot");

S(end+1) = localSpec("1. Error Performance Metrics", "lls_kpi", "link/csv/lls_kpi_summary.csv", "csv", true, "BER/BLER summary");
S(end+1) = localSpec("1. Error Performance Metrics", "dl_pdsch_trials", "link/csv/dl_pdsch_trials.csv", "csv", true, "Per-trial DL PDSCH trace");
S(end+1) = localSpec("1. Error Performance Metrics", "ul_pusch_trials", "link/csv/ul_pusch_trials.csv", "csv", true, "Per-trial UL PUSCH trace");
S(end+1) = localSpec("1. Error Performance Metrics", "pdcch_trials", "link/csv/pdcch_trials.csv", "csv", true, "Per-trial PDCCH trace");
S(end+1) = localSpec("1. Error Performance Metrics", "pucch_trials", "link/csv/pucch_trials.csv", "csv", true, "Per-trial PUCCH trace");
S(end+1) = localSpec("1. Error Performance Metrics", "pbch_trials", "link/csv/pbch_trials.csv", "csv", true, "Per-trial PBCH trace");
S(end+1) = localSpec("1. Error Performance Metrics", "prach_trials", "link/csv/prach_trials.csv", "csv", true, "Per-trial PRACH trace");
S(end+1) = localSpec("1. Error Performance Metrics", "srs_trials", "link/csv/srs_trials.csv", "csv", true, "Per-trial SRS trace");
S(end+1) = localSpec("1. Error Performance Metrics", "control_cell_search_trials", "control/csv/cell_search_trials.csv", "csv", true, "Control-plane cell-search trial trace");
S(end+1) = localSpec("1. Error Performance Metrics", "control_pbch_recovery_trials", "control/csv/pbch_recovery_trials.csv", "csv", true, "Control-plane PBCH recovery trial trace");
S(end+1) = localSpec("1. Error Performance Metrics", "control_prach_trials", "control/csv/prach_trials.csv", "csv", true, "Control-plane PRACH trial trace");
S(end+1) = localSpec("1. Error Performance Metrics", "control_pdcch_trials", "control/csv/pdcch_trials.csv", "csv", true, "Control-plane PDCCH trial trace");
S(end+1) = localSpec("1. Error Performance Metrics", "control_pucch_trials", "control/csv/pucch_trials.csv", "csv", true, "Control-plane PUCCH trial trace");
S(end+1) = localSpec("2. Throughput and Rate Metrics", "lls_snr", "link/csv/lls_snr_sweep.csv", "csv", true, "Throughput vs SNR");
S(end+1) = localSpec("3. Signal Quality and CSI", "sync_ctrl", "csv/probe_sync_control.csv", "csv", requireAuxProbes, "SNR/control quality probes");
S(end+1) = localSpec("4. Channel Estimation and Equalization", "lls_link_results", "link/mat/link_results.mat", "mat", true, "Channel/equalization artifacts");
S(end+1) = localSpec("5. MIMO and Beamforming", "beam_mimo", "csv/probe_beam_mimo.csv", "csv", requireAuxProbes, "MIMO/beam probe");
S(end+1) = localSpec("6. Link Adaptation", "snr_sweep", "link/csv/lls_snr_sweep.csv", "csv", true, "MCS adaptation proxy");
S(end+1) = localSpec("7. HARQ and Retransmissions", "harq_summary", "csv/probe_harq_summary.csv", "csv", requireAuxProbes, "HARQ summary");
S(end+1) = localSpec("8. Latency and Timing", "harq_packets", "csv/probe_harq_packets.csv", "csv", requireAuxProbes, "RTT/processing delay proxy");
S(end+1) = localSpec("9. Power and Energy Efficiency", "rf_energy", "csv/probe_rf_energy.csv", "csv", requireAuxProbes, "Energy/power probe");
S(end+1) = localSpec("10. Synchronization and Timing Offsets", "sync", "csv/probe_sync_control.csv", "csv", requireAuxProbes, "Sync metrics");
S(end+1) = localSpec("11. Channel Coding and Decoding", "harq_packets", "csv/probe_harq_packets.csv", "csv", requireAuxProbes, "Decoder iterations");
S(end+1) = localSpec("12. Modulation and Waveform Quality", "rf_energy", "csv/probe_rf_energy.csv", "csv", requireAuxProbes, "EVM/PAPR proxy");
S(end+1) = localSpec("13. Interference Analysis", "sir_bler", "csv/probe_interference_sir_bler.csv", "csv", requireAuxProbes, "Interference probe");
S(end+1) = localSpec("13. Interference Analysis", "sys_interference_detail", "system/csv/system_interference_detail.csv", "csv", true, "Per-UE interference decomposition trace");
S(end+1) = localSpec("14. Mobility and Time-Varying Channels", "sys_timeseries", "system/csv/system_time_series.csv", "csv", true, "Mobility time series");
S(end+1) = localSpec("14. Mobility and Time-Varying Channels", "sys_handover_events", "system/csv/system_handover_events.csv", "csv", true, "Handover events and interruption timing");
S(end+1) = localSpec("14. Mobility and Time-Varying Channels", "sys_beam_events", "system/csv/system_beam_events.csv", "csv", true, "Beam update/switch event log");
S(end+1) = localSpec("15. Multi-User and Multi-Cell Metrics", "sys_kpi", "system/csv/system_kpis.csv", "csv", true, "System KPIs");
S(end+1) = localSpec("15. Multi-User and Multi-Cell Metrics", "sys_cell_load", "system/csv/system_cell_load.csv", "csv", true, "Per-cell offered/served/queued load");
S(end+1) = localSpec("15. Multi-User and Multi-Cell Metrics", "sys_scheduler_grants", "system/csv/system_scheduler_grants.csv", "csv", true, "Per-grant scheduler trace");
S(end+1) = localSpec("15. Multi-User and Multi-Cell Metrics", "sys_harq_processes", "system/csv/system_harq_processes.csv", "csv", true, "HARQ process outcomes by grant");
S(end+1) = localSpec("16. Beam Management", "beam_mimo", "csv/probe_beam_mimo.csv", "csv", requireAuxProbes, "Beam tracking/selection proxy");
S(end+1) = localSpec("17. Waveform and Numerology Specifics", "numerology", "csv/probe_numerology.csv", "csv", requireAuxProbes, "Numerology sweep");
S(end+1) = localSpec("18. Control Channel and Random Access", "sync", "csv/probe_sync_control.csv", "csv", requireAuxProbes, "PDCCH/PUCCH/PRACH");
S(end+1) = localSpec("18. Control Channel and Random Access", "attach_state_trace", "control/csv/attach_state_trace.csv", "csv", true, "Attach state transition trace");
S(end+1) = localSpec("18. Control Channel and Random Access", "rrc_message_trace", "control/csv/rrc_message_trace.csv", "csv", true, "RRC message sequence trace");
S(end+1) = localSpec("19. Hardware Impairments", "rf", "csv/probe_rf_energy.csv", "csv", requireAuxProbes, "RF impairment probe");
S(end+1) = localSpec("20. Reliability and Outage", "harq_summary", "csv/probe_harq_summary.csv", "csv", requireAuxProbes, "Residual BLER/outage proxy");
S(end+1) = localSpec("21. Massive MTC Metrics", "mmtc", "csv/probe_mmtc_kpis.csv", "csv", requireMMTC, "mMTC KPIs");
S(end+1) = localSpec("22. V2X Metrics", "v2x", "csv/probe_v2x_sidelink.csv", "csv", requireAuxProbes, "V2X sidelink KPIs");
S(end+1) = localSpec("23. NTN Metrics", "ntn", "csv/probe_ntn_delay_doppler.csv", "csv", requireAuxProbes, "NTN KPIs");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_summary", "csv/probe_e2e_summary.csv", "csv", true, "Cross-layer KPIs");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_packet_integrity", "csv/probe_e2e_packet_integrity.csv", "csv", true, "Packet-level integrity and deadline checks");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_packet_trace", "end_to_end/csv/e2e_packet_trace.csv", "csv", true, "Per-packet E2E trace");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_flow_summary", "end_to_end/csv/e2e_flow_summary.csv", "csv", true, "Per-flow E2E packet summary");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_bearer_summary", "end_to_end/csv/e2e_bearer_summary.csv", "csv", true, "Per-bearer E2E packet summary");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_attach_trace", "end_to_end/csv/e2e_attach_trace.csv", "csv", true, "Attach control-plane event trace");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_harq_trace", "end_to_end/csv/e2e_harq_trace.csv", "csv", true, "HARQ transmission outcomes");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_scheduler_trace", "end_to_end/csv/e2e_scheduler_trace.csv", "csv", true, "Scheduler grant-level trace");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_drop_causes", "end_to_end/csv/e2e_drop_causes.csv", "csv", true, "Packet drop-cause summary");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_latency_cdf_fig", "end_to_end/fig/e2e_latency_cdf.png", "fig", false, "Latency CDF figure (when E2ESaveFigures=true)");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_jitter_cdf_fig", "end_to_end/fig/e2e_jitter_cdf.png", "fig", false, "Jitter CDF figure (when E2ESaveFigures=true)");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_latency_percentiles_fig", "end_to_end/fig/e2e_latency_percentiles.png", "fig", false, "P95/P99/P99.9 latency figure (when E2ESaveFigures=true)");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_deadline_miss_vs_load_fig", "end_to_end/fig/e2e_deadline_miss_vs_offered_load.png", "fig", false, "Deadline-miss vs offered-load figure (when E2ESaveFigures=true)");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_drop_cause_breakdown_fig", "end_to_end/fig/e2e_drop_cause_breakdown.png", "fig", false, "Drop-cause breakdown figure (when E2ESaveFigures=true)");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_retx_depth_hist_fig", "end_to_end/fig/e2e_retx_depth_histogram.png", "fig", false, "Retransmission-depth histogram (when E2ESaveFigures=true)");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_attach_delay_hist_fig", "end_to_end/fig/e2e_attach_delay_histogram.png", "fig", false, "Attach delay histogram (when E2ESaveFigures=true)");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_per_flow_throughput_fig", "end_to_end/fig/e2e_per_flow_throughput.png", "fig", false, "Per-flow throughput figure (when E2ESaveFigures=true)");
S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_per_bearer_qos_fig", "end_to_end/fig/e2e_per_bearer_qos_compliance.png", "fig", false, "Per-bearer QoS compliance figure (when E2ESaveFigures=true)");
S(end+1) = localSpec("25. Miscellaneous Statistical Outputs", "sys_fig", "system/fig/*.png", "fig", requireSystemFigures, "Time-series/CDF plots");
end

function r = localSpec(cat, id, pat, kind, req, notes)
r = struct();
r.Category = string(cat);
r.ArtifactID = string(id);
r.Pattern = string(pat);
r.Kind = string(kind);
r.Required = logical(req);
r.Notes = string(notes);
end

function localWriteArtifactChecklistMD(mdFile, T, covPct, missingN)
fid = fopen(mdFile, "w");
if fid < 0
    return;
end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "# Artifact Checklist\n\n");
fprintf(fid, "- Required coverage: `%.2f%%`\n", covPct);
fprintf(fid, "- Missing required items: `%d`\n\n", missingN);
fprintf(fid, "| Category | Artifact | Pattern | Exists | FoundCount | Status |\n");
fprintf(fid, "|---|---|---|---:|---:|---|\n");
for i = 1:height(T)
    fprintf(fid, "| %s | %s | `%s` | %d | %d | %s |\n", ...
        char(T.Category(i)), char(T.ArtifactID(i)), char(T.Pattern(i)), ...
        double(T.Exists(i)), double(T.FoundCount(i)), char(T.Status(i)));
end
end

function localWriteMarkdown(mdFile, summary, audit)
fid = fopen(mdFile, "w");
if fid < 0
    return;
end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "# Full 3GPP Campaign Report\n\n");
fprintf(fid, "- Run folder: `%s`\n", summary.RunFolder);
fprintf(fid, "- Link run folder: `%s`\n", summary.LinkRunFolder);
fprintf(fid, "- Detailed LLS folder: `%s`\n", summary.DetailRunFolder);
fprintf(fid, "- System folder: `%s`\n", summary.SystemRunFolder);
fprintf(fid, "- mMTC folder: `%s`\n\n", summary.MMTCFolder);
fprintf(fid, "- End-to-end stack folder: `%s`\n", summary.E2EFolder);
if isfield(summary, "CalibrationFolder")
    fprintf(fid, "- Calibration folder: `%s`\n", string(summary.CalibrationFolder));
end
if isfield(summary, "CalibrationDBMat")
    fprintf(fid, "- Calibration DB MAT: `%s`\n", string(summary.CalibrationDBMat));
end
if isfield(summary, "CalibrationMetadataJSON")
    fprintf(fid, "- Calibration metadata JSON: `%s`\n", string(summary.CalibrationMetadataJSON));
end
if isfield(summary, "CalibrationCoverageCSV")
    fprintf(fid, "- Calibration coverage CSV: `%s`\n", string(summary.CalibrationCoverageCSV));
end
if isfield(summary, "CalibrationValidationCSV")
    fprintf(fid, "- Calibration validation CSV: `%s`\n", string(summary.CalibrationValidationCSV));
end
if isfield(summary, "CalibrationSource")
    fprintf(fid, "- Calibration source: `%s`\n", string(summary.CalibrationSource));
end
if isfield(summary, "MetaFolder")
    fprintf(fid, "- Metadata folder: `%s`\n", string(summary.MetaFolder));
end
if isfield(summary, "MetaRunManifestJSON")
    fprintf(fid, "- Run manifest JSON: `%s`\n", string(summary.MetaRunManifestJSON));
end
if isfield(summary, "MetaEnvironmentJSON")
    fprintf(fid, "- Environment JSON: `%s`\n", string(summary.MetaEnvironmentJSON));
end
if isfield(summary, "MetaSeedsCSV")
    fprintf(fid, "- Seeds CSV: `%s`\n", string(summary.MetaSeedsCSV));
end
if isfield(summary, "MetaApproximationsCSV")
    fprintf(fid, "- Approximations CSV: `%s`\n", string(summary.MetaApproximationsCSV));
end
if isfield(summary, "MetaCalibrationSourceJSON")
    fprintf(fid, "- Calibration source JSON: `%s`\n", string(summary.MetaCalibrationSourceJSON));
end
if isfield(summary, "CampaignPlotFolder")
    fprintf(fid, "- Campaign plots folder: `%s` (count=%g)\n", string(summary.CampaignPlotFolder), double(sixgr.util.structGet(summary, "CampaignPlotCount", NaN)));
end
if isfield(summary, "ArtifactChecklistCSV")
    fprintf(fid, "- Artifact checklist CSV: `%s`\n", string(summary.ArtifactChecklistCSV));
end
if isfield(summary, "ArtifactCoverage_pct")
    fprintf(fid, "- Artifact required coverage: `%.2f%%` (missing=%g)\n", ...
        double(sixgr.util.structGet(summary, "ArtifactCoverage_pct", NaN)), ...
        double(sixgr.util.structGet(summary, "ArtifactMissingCount", NaN)));
end
if isfield(summary, "StructuredFolder")
    fprintf(fid, "- Structured block-wise folder: `%s`\n", string(summary.StructuredFolder));
end
if isfield(summary, "StructuredMirrorFolder")
    fprintf(fid, "- Structured mirror folder: `%s`\n", string(summary.StructuredMirrorFolder));
end
fprintf(fid, "- Overall status: `%s`\n\n", string(summary.Ok));
fprintf(fid, "## 25-Category Audit\n\n");
for i = 1:height(audit)
    fprintf(fid, "- **%s**: `%s` (%s)\n", char(audit.Category(i)), char(audit.Status(i)), char(audit.Notes(i)));
end
end

function p = localResolveResultsRoot(inPath)
p = char(string(inPath));
if strlength(string(p)) == 0
    p = "results";
end
p = char(string(strtrim(p)));
if ispc
    isAbs = ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once')) || startsWith(p, "\\");
else
    isAbs = startsWith(p, "/");
end
if ~isAbs
    p = fullfile(pwd, p);
end
p = char(string(p));
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
if exist("sixgr_awgn_complex_kernel_mex", "file") == 3 || exist("sixgr_awgn_complex_kernel", "file") == 2
    try
        if exist("sixgr_awgn_complex_kernel_mex", "file") == 3
            [y, nVar] = sixgr_awgn_complex_kernel_mex(x, double(snr_dB));
        else
            [y, nVar] = sixgr_awgn_complex_kernel(x, double(snr_dB));
        end
        return;
    catch
    end
end
snrLin = 10.^(snr_dB/10);
sigPow = mean(abs(x(:)).^2);
nVar = sigPow / max(snrLin, eps);
n = sqrt(nVar/2) * (randn(size(x)) + 1i*randn(size(x)));
y = x + n;
end

function y = localApplyFrequencyOffset(x, foff_Hz, fs_Hz)
y = x;
if isempty(x) || ~isfinite(foff_Hz) || abs(foff_Hz) <= 0
    return;
end
if exist("sixgr_freq_shift_kernel_mex", "file") == 3 || exist("sixgr_freq_shift_kernel", "file") == 2
    try
        if exist("sixgr_freq_shift_kernel_mex", "file") == 3
            y = sixgr_freq_shift_kernel_mex(x, double(fs_Hz), double(foff_Hz));
        else
            y = sixgr_freq_shift_kernel(x, double(fs_Hz), double(foff_Hz));
        end
        return;
    catch
    end
end
n = (0:size(x,1)-1).';
rot = exp(1i * 2*pi * (foff_Hz/max(fs_Hz,eps)) * n);
y = x .* rot;
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

function p = localPapr(x)
v = abs(x(:)).^2;
p = 10*log10(max(v) / max(mean(v), eps));
end
