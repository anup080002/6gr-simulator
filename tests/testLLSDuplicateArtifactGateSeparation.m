function ok = testLLSDuplicateArtifactGateSeparation()
%TESTLLSDUPLICATEARTIFACTGATESEPARATION Missing evidence is not a duplicate.

setup6GRSimToolkit("Verbose", false);
ctx = llsRootGateFixture("pass");
ctx.ScenarioConfig = sixgr.util.structSet(ctx.ScenarioConfig, ...
    "output.artifact_contract_engine.enabled", true);
auditDir = fullfile(ctx.RunFolder, "artifact_generation");
mkdir(auditDir);

audit = table(true, "MISSING", ...
    "No in-memory runtime table was registered.", ...
    'VariableNames', {'Required','Status','Message'});
sixgr.util.csvWriteTable(fullfile(auditDir, ...
    "artifact_generation_results.csv"), audit);
root = sixgr.truth.evaluateLLSRuntimeTruthContract( ...
    ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);
rootStatus = root.CheckDetails.RootStatus;
assert(logical(rootStatus.Status.DuplicateArtifactGateOk));
assert(double(rootStatus.Status.DuplicateArtifactFailureCount) == 0);

audit.Message(1) = "duplicate artifact output path detected";
sixgr.util.csvWriteTable(fullfile(auditDir, ...
    "artifact_generation_results.csv"), audit);
root = sixgr.truth.evaluateLLSRuntimeTruthContract( ...
    ctx.RunFolder, ctx.ScenarioConfig, ctx.InternalConfig);
rootStatus = root.CheckDetails.RootStatus;
assert(~logical(rootStatus.Status.DuplicateArtifactGateOk));
assert(double(rootStatus.Status.DuplicateArtifactFailureCount) == 1);
assert(string(rootStatus.Status.DuplicateArtifactFailureReason) == ...
    "duplicate_artifact_identity_or_output_path_detected");

ok = true;
fprintf("PASS testLLSDuplicateArtifactGateSeparation: completeness and duplicate gates remain distinct.\n");
end
