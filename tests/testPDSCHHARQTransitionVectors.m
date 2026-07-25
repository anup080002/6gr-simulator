function ok = testPDSCHHARQTransitionVectors()
%TESTPDSCHHARQTRANSITIONVECTORS Execute all 11 frozen HARQ transitions.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = PDSCHPhaseTestSupport.vectorRoot();
inputPath = fullfile(root, "pdsch_harq_test_vectors.csv");
inputOptions = detectImportOptions(inputPath, "TextType", "string", ...
    "VariableNamingRule", "preserve");
inputOptions = setvartype(inputOptions, ["NDI","RV"], "string");
inputT = readtable(inputPath, inputOptions);
expectedT = readtable(fullfile(root, "expected_pdsch_harq_transitions.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
assert(height(inputT) == 11 && height(expectedT) == 11);

manager = sixgr.pdsch.PDSCHHARQManager(struct("MaxProcesses", 16));
% Establish a second-codeword prior for the dual-codeword row.
manager.process(PDSCHPhaseTestSupport.harqObservation( ...
    "HARQProcessId", 7, "CodewordIndex", 0));
manager.process(PDSCHPhaseTestSupport.harqObservation( ...
    "HARQProcessId", 7, "CodewordIndex", 1));

for idx = 1:height(inputT)
    row = inputT(idx, :);
    expected = expectedT(expectedT.CaseID == row.CaseID, :);
    assert(height(expected) == 1);
    if row.CaseID == "HARQ-CW2-001"
        for cw = 0:1
            rvValues = localPipeNumbers(row.RV);
            obs = PDSCHPhaseTestSupport.harqObservation( ...
                "HARQProcessId", double(row.HARQProcessID), ...
                "CodewordIndex", cw, "NewData", false, ...
                "RV", rvValues(cw + 1));
            [~, result] = manager.process(obs);
            assert(result.Combined && string(result.Action) == expected.ExpectedHARQAction);
        end
        continue;
    end

    obs = localObservationFromRow(row);
    try
        [~, result] = manager.process(obs);
        actualError = "";
    catch ME
        result = struct("Combined", false, "Action", "reject");
        actualError = string(ME.identifier);
    end
    if expected.ExpectedStatus == "PASS"
        assert(strlength(actualError) == 0, "%s failed with %s.", row.CaseID, actualError);
        assert(logical(result.Combined) == logical(expected.ExpectedCombine));
        assert(string(result.Action) == expected.ExpectedHARQAction);
    else
        assert(actualError == PDSCHPhaseTestSupport.fullError(expected.ExpectedError), ...
            "%s expected %s, got %s.", row.CaseID, expected.ExpectedError, actualError);
        assert(~result.Combined);
    end
end
fprintf("PDSCH HARQ transitions: 11/11 frozen rows passed.\\n");
ok = true;
end

function obs = localObservationFromRow(row)
rv = localPipeNumbers(row.RV);
ndi = localPipeNumbers(row.NDI);
obs = PDSCHPhaseTestSupport.harqObservation( ...
    "HARQProcessId", double(row.HARQProcessID), ...
    "NDI", ndi(1), "RV", rv(1), ...
    "NewData", logical(row.NewData));
if ~logical(row.SameTBIdentity)
    obs.TBIdentityDigest = "TB-DIFFERENT";
end
if ~logical(row.SameTBS)
    obs.TBS = obs.TBS + 8;
end
if ~logical(row.SameCodeBlockLayout)
    obs.CodingPlanDigest = "LAYOUT-DIFFERENT";
end
end

function values = localPipeNumbers(value)
parts = split(string(value), "|");
values = str2double(parts).';
end
