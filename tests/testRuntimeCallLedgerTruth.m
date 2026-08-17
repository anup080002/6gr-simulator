function ok = testRuntimeCallLedgerTruth()
%TESTRUNTIMECALLLEDGERTRUTH Ledger is exact, identified runtime evidence.
setup6GRSimToolkit("Verbose",false);
localAssertRunnerFlushOrdering();
root = tempname(); mkdir(root);
cleanup = onCleanup(@()localCleanup(root)); %#ok<NASGU>
sixgr.runtime.RuntimeCallLedger.reset();
sixgr.runtime.RuntimeCallLedger.configure(root,struct( ...
    "RunId","unit","ExecutionID","exec-unit", ...
    "ConfigHash",string(repmat('a',1,64))));
sixgr.runtime.RuntimeCallLedger.record("sixgr.phy.dl.PDSCH_Tx", ...
    "PDSCH","DL",struct("Stage","TX"));
sixgr.runtime.RuntimeCallLedger.record("sixgr.phy.dl.PDSCH_Rx", ...
    "PDSCH","DL",struct("Stage","RX"));
T = sixgr.runtime.RuntimeCallLedger.flush();
assert(height(T)==2 && all(T.EvidenceClass=="ACTUAL_RUNTIME_ENTRY"));
assert(all(strlength(T.ConfigHash)==64) && all(T.ExecutionID=="exec-unit"));
sixgr.runtime.RuntimeCallLedger.appendObservedRows(T);
merged = sixgr.runtime.RuntimeCallLedger.flush();
assert(height(merged)==4 && isequal(double(merged.Sequence),(1:4).') && ...
    all(merged.RunId=="unit") && all(merged.ExecutionID=="exec-unit"), ...
    "Identity-bound worker observations were not merged exactly.");
G = sixgr.analytics.buildRuntimeCallGraph(root);
callT = readtable(G.Path,"TextType","string");
assert(height(callT)==2 && all(callT.EvidenceClass=="ACTUAL_RUNTIME_ENTRY") && ...
    all(double(callT.NumCalls)==2));
audit = sixgr.analytics.buildPHYPackageExecutionAudit(root,pwd);
required = logical(audit.GateTable.Required);
assert(any(required) && all(logical(audit.GateTable.Pass(required))), ...
    "Runtime call ledger must satisfy required functional execution-evidence gates without a profiler.");
pdsch = audit.DetailTable.Package=="PDSCH" & ...
    ismember(audit.DetailTable.QualifiedName, ...
    ["sixgr.phy.dl.PDSCH_Tx","sixgr.phy.dl.PDSCH_Rx"]);
assert(nnz(pdsch)==2 && all(audit.DetailTable.ActuallyCalled(pdsch)));
ok=true;
fprintf("PASS testRuntimeCallLedgerTruth: canonical runtime entries are identity-bound.\n");
end

function localAssertRunnerFlushOrdering()
runnerPath = which("sixgr.lls6g.runners.runSingle");
assert(strlength(string(runnerPath)) > 0, ...
    "The production LLS runner must be discoverable on the MATLAB path.");
source = string(fileread(runnerPath));
flushPositions = strfind(source, ...
    "sixgr.runtime.RuntimeCallLedger.flush();");
reportPosition = strfind(source, ...
    "reportBundle = sixgr.truth.exportLLSReportingBundle");
assert(~isempty(flushPositions) && isscalar(reportPosition) && ...
    any(flushPositions < reportPosition), ...
    ["The identity-bound runtime ledger must be flushed before the " ...
    "reporting bundle evaluates required wiring evidence."]);
end

function localCleanup(root)
sixgr.runtime.RuntimeCallLedger.reset();
if isfolder(root), rmdir(root,"s"); end
end
