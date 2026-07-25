function ok = testPDSCHHARQNDIReset()
%TESTPDSCHHARQNDIRESET NDI/new-data reset only the selected codeword.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
manager = sixgr.pdsch.PDSCHHARQManager(struct("MaxProcesses", 16));
manager.process(PDSCHPhaseTestSupport.harqObservation( ...
    "RateRecoveredLLR", ones(8,1), "ValidPositionMask", true(8,1)));
[context, result] = manager.process(PDSCHPhaseTestSupport.harqObservation( ...
    "NDI", 0, "NewData", true, "TBIdentityDigest", "TB-B", ...
    "RateRecoveredLLR", 3 * ones(8,1), "ValidPositionMask", true(8,1)));
data = context.toStruct();
assert(~result.Combined && result.Action == "reset_and_load_new_tb");
assert(data.TransmissionCount == 1 && isequal(data.RVHistory, 0));
assert(all(data.CircularBufferLLR == 3) && data.TBIdentityDigest == "TB-B");
fprintf("PDSCH HARQ NDI reset passed.\\n");
ok = true;
end
