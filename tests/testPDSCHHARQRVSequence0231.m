function ok = testPDSCHHARQRVSequence0231()
%TESTPDSCHHARQRVSEQUENCE0231 Preserve actual RV history per codeword.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
manager = sixgr.pdsch.PDSCHHARQManager(struct("MaxProcesses", 16));
sequence = [0 2 3 1];
for idx = 1:numel(sequence)
    obs = PDSCHPhaseTestSupport.harqObservation( ...
        "RV", sequence(idx), "NewData", idx == 1);
    [context, result] = manager.process(obs);
    assert(result.Combined == (idx > 1));
end
data = context.toStruct();
assert(isequal(data.RVHistory, sequence));
assert(data.TransmissionCount == 4);
fprintf("PDSCH HARQ RV sequence [0 2 3 1] passed.\\n");
ok = true;
end
