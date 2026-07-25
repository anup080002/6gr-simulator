function ok = testPDSCHQCLStatePropagation()
%TESTPDSCHQCLSTATEPROPAGATION Carry QCL source truth to the receiver.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
assignment = localAssignment();
[context, precoder] = PDSCHPhaseTestSupport.integrationContext(assignment);
binding = sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, context, precoder);
qcl = binding.ReceiverQCL;
assert(qcl.SourceReferenceSignal == "NZP-CSI-RS");
assert(qcl.SourceReferenceSignalId == "CSI-RS-7");
assert(contains(qcl.QCLTypes, "A") && contains(qcl.QCLTypes, "D"));
assert(contains(qcl.Assumptions, "spatial"));

incomplete = context;
incomplete.ActivatedTCIStates = rmfield( ...
    incomplete.ActivatedTCIStates, "SourceReferenceSignalId");
localAssert(@() sixgr.pdsch.PDSCHIntegrationValidator.bind( ...
    assignment, incomplete, precoder), "sixgr:pdsch:IncompleteQCLState");
fprintf("PDSCH QCL propagation passed.\\n");
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
error("testPDSCHQCLStatePropagation:MissingError","Expected %s.",id);
end
