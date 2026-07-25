function ok = testPDSCHActiveBWPBinding()
%TESTPDSCHACTIVEBWPBINDING Bind zero-based BWP and carrier PRBs exactly.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
assignment = localAssignment();
[context, precoder] = PDSCHPhaseTestSupport.integrationContext(assignment);
binding = sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, context, precoder);
assert(isequal(binding.PRBSetBWPRelative, 0:3));
assert(isequal(binding.PRBSetCarrierRelative, 0:3));
assert(binding.PrecoderBinding.Status == "PASS");

stale = context; stale.ActiveBWPId = context.ActiveBWPId + 1;
localAssert(@() sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, stale, precoder), ...
    "sixgr:pdsch:MissingActiveBWPContext");
outside = context; outside.ActiveBWPNumPRB = 2;
localAssert(@() sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, outside, precoder), ...
    "sixgr:pdsch:ResourceOutsideBWP");
fprintf("PDSCH active-BWP binding passed.\\n");
ok = true;
end

function assignment = localAssignment()
T = readtable(fullfile(PDSCHPhaseTestSupport.vectorRoot(), ...
    "pdsch_scheduling_assignment_test_vectors.csv"), ...
    "TextType","string","VariableNamingRule","preserve");
[assignment, err] = PDSCHPhaseTestSupport.assignmentFromVector( ...
    table2struct(T(T.CaseID == "ASSIGN-001",:)));
assert(strlength(err) == 0);
end

function localAssert(fn,id)
try, fn(); catch ME, assert(string(ME.identifier)==id); return; end
error("testPDSCHActiveBWPBinding:MissingError","Expected %s.",id);
end
