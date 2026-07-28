function summary = runValidationImpactAnalysis(varargin)
%RUNVALIDATIONIMPACTANALYSIS Execute and verify all Phase-14 impact pairs.

parser = inputParser;
parser.addParameter("ExperimentMatrix", fullfile(pwd, "tests", ...
    "vectors", "validation", ...
    "validation_impact_experiment_matrix.csv"));
parser.addParameter("OutputDir", ...
    fullfile(pwd, "artifacts", "validation_impact"));
parser.addParameter("SeedList", [11 23 47 89 131 197]);
parser.addParameter("ConfidenceLevel", 0.95);
parser.addParameter("Strict", true, @(x)islogical(x)&&isscalar(x));
parser.parse(varargin{:});
outputDir = char(string(parser.Results.OutputDir));
sixgr.util.ensureFolder(outputDir);
matrix = readtable(parser.Results.ExperimentMatrix, ...
    "TextType", "string", "Delimiter", ",");
families = unique(string(matrix.FamilyID));
pairs = unique(string(matrix.PairID));
designOK = height(matrix) == 768 && numel(families) == 64 && ...
    numel(pairs) == 384;
pairingOK = true;
for pair = reshape(pairs, 1, [])
    rows = matrix(string(matrix.PairID) == pair, :);
    pairingOK = pairingOK && height(rows) == 2 && ...
        isequal(sort(string(rows.Arm)), ...
        ["BASELINE";"TREATMENT"]) && ...
        numel(unique(double(rows.Seed))) == 1;
end
vectorRoot = fileparts(char(string(parser.Results.ExperimentMatrix)));
rules = readtable(fullfile(vectorRoot, ...
    "validation_impact_acceptance_rules.csv"), ...
    "TextType", "string", "Delimiter", ",");
ruleCount = height(rules);
baseGate = fullfile(pwd, "artifacts", "validation_phase", ...
    "validation_phase14_gate_report.csv");
basePassed = false;
if isfile(baseGate)
    base = readtable(baseGate, "TextType", "string", "Delimiter", ",");
    basePassed = all(string(base.Status) == "PASS");
end

gate = ["ExperimentMatrix";"PairingContract";"AcceptanceRules"; ...
    "BasePhase";"ImpactExecution";"ImpactArtifacts"];
status = repmat("FAIL", 6, 1);
reason = repmat("", 6, 1);
evidence = repmat("", 6, 1);
if designOK
    status(1) = "PASS";
    evidence(1) = string(parser.Results.ExperimentMatrix);
else
    reason(1) = "expected_768_experiments_64_families_384_pairs";
end
if pairingOK
    status(2) = "PASS";
    evidence(2) = fullfile(vectorRoot, ...
        "validation_impact_pairing_contract.csv");
else
    reason(2) = "baseline_treatment_pairing_mismatch";
end
if ruleCount == 96
    status(3) = "PASS";
    evidence(3) = fullfile(vectorRoot, ...
        "validation_impact_acceptance_rules.csv");
else
    reason(3) = "expected_96_acceptance_rules";
end
if basePassed
    status(4) = "PASS";
    evidence(4) = string(baseGate);
else
    reason(4) = "base_validation_phase_not_passed";
end

build = struct();
verifierExit = -1;
if all(status(1:4) == "PASS")
    try
        build = sixgr.validation.ValidationImpactEvidenceBuilder.build( ...
            parser.Results.ExperimentMatrix, outputDir, ...
            parser.Results.ConfidenceLevel);
        if build.ExperimentCount ~= 768 || build.PairCount ~= 384 || ...
                build.FamilyCount ~= 64 || build.RuleCount ~= 96
            error("sixgr:validation:IncompleteMandatoryPoint", ...
                "Impact execution counts do not match the predeclared design.");
        end
        status(5) = "PASS";
        evidence(5) = fullfile(outputDir, ...
            "validation_impact_run_manifest.csv");
    catch cause
        reason(5) = localCause(cause);
    end
else
    reason(5) = "blocked_by_prior_gate";
end

if status(5) == "PASS"
    verifier = fullfile(vectorRoot, ...
        "verify_validation_impact_artifacts.py");
    [verifierExit, verifierOutput] = system(sprintf( ...
        'python "%s" "%s"', verifier, outputDir));
    verifierLog = fullfile(outputDir, ...
        "validation_impact_artifact_verifier.log");
    localWriteText(verifierLog, verifierOutput);
    if verifierExit == 0
        status(6) = "PASS";
        evidence(6) = string(verifierLog);
    else
        reason(6) = "impact_artifact_verifier_exit_" + ...
            string(verifierExit);
    end
else
    reason(6) = "blocked_by_impact_execution";
end

gateTable = table(gate, true(6, 1), status, reason, evidence, ...
    'VariableNames', ["GateName","Required","Status", ...
    "FailureReason","EvidenceArtifact"]);
gatePath = fullfile(outputDir, "validation_impact_gate_report.csv");
sixgr.util.csvWriteTable(gatePath, gateTable);
summary = struct("Passed", all(status == "PASS"), ...
    "ExperimentCount", height(matrix), ...
    "FamilyCount", numel(families), "PairCount", numel(pairs), ...
    "RuleCount", ruleCount, "ArtifactVerifierExitCode", verifierExit, ...
    "GateTable", gateTable, "GateReport", string(gatePath), ...
    "OutputDir", string(outputDir), "Build", build);
if parser.Results.Strict && ~summary.Passed
    failed = gateTable(gateTable.Status ~= "PASS", :);
    error("sixgr:validation:ImpactIncomplete", ...
        "Validation impact failed at %s: %s. Inspect %s.", ...
        failed.GateName(1), failed.FailureReason(1), gatePath);
end
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

function output = localCause(cause)
output = string(cause.identifier) + ":" + ...
    replace(string(cause.message), newline, " ");
end
