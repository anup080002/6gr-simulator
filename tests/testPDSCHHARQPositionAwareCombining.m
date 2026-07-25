function ok = testPDSCHHARQPositionAwareCombining()
%TESTPDSCHHARQPOSITIONAWARECOMBINING Add only matching mother-code positions.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
manager = sixgr.pdsch.PDSCHHARQManager(struct("MaxProcesses", 16));
mask0 = false(16,1); mask0([1 3 5 7]) = true;
llr0 = zeros(16,1); llr0(mask0) = 1;
[~, first] = manager.process(PDSCHPhaseTestSupport.harqObservation( ...
    "RateRecoveredLLR", llr0, "ValidPositionMask", mask0));
assert(~first.Combined);

mask2 = false(16,1); mask2([3 4 7 8]) = true;
llr2 = zeros(16,1); llr2(mask2) = 2;
[context, second] = manager.process(PDSCHPhaseTestSupport.harqObservation( ...
    "NewData", false, "RV", 2, ...
    "RateRecoveredLLR", llr2, "ValidPositionMask", mask2));
data = context.toStruct();
assert(second.Combined);
assert(data.CircularBufferLLR(1) == 1);
assert(data.CircularBufferLLR(3) == 3);
assert(data.CircularBufferLLR(4) == 2);
assert(data.CircularBufferLLR(2) == 0);
assert(nnz(data.ValidPositionMask) == 6);
fprintf("PDSCH HARQ position-aware combining passed.\\n");
ok = true;
end
