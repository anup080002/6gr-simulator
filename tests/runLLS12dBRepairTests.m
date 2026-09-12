function receipt = runLLS12dBRepairTests(receiptPath)
% Explicit focused suite only; never launches testAll or a full scenario.
arguments
    receiptPath (1,1) string
end
setup6GRSimToolkit('Verbose',false);
names=["testRunEvidenceLifecycle","testPDCCHReceivedGrantClock", ...
    "testPDCCHGrantBindingEvidenceReport","testCSIMeasuredStateSchedulingSINRAuthority", ...
    "testPhase7PhysicalChannelReconciliation","testTDDRankOneTwoPortCSIRSSpatialContract", ...
    "testSharedQCLTimingTransfer","testChannelCorrelationNotQCL"];
receipt=struct('Suite',"focused_12dB_repairs",'Status',"RUNNING", ...
    'Tests',repmat(struct('Name',"",'Status',"NOT_RUN",'Seconds',NaN,'Error',""),numel(names),1));
for k=1:numel(names)
    receipt.Tests(k).Name=names(k); started=tic;
    try
        assert(feval(names(k)));
        receipt.Tests(k).Status="PASS";
    catch ME
        receipt.Tests(k).Status="FAIL";
        receipt.Tests(k).Error=string(getReport(ME,'extended','hyperlinks','off'));
    end
    receipt.Tests(k).Seconds=toc(started);
    sixgr.util.jsonWrite(receiptPath,receipt);
end
receipt.Status="PASS";
if any(string({receipt.Tests.Status})~="PASS"), receipt.Status="FAIL"; end
sixgr.util.jsonWrite(receiptPath,receipt);
assert(receipt.Status=="PASS",'sixgr:test:FocusedRepairsFailed', ...
    'Focused repair failures are recorded in %s.',receiptPath);
end
