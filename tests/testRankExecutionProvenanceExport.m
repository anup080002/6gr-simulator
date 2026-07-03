function ok = testRankExecutionProvenanceExport()
%TESTRANKEXECUTIONPROVENANCEEXPORT Ensure rank policy RCA survives grants and trial rows.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

expectedReason = "requested_rank_exceeds_supported_layers";
localAssertSchedulerPath("DL", expectedReason);
localAssertSchedulerPath("UL", expectedReason);
localAssertTrialTablePath("DL", expectedReason);
localAssertTrialTablePath("UL", expectedReason);

ok = true;
end

function localAssertSchedulerPath(direction, expectedReason)
cfg = localSchedulerCfg(direction);
scheduler = sixgr.l2.mac.SchedulerPF(cfg, "Direction", direction);
ue = localUE(direction);

[~, nLayers, ~, amc] = scheduler.selectAMC(ue);
assert(double(nLayers) == 1, "%s AMC must execute the supported rank after downgrade.", direction);
localAssertRankFields(amc, expectedReason, "AMC");

plan = scheduler.buildNewDataGrantPlan(ue, 0:15, [0 14], 2400);
assert(logical(plan.Valid), "%s scheduler plan must remain valid after rank provenance wiring.", direction);
localAssertRankFields(plan, expectedReason, "scheduler plan");

[grants, ~] = scheduler.schedule(0, ue, struct("PRBSet", 0:15, "SymbolAllocation", [0 14]));
assert(~isempty(grants), "%s scheduler must emit a grant for the provenance fixture.", direction);
localAssertRankFields(grants(1), expectedReason, "finalized grant");
end

function localAssertTrialTablePath(direction, expectedReason)
cfg = localWaveformCfg(direction);
grant = struct( ...
    "UEIndex", 1, ...
    "RNTI", 9401, ...
    "ServingCell", 1, ...
    "RankSelectionPolicy", "adaptive", ...
    "RankSelectionSource", expectedReason, ...
    "RankDecisionReason", expectedReason, ...
    "RankDowngradeApplied", true, ...
    "MaxSupportedLayers", 1);

if direction == "DL"
    out = sixgr.link.runDLPDSCHThroughput(cfg, ...
        "NumFrames", 1, ...
        "SNR_dB", 24, ...
        "GrantSnapshot", grant, ...
        "InterferenceBundle", struct([]));
else
    out = sixgr.link.runULPUSCHThroughput(cfg, ...
        "NumFrames", 1, ...
        "SNR_dB", 24, ...
        "GrantSnapshot", grant, ...
        "InterferenceBundle", struct([]));
end

assert(isstruct(out) && istable(out.TrialTable) && height(out.TrialTable) == 1, ...
    "%s throughput run must return one trial row.", direction);
T = out.TrialTable;
required = ["RankSelectionPolicy","RankSelectionSource","RankDecisionReason", ...
    "RankDowngradeApplied","MaxSupportedLayers"];
assert(all(ismember(required, string(T.Properties.VariableNames))), ...
    "%s trial table must export rank execution provenance columns.", direction);
assert(strcmp(string(T.RankSelectionPolicy(1)), "adaptive"), ...
    "%s trial table must preserve rank selection policy.", direction);
assert(strcmp(string(T.RankSelectionSource(1)), expectedReason), ...
    "%s trial table must preserve actionable rank selection source.", direction);
assert(strcmp(string(T.RankDecisionReason(1)), expectedReason), ...
    "%s trial table must preserve rank decision reason.", direction);
assert(logical(T.RankDowngradeApplied(1)), ...
    "%s trial table must preserve rank downgrade flag.", direction);
assert(double(T.MaxSupportedLayers(1)) == 1, ...
    "%s trial table must preserve max supported layer count.", direction);
end

function localAssertRankFields(s, expectedReason, label)
required = ["RankSelectionPolicy","RankSelectionSource","RankDecisionReason", ...
    "RankDowngradeApplied","MaxSupportedLayers"];
for i = 1:numel(required)
    assert(isfield(s, required(i)), "%s missing %s.", label, required(i));
end
assert(strcmp(string(s.RankSelectionPolicy), "adaptive"), ...
    "%s must disclose adaptive rank policy.", label);
assert(strcmp(string(s.RankSelectionSource), expectedReason), ...
    "%s must expose the actionable rank decision as RankSelectionSource.", label);
assert(strcmp(string(s.RankDecisionReason), expectedReason), ...
    "%s must expose the rank decision reason.", label);
assert(logical(s.RankDowngradeApplied), ...
    "%s must disclose the rank downgrade.", label);
assert(double(s.MaxSupportedLayers) == 1, ...
    "%s must disclose the one-layer support limit.", label);
end

function cfg = localSchedulerCfg(direction)
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.mac.scheduler.fastNREApprox = false;
cfg.mac.scheduler.tbsMode = "faithful";
cfg.mac.scheduler.maxUEPerSlot = 1;
cfg.mac.scheduler.minPRBPerUE = 4;
cfg.phy.linkAdaptation.mode = "amc";
cfg.phy.linkAdaptation.rankPolicy = "adaptive";
cfg.phy.mimo.maxRank = 2;
if direction == "DL"
    cfg.phy.pdsch.nLayers = 2;
    cfg.phy.pdsch.numLayers = 2;
    cfg.phy.pdsch.maxLayers = 2;
    cfg.phy.pdsch.NumAntennaPorts = 1;
    cfg.phy.pdsch.mcsTable = "qam64_table1";
    cfg.phy.pdsch.modulation = "QPSK";
    cfg.scenario.bs.nTxAnt = 1;
    cfg.scenario.ue.nRxAnt = 1;
    cfg.phy.nTxAnt = 1;
    cfg.phy.nRxAnt = 1;
else
    cfg.phy.pusch.nLayers = 2;
    cfg.phy.pusch.numLayers = 2;
    cfg.phy.pusch.maxLayers = 2;
    cfg.phy.pusch.NumAntennaPorts = 1;
    cfg.phy.pusch.mcsTable = "qam64_table1";
    cfg.phy.pusch.modulation = "QPSK";
    cfg.phy.pusch.transmissionScheme = "codebook";
    cfg.scenario.ue.nTxAnt = 1;
    cfg.scenario.bs.nRxAnt = 1;
    cfg.phy.nTxAnt = 1;
    cfg.phy.nRxAnt = 1;
end
end

function cfg = localWaveformCfg(direction)
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.run.interferenceExecutionMode = "none";
cfg.mac.scheduler.fastNREApprox = false;
cfg.mac.scheduler.tbsMode = "faithful";
if direction == "DL"
    cfg.phy.pdsch.nLayers = 1;
    cfg.phy.pdsch.numLayers = 1;
    cfg.phy.pdsch.mcsIndex = 4;
    cfg.phy.pdsch.modulation = "QPSK";
    cfg.phy.pdsch.mcsTable = "qam64_table1";
else
    cfg.phy.pusch.nLayers = 1;
    cfg.phy.pusch.numLayers = 1;
    cfg.phy.pusch.mcsIndex = 4;
    cfg.phy.pusch.modulation = "QPSK";
    cfg.phy.pusch.mcsTable = "qam64_table1";
    cfg.phy.pusch.transmissionScheme = "codebook";
end
end

function ue = localUE(direction)
ue = struct( ...
    "RNTI", 9401, ...
    "UEIndex", 1, ...
    "ServingCell", 1, ...
    "CQI", 12, ...
    "RI", 2, ...
    "PMI", 0, ...
    "FeedbackValid", true, ...
    "CausalFeedbackUsable", true, ...
    "HeadOfLineDelay_ms", 1);
if direction == "DL"
    ue.DLBufferBytes = 2400;
else
    ue.ULBufferBytes = 2400;
end
end
