function ok = testLLSEffectiveOperatingPointSummary()
%TESTLLSEFFECTIVEOPERATINGPOINTSUMMARY Guard nominal-vs-effective operating-point semantics.

setup6GRSimToolkit("Verbose", false);

cfg = localNominalConfig();
dlTrials = localCollapsedTrialTable();
ulTrials = localCollapsedTrialTable();

summary = sixgr.truth.summarizeEffectiveOperatingPoint(cfg, dlTrials, ulTrials);

assert(summary.Configured.MIMOText == "2x2 nominal rank-2", ...
    "Configured MIMO text must preserve the nominal layer/rank setting.");
assert(summary.Configured.DL.OperatingPointText == "layers=2, rank=2, modulation=16QAM, mcs=10", ...
    "Configured DL operating point must preserve the nominal modulation and MCS.");
assert(summary.Configured.UL.OperatingPointText == "layers=2, rank=2, modulation=16QAM, mcs=10", ...
    "Configured UL operating point must preserve the nominal modulation and MCS.");

assert(double(summary.Radio.ConfiguredGridNumRBs) == 51, ...
    "Configured grid RBs must preserve the legacy configured allocation.");
assert(double(summary.Radio.ActiveGridNumRBs) == 106, ...
    "Active grid RBs must promote the authoritative full-band carrier grid.");
assert(summary.Radio.ActiveGridSource == "frequency.n_size_grid", ...
    "Active grid source must identify the authoritative runtime field.");
assert(summary.Radio.ActiveDuplexMode == "TDD", ...
    "Active duplex mode must preserve the operative TDD setting.");
assert(summary.Radio.ActiveTDDPattern == "DDDSU" && logical(summary.Radio.TDDPatternApplicable), ...
    "TDD pattern must stay active when the operative duplex mode is TDD.");

assert(double(summary.DL.SampleCount) == 20, ...
    "Warmup-tagged samples must be excluded from the effective DL histogram summary.");
assert(summary.DL.LayerHistogram == "2:20", ...
    "DL layer histogram must summarize the transmitted runtime operating point.");
assert(summary.DL.RankHistogram == "2:20", ...
    "DL rank histogram must summarize the transmitted runtime operating point.");
assert(summary.DL.RecommendedRIHistogram == "1:19|2:1", ...
    "Recommended RI histogram must preserve CSI-driven rank recommendations separately.");
assert(summary.DL.ModulationHistogram == "QPSK:19|16QAM:1", ...
    "DL modulation histogram must summarize the effective runtime collapse.");
assert(summary.DL.MCSHistogram == "2:19|10:1", ...
    "DL MCS histogram must summarize the effective runtime collapse.");
assert(summary.DL.DominantOperatingPointText == "layer=2, rank=2, modulation=QPSK, mcs=2 (19/20)", ...
    "DL dominant operating point must reflect the transmitted runtime point, not the CSI-recommended RI.");
assert(abs(double(summary.DL.ConfiguredMatchRate) - 0.05) < 1e-12, ...
    "Configured-match rate must quantify how rarely the nominal operating point was sustained.");
assert(contains(summary.DL.Narrative, "diverged from the configured nominal operating point"), ...
    "DL narrative must explicitly call out divergence from the nominal setting.");
assert(contains(summary.RuntimeNarrative, "Exact configured-match rate: 1/20 (5.0%)."), ...
    "Runtime narrative must format configured-match percentages as human-readable percentages.");
assert(contains(summary.RuntimeQualifiedDescription, "configured intent"), ...
    "Runtime-qualified description must preserve nominal/configured semantics explicitly.");
assert(contains(summary.RuntimeQualifiedDescription, "DL dominant effective point layer=2, rank=2, modulation=QPSK, mcs=2 (19/20), configured-match rate 5.0%"), ...
    "Runtime-qualified description must summarize the effective DL transmitted point.");
assert(contains(summary.RuntimeQualifiedDescription, "UL dominant effective point layer=2, rank=2, modulation=QPSK, mcs=2 (19/20), configured-match rate 5.0%"), ...
    "Runtime-qualified description must summarize the effective UL transmitted point.");
assert(contains(summary.DL.Narrative, "dominant recommended RI 1 while transmitted rank remained 2"), ...
    "DL narrative must preserve the recommended-RI divergence explicitly.");

cfgFdd = cfg;
cfgFdd.frequency.duplex_mode = "FDD";
fddSummary = sixgr.truth.summarizeEffectiveOperatingPoint(cfgFdd, table(), table());
assert(~logical(fddSummary.Radio.TDDPatternApplicable), ...
    "TDD pattern must be marked inapplicable when the operative duplex mode is FDD.");
assert(fddSummary.Radio.ActiveTDDPattern == "not_applicable", ...
    "Inactive TDD patterns must not be presented as active when duplex collapses to FDD.");

ok = true;
end

function cfg = localNominalConfig()
cfg = struct();
cfg.meta = struct("description", "Nominal 2x2 rank-2 study");
cfg.mimo = struct("n_tx_ant", 2, "n_rx_ant", 2, "n_layers", 2);
cfg.resource_grid = struct("num_rbs", 51);
cfg.frequency = struct("n_size_grid", 106, "duplex_mode", "TDD");
cfg.frame = struct("tdd_pattern", "DDDSU");
cfg.bandwidth_operation = struct("active_bandwidth_mode", "fullband", ...
    "supports_partial_band_activation", false);
cfg.pdsch = struct("modulation", "16QAM", "mcs_index", 10);
cfg.pusch = struct("modulation", "16QAM", "mcs_index", 10);
end

function T = localCollapsedTrialTable()
layers = [2 * ones(20, 1); 2];
rank = [ones(19, 1); 2; 2];
mods = [repmat("QPSK", 19, 1); "16QAM"; "64QAM"];
mcs = [2 * ones(19, 1); 10; 20];
isWarmup = [false(20, 1); true];
T = table(layers, rank, mods, mcs, isWarmup, ...
    'VariableNames', {'Layers','RankIndicator','Modulation','MCS','IsWarmupFrame'});
end
