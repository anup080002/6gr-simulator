function ok = testPrompt4HARQClosedLoopIRCombining()
%TESTPROMPT4HARQCLOSEDLOOPIRCOMBINING Validate closed-loop IR HARQ wiring.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
if ~localHaveRequired5G()
    warning("testPrompt4HARQClosedLoopIRCombining:Missing5G", ...
        "Skipping HARQ closed-loop IR test because required 5G Toolbox APIs are unavailable.");
    ok = true;
    return;
end

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

localAssertMasterScenarioHARQ(tmp);
localAssertCanonicalCombiningGain();
localAssertClosedLoopDiagnostics(tmp);

ok = true;
end

function localAssertMasterScenarioHARQ(tmp)
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "master_scenaio_all_file.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
s = scfg.toStruct();
assert(string(sixgr.util.structGet(s, "harq.validation_mode", "")) == "closed_loop", ...
    "Master scenario must request closed-loop HARQ validation.");
assert(logical(sixgr.util.structGet(s, "harq.save_harq_buffers", false)), ...
    "Master scenario must save HARQ soft buffers for closed-loop IR evidence.");
assert(string(sixgr.util.structGet(s, "harq.stop_condition", "")) == "crc_pass_or_max_retx", ...
    "Master scenario must stop HARQ probes on CRC pass or max retransmission.");

cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "master"));
assert(string(sixgr.util.structGet(cfg, "phy.harq.validationMode", "")) == "closed_loop", ...
    "buildInternalConfig must preserve closed_loop HARQ mode.");
assert(logical(sixgr.util.structGet(cfg, "phy.harq.saveBuffers", false)) && ...
    logical(sixgr.util.structGet(cfg, "mac.harq.saveBuffers", false)), ...
    "buildInternalConfig must map save_harq_buffers into PHY and MAC HARQ namespaces.");
assert(string(sixgr.util.structGet(cfg, "phy.harq.stopCondition", "")) == "crc_pass_or_max_retx" && ...
    string(sixgr.util.structGet(cfg, "mac.harq.stopCondition", "")) == "crc_pass_or_max_retx", ...
    "buildInternalConfig must map the configured HARQ stop condition into PHY and MAC namespaces.");
end

function localAssertCanonicalCombiningGain()
base = struct("A", 8448, "R", 0.48, "Modulation", "16QAM", ...
    "NumLayers", 2, "Direction", "DL");
layout0 = localLayout(base, 0);
layout3 = localLayout(base, 3);
cur0 = localObservation(layout0, 1.25);
[~, info0] = sixgr.phy.harq.combineSoftLLR(cur0, [], "CurrentLayout", layout0);
cur3 = localObservation(layout3, -0.75);
[~, info3] = sixgr.phy.harq.combineSoftLLR(cur3, info0.SoftBuffer, "CurrentLayout", layout3);
assert(logical(info3.Applied) && logical(info3.PositionAware), ...
    "HARQ IR combining must use the canonical position-aware soft buffer.");
assert(isfinite(double(info3.LLRCombiningGain_dB)), ...
    "Canonical HARQ IR combining must report finite LLRCombiningGain_dB evidence.");
assert(double(info3.OverlapPositionCount) >= 0, ...
    "Canonical HARQ IR combining must report the mother-code position overlap count.");
end

function localAssertClosedLoopDiagnostics(tmp)
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_harq_retransmission_exercise.yaml");
scfgBase = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
data = scfgBase.toStruct();
data = sixgr.util.structSet(data, "meta.scenario_id", "PROMPT4_HARQ_CLOSED_LOOP_REGRESSION");
data = sixgr.util.structSet(data, "harq.validation_mode", "closed_loop");
data = sixgr.util.structSet(data, "harq.save_harq_buffers", true);
data = sixgr.util.structSet(data, "harq.stop_condition", "crc_pass_or_max_retx");
scfg = sixgr.lls6g.config.ScenarioConfig(data, ...
    "SourceFiles", scfgBase.SourceFiles, ...
    "ConfigPath", scfgBase.ConfigPath, ...
    "ConfigHash", "prompt4_harq_closed_loop_regression");
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "closed_loop"));

opt = struct();
opt.LinkSNR_dB = double(cfg.channel.snr_dB);
opt.LinkSNRGrid_dB = double(cfg.channel.snr_dB);
opt.LinkSweepFrames = 1;
opt.LinkSweepMaxPoints = 1;
opt.HARQLivePreview = true;
artifacts = sixgr.truth.exportLLSHARQDiagnostics(cfg, fullfile(tmp, "closed_loop", "air_interface"), opt);
packetT = artifacts.PacketTable;
summaryT = artifacts.SummaryTable;
assert(~isempty(packetT) && ~isempty(summaryT), ...
    "Closed-loop HARQ diagnostics must emit packet and summary tables.");
assert(all(string(packetT.ProbeMode) == "closed_loop"), ...
    "Closed-loop HARQ diagnostics must not be downgraded to observation mode.");
assert(all(string(summaryT.Mode) == "closed_loop"), ...
    "Closed-loop HARQ summary rows must retain closed-loop mode.");
assert(all(ismember(["HARQCombiningApplied","HARQSoftCombiningPositionAware", ...
    "HARQSoftCombiningOverlapPositionCount","LLRCombiningGain_dB"], string(packetT.Properties.VariableNames))), ...
    "Closed-loop HARQ packet CSV must expose canonical soft-combining evidence columns.");
terminalStops = string(packetT.StopCondition);
terminalStops = terminalStops(terminalStops ~= "pending" & terminalStops ~= "");
assert(~isempty(terminalStops) && all(ismember(terminalStops, ["crc_pass","max_retx_drop"])), ...
    "Closed-loop HARQ terminal stop conditions must be CRC pass or max retransmission drop.");
assert(any(string(summaryT.MetricKey) == "combining_gain" & string(summaryT.Statistic) == "mean_llr_gain_dB"), ...
    "Closed-loop HARQ summary must include numerical LLR combining gain evidence.");
end

function layout = localLayout(cfg, rv)
qm = 4;
quantum = qm * cfg.NumLayers;
E = ceil((cfg.A + 24) / cfg.R);
E = max(quantum, ceil(E / quantum) * quantum);
layout = sixgr.phy.phycode.resolveCodingLayout( ...
    "Direction", cfg.Direction, ...
    "TransportBlockSize", cfg.A, ...
    "TargetCodeRate", cfg.R, ...
    "RV", rv, ...
    "Modulation", cfg.Modulation, ...
    "NumLayers", cfg.NumLayers, ...
    "RateMatchedBitCount", E);
end

function rec = localObservation(layout, value)
rec = zeros(double(layout.MotherCodeLength), double(layout.NumCodeBlocks));
idx = double(layout.RateMatchPositionMap.MotherCodeLinearIndex(:));
idx = idx(isfinite(idx) & idx >= 1 & idx <= numel(rec));
rec(unique(round(idx), "stable")) = double(value);
end

function tf = localHaveRequired5G()
tf = exist("nrDLSCHInfo", "file") == 2 && ...
    exist("nrRateMatchLDPC", "file") == 2 && ...
    exist("nrRateRecoverLDPC", "file") == 2 && ...
    exist("nrLDPCEncode", "file") == 2;
end