function ok = testLLSPRACHCorrelationPrimaryTruth()
%TESTLLSPRACHCORRELATIONPRIMARYTRUTH Primary PRACH trace is truth-only.

setup6GRSimToolkit("Verbose", false);

emptyT = sixgr.truth.buildPRACHCorrelationTraceTable(table());
assert(istable(emptyT) && isempty(emptyT) && width(emptyT) == 20, ...
    "Unavailable PRACH evidence must yield a typed zero-row table.");

unavailable = table(NaN, NaN, "not_available_missing_truth_status", ...
    'VariableNames', ["LagSamples","CorrelationAbs","TruthStatus"]);
unavailableT = sixgr.truth.buildPRACHCorrelationTraceTable(unavailable);
assert(isempty(unavailableT), ...
    "An all-NaN unavailable row must not enter the primary PRACH trace.");

sourceT = table((1:4).', [-1;0;1;NaN], [0.2;0.8;0.3;NaN], ...
    ["real_lls_evidence";"real_lls_evidence";"proxy";"real_lls_evidence"], ...
    'VariableNames', ["SampleIndex","LagSamples","CorrelationAbs","TruthStatus"]);
truthT = sixgr.truth.buildPRACHCorrelationTraceTable(sourceT);
assert(height(truthT) == 2 && isequal(double(truthT.lag_samples), [-1;0]) && ...
    all(string(truthT.truth_status) == "real_lls_evidence"), ...
    "Primary PRACH rows must be finite and explicitly truth-backed.");

prunedT = sixgr.truth.buildPRACHCorrelationTraceTable(sourceT, ...
    "TruthCasePruned", true);
assert(isempty(prunedT), ...
    "A pruned PRACH truth case must not publish primary measurement rows.");

ok = true;
fprintf("PASS testLLSPRACHCorrelationPrimaryTruth: primary trace is finite truth-only evidence.\n");
end
