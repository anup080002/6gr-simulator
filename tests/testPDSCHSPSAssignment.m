function ok = testPDSCHSPSAssignment()
%TESTPDSCHSPSASSIGNMENT Prove activated SPS state is immutable and fail-closed.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
vectors = readtable(fullfile(PDSCHPhaseTestSupport.vectorRoot(), ...
    "pdsch_scheduling_assignment_test_vectors.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve");
spsRows = vectors(vectors.Profile == "sps_strict", :);
assert(height(spsRows) == 6, "Expected six frozen SPS assignment rows.");

for idx = 1:height(spsRows)
    row = table2struct(spsRows(idx, :));
    [assignment, observedError] = PDSCHPhaseTestSupport.assignmentFromVector(row);
    if row.ExpectedStatus == "PASS"
        assert(strlength(observedError) == 0);
        before = assignment.toStruct();
        assert(assignment.Profile == "sps_strict");
        assert(assignment.Source == "sps_activation_dci+rrc_context");
        assert(before.SPSActivationDCIId == row.SPSActivationDCIId);
        assert(before.SPSConfigId == "SPS-1");
        assert(before.SPSConfigurationEpoch == double(row.ConfigurationEpoch));
        assert(before.HARQProcessId == double(row.HARQProcessID));
        assert(isequaln(before, assignment.toStruct()), ...
            "Reading an SPS assignment changed immutable state.");
    else
        assert(isempty(assignment));
        assert(observedError == PDSCHPhaseTestSupport.fullError(row.ExpectedError), ...
            "%s expected %s, got %s.", row.CaseID, row.ExpectedError, observedError);
    end
end
fprintf("PDSCHSPSAssignment: %d frozen SPS rows passed.\\n", height(spsRows));
ok = true;
end
