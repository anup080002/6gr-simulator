function ok = testPDSCHTCIStateBinding()
%TESTPDSCHTCISTATEBINDING Resolve only the activated assignment TCI state.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
assignment = localAssignment();
[context, precoder] = PDSCHPhaseTestSupport.integrationContext(assignment);
binding = sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, context, precoder);
assert(binding.TCIState.TCIStateId == assignment.get("TCIStateId"));
assert(binding.PrecoderBinding.PrecoderBundleDigest ...
    == precoder.ImmutableBundleDigest);

inactive = context;
inactive.ActivatedTCIStates.Activated = false;
localAssert(@() sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, inactive, precoder), ...
    "sixgr:pdsch:TCIStateNotActivated");
unknown = context;
unknown.ActivatedTCIStates.TCIStateId = 99;
localAssert(@() sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, unknown, precoder), ...
    "sixgr:pdsch:TCIStateNotActivated");
stale = context;
stale.ActivatedTCIStates.PrecoderBundleDigest = string(repmat('0', 1, 64));
localAssert(@() sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, stale, precoder), ...
    "sixgr:pdsch:StalePrecoderTCIContext");
fprintf("PDSCH TCI-state binding passed.\\n");
ok = true;
end

function assignment = localAssignment()
T=readtable(fullfile(PDSCHPhaseTestSupport.vectorRoot(), ...
    "pdsch_scheduling_assignment_test_vectors.csv"),"TextType","string", ...
    "VariableNamingRule","preserve");
[assignment,err]=PDSCHPhaseTestSupport.assignmentFromVector( ...
    table2struct(T(T.CaseID=="ASSIGN-001",:))); assert(strlength(err)==0);
end

function localAssert(fn,id)
try, fn(); catch ME, assert(string(ME.identifier)==id); return; end
error("testPDSCHTCIStateBinding:MissingError","Expected %s.",id);
end
