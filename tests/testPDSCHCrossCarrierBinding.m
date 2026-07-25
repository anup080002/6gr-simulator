function ok = testPDSCHCrossCarrierBinding()
%TESTPDSCHCROSSCARRIERBINDING Preserve scheduling/scheduled cell identity.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
assignment = localCrossCarrierAssignment();
[context, precoder] = PDSCHPhaseTestSupport.integrationContext(assignment);
binding = sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, context, precoder);
assert(binding.CrossCarrier);
assert(binding.Namespace.SchedulingCellId == 2);
assert(binding.Namespace.ServingCellId == 1);

wrong = context; wrong.CarrierIndicatorValid = false;
localAssert(@() sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, wrong, precoder), ...
    "sixgr:pdsch:InvalidCarrierIndicator");
disabled = context; disabled.CrossCarrierSchedulingEnabled = false;
localAssert(@() sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, disabled, precoder), ...
    "sixgr:pdsch:CrossCarrierSchedulingNotConfigured");
fprintf("PDSCH cross-carrier binding passed.\\n");
ok = true;
end

function assignment = localCrossCarrierAssignment()
T = readtable(fullfile(PDSCHPhaseTestSupport.vectorRoot(), ...
    "pdsch_scheduling_assignment_test_vectors.csv"), ...
    "TextType","string","VariableNamingRule","preserve");
[base, err] = PDSCHPhaseTestSupport.assignmentFromVector( ...
    table2struct(T(T.CaseID == "ASSIGN-001",:)));
assert(strlength(err) == 0);
data = base.toStruct();
data.SchedulingCellId = 2;
data.AssignmentId = data.AssignmentId + "-XC";
assignment = sixgr.pdsch.PDSCHSchedulingAssignment(data);
end

function localAssert(fn,id)
try, fn(); catch ME, assert(string(ME.identifier)==id); return; end
error("testPDSCHCrossCarrierBinding:MissingError","Expected %s.",id);
end
