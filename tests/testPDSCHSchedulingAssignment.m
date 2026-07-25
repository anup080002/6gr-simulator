function ok = testPDSCHSchedulingAssignment()
%TESTPDSCHSCHEDULINGASSIGNMENT Execute all frozen assignment rows.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = PDSCHPhaseTestSupport.vectorRoot();
vectors = readtable(fullfile(root, "pdsch_scheduling_assignment_test_vectors.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
expected = readtable(fullfile(root, "expected_pdsch_assignment_resolution.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
assert(height(vectors) == 22 && height(expected) == 22, ...
    "The frozen scheduling-assignment pack must contain exactly 22 rows.");

passCount = 0;
positiveAssignment = [];
for idx = 1:height(vectors)
    row = table2struct(vectors(idx, :));
    exp = expected(expected.CaseID == row.CaseID, :);
    assert(height(exp) == 1, "Missing expected assignment row for %s.", row.CaseID);
    [assignment, observedError] = PDSCHPhaseTestSupport.assignmentFromVector(row);
    if exp.ExpectedStatus == "PASS"
        assert(strlength(observedError) == 0, "%s unexpectedly failed with %s.", ...
            row.CaseID, observedError);
        assert(isa(assignment, "sixgr.pdsch.PDSCHSchedulingAssignment"), ...
            "%s did not create the canonical immutable assignment.", row.CaseID);
        assert(assignment.Source == exp.ExpectedAssignmentSource, ...
            "%s source mismatch: expected %s, got %s.", ...
            row.CaseID, exp.ExpectedAssignmentSource, assignment.Source);
        assert(strlength(assignment.AssignmentId) > 0, ...
            "%s assignment ID is empty.", row.CaseID);
        if isempty(positiveAssignment) && assignment.Profile == "connected_strict"
            positiveAssignment = assignment;
        end
    else
        expectedError = PDSCHPhaseTestSupport.fullError(exp.ExpectedError);
        assert(isempty(assignment), "%s produced an assignment on a negative row.", row.CaseID);
        assert(observedError == expectedError, ...
            "%s expected %s, got %s.", row.CaseID, expectedError, observedError);
    end
    passCount = passCount + 1;
end
assert(passCount == 22);
assert(~isempty(positiveAssignment), ...
    "A connected strict assignment is required for trust-boundary tests.");
forged = positiveAssignment.toStruct();
forged.DCICRCPass = false;
localAssertIdentifier(@() sixgr.pdsch.PDSCHSchedulingAssignment(forged), ...
    "sixgr:pdsch:UnvalidatedDecodedDCIAssignment");
inconsistent = positiveAssignment.toStruct();
inconsistent.TargetCodeRatePerCodeword(1) = ...
    inconsistent.TargetCodeRatePerCodeword(1) + 0.01;
localAssertIdentifier(@() sixgr.pdsch.PDSCHSchedulingAssignment(inconsistent), ...
    "sixgr:pdsch:MCSAssignmentMismatch");
missingCapability = rmfield(positiveAssignment.toStruct(), ...
    "UECapability1024QAM");
localAssertIdentifier(@() sixgr.pdsch.PDSCHSchedulingAssignment(missingCapability), ...
    "sixgr:pdsch:IncompleteSchedulingAssignment");
extraDMRSPort = positiveAssignment.toStruct();
extraDMRSPort.DMRSPortSet(end + 1) = ...
    max(extraDMRSPort.DMRSPortSet) + 1;
localAssertIdentifier(@() sixgr.pdsch.PDSCHSchedulingAssignment(extraDMRSPort), ...
    "sixgr:pdsch:DMRSPortLayerCountMismatch");
fprintf("PDSCHSchedulingAssignment: %d/22 frozen rows passed.\\n", passCount);
ok = true;
end

function localAssertIdentifier(fn, expected)
try
    fn();
catch ME
    assert(string(ME.identifier) == string(expected), ...
        "Expected %s, observed %s.", expected, ME.identifier);
    return;
end
error("testPDSCHSchedulingAssignment:MissingError", ...
    "Expected typed error %s.", expected);
end
