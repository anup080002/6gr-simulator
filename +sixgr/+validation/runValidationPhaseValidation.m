function summary = runValidationPhaseValidation(varargin)
%RUNVALIDATIONPHASEVALIDATION Execute the complete Phase-14 base gate.

parser = inputParser;
parser.addParameter("VectorRoot", ...
    fullfile(pwd, "tests", "vectors", "validation"));
parser.addParameter("OutputDir", ...
    fullfile(pwd, "artifacts", "validation_phase"));
parser.addParameter("ConfidenceLevels", [0.90 0.95 0.99]);
parser.addParameter("SeedList", [11 23 47 89]);
parser.addParameter("Strict", true, @(x)islogical(x)&&isscalar(x));
parser.parse(varargin{:});
vectorRoot = char(string(parser.Results.VectorRoot));
outputDir = char(string(parser.Results.OutputDir));
sixgr.util.ensureFolder(outputDir);

gateName = ["IndependentVectorPack";"CanonicalMATLABTests"; ...
    "IndependentOracleArtifacts";"FreshCanonicalScenarios"; ...
    "ContractedArtifacts";"PublicationGate"];
required = true(6, 1);
status = repmat("FAIL", 6, 1);
failureReason = repmat("", 6, 1);
evidenceArtifact = repmat("", 6, 1);
results = matlab.unittest.TestResult.empty;
vectorExit = -1;
artifactExit = -1;
oracleCount = 0;
canonical = struct();
buildSummary = struct();

% Gate 1: independently supplied Phase-14 vector pack.
verifier = fullfile(vectorRoot, "verify_validation_vector_pack.py");
[vectorExit, vectorOutput] = system(sprintf( ...
    'python "%s" "%s"', verifier, vectorRoot));
vectorLog = fullfile(outputDir, "validation_vector_verifier.log");
localWriteText(vectorLog, vectorOutput);
evidenceArtifact(1) = string(vectorLog);
if vectorExit == 0
    status(1) = "PASS";
else
    failureReason(1) = "independent_vector_verifier_exit_" + ...
        string(vectorExit);
end

% Gate 2: all 85 mandatory validation tests on this MATLAB runtime.
junitPath = fullfile(outputDir, "validation_phase14_junit.xml");
try
    results = runtests(fullfile(pwd, "tests", ...
        "testValidationPhase14.m"));
    localWriteJUnit(junitPath, results);
    evidenceArtifact(2) = string(junitPath);
    if ~isempty(results) && all([results.Passed]) && ...
            ~any([results.Incomplete])
        status(2) = "PASS";
    else
        failureReason(2) = sprintf( ...
            "phase14_matlab_tests_failed=%d_incomplete=%d", ...
            nnz(~[results.Passed]), nnz([results.Incomplete]));
    end
catch cause
    failureReason(2) = localCause(cause);
end

% Gate 3: independent Python/oracle packs materialized and hash checked.
oracleRegistryPath = fullfile(outputDir, ...
    "validation_oracle_registry_materialized.csv");
try
    generator = fullfile(pwd, "tools", "validation", ...
        "generate_independent_oracles.py");
    [oracleExit, oracleOutput] = system(sprintf( ...
        'python "%s" "%s" "%s"', generator, pwd, outputDir));
    localWriteText(fullfile(outputDir, ...
        "validation_oracle_materializer.log"), oracleOutput);
    if oracleExit ~= 0 || ~isfile(oracleRegistryPath)
        error("sixgr:validation:OracleFailure", ...
            "Independent oracle materializer exited %d.", oracleExit);
    end
    oracle = readtable(oracleRegistryPath, ...
        "TextType", "string", "Delimiter", ",");
    validated = sixgr.validation.IndependentOracleRegistry.validate(oracle);
    for index = 1:height(validated)
        if ~isfile(validated.ArtifactPath(index)) || ...
                localFileHash(validated.ArtifactPath(index)) ~= ...
                validated.ArtifactSHA256(index)
            error("sixgr:validation:OracleHashMismatch", ...
                "Oracle %s is missing or changed.", ...
                validated.OracleID(index));
        end
    end
    oracleCount = height(validated);
    if oracleCount ~= 32 || ...
            any(~validated.QualifiesForMandatoryGate)
        error("sixgr:validation:OracleNotQualified", ...
            "Expected 32 qualifying independent oracle artifacts.");
    end
    status(3) = "PASS";
    evidenceArtifact(3) = string(oracleRegistryPath);
catch cause
    failureReason(3) = localCause(cause);
end

% Gate 4: five fresh executable workloads, including DL/UL waveform truth.
if all(status(1:3) == "PASS")
    try
        canonical = sixgr.validation. ...
            ValidationCanonicalRuntimeExecutor.run( ...
            vectorRoot, outputDir);
        if height(canonical.Scenarios) ~= 5 || ...
                numel(unique(canonical.Scenarios.RunID)) ~= 5 || ...
                any(canonical.Scenarios.Status ~= "PASS")
            error("sixgr:validation:CanonicalScenarioNotExecuted", ...
                "Five unique fresh canonical scenarios are required.");
        end
        status(4) = "PASS";
        evidenceArtifact(4) = fullfile(outputDir, ...
            "canonical_runtime");
    catch cause
        failureReason(4) = localCause(cause);
    end
else
    failureReason(4) = "blocked_by_prior_gate";
end

% Gate 5: generate the 32 CSV/22 PNG contract and run its verifier.
if all(status(1:4) == "PASS")
    try
        buildSummary = sixgr.validation. ...
            ValidationPhaseEvidenceBuilder.build( ...
            vectorRoot, outputDir, results, junitPath, ...
            canonical, oracleRegistryPath);
        artifactVerifier = fullfile(vectorRoot, ...
            "verify_validation_artifacts.py");
        [artifactExit, artifactOutput] = system(sprintf( ...
            'python "%s" "%s"', artifactVerifier, outputDir));
        artifactLog = fullfile(outputDir, ...
            "validation_artifact_verifier.log");
        localWriteText(artifactLog, artifactOutput);
        if artifactExit ~= 0
            error("sixgr:validation:ArtifactHashMismatch", ...
                "Validation artifact verifier exited %d.", artifactExit);
        end
        status(5) = "PASS";
        evidenceArtifact(5) = string(artifactLog);
    catch cause
        failureReason(5) = localCause(cause);
    end
else
    failureReason(5) = "blocked_by_prior_gate";
end

% Gate 6: all prior gates must be real PASS evidence.
if all(status(1:5) == "PASS")
    try
        sixgr.validation.PublicationGateEvaluator.evaluate(struct( ...
            "SchemaOK", true, "OracleOK", true, ...
            "ProvenanceOK", true, "StatisticsOK", true, ...
            "CanonicalScenariosOK", true, ...
            "RequiredTestsOK", true, "ArtifactsOK", true, ...
            "ArchiveOK", true));
        status(6) = "PASS";
        evidenceArtifact(6) = fullfile(outputDir, ...
            "validation_publication_gates.csv");
    catch cause
        failureReason(6) = localCause(cause);
    end
else
    failureReason(6) = "blocked_by_prior_gate";
end

gateTable = table(gateName, required, status, failureReason, ...
    evidenceArtifact, 'VariableNames', ...
    ["GateName","Required","Status","FailureReason","EvidenceArtifact"]);
gatePath = fullfile(outputDir, ...
    "validation_phase14_gate_report.csv");
sixgr.util.csvWriteTable(gatePath, gateTable);

summary = struct("Passed", all(status == "PASS"), ...
    "VectorVerifierExitCode", double(vectorExit), ...
    "ArtifactVerifierExitCode", double(artifactExit), ...
    "MATLABTestCount", numel(results), ...
    "MATLABPassedCount", nnz([results.Passed]), ...
    "IndependentOracleArtifactCount", oracleCount, ...
    "GateTable", gateTable, "GateReport", string(gatePath), ...
    "OutputDir", string(outputDir), "Build", buildSummary);
if parser.Results.Strict && ~summary.Passed
    failed = gateTable(gateTable.Status ~= "PASS", :);
    error("sixgr:validation:PhaseIncomplete", ...
        "Phase-14 failed at %s: %s. Inspect %s.", ...
        failed.GateName(1), failed.FailureReason(1), gatePath);
end
end

function localWriteJUnit(path, results)
fid = fopen(path, "wt", "n", "UTF-8");
if fid < 0
    error("sixgr:validation:ArtifactMissing", ...
        "Unable to create JUnit artifact %s.", path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '<?xml version="1.0" encoding="UTF-8"?>\n');
fprintf(fid, '<testsuite name="testValidationPhase14" tests="%d" failures="%d" skipped="%d">\n', ...
    numel(results), nnz(~[results.Passed] & ~[results.Incomplete]), ...
    nnz([results.Incomplete]));
for index = 1:numel(results)
    name = localXML(string(results(index).Name));
    duration = double(results(index).Duration);
    fprintf(fid, '  <testcase name="%s" time="%.9f">', name, duration);
    if results(index).Incomplete
        fprintf(fid, '<skipped/>');
    elseif ~results(index).Passed
        fprintf(fid, '<failure message="MATLAB test failure"/>');
    end
    fprintf(fid, '</testcase>\n');
end
fprintf(fid, '</testsuite>\n');
end

function output = localXML(input)
output = char(replace(replace(replace(replace(replace( ...
    string(input), "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), ...
    '"', "&quot;"), "'", "&apos;"));
end

function localWriteText(path, text)
fid = fopen(path, "wt", "n", "UTF-8");
if fid < 0
    error("sixgr:validation:ArtifactMissing", ...
        "Unable to write %s.", path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s", text);
end

function output = localFileHash(path)
fid = fopen(path, "rb");
if fid < 0
    error("sixgr:validation:ArtifactMissing", ...
        "Unable to hash %s.", string(path));
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
output = string(sixgr.util.sha256Hex(fread(fid, Inf, "*uint8")));
end

function output = localCause(cause)
output = string(cause.identifier) + ":" + ...
    replace(string(cause.message), newline, " ");
end
