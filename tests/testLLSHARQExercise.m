function ok = testLLSHARQExercise()
%TESTLLSHARQEXERCISE Validate the stressed HARQ exercise preset and outputs.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_harq_retransmission_exercise.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));

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
