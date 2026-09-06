function ok = testActualLLSImplementationHarness()
%TESTACTUALLLSIMPLEMENTATIONHARNESS Verify partial-actual verdict from runtime evidence.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
addpath(fullfile(pwd, "tests"));

ctx = llsImplementationHarnessFixture("partial_actual");
out = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig, ...
    "WriteArtifacts", false);

assert(string(out.Summary.ActualLLSVerdict) == "partial actual LLS", ...
    "Expected partial actual LLS verdict for data-channel-only runtime evidence.");
assert(double(out.Summary.EnabledBlockCount) == 3, ...
    "Fixture should enable PDSCH, PUSCH, and KPI only.");

matrixT = out.ValidationMatrix;
pdsch = matrixT(string(matrixT.BlockId) == "PDSCH", :);
pusch = matrixT(string(matrixT.BlockId) == "PUSCH", :);
kpi = matrixT(string(matrixT.BlockId) == "KPI", :);

assert(isscalar(pdsch.ImplementationPass) && logical(pdsch.ImplementationPass), ...
    "PDSCH should pass actual runtime implementation checks.");
assert(isscalar(pusch.ImplementationPass) && logical(pusch.ImplementationPass), ...
    "PUSCH should pass actual runtime implementation checks.");
assert(isscalar(kpi.ImplementationPass) && ~logical(kpi.ImplementationPass), ...
    "KPI should fail closed when no strict reference path is available.");
assert(string(kpi.FailureReason) == "reference_path_unavailable", ...
    "KPI failure should stay explicitly tied to missing strict reference evidence.");

% A truthful provenance sentence containing "oracle-free" must not trip
% the affirmative oracle-use detector.  A populated UsedOracleFields field
% must still fail closed, even when OracleUsed itself is false.
pucchT = table(false, "", ...
    "Waveform-backed PUCCH through typed report, assignment and oracle-free receiver.", ...
    "real_pucch_waveform_uci_receiver_evidence", "PASS", ...
    'VariableNames', {'OracleUsed','UsedOracleFields','Notes','TruthStatus','Status'});
pucchPath = fullfile(ctx.Layout.AirInterfaceCSVDir, "pucch_trials.csv");
sixgr.util.csvWriteTable(pucchPath, pucchT);
outNoOracle = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ...
    ctx.ScenarioConfig, ctx.InternalConfig, "WriteArtifacts", false);
pucchDetector = outNoOracle.OracleProxyFallbackDetector( ...
    string(outNoOracle.OracleProxyFallbackDetector.BlockId) == "PUCCH_UCI", :);
assert(height(pucchDetector) == 1 && ~logical(pucchDetector.OracleUsed), ...
    "Negative oracle provenance must not be classified as affirmative oracle use.");

pucchT.UsedOracleFields(:) = "transmitted_uci_bits";
sixgr.util.csvWriteTable(pucchPath, pucchT);
outWithOracle = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ...
    ctx.ScenarioConfig, ctx.InternalConfig, "WriteArtifacts", false);
pucchDetector = outWithOracle.OracleProxyFallbackDetector( ...
    string(outWithOracle.OracleProxyFallbackDetector.BlockId) == "PUCCH_UCI", :);
assert(height(pucchDetector) == 1 && logical(pucchDetector.OracleUsed), ...
    "Populated UsedOracleFields must remain an affirmative oracle disclosure.");

% Runtime MIMO coverage is the production rank/layer/precoder call graph,
% not only the legacy executeSpatialComposite helper.  Evidence without a
% canonical call must still be classified as bypassed.
rankLayerT = table(1, 1, 1, 1, "real_rank_layer_runtime_evidence", "PASS", ...
    'VariableNames', {'ConfiguredRank','ScheduledRank','TransmittedRank', ...
    'EffectiveDecodedRank','TruthStatus','Status'});
rankLayerPath = fullfile(ctx.Layout.BeamformingCSVDir, "rank_layer_trials.csv");
sixgr.util.csvWriteTable(rankLayerPath, rankLayerT);
outMIMONoCall = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ...
    ctx.ScenarioConfig, ctx.InternalConfig, "WriteArtifacts", false);
mimoDetector = outMIMONoCall.OracleProxyFallbackDetector( ...
    string(outMIMONoCall.OracleProxyFallbackDetector.BlockId) == "MIMO", :);
assert(height(mimoDetector) == 1 && logical(mimoDetector.Bypassed), ...
    "MIMO evidence without a canonical runtime call must fail as bypassed.");

profilePath = fullfile(ctx.Layout.ReportCSVDir, "runtime_function_profile.csv");
profileT = readtable(profilePath, "VariableNamingRule", "preserve", ...
    "TextType", "string");
profileT(end+1, :) = profileT(1, :);
profileT.FunctionName(end) = "sixgr.phy.dl.resolvePDSCHPrecoding";
profileT.CompleteName(end) = "sixgr.phy.dl.resolvePDSCHPrecoding";
profileT.NumCalls(end) = 1;
profileT.TotalTime_s(end) = 0.01;
profileT.SelfTimeApprox_s(end) = 0.005;
sixgr.util.csvWriteTable(profilePath, profileT);
outMIMOCall = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ...
    ctx.ScenarioConfig, ctx.InternalConfig, "WriteArtifacts", false);
mimoDetector = outMIMOCall.OracleProxyFallbackDetector( ...
    string(outMIMOCall.OracleProxyFallbackDetector.BlockId) == "MIMO", :);
mimoMatrix = outMIMOCall.ValidationMatrix( ...
    string(outMIMOCall.ValidationMatrix.BlockId) == "MIMO", :);
assert(height(mimoDetector) == 1 && ~logical(mimoDetector.Bypassed) && ...
    height(mimoMatrix) == 1 && logical(mimoMatrix.DUTFunctionActuallyCalled), ...
    "Canonical rank/layer/precoder execution must satisfy MIMO runtime coverage.");

ok = true;
end
