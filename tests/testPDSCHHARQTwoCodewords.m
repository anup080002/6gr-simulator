function ok = testPDSCHHARQTwoCodewords()
%TESTPDSCHHARQTWOCODEWORDS Keep CW0 and CW1 buffers disjoint.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
manager = sixgr.pdsch.PDSCHHARQManager(struct("MaxProcesses", 16));
for cw = 0:1
    manager.process(PDSCHPhaseTestSupport.harqObservation( ...
        "CodewordIndex", cw, "TBIdentityDigest", "TB-" + string(cw), ...
        "RateRecoveredLLR", (cw + 1) * ones(8,1), ...
        "ValidPositionMask", true(8,1)));
end
for cw = 0:1
    [context, result] = manager.process(PDSCHPhaseTestSupport.harqObservation( ...
        "CodewordIndex", cw, "TBIdentityDigest", "TB-" + string(cw), ...
        "NewData", false, "RV", 2 + cw, ...
        "RateRecoveredLLR", (cw + 1) * ones(8,1), ...
        "ValidPositionMask", true(8,1)));
    assert(result.Combined);
    data = context.toStruct();
    assert(all(data.CircularBufferLLR == 2 * (cw + 1)));
end
fprintf("PDSCH HARQ two-codeword isolation passed.\\n");
ok = true;
end
