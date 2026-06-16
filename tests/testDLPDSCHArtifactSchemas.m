function ok = testDLPDSCHArtifactSchemas()
%TESTDLPDSCHARTIFACTSCHEMAS Verify DL PDSCH objective artifact schemas.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.run.noProxyTruthContract = true;
cfg.run.runId = "dl_pdsch_artifact_schema_unit";
cfg.run.scenarioID = "dl_pdsch_artifact_schema_unit";
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.phy.linkAdaptation.mode = "fixed";
cfg.phy.pdsch.mcsIndex = 4;
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.validation.dl_pdsch.max_bler = 0.10;
cfg.validation.dl_pdsch.max_ber = 1e-3;

T = localPassingTrialTable();
art = sixgr.truth.exportPDSCHObjectiveArtifacts(tmp, cfg, T, ...
    "RunId", "dl_pdsch_artifact_schema_unit", ...
    "ScenarioName", "dl_pdsch_artifact_schema_unit", ...
    "StrictMode", true);

paths = [string(art.csv(:)); string(art.json(:))];
assert(numel(paths) >= 5, "DL PDSCH objective exporter must write CSV and JSON artifacts.");
for i = 1:numel(paths)
    assert(exist(paths(i), "file") == 2, "Missing DL PDSCH objective artifact: %s", paths(i));
end

summaryPath = fullfile(tmp, "reports", "csv", "dl_pdsch_raw_bler_ber_objective.csv");
failurePath = fullfile(tmp, "reports", "csv", "dl_pdsch_objective_failures.csv");
auditPath = fullfile(tmp, "air_interface", "csv", "dl_pdsch_receiver_evidence_audit.csv");
capabilityPath = fullfile(tmp, "reports", "json", "dl_pdsch_toolbox_capabilities.json");

S = readtable(summaryPath, "VariableNamingRule", "preserve");
F = readtable(failurePath, "VariableNamingRule", "preserve");
A = readtable(auditPath, "VariableNamingRule", "preserve");

assert(height(S) == 1 && logical(S.ObjectivePass(1)), ...
    "Passing raw DL PDSCH rows must produce one passing objective summary.");
assert(height(F) == 0, "Passing raw DL PDSCH rows must not emit objective failures.");
assert(height(A) == height(T), "Receiver evidence audit must be row-aligned with raw trial table.");
assert(all(ismember(["RawBLER","RawBERWeighted","ObjectivePass","ScenarioObjectiveOk","ResultOk"], string(S.Properties.VariableNames))), ...
    "Objective summary must expose raw BLER/BER and pass/fail columns.");
assert(all(ismember(["StrictReceiverEvidenceOk","ChannelEstimateAttempted","EqualizationAttempted","DLSCHDecodeAttempted"], string(A.Properties.VariableNames))), ...
    "Receiver evidence audit must expose strict receiver stage columns.");

txt = fileread(capabilityPath);
assert(contains(txt, "nrPDSCHDecodeAvailable") && contains(txt, "StrictModeToolboxFallbackAllowed"), ...
    "Toolbox capability JSON must disclose PDSCH decode availability and strict fallback policy.");

ok = true;
end

function T = localPassingTrialTable()
n = 3;
T = table();
T.Direction = repmat("DL", n, 1);
T.SNR_dB = repmat(30, n, 1);
T.Frame = (0:n-1)';
T.MCS = repmat(4, n, 1);
T.Layers = repmat(1, n, 1);
T.Modulation = repmat("QPSK", n, 1);
T.ConfiguredMCSIndex = repmat(4, n, 1);
T.ConfiguredModulation = repmat("QPSK", n, 1);
T.ConfiguredLayers = repmat(1, n, 1);
T.ConfiguredRank = repmat(1, n, 1);
T.TBSize_bits = repmat(1000, n, 1);
T.CRCPass = true(n, 1);
T.BitErrors = zeros(n, 1);
T.BitsCompared = repmat(1000, n, 1);
T.StrictReceiverEvidenceOk = true(n, 1);
T.ChannelEstimateAttempted = true(n, 1);
T.ChannelEstimateAvailable = true(n, 1);
T.ResourceExtractionAttempted = true(n, 1);
T.ResourceExtractionAvailable = true(n, 1);
T.EqualizationAttempted = true(n, 1);
T.EqualizationAvailable = true(n, 1);
T.DLSCHDecodeAttempted = true(n, 1);
T.DLSCHDecodeAvailable = true(n, 1);
T.LLRAvailable = true(n, 1);
T.LLRFinite = true(n, 1);
T.PostEqSINRWidebanddB = repmat(25, n, 1);
T.PostEqSINRSource = repmat("post_equalization_sinr_from_equalizer_channel_estimate", n, 1);
T.PostEqSINRValueRole = repmat("measured_post_equalization_scheduling_input", n, 1);
T.PostEqSINRValueStatus = repmat("OK", n, 1);
T.SINRComputationMethod = repmat("mmse", n, 1);
T.Crash = false(n, 1);
T.Skipped = false(n, 1);
T.TruthStatus = repmat("real_lls_evidence", n, 1);
end
