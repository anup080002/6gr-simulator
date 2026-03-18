function out = run_full_2min_60cell_profile(varargin)
%RUN_FULL_2MIN_60CELL_PROFILE Heavy 120s campaign run + profiling package.
%
% This runner applies a high-load 60-cell mobility/handover scenario and
% exports detailed CPU/time/memory profiling artifacts under:
%   <runFolder>/profiling
%
% NOTE:
% - The current simulator architecture still uses abstraction/proxy paths in
%   some high-scale modes (especially when fast kernels are enabled).
% - This runner is intended for stress profiling and bottleneck discovery.

ip = inputParser;
ip.addParameter("ConfigFile", "config/suite_config.json", @(x)ischar(x)||isstring(x)||isstruct(x));
ip.addParameter("ResultsRoot", "results", @(x)ischar(x)||isstring(x));
ip.addParameter("Duration_s", 120, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter("E2EDuration_s", NaN, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter("NumSites", 20, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter("SectorsPerSite", 3, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter("SystemNumUE", 1200, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter("E2EUECount", 120, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter("LinkMaxSimFrames", 120, @(x)isnumeric(x)&&isscalar(x)&&x>=8);
ip.addParameter("E2EMaxSlots", 4000, @(x)isnumeric(x)&&isscalar(x)&&x>=100);
ip.addParameter("UseFastLinkModel", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("UseMexAcceleration", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("UseParallelAcceleration", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("AutoStartParallelPool", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("EnableStrictMode", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2EAirModel", "lut", @(x)ischar(x)||isstring(x));
ip.addParameter("E2ETruthMaxSlots", 20000, @(x)isnumeric(x)&&isscalar(x)&&x>=20);
ip.addParameter("E2ETruthFastAWGNPath", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2ETruthCompactPHYIO", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2ETruthAdaptiveLDPC", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("E2ETruthLDPCMaxIterations", 0, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter("E2ETruthUseGPU", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("CarrierSCS_kHz", 15, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter("EnableAllBlocks", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("FullBufferBitsPerTTI", 2e5, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter("TrafficTargetRate_Mbps", 0.2, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter("TrafficPacketInterval_ms", 10, @(x)isnumeric(x)&&isscalar(x)&&x>0);
ip.addParameter("RunAuxiliaryProbes", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("RunSystemMMTCProbe", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("GenerateCampaignPlots", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("SaveFigures", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("ProfileMemory", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("Verbose", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;
if ~isfinite(double(opt.E2EDuration_s))
    opt.E2EDuration_s = double(opt.Duration_s);
end

if builtin("isstruct", opt.ConfigFile) && isscalar(opt.ConfigFile)
    cfg = sixgr.util.mergeStruct(sixgr.config.defaultConfig(), opt.ConfigFile);
    cfg = sixgr.config.normalizeConfig(cfg);
    sixgr.config.validateConfig(cfg);
else
    cfg = sixgr_loadConfig(char(string(opt.ConfigFile)));
end

% -------------------------------------------------------------------------
% Requested heavy scenario settings
% -------------------------------------------------------------------------
cfg.run.shortRun = false;
cfg.run.strictMode = logical(opt.EnableStrictMode);
cfg.run.useMex = logical(opt.UseMexAcceleration);
cfg.run.useParallel = logical(opt.UseParallelAcceleration);
cfg.run.autoStartParallelPool = logical(opt.AutoStartParallelPool);
cfg.run.resultsRoot = char(string(opt.ResultsRoot));
cfg.phy.carrier.SubcarrierSpacing = double(opt.CarrierSCS_kHz);
cfg.phy.carrier.NSizeGrid = min(51, max(25, round(double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 51)))));

cfg.scenario.layout.nSites = max(1, round(double(opt.NumSites)));
cfg.scenario.layout.nSectorsPerSite = max(1, round(double(opt.SectorsPerSite)));
cfg.scenario.layout.type = "hex";
cfg.scenario.layout.wrapAround = true;
cfg.scenario.layout.interSiteDistance_m = 700;
cfg.scenario.mobility.enable = true;
cfg.scenario.mobility.model = "randomWaypoint";
cfg.scenario.mobility.speed_kmh = [30 120];
cfg.scenario.mobility.updatePeriod_s = 0.1;
cfg.scenario.ue.nUE = max(1, round(double(opt.SystemNumUE)));
cfg.scenario.nUE = cfg.scenario.ue.nUE;
cfg.system.handover.enable = true;
cfg.system.handover.a3Offset_dB = 2.0;
cfg.system.handover.hysteresis_dB = 0.5;
cfg.system.handover.timeToTrigger_slots = 4;
cfg.system.handover.interruptionSlots = 2;
cfg.system.beam.enable = true;
cfg.system.beam.updatePeriod_slots = 2;
cfg.system.measurement.periodSlots = 1;

cfg.traffic.model = "fullBuffer";
cfg.traffic.transport = "UDP";
cfg.traffic.flowDirection = "BIDIR";
cfg.traffic.dlRatio = 0.5;
cfg.traffic.ulRatio = 0.5;
cfg.traffic.fullBufferBitsPerTTI = double(opt.FullBufferBitsPerTTI);
cfg.traffic.targetRate_Mbps = double(opt.TrafficTargetRate_Mbps);
cfg.traffic.packetInterval_ms = double(opt.TrafficPacketInterval_ms);
cfg.traffic.packetDelayBudget_ms = 20;

cfg.channel.interference.enable = true;
cfg.channel.fading.enable = true;
cfg.channel.fading.model = "TDL";
cfg.channel.fading.profile = "TDL-C";
cfg.channel.fading.maxDoppler_Hz = 300;
cfg.channel.model = "TDL-C";
cfg.channel.dopplerHz = 300;
cfg.channel.doppler_Hz = 300;
cfg.channel.awgnOnly = false;
cfg.channel.rayTracing.enable = false;

cfg.rf.enable = true;
cfg.rf.iqImbalance.enable = true;
cfg.rf.iqImbalance.gainImbalance_dB = 1.0;
cfg.rf.iqImbalance.phaseImbalance_deg = 3.0;
cfg.rf.phaseNoise.enable = true;
cfg.rf.phaseNoise.level_dBcHz = -80;
cfg.rf.cfo_Hz = 120;
cfg.rf.dcOffset = 0.01 + 0.01i;

cfg.outputs.saveCSV = true;
cfg.outputs.saveMAT = true;
cfg.outputs.saveFigures = logical(opt.SaveFigures);
cfg.outputs.saveFIG = logical(opt.SaveFigures);

if logical(opt.EnableAllBlocks)
    cfg = localEnableAllPhyBlocks(cfg);
end
[cfg, blockEnableAudit] = localForceEnableBlockPaths(cfg, logical(opt.EnableAllBlocks));

% -------------------------------------------------------------------------
% Run with MATLAB profiler (time + memory)
% -------------------------------------------------------------------------
profile clear;
if logical(opt.ProfileMemory)
    profile on -memory;
else
    profile on;
end
t0 = tic;
memBefore = localMemorySnapshot();

report = sixgr_run_3gpp_full_campaign(cfg, ...
    "ResultsRoot", char(string(opt.ResultsRoot)), ...
    "LinkDuration_s", double(opt.Duration_s), ...
    "LinkMaxSimFrames", round(double(opt.LinkMaxSimFrames)), ...
    "LinkSaveFigures", logical(opt.SaveFigures), ...
    "SystemDuration_s", double(opt.Duration_s), ...
    "SystemNumUE", round(double(opt.SystemNumUE)), ...
    "SystemDetailedTrace", true, ...
    "SystemSaveFigures", logical(opt.SaveFigures), ...
    "RunSystemMMTCProbe", logical(opt.RunSystemMMTCProbe), ...
    "MMTCNumUE", max(100, round(double(opt.SystemNumUE) / 2)), ...
    "MMTCSaveFigures", logical(opt.SaveFigures), ...
    "RunAuxiliaryProbes", logical(opt.RunAuxiliaryProbes), ...
    "RunE2EStackProbe", true, ...
    "E2EDuration_s", double(opt.E2EDuration_s), ...
    "E2EUECount", round(double(opt.E2EUECount)), ...
    "E2EMaxSlots", round(double(opt.E2EMaxSlots)), ...
    "E2ETrafficModel", "fullbuffer", ...
    "E2EAirModel", char(string(opt.E2EAirModel)), ...
    "E2ETruthMaxSlots", round(double(opt.E2ETruthMaxSlots)), ...
    "E2ETruthFastAWGNPath", logical(opt.E2ETruthFastAWGNPath), ...
    "E2ETruthCompactPHYIO", logical(opt.E2ETruthCompactPHYIO), ...
    "E2ETruthAdaptiveLDPC", logical(opt.E2ETruthAdaptiveLDPC), ...
    "E2ETruthLDPCMaxIterations", round(double(opt.E2ETruthLDPCMaxIterations)), ...
    "E2ETruthUseGPU", logical(opt.E2ETruthUseGPU), ...
    "E2EFastTraceMode", "full", ...
    "E2EEnableAI", true, ...
    "E2ESaveFigures", logical(opt.SaveFigures), ...
    "E2EStrictValidation", logical(opt.EnableStrictMode), ...
    "E2EScaleServiceWithCompression", true, ...
    "UseFastLinkModel", logical(opt.UseFastLinkModel), ...
    "UseMexAcceleration", logical(opt.UseMexAcceleration), ...
    "UseParallelAcceleration", logical(opt.UseParallelAcceleration), ...
    "AutoStartParallelPool", logical(opt.AutoStartParallelPool), ...
    "AutoBuildMexAcceleration", false, ...
    "GenerateCampaignPlots", logical(opt.GenerateCampaignPlots), ...
    "VerifyArtifacts", true, ...
    "OrganizeByBlock", true, ...
    "MirrorStructuredResults", false, ...
    "SetupToolboxChecks", false, ...
    "Verbose", logical(opt.Verbose));

memAfter = localMemorySnapshot();
elapsed_s = toc(t0);
pinfo = profile("info");
profile off;

runFolder = char(string(sixgr.util.structGet(report, "RunFolder", "")));
if strlength(string(runFolder)) == 0 || ~isfolder(runFolder)
    error("sixgr:profile:NoRunFolder", "Run folder not found in report output.");
end
profDir = fullfile(runFolder, "profiling");
sixgr.util.ensureDir(profDir);

ft = localProfileFunctionTable(pinfo);
if ~isempty(ft)
    ft = sortrows(ft, "TotalTime_s", "descend");
end
topN = min(500, height(ft));
if topN > 0
    ftTop = ft(1:topN, :);
else
    ftTop = ft;
end
block = localProfileBlockTable(ft);
if ~isempty(block)
    block = sortrows(block, "TotalTime_s", "descend");
end

sixgr.util.csvWriteTable(fullfile(profDir, "function_profile_all.csv"), ft);
sixgr.util.csvWriteTable(fullfile(profDir, "function_profile_top500.csv"), ftTop);
sixgr.util.csvWriteTable(fullfile(profDir, "block_profile.csv"), block);

zoneSummary = localBuildRFZoneSummary(runFolder);
hoSummary = localBuildHandoverSummary(runFolder);
prbUtil = localBuildPRBUtilizationSummary(runFolder, cfg);
flowSummary = localBuildFlowDirectionSummary(runFolder);
sixgr.util.csvWriteTable(fullfile(profDir, "rf_zone_summary.csv"), zoneSummary);
sixgr.util.csvWriteTable(fullfile(profDir, "handover_summary.csv"), hoSummary);
sixgr.util.csvWriteTable(fullfile(profDir, "prb_utilization_summary.csv"), prbUtil);
sixgr.util.csvWriteTable(fullfile(profDir, "flow_direction_summary.csv"), flowSummary);
sixgr.util.csvWriteTable(fullfile(profDir, "block_enable_audit.csv"), blockEnableAudit);

sixgr.util.matSave(fullfile(profDir, "profiler_raw.mat"), struct( ...
    "profileInfo", pinfo, ...
    "report", report, ...
    "memoryBefore", memBefore, ...
    "memoryAfter", memAfter, ...
    "elapsed_s", elapsed_s, ...
    "blockEnableAudit", blockEnableAudit));

runMeta = struct();
runMeta.GeneratedUTC = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
runMeta.RunFolder = runFolder;
runMeta.DurationRequested_s = double(opt.Duration_s);
runMeta.E2EDurationRequested_s = double(opt.E2EDuration_s);
runMeta.NumSites = double(cfg.scenario.layout.nSites);
runMeta.SectorsPerSite = double(cfg.scenario.layout.nSectorsPerSite);
runMeta.TotalCells = double(cfg.scenario.layout.nSites) * double(cfg.scenario.layout.nSectorsPerSite);
runMeta.SystemNumUE = double(opt.SystemNumUE);
runMeta.E2EUECount = double(opt.E2EUECount);
runMeta.TrafficModel = char(string(cfg.traffic.model));
runMeta.FlowDirection = char(string(cfg.traffic.flowDirection));
runMeta.DLRatio = double(cfg.traffic.dlRatio);
runMeta.ULRatio = double(cfg.traffic.ulRatio);
runMeta.FullBufferBitsPerTTI = double(cfg.traffic.fullBufferBitsPerTTI);
runMeta.UseFastLinkModel = logical(opt.UseFastLinkModel);
runMeta.UseMexAcceleration = logical(opt.UseMexAcceleration);
runMeta.UseParallelAcceleration = logical(opt.UseParallelAcceleration);
runMeta.AutoStartParallelPool = logical(opt.AutoStartParallelPool);
runMeta.EnableStrictMode = logical(opt.EnableStrictMode);
runMeta.E2EAirModel = char(string(opt.E2EAirModel));
runMeta.E2ETruthMaxSlots = double(opt.E2ETruthMaxSlots);
runMeta.E2ETruthFastAWGNPath = logical(opt.E2ETruthFastAWGNPath);
runMeta.E2ETruthCompactPHYIO = logical(opt.E2ETruthCompactPHYIO);
runMeta.E2ETruthAdaptiveLDPC = logical(opt.E2ETruthAdaptiveLDPC);
runMeta.E2ETruthLDPCMaxIterations = double(opt.E2ETruthLDPCMaxIterations);
runMeta.E2ETruthUseGPU = logical(opt.E2ETruthUseGPU);
runMeta.E2EFastTraceMode = "full";
runMeta.CarrierSCS_kHz = double(opt.CarrierSCS_kHz);
runMeta.EnableAllBlocks = logical(opt.EnableAllBlocks);
runMeta.SaveFigures = logical(opt.SaveFigures);
runMeta.ElapsedWallClock_s = double(elapsed_s);
runMeta.MemoryBefore = memBefore;
runMeta.MemoryAfter = memAfter;
runMeta.ProfileArtifacts = struct( ...
    "FunctionProfileCSV", fullfile(profDir, "function_profile_all.csv"), ...
    "FunctionTopCSV", fullfile(profDir, "function_profile_top500.csv"), ...
    "BlockProfileCSV", fullfile(profDir, "block_profile.csv"), ...
    "RFZoneCSV", fullfile(profDir, "rf_zone_summary.csv"), ...
    "HandoverCSV", fullfile(profDir, "handover_summary.csv"), ...
    "PRBUtilCSV", fullfile(profDir, "prb_utilization_summary.csv"), ...
    "FlowSummaryCSV", fullfile(profDir, "flow_direction_summary.csv"), ...
    "BlockEnableAuditCSV", fullfile(profDir, "block_enable_audit.csv"), ...
    "ProfilerRawMAT", fullfile(profDir, "profiler_raw.mat"));
runMeta.Notes = [ ...
    "This is a heavy non-smoke stress run for profiling.", ...
    "When strict mode is false and MEX fast kernels are enabled, some modules use proxy execution backends.", ...
    "Use strict mode + truth air model for highest fidelity at significantly higher runtime."];
runMeta.ProfileMemoryEnabled = logical(opt.ProfileMemory);
sixgr.util.jsonWrite(fullfile(profDir, "run_profile_summary.json"), runMeta);

out = struct();
out.Ok = logical(sixgr.util.structGet(report, "Ok", false));
out.RunFolder = runFolder;
out.ProfilingFolder = profDir;
out.Report = report;
out.FunctionProfileCSV = fullfile(profDir, "function_profile_all.csv");
out.BlockProfileCSV = fullfile(profDir, "block_profile.csv");
out.RunProfileSummaryJSON = fullfile(profDir, "run_profile_summary.json");
end

function m = localMemorySnapshot()
m = struct();
m.Available = false;
m.MemAvailableAllArrays_bytes = NaN;
m.MemUsedMATLAB_bytes = NaN;
m.MaxPossibleArrayBytes = NaN;
try
    mm = memory();
    m.Available = true;
    m.MemAvailableAllArrays_bytes = double(sixgr.util.structGet(mm, "MemAvailableAllArrays", NaN));
    m.MemUsedMATLAB_bytes = double(sixgr.util.structGet(mm, "MemUsedMATLAB", NaN));
    m.MaxPossibleArrayBytes = double(sixgr.util.structGet(mm, "MaxPossibleArrayBytes", NaN));
catch
end
end

function cfg = localEnableAllPhyBlocks(cfg)
% Keep both lowercase/uppercase variants because existing modules read both.
cfg.phy.ssb.enable = true;
cfg.phy.ssb.Enable = true;
cfg.phy.pdcch.enable = true;
cfg.phy.pdcch.Enable = true;
cfg.phy.pucch.enable = true;
cfg.phy.pucch.Enable = true;
cfg.phy.prach.enable = true;
cfg.phy.prach.Enable = true;
cfg.phy.srs.enable = true;
cfg.phy.srs.Enable = true;

if ~isfield(cfg.phy, "dl") || ~isstruct(cfg.phy.dl)
    cfg.phy.dl = struct();
end
if ~isfield(cfg.phy, "ul") || ~isstruct(cfg.phy.ul)
    cfg.phy.ul = struct();
end
if ~isfield(cfg.phy.dl, "pdcch") || ~isstruct(cfg.phy.dl.pdcch)
    cfg.phy.dl.pdcch = struct();
end
if ~isfield(cfg.phy.ul, "pucch") || ~isstruct(cfg.phy.ul.pucch)
    cfg.phy.ul.pucch = struct();
end
if ~isfield(cfg.phy.ul, "prach") || ~isstruct(cfg.phy.ul.prach)
    cfg.phy.ul.prach = struct();
end
if ~isfield(cfg.phy.ul, "srs") || ~isstruct(cfg.phy.ul.srs)
    cfg.phy.ul.srs = struct();
end
cfg.phy.dl.pdcch.enable = true;
cfg.phy.dl.pdcch.Enable = true;
cfg.phy.ul.pucch.enable = true;
cfg.phy.ul.pucch.Enable = true;
cfg.phy.ul.prach.enable = true;
cfg.phy.ul.prach.Enable = true;
cfg.phy.ul.srs.enable = true;
cfg.phy.ul.srs.Enable = true;
end

function [cfg, T] = localForceEnableBlockPaths(cfg, forceOn)
paths = [ ...
    "phy.ssb.enable"; "phy.ssb.Enable"; ...
    "phy.pbch.enable"; "phy.pbch.Enable"; ...
    "phy.pdsch.enable"; "phy.pdsch.Enable"; ...
    "phy.pusch.enable"; "phy.pusch.Enable"; ...
    "phy.prach.enable"; "phy.prach.Enable"; ...
    "phy.ul.prach.enable"; "phy.ul.prach.Enable"; ...
    "phy.pdcch.enable"; "phy.pdcch.Enable"; ...
    "phy.dl.pdcch.enable"; "phy.dl.pdcch.Enable"; ...
    "phy.pucch.enable"; "phy.pucch.Enable"; ...
    "phy.ul.pucch.enable"; "phy.ul.pucch.Enable"; ...
    "phy.srs.enable"; "phy.srs.Enable"; ...
    "phy.ul.srs.enable"; "phy.ul.srs.Enable"; ...
    "outputs.saveCSV"; "outputs.saveMAT"];

n = numel(paths);
Path = strings(n,1);
Before = false(n,1);
After = false(n,1);
Forced = false(n,1);
for i = 1:n
    p = char(paths(i));
    b = logical(sixgr.util.structGet(cfg, p, false));
    if forceOn
        cfg = sixgr.util.structSet(cfg, p, true);
        a = logical(sixgr.util.structGet(cfg, p, false));
        f = (~b) && a;
    else
        a = b;
        f = false;
    end
    Path(i) = string(p);
    Before(i) = b;
    After(i) = a;
    Forced(i) = f;
end
T = table(Path, Before, After, Forced);
end

function T = localProfileFunctionTable(pinfo)
vars = {'Function','CompleteName','FileName','Block','NumCalls','TotalTime_s','CPU_pct','TotalMemAllocated_B','TotalMemFreed_B','PeakMem_B'};
if ~isstruct(pinfo) || ~isfield(pinfo, "FunctionTable") || isempty(pinfo.FunctionTable)
    T = table(string.empty(0,1), string.empty(0,1), string.empty(0,1), string.empty(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        'VariableNames', vars);
    return;
end

F = pinfo.FunctionTable;
n = numel(F);
rows = repmat(struct("Function","","CompleteName","","FileName","","Block","", ...
    "NumCalls",0,"TotalTime_s",0,"CPU_pct",0,"TotalMemAllocated_B",0,"TotalMemFreed_B",0,"PeakMem_B",0), n, 1);
tot = 0;
for i = 1:n
    tot = tot + double(sixgr.util.structGet(F(i), "TotalTime", 0));
end
tot = max(tot, eps);

for i = 1:n
    comp = string(sixgr.util.structGet(F(i), "CompleteName", ""));
    fname = string(sixgr.util.structGet(F(i), "FunctionName", ""));
    fpath = string(sixgr.util.structGet(F(i), "FileName", ""));
    t = double(sixgr.util.structGet(F(i), "TotalTime", 0));
    rows(i).Function = fname;
    rows(i).CompleteName = comp;
    rows(i).FileName = fpath;
    rows(i).Block = localProfileBlockName(comp, fpath);
    rows(i).NumCalls = double(sixgr.util.structGet(F(i), "NumCalls", 0));
    rows(i).TotalTime_s = t;
    rows(i).CPU_pct = 100 * t / tot;
    rows(i).TotalMemAllocated_B = double(sixgr.util.structGet(F(i), "TotalMemAllocated", 0));
    rows(i).TotalMemFreed_B = double(sixgr.util.structGet(F(i), "TotalMemFreed", 0));
    rows(i).PeakMem_B = double(sixgr.util.structGet(F(i), "PeakMem", 0));
end

T = struct2table(rows);
T.Function = string(T.Function);
T.CompleteName = string(T.CompleteName);
T.FileName = string(T.FileName);
T.Block = string(T.Block);
end

function b = localProfileBlockName(completeName, fileName)
s = lower(char(string(completeName) + " " + string(fileName)));
if contains(s, "sixgr.link.")
    b = "LLS";
elseif contains(s, "sixgr.system.")
    b = "SLS";
elseif contains(s, "sixgr.l2.") || contains(s, "sixgr.l3.")
    b = "E2E_L2L3";
elseif contains(s, "sixgr.phy.")
    b = "PHY";
elseif contains(s, "sixgr.hybrid.") || contains(s, "calibratebler")
    b = "Calibration";
elseif contains(s, "organizerunresults") || contains(s, "sixgr.report.")
    b = "Reporting";
elseif contains(s, "sixgr_run_3gpp_full_campaign")
    b = "CampaignOrchestrator";
else
    b = "Other";
end
b = string(b);
end

function T = localProfileBlockTable(ft)
vars = {'Block','NumFunctions','TotalCalls','TotalTime_s','CPU_pct','TotalMemAllocated_B','TotalMemFreed_B','MaxPeakMem_B'};
if isempty(ft)
    T = table(string.empty(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        'VariableNames', vars);
    return;
end
tot = max(sum(double(ft.TotalTime_s)), eps);
[g, blk] = findgroups(string(ft.Block));
numFuncs = splitapply(@numel, ft.Block, g);
calls = splitapply(@sum, double(ft.NumCalls), g);
t = splitapply(@sum, double(ft.TotalTime_s), g);
cpu = 100 * t / tot;
ma = splitapply(@sum, double(ft.TotalMemAllocated_B), g);
mf = splitapply(@sum, double(ft.TotalMemFreed_B), g);
pk = splitapply(@max, double(ft.PeakMem_B), g);
T = table(blk, numFuncs, calls, t, cpu, ma, mf, pk, 'VariableNames', vars);
end

function T = localBuildRFZoneSummary(runFolder)
f = fullfile(runFolder, "system", "csv", "system_interference_detail.csv");
vars = {'Zone','NumUE','NumSamples','MeanRSRP_dBm','MeanSINR_DL_dB','MeanSINR_UL_dB','P05SINR_DL_dB','P50SINR_DL_dB','P95SINR_DL_dB'};
if exist(f, "file") ~= 2
    T = localEmptyTable(vars);
    return;
end
try
    X = readtable(f, "VariableNamingRule", "preserve");
catch
    T = localEmptyTable(vars);
    return;
end
if isempty(X) || ~all(ismember(["UE","RSRP_dBm","SINR_DL_dB","SINR_UL_dB"], string(X.Properties.VariableNames)))
    T = localEmptyTable(vars);
    return;
end
X.UE = double(X.UE);
X.RSRP_dBm = double(X.RSRP_dBm);
X.SINR_DL_dB = double(X.SINR_DL_dB);
X.SINR_UL_dB = double(X.SINR_UL_dB);
[g, ue] = findgroups(X.UE);
rsrpUE = splitapply(@(v) mean(v, "omitnan"), X.RSRP_dBm, g);
sinrDL_UE = splitapply(@(v) mean(v, "omitnan"), X.SINR_DL_dB, g);
sinrUL_UE = splitapply(@(v) mean(v, "omitnan"), X.SINR_UL_dB, g);
samplesUE = splitapply(@numel, X.UE, g);

q33 = localPercentile(rsrpUE, 33.3333);
q66 = localPercentile(rsrpUE, 66.6667);
zoneUE = strings(numel(ue),1);
for i = 1:numel(ue)
    if rsrpUE(i) <= q33
        zoneUE(i) = "edge";
    elseif rsrpUE(i) <= q66
        zoneUE(i) = "mid";
    else
        zoneUE(i) = "center";
    end
end

zones = ["edge";"mid";"center"];
nz = numel(zones);
zName = strings(nz,1);
zNumUE = zeros(nz,1);
zSamples = zeros(nz,1);
zRSRP = NaN(nz,1);
zSINRDL = NaN(nz,1);
zSINRUL = NaN(nz,1);
zP05 = NaN(nz,1);
zP50 = NaN(nz,1);
zP95 = NaN(nz,1);
for i = 1:nz
    z = zones(i);
    idxUE = zoneUE == z;
    zName(i) = z;
    zNumUE(i) = sum(idxUE);
    zSamples(i) = sum(samplesUE(idxUE));
    zRSRP(i) = mean(rsrpUE(idxUE), "omitnan");
    zSINRDL(i) = mean(sinrDL_UE(idxUE), "omitnan");
    zSINRUL(i) = mean(sinrUL_UE(idxUE), "omitnan");
    vals = sinrDL_UE(idxUE);
    zP05(i) = localPercentile(vals, 5);
    zP50(i) = localPercentile(vals, 50);
    zP95(i) = localPercentile(vals, 95);
end
T = table(zName, zNumUE, zSamples, zRSRP, zSINRDL, zSINRUL, zP05, zP50, zP95, 'VariableNames', vars);
end

function T = localBuildHandoverSummary(runFolder)
f = fullfile(runFolder, "system", "csv", "system_handover_events.csv");
vars = {'Metric','Value'};
if exist(f, "file") ~= 2
    T = localEmptyKV(vars);
    return;
end
try
    X = readtable(f, "VariableNamingRule", "preserve");
catch
    T = localEmptyKV(vars);
    return;
end
if isempty(X)
    T = localEmptyKV(vars);
    return;
end
status = strings(height(X),1);
if ismember("Status", string(X.Properties.VariableNames))
    status = lower(string(X.Status));
end
triggered = height(X);
completed = sum(status == "completed");
startCol = localNumericColumn(X, "StartTime_s", NaN(height(X),1));
if all(~isfinite(startCol))
    startCol = localNumericColumn(X, "StartTTI", NaN(height(X),1));
end
started = sum(isfinite(startCol));
failed = sum(status == "failed" | status == "aborted");
interruption = localNumericColumn(X, "InterruptionDuration_ms", NaN(height(X),1));
if all(~isfinite(interruption))
    interruption = localNumericColumn(X, "Interruption_ms", NaN(height(X),1));
end
T = table(["Triggered";"Started";"Completed";"Failed";"CompletionRate_pct";"MeanInterruption_ms";"P95Interruption_ms"], ...
    [triggered; started; completed; failed; 100*completed/max(triggered,1); mean(interruption, "omitnan"); localPercentile(interruption,95)], ...
    'VariableNames', vars);
end

function T = localBuildPRBUtilizationSummary(runFolder, cfg)
f = fullfile(runFolder, "system", "csv", "system_scheduler_grants.csv");
vars = {'Direction','MeanPRBUtilization_pct','P95PRBUtilization_pct','MaxPRBUtilization_pct','NumCellSlots'};
if exist(f, "file") ~= 2
    T = localEmptyTable(vars);
    return;
end
try
    G = readtable(f, "VariableNamingRule", "preserve");
catch
    T = localEmptyTable(vars);
    return;
end
if isempty(G) || ~all(ismember(["TTI","CellID","Direction","PRBCount"], string(G.Properties.VariableNames)))
    T = localEmptyTable(vars);
    return;
end
nRB = max(1, round(double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 51))));
G.TTI = round(double(G.TTI));
G.CellID = round(double(G.CellID));
G.PRBCount = double(G.PRBCount);
G.Direction = upper(string(G.Direction));

dirs = ["DL";"UL"];
nd = numel(dirs);
dName = strings(nd,1);
meanU = NaN(nd,1);
p95U = NaN(nd,1);
maxU = NaN(nd,1);
nRows = zeros(nd,1);
for i = 1:nd
    d = dirs(i);
    X = G(G.Direction == d, :);
    dName(i) = d;
    if isempty(X)
        continue;
    end
    [g, ttiK, cellK] = findgroups(X.TTI, X.CellID); %#ok<ASGLU>
    prb = splitapply(@sum, X.PRBCount, g);
    utilPct = 100 * min(max(prb / max(nRB,1), 0), 1);
    meanU(i) = mean(utilPct, "omitnan");
    p95U(i) = localPercentile(utilPct, 95);
    maxU(i) = max(utilPct);
    nRows(i) = numel(utilPct);
end
T = table(dName, meanU, p95U, maxU, nRows, 'VariableNames', vars);
end

function T = localBuildFlowDirectionSummary(runFolder)
f = fullfile(runFolder, "csv", "probe_e2e_summary.csv");
vars = {'Metric','Value'};
if exist(f, "file") ~= 2
    T = localEmptyKV(vars);
    return;
end
try
    E = readtable(f, "VariableNamingRule", "preserve");
catch
    T = localEmptyKV(vars);
    return;
end
if isempty(E)
    T = localEmptyKV(vars);
    return;
end
offDL = localNumericScalar(E, "OfferedDL_Mbps", NaN);
offUL = localNumericScalar(E, "OfferedUL_Mbps", NaN);
goodDL = localNumericScalar(E, "GoodputDL_Mbps", NaN);
goodUL = localNumericScalar(E, "GoodputUL_Mbps", NaN);
delDL = localNumericScalar(E, "DeliveryRatioDL", NaN);
delUL = localNumericScalar(E, "DeliveryRatioUL", NaN);
T = table(["OfferedDL_Mbps";"OfferedUL_Mbps";"GoodputDL_Mbps";"GoodputUL_Mbps";"DeliveryRatioDL";"DeliveryRatioUL"], ...
    [offDL; offUL; goodDL; goodUL; delDL; delUL], 'VariableNames', vars);
end

function T = localEmptyTable(vars)
n = numel(vars);
cols = cell(1,n);
for i = 1:n
    if i == 1
        cols{i} = strings(0,1);
    else
        cols{i} = zeros(0,1);
    end
end
T = table(cols{:}, 'VariableNames', vars);
end

function T = localEmptyKV(vars)
T = table(strings(0,1), zeros(0,1), 'VariableNames', vars);
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

function v = localNumericColumn(T, name, fallback)
if ismember(name, string(T.Properties.VariableNames))
    try
        v = double(T.(name));
        return;
    catch
    end
end
v = double(fallback);
end

function v = localNumericScalar(T, name, def)
if ismember(name, string(T.Properties.VariableNames)) && ~isempty(T)
    try
        v = double(T.(name)(1));
        return;
    catch
    end
end
v = double(def);
end
