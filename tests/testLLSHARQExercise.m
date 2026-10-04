function ok = testLLSHARQExercise()
%TESTLLSHARQEXERCISE Validate the stressed HARQ exercise preset and outputs.

setup6GRSimToolkit("Verbose", false);

% Preserve real failed/recovered packet evidence for failure reconciliation.
tmp = fullfile(pwd, "results", "lls", "harq_exercise", ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(tmp);
fprintf('HARQ_EXERCISE_RUN_FOLDER=%s\n',tmp);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_harq_retransmission_exercise.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
cfg = sixgr.util.structSet(cfg, "phy.pdsch.nLayers", 1);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.numLayers", 1);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.precoding.matrix", ones(64, 2) ./ sqrt(64));
cfg = sixgr.util.structSet(cfg, "phy.pdsch.pmi", NaN);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.tpmi", NaN);
localAssertHARQTimingReachesScheduler(scfg, tmp);

assert(logical(sixgr.util.structGet(cfg, "phy.harq.enable", false)), ...
    "HARQ exercise preset must keep HARQ enabled.");
assert(string(sixgr.util.structGet(cfg, "phy.harq.validationMode", "")) == "exercise", ...
    "HARQ exercise preset must map validation_mode into the internal config.");
assert(double(sixgr.util.structGet(cfg, "mac.harq.maxRetx", NaN)) == 3, ...
    "HARQ exercise preset must map max_retx into the internal config.");

snrOffsets = double(scfg.get("simulation.snr_sweep_offsets_db"));
if isempty(snrOffsets)
    snrOffsets = 0;
end
snrGrid = double(cfg.channel.snr_dB) + reshape(snrOffsets, 1, []);
opt = struct();
opt.LinkSNR_dB = double(cfg.channel.snr_dB);
opt.LinkSNRGrid_dB = snrGrid;
opt.LinkSweepFrames = max(1, round(double(scfg.get("simulation.monte_carlo_iterations"))));
opt.LinkSweepMaxPoints = numel(snrGrid);
opt.HARQProbeDirections = ["DL"; "UL"];
opt.HARQProbePackets = 2;

artifacts = sixgr.truth.exportLLSHARQDiagnostics(cfg, fullfile(tmp, "run", "air_interface"), opt);
packetPath = fullfile(tmp, "run", "harq", "csv", "probe_harq_packets.csv");
summaryPath = fullfile(tmp, "run", "harq", "csv", "probe_harq_summary.csv");
assert(exist(packetPath, "file") == 2, ...
    "HARQ exercise probe must write the raw packet table.");
assert(exist(summaryPath, "file") == 2, ...
    "HARQ exercise probe must write the raw summary table.");

packetT = readtable(packetPath, "VariableNamingRule", "preserve");
summaryT = readtable(summaryPath, "VariableNamingRule", "preserve");
assert(~isempty(artifacts.PacketTable) && ~isempty(artifacts.SummaryTable), ...
    "HARQ exercise probe must return in-memory packet and summary tables.");
assert(~isempty(packetT), "HARQ exercise packet table must not be empty.");
assert(~isempty(summaryT), "HARQ exercise summary table must not be empty.");
assert(all(string(packetT.ProbeMode) == "exercise"), ...
    "HARQ exercise packet table must carry exercise-mode semantics explicitly.");
assert(all(string(summaryT.Mode) == "exercise"), ...
    "HARQ exercise summary table must carry exercise-mode semantics explicitly.");
assert(any(logical(packetT.IsRetransmission)), ...
    "HARQ exercise preset must trigger real retransmission attempts.");
assert(any(logical(packetT.RecoveryAfterRetx)), ...
    "HARQ exercise preset must recover at least one packet after retransmission.");

combiningMask = string(summaryT.MetricKey) == "combining_gain" & ...
    string(summaryT.Statistic) == "recovered_after_retx_rate";
harqGainMask = string(summaryT.MetricKey) == "harq_gain_per_retransmission" & ...
    string(summaryT.Statistic) == "recovered_after_retx_rate";
assert(any(combiningMask), "HARQ exercise summary must emit combining-gain rows.");
assert(any(harqGainMask), "HARQ exercise summary must emit HARQ gain-per-retransmission rows.");
assert(any(combiningMask & string(summaryT.Availability) == "available"), ...
    "HARQ exercise summary must mark combining gain available once retransmissions occur.");
assert(any(harqGainMask & string(summaryT.Availability) == "available"), ...
    "HARQ exercise summary must mark HARQ gain per retransmission available once retransmissions occur.");
assert(any(combiningMask & string(summaryT.Availability) == "available" & double(summaryT.Value) > 0), ...
    "HARQ exercise summary must show non-zero combining recovery from real retransmissions.");
assert(any(harqGainMask & string(summaryT.Availability) == "available" & double(summaryT.Value) > 0), ...
    "HARQ exercise summary must show non-zero HARQ gain per retransmission from real retransmissions.");

ackStats = string(summaryT.Statistic(string(summaryT.MetricKey) == "ack_nack_dtx_distribution"));
assert(all(ismember(["first_attempt_ack_rate","first_attempt_nack_rate","final_ack_rate","final_nack_rate","dtx_rate"], ackStats)), ...
    "HARQ exercise summary must export first-attempt and final ACK/NACK statistics explicitly.");

ok = true;
end

function localAssertHARQTimingReachesScheduler(scfg, tmp)
data = scfg.toStruct();
data = sixgr.util.structSet(data, "meta.scenario_id", "HARQ_TIMING_REGRESSION");
data = sixgr.util.structSet(data, "harq.feedback_timing_slots", 2);
% A selected K1 must also exist in the installed DCI candidate list. Keep
% the rejection check below; changing a scalar alone is not an RRC update.
data = sixgr.util.structSet(data, "tdd_timing.dl_harq_feedback_k1", 2);
data = sixgr.util.structSet(data, "harq.k2", 3);
data = sixgr.util.structSet(data, "tdd_timing.ul_grant_k2", 3);
data = sixgr.util.structSet(data, "tdd_timing.pdcch_to_pusch_k2", 3);
scfgTiming = sixgr.lls6g.config.ScenarioConfig(data, ...
    "SourceFiles", scfg.SourceFiles, ...
    "ConfigPath", scfg.ConfigPath, ...
    "ConfigHash", "harq_timing_regression");
cfgTiming = sixgr.lls6g.buildInternalConfig(scfgTiming, fullfile(tmp, "timing_run"));

invalidData = sixgr.util.structSet(data, "tdd_timing.dl_harq_feedback_k1", 4);
invalidScenario = sixgr.lls6g.config.ScenarioConfig(invalidData, ...
    "SourceFiles", scfg.SourceFiles, "ConfigPath", scfg.ConfigPath, ...
    "ConfigHash", "harq_timing_invalid_candidate_regression");
rejected = false;
try
    sixgr.lls6g.buildInternalConfig(invalidScenario, fullfile(tmp, "invalid_timing"));
catch timingError
    assert(string(timingError.identifier) == ...
        "sixgr:lls6g:config:SelectedK1OutsideCandidateSet", ...
        'Unexpected failure for an uninstalled K1: %s', timingError.message);
    rejected = true;
end
assert(rejected, 'A selected K1 outside the installed candidate set must fail.');

assert(double(sixgr.util.structGet(cfgTiming, "phy.harq.feedbackTimingSlots", NaN)) == 2, ...
    "HARQ feedback_timing_slots must reach cfg.phy.harq.feedbackTimingSlots.");
assert(double(sixgr.util.structGet(cfgTiming, "mac.harq.k1", NaN)) == 2, ...
    "HARQ feedback_timing_slots must drive scheduler K1 instead of the hardcoded default.");
assert(double(sixgr.util.structGet(cfgTiming, "mac.harq.k2", NaN)) == 3 && ...
    double(sixgr.util.structGet(cfgTiming, "phy.pusch.k2_slots", NaN)) == 3 && ...
    double(sixgr.util.structGet(cfgTiming, "phy.ul.grantK2Slots", NaN)) == 3, ...
    "HARQ k2 must reach scheduler and UL grant timing aliases.");

ueDL = struct("RNTI", 101, "DLBufferBytes", 4096, "ULBufferBytes", 0, "CQI", 10, "RI", 1);
ueUL = struct("RNTI", 102, "DLBufferBytes", 0, "ULBufferBytes", 4096, "CQI", 10, "RI", 1);
% Slot 0 + K1=2 is DL-only in this TDD pattern. Slot 4 has a legal
% feedback occasion at 6 and UL data at 7 for K2=3. Use installed TDRA.
budgetDL = struct("NPRB", 24, "ControlSymbolAllocation", [0 2], ...
    "SymbolAllocation", cfgTiming.phy.pdsch.symbolAllocation);
budgetUL = struct("NPRB", 24, "ControlSymbolAllocation", [0 2], ...
    "SymbolAllocation", cfgTiming.phy.pusch.symbolAllocation);
schDL = sixgr.l2.mac.SchedulerPF(cfgTiming, "Direction", "DL");
schUL = sixgr.l2.mac.SchedulerPF(cfgTiming, "Direction", "UL");
dlGrant = schDL.schedule(4, ueDL, budgetDL);
ulGrant = schUL.schedule(4, ueUL, budgetUL);
assert(~isempty(dlGrant) && all([dlGrant.K1] == 2) && all(isnan([dlGrant.K2])) && ...
    all([dlGrant.HARQFeedbackAbsoluteSlot] == 6), ...
    "DL grants must carry configured K1 and its actual ACK slot; UL K2 is not applicable.");
assert(~isempty(ulGrant) && all(isnan([ulGrant.K1])) && all([ulGrant.K2] == 3) && ...
    all([ulGrant.ScheduledAbsoluteSlot] == 7), ...
    "UL grants must carry configured K2 and its actual data slot; DL K1 is not applicable.");
end
