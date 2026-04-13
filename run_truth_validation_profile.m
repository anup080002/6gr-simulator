function out = run_truth_validation_profile(varargin)
%RUN_TRUTH_VALIDATION_PROFILE Waveform LLS + truth E2E validation runner.
%
% This runner still excludes standalone SLS/system artifact export, but the
% truth E2E leg now couples to an internal waveform SystemLevelRunner pass
% so packet-flow delivery follows actual lower-layer grant/HARQ outcomes.

ip = inputParser;
ip.addParameter("ConfigFile", "config/suite_config_truth_validation.json", @(x)ischar(x)||isstring(x)||isstruct(x));
ip.addParameter("ResultsRoot", "results", @(x)ischar(x)||isstring(x));
ip.addParameter("LinkDuration_s", 0.02, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter("LinkMaxSimFrames", 8, @(x)isnumeric(x)&&isscalar(x)&&x>=8);
ip.addParameter("LinkSNR_dB", 30, @(x)isnumeric(x)&&isscalar(x));
ip.addParameter("LinkSNRGrid_dB", [0 10 20 30], @(x)isnumeric(x)&&isvector(x)&&~isempty(x));
ip.addParameter("LinkSweepFrames", 2, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter("LinkSweepMaxPoints", 4, @(x)isnumeric(x)&&isscalar(x)&&x>=3);
ip.addParameter("E2EDuration_s", 0.02, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter("E2EMaxSlots", 24, @(x)isnumeric(x)&&isscalar(x)&&x>=20);
ip.addParameter("E2EUECount", 2, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter("E2ETrafficModel", "traceReplay", @(x)ischar(x)||isstring(x));
ip.addParameter("SaveFigures", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("GenerateCampaignPlots", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("SetupToolboxChecks", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("Verbose", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

setup6GRSimToolkit("Verbose", logical(opt.Verbose), "RunToolboxChecks", logical(opt.SetupToolboxChecks));
cfg = localLoadConfig(opt.ConfigFile);
cfg = sixgr.truth.prepareValidationConfig(cfg, opt);
truthSlotBudget = max(round(double(opt.E2EMaxSlots)), localRequiredTruthSlots(cfg, double(opt.E2EDuration_s)));

baseRep = sixgr_run_3gpp_full_campaign(cfg, ...
    "ResultsRoot", char(string(opt.ResultsRoot)), ...
    "Verbose", logical(opt.Verbose), ...
    "SetupToolboxChecks", false, ...
    "CampaignProfileMode", "truth_validation", ...
    "CampaignProfileEntryPoint", "run_truth_validation_profile", ...
    "OnlyE2E", true, ...
    "RunE2EStackProbe", true, ...
    "RunSystemMMTCProbe", false, ...
    "RunAuxiliaryProbes", false, ...
    "UseFastLinkModel", false, ...
    "UseMexAcceleration", false, ...
    "UseParallelAcceleration", false, ...
    "AutoStartParallelPool", false, ...
    "AutoBuildMexAcceleration", false, ...
    "CalibrateSystemBLERFromLink", false, ...
    "GenerateCampaignPlots", logical(opt.GenerateCampaignPlots), ...
    "VerifyArtifacts", true, ...
    "NoProxyTruthContract", true, ...
    "E2EDuration_s", double(opt.E2EDuration_s), ...
    "E2EMaxSlots", round(double(opt.E2EMaxSlots)), ...
    "E2EUECount", round(double(opt.E2EUECount)), ...
    "E2ETrafficModel", char(string(opt.E2ETrafficModel)), ...
    "E2EEnableAI", false, ...
    "E2ESaveFigures", logical(opt.SaveFigures), ...
    "E2EAirModel", "truth", ...
    "E2EStrictValidation", true, ...
    "E2ETruthFastAWGNPath", false, ...
    "E2ETruthCompactPHYIO", true, ...
    "E2ETruthAdaptiveLDPC", true, ...
    "E2ETruthLDPCMaxIterations", 0, ...
    "E2ETruthUseGPU", false, ...
    "E2ETruthMaxSlots", truthSlotBudget, ...
    "OrganizeByBlock", false, ...
    "MirrorStructuredResults", false);

runFolder = char(string(baseRep.RunFolder));
if strlength(string(runFolder)) == 0 || ~isfolder(runFolder)
    error("sixgr:truth:MissingRunFolder", "Truth validation base run did not produce a valid run folder.");
end
layout = sixgr.report.resultLayout(runFolder);
supplementalRoot = fullfile(runFolder, "supplemental_link");
supplementalLayout = sixgr.report.resultLayout(supplementalRoot);
supplementalRelativeRoot = "supplemental_link";

link = sixgr.truth.runWaveformLinkBundle(cfg, supplementalLayout.AirInterfaceDir, opt);
controlTrace = sixgr.truth.exportControlPlaneTraces(supplementalRoot, sixgr.util.structGet(baseRep, "E2E", struct()));
scan = sixgr.truth.scanTruthArtifacts(runFolder, sixgr.util.structGet(baseRep, "Summary", struct()));
supplementalScan = sixgr.truth.scanTruthArtifacts(supplementalRoot, struct());

artifactCtx = struct( ...
    "IncludeRun", true, ...
    "IncludeReproMeta", true, ...
    "IncludeCalibration", false, ...
    "IncludeStructuredManifest", false, ...
    "IncludeLink", false, ...
    "IncludeControl", false, ...
    "IncludeAuxiliary", false, ...
    "IncludeMMTC", false, ...
    "IncludeSystem", false, ...
    "IncludeE2E", true, ...
    "IncludeCampaignPlots", logical(opt.GenerateCampaignPlots), ...
    "IncludeSystemFigures", false, ...
    "IncludeE2EFigures", logical(opt.SaveFigures));
artifactCheck = sixgr.report.verifyCampaignArtifacts(runFolder, baseRep.Summary, ...
    "ModuleContext", artifactCtx, ...
    "StrictMode", true);

settings = localBuildSettings(opt, cfg);
summary = localBuildSummary(runFolder, baseRep, link, artifactCheck, scan, supplementalScan, settings, supplementalRoot, supplementalRelativeRoot);
localAnnotateBaseArtifacts(layout, supplementalRoot, supplementalRelativeRoot);

metaDir = layout.MetaDir;
sixgr.util.ensureDir(metaDir);
manifestFile = fullfile(metaDir, "truth_validation_manifest.json");
sixgr.util.jsonWrite(manifestFile, struct( ...
    "GeneratedUTC", localUtcStamp(), ...
    "EntryPoint", "run_truth_validation_profile", ...
    "ProfileMode", "truth_validation", ...
    "ProfileLabel", "TRUTH_VALIDATION_PROFILE", ...
    "RunFolder", runFolder, ...
    "SupplementalArtifactRoot", supplementalRoot, ...
    "SupplementalArtifactRootRelative", supplementalRelativeRoot, ...
    "SupplementalArtifactsGenerated", true, ...
    "SupplementalArtifactsCoLocated", false, ...
    "SupplementalArtifactSemantics", "wrapper_generated_not_part_of_base_campaign_execution", ...
    "Settings", settings, ...
    "ArtifactChecklistCSV", artifactCheck.CSV, ...
    "RequiredOutputsCSV", artifactCheck.RequiredOutputsCSV, ...
    "BaseNoProxyScanCSV", scan.CSV, ...
    "SupplementalNoProxyScanCSV", supplementalScan.CSV, ...
    "ClaimMatrixMarkdown", fullfile(localRepoRoot(), "FOLLOWUP_PROMPT_CLAIM_MATRIX.md"), ...
    "Notes", {{ ...
        'This profile excludes standalone SLS/system artifacts while keeping truth E2E coupled to an internal waveform system grant engine.', ...
        'Supplemental waveform link and control exports are written under supplemental_link/ and are not part of the base e2e_only campaign execution.', ...
        'Waveform truth is enforced for link/control export and lower-layer-coupled E2E replay.', ...
        'Proxy, fallback, LUT, logistic, and synthetic markers are scanned from primary truth artifacts.'}}));

mdFile = fullfile(layout.ReportDir, "truth_validation_report.md");
matFile = fullfile(layout.ReportMATDir, "truth_validation_report.mat");
localWriteReport(mdFile, summary, settings, link, controlTrace, artifactCheck, scan, supplementalScan);
sixgr.util.matSave(matFile, struct( ...
    "summary", summary, ...
    "settings", settings, ...
    "baseE2EReport", baseRep, ...
    "link", link, ...
    "controlTrace", controlTrace, ...
    "artifactCheck", artifactCheck, ...
    "noProxyScan", scan, ...
    "supplementalNoProxyScan", supplementalScan));

out = struct();
out.Ok = logical(summary.Ok);
out.RunFolder = runFolder;
out.SupplementalRoot = supplementalRoot;
out.Settings = settings;
out.BaseE2EReport = baseRep;
out.Link = link;
out.Control = controlTrace;
out.ArtifactCheck = artifactCheck;
out.NoProxyScan = scan;
out.SupplementalNoProxyScan = supplementalScan;
out.ReportMarkdown = mdFile;
out.ReportMAT = matFile;
out.ManifestJSON = manifestFile;
out.ClaimMatrixMarkdown = fullfile(localRepoRoot(), "FOLLOWUP_PROMPT_CLAIM_MATRIX.md");
out.NoProxyScanCSV = scan.CSV;
out.SupplementalNoProxyScanCSV = supplementalScan.CSV;
end

function cfg = localLoadConfig(cfgFile)
if builtin("isstruct", cfgFile) && isscalar(cfgFile)
    cfg = sixgr.util.mergeStruct(sixgr.config.defaultConfig(), cfgFile);
    cfg = sixgr.config.normalizeConfig(cfg);
    sixgr.config.validateConfig(cfg);
else
    cfg = sixgr_loadConfig(char(string(cfgFile)));
end
end

function settings = localBuildSettings(opt, cfg)
settings = struct();
settings.ConfigFile = char(string(opt.ConfigFile));
settings.UseFastLinkModel = false;
settings.UseMexAcceleration = false;
settings.UseParallelAcceleration = false;
settings.StrictMode = true;
settings.NoProxyTruthContract = true;
settings.OnlyE2EBaseRun = true;
settings.IncludeSystem = false;
settings.IncludeSystemSINRSurface = false;
settings.IncludeCalibrationArtifacts = false;
settings.E2EAirModel = "truth";
settings.E2ETruthFastAWGNPath = false;
settings.RequestedChannelModel = "TDL-C";
settings.NormalizedChannelModel = string(sixgr.util.structGet(cfg, "channel.model", ""));
settings.TDLProfile = string(sixgr.util.structGet(cfg, "channel.tdlProfile", ""));
settings.ChannelAWGNOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", true));
settings.LinkSNR_dB = double(opt.LinkSNR_dB);
settings.LinkMaxSimFrames = round(double(opt.LinkMaxSimFrames));
settings.E2EMaxSlots = round(double(opt.E2EMaxSlots));
settings.E2EUECount = round(double(opt.E2EUECount));
settings.E2ETrafficModel = string(opt.E2ETrafficModel);
settings.SaveFigures = logical(opt.SaveFigures);
settings.GenerateCampaignPlots = logical(opt.GenerateCampaignPlots);
end

function summary = localBuildSummary(runFolder, baseRep, link, artifactCheck, scan, supplementalScan, settings, supplementalRoot, supplementalRelativeRoot)
summary = struct();
summary.Ok = logical(baseRep.Ok) && logical(link.Ok) && logical(scan.Ok) && logical(supplementalScan.Ok) && logical(artifactCheck.Ok);
summary.RunFolder = string(runFolder);
summary.SupplementalArtifactRoot = string(supplementalRoot);
summary.SupplementalArtifactRootRelative = string(supplementalRelativeRoot);
summary.BaseE2EOk = logical(baseRep.Ok);
summary.LinkOk = logical(link.Ok);
summary.NoProxyScanOk = logical(scan.Ok);
summary.SupplementalNoProxyScanOk = logical(supplementalScan.Ok);
summary.ArtifactCheckOk = logical(artifactCheck.Ok);
summary.E2EExecutionMode = string(sixgr.util.structGet(baseRep.Summary, "E2EExecutionMode", ""));
summary.E2EArtifactMode = string(sixgr.util.structGet(baseRep.Summary, "E2EArtifactMode", ""));
summary.E2EQoSPass = logical(sixgr.util.structGet(baseRep.Summary, "E2EQoSPass", true));
summary.E2EPacketAccountingPassRate_pct = double(sixgr.util.structGet(baseRep.Summary, "E2EPacketAccountingPassRate_pct", NaN));
summary.E2EDeliveryRatio = double(sixgr.util.structGet(baseRep.Summary, "E2EDeliveryRatio", NaN));
summary.E2EDeliveryRatioTarget = double(sixgr.util.structGet(baseRep.Summary, "E2EDeliveryRatioTarget", NaN));
summary.E2ELatencyBudgetPass = logical(sixgr.util.structGet(baseRep.Summary, "E2ELatencyBudgetPass", true));
summary.E2EThroughputTargetPass = logical(sixgr.util.structGet(baseRep.Summary, "E2EThroughputTargetPass", true));
summary.E2EAttachPass = logical(sixgr.util.structGet(baseRep.Summary, "E2EAttachPass", true));
summary.RequestedChannelModel = string(settings.RequestedChannelModel);
summary.NormalizedChannelModel = string(settings.NormalizedChannelModel);
summary.TDLProfile = string(settings.TDLProfile);
summary.ArtifactChecklistCSV = string(artifactCheck.CSV);
summary.RequiredOutputsCSV = string(artifactCheck.RequiredOutputsCSV);
summary.NoProxyScanCSV = string(scan.CSV);
summary.SupplementalNoProxyScanCSV = string(supplementalScan.CSV);
summary.ClaimMatrixMarkdown = string(fullfile(localRepoRoot(), "FOLLOWUP_PROMPT_CLAIM_MATRIX.md"));
end

function localWriteReport(mdFile, summary, settings, link, controlTrace, artifactCheck, scan, supplementalScan)
fid = fopen(mdFile, "w");
if fid < 0
    return;
end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "# Truth Validation Report\n\n");
fprintf(fid, "- Overall status: `%s`\n", string(summary.Ok));
fprintf(fid, "- Profile label: `TRUTH_VALIDATION_PROFILE`\n");
fprintf(fid, "- Run folder: `%s`\n", string(summary.RunFolder));
fprintf(fid, "- Base campaign scope: `e2e_only`\n");
fprintf(fid, "- Supplemental artifact root: `%s`\n", string(summary.SupplementalArtifactRootRelative));
fprintf(fid, "- Supplemental artifacts are part of the wrapper output only and were not part of the base campaign execution counted by `OnlyE2E`, `LinkExecuted`, or `SystemExecuted`.\n");
fprintf(fid, "- Base E2E status: `%s`\n", string(summary.BaseE2EOk));
fprintf(fid, "- Link status: `%s`\n", string(summary.LinkOk));
fprintf(fid, "- No-proxy scan: `%s`\n", string(summary.NoProxyScanOk));
fprintf(fid, "- Supplemental no-proxy scan: `%s`\n", string(summary.SupplementalNoProxyScanOk));
fprintf(fid, "- Artifact check: `%s`\n", string(summary.ArtifactCheckOk));
fprintf(fid, "- Requested channel model: `%s`\n", string(settings.RequestedChannelModel));
fprintf(fid, "- Normalized channel model: `%s`\n", string(settings.NormalizedChannelModel));
fprintf(fid, "- TDL profile: `%s`\n", string(settings.TDLProfile));
fprintf(fid, "- E2E execution mode: `%s`\n", string(summary.E2EExecutionMode));
fprintf(fid, "- E2E artifact mode: `%s`\n", string(summary.E2EArtifactMode));
fprintf(fid, "- E2E packet-accounting integrity pass rate: `%.2f%%`\n", double(summary.E2EPacketAccountingPassRate_pct));
fprintf(fid, "- E2E QoS/SLA acceptance: `%s`\n", string(summary.E2EQoSPass));
fprintf(fid, "- E2E delivery ratio: `%.6f` vs target `%.6f`\n", double(summary.E2EDeliveryRatio), double(summary.E2EDeliveryRatioTarget));
fprintf(fid, "- E2E latency-budget pass: `%s`\n", string(summary.E2ELatencyBudgetPass));
fprintf(fid, "- E2E throughput-target pass: `%s`\n", string(summary.E2EThroughputTargetPass));
fprintf(fid, "- E2E attach pass: `%s`\n", string(summary.E2EAttachPass));
fprintf(fid, "- Interpretation: packet-accounting integrity is reported separately from service-quality acceptance.\n");
fprintf(fid, "- System/SINR surface: `skipped_by_design`\n");
fprintf(fid, "- Calibration artifacts in base campaign: `not_exported`\n");
fprintf(fid, "- Artifact checklist CSV: `%s`\n", string(summary.ArtifactChecklistCSV));
fprintf(fid, "- Required outputs CSV: `%s`\n", string(summary.RequiredOutputsCSV));
fprintf(fid, "- Base no-proxy scan CSV: `%s`\n", string(summary.NoProxyScanCSV));
fprintf(fid, "- Supplemental no-proxy scan CSV: `%s`\n", string(summary.SupplementalNoProxyScanCSV));
fprintf(fid, "- Claim matrix: `%s`\n\n", string(summary.ClaimMatrixMarkdown));
fprintf(fid, "## Supplemental Link Cases\n\n");
if istable(link.KPITable) && ~isempty(link.KPITable)
    for i = 1:height(link.KPITable)
        fprintf(fid, "- `%s`: ok=%s skipped=%s notes=`%s`\n", ...
            string(link.KPITable.Case(i)), string(link.KPITable.Ok(i)), ...
            string(link.KPITable.Skipped(i)), string(link.KPITable.Notes(i)));
    end
end
fprintf(fid, "\n## Supplemental Control Outputs\n\n");
fprintf(fid, "- Cell search trials: `%s`\n", string(controlTrace.CellSearchTrialsCSV));
fprintf(fid, "- PBCH recovery trials: `%s`\n", string(controlTrace.PBCHRecoveryTrialsCSV));
fprintf(fid, "- PRACH trials: `%s`\n", string(controlTrace.PRACHTrialsCSV));
fprintf(fid, "- PDCCH trials: `%s`\n", string(controlTrace.PDCCHTrialsCSV));
fprintf(fid, "- PUCCH trials: `%s`\n", string(controlTrace.PUCCHTrialsCSV));
fprintf(fid, "- Attach state trace: `%s`\n", string(controlTrace.AttachStateTraceCSV));
fprintf(fid, "- RRC message trace: `%s`\n", string(controlTrace.RRCMessageTraceCSV));
fprintf(fid, "\n## Final Checks\n\n");
fprintf(fid, "- Artifact required coverage: `%.2f%%`\n", double(sixgr.util.structGet(artifactCheck, "Coverage_pct", NaN)));
fprintf(fid, "- Required output coverage: `%.2f%%`\n", double(sixgr.util.structGet(artifactCheck, "RequiredOutputCoverage_pct", NaN)));
fprintf(fid, "- Base no-proxy scan issues: `%d`\n", double(sixgr.util.structGet(scan, "IssueCount", NaN)));
fprintf(fid, "- Supplemental no-proxy scan issues: `%d`\n", double(sixgr.util.structGet(supplementalScan, "IssueCount", NaN)));
end

function localAnnotateBaseArtifacts(layout, supplementalRoot, supplementalRelativeRoot)
localAnnotateRunManifest(layout.RunManifestJSON, supplementalRoot, supplementalRelativeRoot);
localAppendSupplementalNote(layout.CampaignReportMD, supplementalRelativeRoot);
end

function localAnnotateRunManifest(filePath, supplementalRoot, supplementalRelativeRoot)
if exist(filePath, "file") ~= 2
    return;
end
manifest = jsondecode(fileread(filePath));
manifest.SupplementalArtifactsGenerated = true;
manifest.SupplementalArtifactRoot = supplementalRoot;
manifest.SupplementalArtifactRootRelative = supplementalRelativeRoot;
manifest.SupplementalArtifactsCoLocated = false;
manifest.SupplementalArtifactSemantics = "wrapper_generated_not_part_of_base_campaign_execution";
manifest.SupplementalArtifactCategories = ["link","control","beamforming","harq","rf","reports"];
sixgr.util.jsonWrite(filePath, manifest);
end

function localAppendSupplementalNote(filePath, supplementalRelativeRoot)
if exist(filePath, "file") ~= 2
    return;
end
fid = fopen(filePath, "a");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "\n## Supplemental Wrapper Artifacts\n\n");
fprintf(fid, "- Base campaign scope remains `e2e_only`.\n");
fprintf(fid, "- Wrapper-generated waveform link/control artifacts were written under `%s`.\n", string(supplementalRelativeRoot));
fprintf(fid, "- These supplemental artifacts were not part of the base campaign execution counted by `OnlyE2E`, `LinkExecuted`, or `SystemExecuted`.\n");
fprintf(fid, "- Primary artifacts in the base run root remain E2E-only.\n");
end

function root = localRepoRoot()
root = fileparts(mfilename("fullpath"));
end

function nSlots = localRequiredTruthSlots(cfg, duration_s)
scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
mu = log2(scs/15);
if ~isfinite(mu) || mu < 0
    mu = 0;
end
slotDur_s = 1e-3 / (2^mu);
nSlots = max(24, ceil(double(duration_s) / max(slotDur_s, eps)));
end

function s = localUtcStamp()
t = datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd HH:mm:ss");
s = char(string(t) + "Z");
end
