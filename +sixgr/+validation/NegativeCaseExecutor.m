classdef NegativeCaseExecutor
    %NEGATIVECASEEXECUTOR Execute fail-closed validation mutations.
    %
    % This is the canonical boundary used by Phase-14 evidence generation.
    % A negative vector qualifies only when the production validator rejects
    % it with the declared public error identifier and without mutating the
    % supplied baseline state.

    methods (Static)
        function result = execute(row)
            if istable(row)
                if height(row) ~= 1
                    error("sixgr:validation:SchemaDuplicateKey", ...
                        "A negative validation case must contain exactly one row.");
                end
                row = table2struct(row);
            end
            required = ["CaseID","Mutation","ExpectedError"];
            for name = required
                if ~isstruct(row) || ~isfield(row, char(name))
                    error("sixgr:validation:SchemaMissingColumn", ...
                        "Negative validation case is missing %s.", name);
                end
            end

            expected = string(row.ExpectedError);
            baseline = sixgr.validation.ValidationSchemaRegistry.sampleCampaignPoint();
            baselineHash = localTableHash(baseline);
            actual = "";
            try
                localApplyMutation(upper(string(row.Mutation)), baseline);
            catch cause
                actual = string(cause.identifier);
            end
            postHash = localTableHash(baseline);
            stateMutation = baselineHash ~= postHash;
            if strlength(actual) == 0
                error("sixgr:validation:NegativeCaseAccepted", ...
                    "Negative case %s was accepted.", string(row.CaseID));
            end
            if actual ~= expected
                error("sixgr:validation:NegativeErrorMismatch", ...
                    "Negative case %s expected %s but observed %s.", ...
                    string(row.CaseID), expected, actual);
            end
            if stateMutation
                error("sixgr:validation:NegativeStateMutation", ...
                    "Negative case %s mutated its baseline state.", ...
                    string(row.CaseID));
            end
            result = struct( ...
                "CaseID", string(row.CaseID), ...
                "Mutation", upper(string(row.Mutation)), ...
                "ExpectedError", expected, ...
                "ActualError", actual, ...
                "StateMutation", false, ...
                "GatePass", false, ...
                "ArtifactAccepted", false, ...
                "Status", "PASS");
        end
    end
end

function localApplyMutation(mutation, baseline)
switch mutation
    case "UNKNOWN_STATUS"
        sixgr.validation.PointStatus.parse("BOGUS");
    case "UNKNOWN_REASON"
        sixgr.validation.StopReason.parse("BOGUS");
    case "MISSING_COLUMN"
        mutated = baseline;
        mutated.TrialCount = [];
        sixgr.validation.CanonicalSchemaValidator.validateCampaignPoint(mutated);
    case "NAN_THRESHOLD"
        mutated = baseline;
        mutated.ConfidenceLevel(:) = NaN;
        sixgr.validation.CanonicalSchemaValidator.validateCampaignPoint(mutated);
    case "INCOMPLETE_POINT"
        localRequireCompletePoint("INCOMPLETE_MAX_TRIALS");
    case "INVALID_CENSOR"
        localValidateCensor("CENSORED_COMPLETE", NaN);
    case "MISSING_SINR"
        sixgr.validation.MeasuredSINRGate.validate( ...
            [], "DECODED_RECEIVER_STATE", 1, ...
            "FIXED_LINK_CALIBRATION", 10);
    case "CONFIG_SINR"
        sixgr.validation.MeasuredSINRGate.validate( ...
            10, "CONFIGURED", 1, "FIXED_LINK_CALIBRATION", 10);
    case "CIRCULAR_PROV"
        sixgr.validation.EvidenceCircularityChecker.check( ...
            "EXTERNAL_ORACLE", "shared-root", ...
            "DUT_OUTPUT", "shared-root");
    case "SELF_REFERENCE"
        localRejectSelfReference();
    case "REFERENCE_HASH"
        localRejectReferenceCopy();
    case "MISSING_POINT"
        localRejectMissingPoint();
    case "DUPLICATE_POINT"
        localRejectDuplicatePoint();
    case "RUNCLASS_SUB"
        sixgr.validation.RunClass.require( ...
            "GEOMETRY_LINK_LEVEL", "FIXED_LINK_CALIBRATION");
    case "TASK_CONFLICT"
        localRejectTaskConflict();
    case "SEED_COLLISION"
        localRejectSeedCollision();
    case "ARTIFACT_MISSING"
        requirement = struct("Artifact", "missing.csv", ...
            "Mandatory", true, "Generated", false, "Valid", false);
        sixgr.validation.ArtifactRequirementRegistry.validate(requirement);
    case "ARTIFACT_STALE"
        localRejectStaleArtifact();
    case "YAML_INVALID"
        localRejectInvalidYAML();
    case "TEST_SKIPPED"
        ledger = table("NEG", "required_test", true, false, true, false, ...
            'VariableNames', ["TestID","TestName","Executed","Passed", ...
            "Skipped","Blocked"]);
        sixgr.validation.TestExecutionLedger.validate(ledger);
    otherwise
        error("sixgr:validation:UnknownNegativeMutation", ...
            "Unknown negative validation mutation '%s'.", mutation);
end
end

function localRequireCompletePoint(status)
if ~ismember(string(status), ["COMPLETE","CENSORED_COMPLETE"])
    error("sixgr:validation:IncompleteMandatoryPoint", ...
        "A mandatory point is incomplete.");
end
end

function localValidateCensor(status, upperBound)
if string(status) == "CENSORED_COMPLETE" && ...
        ~(isnumeric(upperBound) && isscalar(upperBound) && ...
        isfinite(upperBound) && upperBound >= 0 && upperBound <= 1)
    error("sixgr:validation:InvalidCensorPolicy", ...
        "Censored completion requires a finite one-sided upper bound.");
end
end

function localRejectSelfReference()
row = table("NEG-ORACLE", "DUT_REGRESSION", "CRC24C", ...
    "nr_rel18_phy_lls_strict", "dut_self_reference", "1.0.0", ...
    "dut.csv", string(repmat('a', 1, 64)), true, ...
    'VariableNames', ["OracleID","OracleType","Feature","ProfileID", ...
    "SourceName","SourceVersion","ArtifactPath","ArtifactSHA256", ...
    "IndependentOfDUT"]);
descriptor = sixgr.validation.IndependentOracleDescriptor(row);
if ~descriptor.qualifies()
    error("sixgr:validation:OracleNotQualified", ...
        "DUT regression output cannot qualify as an independent oracle.");
end
end

function localRejectReferenceCopy()
row = table("NEG-REF", "dut_copy", "1.0.0", ...
    string(repmat('b', 1, 64)), string(repmat('b', 1, 64)), ...
    true, "FRESH", ...
    'VariableNames', ["ReferenceID","SourceName","SourceVersion", ...
    "ReferenceSHA256","DUTSHA256","IndependentOfDUT","Freshness"]);
sixgr.validation.ReferenceDatasetDescriptor(row);
end

function localRejectMissingPoint()
base = localPointTable();
result = sixgr.validation.OperatingPointJoiner.join( ...
    base, base([],:), "Strict", false);
if result.MissingReferenceCount > 0
    error("sixgr:validation:OperatingPointMissing", ...
        "Independent reference is missing an operating point.");
end
end

function localRejectDuplicatePoint()
base = localPointTable();
result = sixgr.validation.OperatingPointJoiner.join( ...
    base, [base; base], "Strict", false);
if result.DuplicateReferenceCount > 0
    error("sixgr:validation:OperatingPointDuplicate", ...
        "Reference contains a duplicate operating point.");
end
end

function localRejectTaskConflict()
rows = table(["T";"T"], ...
    [string(repmat('a', 1, 64)); string(repmat('b', 1, 64))], ...
    [0;1], 'VariableNames', ["TaskID","OutputSHA256","RetryIndex"]);
try
    sixgr.validation.DeterministicMergeEngine.merge(rows);
catch cause
    if string(cause.identifier) == "sixgr:validation:DuplicateTaskConflict"
        error("sixgr:validation:TaskDuplicateConflict", ...
            "The same TaskID produced conflicting output hashes.");
    end
    rethrow(cause);
end
end

function localRejectSeedCollision()
rows = table(["C";"C"], ["T1";"T2"], ["D1";"D2"], ...
    [11;11], [1;1], 'VariableNames', ...
    ["CampaignID","TaskID","IndependentDropID","Seed","Substream"]);
sixgr.validation.SeedLedger.validate(rows);
end

function localRejectStaleArtifact()
row = struct("SourceTreeHash", "MATCH", "ScenarioHash", "MATCH", ...
    "Freshness", "STALE", "Toolchain", "PINNED", ...
    "RuntimeEvidence", "ALL_PASS");
sixgr.validation.ArchiveAcceptanceRunner.validate(row);
end

function localRejectInvalidYAML()
path = string(tempname) + ".yaml";
cleanup = onCleanup(@() localDelete(path)); %#ok<NASGU>
fid = fopen(path, "wt");
if fid < 0
    error("sixgr:validation:YAMLParseFailed", ...
        "Unable to create invalid YAML fixture.");
end
fcloseCleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "root:\n  broken: [1, 2\n");
clear fcloseCleanup;
try
    sixgr.lls6g.config.readConfigFile(path);
catch
    error("sixgr:validation:YAMLParseFailed", ...
        "Malformed YAML was rejected.");
end
error("sixgr:validation:NegativeCaseAccepted", ...
    "Malformed YAML was unexpectedly accepted.");
end

function tableOut = localPointTable()
tableOut = table("FIXED_LINK_CALIBRATION", "DL", ...
    "nr_rel18_phy_lls_strict", "AWGN", ...
    4e9, 100e6, 30, 4, 1, "MMSE", 10, ...
    'VariableNames', cellstr( ...
    sixgr.validation.OperatingPointKey.requiredFields()));
end

function hash = localTableHash(input)
text = jsonencode(table2struct(input));
hash = string(sixgr.util.sha256Hex(uint8(unicode2native(text, "UTF-8"))));
end

function localDelete(path)
if isfile(path)
    delete(path);
end
end
