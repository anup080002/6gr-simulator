function report = sixgr_run_3gpp_full_campaign(cfgFile, varargin)
%SIXGR_RUN_3GPP_FULL_CAMPAIGN Unified 3GPP-oriented analysis campaign.
%
% This orchestrator runs multiple analyses and stores all artifacts under one
% parent folder with structured subfolders per simulator domain:
%   - air_interface/        : link-level waveform outputs
%   - air_interface/detailed: detailed PHY diagnostics
%   - system/               : mobility/system-level KPIs
%   - mmtc/                 : mMTC traffic profile KPIs
%   - packet_flow/          : end-to-end stack outputs
%   - control/              : control-plane traces and attach signaling
%   - reports/              : markdown/MAT/csv reports and audits
%   - meta/                 : reproducibility manifests and config snapshots
%   - logs/                 : campaign log
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
ip.addParameter("RunLinkCampaign", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("RunDetailedLinkDiagnostics", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("SystemDuration_s", 20, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter("SystemNumUE", 32, @(x)isnumeric(x)&&isscalar(x)&&x>=4);
ip.addParameter("SystemDetailedTrace", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("SystemSaveFigures", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("RunSystemMMTCProbe", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("MMTCNumUE", 0, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter("MMTCSaveFigures", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("RunAuxiliaryProbes", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("UseFastLinkModel", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
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
ip.addParameter("E2EAirModel", "truth", @(x)ischar(x)||isstring(x));
ip.addParameter("E2EScaleServiceWithCompression", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2EServiceScaleCap", 256, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter("E2EStrictValidation", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2ETruthMaxSlots", 240, @(x)isnumeric(x)&&isscalar(x)&&x>=20);
ip.addParameter("E2EEnableSemanticChecks", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2EScaleChunkWithCompression", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2EMaxSDUChunkBytes", 4*1024*1024, @(x)isnumeric(x)&&isscalar(x)&&x>=1024);
ip.addParameter("E2EFastTraceMode", "lite", @(x)ischar(x)||isstring(x));
ip.addParameter("E2ETruthFastAWGNPath", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2ETruthCompactPHYIO", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2ETruthAdaptiveLDPC", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2ETruthLDPCMaxIterations", 0, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter("E2ETruthUseGPU", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("CalibrateSystemBLERFromLink", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("ReuseLinkForDetailedDiagnostics", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("MirrorStructuredResults", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("OrganizeByBlock", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("GenerateCampaignPlots", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("VerifyArtifacts", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("CampaignProfileMode", "", @(x)ischar(x)||isstring(x));
ip.addParameter("CampaignProfileEntryPoint", "", @(x)ischar(x)||isstring(x));
ip.addParameter("NoProxyTruthContract", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("SetupToolboxChecks", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("Verbose", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.parse(cfgFile, varargin{:});
optUser = ip.Results;
opt = optUser;
profileMeta = localNormalizeCampaignProfileMeta( ...
    sixgr.util.structGet(opt, "CampaignProfileMode", ""), ...
    sixgr.util.structGet(opt, "CampaignProfileEntryPoint", ""));
opt.CampaignProfileMode = char(string(profileMeta.Mode));
opt.CampaignProfileLabel = char(string(profileMeta.Label));
opt.CampaignProfileEntryPoint = char(string(profileMeta.EntryPoint));

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
cfg.run.noProxyTruthContract = localNoProxyTruthContractEnabled(cfg, opt);
localRejectRemovedProxyModes(cfg, opt);
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
[runBucket, runProfile] = localCampaignRunFolderClass(opt, profileMeta);
runFolder = sixgr.report.defaultRunFolder(resultsRoot, ...
    "Bucket", runBucket, ...
    "Profile", runProfile, ...
    "Leaf", "current", ...
    "CleanExisting", true);
layout = sixgr.report.resultLayout(runFolder);

logFile = fullfile(runFolder, "logs", "full_campaign.log");
L = sixgr.core.Logger(logFile, "Level", 3, "EchoToConsole", verbose);
L.info("Starting full 3GPP campaign");
L.info("Run folder: " + string(runFolder));
onlyE2E = logical(opt.OnlyE2E);
runMMTC = logical(opt.RunSystemMMTCProbe);
runAux = logical(opt.RunAuxiliaryProbes);
runLinkCampaign = ~onlyE2E && logical(sixgr.util.structGet(opt, "RunLinkCampaign", true));
runDetailedDiagnostics = ~onlyE2E && logical(sixgr.util.structGet(opt, "RunDetailedLinkDiagnostics", true));
runSystemCampaign = ~onlyE2E;
organizeByBlock = logical(opt.OrganizeByBlock);
localGuardTruthE2ESystemCoupling(cfg, opt, onlyE2E, runSystemCampaign);
localEnforceNoProxyTruthContract(cfg, opt, onlyE2E, runLinkCampaign, runSystemCampaign);

% Save resolved config snapshot.
try
    sixgr.util.jsonWrite(layout.ConfigResolvedJSON, cfg);
catch
end

% -------------------------------------------------------------------------
% 1) Link-level campaign (main)
% -------------------------------------------------------------------------
linkFolder = layout.AirInterfaceDir;
detailDst = layout.DetailedLLSDir;
sysDst = fullfile(runFolder, "system");
e2eAirLUT = struct();
sysBlerLUT = struct();
if onlyE2E
    L.info("OnlyE2E=true: skipping link/system/auxiliary probes and running E2E stack only.");
    link = localMarkModuleSkipped(struct("Ok", false, "RunFolder", linkFolder, "Result", struct(), ...
        "KPITable", table(), "SNRSweep", table(), "Errors", strings(0,1), ...
        "Artifacts", struct("csv",{{}}, "mat",{{}}, "fig",{{}}, "m",{{}})), ...
        "Skipped by OnlyE2E=true");
    detailed = localMarkModuleSkipped(struct("Ok", false, "RunFolder", detailDst, "Result", struct(), ...
        "Table", table(), "Errors", strings(0,1)), ...
        "Skipped by OnlyE2E=true");
    sys = localMarkModuleSkipped(struct("Ok", false, "RunFolder", sysDst, "Result", struct(), ...
        "KPITable", table(), "Errors", strings(0,1)), ...
        "Skipped by OnlyE2E=true");
    mmtc = localMarkModuleSkipped(struct("Ok", false, "Result", struct(), "Table", table()), ...
        "Skipped by OnlyE2E=true");
    harq = localMarkModuleSkipped(struct("Ok", false, "PacketTable", table(), "SummaryTable", table()), ...
        "Skipped by OnlyE2E=true");
    syncCtrl = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
        "Skipped by OnlyE2E=true");
    v2x = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
        "Skipped by OnlyE2E=true");
    ntn = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
        "Skipped by OnlyE2E=true");
    interf = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
        "Skipped by OnlyE2E=true");
    rfp = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
        "Skipped by OnlyE2E=true");
    numProbe = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
        "Skipped by OnlyE2E=true");
    beam = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
        "Skipped by OnlyE2E=true");
else
    if runLinkCampaign
        L.info("Running link-level campaign");
        link = localRunLinkCampaign(cfg, linkFolder, opt);
        if logical(opt.CalibrateSystemBLERFromLink)
            error("sixgr:campaign:ProxyModeRemoved", ...
                "CalibrateSystemBLERFromLink=true is no longer supported because BLER calibration/LUT proxy paths were removed.");
        end
    else
        L.info("RunLinkCampaign=false: skipping link-level campaign.");
        link = localMarkModuleSkipped(struct("Ok", false, "RunFolder", linkFolder, "Result", struct(), ...
            "KPITable", table(), "SNRSweep", table(), "Errors", strings(0,1), ...
            "Artifacts", struct("csv",{{}}, "mat",{{}}, "fig",{{}}, "m",{{}})), ...
            "Skipped by RunLinkCampaign=false");
    end

    % ---------------------------------------------------------------------
    % 2) Detailed link-level diagnostics
    % ---------------------------------------------------------------------
    if runDetailedDiagnostics
        L.info("Running detailed link-level diagnostics");
        detailed = localRunDetailedDiagnostics(cfg, detailDst, opt, link);
    else
        L.info("RunDetailedLinkDiagnostics=false: skipping detailed link-level diagnostics.");
        detailed = localMarkModuleSkipped(struct("Ok", false, "RunFolder", detailDst, "Result", struct(), ...
            "Table", table(), "Errors", strings(0,1)), ...
            "Skipped by RunDetailedLinkDiagnostics=false");
    end

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
        mmtc = localRunMMTCProbe(cfg, layout.MMTCDir, opt, sysBlerLUT);
        sixgr.util.csvWriteTable(fullfile(layout.MMTCCSVDir, "probe_mmtc_kpis.csv"), mmtc.Table);
    else
        mmtc = localMarkModuleSkipped(struct("Ok", false, "Result", struct(), "Table", table()), ...
            "Skipped by RunSystemMMTCProbe=false");
    end

    if runAux
        % -----------------------------------------------------------------
        % 5) HARQ probe
        % -----------------------------------------------------------------
        L.info("Running HARQ probe");
        harq = localRunHARQProbe(cfg, double(opt.LinkSNR_dB), round(double(opt.HARQPackets)), round(double(opt.HARQMaxRetx)));
        sixgr.util.csvWriteTable(fullfile(layout.HARQCSVDir, "probe_harq_packets.csv"), harq.PacketTable);
        sixgr.util.csvWriteTable(fullfile(layout.HARQCSVDir, "probe_harq_summary.csv"), harq.SummaryTable);

        % -----------------------------------------------------------------
        % 6) Sync/control probe
        % -----------------------------------------------------------------
        L.info("Running synchronization/control probe");
        syncCtrl = localRunSyncControlProbe(cfg, double(opt.LinkSNR_dB));
        sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "probe_sync_control.csv"), syncCtrl.Table);

        % -----------------------------------------------------------------
        % 7) V2X sidelink probe
        % -----------------------------------------------------------------
        L.info("Running V2X sidelink probe");
        v2x = localRunV2XProbe(cfg, opt, double(opt.LinkSNR_dB));
        sixgr.util.csvWriteTable(fullfile(layout.V2XCSVDir, "probe_v2x_sidelink.csv"), v2x.Table);

        % -----------------------------------------------------------------
        % 8) NTN delay/doppler probe
        % -----------------------------------------------------------------
        L.info("Running NTN delay/doppler probe");
        ntn = localRunNTNProbe(cfg, opt, double(opt.LinkSNR_dB));
        sixgr.util.csvWriteTable(fullfile(layout.NTNCSVDir, "probe_ntn_delay_doppler.csv"), ntn.Table);

        % -----------------------------------------------------------------
        % 9) Interference probe
        % -----------------------------------------------------------------
        L.info("Running interference probe");
        interf = localRunInterferenceProbe(cfg, [-10 -5 0 5 10 15], 8);
        sixgr.util.csvWriteTable(fullfile(layout.InterferenceCSVDir, "probe_interference_sir_bler.csv"), interf.Table);

        % -----------------------------------------------------------------
        % 10) RF impairment + energy probe
        % -----------------------------------------------------------------
        L.info("Running RF/energy probe");
        rfp = localRunRFProbe(cfg);
        sixgr.util.csvWriteTable(fullfile(layout.RFCSVDir, "probe_rf_energy.csv"), rfp.Table);

        % -----------------------------------------------------------------
        % 11) Numerology probe
        % -----------------------------------------------------------------
        L.info("Running numerology probe");
        numProbe = localRunNumerologyProbe(cfg, double(opt.LinkSNR_dB), [15 30 60], 8);
        sixgr.util.csvWriteTable(fullfile(layout.NumerologyCSVDir, "probe_numerology.csv"), numProbe.Table);

        % -----------------------------------------------------------------
        % 12) Beam/MIMO probe
        % -----------------------------------------------------------------
        L.info("Running beam/MIMO probe");
        beam = localRunBeamMIMOProbe(cfg, double(opt.LinkSNR_dB));
        sixgr.util.csvWriteTable(fullfile(layout.BeamformingCSVDir, "probe_beam_mimo.csv"), beam.Table);
    else
        harq = localMarkModuleSkipped(struct("Ok", false, "PacketTable", table(), "SummaryTable", table()), ...
            "Skipped by RunAuxiliaryProbes=false");
        syncCtrl = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
            "Skipped by RunAuxiliaryProbes=false");
        v2x = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
            "Skipped by RunAuxiliaryProbes=false");
        ntn = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
            "Skipped by RunAuxiliaryProbes=false");
        interf = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
            "Skipped by RunAuxiliaryProbes=false");
        rfp = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
            "Skipped by RunAuxiliaryProbes=false");
        numProbe = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
            "Skipped by RunAuxiliaryProbes=false");
        beam = localMarkModuleSkipped(struct("Ok", false, "Table", table()), ...
            "Skipped by RunAuxiliaryProbes=false");
    end
end

% -------------------------------------------------------------------------
% 13) End-to-end stack probe (SDAP/PDCP/RLC/MAC/RRC/AI hooks)
% -------------------------------------------------------------------------
if logical(opt.RunE2EStackProbe)
    L.info("Running end-to-end stack probe");
    e2e = localRunEndToEndProbe(cfg, layout.PacketFlowDir, opt, e2eAirLUT);
    sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "probe_e2e_slot_metrics.csv"), e2e.SlotTable);
    sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "probe_e2e_component_io.csv"), e2e.ComponentIOTable);
    sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "probe_e2e_component_checks.csv"), e2e.CheckTable);
    sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "probe_e2e_packet_integrity.csv"), e2e.PacketIntegrityTable);
    sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "probe_e2e_summary.csv"), e2e.SummaryTable);
    if isfield(e2e, "QoSEvaluationTable") && istable(e2e.QoSEvaluationTable)
        sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "probe_e2e_qos_evaluation.csv"), e2e.QoSEvaluationTable);
    end
    sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "probe_e2e_ai_metrics.csv"), e2e.AITable);
    if isfield(e2e, "ArtifactSpec") && isstruct(e2e.ArtifactSpec)
        topSpec = sixgr.util.structGet(e2e.ArtifactSpec, "TopLevel", struct());
        if isfield(topSpec, "SlotMetricsCSV")
            e2e.SlotMetricsArtifactCSV = fullfile(layout.PacketFlowCSVDir, char(string(topSpec.SlotMetricsCSV)));
            sixgr.util.csvWriteTable(e2e.SlotMetricsArtifactCSV, e2e.SlotTable);
        end
        if isfield(topSpec, "ComponentIOCSV")
            e2e.ComponentIOArtifactCSV = fullfile(layout.PacketFlowCSVDir, char(string(topSpec.ComponentIOCSV)));
            sixgr.util.csvWriteTable(e2e.ComponentIOArtifactCSV, e2e.ComponentIOTable);
        end
        if isfield(topSpec, "ComponentChecksCSV")
            e2e.ComponentChecksArtifactCSV = fullfile(layout.PacketFlowCSVDir, char(string(topSpec.ComponentChecksCSV)));
            sixgr.util.csvWriteTable(e2e.ComponentChecksArtifactCSV, e2e.CheckTable);
        end
        if isfield(topSpec, "PacketIntegrityCSV")
            e2e.PacketIntegrityArtifactCSV = fullfile(layout.PacketFlowCSVDir, char(string(topSpec.PacketIntegrityCSV)));
            sixgr.util.csvWriteTable(e2e.PacketIntegrityArtifactCSV, e2e.PacketIntegrityTable);
        end
        if isfield(topSpec, "SummaryCSV")
            e2e.SummaryArtifactCSV = fullfile(layout.PacketFlowCSVDir, char(string(topSpec.SummaryCSV)));
            sixgr.util.csvWriteTable(e2e.SummaryArtifactCSV, e2e.SummaryTable);
        end
        if isfield(topSpec, "QoSEvaluationCSV") && isfield(e2e, "QoSEvaluationTable") && istable(e2e.QoSEvaluationTable)
            e2e.QoSEvaluationArtifactCSV = fullfile(layout.PacketFlowCSVDir, char(string(topSpec.QoSEvaluationCSV)));
            sixgr.util.csvWriteTable(e2e.QoSEvaluationArtifactCSV, e2e.QoSEvaluationTable);
        end
        if isfield(topSpec, "AIMetricsCSV")
            e2e.AIArtifactCSV = fullfile(layout.PacketFlowCSVDir, char(string(topSpec.AIMetricsCSV)));
            sixgr.util.csvWriteTable(e2e.AIArtifactCSV, e2e.AITable);
        end
    end
else
    e2e = localMarkModuleSkipped(struct(), "Skipped by RunE2EStackProbe=false");
    e2e.Ok = false;
    e2e.RunFolder = "";
    e2e.ExecutionMode = "";
    e2e.ArtifactMode = "";
    e2e.ArtifactSpec = struct();
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
end

% -------------------------------------------------------------------------
% 13b) Control-plane detailed trace package
% -------------------------------------------------------------------------
if onlyE2E
    controlTrace = localMarkModuleSkipped(struct( ...
        "Folder", "", ...
        "CellSearchTrialsCSV", "", ...
        "PBCHRecoveryTrialsCSV", "", ...
        "PRACHTrialsCSV", "", ...
        "PDCCHTrialsCSV", "", ...
        "PUCCHTrialsCSV", "", ...
        "AttachStateTraceCSV", "", ...
        "RRCMessageTraceCSV", ""), ...
        "Skipped by OnlyE2E=true");
else
    controlTrace = localExportControlPlaneTraces(runFolder, link, e2e, syncCtrl);
end

% -------------------------------------------------------------------------
% 14) Calibration artifact package (BLER DB + metadata/coverage/validation)
% -------------------------------------------------------------------------
calibration = struct("Ok", false, "CalibrationFolder", "", "BLERDBMat", "", ...
    "MetadataJSON", "", "CoverageCSV", "", "ValidationCSV", "", ...
    "Source", "", "CoveragePct", NaN, "MissingPoints", NaN, "TotalPoints", NaN);
[exportCalibration, calibrationSkipReason] = localShouldExportCalibrationArtifacts(opt);
if exportCalibration
    try
        calibPayload = localBuildCampaignCalibrationPayload(cfg, opt, e2eAirLUT, link);
        trialCounts = localCollectCalibrationTrialCounts(runFolder);
        calibration = sixgr.hybrid.ExportCalibrationArtifacts(runFolder, calibPayload, ...
            "StrictMode", logical(sixgr.util.structGet(cfg, "run.strictMode", false)), ...
            "SourceRun", runFolder, ...
            "TrialCounts", trialCounts);
        calibration.Ok = true;
        calibration.Executed = true;
    catch ME
        calibration.Ok = false;
        calibration.Executed = true;
        calibration.Notes = string(ME.message);
        L.warn("Calibration artifact export failed: " + string(ME.message));
    end
else
    calibration = localMarkModuleSkipped(calibration, calibrationSkipReason);
end

% -------------------------------------------------------------------------
% 15) 25-category audit
% -------------------------------------------------------------------------
audit = localBuild25CategoryAudit(runFolder, opt, link, sys, mmtc, harq, syncCtrl, v2x, ntn, interf, rfp, numProbe, beam, e2e);
csvAudit = layout.CategoryAuditCSV;
sixgr.util.csvWriteTable(csvAudit, audit);

% Campaign report.
summary = struct();
summary.RunFolder = runFolder;
summary.LinkRunFolder = linkFolder;
summary.DetailRunFolder = detailDst;
summary.SystemRunFolder = sysDst;
summary.MMTCFolder = layout.MMTCDir;
summary.E2EFolder = layout.PacketFlowDir;
summary.LinkRunRequested = logical(runLinkCampaign);
summary.DetailedLLSRequested = logical(runDetailedDiagnostics);
summary.SystemRunRequested = logical(runSystemCampaign);
[summary.LinkRunStatus, summary.LinkRunNotes] = localSummarizeSubrun(runLinkCampaign, link, linkFolder, ...
    localJoinNotes("Skipped by OnlyE2E=true", "Skipped by RunLinkCampaign=false"));
[summary.DetailRunStatus, summary.DetailRunNotes] = localSummarizeSubrun(runDetailedDiagnostics, detailed, detailDst, ...
    localJoinNotes("Skipped by OnlyE2E=true", "Skipped by RunDetailedLinkDiagnostics=false"));
[summary.SystemRunStatus, summary.SystemRunNotes] = localSummarizeSubrun(runSystemCampaign, sys, sysDst, "Skipped by OnlyE2E=true");
[summary.MMTCRunStatus, summary.MMTCRunNotes] = localSummarizeSubrun(~onlyE2E && runMMTC, mmtc, layout.MMTCDir, ...
    "Skipped by " + localMMTCSkipReason(onlyE2E, runMMTC));
[summary.E2ERunStatus, summary.E2ERunNotes] = localSummarizeSubrun(logical(opt.RunE2EStackProbe), e2e, layout.PacketFlowDir, ...
    "Skipped by RunE2EStackProbe=false");
[summary.CalibrationStatus, summary.CalibrationNotes] = localSummarizeSubrun(exportCalibration, calibration, ...
    fullfile(runFolder, "calibration"), calibrationSkipReason);
summary.E2EExecutionMode = string(sixgr.util.structGet(e2e, "ExecutionMode", ""));
summary.E2EArtifactMode = string(sixgr.util.structGet(e2e, "ArtifactMode", ""));
summary.E2ESlotMetricsCSV = string(sixgr.util.structGet(e2e, "SlotMetricsArtifactCSV", ""));
summary.E2EComponentIOCSV = string(sixgr.util.structGet(e2e, "ComponentIOArtifactCSV", ""));
summary.E2EComponentChecksCSV = string(sixgr.util.structGet(e2e, "ComponentChecksArtifactCSV", ""));
summary.E2ESummaryCSV = string(sixgr.util.structGet(e2e, "SummaryArtifactCSV", ""));
summary.E2EQoSEvaluationCSV = string(sixgr.util.structGet(e2e, "QoSEvaluationArtifactCSV", ""));
summary.E2EAIMetricsCSV = string(sixgr.util.structGet(e2e, "AIArtifactCSV", ""));
summary.E2EPacketIntegrityCSV = string(sixgr.util.structGet(e2e, "PacketIntegrityArtifactCSV", ""));
summary.E2EPacketTraceCSV = string(sixgr.util.structGet(e2e, "PacketTraceArtifactCSV", ""));
summary.E2EFlowSummaryCSV = string(sixgr.util.structGet(e2e, "FlowSummaryArtifactCSV", ""));
summary.E2EBearerSummaryCSV = string(sixgr.util.structGet(e2e, "BearerSummaryArtifactCSV", ""));
summary.E2EAttachTraceCSV = string(sixgr.util.structGet(e2e, "AttachTraceArtifactCSV", ""));
summary.E2ESchedulerTraceCSV = string(sixgr.util.structGet(e2e, "SchedulerTraceArtifactCSV", ""));
summary.E2EHARQTraceCSV = string(sixgr.util.structGet(e2e, "HARQTraceArtifactCSV", ""));
summary.E2EDropCausesCSV = string(sixgr.util.structGet(e2e, "DropCauseArtifactCSV", ""));
summary.E2EMAT = string(sixgr.util.structGet(e2e, "ArtifactMAT", ""));
summary.ControlTraceFolder = string(sixgr.util.structGet(controlTrace, "Folder", ""));
summary.CalibrationFolder = "";
summary.CalibrationDBMat = "";
summary.CalibrationMetadataJSON = "";
summary.CalibrationCoverageCSV = "";
summary.CalibrationValidationCSV = "";
summary.CalibrationSource = "";
summary.CalibrationSourceKind = "";
summary.CalibrationUsedByThisRun = false;
summary.CalibrationGeneratedFromCampaignLinkSweep = false;
summary.CalibrationUsedByModules = strings(0,1);
strictnessMeta = localBuildStrictnessMetadata(cfg, opt);
summary.OnlyE2E = logical(strictnessMeta.OnlyE2E);
summary.CampaignStrictMode = logical(strictnessMeta.CampaignStrictMode);
summary.E2EStrictValidation = logical(strictnessMeta.E2EStrictValidation);
summary.LinkStrictValidation = logical(strictnessMeta.LinkStrictValidation);
summary.SystemStrictValidation = logical(strictnessMeta.SystemStrictValidation);
summary.DetailedLLSStrictValidation = logical(strictnessMeta.DetailedLLSStrictValidation);
summary.CalibrationStrictValidation = logical(strictnessMeta.CalibrationStrictValidation);
summary.LinkExecuted = logical(strictnessMeta.LinkExecuted);
summary.SystemExecuted = logical(strictnessMeta.SystemExecuted);
summary.DetailedLLSExecuted = logical(strictnessMeta.DetailedLLSExecuted);
summary.E2EExecuted = logical(strictnessMeta.E2EExecuted);
summary.CalibrationExecuted = logical(strictnessMeta.CalibrationExecuted);
summary.NoProxyTruthContract = logical(strictnessMeta.NoProxyTruthContract);
summary.CampaignProfileMode = string(profileMeta.Mode);
summary.CampaignProfileLabel = string(profileMeta.Label);
summary.CampaignProfileEntryPoint = string(profileMeta.EntryPoint);
summary.RunScope = localBuildRunScope(opt);
summary.ConformanceLevel = localDetermineConformanceLevel(cfg, opt, summary);
summary = localAppendE2EReportSummary(summary, e2e);
summary.ConformanceLevel = localDetermineConformanceLevel(cfg, opt, summary);
if exportCalibration && isfolder(char(string(sixgr.util.structGet(calibration, "CalibrationFolder", ""))))
    summary.CalibrationFolder = sixgr.util.structGet(calibration, "CalibrationFolder", "");
end
if exportCalibration
    summary.CalibrationDBMat = sixgr.util.structGet(calibration, "BLERDBMat", "");
    summary.CalibrationMetadataJSON = sixgr.util.structGet(calibration, "MetadataJSON", "");
    summary.CalibrationCoverageCSV = sixgr.util.structGet(calibration, "CoverageCSV", "");
    summary.CalibrationValidationCSV = sixgr.util.structGet(calibration, "ValidationCSV", "");
    summary.CalibrationSource = string(sixgr.util.structGet(calibration, "Source", ""));
    summary.CalibrationSourceKind = string(sixgr.util.structGet(calibration, "SourceKind", ""));
    summary.CalibrationUsedByThisRun = logical(sixgr.util.structGet(calibration, "UsedByThisRun", false));
    summary.CalibrationGeneratedFromCampaignLinkSweep = logical(sixgr.util.structGet(calibration, "GeneratedFromCampaignLinkSweep", false));
    summary.CalibrationUsedByModules = string(sixgr.util.structGet(calibration, "UsedByModules", strings(0,1)));
end
summary.AuditCSV = csvAudit;
summary.LogFile = logFile;
summary.MetaFolder = layout.MetaDir;
if onlyE2E
    summary.Ok = logical((~logical(opt.RunE2EStackProbe) || sixgr.util.structGet(e2e, "Ok", false)));
else
    summary.Ok = logical( ...
        (~runLinkCampaign || sixgr.util.structGet(link, "Ok", false)) && ...
        (~runDetailedDiagnostics || sixgr.util.structGet(detailed, "Ok", false)) && ...
        (~runSystemCampaign || sixgr.util.structGet(sys, "Ok", false)) && ...
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
summary = localFinalizeRunCompletion(summary);

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
summary.StructuredMirrorLayout = sixgr.util.structGet(structured, "MirrorLayout", "");
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
artifactCheck = struct( ...
    "Ok", false, ...
    "Table", table(), ...
    "CSV", "", ...
    "MD", "", ...
    "Coverage_pct", NaN, ...
    "MissingCount", NaN, ...
    "RequiredOutputsTable", table(), ...
    "RequiredOutputsCSV", "", ...
    "RequiredOutputCoverage_pct", NaN, ...
    "RequiredOutputMissingCount", NaN, ...
    "MissingRequiredOutputs", strings(0,1));
summary.ArtifactChecklistCSV = "";
summary.ArtifactChecklistMD = "";
summary.ArtifactCoverage_pct = NaN;
summary.ArtifactMissingCount = NaN;
summary.RequiredOutputsCSV = "";
summary.RequiredOutputCoverage_pct = NaN;
summary.RequiredOutputMissingCount = NaN;

metaRepro = localWriteReproducibilityMeta(runFolder, cfg, opt, summary, audit, calibration, artifactCheck);
summary.MetaRunManifestJSON = sixgr.util.structGet(metaRepro, "RunManifestJSON", "");
summary.MetaEnvironmentJSON = sixgr.util.structGet(metaRepro, "EnvironmentJSON", "");
summary.MetaSeedsCSV = sixgr.util.structGet(metaRepro, "SeedsCSV", "");
summary.MetaApproximationsCSV = sixgr.util.structGet(metaRepro, "ApproximationsCSV", "");
summary.MetaCalibrationSourceJSON = sixgr.util.structGet(metaRepro, "CalibrationSourceJSON", "");

matFile = layout.CampaignReportMAT;
mdFile = layout.CampaignReportMD;
localSaveCampaignMAT(matFile, summary, link, detailed, sys, mmtc, harq, syncCtrl, v2x, ntn, interf, rfp, numProbe, beam, e2e, calibration, audit, plotSummary, artifactCheck);
localWriteMarkdown(mdFile, summary, audit);

if logical(opt.VerifyArtifacts)
    try
        artifactCheck = localVerifyArtifacts(runFolder, logical(opt.GenerateCampaignPlots), opt, summary, ...
            logical(sixgr.util.structGet(cfg, "run.strictMode", false)));
    catch ME
        if logical(sixgr.util.structGet(cfg, "run.strictMode", false))
            rethrow(ME);
        end
        L.warn("Artifact verification failed: " + string(ME.message));
    end
    summary.ArtifactChecklistCSV = sixgr.util.structGet(artifactCheck, "CSV", "");
    summary.ArtifactChecklistMD = sixgr.util.structGet(artifactCheck, "MD", "");
    summary.ArtifactCoverage_pct = double(sixgr.util.structGet(artifactCheck, "Coverage_pct", NaN));
    summary.ArtifactMissingCount = double(sixgr.util.structGet(artifactCheck, "MissingCount", NaN));
    summary.RequiredOutputsCSV = sixgr.util.structGet(artifactCheck, "RequiredOutputsCSV", "");
    summary.RequiredOutputCoverage_pct = double(sixgr.util.structGet(artifactCheck, "RequiredOutputCoverage_pct", NaN));
    summary.RequiredOutputMissingCount = double(sixgr.util.structGet(artifactCheck, "RequiredOutputMissingCount", NaN));

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
            isnan(double(sixgr.util.structGet(summary, "ArtifactMissingCount", NaN))) || ...
            isnan(double(sixgr.util.structGet(summary, "RequiredOutputCoverage_pct", NaN))) || ...
            isnan(double(sixgr.util.structGet(summary, "RequiredOutputMissingCount", NaN)))
        summary.Ok = false;
    end
    summary = localFinalizeRunCompletion(summary);
    % Persist final status after artifact gating so report files are consistent.
    localWriteMarkdown(mdFile, summary, audit);
    localSaveCampaignMAT(matFile, summary, link, detailed, sys, mmtc, harq, syncCtrl, v2x, ntn, interf, rfp, numProbe, beam, e2e, calibration, audit, plotSummary, artifactCheck);
end

% Refresh structured organization after final metadata/report files are
% written so the run-local manifest and the repo-level lls/sls/e2e mirrors
% capture complete campaign artifacts.
if organizeByBlock
    try
        structured = sixgr.report.OrganizeRunResults(runFolder, ...
            "ResultsRoot", resultsRoot, ...
            "MirrorToResultsRoot", logical(opt.MirrorStructuredResults));
        summary.StructuredFolder = sixgr.util.structGet(structured, "StructuredFolder", "");
        summary.StructuredMirrorFolder = sixgr.util.structGet(structured, "MirrorFolder", "");
        summary.StructuredMirrorLayout = sixgr.util.structGet(structured, "MirrorLayout", "");
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
report.Artifacts.csv = localFilterPresentArtifacts({ ...
    fullfile(layout.MMTCCSVDir, "probe_mmtc_kpis.csv"), ...
    fullfile(layout.HARQCSVDir, "probe_harq_packets.csv"), ...
    fullfile(layout.HARQCSVDir, "probe_harq_summary.csv"), ...
    fullfile(layout.ControlCSVDir, "probe_sync_control.csv"), ...
    fullfile(layout.V2XCSVDir, "probe_v2x_sidelink.csv"), ...
    fullfile(layout.NTNCSVDir, "probe_ntn_delay_doppler.csv"), ...
    fullfile(layout.InterferenceCSVDir, "probe_interference_sir_bler.csv"), ...
    fullfile(layout.RFCSVDir, "probe_rf_energy.csv"), ...
    fullfile(layout.NumerologyCSVDir, "probe_numerology.csv"), ...
    fullfile(layout.BeamformingCSVDir, "probe_beam_mimo.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "probe_e2e_slot_metrics.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "probe_e2e_component_io.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "probe_e2e_component_checks.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "probe_e2e_packet_integrity.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "probe_e2e_summary.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "probe_e2e_qos_evaluation.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "probe_e2e_ai_metrics.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "e2e_packet_trace.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "e2e_flow_summary.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "e2e_bearer_summary.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "e2e_attach_trace.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "e2e_harq_trace.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "e2e_scheduler_trace.csv"), ...
    fullfile(layout.PacketFlowCSVDir, "e2e_drop_causes.csv"), ...
    fullfile(layout.ControlCSVDir, "cell_search_trials.csv"), ...
    fullfile(layout.ControlCSVDir, "pbch_recovery_trials.csv"), ...
    fullfile(layout.ControlCSVDir, "prach_trials.csv"), ...
    fullfile(layout.ControlCSVDir, "pdcch_trials.csv"), ...
    fullfile(layout.ControlCSVDir, "pucch_trials.csv"), ...
    fullfile(layout.ControlCSVDir, "attach_state_trace.csv"), ...
    fullfile(layout.ControlCSVDir, "rrc_message_trace.csv"), ...
    layout.SeedsCSV, ...
    layout.ApproximationsCSV, ...
    fullfile(layout.CalibrationDir, "calibration_coverage.csv"), ...
    fullfile(layout.CalibrationDir, "calibration_validation.csv"), ...
    layout.ArtifactChecklistCSV, ...
    layout.RequiredOutputsCSV, ...
    csvAudit});
report.Artifacts.mat = localFilterPresentArtifacts({matFile, fullfile(layout.CalibrationDir, "bler_db.mat")});
report.Artifacts.logs = localFilterPresentArtifacts({logFile, mdFile, fullfile(layout.CalibrationDir, "bler_db_metadata.json"), ...
    layout.RunManifestJSON, ...
    layout.EnvironmentJSON, ...
    layout.CalibrationSourceJSON});
report.Artifacts.structured = { ...
    sixgr.util.structGet(structured, "StructuredFolder", ""), ...
    sixgr.util.structGet(structured, "MirrorFolder", ""), ...
    sixgr.util.structGet(structured, "ManifestCSV", "")};
report.Artifacts.meta = localFilterPresentArtifacts({ ...
    layout.RunManifestJSON, ...
    layout.EnvironmentJSON, ...
    layout.SeedsCSV, ...
    layout.ApproximationsCSV, ...
    layout.CalibrationSourceJSON});

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
layout = sixgr.report.resultLayout(runFolder);
metaDir = layout.MetaDir;
sixgr.util.ensureDir(metaDir);

runManifestFile = layout.RunManifestJSON;
envFile = layout.EnvironmentJSON;
seedFile = layout.SeedsCSV;
approxFile = layout.ApproximationsCSV;
calSrcFile = layout.CalibrationSourceJSON;
includeCalibrationMeta = localIncludeCalibrationMeta(summary, calibration);
strictnessMeta = localBuildStrictnessMetadata(cfg, opt);

cfgHash = localComputeConfigHash(cfg);
repoRoot = fileparts(mfilename("fullpath"));
[codeVersion, codeVersionDetail] = localDetectCodeVersion(repoRoot);
strictMode = logical(strictnessMeta.CampaignStrictMode);

env = localBuildEnvironmentStruct(codeVersion, codeVersionDetail, repoRoot);
sixgr.util.jsonWrite(envFile, env);

seedTable = localBuildSeedTable(cfg, opt);
sixgr.util.csvWriteTable(seedFile, seedTable);

approxTable = localBuildApproximationsUsedTable(cfg, audit, runFolder, calibration);
sixgr.util.csvWriteTable(approxFile, approxTable);

if includeCalibrationMeta
    calSrc = struct();
    calSrc.Source = char(string(sixgr.util.structGet(calibration, "Source", "")));
    calSrc.SourceKind = char(string(sixgr.util.structGet(calibration, "SourceKind", "")));
    calSrc.StrictMode = strictMode;
    calSrc.StrictModeSemantics = "CampaignStrictMode";
    calSrc.CampaignStrictMode = logical(strictnessMeta.CampaignStrictMode);
    calSrc.OnlyE2E = logical(strictnessMeta.OnlyE2E);
    calSrc.NoProxyTruthContract = logical(strictnessMeta.NoProxyTruthContract);
    calSrc.E2EStrictValidation = logical(strictnessMeta.E2EStrictValidation);
    calSrc.LinkStrictValidation = logical(strictnessMeta.LinkStrictValidation);
    calSrc.SystemStrictValidation = logical(strictnessMeta.SystemStrictValidation);
    calSrc.DetailedLLSStrictValidation = logical(strictnessMeta.DetailedLLSStrictValidation);
    calSrc.CalibrationStrictValidation = logical(strictnessMeta.CalibrationStrictValidation);
    calSrc.LinkExecuted = logical(strictnessMeta.LinkExecuted);
    calSrc.SystemExecuted = logical(strictnessMeta.SystemExecuted);
    calSrc.DetailedLLSExecuted = logical(strictnessMeta.DetailedLLSExecuted);
    calSrc.E2EExecuted = logical(strictnessMeta.E2EExecuted);
    calSrc.CalibrationExecuted = logical(strictnessMeta.CalibrationExecuted);
    calSrc.GeneratedFromCampaignLinkSweep = logical(sixgr.util.structGet(calibration, "GeneratedFromCampaignLinkSweep", false));
    calSrc.UsedByThisRun = logical(sixgr.util.structGet(calibration, "UsedByThisRun", false));
    calSrc.UsedByModules = cellstr(string(sixgr.util.structGet(calibration, "UsedByModules", strings(0,1))));
    calSrc.Notes = char(string(sixgr.util.structGet(calibration, "Notes", "")));
    calSrc.BLERDBMat = char(string(sixgr.util.structGet(calibration, "BLERDBMat", "")));
    calSrc.MetadataJSON = char(string(sixgr.util.structGet(calibration, "MetadataJSON", "")));
    calSrc.CoverageCSV = char(string(sixgr.util.structGet(calibration, "CoverageCSV", "")));
    calSrc.ValidationCSV = char(string(sixgr.util.structGet(calibration, "ValidationCSV", "")));
    calSrc.CoveragePct = double(sixgr.util.structGet(calibration, "CoveragePct", NaN));
    calSrc.MissingPoints = double(sixgr.util.structGet(calibration, "MissingPoints", NaN));
    calSrc.TotalPoints = double(sixgr.util.structGet(calibration, "TotalPoints", NaN));
    calSrc.Status = char(string(sixgr.util.structGet(summary, "CalibrationStatus", "")));
    calSrc.Notes = char(string(sixgr.util.structGet(summary, "CalibrationNotes", "")));
    calSrc.GeneratedUTC = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
    sixgr.util.jsonWrite(calSrcFile, calSrc);
end

[~, runName] = fileparts(runFolder);
manifest = struct();
manifest.SchemaVersion = "sixgr_meta_v1";
manifest.RunName = string(runName);
manifest.RunFolder = string(runFolder);
manifest.GeneratedUTC = string(char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')));
manifest.StrictMode = strictMode;
manifest.StrictModeSemantics = "CampaignStrictMode";
manifest.CampaignProfileMode = string(sixgr.util.structGet(summary, "CampaignProfileMode", ""));
manifest.CampaignProfileLabel = string(sixgr.util.structGet(summary, "CampaignProfileLabel", ""));
manifest.CampaignProfileEntryPoint = string(sixgr.util.structGet(summary, "CampaignProfileEntryPoint", ""));
manifest.NoProxyTruthContract = logical(sixgr.util.structGet(summary, "NoProxyTruthContract", false));
manifest.RunScope = string(sixgr.util.structGet(summary, "RunScope", ""));
manifest.RunCompletion = string(sixgr.util.structGet(summary, "RunCompletion", ""));
manifest.ConformanceLevel = string(sixgr.util.structGet(summary, "ConformanceLevel", ""));
manifest.RunLinkCampaign = logical(sixgr.util.structGet(opt, "RunLinkCampaign", true));
manifest.RunDetailedLinkDiagnostics = logical(sixgr.util.structGet(opt, "RunDetailedLinkDiagnostics", true));
manifest.CampaignStrictMode = logical(strictnessMeta.CampaignStrictMode);
manifest.OnlyE2E = logical(strictnessMeta.OnlyE2E);
manifest.E2EStrictValidation = logical(strictnessMeta.E2EStrictValidation);
manifest.LinkStrictValidation = logical(strictnessMeta.LinkStrictValidation);
manifest.SystemStrictValidation = logical(strictnessMeta.SystemStrictValidation);
manifest.DetailedLLSStrictValidation = logical(strictnessMeta.DetailedLLSStrictValidation);
manifest.CalibrationStrictValidation = logical(strictnessMeta.CalibrationStrictValidation);
manifest.LinkExecuted = logical(strictnessMeta.LinkExecuted);
manifest.SystemExecuted = logical(strictnessMeta.SystemExecuted);
manifest.DetailedLLSExecuted = logical(strictnessMeta.DetailedLLSExecuted);
manifest.E2EExecuted = logical(strictnessMeta.E2EExecuted);
manifest.CalibrationExecuted = logical(strictnessMeta.CalibrationExecuted);
manifest.ConfigResolvedJSON = string(layout.ConfigResolvedJSON);
manifest.ConfigHash = string(cfgHash);
manifest.CodeVersion = string(codeVersion);
manifest.CodeVersionDetail = string(codeVersionDetail);
manifest.VerifyArtifactsEnabled = logical(sixgr.util.structGet(opt, "VerifyArtifacts", false));
if logical(strictnessMeta.E2EExecuted)
    manifest.E2EAirModel = string(sixgr.util.structGet(opt, "E2EAirModel", ""));
else
    manifest.E2EAirModel = "not_run";
end
manifest.E2EExecutionMode = string(sixgr.util.structGet(summary, "E2EExecutionMode", ""));
manifest.E2EArtifactMode = string(sixgr.util.structGet(summary, "E2EArtifactMode", ""));
manifest.E2ESystemCoupled = logical(sixgr.util.structGet(summary, "E2ESystemCoupled", false));
manifest.E2ECouplingMode = string(sixgr.util.structGet(summary, "E2ECouplingMode", ""));
manifest.E2ECouplingNotes = string(sixgr.util.structGet(summary, "E2ECouplingNotes", ""));
manifest.E2EAppSDUChunkBytes = double(sixgr.util.structGet(summary, "E2EAppSDUChunkBytes", NaN));
manifest.E2EAppSDUChunkSource = string(sixgr.util.structGet(summary, "E2EAppSDUChunkSource", ""));
manifest.E2ESlotMetricsCSV = string(sixgr.util.structGet(summary, "E2ESlotMetricsCSV", ""));
manifest.E2EComponentIOCSV = string(sixgr.util.structGet(summary, "E2EComponentIOCSV", ""));
manifest.E2EComponentChecksCSV = string(sixgr.util.structGet(summary, "E2EComponentChecksCSV", ""));
manifest.E2ESummaryCSV = string(sixgr.util.structGet(summary, "E2ESummaryCSV", ""));
manifest.E2EQoSEvaluationCSV = string(sixgr.util.structGet(summary, "E2EQoSEvaluationCSV", ""));
manifest.E2EAIMetricsCSV = string(sixgr.util.structGet(summary, "E2EAIMetricsCSV", ""));
manifest.E2EPacketIntegrityCSV = string(sixgr.util.structGet(summary, "E2EPacketIntegrityCSV", ""));
manifest.E2EPacketTraceCSV = string(sixgr.util.structGet(summary, "E2EPacketTraceCSV", ""));
manifest.E2EFlowSummaryCSV = string(sixgr.util.structGet(summary, "E2EFlowSummaryCSV", ""));
manifest.E2EBearerSummaryCSV = string(sixgr.util.structGet(summary, "E2EBearerSummaryCSV", ""));
manifest.E2EAttachTraceCSV = string(sixgr.util.structGet(summary, "E2EAttachTraceCSV", ""));
manifest.E2ESchedulerTraceCSV = string(sixgr.util.structGet(summary, "E2ESchedulerTraceCSV", ""));
manifest.E2EHARQTraceCSV = string(sixgr.util.structGet(summary, "E2EHARQTraceCSV", ""));
manifest.E2EDropCausesCSV = string(sixgr.util.structGet(summary, "E2EDropCausesCSV", ""));
manifest.E2EMAT = string(sixgr.util.structGet(summary, "E2EMAT", ""));
manifest.UseMexAcceleration = logical(sixgr.util.structGet(opt, "UseMexAcceleration", false));
manifest.SummaryOk = logical(sixgr.util.structGet(summary, "Ok", false));
manifest.E2EQoSPass = logical(sixgr.util.structGet(summary, "E2EQoSPass", true));
manifest.E2EPacketAccountingPassRate_pct = double(sixgr.util.structGet(summary, "E2EPacketAccountingPassRate_pct", NaN));
manifest.ArtifactCoverage_pct = double(sixgr.util.structGet(summary, "ArtifactCoverage_pct", NaN));
manifest.ArtifactMissingCount = double(sixgr.util.structGet(summary, "ArtifactMissingCount", NaN));
manifest.ArtifactChecklistCSV = string(sixgr.util.structGet(summary, "ArtifactChecklistCSV", ""));
manifest.RequiredOutputsCSV = string(sixgr.util.structGet(summary, "RequiredOutputsCSV", ""));
manifest.RequiredOutputCoverage_pct = double(sixgr.util.structGet(summary, "RequiredOutputCoverage_pct", NaN));
manifest.RequiredOutputMissingCount = double(sixgr.util.structGet(summary, "RequiredOutputMissingCount", NaN));
manifest.ApproximationsCount = height(approxTable);
manifest.SeedRows = height(seedTable);
manifest.MetaFiles = struct( ...
    "run_manifest", string(runManifestFile), ...
    "environment", string(envFile), ...
    "seeds", string(seedFile), ...
    "approximations_used", string(approxFile));
manifest.TopLevelFiles = struct( ...
    "report_md", string(layout.CampaignReportMD), ...
    "report_mat", string(layout.CampaignReportMAT), ...
    "category_audit_csv", string(layout.CategoryAuditCSV));
if includeCalibrationMeta
    manifest.CalibrationSource = string(sixgr.util.structGet(summary, "CalibrationSource", ""));
    manifest.CalibrationSourceKind = string(sixgr.util.structGet(summary, "CalibrationSourceKind", ""));
    manifest.CalibrationUsedByThisRun = logical(sixgr.util.structGet(summary, "CalibrationUsedByThisRun", false));
    manifest.CalibrationGeneratedFromCampaignLinkSweep = logical(sixgr.util.structGet(summary, "CalibrationGeneratedFromCampaignLinkSweep", false));
    manifest.CalibrationUsedByModules = string(sixgr.util.structGet(summary, "CalibrationUsedByModules", strings(0,1)));
    manifest.MetaFiles.calibration_source = string(calSrcFile);
    manifest.CalibrationFiles = struct( ...
        "bler_db_mat", string(sixgr.util.structGet(calibration, "BLERDBMat", "")), ...
        "metadata_json", string(sixgr.util.structGet(calibration, "MetadataJSON", "")), ...
        "coverage_csv", string(sixgr.util.structGet(calibration, "CoverageCSV", "")), ...
        "validation_csv", string(sixgr.util.structGet(calibration, "ValidationCSV", "")));
end
if isstruct(artifactCheck) && isfield(artifactCheck, "Ok")
    manifest.ArtifactCheck = struct( ...
        "Ok", logical(sixgr.util.structGet(artifactCheck, "Ok", false)), ...
        "Coverage_pct", double(sixgr.util.structGet(artifactCheck, "Coverage_pct", NaN)), ...
        "MissingCount", double(sixgr.util.structGet(artifactCheck, "MissingCount", NaN)), ...
        "RequiredOutputsCSV", string(sixgr.util.structGet(artifactCheck, "RequiredOutputsCSV", "")), ...
        "RequiredOutputCoverage_pct", double(sixgr.util.structGet(artifactCheck, "RequiredOutputCoverage_pct", NaN)), ...
        "RequiredOutputMissingCount", double(sixgr.util.structGet(artifactCheck, "RequiredOutputMissingCount", NaN)), ...
        "MissingRequiredOutputs", string(sixgr.util.structGet(artifactCheck, "MissingRequiredOutputs", strings(0,1))), ...
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
if includeCalibrationMeta
    out.CalibrationSourceJSON = calSrcFile;
else
    out.CalibrationSourceJSON = "";
end
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
onlyE2E = logical(sixgr.util.structGet(opt, "OnlyE2E", false));
runE2E = logical(sixgr.util.structGet(opt, "RunE2EStackProbe", true));
runAux = ~onlyE2E && logical(sixgr.util.structGet(opt, "RunAuxiliaryProbes", false));
runMMTC = ~onlyE2E && logical(sixgr.util.structGet(opt, "RunSystemMMTCProbe", false));
includeCalibrationSeed = localShouldExportCalibrationArtifacts(opt);
rows = repmat(struct("Component","","Seed",NaN,"SeedExpression","","Notes",""), 0, 1);

rows(end+1,1) = localSeedRow("global_campaign", baseSeed, "cfg.run.seed", "Master seed for campaign reproducibility.");
if ~onlyE2E
    rows(end+1,1) = localSeedRow("link_campaign", baseSeed, "cfg.run.seed", "Link-level modules consume deterministic streams from base seed.");
    rows(end+1,1) = localSeedRow("detailed_lls", baseSeed, "cfg.run.seed", "Detailed PHY diagnostics seeded from base.");
    rows(end+1,1) = localSeedRow("system_campaign", baseSeed, "cfg.run.seed", "System-level runner base seed.");
    rows(end+1,1) = localSeedRow("system_phy_decode", baseSeed + 31, "cfg.run.seed + 31", "PHY decoder RNG in system-level path.");
end
if runE2E
    rows(end+1,1) = localSeedRow("e2e_probe", baseSeed, "cfg.run.seed", "E2E stack scheduling/queue randomness.");
end
if runAux || runE2E
    rows(end+1,1) = localSeedRow("sync_control_probes", baseSeed, "cfg.run.seed", "PBCH/PRACH/PDCCH/PUCCH trial traces.");
end
if runMMTC
    rows(end+1,1) = localSeedRow("mmtc", baseSeed, "cfg.run.seed", "mMTC probe seeded from base.");
end
if includeCalibrationSeed
    rows(end+1,1) = localSeedRow("calibration_export", baseSeed, "cfg.run.seed", "Calibration artifact generation context.");
end
rows(end+1,1) = localSeedRow("mode_flags", NaN, "N/A", "strictMode=" + string(strictMode) + ", useMex=" + string(useMex));
rows(end).Notes = rows(end).Notes + ", noProxyTruthContract=" + string(localNoProxyTruthContractEnabled(cfg, opt));

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

function meta = localBuildStrictnessMetadata(cfg, opt)
if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2 || ~isstruct(opt)
    opt = struct();
end

campaignStrict = logical(sixgr.util.structGet(cfg, "run.strictMode", false));
onlyE2E = logical(sixgr.util.structGet(opt, "OnlyE2E", false));
runE2E = logical(sixgr.util.structGet(opt, "RunE2EStackProbe", true));
[runCalibration, ~] = localShouldExportCalibrationArtifacts(opt);
linkExecuted = ~onlyE2E && logical(sixgr.util.structGet(opt, "RunLinkCampaign", true));
systemExecuted = ~onlyE2E;
detailedExecuted = ~onlyE2E && logical(sixgr.util.structGet(opt, "RunDetailedLinkDiagnostics", true));
noProxyTruthContract = localNoProxyTruthContractEnabled(cfg, opt);

meta = struct();
meta.CampaignStrictMode = campaignStrict;
meta.OnlyE2E = onlyE2E;
meta.NoProxyTruthContract = noProxyTruthContract;
meta.E2EStrictValidation = runE2E && logical(sixgr.util.structGet(opt, "E2EStrictValidation", false));
meta.LinkStrictValidation = linkExecuted && campaignStrict;
meta.SystemStrictValidation = systemExecuted && campaignStrict;
meta.DetailedLLSStrictValidation = detailedExecuted && campaignStrict;
meta.CalibrationStrictValidation = runCalibration && campaignStrict;
meta.LinkExecuted = linkExecuted;
meta.SystemExecuted = systemExecuted;
meta.DetailedLLSExecuted = detailedExecuted;
meta.E2EExecuted = runE2E;
meta.CalibrationExecuted = runCalibration;
end

function usedBy = localCalibrationUsedByModules(opt)
if nargin < 1 || ~isstruct(opt)
    opt = struct();
end
onlyE2E = logical(sixgr.util.structGet(opt, "OnlyE2E", false));
runE2E = logical(sixgr.util.structGet(opt, "RunE2EStackProbe", true));
airModel = lower(strtrim(char(string(sixgr.util.structGet(opt, "E2EAirModel", "truth")))));
usedBy = strings(0,1);

if ~onlyE2E && logical(sixgr.util.structGet(opt, "CalibrateSystemBLERFromLink", false))
    usedBy(end+1,1) = "system"; %#ok<AGROW>
end
if runE2E && strcmp(airModel, "lut")
    usedBy(end+1,1) = "e2e_lut"; %#ok<AGROW>
end
usedBy = unique(usedBy, "stable");
end

function T = localAppendE2ESummaryStrictness(T, cfg, opt)
if ~istable(T) || isempty(T)
    return;
end
meta = localBuildStrictnessMetadata(cfg, opt);
n = height(T);
T.OnlyE2E = repmat(logical(meta.OnlyE2E), n, 1);
T.NoProxyTruthContract = repmat(logical(meta.NoProxyTruthContract), n, 1);
T.CampaignStrictMode = repmat(logical(meta.CampaignStrictMode), n, 1);
T.E2EStrictValidation = repmat(logical(meta.E2EStrictValidation), n, 1);
T.LinkStrictValidation = repmat(logical(meta.LinkStrictValidation), n, 1);
T.SystemStrictValidation = repmat(logical(meta.SystemStrictValidation), n, 1);
T.DetailedLLSStrictValidation = repmat(logical(meta.DetailedLLSStrictValidation), n, 1);
T.CalibrationStrictValidation = repmat(logical(meta.CalibrationStrictValidation), n, 1);
T.LinkExecuted = repmat(logical(meta.LinkExecuted), n, 1);
T.SystemExecuted = repmat(logical(meta.SystemExecuted), n, 1);
T.DetailedLLSExecuted = repmat(logical(meta.DetailedLLSExecuted), n, 1);
T.E2EExecuted = repmat(logical(meta.E2EExecuted), n, 1);
T.CalibrationExecuted = repmat(logical(meta.CalibrationExecuted), n, 1);
T.RunScope = repmat(localBuildRunScope(opt), n, 1);
T.ConformanceLevel = repmat(localDetermineConformanceLevel(cfg, opt, struct()), n, 1);
end

function localGuardTruthE2ESystemCoupling(cfg, opt, onlyE2E, runSystemCampaign)
% Truth E2E now consumes an internal waveform SystemLevelRunner grant trace,
% so combined system + truth E2E requests no longer need to fail closed
% here. Keep the hook for future coupling sanity checks.
return;
end

function tf = localNoProxyTruthContractEnabled(cfg, opt)
if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2 || ~isstruct(opt)
    opt = struct();
end
explicit = logical(sixgr.util.structGet(opt, "NoProxyTruthContract", ...
    sixgr.util.structGet(cfg, "run.noProxyTruthContract", false)));
profileMode = lower(strtrim(char(string(sixgr.util.structGet(opt, "CampaignProfileMode", "")))));
tf = explicit || strcmp(profileMode, "truth_validation");
end

function localEnforceNoProxyTruthContract(cfg, opt, onlyE2E, runLinkCampaign, runSystemCampaign)
if ~localNoProxyTruthContractEnabled(cfg, opt)
    return;
end

runE2E = logical(sixgr.util.structGet(opt, "RunE2EStackProbe", true));
e2eAirModel = lower(strtrim(char(string(sixgr.util.structGet(opt, "E2EAirModel", "truth")))));
trafficModel = lower(strtrim(char(string(sixgr.util.structGet(opt, "E2ETrafficModel", ...
    sixgr.util.structGet(cfg, "traffic.model", "fullBuffer"))))));
e2eUsesSystemCoupling = runE2E && strcmp(e2eAirModel, "truth");
ctx = struct();
ctx.Enabled = true;
ctx.E2EAirModel = e2eAirModel;
ctx.TrafficModel = trafficModel;
ctx.UseFastLinkModel = logical(sixgr.util.structGet(opt, "UseFastLinkModel", false)) && logical(runLinkCampaign);
ctx.SystemPHYBackend = string(sixgr.util.structGet(cfg, "system.phyBackend", "waveform"));
ctx.RunE2E = runE2E;
ctx.RunSystem = logical(runSystemCampaign) || logical(e2eUsesSystemCoupling);
ctx.RunLink = logical(runLinkCampaign);
ctx.OnlyE2E = logical(onlyE2E);
ctx.CampaignProfileMode = string(sixgr.util.structGet(opt, "CampaignProfileMode", ""));
if e2eUsesSystemCoupling
    ctx.CouplingMode = "system_waveform_grant_trace";
    ctx.E2ESystemCoupled = true;
    if ~logical(runSystemCampaign)
        ctx.SystemPHYBackend = "waveform";
    end
end
sixgr.truth.enforceNoProxyContract(cfg, ctx);
end

function T = localBuildApproximationsUsedTable(cfg, audit, runFolder, calibration)
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

channelModel = lower(strtrim(string(sixgr.util.structGet(cfg, "channel.model", ""))));
pathlossModel = lower(strtrim(string(sixgr.util.structGet(cfg, "channel.pathlossModel", ...
    sixgr.util.structGet(cfg, "channel.pathloss.model", "")))));
usesTR38901LargeScale = any(channelModel == ["tr38901","tr38.901","tr38_901","abg","large","abstract"]);
if (usesTR38901LargeScale || any(pathlossModel == ["nrpathloss","nr","abg","tr38901abg","fr3abg"])) && ...
        any(pathlossModel == ["nrpathloss","nr"]) && ...
        (exist("nrPathLossConfig","class") ~= 8 || exist("nrPathLoss","file") ~= 2)
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Area", "Channel/RF", ...
        "Component", "large_scale_pathloss", ...
        "ApproximationMode", "free_space_path_loss_fallback", ...
        "Evidence", "sixgr.channel.TR38901Plus.pathlossViaNrPathLoss", ...
        "Notes", "nrPathLoss runtime backend unavailable; TR38901Plus falls back to FSPL and must stay labeled approximate.");
elseif usesTR38901LargeScale && any(pathlossModel == ["abg","tr38901abg","fr3abg"])
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Area", "Channel/RF", ...
        "Component", "large_scale_pathloss", ...
        "ApproximationMode", "abg_large_scale_model", ...
        "Evidence", "sixgr.channel.TR38901Plus", ...
        "Notes", "Configured ABG pathloss is a large-scale abstraction and not the standards-backed nrPathLoss runtime backend.");
end

if logical(sixgr.util.structGet(cfg, "channel.spatialNonStationary.enable", false))
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Area", "Channel/RF", ...
        "Component", "spatial_non_stationarity", ...
        "ApproximationMode", "random_placeholder_visibility_masks", ...
        "Evidence", "sixgr.channel.SpatialNonStationarity", ...
        "Notes", "Visibility masks are random placeholders without geometry, angle, or array-manifold coupling.");
end

if logical(sixgr.util.structGet(cfg, "rf.phaseNoise.enable", false))
    phaseNoiseBackend = "wiener_linewidth_proxy_fallback";
    phaseNoiseNotes = "PhaseNoiseModel helper resolves to the Wiener/linewidth proxy if used directly.";
    if exist("comm.PhaseNoise","class") == 8
        phaseNoiseBackend = "comm_phase_noise_runtime_backend";
        phaseNoiseNotes = "PhaseNoiseModel helper can resolve to comm.PhaseNoise, but the active no-proxy waveform replay path does not materialize phase-noise impairment.";
    end
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "Area", "Channel/RF", ...
        "Component", "phase_noise", ...
        "ApproximationMode", "not_materialized_in_active_waveform_truth_path", ...
        "Evidence", "sixgr.link.applyWaveformImpairments", ...
        "Notes", "Configured phase noise is not applied in the active waveform truth path. Helper backend=" + phaseNoiseBackend + ". " + phaseNoiseNotes);
end

layout = sixgr.report.resultLayout(runFolder);
e2eFile = fullfile(layout.PacketFlowCSVDir, "probe_e2e_summary.csv");
if exist(e2eFile, "file") == 2
    try
        E = readtable(e2eFile, "VariableNamingRule", "preserve");
        if ~isempty(E)
            backend = "";
            phyMode = "";
            airMode = "";
            airSrc = "";
            systemCoupled = false;
            couplingMode = "";
            if ismember("ExecutionBackend", string(E.Properties.VariableNames)), backend = string(E.ExecutionBackend(1)); end
            if ismember("PHYMode", string(E.Properties.VariableNames)), phyMode = string(E.PHYMode(1)); end
            if ismember("E2EAirModel", string(E.Properties.VariableNames)), airMode = string(E.E2EAirModel(1)); end
            if ismember("E2EAirModelSource", string(E.Properties.VariableNames)), airSrc = string(E.E2EAirModelSource(1)); end
            if ismember("E2ESystemCoupled", string(E.Properties.VariableNames)), systemCoupled = logical(E.E2ESystemCoupled(1)); end
            if ismember("E2ECouplingMode", string(E.Properties.VariableNames)), couplingMode = string(E.E2ECouplingMode(1)); end
            if contains(upper(backend), "FAST_PROXY") || contains(upper(phyMode), "PROXY") || lower(airMode) ~= "truth"
                rows(end+1,1) = struct( ... %#ok<AGROW>
                    "Area", "E2E", ...
                    "Component", "end_to_end_radio_delivery", ...
                    "ApproximationMode", "proxy_model", ...
                    "Evidence", "packet_flow/csv/probe_e2e_summary.csv", ...
                    "Notes", "ExecutionBackend=" + backend + "; PHYMode=" + phyMode + "; AirModel=" + airMode + "; Source=" + airSrc);
            end
            if lower(airMode) == "truth" && ~systemCoupled
                rows(end+1,1) = struct( ... %#ok<AGROW>
                    "Area", "E2E", ...
                    "Component", "truth_e2e_coupling", ...
                    "ApproximationMode", "uncoupled_truth_replay", ...
                    "Evidence", "packet_flow/csv/probe_e2e_summary.csv", ...
                    "Notes", "E2ESystemCoupled=false; E2ECouplingMode=" + couplingMode + "; Source=" + airSrc);
            end
        end
    catch
    end
end

sysFile = fullfile(layout.SystemCSVDir, "system_kpis.csv");
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
strictNoProxy = logical(sixgr.util.structGet(cfgL, "run.strictMode", false)) || ...
    logical(sixgr.util.structGet(cfgL, "run.noProxyTruthContract", false));

if logical(sixgr.util.structGet(cfgL, "run.noProxyTruthContract", false)) && logical(opt.UseFastLinkModel)
    error("sixgr:link:NoProxyFastLinkForbidden", ...
        "UseFastLinkModel=true is forbidden for link execution under the no-proxy truth contract.");
end

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
kpi = sixgr.util.structGet(res, "KPITable", table());
snrGrid = localReduceSweepGrid(double(opt.LinkSNRGrid_dB(:)), round(double(opt.LinkSweepMaxPoints)), double(opt.LinkSNR_dB));
fallback = struct("Active", false, "Result", struct(), "KPITable", table(), ...
    "SNRSweep", table(), "Artifacts", struct("csv",{{}}, "mat",{{}}, "fig",{{}}), ...
    "ConfigUsed", struct(), "Notes", "");

if ~localLinkKPITableHealthy(kpi)
    if strictNoProxy
        sixgr.link.failIfStrictCoverageGap(cfgL, "sixgr:link:StrictCoverageGap", ...
            "Primary waveform link campaign failed coverage, and fallback rescue reruns are forbidden under strict/no-proxy execution.");
    end
    % Keep rescued reruns quarantined in explicitly named sidecar exports.
    cfgLF = localBuildDLTraceFallbackCfg(cfgL);
    try
        cfgLF.outputs.saveCSV = false;
        cfgLF.outputs.saveMAT = false;
        cfgLF.outputs.saveFigures = false;
        cfgLF.outputs.saveFIG = false;
        ctxF = sixgr.core.SimContext(cfgLF, "RunFolder", runFolder);
        ctxF.Logger.EchoToConsole = false;
        resF = sixgr.link.LinkLevelRunner.run(ctxF, params);
        kpiF = sixgr.util.structGet(resF, "KPITable", table());
        if localLinkKPITableHealthy(kpiF)
            resF = localTagLinkFallbackCases(resF, "link_campaign_fallback_awgn");
            kpiF = localAnnotateFallbackLinkKPI(kpiF, cfgL, cfgLF, "link_campaign_fallback_awgn");
            fallback.Active = true;
            fallback.Result = resF;
            fallback.KPITable = kpiF;
            fallback.ConfigUsed = cfgLF;
            fallback.Artifacts = sixgr.link.exportLinkKPIs(runFolder, kpiF, resF, ...
                "SaveCSV", true, "SaveMAT", false, "SaveFigures", false, ...
                "FileSuffix", "_fallback");
            fallback.SNRSweep = localRunLinkSNRSweep(cfgLF, snrGrid, round(double(opt.LinkSweepFrames)));
            fSweepFallback = fullfile(runFolder, "csv", "lls_snr_sweep_fallback.csv");
            sixgr.util.csvWriteTable(fSweepFallback, fallback.SNRSweep);
            fallback.Artifacts.csv{end+1} = fSweepFallback;
            fallback.Notes = "Fallback link reruns exported to *_fallback.csv sidecars.";
        end
    catch
    end
end

sweep = localRunLinkSNRSweep(cfgL, snrGrid, round(double(opt.LinkSweepFrames)));
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_snr_sweep.csv"), sweep);
rawTrials = localExportLinkRawTrialTables(cfgL, runFolder, res, numFrames, double(opt.LinkSNR_dB));
[kpi, integrity] = sixgr.link.enforcePrimaryLinkExportIntegrity(cfgL, kpi, rawTrials);
res.KPITable = kpi;
if istable(kpi) && width(kpi) > 0
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "link_kpis.csv"), kpi);
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_kpi_summary.csv"), kpi);
elseif exist(fullfile(runFolder, "csv", "link_kpis.csv"), "file")
    copyfile(fullfile(runFolder, "csv", "link_kpis.csv"), fullfile(runFolder, "csv", "lls_kpi_summary.csv"));
end

out = struct();
out.Ok = logical(sixgr.util.structGet(res, "Ok", false));
out.RunFolder = runFolder;
out.Result = res;
out.KPITable = kpi;
out.SNRSweep = sweep;
out.RawTrials = rawTrials;
out.Errors = sixgr.util.structGet(res, "Errors", strings(0,1));
out.Artifacts = sixgr.util.structGet(res, "Artifacts", struct("csv",{{}}, "mat",{{}}, "fig",{{}}, "m",{{}}));
if fallback.Active
    out.Artifacts.csv = [out.Artifacts.csv, fallback.Artifacts.csv]; %#ok<AGROW>
end
out.ConfigUsed = cfgL;
out.Fallback = fallback;
out.Integrity = integrity;
end

function out = localRunLinkCampaignFast(cfgL, runFolder, opt)
sixgr.util.ensureDir(runFolder);
sixgr.util.ensureDir(fullfile(runFolder, "csv"));
sixgr.util.ensureDir(fullfile(runFolder, "mat"));
sixgr.util.ensureDir(fullfile(runFolder, "image"));
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
rawTrials = localExportLinkRawTrialTables(cfgL, runFolder, res, numFrames, snrMain);
[kpi, integrity] = sixgr.link.enforcePrimaryLinkExportIntegrity(cfgL, kpi, rawTrials);
res.KPITable = kpi;
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "link_kpis.csv"), kpi);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_kpi_summary.csv"), kpi);

out = struct();
out.Ok = true;
out.RunFolder = runFolder;
out.Result = res;
out.KPITable = kpi;
out.SNRSweep = sweep;
out.RawTrials = rawTrials;
out.Errors = strings(0,1);
out.Artifacts = struct("csv", {{fullfile(runFolder, "csv", "link_kpis.csv"), fullfile(runFolder, "csv", "lls_snr_sweep.csv")}}, ...
    "mat", {{fullfile(runFolder, "mat", "link_results.mat")}}, "fig", {{}}, "m", {{}});
out.Integrity = integrity;
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
tf = all(ok & ~sk);
end

function res = localTagLinkFallbackCases(res, notePrefix)
if ~(isstruct(res) && isscalar(res) && isfield(res, "Cases"))
    return;
end

fn = string(fieldnames(res.Cases));
for iFn = 1:numel(fn)
    c = res.Cases.(char(fn(iFn)));
    note = string(sixgr.util.structGet(c, "Notes", ""));
    c.Notes = string(notePrefix) + "|" + note;
    res.Cases.(char(fn(iFn))) = c;
end
end

function kpi = localAnnotateFallbackLinkKPI(kpi, cfgRequested, cfgUsed, reason)
if ~(istable(kpi) && ~isempty(kpi))
    return;
end

n = height(kpi);
if ~ismember("RequestedChannelModel", string(kpi.Properties.VariableNames))
    kpi.RequestedChannelModel = strings(n,1);
end
if ~ismember("ObservedChannelModel", string(kpi.Properties.VariableNames))
    kpi.ObservedChannelModel = strings(n,1);
end
if ~ismember("FallbackUsed", string(kpi.Properties.VariableNames))
    kpi.FallbackUsed = false(n,1);
end
if ~ismember("FallbackReason", string(kpi.Properties.VariableNames))
    kpi.FallbackReason = strings(n,1);
end

kpi.RequestedChannelModel(:) = localResolveRequestedLinkChannelModel(cfgRequested);
kpi.ObservedChannelModel(:) = localResolveRequestedLinkChannelModel(cfgUsed);
kpi.FallbackUsed(:) = true;
kpi.FallbackReason(:) = string(reason);

if ismember("Notes", string(kpi.Properties.VariableNames))
    kpi.Notes = "fallback_" + string(reason) + "|" + string(kpi.Notes);
end
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
dlTrials = localEnsureLinkTrialTable(dlTrials, "DL", snr_dB, cfg);
fDL = fullfile(csvDir, "dl_pdsch_trials.csv");
sixgr.util.csvWriteTable(fDL, dlTrials);
fDLFallback = "";
if localAllTrialsCrash(dlTrials)
    cfgDL = localBuildDLTraceFallbackCfg(cfg);
    try
        dlRun = sixgr.link.runDLPDSCHThroughput(cfgDL, "NumFrames", nTrials, "SNR_dB", snr_dB);
        dlFallback = sixgr.util.structGet(dlRun, "TrialTable", table());
        if istable(dlFallback) && ~isempty(dlFallback)
            if ismember("Notes", dlFallback.Properties.VariableNames)
                dlFallback.Notes = "fallback_awgn_profile|" + string(dlFallback.Notes);
            end
            dlFallback = localEnsureLinkTrialTable(dlFallback, "DL", snr_dB, cfgDL);
            fDLFallback = fullfile(csvDir, "dl_pdsch_trials_fallback.csv");
            sixgr.util.csvWriteTable(fDLFallback, dlFallback);
        end
    catch
    end
end

ulTrials = localGetCaseTrialTable(linkRes, "UL_PUSCH_Throughput");
if isempty(ulTrials)
    try
        ulRun = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", nTrials, "SNR_dB", snr_dB);
        ulTrials = sixgr.util.structGet(ulRun, "TrialTable", table());
    catch
        ulTrials = table();
    end
end
ulTrials = localEnsureLinkTrialTable(ulTrials, "UL", snr_dB, cfg);
fUL = fullfile(csvDir, "ul_pusch_trials.csv");
sixgr.util.csvWriteTable(fUL, ulTrials);
fULFallback = "";
if localAllTrialsCrash(ulTrials)
    cfgUL = localBuildULTraceFallbackCfg(cfg);
    try
        ulRun = sixgr.link.runULPUSCHThroughput(cfgUL, "NumFrames", nTrials, "SNR_dB", snr_dB);
        ulFallback = sixgr.util.structGet(ulRun, "TrialTable", table());
        if istable(ulFallback) && ~isempty(ulFallback)
            if ismember("Notes", ulFallback.Properties.VariableNames)
                ulFallback.Notes = "fallback_valid_tdl_profile|" + string(ulFallback.Notes);
            end
            ulFallback = localEnsureLinkTrialTable(ulFallback, "UL", snr_dB, cfgUL);
            fULFallback = fullfile(csvDir, "ul_pusch_trials_fallback.csv");
            sixgr.util.csvWriteTable(fULFallback, ulFallback);
        end
    catch
    end
end

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
out.DLFallback = fDLFallback;
out.ULFallback = fULFallback;
out.PBCH = fPBCH;
out.PRACH = fPRACH;
out.PDCCH = fPDCCH;
out.PUCCH = fPUCCH;
out.SRS = fSRS;
end

function out = localExportControlPlaneTraces(runFolder, link, e2e, syncCtrl)
layout = sixgr.report.resultLayout(runFolder);
controlDir = layout.ControlCSVDir;
sixgr.util.ensureDir(controlDir);

linkCsvDir = layout.AirInterfaceCSVDir;
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
        attachTrace = readtable(fullfile(layout.PacketFlowCSVDir, "e2e_attach_trace.csv"), "VariableNamingRule", "preserve");
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
reqModel = localResolveRequestedLinkChannelModel(cfg);
if all(strlength(string(T.ChannelModel)) == 0)
    T.ChannelModel(:) = reqModel;
end
uCm = upper(strtrim(string(T.ChannelModel)));
maskAWGN = (uCm == "NONE" | uCm == "OFF");
if any(maskAWGN)
    T.ChannelModel(maskAWGN) = "AWGN";
end
maskTDL = (uCm == "TDL") & startsWith(reqModel, "TDL");
if any(maskTDL)
    T.ChannelModel(maskTDL) = reqModel;
    if ismember("Notes", T.Properties.VariableNames)
        T.Notes(maskTDL) = string(T.Notes(maskTDL)) + "|normalized_channel_model=" + reqModel;
    end
end
maskCDL = (uCm == "CDL") & startsWith(reqModel, "CDL");
if any(maskCDL)
    T.ChannelModel(maskCDL) = reqModel;
    if ismember("Notes", T.Properties.VariableNames)
        T.Notes(maskCDL) = string(T.Notes(maskCDL)) + "|normalized_channel_model=" + reqModel;
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
        skipped = logical(sixgr.util.structGet(out, "Skipped", false));
        ok = ok && ~skipped;
        r.CRCPass = double(ok);
        if ok
            r.DetectionMetric = 1;
            r.Status = "PASS";
        else
            r.DetectionMetric = NaN;
            r.Status = "FAIL";
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
        completed = logical(sixgr.util.structGet(out, "Ok", false)) && ...
            ~logical(sixgr.util.structGet(out, "Skipped", false));
        detected = logical(sixgr.util.structGet(out, "Detected", false));
        r.CRCPass = double(detected);
        r.DetectionMetric = double(sixgr.util.structGet(out, "DetectionMetric", double(detected)));
        if completed && detected
            r.Status = "PASS";
        elseif logical(sixgr.util.structGet(out, "Skipped", false))
            r.CRCPass = NaN;
            r.DetectionMetric = NaN;
            r.Status = "NA";
        else
            r.Status = "FAIL";
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
row.ChannelModel = localResolveRequestedLinkChannelModel(cfg);
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
    sixgr.util.ensureDir(fullfile(runFolder, "image"));
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
strictSLS = strictSLS || localNoProxyTruthContractEnabled(cfg, opt);
strictSLS = strictSLS || strcmpi(string(sixgr.util.structGet(opt, "E2EAirModel", "truth")), "truth");
numSites = max(1, round(double(sixgr.util.structGet(cfg, "scenario.layout.nSites", 1))));
numSectors = max(1, round(double(sixgr.util.structGet(cfg, "scenario.layout.nSectorsPerSite", 1))));
multiCellRequested = (numSites * numSectors) > 1;
handoverRequested = logical(sixgr.util.structGet(cfg, "system.handover.enable", false));
detailedTraceRequested = logical(sixgr.util.structGet(opt, "SystemDetailedTrace", false));
requireFullSystem = multiCellRequested || handoverRequested || detailedTraceRequested;
if logical(opt.UseMexAcceleration) && ~strictSLS && ~requireFullSystem && ...
        (exist("sixgr_system_fast_core_kernel_mex","file") == 3 || exist("sixgr_system_fast_core_kernel","file") == 2)
    error("sixgr:campaign:ProxyModeRemoved", ...
        "The system fast proxy kernel was removed from the active waveform-truth-only repository. Run the waveform SystemLevelRunner path instead.");
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
if strcmpi(string(sixgr.util.structGet(opt, "E2EAirModel", "truth")), "truth")
    cfgS.system.phyBackend = "waveform";
end

ctx = sixgr.core.SimContext(cfgS, "RunFolder", runFolder);
ctx.Logger.EchoToConsole = false;

params = struct();
slotDur_s = localSlotDuration(cfgS);
params.SimDuration_s = double(opt.SystemDuration_s);
params.TTI_s = slotDur_s;
params.NumTTI = max(1, ceil(double(opt.SystemDuration_s) / max(slotDur_s, eps)));
params.ForceLong = true;
params.DetailedTrace = logical(opt.SystemDetailedTrace);
res = sixgr.system.SystemLevelRunner.run(ctx, params);

out = struct();
out.Ok = logical(sixgr.util.structGet(res, "Ok", false));
out.RunFolder = runFolder;
out.Result = res;
out.KPITable = sixgr.util.structGet(res, "KPITable", table());
out.Errors = sixgr.util.structGet(res, "Errors", strings(0,1));
end

function out = localRunSystemMobilityCampaignFast(cfg, runFolder, opt)
%#ok<INUSD>
error("sixgr:campaign:ProxyModeRemoved", ...
    "The system fast proxy kernel is inaccessible in the active waveform-truth-only repository.");

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
sixgr.util.ensureDir(fullfile(runFolder, "image"));
sixgr.util.ensureDir(fullfile(runFolder, "logs"));

nUE = max(1, round(double(opt.SystemNumUE)));
tti_s = 1.0;
nTTI = max(20, ceil(double(opt.SystemDuration_s) / max(tti_s, eps)));
simDur_s = nTTI * tti_s;
bw_Hz = double(sixgr.util.structGet(cfgS, "channel.bandwidth_Hz", 20e6));
qMaxBits = double(sixgr.util.structGet(cfgS, "system.queueMaxBits", 5e7));

try
    traffic = sixgr.system.TrafficFactory.generate(cfgS, nUE, nTTI, tti_s);
catch ME
    if localNoProxyTruthContractEnabled(cfgS, opt)
        rethrow(ME);
    end
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
out.Notes = "System run used FAST_PROXY_KERNEL; aggregate-only slot traces are exported and per-grant tables stay empty when no real grants exist.";
end

function traces = localBuildFastSystemTraceArtifacts( ...
    nTTI, nUE, tti_s, slot, offeredDL, offeredUL, servedDL, servedUL, ...
    droppedDL, droppedUL, schedDL, schedUL, sinrDL, sinrUL, meanQ, bw_Hz)
traces = sixgr.system.buildFastProxyTraceArtifacts( ...
    nTTI, nUE, tti_s, slot, offeredDL, offeredUL, servedDL, servedUL, ...
    droppedDL, droppedUL, schedDL, schedUL, sinrDL, sinrUL, meanQ, bw_Hz);
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
            okCnt = okCnt + double(logical(sixgr.util.structGet(r, "Detected", false)));
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
noProxyTruthContract = localNoProxyTruthContractEnabled(cfg, opt);
strictValidation = logical(opt.E2EStrictValidation) || noProxyTruthContract;
airModeReq = lower(char(string(sixgr.util.structGet(opt, "E2EAirModel", "truth"))));
if logical(opt.UseMexAcceleration) && ~strictValidation && ~strcmp(airModeReq, "truth") && ...
        (exist("sixgr_e2e_fast_core_kernel_mex","file") == 3 || exist("sixgr_e2e_fast_core_kernel","file") == 2)
    error("sixgr:campaign:ProxyModeRemoved", ...
        "The E2E fast proxy kernel was removed from the active waveform-truth-only repository. Use E2EAirModel='truth'.");
end

sixgr.util.ensureDir(runFolder);
sixgr.util.ensureDir(fullfile(runFolder, "csv"));
sixgr.util.ensureDir(fullfile(runFolder, "mat"));
sixgr.util.ensureDir(fullfile(runFolder, "image"));
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
    if strictValidation || noProxyTruthContract
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
chunkInfo = localResolveE2EAppChunk(cfgE, traffic);
baseChunk = chunkInfo.Bytes;
appSDUChunkBytes = baseChunk;
if logical(opt.E2EScaleChunkWithCompression)
    maxChunk = max(1024, round(double(opt.E2EMaxSDUChunkBytes)));
    scaledChunk = baseChunk * max(1, compression);
    appSDUChunkBytes = min(maxChunk, max(baseChunk, scaledChunk));
end
airModel = localBuildE2EAirModel(cfgE, fileparts(runFolder), opt, e2eAirLUT);
airModelName = string(sixgr.util.structGet(airModel, "Mode", "logistic"));
airModelSource = string(sixgr.util.structGet(airModel, "Source", "default"));
artifactSpec = localBuildE2EArtifactSpec("truth");
enableSemanticChecks = logical(opt.E2EEnableSemanticChecks);
enablePacketTrace = true;

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
if logical(attachOK) && isfinite(double(attachSlots))
    attachGateSlots = min(nSlots, max(0, round(double(attachSlots))));
else
    attachGateSlots = nSlots;
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

coupledTruth = localInitE2ESystemCouplingContext();
if strcmp(airModeReq, "truth")
    coupledTruth = localRunE2ESystemCoupling( ...
        cfgE, runFolder, traffic, nSlots, slotDur_s, nUE, nRB, ...
        attachGateSlots, opt, flowDirCfg);
    [appSDUChunkBytes, chunkInfo.Source] = localCapE2EAppChunkForCoupledTruth( ...
        appSDUChunkBytes, chunkInfo.Source, coupledTruth);
end

for t = 1:nSlots
    [slotDL, slotUL, slotLbl] = localSlotDuplexStateE2E(cfgE, t);
    slotDirection(t) = slotLbl;
    if flowDirCfg == "DL"
        slotUL = false;
    elseif flowDirCfg == "UL"
        slotDL = false;
    end
    dataPlaneReady = logical(attachOK) && (t > attachGateSlots);
    if ~dataPlaneReady
        slotDL = false;
        slotUL = false;
    end
    slotOfferedDL = double(traffic.OfferedBitsDL(t,:));
    slotOfferedUL = double(traffic.OfferedBitsUL(t,:));
    if ~dataPlaneReady
        slotOfferedDL(:) = 0;
        slotOfferedUL(:) = 0;
    end
    offeredBitsDL(t) = sum(slotOfferedDL);
    offeredBitsUL(t) = sum(slotOfferedUL);
    offeredBits(t) = offeredBitsDL(t) + offeredBitsUL(t);

    for u = 1:nUE
        bytesInDL = floor(max(double(slotOfferedDL(u)), 0) / 8);
        bytesInUL = floor(max(double(slotOfferedUL(u)), 0) / 8);

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
                    [virtPktQ_DL{u}, nextPktIdDL(u)] = localEnqueueVirtualPacketDirect( ...
                        virtPktQ_DL{u}, nextPktIdDL(u), chunk, t, u, lcidData, qfi);
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
                    [virtPktQ_UL{u}, nextPktIdUL(u)] = localEnqueueVirtualPacketDirect( ...
                        virtPktQ_UL{u}, nextPktIdUL(u), chunk, t, u, lcidData, qfi);
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
    if coupledTruth.Enabled
        grantsDL = coupledTruth.GrantsDLBySlot{t};
        grantsUL = coupledTruth.GrantsULBySlot{t};
    else
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
    end
    grantCountDL(t) = numel(grantsDL);
    grantCountUL(t) = numel(grantsUL);
    grantCount(t) = grantCountDL(t) + grantCountUL(t);
    if coupledTruth.Enabled
        cqiCoupled = zeros(0,1);
        if ~isempty(grantsDL)
            cqiCoupled = [cqiCoupled; reshape(double([grantsDL.CQIUsed]), [], 1)]; %#ok<AGROW>
        end
        if ~isempty(grantsUL)
            cqiCoupled = [cqiCoupled; reshape(double([grantsUL.CQIUsed]), [], 1)]; %#ok<AGROW>
        end
        if ~isempty(cqiCoupled)
            meanCQI(t) = mean(cqiCoupled, "omitnan");
        end
    end
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
        [grantTBSBits, ~] = sixgr.util.resolveGrantTBSBits(gr, ...
            sprintf("E2E DL slot=%d grant=%d RNTI=%d", round(t), round(g), round(u)));
        grantTBSBytes = max(1, round(grantTBSBits / 8));
        tbsBytesBase = grantTBSBytes;
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
                macPdu = sixgr.l2.mac.TBAssembler.assemble(tbsBytes, sduList, ceList, "Direction", "DL");
            end
        else
            sduList = rlcDLTx{u}.buildMACSDUs(localMacPayloadBudget(tbsBytes));
            ioDL_RLC_TxOut(t) = ioDL_RLC_TxOut(t) + localSumMACSDUPayloadBytes(sduList);
            ceList = struct([]);
            macPdu = sixgr.l2.mac.TBAssembler.assemble(tbsBytes, sduList, ceList, "Direction", "DL");
        end
        ioDL_MAC_TBOut(t) = ioDL_MAC_TBOut(t) + numel(macPdu);

        try
            harqDL.onTx(u, harqId, macPdu, gr, t-1);
        catch
        end

        if coupledTruth.Enabled && isfield(gr, "CoupledAck")
            airRes = localCoupledGrantAirResult(gr, coupledTruth);
        else
            airRes = localDeliverGrantOverPhy(cfgE, "DL", gr, macPdu, snr_dB, airModel, strictValidation, ...
                double(ueStatesDL(u).CQI), retxDepthDL(u,pid));
        end
        ack = logical(airRes.Ok);
        blerEff = double(airRes.BLER); %#ok<NASGU>
        virtPktQ_DL{u} = localMarkVirtualPacketTx(virtPktQ_DL{u}, numel(macPdu), t, pid, ack);

        try
            harqDL.onFeedback(u, harqId, ack);
        catch
        end

        nFbDL = nFbDL + 1;
        feedbackDL(nFbDL) = struct("RNTI", u, "TBSBits", grantTBSBits, "Ack", ack);

        if ack
            ackCountDL(t) = ackCountDL(t) + 1;
            ackUE_DL(u) = ackUE_DL(u) + 1;
            retxDepthDL(u,pid) = 0;
            ioDL_Air_RxIn(t) = ioDL_Air_RxIn(t) + numel(macPdu);

            rxSdus = sixgr.l2.mac.TBAssembler.disassemble(macPdu, "Direction", "DL");
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
                [virtPktQ_DL{u}, sem] = localConsumeVirtualPacketsDirect(virtPktQ_DL{u}, deliveredNowBytes, ...
                    t, semanticSlotDur_s, pdb_ms, lastDeliveredPktIdDL(u), "DL", u);
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
        tr.CellID = double(sixgr.util.structGet(gr, "CellID", 1));
        tr.UE = u;
        tr.FlowID = u;
        tr.BearerID = lcidData;
        tr.QFI = qfi;
        tr.GrantIndex = g;
        tr.NumPRB = numPRB;
        tr.TBSBytes = grantTBSBytes;
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
        [grantTBSBits, ~] = sixgr.util.resolveGrantTBSBits(gr, ...
            sprintf("E2E UL slot=%d grant=%d RNTI=%d", round(t), round(g), round(u)));
        grantTBSBytes = max(1, round(grantTBSBits / 8));
        tbsBytesBase = grantTBSBytes;
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
                macPdu = sixgr.l2.mac.TBAssembler.assemble(tbsBytes, sduList, ceList, "Direction", "UL");
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
            macPdu = sixgr.l2.mac.TBAssembler.assemble(tbsBytes, sduList, ceList, "Direction", "UL");
        end
        ioUL_MAC_TBOut(t) = ioUL_MAC_TBOut(t) + numel(macPdu);

        try
            harqUL.onTx(u, harqId, macPdu, gr, t-1);
        catch
        end

        if coupledTruth.Enabled && isfield(gr, "CoupledAck")
            airRes = localCoupledGrantAirResult(gr, coupledTruth);
        else
            airRes = localDeliverGrantOverPhy(cfgE, "UL", gr, macPdu, snr_dB + ulSnrOffset_dB, airModel, strictValidation, ...
                double(ueStatesUL(u).CQI), retxDepthUL(u,pid));
        end
        ack = logical(airRes.Ok);
        blerEff = double(airRes.BLER); %#ok<NASGU>
        virtPktQ_UL{u} = localMarkVirtualPacketTx(virtPktQ_UL{u}, numel(macPdu), t, pid, ack);

        try
            harqUL.onFeedback(u, harqId, ack);
        catch
        end

        nFbUL = nFbUL + 1;
        feedbackUL(nFbUL) = struct("RNTI", u, "TBSBits", grantTBSBits, "Ack", ack);

        if ack
            ackCountUL(t) = ackCountUL(t) + 1;
            ackUE_UL(u) = ackUE_UL(u) + 1;
            retxDepthUL(u,pid) = 0;
            ioUL_Air_RxIn(t) = ioUL_Air_RxIn(t) + numel(macPdu);

            rxSdus = sixgr.l2.mac.TBAssembler.disassemble(macPdu, "Direction", "UL");
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
                [virtPktQ_UL{u}, sem] = localConsumeVirtualPacketsDirect(virtPktQ_UL{u}, deliveredNowBytes, ...
                    t, semanticSlotDur_s, pdb_ms, lastDeliveredPktIdUL(u), "UL", u);
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
        tr.CellID = double(sixgr.util.structGet(gr, "CellID", 1));
        tr.UE = u;
        tr.FlowID = u;
        tr.BearerID = lcidData;
        tr.QFI = qfi;
        tr.GrantIndex = g;
        tr.NumPRB = numPRB;
        tr.TBSBytes = grantTBSBytes;
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

    if ~coupledTruth.Enabled
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
            virtPktQ_DL{u}, nSlots, semanticSlotDur_s, pdb_ms, ...
            lastDeliveredPktIdDL(u), "DL", u, finalDropCause);
        if ~isempty(dropRowsDL)
            [packetTraceChunks, packetTraceChunkCount] = localPushStructChunk( ...
                packetTraceChunks, packetTraceChunkCount, dropRowsDL(:));
        end
        [virtPktQ_UL{u}, dropRowsUL] = localFinalizeVirtualQueueDrops( ...
            virtPktQ_UL{u}, nSlots, semanticSlotDur_s, pdb_ms, ...
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
packetTraceTable = localPacketTraceRowsToTable(packetTraceRows);
[schedulerTraceTable, harqTraceTable] = localBuildE2EGrantTraceTables(grantTraceRows);
attachTraceTable = localBuildE2EAttachTraceTable(attachTraceRows);
[packetIntegrityTable, semanticPassRate] = localBuildE2EPacketIntegrityTableFromTrace(packetTraceTable, pdb_ms);
[flowSummaryTable, bearerSummaryTable, dropCauseTable] = localBuildE2ETraceSummaries(packetTraceTable, simDur_s);
[deliveryRatio, deliveryRatioDL, deliveryRatioUL] = localPacketIntegrityDeliveryRatios(packetIntegrityTable);
packetTraceTable = localAnnotateE2ETraceTable(packetTraceTable, "TRUTH_REPLAY", "REAL_PACKET_TRAVERSAL");
schedulerTraceTable = localAnnotateE2ETraceTable(schedulerTraceTable, "TRUTH_REPLAY", "REAL_SCHEDULER_GRANT_TRACE");
harqTraceTable = localAnnotateE2ETraceTable(harqTraceTable, "TRUTH_REPLAY", "REAL_HARQ_TRACE");
attachTraceTable = localAnnotateE2EDataTable(attachTraceTable, "TRUTH_REPLAY", "ATTACH_CONTROL_PLANE_TRACE");
packetIntegrityTable = localAnnotateE2EDataTable(packetIntegrityTable, "TRUTH_REPLAY", "REAL_PACKET_TRAVERSAL");
flowSummaryTable = localAnnotateE2EDataTable(flowSummaryTable, "TRUTH_REPLAY", "REAL_PACKET_TRAVERSAL");
bearerSummaryTable = localAnnotateE2EDataTable(bearerSummaryTable, "TRUTH_REPLAY", "REAL_PACKET_TRAVERSAL");
dropCauseTable = localAnnotateE2EDataTable(dropCauseTable, "TRUTH_REPLAY", "REAL_PACKET_TRAVERSAL");

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
summaryTable = localAppendE2ESummaryStrictness(summaryTable, cfg, opt);
if coupledTruth.Enabled
    summaryTable.E2EAirModelSource = repmat(string(coupledTruth.Source), height(summaryTable), 1);
end
summaryTable.PacketAccountingPassRate_pct = summaryTable.SemanticCheckPassRate_pct;
summaryTable.PacketAccountingMeaning = repmat(localE2EAccountingMeaning(), height(summaryTable), 1);
if coupledTruth.Enabled
    summaryTable.ExecutionBackend = repmat("FULL_STACK_REPLAY_SYSTEM_COUPLED", height(summaryTable), 1);
    summaryTable.PHYMode = repmat("SYSTEM_WAVEFORM_GRANT_TRACE_REPLAY", height(summaryTable), 1);
    summaryTable.AirInterfaceBackend = repmat(string(coupledTruth.ExecutionBackend), height(summaryTable), 1);
    summaryTable.AirInterfacePHYMode = repmat(string(coupledTruth.PHYMode), height(summaryTable), 1);
else
    summaryTable.ExecutionBackend = repmat("FULL_STACK_REPLAY", height(summaryTable), 1);
    summaryTable.PHYMode = repmat("GRANT_DELIVERY_BACKEND", height(summaryTable), 1);
    summaryTable.AirInterfaceBackend = repmat("WAVEFORM_GRANT_REPLAY", height(summaryTable), 1);
    summaryTable.AirInterfacePHYMode = repmat("CRC_WAVEFORM_REPLAY", height(summaryTable), 1);
end
summaryTable.ExecutionMode = repmat("TRUTH_REPLAY", height(summaryTable), 1);
summaryTable.ArtifactMode = repmat(string(artifactSpec.Mode), height(summaryTable), 1);
summaryTable.PacketTraceSemantics = repmat("REAL_PACKET_TRAVERSAL", height(summaryTable), 1);
summaryTable.SchedulerTraceSemantics = repmat("REAL_SCHEDULER_GRANT_TRACE", height(summaryTable), 1);
summaryTable.HARQTraceSemantics = repmat("REAL_HARQ_TRACE", height(summaryTable), 1);
summaryTable.SummaryArtifact = repmat(string(artifactSpec.TopLevel.SummaryCSV), height(summaryTable), 1);
summaryTable.PacketIntegrityArtifact = repmat(string(artifactSpec.TopLevel.PacketIntegrityCSV), height(summaryTable), 1);
qosEvaluationTable = localBuildE2EQoSEvaluationTable(cfgE, traffic, packetIntegrityTable, ...
    offered_Mbps, offeredDL_Mbps, offeredUL_Mbps, ...
    goodput_Mbps_total, goodputDL_Mbps_total, goodputUL_Mbps_total, logical(attachOK));
qosEvaluationTable = localAnnotateE2EDataTable(qosEvaluationTable, "TRUTH_REPLAY", "QOS_SLA_EVALUATION");
summaryTable = localAppendE2EQoSSummary(summaryTable, qosEvaluationTable, string(artifactSpec.TopLevel.QoSEvaluationCSV));
summaryTable.PacketTraceArtifact = repmat("packet_flow/csv/" + string(artifactSpec.EndToEnd.PacketTraceCSV), height(summaryTable), 1);
summaryTable.SchedulerTraceArtifact = repmat("packet_flow/csv/" + string(artifactSpec.EndToEnd.SchedulerTraceCSV), height(summaryTable), 1);
summaryTable.HARQTraceArtifact = repmat("packet_flow/csv/" + string(artifactSpec.EndToEnd.HARQTraceCSV), height(summaryTable), 1);
summaryTable.E2ESystemCoupled = repmat(logical(coupledTruth.Enabled), height(summaryTable), 1);
summaryTable.E2ECouplingMode = repmat(string(coupledTruth.CouplingMode), height(summaryTable), 1);
summaryTable.E2ECouplingNotes = repmat(string(coupledTruth.Notes), height(summaryTable), 1);
summaryTable.AppSDUChunkBytes = repmat(double(appSDUChunkBytes), height(summaryTable), 1);
summaryTable.AppSDUChunkSource = repmat(string(chunkInfo.Source), height(summaryTable), 1);
summaryTable.ConformanceLevel = repmat(localDetermineConformanceLevel(cfg, opt, struct( ...
    "E2ESystemCoupled", logical(coupledTruth.Enabled))), height(summaryTable), 1);

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
resultIntegrityTable = sixgr.report.checkResultIntegrity(struct( ...
    "SummaryTable", summaryTable, ...
    "PacketIntegrityTable", packetIntegrityTable, ...
    "FlowSummaryTable", flowSummaryTable, ...
    "BearerSummaryTable", bearerSummaryTable, ...
    "PacketTraceTable", packetTraceTable, ...
    "CheckTable", checkTable));
resultIntegrityPassRate = 100 * mean(double(resultIntegrityTable.Pass));
summaryTable.ResultIntegrityPassRate_pct = resultIntegrityPassRate;
summaryTable.ResultIntegrityFailureCount = sum(~logical(resultIntegrityTable.Pass));
checkTable = localAppendResultIntegrityChecks(checkTable, resultIntegrityTable);
if any(~logical(resultIntegrityTable.Pass)) && strictValidation
    failedChecks = string(resultIntegrityTable.Check(~logical(resultIntegrityTable.Pass)));
    error("sixgr:e2e:ResultIntegrityFailed", ...
        "Strict E2E truth validation failed result-integrity checks: %s", ...
        strjoin(cellstr(failedChecks), ", "));
end
slotTable = localAnnotateE2EDataTable(slotTable, "TRUTH_REPLAY", "SLOT_LEVEL_MEASUREMENTS");
componentIOTable = localAnnotateE2EDataTable(componentIOTable, "TRUTH_REPLAY", "COMPONENT_IO_COUNTERS");
checkTable = localAnnotateE2EDataTable(checkTable, "TRUTH_REPLAY", "VALIDATION_RESULTS");

aiTable = localRunE2EAIProbe(cfgE, logical(opt.E2EEnableAI), snr_dB);
aiTable = localAnnotateE2EDataTable(aiTable, "TRUTH_REPLAY", "AI_AUXILIARY_METRICS");

sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_packet_trace.csv"), packetTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_flow_summary.csv"), flowSummaryTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_bearer_summary.csv"), bearerSummaryTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_attach_trace.csv"), attachTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_harq_trace.csv"), harqTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_scheduler_trace.csv"), schedulerTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_drop_causes.csv"), dropCauseTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_e2e_qos_evaluation.csv"), qosEvaluationTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.PacketTraceCSV))), packetTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.FlowSummaryCSV))), flowSummaryTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.BearerSummaryCSV))), bearerSummaryTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.AttachTraceCSV))), attachTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.HARQTraceCSV))), harqTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.SchedulerTraceCSV))), schedulerTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.DropCausesCSV))), dropCauseTable);

sixgr.util.matSave(fullfile(runFolder, "mat", "e2e_probe.mat"), struct( ...
    "slotTable", slotTable, ...
    "componentIOTable", componentIOTable, ...
    "checkTable", checkTable, ...
    "packetIntegrityTable", packetIntegrityTable, ...
    "qosEvaluationTable", qosEvaluationTable, ...
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
sixgr.util.matSave(fullfile(runFolder, "mat", char(string(artifactSpec.EndToEnd.MAT))), struct( ...
    "slotTable", slotTable, ...
    "componentIOTable", componentIOTable, ...
    "checkTable", checkTable, ...
    "packetIntegrityTable", packetIntegrityTable, ...
    "qosEvaluationTable", qosEvaluationTable, ...
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
out.Ok = all(logical(checkTable.Pass));
out.RunFolder = runFolder;
out.ExecutionMode = "TRUTH_REPLAY";
out.ArtifactMode = string(artifactSpec.Mode);
out.ArtifactSpec = artifactSpec;
out.SlotMetricsArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.SlotMetricsCSV)));
out.ComponentIOArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.ComponentIOCSV)));
out.ComponentChecksArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.ComponentChecksCSV)));
out.SummaryArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.SummaryCSV)));
out.QoSEvaluationArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.QoSEvaluationCSV)));
out.AIArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.AIMetricsCSV)));
out.PacketIntegrityArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.PacketIntegrityCSV)));
out.PacketTraceArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.PacketTraceCSV)));
out.FlowSummaryArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.FlowSummaryCSV)));
out.BearerSummaryArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.BearerSummaryCSV)));
out.AttachTraceArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.AttachTraceCSV)));
out.SchedulerTraceArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.SchedulerTraceCSV)));
out.HARQTraceArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.HARQTraceCSV)));
out.DropCauseArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.DropCausesCSV)));
out.ArtifactMAT = fullfile(runFolder, "mat", char(string(artifactSpec.EndToEnd.MAT)));
out.SlotTable = slotTable;
out.ComponentIOTable = componentIOTable;
out.CheckTable = checkTable;
out.PacketIntegrityTable = packetIntegrityTable;
out.QoSEvaluationTable = qosEvaluationTable;
out.PacketTraceTable = packetTraceTable;
out.FlowSummaryTable = flowSummaryTable;
out.BearerSummaryTable = bearerSummaryTable;
out.AttachTraceTable = attachTraceTable;
out.HARQTraceTable = harqTraceTable;
out.SchedulerTraceTable = schedulerTraceTable;
out.DropCauseTable = dropCauseTable;
out.SummaryTable = summaryTable;
out.AITable = aiTable;
out.ResultIntegrityTable = resultIntegrityTable;
out.SystemCoupled = logical(coupledTruth.Enabled);
out.CouplingMode = string(coupledTruth.CouplingMode);
out.CouplingNotes = string(coupledTruth.Notes);
out.AppSDUChunkBytes = double(appSDUChunkBytes);
out.AppSDUChunkSource = string(chunkInfo.Source);
out.CoupledSystemMeta = rmfield(coupledTruth, {'GrantsDLBySlot','GrantsULBySlot','Result'});
if coupledTruth.Enabled
    out.Notes = "E2E truth replay completed with actual SystemLevelRunner waveform grant coupling and lower-layer scheduler/HARQ outcomes.";
else
    out.Notes = "E2E truth replay completed with explicit truth-labeled artifacts and real packet/grant traversal traces.";
end
end

function out = localRunEndToEndProbeFast(cfg, runFolder, opt, e2eAirLUT)
%#ok<INUSD>
error("sixgr:campaign:ProxyModeRemoved", ...
    "The E2E fast proxy kernel is inaccessible in the active waveform-truth-only repository.");

if nargin < 4
    e2eAirLUT = struct();
end
sixgr.util.ensureDir(runFolder);
sixgr.util.ensureDir(fullfile(runFolder, "csv"));
sixgr.util.ensureDir(fullfile(runFolder, "mat"));
sixgr.util.ensureDir(fullfile(runFolder, "image"));
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
airModeReq = lower(char(string(sixgr.util.structGet(opt, "E2EAirModel", "truth"))));
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
artifactSpec = localBuildE2EArtifactSpec("fast_proxy");

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

pdb_ms = double(sixgr.util.structGet(traffic, "PacketDelayBudget_ms", sixgr.util.structGet(cfgE, "traffic.packetDelayBudget_ms", 50)));
proxyPacketTraceTable = localBuildFastE2EProxyPacketTrace( ...
    nSlots, nUE, slotDur_s, offeredDLMat, offeredULMat, deliveredBitsDL, deliveredBitsUL, ...
    lcidData, qfi, attachOK, pdb_ms);
packetTraceTable = localPacketTraceRowsToTable(repmat(localPacketTraceRowTemplate(), 0, 1));
[schedulerTraceTable, harqTraceTable] = localBuildE2EGrantTraceTables([]);
attachTraceTable = localBuildE2EAttachTraceTable(attachTraceRows);
[packetIntegrityTable, semanticPassRate] = localBuildE2EPacketIntegrityTableFromTrace(proxyPacketTraceTable, pdb_ms);
[flowSummaryTable, bearerSummaryTable, dropCauseTable] = localBuildE2ETraceSummaries(proxyPacketTraceTable, simDur_s);
[deliveryRatio, deliveryRatioDL, deliveryRatioUL] = localPacketIntegrityDeliveryRatios(packetIntegrityTable);
packetTraceTable = localAnnotateE2ETraceTable(packetTraceTable, "FAST_PROXY", "NO_REAL_PACKET_TRAVERSAL_IN_PROXY");
schedulerTraceTable = localAnnotateE2ETraceTable(schedulerTraceTable, "FAST_PROXY", "NO_REAL_SCHEDULER_GRANT_TRACE_IN_PROXY");
harqTraceTable = localAnnotateE2ETraceTable(harqTraceTable, "FAST_PROXY", "NO_REAL_HARQ_TRACE_IN_PROXY");
attachTraceTable = localAnnotateE2EDataTable(attachTraceTable, "FAST_PROXY", "ATTACH_CONTROL_PLANE_TRACE");
packetIntegrityTable = localAnnotateE2EDataTable(packetIntegrityTable, "FAST_PROXY", "PROXY_PACKET_MODEL");
flowSummaryTable = localAnnotateE2EDataTable(flowSummaryTable, "FAST_PROXY", "PROXY_PACKET_MODEL");
bearerSummaryTable = localAnnotateE2EDataTable(bearerSummaryTable, "FAST_PROXY", "PROXY_PACKET_MODEL");
dropCauseTable = localAnnotateE2EDataTable(dropCauseTable, "FAST_PROXY", "PROXY_PACKET_MODEL");

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
summaryTable = localAppendE2ESummaryStrictness(summaryTable, cfg, opt);
summaryTable.ComponentCheckPassRate_pct = passRate;
summaryTable.PacketAccountingPassRate_pct = summaryTable.SemanticCheckPassRate_pct;
summaryTable.PacketAccountingMeaning = repmat(localE2EAccountingMeaning(), height(summaryTable), 1);
summaryTable.ExecutionBackend = repmat("FAST_PROXY_KERNEL", height(summaryTable), 1);
summaryTable.PHYMode = repmat("QUEUE_CQI_LOGISTIC_PROXY", height(summaryTable), 1);
summaryTable.ExecutionMode = repmat("FAST_PROXY", height(summaryTable), 1);
summaryTable.ArtifactMode = repmat(string(artifactSpec.Mode), height(summaryTable), 1);
summaryTable.PacketTraceSemantics = repmat("NO_REAL_PACKET_TRAVERSAL_IN_PROXY", height(summaryTable), 1);
summaryTable.SchedulerTraceSemantics = repmat("NO_REAL_SCHEDULER_GRANT_TRACE_IN_PROXY", height(summaryTable), 1);
summaryTable.HARQTraceSemantics = repmat("NO_REAL_HARQ_TRACE_IN_PROXY", height(summaryTable), 1);
summaryTable.SummaryArtifact = repmat(string(artifactSpec.TopLevel.SummaryCSV), height(summaryTable), 1);
summaryTable.PacketIntegrityArtifact = repmat(string(artifactSpec.TopLevel.PacketIntegrityCSV), height(summaryTable), 1);
qosEvaluationTable = localBuildE2EQoSEvaluationTable(cfgE, traffic, packetIntegrityTable, ...
    offered_Mbps, offeredDL_Mbps, offeredUL_Mbps, ...
    goodput_Mbps_total, goodputDL_Mbps_total, goodputUL_Mbps_total, logical(attachOK));
qosEvaluationTable = localAnnotateE2EDataTable(qosEvaluationTable, "FAST_PROXY", "QOS_SLA_EVALUATION");
summaryTable = localAppendE2EQoSSummary(summaryTable, qosEvaluationTable, string(artifactSpec.TopLevel.QoSEvaluationCSV));
summaryTable.PacketTraceArtifact = repmat("packet_flow/csv/" + string(artifactSpec.EndToEnd.PacketTraceCSV), height(summaryTable), 1);
summaryTable.SchedulerTraceArtifact = repmat("packet_flow/csv/" + string(artifactSpec.EndToEnd.SchedulerTraceCSV), height(summaryTable), 1);
summaryTable.HARQTraceArtifact = repmat("packet_flow/csv/" + string(artifactSpec.EndToEnd.HARQTraceCSV), height(summaryTable), 1);
resultIntegrityTable = sixgr.report.checkResultIntegrity(struct( ...
    "SummaryTable", summaryTable, ...
    "PacketIntegrityTable", packetIntegrityTable, ...
    "FlowSummaryTable", flowSummaryTable, ...
    "BearerSummaryTable", bearerSummaryTable, ...
    "PacketTraceTable", packetTraceTable, ...
    "CheckTable", checkTable));
resultIntegrityPassRate = 100 * mean(double(resultIntegrityTable.Pass));
summaryTable.ResultIntegrityPassRate_pct = resultIntegrityPassRate;
summaryTable.ResultIntegrityFailureCount = sum(~logical(resultIntegrityTable.Pass));
checkTable = localAppendResultIntegrityChecks(checkTable, resultIntegrityTable);
if any(~logical(resultIntegrityTable.Pass)) && logical(opt.E2EStrictValidation)
    failedChecks = string(resultIntegrityTable.Check(~logical(resultIntegrityTable.Pass)));
    error("sixgr:e2e:ResultIntegrityFailed", ...
        "Strict E2E proxy validation failed result-integrity checks: %s", ...
        strjoin(cellstr(failedChecks), ", "));
end
slotTable = localAnnotateE2EDataTable(slotTable, "FAST_PROXY", "SLOT_LEVEL_PROXY_METRICS");
componentIOTable = localAnnotateE2EDataTable(componentIOTable, "FAST_PROXY", "PROXY_COMPONENT_IO_COUNTERS");
checkTable = localAnnotateE2EDataTable(checkTable, "FAST_PROXY", "VALIDATION_RESULTS");

aiTable = localRunE2EAIProbe(cfgE, logical(opt.E2EEnableAI), snr_dB);
aiTable = localAnnotateE2EDataTable(aiTable, "FAST_PROXY", "AI_AUXILIARY_METRICS");

sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_packet_trace.csv"), packetTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_flow_summary.csv"), flowSummaryTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_bearer_summary.csv"), bearerSummaryTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_attach_trace.csv"), attachTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_harq_trace.csv"), harqTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_scheduler_trace.csv"), schedulerTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "e2e_drop_causes.csv"), dropCauseTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "probe_e2e_qos_evaluation.csv"), qosEvaluationTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.PacketTraceCSV))), packetTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.FlowSummaryCSV))), flowSummaryTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.BearerSummaryCSV))), bearerSummaryTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.AttachTraceCSV))), attachTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.HARQTraceCSV))), harqTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.SchedulerTraceCSV))), schedulerTraceTable);
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.DropCausesCSV))), dropCauseTable);

sixgr.util.matSave(fullfile(runFolder, "mat", "e2e_probe.mat"), struct( ...
    "slotTable", slotTable, ...
    "componentIOTable", componentIOTable, ...
    "checkTable", checkTable, ...
    "packetIntegrityTable", packetIntegrityTable, ...
    "qosEvaluationTable", qosEvaluationTable, ...
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
sixgr.util.matSave(fullfile(runFolder, "mat", char(string(artifactSpec.EndToEnd.MAT))), struct( ...
    "slotTable", slotTable, ...
    "componentIOTable", componentIOTable, ...
    "checkTable", checkTable, ...
    "packetIntegrityTable", packetIntegrityTable, ...
    "qosEvaluationTable", qosEvaluationTable, ...
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
out.Ok = all(logical(checkTable.Pass));
out.RunFolder = runFolder;
out.ExecutionMode = "FAST_PROXY";
out.ArtifactMode = string(artifactSpec.Mode);
out.ArtifactSpec = artifactSpec;
out.SlotMetricsArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.SlotMetricsCSV)));
out.ComponentIOArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.ComponentIOCSV)));
out.ComponentChecksArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.ComponentChecksCSV)));
out.SummaryArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.SummaryCSV)));
out.QoSEvaluationArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.QoSEvaluationCSV)));
out.AIArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.AIMetricsCSV)));
out.PacketIntegrityArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.TopLevel.PacketIntegrityCSV)));
out.PacketTraceArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.PacketTraceCSV)));
out.FlowSummaryArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.FlowSummaryCSV)));
out.BearerSummaryArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.BearerSummaryCSV)));
out.AttachTraceArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.AttachTraceCSV)));
out.SchedulerTraceArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.SchedulerTraceCSV)));
out.HARQTraceArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.HARQTraceCSV)));
out.DropCauseArtifactCSV = fullfile(runFolder, "csv", char(string(artifactSpec.EndToEnd.DropCausesCSV)));
out.ArtifactMAT = fullfile(runFolder, "mat", char(string(artifactSpec.EndToEnd.MAT)));
out.SlotTable = slotTable;
out.ComponentIOTable = componentIOTable;
out.CheckTable = checkTable;
out.PacketIntegrityTable = packetIntegrityTable;
out.QoSEvaluationTable = qosEvaluationTable;
out.PacketTraceTable = packetTraceTable;
out.FlowSummaryTable = flowSummaryTable;
out.BearerSummaryTable = bearerSummaryTable;
out.AttachTraceTable = attachTraceTable;
out.HARQTraceTable = harqTraceTable;
out.SchedulerTraceTable = schedulerTraceTable;
out.DropCauseTable = dropCauseTable;
out.SummaryTable = summaryTable;
out.AITable = aiTable;
out.ResultIntegrityTable = resultIntegrityTable;
out.Notes = "E2E fast proxy completed with explicit proxy-labeled artifacts; packet, scheduler, and HARQ primary traces remain empty because no real traversal exists in proxy mode.";
end

function packetTraceTable = localBuildFastE2EProxyPacketTrace( ...
    nSlots, nUE, slotDur_s, offeredDLMat, offeredULMat, deliveredBitsDL, deliveredBitsUL, ...
    lcidData, qfi, attachOK, pdb_ms)

appChunk = 1500;
queueBytesDL_UE = zeros(nUE,1);
queueBytesUL_UE = zeros(nUE,1);
virtPktQ_DL = cell(nUE,1);
virtPktQ_UL = cell(nUE,1);
nextPktIdDL = zeros(nUE,1);
nextPktIdUL = zeros(nUE,1);
lastDeliveredPktIdDL = zeros(nUE,1);
lastDeliveredPktIdUL = zeros(nUE,1);
offeredDLBytes = floor(max(double(offeredDLMat), 0) / 8);
offeredULBytes = floor(max(double(offeredULMat), 0) / 8);
deliveredDLBytes = floor(max(double(deliveredBitsDL(:)), 0) / 8);
deliveredULBytes = floor(max(double(deliveredBitsUL(:)), 0) / 8);
packetChunks = cell(max(128, min(2 * nSlots * max(nUE, 1), 2e6)), 1);
packetChunkCount = 0;
vqCap0 = max(512, 4 * nSlots);

for u = 1:nUE
    virtPktQ_DL{u} = localInitVirtualQueue(vqCap0);
    virtPktQ_UL{u} = localInitVirtualQueue(vqCap0);
end

for t = 1:nSlots
    for u = 1:nUE
        bytesInDL = offeredDLBytes(t,u);
        bytesInUL = offeredULBytes(t,u);
        rem = bytesInDL;
        while rem > 0
            chunk = min(rem, appChunk);
            [virtPktQ_DL{u}, nextPktIdDL(u)] = localEnqueueVirtualPacketDirect( ...
                virtPktQ_DL{u}, nextPktIdDL(u), chunk, t, u, lcidData, qfi);
            queueBytesDL_UE(u) = queueBytesDL_UE(u) + chunk;
            rem = rem - chunk;
        end
        rem = bytesInUL;
        while rem > 0
            chunk = min(rem, appChunk);
            [virtPktQ_UL{u}, nextPktIdUL(u)] = localEnqueueVirtualPacketDirect( ...
                virtPktQ_UL{u}, nextPktIdUL(u), chunk, t, u, lcidData, qfi);
            queueBytesUL_UE(u) = queueBytesUL_UE(u) + chunk;
            rem = rem - chunk;
        end
    end

    delBytesDL = deliveredDLBytes(t);
    delBytesUL = deliveredULBytes(t);
    allocDL = localProportionalByteAllocation(queueBytesDL_UE, delBytesDL);
    allocUL = localProportionalByteAllocation(queueBytesUL_UE, delBytesUL);
    if ~attachOK
        allocDL(:) = 0;
        allocUL(:) = 0;
    end

    for u = 1:nUE
        if allocDL(u) > 0
            virtPktQ_DL{u} = localMarkVirtualPacketTx(virtPktQ_DL{u}, allocDL(u), t, 0, true);
            [virtPktQ_DL{u}, semDL] = localConsumeVirtualPacketsDirect( ...
                virtPktQ_DL{u}, allocDL(u), t, slotDur_s, pdb_ms, lastDeliveredPktIdDL(u), "DL", u);
            lastDeliveredPktIdDL(u) = semDL.LastDeliveredId;
            queueBytesDL_UE(u) = max(queueBytesDL_UE(u) - allocDL(u), 0);
            if ~isempty(semDL.PacketRows)
                [packetChunks, packetChunkCount] = localPushStructChunk( ...
                    packetChunks, packetChunkCount, semDL.PacketRows(:));
            end
        end
        if allocUL(u) > 0
            virtPktQ_UL{u} = localMarkVirtualPacketTx(virtPktQ_UL{u}, allocUL(u), t, 0, true);
            [virtPktQ_UL{u}, semUL] = localConsumeVirtualPacketsDirect( ...
                virtPktQ_UL{u}, allocUL(u), t, slotDur_s, pdb_ms, lastDeliveredPktIdUL(u), "UL", u);
            lastDeliveredPktIdUL(u) = semUL.LastDeliveredId;
            queueBytesUL_UE(u) = max(queueBytesUL_UE(u) - allocUL(u), 0);
            if ~isempty(semUL.PacketRows)
                [packetChunks, packetChunkCount] = localPushStructChunk( ...
                    packetChunks, packetChunkCount, semUL.PacketRows(:));
            end
        end
    end
end

finalDropCause = "not_delivered_by_end";
if ~attachOK
    finalDropCause = "attach_not_connected";
end
for u = 1:nUE
    [virtPktQ_DL{u}, drDL] = localFinalizeVirtualQueueDrops( ...
        virtPktQ_DL{u}, nSlots, slotDur_s, pdb_ms, lastDeliveredPktIdDL(u), "DL", u, finalDropCause);
    if ~isempty(drDL)
        [packetChunks, packetChunkCount] = localPushStructChunk( ...
            packetChunks, packetChunkCount, drDL(:));
    end
    [virtPktQ_UL{u}, drUL] = localFinalizeVirtualQueueDrops( ...
        virtPktQ_UL{u}, nSlots, slotDur_s, pdb_ms, lastDeliveredPktIdUL(u), "UL", u, finalDropCause);
    if ~isempty(drUL)
        [packetChunks, packetChunkCount] = localPushStructChunk( ...
            packetChunks, packetChunkCount, drUL(:));
    end
end

packetRows = localConcatStructChunks(packetChunks, packetChunkCount, localPacketTraceRowTemplate());
packetTraceTable = localPacketTraceRowsToTable(packetRows);
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
            [virtPktQ_DL{u}, nextPktIdDL(u)] = localEnqueueVirtualPacketDirect( ...
                virtPktQ_DL{u}, nextPktIdDL(u), chunk, t, u, lcidData, qfi);
            queueBytesDL_UE(u) = queueBytesDL_UE(u) + chunk;
            rem = rem - chunk;
        end
        rem = bytesInUL;
        while rem > 0
            chunk = min(rem, appChunk);
            [virtPktQ_UL{u}, nextPktIdUL(u)] = localEnqueueVirtualPacketDirect( ...
                virtPktQ_UL{u}, nextPktIdUL(u), chunk, t, u, lcidData, qfi);
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
            [virtPktQ_DL{u}, semDL] = localConsumeVirtualPacketsDirect( ...
                virtPktQ_DL{u}, allocDL(u), t, slotDur_s, pdbSlots, lastDeliveredPktIdDL(u), "DL", u);
            lastDeliveredPktIdDL(u) = semDL.LastDeliveredId;
            queueBytesDL_UE(u) = max(queueBytesDL_UE(u) - allocDL(u), 0);
            if ~isempty(semDL.PacketRows)
                packetRows = [packetRows; semDL.PacketRows(:)]; %#ok<AGROW>
            end
        end
        if allocUL(u) > 0
            virtPktQ_UL{u} = localMarkVirtualPacketTx(virtPktQ_UL{u}, allocUL(u), t, 0, true);
            [virtPktQ_UL{u}, semUL] = localConsumeVirtualPacketsDirect( ...
                virtPktQ_UL{u}, allocUL(u), t, slotDur_s, pdbSlots, lastDeliveredPktIdUL(u), "UL", u);
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
[schedulerTraceTable, harqTraceTable] = localBuildE2EGrantTraceTables([]);
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
[schedulerTraceTable, harqTraceTable] = localBuildE2EGrantTraceTables([]);
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

% Packet-accounting integrity checks only. QoS/SLA acceptance is reported separately.
if ~isempty(packetIntegrityTable) && all(ismember(["Direction"], string(packetIntegrityTable.Properties.VariableNames)))
    for i = 1:height(packetIntegrityTable)
        dirI = string(packetIntegrityTable.Direction(i));
        if dirI == "ALL"
            continue;
        end
        passField = "SemanticPass";
        if ismember("AccountingIntegrityPass", string(packetIntegrityTable.Properties.VariableNames))
            passField = "AccountingIntegrityPass";
        end
        notes = "Packet accounting integrity: no duplicate delivery inflation, no out-of-order accounting bug, honest deadline-miss bookkeeping";
        if ismember("Notes", string(packetIntegrityTable.Properties.VariableNames))
            notes = localJoinNotes(notes, string(packetIntegrityTable.Notes(i)));
        end
        rows(end+1,1) = struct('Direction',dirI,'Component',"PACKET_ACCOUNTING_INTEGRITY", ...
            'InputBytes',0,'OutputBytes',0,'ExpectedRelation',"packet_accounting_checks",'Pass',logical(packetIntegrityTable.(char(passField))(i)), ...
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

function T = localAppendResultIntegrityChecks(T, resultIntegrityTable)
if ~(istable(resultIntegrityTable) && ~isempty(resultIntegrityTable))
    return;
end

rows = repmat(struct('Direction',"ALL",'Component',"",'InputBytes',0,'OutputBytes',0, ...
    'ExpectedRelation',"",'Pass',false,'Notes',""), height(resultIntegrityTable), 1);
for i = 1:height(resultIntegrityTable)
    componentName = "RESULT_INTEGRITY_" + upper(strrep(string(resultIntegrityTable.Check(i)), "-", "_"));
    rows(i) = struct( ...
        'Direction',"ALL", ...
        'Component',componentName, ...
        'InputBytes',0, ...
        'OutputBytes',0, ...
        'ExpectedRelation',"report_check", ...
        'Pass',logical(resultIntegrityTable.Pass(i)), ...
        'Notes',string(resultIntegrityTable.Notes(i)));
end

appendT = struct2table(rows);
if isempty(T)
    T = appendT;
else
    T = [T; appendT]; %#ok<AGROW>
end
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
persistent rowTemplate;
if isempty(rowTemplate)
    rowTemplate = struct();
    rowTemplate.Direction = "";
    rowTemplate.UE = NaN;
    rowTemplate.PacketID = NaN;
    rowTemplate.FlowID = NaN;
    rowTemplate.BearerID = NaN;
    rowTemplate.QFI = NaN;
    rowTemplate.PacketBytes = NaN;
    rowTemplate.GenerationSlot = NaN;
    rowTemplate.GenerationTime_s = NaN;
    rowTemplate.GrantSlot = NaN;
    rowTemplate.HARQProcess = NaN;
    rowTemplate.Attempts = NaN;
    rowTemplate.CRCResult = false;
    rowTemplate.DeliverySlot = NaN;
    rowTemplate.DeliveryTime_s = NaN;
    rowTemplate.Latency_ms = NaN;
    rowTemplate.DeadlineMiss = false;
    rowTemplate.DuplicateFlag = false;
    rowTemplate.ReorderFlag = false;
    rowTemplate.DropCause = "";
end
row = rowTemplate;
end

function row = localE2EGrantTraceRowTemplate()
persistent rowTemplate;
if isempty(rowTemplate)
    rowTemplate = struct();
    rowTemplate.Slot = NaN;
    rowTemplate.Time_s = NaN;
    rowTemplate.Direction = "";
    rowTemplate.CellID = NaN;
    rowTemplate.UE = NaN;
    rowTemplate.FlowID = NaN;
    rowTemplate.BearerID = NaN;
    rowTemplate.QFI = NaN;
    rowTemplate.GrantIndex = NaN;
    rowTemplate.NumPRB = NaN;
    rowTemplate.TBSBytes = NaN;
    rowTemplate.CQIUsed = NaN;
    rowTemplate.MCSIndex = NaN;
    rowTemplate.NumLayers = NaN;
    rowTemplate.TargetCodeRate = NaN;
    rowTemplate.QueueBytesBefore = NaN;
    rowTemplate.QueueBytesAfter = NaN;
    rowTemplate.HARQProcess = NaN;
    rowTemplate.RetxDepthBefore = NaN;
    rowTemplate.RetxDepthAfter = NaN;
    rowTemplate.AttemptCount = NaN;
    rowTemplate.IsRetransmission = false;
    rowTemplate.Ack = false;
    rowTemplate.CRCResult = false;
    rowTemplate.BLER = NaN;
    rowTemplate.AirMode = "";
    rowTemplate.Note = "";
    rowTemplate.GrantReason = "";
end
row = rowTemplate;
end

function spec = localBuildE2EArtifactSpec(mode)
mode = lower(string(mode));
if strlength(mode) == 0
    mode = "unknown";
end
spec = struct();
spec.Mode = mode;
spec.TopLevel = struct( ...
    "SlotMetricsCSV", "probe_e2e_slot_metrics_" + mode + ".csv", ...
    "ComponentIOCSV", "probe_e2e_component_io_" + mode + ".csv", ...
    "ComponentChecksCSV", "probe_e2e_component_checks_" + mode + ".csv", ...
    "PacketIntegrityCSV", "probe_e2e_packet_integrity_" + mode + ".csv", ...
    "SummaryCSV", "probe_e2e_summary_" + mode + ".csv", ...
    "QoSEvaluationCSV", "probe_e2e_qos_evaluation_" + mode + ".csv", ...
    "AIMetricsCSV", "probe_e2e_ai_metrics_" + mode + ".csv");
spec.EndToEnd = struct( ...
    "PacketTraceCSV", "e2e_packet_trace_" + mode + ".csv", ...
    "FlowSummaryCSV", "e2e_flow_summary_" + mode + ".csv", ...
    "BearerSummaryCSV", "e2e_bearer_summary_" + mode + ".csv", ...
    "AttachTraceCSV", "e2e_attach_trace_" + mode + ".csv", ...
    "HARQTraceCSV", "e2e_harq_trace_" + mode + ".csv", ...
    "SchedulerTraceCSV", "e2e_scheduler_trace_" + mode + ".csv", ...
    "DropCausesCSV", "e2e_drop_causes_" + mode + ".csv", ...
    "MAT", "e2e_probe_" + mode + ".mat");
end

function T = localAnnotateE2EDataTable(T, executionMode, dataSemantics)
if ~istable(T)
    return;
end
n = height(T);
T.ExecutionMode = repmat(string(executionMode), n, 1);
T.DataSemantics = repmat(string(dataSemantics), n, 1);
end

function T = localAnnotateE2ETraceTable(T, executionMode, traceSemantics)
if ~istable(T)
    return;
end
n = height(T);
T.ExecutionMode = repmat(string(executionMode), n, 1);
T.TraceSemantics = repmat(string(traceSemantics), n, 1);
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
schedulerCols = { ...
    'Slot','Time_s','Direction','CellID','UE','FlowID','BearerID','QFI','GrantIndex', ...
    'NumPRB','TBSBytes','CQIUsed','MCSIndex','NumLayers','TargetCodeRate', ...
    'QueueBytesBefore','QueueBytesAfter','HARQProcess','IsRetransmission','GrantReason'};
harqCols = { ...
    'Slot','Time_s','Direction','CellID','UE','FlowID','HARQProcess','GrantIndex', ...
    'RetxDepthBefore','RetxDepthAfter','AttemptCount','IsRetransmission', ...
    'Ack','CRCResult','BLER','AirMode','Note','TBSBytes'};
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
    schedulerTrace = base(:, schedulerCols);
    harqTrace = base(:, harqCols);
    return;
end
base.Direction = string(base.Direction);
base.AirMode = string(base.AirMode);
base.Note = string(base.Note);
base.GrantReason = string(base.GrantReason);
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

function [allRatio, dlRatio, ulRatio] = localPacketIntegrityDeliveryRatios(packetIntegrityTable)
allRatio = NaN;
dlRatio = NaN;
ulRatio = NaN;
if ~(istable(packetIntegrityTable) && ~isempty(packetIntegrityTable) && ...
        all(ismember(["Direction","PacketDeliveryRatio"], string(packetIntegrityTable.Properties.VariableNames))))
    return;
end

allRatio = localPacketIntegrityRatioForDirection(packetIntegrityTable, "ALL");
dlRatio = localPacketIntegrityRatioForDirection(packetIntegrityTable, "DL");
ulRatio = localPacketIntegrityRatioForDirection(packetIntegrityTable, "UL");
end

function ratio = localPacketIntegrityRatioForDirection(packetIntegrityTable, direction)
ratio = NaN;
dirMask = upper(strtrim(string(packetIntegrityTable.Direction))) == upper(string(direction));
idx = find(dirMask, 1, "first");
if isempty(idx)
    return;
end
ratio = double(packetIntegrityTable.PacketDeliveryRatio(idx));
end

function txt = localE2EAccountingMeaning()
txt = "packet_accounting_only:no_duplicate_inflation;no_out_of_order_accounting_bug;honest_deadline_miss_bookkeeping";
end

function T = localBuildE2EQoSEvaluationTable(cfg, traffic, packetIntegrityTable, ...
    offeredAll_Mbps, offeredDL_Mbps, offeredUL_Mbps, ...
    goodputAll_Mbps, goodputDL_Mbps, goodputUL_Mbps, attachOK)

dirs = ["DL"; "UL"; "ALL"];
requestedDir = upper(string(sixgr.util.structGet(traffic, "FlowDirection", ...
    sixgr.util.structGet(cfg, "traffic.flowDirection", "BIDIR"))));
trafficModel = lower(string(sixgr.util.structGet(traffic, "Model", sixgr.util.structGet(cfg, "traffic.model", "fullbuffer"))));
trafficProfile = string(sixgr.util.structGet(cfg, "traffic.profileName", trafficModel));
if strlength(trafficProfile) == 0
    trafficProfile = trafficModel;
end
qfi = double(sixgr.util.structGet(cfg, "traffic.qos.default5QI", 9));

offeredByDir = [offeredDL_Mbps; offeredUL_Mbps; offeredAll_Mbps];
goodputByDir = [goodputDL_Mbps; goodputUL_Mbps; goodputAll_Mbps];

evaluated = true(3,1);
if requestedDir == "DL"
    evaluated(2) = false;
elseif requestedDir == "UL"
    evaluated(1) = false;
end

deliveryObserved = NaN(3,1);
latencyObserved = NaN(3,1);
generatedPackets = zeros(3,1);
deliveryTarget = NaN(3,1);
deliveryPass = true(3,1);
latencyTarget = NaN(3,1);
latencyPercentile = NaN(3,1);
latencyPass = true(3,1);
throughputFracTarget = NaN(3,1);
throughputTarget = NaN(3,1);
throughputPass = true(3,1);
attachRequired = false(3,1);
attachPass = true(3,1);
qosPass = true(3,1);
notes = strings(3,1);
policySource = strings(3,1);

for i = 1:3
    dirTag = dirs(i);
    row = localDirectionRow(packetIntegrityTable, dirTag);
    if ~isempty(row)
        deliveryObserved(i) = double(row.PacketDeliveryRatio);
        latencyObserved(i) = double(row.P95Latency_ms);
        generatedPackets(i) = double(row.GeneratedPackets);
    end

    policy = localResolveE2EQoSPolicy(cfg, trafficModel, trafficProfile, qfi);
    deliveryTarget(i) = policy.DeliveryRatioTarget;
    latencyTarget(i) = policy.LatencyBudget_ms;
    latencyPercentile(i) = policy.LatencyPercentile;
    throughputFracTarget(i) = policy.ThroughputTargetFractionOfOffered;
    throughputTarget(i) = max(0, offeredByDir(i)) * max(policy.ThroughputTargetFractionOfOffered, 0);
    if isfinite(double(policy.ThroughputTarget_Mbps))
        throughputTarget(i) = max(throughputTarget(i), double(policy.ThroughputTarget_Mbps));
    end
    attachRequired(i) = logical(policy.RequireAttach);
    policySource(i) = string(policy.Source);

    if ~evaluated(i)
        notes(i) = "direction_not_requested";
        continue;
    end

    if generatedPackets(i) <= 0 && max(offeredByDir(i), 0) <= 1e-12
        attachPass(i) = ~attachRequired(i) || logical(attachOK);
        qosPass(i) = attachPass(i);
        notes(i) = "no_generated_packets";
        continue;
    end

    deliveryPass(i) = isfinite(deliveryObserved(i)) && (deliveryObserved(i) + 1e-12 >= deliveryTarget(i));
    if isnan(latencyObserved(i))
        latencyPass(i) = false;
    else
        latencyPass(i) = latencyObserved(i) <= latencyTarget(i) + 1e-9;
    end
    throughputPass(i) = (~isfinite(throughputTarget(i))) || (goodputByDir(i) + 1e-9 >= throughputTarget(i));
    attachPass(i) = ~attachRequired(i) || logical(attachOK);
    qosPass(i) = deliveryPass(i) && latencyPass(i) && throughputPass(i) && attachPass(i);

    noteParts = strings(0,1);
    if ~deliveryPass(i)
        noteParts(end+1,1) = "delivery_ratio_below_target"; %#ok<AGROW>
    end
    if ~latencyPass(i)
        noteParts(end+1,1) = "latency_budget_not_met"; %#ok<AGROW>
    end
    if ~throughputPass(i)
        noteParts(end+1,1) = "throughput_target_not_met"; %#ok<AGROW>
    end
    if ~attachPass(i)
        noteParts(end+1,1) = "attach_not_completed"; %#ok<AGROW>
    end
    if isempty(noteParts)
        noteParts(end+1,1) = "qos_targets_met"; %#ok<AGROW>
    end
    notes(i) = strjoin(noteParts, ";");
end

T = table(dirs, repmat(trafficModel, 3, 1), repmat(trafficProfile, 3, 1), repmat(qfi, 3, 1), ...
    evaluated, generatedPackets, ...
    deliveryObserved, deliveryTarget, deliveryPass, ...
    latencyObserved, latencyTarget, latencyPercentile, latencyPass, ...
    offeredByDir, goodputByDir, throughputFracTarget, throughputTarget, throughputPass, ...
    attachRequired, repmat(logical(attachOK), 3, 1), attachPass, qosPass, policySource, notes, ...
    'VariableNames', {'Direction','TrafficModel','TrafficProfile','FiveQI', ...
    'Evaluated','GeneratedPackets', ...
    'DeliveryRatioObserved','DeliveryRatioTarget','DeliveryRatioPass', ...
    'ObservedP95Latency_ms','LatencyBudgetTarget_ms','LatencyPercentile','LatencyBudgetPass', ...
    'Offered_Mbps','Goodput_Mbps','ThroughputTargetFractionOfOffered','ThroughputTarget_Mbps','ThroughputTargetPass', ...
    'AttachRequired','AttachObserved','AttachPass','QoSPass','PolicySource','Notes'});
end

function policy = localResolveE2EQoSPolicy(cfg, trafficModel, trafficProfile, qfi)
policy = struct();
policy.DeliveryRatioTarget = 0.90;
policy.LatencyBudget_ms = double(sixgr.util.structGet(cfg, "traffic.packetDelayBudget_ms", ...
    sixgr.util.structGet(cfg, "traffic.qos.latencyBudget_ms", 50)));
policy.LatencyPercentile = 95;
policy.ThroughputTargetFractionOfOffered = 0.50;
policy.ThroughputTarget_Mbps = NaN;
policy.RequireAttach = true;
policy.Source = "default";

switch lower(char(trafficModel))
    case {"xr","traffic_xr","extendedreality"}
        policy.DeliveryRatioTarget = 0.99;
        policy.ThroughputTargetFractionOfOffered = 0.85;
        policy.LatencyBudget_ms = min(policy.LatencyBudget_ms, 20);
        policy.Source = "traffic_model:" + string(trafficModel);
    case {"genai","traffic_genai","ai"}
        policy.DeliveryRatioTarget = 0.95;
        policy.ThroughputTargetFractionOfOffered = 0.70;
        policy.Source = "traffic_model:" + string(trafficModel);
    case {"mmtc","traffic_mmtc","iot"}
        policy.DeliveryRatioTarget = 0.90;
        policy.ThroughputTargetFractionOfOffered = 0.40;
        policy.Source = "traffic_model:" + string(trafficModel);
    otherwise
        policy.DeliveryRatioTarget = 0.85;
        policy.ThroughputTargetFractionOfOffered = 0.50;
        policy.Source = "traffic_model:generic";
end

if isfinite(double(qfi))
    switch round(double(qfi))
        case 84
            policy.DeliveryRatioTarget = max(policy.DeliveryRatioTarget, 0.99);
            policy.ThroughputTargetFractionOfOffered = max(policy.ThroughputTargetFractionOfOffered, 0.85);
            policy.LatencyBudget_ms = min(policy.LatencyBudget_ms, 20);
            policy.Source = localJoinNotes(policy.Source, "5qi:84");
        case 9
            policy.DeliveryRatioTarget = max(policy.DeliveryRatioTarget, 0.90);
            policy.Source = localJoinNotes(policy.Source, "5qi:9");
    end
end

policy = localOverlayQoSPolicy(policy, sixgr.util.structGet(cfg, "traffic.qos.acceptance", struct()), "traffic.qos.acceptance");
if strlength(string(trafficProfile)) > 0
    policy = localOverlayQoSPolicy(policy, ...
        sixgr.util.structGet(cfg, "traffic.qos.acceptance.byProfile." + string(trafficProfile), struct()), ...
        "traffic.qos.acceptance.byProfile." + string(trafficProfile));
end
policy = localOverlayQoSPolicy(policy, ...
    sixgr.util.structGet(cfg, "traffic.qos.acceptance.byTrafficModel." + string(trafficModel), struct()), ...
    "traffic.qos.acceptance.byTrafficModel." + string(trafficModel));
policy = localOverlayQoSPolicy(policy, ...
    sixgr.util.structGet(cfg, "traffic.qos.acceptance.by5QI.qi" + string(round(double(qfi))), struct()), ...
    "traffic.qos.acceptance.by5QI.qi" + string(round(double(qfi))));

if ~(isfinite(double(policy.LatencyBudget_ms)) && double(policy.LatencyBudget_ms) > 0)
    policy.LatencyBudget_ms = 50;
end
policy.DeliveryRatioTarget = min(max(double(policy.DeliveryRatioTarget), 0), 1);
policy.ThroughputTargetFractionOfOffered = max(double(policy.ThroughputTargetFractionOfOffered), 0);
policy.LatencyPercentile = min(max(double(policy.LatencyPercentile), 0), 100);
policy.RequireAttach = logical(policy.RequireAttach);
end

function policy = localOverlayQoSPolicy(policy, rawOverride, sourceLabel)
if ~(isstruct(rawOverride) && isscalar(rawOverride))
    return;
end
if isfield(rawOverride, "deliveryRatioTarget")
    policy.DeliveryRatioTarget = double(rawOverride.deliveryRatioTarget);
end
if isfield(rawOverride, "latencyBudget_ms")
    policy.LatencyBudget_ms = double(rawOverride.latencyBudget_ms);
elseif isfield(rawOverride, "packetDelayBudget_ms")
    policy.LatencyBudget_ms = double(rawOverride.packetDelayBudget_ms);
end
if isfield(rawOverride, "latencyPercentile")
    policy.LatencyPercentile = double(rawOverride.latencyPercentile);
end
if isfield(rawOverride, "throughputTargetFractionOfOffered")
    policy.ThroughputTargetFractionOfOffered = double(rawOverride.throughputTargetFractionOfOffered);
elseif isfield(rawOverride, "throughputFractionOfOffered")
    policy.ThroughputTargetFractionOfOffered = double(rawOverride.throughputFractionOfOffered);
end
if isfield(rawOverride, "throughputTarget_Mbps")
    policy.ThroughputTarget_Mbps = double(rawOverride.throughputTarget_Mbps);
end
if isfield(rawOverride, "requireAttach")
    policy.RequireAttach = logical(rawOverride.requireAttach);
elseif isfield(rawOverride, "attachRequired")
    policy.RequireAttach = logical(rawOverride.attachRequired);
end
policy.Source = string(sourceLabel);
end

function summaryTable = localAppendE2EQoSSummary(summaryTable, qosEvaluationTable, qosArtifact)
if ~(istable(summaryTable) && height(summaryTable) == 1)
    return;
end

summaryTable.QoSPass = true(height(summaryTable), 1);
summaryTable.DeliveryRatioTarget = NaN(height(summaryTable), 1);
summaryTable.DeliveryRatioPass = true(height(summaryTable), 1);
summaryTable.LatencyBudgetTarget_ms = NaN(height(summaryTable), 1);
summaryTable.ObservedP95Latency_ms = NaN(height(summaryTable), 1);
summaryTable.LatencyBudgetPass = true(height(summaryTable), 1);
summaryTable.ThroughputTargetFractionOfOffered = NaN(height(summaryTable), 1);
summaryTable.ThroughputTarget_Mbps = NaN(height(summaryTable), 1);
summaryTable.ThroughputTargetPass = true(height(summaryTable), 1);
summaryTable.AttachRequired = false(height(summaryTable), 1);
summaryTable.AttachPass = true(height(summaryTable), 1);
summaryTable.QoSFailureCount = zeros(height(summaryTable), 1);
summaryTable.QoSPolicySource = repmat("", height(summaryTable), 1);
summaryTable.QoSEvaluationArtifact = repmat(string(qosArtifact), height(summaryTable), 1);

if ~(istable(qosEvaluationTable) && ~isempty(qosEvaluationTable))
    return;
end

evalMask = logical(qosEvaluationTable.Evaluated);
allRow = qosEvaluationTable(upper(string(qosEvaluationTable.Direction)) == "ALL", :);
if isempty(allRow)
    allRow = qosEvaluationTable(1,:);
end

summaryTable.QoSPass(:) = all(logical(qosEvaluationTable.QoSPass(evalMask)));
summaryTable.DeliveryRatioTarget(:) = double(allRow.DeliveryRatioTarget(1));
summaryTable.DeliveryRatioPass(:) = logical(allRow.DeliveryRatioPass(1));
summaryTable.LatencyBudgetTarget_ms(:) = double(allRow.LatencyBudgetTarget_ms(1));
summaryTable.ObservedP95Latency_ms(:) = double(allRow.ObservedP95Latency_ms(1));
summaryTable.LatencyBudgetPass(:) = logical(allRow.LatencyBudgetPass(1));
summaryTable.ThroughputTargetFractionOfOffered(:) = double(allRow.ThroughputTargetFractionOfOffered(1));
summaryTable.ThroughputTarget_Mbps(:) = double(allRow.ThroughputTarget_Mbps(1));
summaryTable.ThroughputTargetPass(:) = logical(allRow.ThroughputTargetPass(1));
summaryTable.AttachRequired(:) = logical(allRow.AttachRequired(1));
summaryTable.AttachPass(:) = logical(allRow.AttachPass(1));
summaryTable.QoSFailureCount(:) = sum(evalMask & ~logical(qosEvaluationTable.QoSPass));
summaryTable.QoSPolicySource(:) = string(allRow.PolicySource(1));
end

function summary = localAppendE2EReportSummary(summary, e2e)
if ~(isstruct(summary) && isstruct(e2e))
    return;
end
T = sixgr.util.structGet(e2e, "SummaryTable", table());
if ~(istable(T) && height(T) >= 1)
    return;
end
S = T(1,:);
summary.E2EPacketAccountingPassRate_pct = double(localScalarFromTableRow(S, "PacketAccountingPassRate_pct", ...
    localScalarFromTableRow(S, "SemanticCheckPassRate_pct", NaN)));
summary.E2EPacketAccountingMeaning = string(localStringFromTableRow(S, "PacketAccountingMeaning", localE2EAccountingMeaning()));
summary.E2EQoSPass = logical(localScalarFromTableRow(S, "QoSPass", true));
summary.E2EDeliveryRatio = double(localScalarFromTableRow(S, "DeliveryRatio", NaN));
summary.E2EDeliveryRatioTarget = double(localScalarFromTableRow(S, "DeliveryRatioTarget", NaN));
summary.E2EDeliveryRatioPass = logical(localScalarFromTableRow(S, "DeliveryRatioPass", true));
summary.E2EObservedP95Latency_ms = double(localScalarFromTableRow(S, "ObservedP95Latency_ms", NaN));
summary.E2ELatencyBudgetTarget_ms = double(localScalarFromTableRow(S, "LatencyBudgetTarget_ms", NaN));
summary.E2ELatencyBudgetPass = logical(localScalarFromTableRow(S, "LatencyBudgetPass", true));
summary.E2EGoodput_Mbps = double(localScalarFromTableRow(S, "Goodput_Mbps", NaN));
summary.E2EThroughputTarget_Mbps = double(localScalarFromTableRow(S, "ThroughputTarget_Mbps", NaN));
summary.E2EThroughputTargetPass = logical(localScalarFromTableRow(S, "ThroughputTargetPass", true));
summary.E2EAttachPass = logical(localScalarFromTableRow(S, "AttachPass", true));
summary.E2EQoSFailureCount = double(localScalarFromTableRow(S, "QoSFailureCount", 0));
summary.E2EQoSPolicySource = string(localStringFromTableRow(S, "QoSPolicySource", ""));
summary.E2ESystemCoupled = logical(localScalarFromTableRow(S, "E2ESystemCoupled", false));
summary.E2ECouplingMode = string(localStringFromTableRow(S, "E2ECouplingMode", ""));
summary.E2ECouplingNotes = string(localStringFromTableRow(S, "E2ECouplingNotes", ""));
summary.E2EAppSDUChunkBytes = double(localScalarFromTableRow(S, "AppSDUChunkBytes", NaN));
summary.E2EAppSDUChunkSource = string(localStringFromTableRow(S, "AppSDUChunkSource", ""));
end

function info = localResolveE2EAppChunk(cfgE, traffic)
info = struct();
info.Bytes = NaN;
info.Source = "";

cfgChunk = double(sixgr.util.structGet(cfgE, "traffic.rlcSduChunk_bytes", NaN));
if isfinite(cfgChunk) && cfgChunk > 0
    info.Bytes = max(64, round(cfgChunk));
    info.Source = "traffic.rlcSduChunk_bytes";
    return;
end

flowTable = sixgr.util.structGet(traffic, "FlowTable", table());
if istable(flowTable) && ~isempty(flowTable) && ismember("PacketSize_bytes", string(flowTable.Properties.VariableNames))
    pktVals = double(flowTable.PacketSize_bytes);
    pktVals = pktVals(isfinite(pktVals) & pktVals > 0);
    if ~isempty(pktVals)
        info.Bytes = max(64, round(median(pktVals, "omitnan")));
        info.Source = "traffic_flow_packet_size_bytes";
        return;
    end
end

pktChunk = double(sixgr.util.structGet(cfgE, "traffic.packetSize_bytes", NaN));
if isfinite(pktChunk) && pktChunk > 0
    info.Bytes = max(64, round(pktChunk));
    info.Source = "traffic_packet_size_bytes";
    return;
end

info.Bytes = 32768;
info.Source = "legacy_default_32768";
end

function [chunkBytes, sourceOut] = localCapE2EAppChunkForCoupledTruth(chunkBytesIn, sourceIn, coupledTruth)
chunkBytes = max(64, round(double(chunkBytesIn)));
sourceOut = string(sourceIn);
if ~logical(sixgr.util.structGet(coupledTruth, "Enabled", false))
    return;
end
if sourceOut == "traffic.rlcSduChunk_bytes" || ...
        sourceOut == "traffic_packet_size_bytes" || ...
        sourceOut == "traffic_flow_packet_size_bytes"
    return;
end

res = sixgr.util.structGet(coupledTruth, "Result", struct());
details = sixgr.util.structGet(res, "Details", struct());
grantTable = sixgr.util.structGet(details, "SchedulerGrants", table());
if ~(istable(grantTable) && ~isempty(grantTable) && ismember("TBSBits", string(grantTable.Properties.VariableNames)))
    return;
end

tbsBytes = ceil(double(grantTable.TBSBits) / 8);
tbsBytes = tbsBytes(isfinite(tbsBytes) & tbsBytes >= 64);
if isempty(tbsBytes)
    return;
end

capBytes = floor(prctile(tbsBytes, 25));
capBytes = max(64, round(double(capBytes)));
if capBytes < chunkBytes
    chunkBytes = capBytes;
    if strlength(sourceOut) > 0
        sourceOut = sourceOut + "|coupled_truth_grant_tbs_p25_cap";
    else
        sourceOut = "coupled_truth_grant_tbs_p25_cap";
    end
end
end

function v = localScalarFromTableRow(T, fieldName, defaultValue)
v = defaultValue;
if ~(istable(T) && height(T) >= 1 && ismember(string(fieldName), string(T.Properties.VariableNames)))
    return;
end
raw = T.(char(fieldName));
if isempty(raw)
    return;
end
v = raw(1);
end

function v = localStringFromTableRow(T, fieldName, defaultValue)
v = string(defaultValue);
if ~(istable(T) && height(T) >= 1 && ismember(string(fieldName), string(T.Properties.VariableNames)))
    return;
end
raw = string(T.(char(fieldName)));
if isempty(raw)
    return;
end
v = raw(1);
end

function row = localDirectionRow(T, dirTag)
row = table();
if ~(istable(T) && ~isempty(T) && ismember("Direction", string(T.Properties.VariableNames)))
    return;
end
idx = find(upper(string(T.Direction)) == upper(string(dirTag)), 1, "first");
if ~isempty(idx)
    row = T(idx,:);
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
 [q, nextId] = localEnqueueVirtualPacketDirect(q, nextId, bytes, slotIdx, flowId, bearerId, qfi);
end

function [q, nextId] = localEnqueueVirtualPacketDirect(q, nextId, bytes, slotIdx, flowId, bearerId, qfi)
if nargin < 1 || isempty(q)
    q = localInitVirtualQueue(256);
else
    q = localEnsureVirtualQueue(q);
end
nextId = max(0, round(double(nextId))) + 1;
bytes = max(1, round(double(bytes)));
slotIdx = max(1, round(double(slotIdx)));
flowId = double(flowId);
bearerId = double(bearerId);
qfi = double(qfi);

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

function [q, sem] = localConsumeVirtualPackets(q, deliveredBytes, slotIdx, slotDur_s, pdb_ms, lastDeliveredId, varargin)
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
 [q, sem] = localConsumeVirtualPacketsDirect(q, deliveredBytes, slotIdx, slotDur_s, pdb_ms, lastDeliveredId, direction, ueId);
end

function [q, sem] = localConsumeVirtualPacketsDirect(q, deliveredBytes, slotIdx, slotDur_s, pdb_ms, lastDeliveredId, direction, ueId)
sem = struct();
sem.DeliveredPackets = 0;
sem.DeadlineMissPackets = 0;
sem.DuplicatePackets = 0;
sem.OutOfOrderPackets = 0;
sem.LastDeliveredId = double(lastDeliveredId);
sem.LatencyMs = zeros(0,1);
sem.PacketRows = repmat(localPacketTraceRowTemplate(), 0, 1);

if isempty(q) || deliveredBytes <= 0
    return;
end
q = localEnsureVirtualQueue(q);
if q.Count <= 0
    return;
end

rem = max(0, round(double(deliveredBytes)));
slotIdx = max(1, round(double(slotIdx)));
pdb_ms = max(double(pdb_ms), eps);
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

    generationTime_s = (double(q.GenSlot(idx)) - 1) * double(slotDur_s);
    deliveryTime_s = double(slotIdx) * double(slotDur_s);
    latMs = max(0, 1e3 * (deliveryTime_s - generationTime_s));
    deadlineMiss = (latMs > pdb_ms + 1e-9);
    if deadlineMiss
        sem.DeadlineMissPackets = sem.DeadlineMissPackets + 1;
    end
    nLat = nLat + 1;
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
    row.GenerationTime_s = generationTime_s;
    row.GrantSlot = double(q.FirstGrantSlot(idx));
    row.HARQProcess = double(q.LastHarqProcess(idx));
    row.Attempts = double(q.Attempts(idx));
    row.CRCResult = logical(q.LastCRC(idx));
    row.DeliverySlot = double(slotIdx);
    row.DeliveryTime_s = deliveryTime_s;
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

function [q, rows] = localFinalizeVirtualQueueDrops(q, finalSlot, slotDur_s, pdb_ms, lastDeliveredId, direction, ueId, dropCause)
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
pdb_ms = max(double(pdb_ms), eps);
idxList = localRingLinearIndices(q.Head, q.Count, q.Capacity);
rows = repmat(localPacketTraceRowTemplate(), numel(idxList), 1);
for i = 1:numel(idxList)
    idx = idxList(i);
    pktId = double(q.ID(idx));
    generationTime_s = (double(q.GenSlot(idx)) - 1) * double(slotDur_s);
    observedTime_s = double(finalSlot) * double(slotDur_s);
    latMs = max(0, 1e3 * (observedTime_s - generationTime_s));
    deadlineMiss = latMs > (pdb_ms + 1e-9);
    row = localPacketTraceRowTemplate();
    row.Direction = string(direction);
    row.UE = double(ueId);
    row.PacketID = pktId;
    row.FlowID = double(q.FlowID(idx));
    row.BearerID = double(q.BearerID(idx));
    row.QFI = double(q.QFI(idx));
    row.PacketBytes = double(q.InitialBytes(idx));
    row.GenerationSlot = double(q.GenSlot(idx));
    row.GenerationTime_s = generationTime_s;
    row.GrantSlot = double(q.FirstGrantSlot(idx));
    row.HARQProcess = double(q.LastHarqProcess(idx));
    row.Attempts = double(q.Attempts(idx));
    row.CRCResult = logical(q.LastCRC(idx));
    row.DeliverySlot = NaN;
    row.DeliveryTime_s = NaN;
    row.Latency_ms = latMs;
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
idx = head + (0:count-1);
idx = mod(idx - 1, capacity) + 1;
idx = idx(:);
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

function [T, passRate_pct] = localBuildE2EPacketIntegrityTableFromTrace(packetTraceTable, pdb_ms)
dirs = ["DL";"UL";"ALL"];
generated = zeros(3,1);
delivered = zeros(3,1);
undelivered = zeros(3,1);
pdr = zeros(3,1);
meanLat = NaN(3,1);
p95Lat = NaN(3,1);
missN = zeros(3,1);
missRate = zeros(3,1);
dupN = zeros(3,1);
reordN = zeros(3,1);
deadlinePDB = repmat(double(pdb_ms), 3, 1);
duplicateInflationFreePass = true(3,1);
orderingIntegrityPass = true(3,1);
deadlineAccountingPass = true(3,1);
accountingIntegrityPass = true(3,1);
semanticPass = true(3,1);
semanticNotes = repmat("OK", 3, 1);

Traw = packetTraceTable;
if isempty(Traw)
    Traw = localPacketTraceRowsToTable(repmat(localPacketTraceRowTemplate(), 0, 1));
end
if ~ismember("DropCause", string(Traw.Properties.VariableNames))
    Traw.DropCause = strings(height(Traw), 1);
end
if ~ismember("Latency_ms", string(Traw.Properties.VariableNames))
    Traw.Latency_ms = NaN(height(Traw), 1);
end
if ~ismember("DeadlineMiss", string(Traw.Properties.VariableNames))
    Traw.DeadlineMiss = false(height(Traw), 1);
end
if ~ismember("DuplicateFlag", string(Traw.Properties.VariableNames))
    Traw.DuplicateFlag = false(height(Traw), 1);
end
if ~ismember("ReorderFlag", string(Traw.Properties.VariableNames))
    Traw.ReorderFlag = false(height(Traw), 1);
end

dirCol = upper(string(Traw.Direction));
dropCause = string(Traw.DropCause);
isDelivered = (strlength(dropCause) == 0);
isMiss = logical(Traw.DeadlineMiss);
isDup = logical(Traw.DuplicateFlag);
isReord = logical(Traw.ReorderFlag);
latCol = double(Traw.Latency_ms);

for i = 1:3
    if dirs(i) == "ALL"
        idx = true(height(Traw), 1);
    else
        idx = (dirCol == dirs(i));
    end
    idxDel = idx & isDelivered;
    generated(i) = sum(idx);
    delivered(i) = sum(idxDel);
    undelivered(i) = sum(idx & ~isDelivered);
    pdr(i) = delivered(i) / max(generated(i), 1);
    lat = latCol(idxDel);
    lat = lat(isfinite(lat));
    if ~isempty(lat)
        meanLat(i) = mean(lat, "omitnan");
        p95Lat(i) = localPercentile(lat, 95);
    end
    missN(i) = sum(idx & isMiss);
    missRate(i) = missN(i) / max(generated(i), 1);
    dupN(i) = sum(idx & isDup);
    reordN(i) = sum(idx & isReord);

    lateWithoutMiss = any(idx & isfinite(latCol) & (latCol > double(pdb_ms) + 1e-9) & ~isMiss);
    missWithoutLate = any(idx & isfinite(latCol) & (latCol <= double(pdb_ms) + 1e-9) & isMiss);
    duplicateInflationFreePass(i) = (delivered(i) <= generated(i)) && (dupN(i) == 0);
    orderingIntegrityPass(i) = (reordN(i) == 0);
    deadlineAccountingPass(i) = ~(lateWithoutMiss || missWithoutLate);
    accountingIntegrityPass(i) = duplicateInflationFreePass(i) && orderingIntegrityPass(i) && deadlineAccountingPass(i);
    semanticPass(i) = accountingIntegrityPass(i);
    if ~semanticPass(i)
        msg = strings(0,1);
        if ~duplicateInflationFreePass(i)
            if delivered(i) > generated(i)
                msg(end+1,1) = "delivered>generated"; %#ok<AGROW>
            end
            if dupN(i) > 0
                msg(end+1,1) = "duplicate_packets"; %#ok<AGROW>
            end
        end
        if ~orderingIntegrityPass(i)
            msg(end+1,1) = "reordered_packets"; %#ok<AGROW>
        end
        if ~deadlineAccountingPass(i)
            if lateWithoutMiss
                msg(end+1,1) = "late_packets_without_deadline_miss"; %#ok<AGROW>
            end
            if missWithoutLate
                msg(end+1,1) = "deadline_miss_flag_without_late_packet"; %#ok<AGROW>
            end
        end
        if isempty(msg)
            msg(end+1,1) = "inconsistent_packet_integrity"; %#ok<AGROW>
        end
        semanticNotes(i) = strjoin(msg, ";");
    else
        semanticNotes(i) = "packet_accounting_integrity_ok";
    end
end

T = table(dirs, generated, delivered, undelivered, pdr, meanLat, p95Lat, ...
    missN, missRate, dupN, reordN, deadlinePDB, ...
    duplicateInflationFreePass, orderingIntegrityPass, deadlineAccountingPass, accountingIntegrityPass, ...
    semanticPass, repmat(localE2EAccountingMeaning(), 3, 1), semanticNotes, ...
    'VariableNames', {'Direction','GeneratedPackets','DeliveredPackets','UndeliveredPackets', ...
    'PacketDeliveryRatio','MeanLatency_ms','P95Latency_ms','DeadlineMissPackets', ...
    'DeadlineMissRate','DuplicatePackets','OutOfOrderPackets','PacketDelayBudget_ms', ...
    'DuplicateInflationFreePass','OrderingIntegrityPass','DeadlineAccountingPass','AccountingIntegrityPass', ...
    'SemanticPass','AccountingMeaning','Notes'});
passRate_pct = 100 * mean(double(semanticPass));
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

duplicateInflationFreePass = (delivered <= generated) & (dupN == 0);
orderingIntegrityPass = (reordN == 0);
deadlineAccountingPass = true(size(dirs));
accountingIntegrityPass = duplicateInflationFreePass & orderingIntegrityPass & deadlineAccountingPass;
semanticPass = accountingIntegrityPass;
semanticNotes = repmat("OK", 3, 1);
for i = 1:3
    if ~semanticPass(i)
        msg = strings(0,1);
        if ~duplicateInflationFreePass(i)
            if delivered(i) > generated(i)
                msg(end+1,1) = "delivered>generated"; %#ok<AGROW>
            end
            if dupN(i) > 0
                msg(end+1,1) = "duplicate_packets"; %#ok<AGROW>
            end
        end
        if ~orderingIntegrityPass(i)
            msg(end+1,1) = "reordered_packets"; %#ok<AGROW>
        end
        semanticNotes(i) = strjoin(msg, ";");
    else
        semanticNotes(i) = "packet_accounting_integrity_ok";
    end
end

T = table(dirs, generated, delivered, undelivered, pdr, meanLat, p95Lat, ...
    missN, missRate, dupN, reordN, deadlinePDB, ...
    duplicateInflationFreePass, orderingIntegrityPass, deadlineAccountingPass, accountingIntegrityPass, ...
    semanticPass, repmat(localE2EAccountingMeaning(), 3, 1), semanticNotes, ...
    'VariableNames', {'Direction','GeneratedPackets','DeliveredPackets','UndeliveredPackets', ...
    'PacketDeliveryRatio','MeanLatency_ms','P95Latency_ms','DeadlineMissPackets', ...
    'DeadlineMissRate','DuplicatePackets','OutOfOrderPackets','PacketDelayBudget_ms', ...
    'DuplicateInflationFreePass','OrderingIntegrityPass','DeadlineAccountingPass','AccountingIntegrityPass', ...
    'SemanticPass','AccountingMeaning','Notes'});
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

function ctx = localInitE2ESystemCouplingContext()
ctx = struct();
ctx.Enabled = false;
ctx.CouplingMode = "standalone_scheduler_replay";
ctx.Notes = "Truth E2E uses standalone schedulers/queues and is not coupled to SystemLevelRunner multi-cell state.";
ctx.Source = "waveform_grant_replay";
ctx.ExecutionBackend = "WAVEFORM_GRANT_REPLAY";
ctx.PHYMode = "CRC_WAVEFORM_REPLAY";
ctx.Result = struct();
ctx.GrantsDLBySlot = {};
ctx.GrantsULBySlot = {};
end

function ctx = localRunE2ESystemCoupling(cfgE, runFolder, traffic, nSlots, slotDur_s, nUE, nRB, attachGateSlots, opt, flowDirCfg)
ctx = localInitE2ESystemCouplingContext();

offeredDL = localExpandTrafficBits(sixgr.util.structGet(traffic, "OfferedBitsDL", zeros(nSlots, nUE)), nSlots, nUE, "E2ECoupledOfferedBitsDL");
offeredUL = localExpandTrafficBits(sixgr.util.structGet(traffic, "OfferedBitsUL", zeros(nSlots, nUE)), nSlots, nUE, "E2ECoupledOfferedBitsUL");
offeredDL = max(0, round(double(offeredDL)));
offeredUL = max(0, round(double(offeredUL)));
if upper(string(flowDirCfg)) == "DL"
    offeredUL(:) = 0;
elseif upper(string(flowDirCfg)) == "UL"
    offeredDL(:) = 0;
end
if attachGateSlots > 0
    offeredDL(1:attachGateSlots, :) = 0;
    offeredUL(1:attachGateSlots, :) = 0;
end

cfgS = cfgE;
cfgS.run.mode = "system";
cfgS.run.shortRun = false;
cfgS.outputs.saveCSV = false;
cfgS.outputs.saveMAT = false;
cfgS.outputs.saveFigures = false;
cfgS.outputs.saveFIG = false;
cfgS.outputs.detailedSystemTrace = false;
cfgS.system.phyBackend = "waveform";
cfgS.scenario.ue.nUE = nUE;
cfgS.scenario.nUE = nUE;

tmpRun = tempname;
sixgr.util.ensureDir(tmpRun);
cleanupTmp = onCleanup(@() localSafeRemoveDir(tmpRun)); %#ok<NASGU>

ctxSys = sixgr.core.SimContext(cfgS, "RunFolder", tmpRun);
ctxSys.Logger.EchoToConsole = false;

params = struct();
params.NumTTI = nSlots;
params.TTI_s = slotDur_s;
params.SimDuration_s = nSlots * slotDur_s;
params.ForceLong = true;
params.DetailedTrace = false;
params.OfferedBitsDL = offeredDL;
params.OfferedBitsUL = offeredUL;
params.OfferedBits = offeredDL + offeredUL;
params.TrafficModel = string(sixgr.util.structGet(traffic, "Model", sixgr.util.structGet(cfgS, "traffic.model", "custom")));
params.TrafficTransport = string(sixgr.util.structGet(traffic, "Transport", sixgr.util.structGet(cfgS, "traffic.transport", "UDP")));
params.TrafficFlowDirection = string(sixgr.util.structGet(traffic, "FlowDirection", sixgr.util.structGet(cfgS, "traffic.flowDirection", "BIDIR")));
params.PacketDelayBudget_ms = double(sixgr.util.structGet(traffic, "PacketDelayBudget_ms", sixgr.util.structGet(cfgS, "traffic.packetDelayBudget_ms", 50)));
params.PHYBackend = "waveform";
params.NoProxyTruthContract = localNoProxyTruthContractEnabled(cfgS, opt);
params.WaveformCompactPHYIO = logical(sixgr.util.structGet(opt, "E2ETruthCompactPHYIO", true));
params.WaveformFastAWGNPath = logical(sixgr.util.structGet(opt, "E2ETruthFastAWGNPath", false));
params.WaveformAdaptiveLDPC = logical(sixgr.util.structGet(opt, "E2ETruthAdaptiveLDPC", true));
params.WaveformLDPCMaxIterations = double(sixgr.util.structGet(opt, "E2ETruthLDPCMaxIterations", 0));
params.WaveformUseGPU = logical(sixgr.util.structGet(opt, "E2ETruthUseGPU", false));

res = sixgr.system.SystemLevelRunner.run(ctxSys, params);
if ~logical(sixgr.util.structGet(res, "Ok", false))
    errs = string(sixgr.util.structGet(res, "Errors", strings(0,1)));
    if isempty(errs)
        errs = "unknown_system_coupling_failure";
    end
    error("sixgr:e2e:SystemCouplingFailed", ...
        "Truth E2E system coupling failed before packet replay: %s", strjoin(cellstr(errs), " | "));
end

details = sixgr.util.structGet(res, "Details", struct());
waveformBacked = logical(sixgr.util.structGet(details, "WaveformBacked", false));
if ~waveformBacked
    error("sixgr:e2e:SystemCouplingBackend", ...
        "Truth E2E system coupling requires a waveform-backed SystemLevelRunner backend.");
end

grantTable = sixgr.util.structGet(details, "SchedulerGrants", table());
[grantsDLBySlot, grantsULBySlot] = localBuildCoupledE2EGrantSlots(grantTable, nSlots, nRB);

ctx.Enabled = true;
ctx.CouplingMode = "system_waveform_grant_trace";
ctx.Notes = "Truth E2E consumed actual SystemLevelRunner waveform grant, HARQ, and scheduler outcomes.";
ctx.Source = "system_waveform_grant_trace";
ctx.ExecutionBackend = string(sixgr.util.structGet(details, "ExecutionBackend", "WAVEFORM_SYSTEM_PHY"));
ctx.PHYMode = string(sixgr.util.structGet(details, "PHYMode", "GRANT_CRC_WAVEFORM_REPLAY_EXPERIMENTAL"));
ctx.Result = res;
ctx.GrantsDLBySlot = grantsDLBySlot;
ctx.GrantsULBySlot = grantsULBySlot;
end

function [grantsDLBySlot, grantsULBySlot] = localBuildCoupledE2EGrantSlots(grantTable, nSlots, nRB)
grantsDLBySlot = repmat({struct([])}, nSlots, 1);
grantsULBySlot = repmat({struct([])}, nSlots, 1);
if ~(istable(grantTable) && ~isempty(grantTable))
    return;
end

for i = 1:height(grantTable)
    row = grantTable(i,:);
    slotIdx = max(1, min(nSlots, round(double(row.TTI(1)))));
    g = struct();
    g.RNTI = double(row.UE(1));
    g.CellID = double(row.CellID(1));
    g.NPRB = max(1, round(double(row.PRBCount(1))));
    g.PRBStart = double(row.PRBStart(1));
    if isfinite(g.PRBStart)
        g.PRBSet = g.PRBStart + (0:(g.NPRB-1));
    else
        g.PRBSet = [];
    end
    g.SymbolAllocation = [double(row.SymbolStart(1)) double(row.NumSymbols(1))];
    g.TBSBits = double(row.TBSBits(1));
    g.TBSBytes = ceil(max(g.TBSBits, 0) / 8);
    g.CQIUsed = double(row.CQIUsed(1));
    g.MCSIndex = double(row.MCSIndex(1));
    g.NumLayers = max(1, round(double(row.NumLayers(1))));
    g.TargetCodeRate = double(row.TargetCodeRate(1));
    g.HeadOfLineDelay_ms = double(row.HeadOfLineDelay_ms(1));
    g.BufferBytesBefore = double(row.BufferBytesBefore(1));
    g.BufferBytesAfter = double(row.BufferBytesAfter(1));
    g.GrantReason = string(row.GrantReason(1));
    g.SearchSpaceID = double(row.SearchSpaceID(1));
    g.CORESETID = double(row.CORESETID(1));
    g.BWPId = double(row.BWPId(1));
    g.DAI = double(row.DAI(1));
    g.K1 = double(row.K1(1));
    g.K2 = double(row.K2(1));
    g.HARQ = struct( ...
        "HarqID", double(row.HarqID(1)), ...
        "RV", double(row.RV(1)), ...
        "NDI", double(row.NDI(1)), ...
        "IsRetransmission", logical(row.IsRetransmission(1)));
    g.CoupledAck = logical(row.Ack(1));
    g.CoupledBLER = double(row.BLER(1));
    g.CoupledSINR_dB = double(row.SINR_dB(1));
    g.CoupledSource = "system_waveform_grant_trace";

    dirTag = upper(string(row.Direction(1)));
    if dirTag == "DL"
        if isempty(grantsDLBySlot{slotIdx})
            grantsDLBySlot{slotIdx} = g;
        else
            grantsDLBySlot{slotIdx}(end+1,1) = g; %#ok<AGROW>
        end
    elseif dirTag == "UL"
        if isempty(grantsULBySlot{slotIdx})
            grantsULBySlot{slotIdx} = g;
        else
            grantsULBySlot{slotIdx}(end+1,1) = g; %#ok<AGROW>
        end
    end
end
end

function airRes = localCoupledGrantAirResult(grant, coupledTruth)
airRes = struct();
airRes.Ok = logical(sixgr.util.structGet(grant, "CoupledAck", false));
bler = double(sixgr.util.structGet(grant, "CoupledBLER", NaN));
if ~isfinite(bler)
    bler = 1.0 - double(airRes.Ok);
end
airRes.BLER = bler;
airRes.Mode = "truth";
airRes.Source = string(sixgr.util.structGet(coupledTruth, "Source", "system_waveform_grant_trace"));
airRes.ExecutionBackend = string(sixgr.util.structGet(coupledTruth, "ExecutionBackend", "WAVEFORM_SYSTEM_PHY"));
airRes.PHYMode = string(sixgr.util.structGet(coupledTruth, "PHYMode", "GRANT_CRC_WAVEFORM_REPLAY_EXPERIMENTAL"));
airRes.Notes = "system_coupled_grant_trace";
end

function localSafeRemoveDir(pathIn)
if nargin < 1 || strlength(string(pathIn)) == 0
    return;
end
try
    if exist(pathIn, "dir") == 7
        rmdir(pathIn, "s");
    end
catch
end
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

mode = lower(char(string(sixgr.util.structGet(airModel, "Mode", "truth"))));
if strcmp(mode, "truth")
    airRes = localTruthPhyReplay(cfgE, direction, grant, macPduBytes, snr_dB, airModel);
    return;
end

error("sixgr:e2e:ProxyAirModelRemoved", ...
    "E2E air model '%s' is not reachable in the waveform-truth-only runtime. Use E2EAirModel='truth'.", mode);
end

function airRes = localTruthPhyReplay(cfgE, direction, grant, macPduBytes, snr_dB, airModel)
if nargin < 6
    airModel = struct();
end
tbBitsIn = sixgr.l2.mac.TBAssembler.bytesToBits(uint8(macPduBytes(:)));
if isempty(tbBitsIn)
    airRes = struct("Ok", false, "BLER", 1.0, "Mode", "truth", ...
        "Source", "waveform_grant_replay", "Notes", "empty_tb");
    return;
end

strictMode = logical(sixgr.util.structGet(cfgE, "run.strictMode", false));
compactPHY = logical(sixgr.util.structGet(airModel, "TruthCompactPHYIO", true));
fastAWGNPath = logical(sixgr.util.structGet(airModel, "TruthFastAWGNPath", false));
adaptiveLDPC = logical(sixgr.util.structGet(airModel, "TruthAdaptiveLDPC", true));
maxIter = double(sixgr.util.structGet(airModel, "TruthLDPCMaxIterations", 0));
useGPU = logical(sixgr.util.structGet(airModel, "TruthUseGPU", false));
dir = upper(string(direction));
try
    tmpl = localTruthTemplateForGrant(cfgE, dir, grant);
    tbBits = localResizeBitsForTB(tbBitsIn, double(tmpl.TransportBlockSize));
    grantReplay = grant;
    grantReplay.TBSBits = double(tmpl.TransportBlockSize);
    grantReplay.TBSBytes = ceil(double(tmpl.TransportBlockSize) / 8);
    replay = sixgr.system.waveform.replayGrant(cfgE, direction, grantReplay, tbBits, snr_dB, ...
        "InputFormat", "bits", ...
        "StrictMode", strictMode, ...
        "CompactPHYIO", compactPHY, ...
        "FastAWGNPath", fastAWGNPath, ...
        "AdaptiveLDPC", adaptiveLDPC, ...
        "LDPCMaxIterations", maxIter, ...
        "UseGPU", useGPU);
    airRes = replay;
    airRes.Mode = "truth";
    airRes.Source = "waveform_grant_replay";
catch ME
    if strictMode
        rethrow(ME);
    end
    airRes = struct("Ok", false, "BLER", 1.0, "Mode", "truth", ...
        "Source", "waveform_grant_replay", ...
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

function model = localBuildE2EAirModel(cfg, campaignRunFolder, opt, e2eAirLUT)
mode = lower(char(string(sixgr.util.structGet(opt, "E2EAirModel", "truth"))));
strictValidation = logical(sixgr.util.structGet(opt, "E2EStrictValidation", false)) || ...
    logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false));
if logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false)) && ~strcmp(mode, "truth")
    error("sixgr:e2e:NoProxyTruthAirModel", ...
        "No-proxy truth contract requires E2EAirModel='truth'.");
end
if strictValidation && strcmp(mode, "logistic")
    error("sixgr:e2e:StrictLogisticForbidden", "Strict validation forbids logistic air model fallback. Use E2EAirModel='truth'.");
end

model = struct();
model.Mode = string(mode);
model.Source = "default";
model.DL = struct();
model.UL = struct();

if strcmp(mode, "truth")
    model.Source = "waveform_grant_replay";
    model.TruthFastAWGNPath = logical(sixgr.util.structGet(opt, "E2ETruthFastAWGNPath", false));
    model.TruthCompactPHYIO = logical(sixgr.util.structGet(opt, "E2ETruthCompactPHYIO", true));
    model.TruthAdaptiveLDPC = logical(sixgr.util.structGet(opt, "E2ETruthAdaptiveLDPC", true));
    model.TruthLDPCMaxIterations = double(sixgr.util.structGet(opt, "E2ETruthLDPCMaxIterations", 0));
    model.TruthUseGPU = logical(sixgr.util.structGet(opt, "E2ETruthUseGPU", false));
    return;
end

error("sixgr:e2e:ProxyAirModelRemoved", ...
    "E2EAirModel='%s' is no longer supported because LUT/logistic proxy air models were removed. Use E2EAirModel='truth'.", mode);
end

function calib = localBuildCampaignCalibrationPayload(cfg, opt, e2eAirLUT, link)
%#ok<INUSD>
error("sixgr:campaign:ProxyModeRemoved", ...
    "BLER calibration payload export was removed from the active waveform-truth-only repository.");
end

function kind = localClassifyCalibrationSourceKind(src)
src = lower(strtrim(char(string(src))));
if contains(src, "campaign_link_sweep") || strcmp(src, "link_sweep") || contains(src, "link_sweep")
    kind = "campaign_link_sweep";
elseif contains(src, "default") || contains(src, "external")
    kind = "external_proxy_payload";
else
    kind = "external_payload";
end
end

function notes = localDescribeCalibrationPayload(calib)
used = logical(sixgr.util.structGet(calib, "UsedByThisRun", false));
srcKind = string(sixgr.util.structGet(calib, "SourceKind", ""));
if srcKind == "campaign_link_sweep"
    origin = "Generated from campaign link sweeps.";
elseif srcKind == "external_proxy_payload"
    origin = "External proxy calibration payload is not used by active waveform-truth runs.";
else
    origin = "Loaded from external calibration payload.";
end

if used
    usedBy = string(sixgr.util.structGet(calib, "UsedByModules", strings(0,1)));
    if isempty(usedBy)
        usage = "UsedByThisRun=true.";
    else
        usage = "UsedByThisRun=true via " + strjoin(cellstr(usedBy), ", ") + ".";
    end
else
    usage = "UsedByThisRun=false.";
end
notes = localJoinNotes(origin, usage);
end

function tc = localCollectCalibrationTrialCounts(runFolder)
tc = struct();
layout = sixgr.report.resultLayout(runFolder);
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
    p = fullfile(layout.AirInterfaceCSVDir, fn);
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
    figDir = fullfile(runFolder, "image");
    csvDir = fullfile(runFolder, "csv");
    sixgr.util.ensureDir(figDir);
    hasSlotTableArg = (nargin >= 2) && istable(slotTable);
    hasPacketTraceArg = (nargin >= 3) && istable(packetTraceTable);
    hasFlowSummaryArg = (nargin >= 4) && istable(flowSummaryTable);
    hasBearerSummaryArg = (nargin >= 5) && istable(bearerSummaryTable);
    hasDropCauseArg = (nargin >= 6) && istable(dropCauseTable);
    hasHarqTraceArg = (nargin >= 7) && istable(harqTraceTable);
    hasAttachTraceArg = (nargin >= 8) && istable(attachTraceTable);
    hasSummaryArg = (nargin >= 9) && istable(summaryTable);

    if ~hasSlotTableArg
        try
            slotTable = readtable(fullfile(csvDir, "e2e_slot_metrics.csv"), "VariableNamingRule", "preserve");
        catch
            slotTable = table();
        end
    end
    if ~hasPacketTraceArg
        packetTraceTable = table();
    end
    if ~hasFlowSummaryArg
        flowSummaryTable = table();
    end
    if ~hasBearerSummaryArg
        bearerSummaryTable = table();
    end
    if ~hasDropCauseArg
        dropCauseTable = table();
    end
    if ~hasHarqTraceArg
        harqTraceTable = table();
    end
    if ~hasAttachTraceArg
        attachTraceTable = table();
    end
    if ~hasSummaryArg
        summaryTable = table();
    end

    if ~hasPacketTraceArg && isempty(packetTraceTable)
        try
            packetTraceTable = readtable(fullfile(csvDir, "e2e_packet_trace.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end
    if ~hasFlowSummaryArg && isempty(flowSummaryTable)
        try
            flowSummaryTable = readtable(fullfile(csvDir, "e2e_flow_summary.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end
    if ~hasBearerSummaryArg && isempty(bearerSummaryTable)
        try
            bearerSummaryTable = readtable(fullfile(csvDir, "e2e_bearer_summary.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end
    if ~hasDropCauseArg && isempty(dropCauseTable)
        try
            dropCauseTable = readtable(fullfile(csvDir, "e2e_drop_causes.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end
    if ~hasHarqTraceArg && isempty(harqTraceTable)
        try
            harqTraceTable = readtable(fullfile(csvDir, "e2e_harq_trace.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end
    if ~hasAttachTraceArg && isempty(attachTraceTable)
        try
            attachTraceTable = readtable(fullfile(csvDir, "e2e_attach_trace.csv"), "VariableNamingRule", "preserve");
        catch
        end
    end
    if ~hasSummaryArg && isempty(summaryTable)
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

function audit = localBuild25CategoryAudit(runFolder, opt, link, sys, mmtc, harq, syncCtrl, v2x, ntn, interf, rfp, numProbe, beam, e2e)
rows = repmat(struct("Category","","Status","","Evidence","","Notes",""), 0, 1);

onlyE2E = logical(sixgr.util.structGet(opt, "OnlyE2E", false));
runAux = ~onlyE2E && logical(sixgr.util.structGet(opt, "RunAuxiliaryProbes", false));
runMMTC = ~onlyE2E && logical(sixgr.util.structGet(opt, "RunSystemMMTCProbe", false));
runE2E = logical(sixgr.util.structGet(opt, "RunE2EStackProbe", true));
runLink = ~onlyE2E && logical(sixgr.util.structGet(opt, "RunLinkCampaign", true));
runSystem = ~onlyE2E;
[systemWaveformBacked, systemBackendLabel] = localSystemWaveformAuditState(sys);

multiUserStatus = "approximated";
multiUserNotes = "Fairness/sum-rate style KPIs from system abstraction";
if systemWaveformBacked
    multiUserStatus = "implemented";
    multiUserNotes = "Fairness/sum-rate KPIs from waveform-backed system grant replay (" + systemBackendLabel + ")";
end

rows(end+1,1) = localAudit(runFolder, "1. Error Performance Metrics", "implemented", ...
    "air_interface/csv/lls_kpi_summary.csv", "BER/BLER/outage proxy", runLink, link);
rows(end+1,1) = localAudit(runFolder, "2. Throughput and Rate Metrics", "implemented", ...
    "air_interface/csv/lls_kpi_summary.csv", "Goodput + spectral efficiency + peak from sweep", runLink, link);
rows(end+1,1) = localAudit(runFolder, "3. Signal Quality and CSI", "approximated", ...
    "air_interface/mat/link_results.mat", "SNR and noise variance; full CSI feedback set is partial", runLink, link);
rows(end+1,1) = localAudit(runFolder, "4. Channel Estimation and Equalization", "implemented", ...
    "air_interface/mat/link_results.mat", "Channel-estimation artifacts and equalization outputs", runLink, link);
rows(end+1,1) = localAudit(runFolder, "5. MIMO and Beamforming", "approximated", ...
    "beamforming/csv/probe_beam_mimo.csv", "Capacity/condition/beam metrics from probe", runAux, beam);
rows(end+1,1) = localAudit(runFolder, "6. Link Adaptation", "implemented", ...
    "air_interface/csv/lls_snr_sweep.csv", "BLER/BER/throughput vs SNR curves", runLink, link);
rows(end+1,1) = localAudit(runFolder, "7. HARQ and Retransmissions", "implemented", ...
    "harq/csv/probe_harq_summary.csv", "Retransmission probability/RTT/residual BLER", runAux, harq);
rows(end+1,1) = localAudit(runFolder, "8. Latency and Timing", "approximated", ...
    "harq/csv/probe_harq_packets.csv", "Processing delay + HARQ RTT proxy", runAux, harq);
rows(end+1,1) = localAudit(runFolder, "9. Power and Energy Efficiency", "approximated", ...
    "rf/csv/probe_rf_energy.csv", "Power model outputs + PAPR", runAux, rfp);
rows(end+1,1) = localAudit(runFolder, "10. Synchronization and Timing Offsets", "approximated", ...
    "control/csv/probe_sync_control.csv", "PBCH/PRACH detect + timing offset", runAux, syncCtrl);
rows(end+1,1) = localAudit(runFolder, "11. Channel Coding and Decoding", "implemented", ...
    "air_interface/csv/lls_kpi_summary.csv", "LDPC decoder iterations + BER/BLER", runLink, link);
rows(end+1,1) = localAudit(runFolder, "12. Modulation and Waveform Quality", "implemented", ...
    "air_interface/mat/link_results.mat", "EVM/PAPR waveform-quality artifacts; figures are optional", runLink, link);
rows(end+1,1) = localAudit(runFolder, "13. Interference Analysis", "approximated", ...
    "system/csv/system_interference_detail.csv", "Per-UE interference decomposition trace", runSystem, sys);
rows(end+1,1) = localAudit(runFolder, "14. Mobility and Time-Varying Channels", "implemented", ...
    "system/csv/system_time_series.csv", "Mobility traces and time-varying SINR", runSystem, sys);
rows(end+1,1) = localAudit(runFolder, "15. Multi-User and Multi-Cell Metrics", multiUserStatus, ...
    "system/csv/system_kpis.csv", multiUserNotes, runSystem, sys);
rows(end+1,1) = localAudit(runFolder, "16. Beam Management", "approximated", ...
    "beamforming/csv/probe_beam_mimo.csv", "Beam score metrics; full beam management loop not modeled", runAux, beam);
rows(end+1,1) = localAudit(runFolder, "17. Waveform and Numerology Specifics", "implemented", ...
    "numerology/csv/probe_numerology.csv", "SCS sweep impact on BER/BLER/throughput", runAux, numProbe);
rows(end+1,1) = localAudit(runFolder, "18. Control Channel and Random Access", "implemented", ...
    "control/csv/probe_sync_control.csv", "PBCH/PRACH/PDCCH/PUCCH probe metrics", runAux, syncCtrl);
rows(end+1,1) = localAudit(runFolder, "19. Hardware Impairments", "implemented", ...
    "rf/csv/probe_rf_energy.csv", "IQ imbalance/phase noise/CFO/DC offset sensitivity", runAux, rfp);
rows(end+1,1) = localAudit(runFolder, "20. Reliability and Outage (URLLC)", "approximated", ...
    "air_interface/csv/lls_kpi_summary.csv", "Outage and BLER reliability proxy", runLink, link);
rows(end+1,1) = localAudit(runFolder, "21. Massive MTC (mMTC) Metrics", "implemented", ...
    "mmtc/csv/probe_mmtc_kpis.csv", "Connection density + access success proxy", runMMTC, mmtc);
rows(end+1,1) = localAudit(runFolder, "22. V2X Metrics", "approximated", ...
    "v2x/csv/probe_v2x_sidelink.csv", "Sidelink-style PRR/IPG/latency vs velocity", runAux, v2x);
rows(end+1,1) = localAudit(runFolder, "23. NTN Metrics", "approximated", ...
    "ntn/csv/probe_ntn_delay_doppler.csv", "Delay/Doppler compensation probe", runAux, ntn);
rows(end+1,1) = localAudit(runFolder, "24. Protocol and Stack Interactions", "implemented", ...
    "packet_flow/csv/probe_e2e_summary.csv + packet_flow/csv/probe_e2e_packet_integrity.csv", "SDAP/PDCP/RLC/MAC/HARQ/RRC hooks with semantic packet checks", runE2E, e2e);
rows(end+1,1) = localAudit(runFolder, "25. Miscellaneous Statistical Outputs", "implemented", ...
    "packet_flow/csv/probe_e2e_slot_metrics.csv", "Slot-level statistical exports for correlation and post-processing", runE2E, e2e);

audit = struct2table(rows);
end

function r = localAudit(runFolder, cat, desiredStatus, evidence, notes, executed, module)
[evidenceExists, missingTokens] = localAuditEvidenceExists(runFolder, evidence);
moduleOk = logical(sixgr.util.structGet(module, "Ok", false));
moduleNotes = localExtractModuleNotes(module);
status = string(desiredStatus);
notesOut = string(notes);
if ~logical(executed)
    status = "not_run";
    notesOut = localDefaultAuditSkipNote(moduleNotes);
elseif ~evidenceExists
    status = "missing_artifact";
    notesOut = localJoinNotes(notesOut, "Missing evidence: " + strjoin(cellstr(missingTokens), ", "));
elseif ~moduleOk
    status = "failed";
    notesOut = localJoinNotes(notesOut, localDefaultAuditFailureNote(moduleNotes));
end
r = struct();
r.Category = string(cat);
r.Status = string(status);
r.Evidence = string(evidence);
r.Notes = string(notesOut);
end

function [waveformBacked, backendLabel] = localSystemWaveformAuditState(sys)
waveformBacked = false;
backendLabel = "";

kpi = sixgr.util.structGet(sys, "KPITable", table());
if ~(istable(kpi) && height(kpi) >= 1)
    return;
end

if ismember("WaveformBacked", string(kpi.Properties.VariableNames))
    waveformBacked = logical(kpi.WaveformBacked(1));
end
if ismember("ExecutionBackend", string(kpi.Properties.VariableNames))
    backendLabel = string(kpi.ExecutionBackend(1));
    waveformBacked = waveformBacked || contains(upper(backendLabel), "WAVEFORM");
end
end

function [existsAll, missingTokens] = localAuditEvidenceExists(runFolder, evidence)
tokens = split(string(evidence), "+");
missingTokens = strings(0,1);
existsAll = true;
for i = 1:numel(tokens)
    token = strtrim(tokens(i));
    if strlength(token) == 0
        continue;
    end
    if ~localAuditEvidenceTokenExists(runFolder, token)
        existsAll = false;
        missingTokens(end+1,1) = token; %#ok<AGROW>
    end
end
end

function tf = localAuditEvidenceTokenExists(runFolder, token)
token = strtrim(string(token));
if strlength(token) == 0
    tf = true;
    return;
end
absPattern = fullfile(runFolder, char(token));
if localPatternHasWildcard(token)
    tf = ~isempty(dir(absPattern));
else
    tf = exist(absPattern, "file") == 2 || exist(absPattern, "dir") == 7;
end
end

function note = localDefaultAuditSkipNote(moduleNotes)
note = strtrim(string(moduleNotes));
if strlength(note) == 0
    note = "Module not executed for this campaign.";
end
end

function note = localDefaultAuditFailureNote(moduleNotes)
note = strtrim(string(moduleNotes));
if strlength(note) == 0
    note = "Module reported Ok=false.";
end
end

function txt = localExtractModuleNotes(module)
txt = strtrim(string(sixgr.util.structGet(module, "Notes", "")));
end

function localEnsureMexAccelerators()
persistent builtOK
if ~isempty(builtOK) && builtOK
    return;
end

need = ["sixgr_fft_papr_kernel_mex", ...
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

function localRejectRemovedProxyModes(cfg, opt)
useFastLink = logical(sixgr.util.structGet(opt, "UseFastLinkModel", false));
if useFastLink
    error("sixgr:campaign:ProxyModeRemoved", ...
        "UseFastLinkModel=true is no longer supported. The active repository is waveform-truth-only.");
end

airModel = lower(strtrim(char(string(sixgr.util.structGet(opt, "E2EAirModel", "truth")))));
if ~strcmp(airModel, "truth")
    error("sixgr:campaign:ProxyModeRemoved", ...
        "E2EAirModel='%s' is no longer supported. Use E2EAirModel='truth' only.", airModel);
end

profileMode = lower(strtrim(char(string(sixgr.util.structGet(opt, "CampaignProfileMode", "")))));
if strcmp(profileMode, "stress_proxy")
    error("sixgr:campaign:ProxyModeRemoved", ...
        "CampaignProfileMode='stress_proxy' has been removed from the active repository.");
end

if logical(sixgr.util.structGet(opt, "CalibrateSystemBLERFromLink", false))
    error("sixgr:campaign:ProxyModeRemoved", ...
        "CalibrateSystemBLERFromLink=true is no longer supported because BLER calibration/LUT proxy paths were removed.");
end

phyBackend = lower(strtrim(char(string(sixgr.util.structGet(cfg, "system.phyBackend", "waveform")))));
if ~strcmp(phyBackend, "waveform")
    error("sixgr:campaign:ProxyModeRemoved", ...
        "system.phyBackend='%s' is no longer supported. Use waveform only.", phyBackend);
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
opt = localOverrideBool(opt, camp, "NoProxyTruthContract", "noProxyTruthContract");
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
layout = sixgr.report.resultLayout(runFolder);
figDir = layout.ReportImageDir;
sixgr.util.ensureDir(figDir);
files = strings(0,1);
nPlots = 0;

% 1) Link SNR sweep.
fSweep = fullfile(layout.AirInterfaceCSVDir, "lls_snr_sweep.csv");
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
fHarq = fullfile(layout.HARQCSVDir, "probe_harq_summary.csv");
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
fSync = fullfile(layout.ControlCSVDir, "probe_sync_control.csv");
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
fInterf = fullfile(layout.InterferenceCSVDir, "probe_interference_sir_bler.csv");
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
fNum = fullfile(layout.NumerologyCSVDir, "probe_numerology.csv");
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
fV2X = fullfile(layout.V2XCSVDir, "probe_v2x_sidelink.csv");
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

fNTN = fullfile(layout.NTNCSVDir, "probe_ntn_delay_doppler.csv");
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
fE2E = fullfile(layout.PacketFlowCSVDir, "probe_e2e_slot_metrics.csv");
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

function out = localVerifyArtifacts(runFolder, requireCampaignPlots, opt, summary, strictMode)
if nargin < 2
    requireCampaignPlots = false;
end
if nargin < 3 || ~isstruct(opt)
    opt = struct();
end
if nargin < 4 || ~isstruct(summary)
    summary = struct();
end
if nargin < 5
    strictMode = false;
end
ctx = localBuildArtifactVerificationContext(requireCampaignPlots, opt);
out = sixgr.report.verifyCampaignArtifacts(runFolder, summary, ...
    "ModuleContext", ctx, ...
    "StrictMode", logical(strictMode));
end

function ctx = localBuildArtifactVerificationContext(requireCampaignPlots, opt)
if nargin < 1
    requireCampaignPlots = false;
end
if nargin < 2 || ~isstruct(opt)
    opt = struct();
end

onlyE2E = logical(sixgr.util.structGet(opt, "OnlyE2E", false));
runE2E = logical(sixgr.util.structGet(opt, "RunE2EStackProbe", true));
runAux = logical(sixgr.util.structGet(opt, "RunAuxiliaryProbes", false));
runMMTC = logical(sixgr.util.structGet(opt, "RunSystemMMTCProbe", false));
runLink = logical(sixgr.util.structGet(opt, "RunLinkCampaign", true));

ctx = struct();
ctx.IncludeRun = true;
ctx.IncludeReproMeta = true;
ctx.IncludeCalibration = localShouldExportCalibrationArtifacts(opt);
ctx.IncludeStructuredManifest = logical(sixgr.util.structGet(opt, "OrganizeByBlock", false));
ctx.IncludeLink = ~onlyE2E && runLink;
ctx.IncludeControl = ~onlyE2E && logical(runE2E || runLink);
ctx.IncludeAuxiliary = ~onlyE2E && runAux;
ctx.IncludeMMTC = ~onlyE2E && runMMTC;
ctx.IncludeSystem = ~onlyE2E;
ctx.IncludeE2E = runE2E;
ctx.IncludeCampaignPlots = logical(requireCampaignPlots);
ctx.IncludeSystemFigures = ~onlyE2E && logical(sixgr.util.structGet(opt, "SystemSaveFigures", false));
ctx.IncludeE2EFigures = runE2E && logical(sixgr.util.structGet(opt, "E2ESaveFigures", false));
end

function requiredOutputs = localBuildRequiredOutputList(runFolder, summary, spec)
requiredOutputs = strings(0,1);
for i = 1:numel(spec)
    pat = string(spec(i).Pattern);
    if logical(spec(i).Required) && strlength(pat) > 0 && ~localPatternHasWildcard(pat)
        requiredOutputs(end+1,1) = string(fullfile(runFolder, char(pat))); %#ok<AGROW>
    end
end

summaryFields = [ ...
    "LogFile", "AuditCSV", ...
    "CalibrationDBMat", "CalibrationMetadataJSON", "CalibrationCoverageCSV", "CalibrationValidationCSV", ...
    "MetaRunManifestJSON", "MetaEnvironmentJSON", "MetaSeedsCSV", "MetaApproximationsCSV", "MetaCalibrationSourceJSON", ...
    "E2ESlotMetricsCSV", "E2EComponentIOCSV", "E2EComponentChecksCSV", ...
    "E2ESummaryCSV", "E2EAIMetricsCSV", "E2EPacketIntegrityCSV", ...
    "E2EPacketTraceCSV", "E2EFlowSummaryCSV", "E2EBearerSummaryCSV", "E2EAttachTraceCSV", ...
    "E2ESchedulerTraceCSV", "E2EHARQTraceCSV", "E2EDropCausesCSV", "E2EMAT"];
for i = 1:numel(summaryFields)
    fieldName = summaryFields(i);
    if isfield(summary, fieldName)
        pathValue = string(summary.(char(fieldName)));
        pathValue = strtrim(pathValue);
        if strlength(pathValue) > 0
            requiredOutputs(end+1,1) = pathValue; %#ok<AGROW>
        end
    end
end

layout = sixgr.report.resultLayout(runFolder);
requiredOutputs(end+1,1) = string(layout.ConfigResolvedJSON); %#ok<AGROW>
requiredOutputs = unique(requiredOutputs(strlength(requiredOutputs) > 0), "stable");
end

function tf = localPatternHasWildcard(pattern)
pattern = char(string(pattern));
tf = contains(pattern, "*") || contains(pattern, "?");
end

function meta = localNormalizeCampaignProfileMeta(modeIn, entryPointIn)
mode = lower(strtrim(string(modeIn)));
if strlength(mode) == 0
    mode = "unspecified";
end

entryPoint = strtrim(string(entryPointIn));
if strlength(entryPoint) == 0
    entryPoint = "sixgr_run_3gpp_full_campaign";
end

if mode == "stress_proxy"
    label = "STRESS_PROXY_PROFILE";
elseif mode == "truth_validation"
    label = "TRUTH_VALIDATION_PROFILE";
else
    label = upper(mode) + "_PROFILE";
end

meta = struct();
meta.Mode = mode;
meta.Label = label;
meta.EntryPoint = entryPoint;
end

function localWriteMarkdown(mdFile, summary, audit)
fid = fopen(mdFile, "w");
if fid < 0
    return;
end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "# Full 3GPP Campaign Report\n\n");
fprintf(fid, "- Run folder: `%s`\n", summary.RunFolder);
if isfield(summary, "CampaignProfileLabel") && strlength(string(summary.CampaignProfileLabel)) > 0
    fprintf(fid, "- Campaign profile: `%s`\n", string(summary.CampaignProfileLabel));
end
if isfield(summary, "CampaignProfileMode") && strlength(string(summary.CampaignProfileMode)) > 0
    fprintf(fid, "- Campaign profile mode: `%s`\n", string(summary.CampaignProfileMode));
end
if isfield(summary, "CampaignProfileEntryPoint") && strlength(string(summary.CampaignProfileEntryPoint)) > 0
    fprintf(fid, "- Campaign entry point: `%s`\n", string(summary.CampaignProfileEntryPoint));
end
if isfield(summary, "RunScope") && strlength(string(summary.RunScope)) > 0
    fprintf(fid, "- Run scope: `%s`\n", string(summary.RunScope));
end
if isfield(summary, "RunCompletion") && strlength(string(summary.RunCompletion)) > 0
    fprintf(fid, "- Run completion: `%s`\n", string(summary.RunCompletion));
end
if isfield(summary, "ConformanceLevel") && strlength(string(summary.ConformanceLevel)) > 0
    fprintf(fid, "- Conformance level: `%s`\n", string(summary.ConformanceLevel));
end
if isfield(summary, "NoProxyTruthContract")
    fprintf(fid, "- No-proxy truth contract: `%s`\n", string(logical(sixgr.util.structGet(summary, "NoProxyTruthContract", false))));
end
localWriteSubrunLine(fid, "Link run", sixgr.util.structGet(summary, "LinkRunStatus", ""), ...
    sixgr.util.structGet(summary, "LinkRunFolder", ""), sixgr.util.structGet(summary, "LinkRunNotes", ""));
localWriteSubrunLine(fid, "Detailed LLS", sixgr.util.structGet(summary, "DetailRunStatus", ""), ...
    sixgr.util.structGet(summary, "DetailRunFolder", ""), sixgr.util.structGet(summary, "DetailRunNotes", ""));
localWriteSubrunLine(fid, "System mobility", sixgr.util.structGet(summary, "SystemRunStatus", ""), ...
    sixgr.util.structGet(summary, "SystemRunFolder", ""), sixgr.util.structGet(summary, "SystemRunNotes", ""));
localWriteSubrunLine(fid, "mMTC run", sixgr.util.structGet(summary, "MMTCRunStatus", ""), ...
    sixgr.util.structGet(summary, "MMTCFolder", ""), sixgr.util.structGet(summary, "MMTCRunNotes", ""));
localWriteSubrunLine(fid, "End-to-end stack", sixgr.util.structGet(summary, "E2ERunStatus", ""), ...
    sixgr.util.structGet(summary, "E2EFolder", ""), sixgr.util.structGet(summary, "E2ERunNotes", ""));
localWriteSubrunLine(fid, "Calibration artifacts", sixgr.util.structGet(summary, "CalibrationStatus", ""), ...
    sixgr.util.structGet(summary, "CalibrationFolder", ""), sixgr.util.structGet(summary, "CalibrationNotes", ""));
fprintf(fid, "\n");
if localShouldWriteCalibrationDetails(summary)
    fprintf(fid, "- Calibration folder: `%s`\n", string(summary.CalibrationFolder));
    fprintf(fid, "- Calibration DB MAT: `%s`\n", string(summary.CalibrationDBMat));
    fprintf(fid, "- Calibration metadata JSON: `%s`\n", string(summary.CalibrationMetadataJSON));
    fprintf(fid, "- Calibration coverage CSV: `%s`\n", string(summary.CalibrationCoverageCSV));
    fprintf(fid, "- Calibration validation CSV: `%s`\n", string(summary.CalibrationValidationCSV));
    fprintf(fid, "- Calibration source: `%s`\n", string(summary.CalibrationSource));
    fprintf(fid, "- Calibration source kind: `%s`\n", string(sixgr.util.structGet(summary, "CalibrationSourceKind", "")));
    fprintf(fid, "- Calibration generated from campaign link sweep: `%s`\n", string(logical(sixgr.util.structGet(summary, "CalibrationGeneratedFromCampaignLinkSweep", false))));
    fprintf(fid, "- Calibration used by this run: `%s`\n", string(logical(sixgr.util.structGet(summary, "CalibrationUsedByThisRun", false))));
    usedBy = string(sixgr.util.structGet(summary, "CalibrationUsedByModules", strings(0,1)));
    if ~isempty(usedBy)
        fprintf(fid, "- Calibration used by modules: `%s`\n", strjoin(cellstr(usedBy), ", "));
    end
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
if isfield(summary, "MetaCalibrationSourceJSON") && strlength(string(summary.MetaCalibrationSourceJSON)) > 0
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
if isfield(summary, "RequiredOutputsCSV")
    fprintf(fid, "- Required outputs CSV: `%s`\n", string(summary.RequiredOutputsCSV));
end
if isfield(summary, "RequiredOutputCoverage_pct")
    fprintf(fid, "- Required output completeness: `%.2f%%` (missing=%g)\n", ...
        double(sixgr.util.structGet(summary, "RequiredOutputCoverage_pct", NaN)), ...
        double(sixgr.util.structGet(summary, "RequiredOutputMissingCount", NaN)));
end
if isfield(summary, "StructuredFolder")
    fprintf(fid, "- Structured block-wise folder: `%s`\n", string(summary.StructuredFolder));
end
if isfield(summary, "StructuredMirrorFolder")
    fprintf(fid, "- Structured mirror folder: `%s`\n", string(summary.StructuredMirrorFolder));
end
if isfield(summary, "StructuredMirrorLayout")
    fprintf(fid, "- Structured mirror layout: `%s`\n", string(summary.StructuredMirrorLayout));
end
if isfield(summary, "E2EPacketAccountingPassRate_pct") || isfield(summary, "E2EQoSPass")
    fprintf(fid, "\n## E2E Integrity vs QoS\n\n");
    if isfield(summary, "E2EPacketAccountingPassRate_pct")
        fprintf(fid, "- Packet-accounting integrity pass rate: `%.2f%%`\n", double(sixgr.util.structGet(summary, "E2EPacketAccountingPassRate_pct", NaN)));
    end
    if isfield(summary, "E2EPacketAccountingMeaning")
        fprintf(fid, "- Packet-accounting meaning: `%s`\n", string(sixgr.util.structGet(summary, "E2EPacketAccountingMeaning", "")));
    end
    if isfield(summary, "E2EQoSPass")
        fprintf(fid, "- QoS/SLA acceptance: `%s`\n", string(logical(sixgr.util.structGet(summary, "E2EQoSPass", false))));
    end
    if isfield(summary, "E2EDeliveryRatio")
        fprintf(fid, "- Delivery ratio: `%.6f` vs target `%.6f` -> `%s`\n", ...
            double(sixgr.util.structGet(summary, "E2EDeliveryRatio", NaN)), ...
            double(sixgr.util.structGet(summary, "E2EDeliveryRatioTarget", NaN)), ...
            string(logical(sixgr.util.structGet(summary, "E2EDeliveryRatioPass", false))));
    end
    if isfield(summary, "E2EObservedP95Latency_ms")
        fprintf(fid, "- P95 latency: `%.3f ms` vs budget `%.3f ms` -> `%s`\n", ...
            double(sixgr.util.structGet(summary, "E2EObservedP95Latency_ms", NaN)), ...
            double(sixgr.util.structGet(summary, "E2ELatencyBudgetTarget_ms", NaN)), ...
            string(logical(sixgr.util.structGet(summary, "E2ELatencyBudgetPass", false))));
    end
    if isfield(summary, "E2EGoodput_Mbps")
        fprintf(fid, "- Goodput: `%.6f Mbps` vs throughput target `%.6f Mbps` -> `%s`\n", ...
            double(sixgr.util.structGet(summary, "E2EGoodput_Mbps", NaN)), ...
            double(sixgr.util.structGet(summary, "E2EThroughputTarget_Mbps", NaN)), ...
            string(logical(sixgr.util.structGet(summary, "E2EThroughputTargetPass", false))));
    end
    if isfield(summary, "E2ESystemCoupled")
        fprintf(fid, "- System-coupled execution: `%s`\n", string(logical(sixgr.util.structGet(summary, "E2ESystemCoupled", false))));
    end
    if isfield(summary, "E2ECouplingMode") && strlength(string(summary.E2ECouplingMode)) > 0
        fprintf(fid, "- E2E coupling mode: `%s`\n", string(sixgr.util.structGet(summary, "E2ECouplingMode", "")));
    end
    if isfield(summary, "E2EAppSDUChunkBytes")
        fprintf(fid, "- App SDU chunk bytes: `%.0f` (`%s`)\n", ...
            double(sixgr.util.structGet(summary, "E2EAppSDUChunkBytes", NaN)), ...
            string(sixgr.util.structGet(summary, "E2EAppSDUChunkSource", "")));
    end
    if isfield(summary, "E2EAttachPass")
        fprintf(fid, "- Attach pass: `%s`\n", string(logical(sixgr.util.structGet(summary, "E2EAttachPass", false))));
    end
    if isfield(summary, "E2EQoSFailureCount")
        fprintf(fid, "- QoS failure count: `%g`\n", double(sixgr.util.structGet(summary, "E2EQoSFailureCount", NaN)));
    end
    if isfield(summary, "E2EQoSEvaluationCSV") && strlength(string(summary.E2EQoSEvaluationCSV)) > 0
        fprintf(fid, "- QoS evaluation CSV: `%s`\n", string(summary.E2EQoSEvaluationCSV));
    end
    if isfield(summary, "E2ECouplingNotes") && strlength(string(summary.E2ECouplingNotes)) > 0
        fprintf(fid, "- Coupling note: %s\n", string(summary.E2ECouplingNotes));
    end
    fprintf(fid, "- Interpretation: execution/report integrity can pass while QoS/SLA acceptance fails.\n");
end
fprintf(fid, "\n- Overall execution/report integrity status: `%s`\n\n", string(summary.Ok));
fprintf(fid, "## 25-Category Audit\n\n");
for i = 1:height(audit)
    fprintf(fid, "- **%s**: `%s` (%s)\n", char(audit.Category(i)), char(audit.Status(i)), char(audit.Notes(i)));
end
end

function localWriteSubrunLine(fid, label, status, folder, notes)
status = strtrim(string(status));
folder = strtrim(string(folder));
notes = strtrim(string(notes));
if strlength(status) == 0
    status = "unknown";
end
fprintf(fid, "- %s: `%s`", label, status);
if any(status == ["completed","failed","missing_artifact"]) && strlength(folder) > 0 && isfolder(char(folder))
    fprintf(fid, " (`%s`)", folder);
end
if strlength(notes) > 0
    fprintf(fid, " - %s", notes);
end
fprintf(fid, "\n");
end

function scope = localBuildRunScope(opt)
onlyE2E = logical(sixgr.util.structGet(opt, "OnlyE2E", false));
if onlyE2E
    scope = "e2e_only";
    return;
end

parts = strings(0,1);
if logical(sixgr.util.structGet(opt, "RunLinkCampaign", true))
    parts(end+1,1) = "air_interface"; %#ok<AGROW>
end
if logical(sixgr.util.structGet(opt, "RunDetailedLinkDiagnostics", true))
    parts(end+1,1) = "air_interface_detailed"; %#ok<AGROW>
end
parts(end+1,1) = "system"; %#ok<AGROW>
if logical(sixgr.util.structGet(opt, "RunSystemMMTCProbe", false))
    parts(end+1,1) = "mmtc"; %#ok<AGROW>
end
if logical(sixgr.util.structGet(opt, "RunAuxiliaryProbes", false))
    parts(end+1,1) = "auxiliary"; %#ok<AGROW>
end
if logical(sixgr.util.structGet(opt, "RunE2EStackProbe", true))
    parts(end+1,1) = "packet_flow"; %#ok<AGROW>
end
scope = strjoin(parts, "+");
if strlength(scope) == 0
    scope = "no_modules";
end
end

function level = localDetermineConformanceLevel(cfg, opt, summary)
if nargin < 3 || ~isstruct(summary)
    summary = struct();
end
if localNoProxyTruthContractEnabled(cfg, opt)
    level = "strict_no_proxy_truth";
    return;
end

profileMode = lower(strtrim(char(string(sixgr.util.structGet(opt, "CampaignProfileMode", "")))));
if strcmp(profileMode, "stress_proxy")
    level = "stress_proxy";
    return;
end

e2eAirModel = lower(strtrim(char(string(sixgr.util.structGet(opt, "E2EAirModel", "truth")))));
systemCoupled = logical(sixgr.util.structGet(summary, "E2ESystemCoupled", false));
if strcmp(e2eAirModel, "truth") && systemCoupled
    level = "system_coupled_truth_replay";
    return;
end
if strcmp(e2eAirModel, "truth") && ~systemCoupled
    level = "uncoupled_truth_replay";
    return;
end

sysPhyBackend = lower(strtrim(char(string(sixgr.util.structGet(cfg, "system.phyBackend", "waveform")))));
if strcmp(e2eAirModel, "truth") || strcmp(sysPhyBackend, "waveform")
    level = "partial_truth_execution";
    return;
end

level = "mixed_proxy_truth";
end

function summary = localFinalizeRunCompletion(summary)
if ~(isstruct(summary) && isfield(summary, "Ok"))
    return;
end
if logical(summary.Ok)
    summary.RunCompletion = "completed_requested_scope";
else
    summary.RunCompletion = "failed_requested_scope";
end
end

function tf = localShouldWriteCalibrationDetails(summary)
status = lower(strtrim(char(string(sixgr.util.structGet(summary, "CalibrationStatus", "")))));
tf = any(strcmp(status, {"completed", "failed", "missing_artifact"}));
end

function module = localMarkModuleSkipped(module, reason)
if nargin < 1 || ~isstruct(module)
    module = struct();
end
if nargin < 2
    reason = "Skipped";
end
module.Executed = false;
module.Status = "skipped";
module.Notes = string(reason);
end

function [status, notes] = localSummarizeSubrun(executed, module, runFolder, skipReason)
if nargin < 4
    skipReason = "Skipped";
end
status = "skipped";
notes = localExtractModuleNotes(module);
if ~logical(executed)
    if strlength(notes) == 0
        notes = string(skipReason);
    end
    return;
end

runFolder = strtrim(string(runFolder));
hasFolder = strlength(runFolder) > 0 && isfolder(char(runFolder));
ok = logical(sixgr.util.structGet(module, "Ok", false));
if hasFolder
    if ok
        status = "completed";
    else
        status = "failed";
    end
else
    if ok
        status = "missing_artifact";
    else
        status = "failed";
    end
    notes = localJoinNotes(notes, "Expected run folder missing.");
end
end

function [tf, reason] = localShouldExportCalibrationArtifacts(opt)
tf = false;
reason = "Calibration/LUT artifact export was removed from the active waveform-truth-only repository.";
end

function tf = localIncludeCalibrationMeta(summary, calibration)
status = lower(strtrim(char(string(sixgr.util.structGet(summary, "CalibrationStatus", "")))));
tf = any(strcmp(status, {"completed", "failed", "missing_artifact"}));
if ~tf
    src = strtrim(char(string(sixgr.util.structGet(calibration, "Source", ""))));
    tf = strlength(string(src)) > 0 && ~strcmp(status, "skipped");
end
end

function reason = localMMTCSkipReason(onlyE2E, runMMTC)
if logical(onlyE2E)
    reason = "OnlyE2E=true";
elseif ~logical(runMMTC)
    reason = "RunSystemMMTCProbe=false";
else
    reason = "module_disabled";
end
end

function out = localJoinNotes(varargin)
parts = strings(0,1);
for i = 1:nargin
    s = strtrim(string(varargin{i}));
    if strlength(s) > 0
        parts(end+1,1) = s; %#ok<AGROW>
    end
end
if isempty(parts)
    out = "";
    return;
end
parts = unique(parts, "stable");
out = join(parts, " | ");
out = out(1);
end

function paths = localFilterPresentArtifacts(pathsIn)
if isempty(pathsIn)
    paths = {};
    return;
end
paths = {};
for i = 1:numel(pathsIn)
    p = strtrim(string(pathsIn{i}));
    if strlength(p) == 0
        continue;
    end
    pChar = char(p);
    if exist(pChar, "file") == 2 || isfolder(pChar)
        paths{end+1} = pChar; %#ok<AGROW>
    end
end
end

function p = localResolveResultsRoot(inPath)
p = sixgr.report.resolveResultsRoot(inPath);
end

function [bucket, profile] = localCampaignRunFolderClass(opt, profileMeta)
onlyE2E = logical(sixgr.util.structGet(opt, "OnlyE2E", false));
runLink = ~onlyE2E && logical(sixgr.util.structGet(opt, "RunLinkCampaign", true));
runDetailed = ~onlyE2E && logical(sixgr.util.structGet(opt, "RunDetailedLinkDiagnostics", true));
runSystem = ~onlyE2E;

profile = localSanitizeRunFolderToken(string(sixgr.util.structGet(profileMeta, "Mode", "")), "campaign");
if strcmpi(profile, "unspecified")
    profile = "campaign";
end

if onlyE2E
    bucket = "e2e";
elseif runSystem || strcmpi(profile, "stress_proxy")
    bucket = "sls";
elseif runLink || runDetailed
    bucket = "lls";
else
    bucket = "sls";
end

if strlength(string(profile)) == 0 || strcmpi(profile, "campaign")
    if onlyE2E
        profile = "packet_flow";
    elseif strcmpi(bucket, "lls")
        profile = "link_validation";
    else
        profile = "campaign";
    end
end
end

function tok = localSanitizeRunFolderToken(inTok, fallback)
tok = lower(strtrim(char(string(inTok))));
tok = regexprep(tok, '[^a-z0-9]+', '_');
tok = regexprep(tok, '_+', '_');
tok = regexprep(tok, '^_+|_+$', '');
if strlength(string(tok)) == 0
    tok = char(string(fallback));
end
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
