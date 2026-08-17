function ok = testRuntimeCallLedgerResumePreservation()
%TESTRUNTIMECALLLEDGERRESUMEPRESERVATION Resume must retain actual entries.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = string(tempname);
mkdir(root);
cleanup = onCleanup(@() localCleanup(root)); %#ok<NASGU>
identity = struct("RunId", "run_1", "ExecutionID", "execution_1", ...
    "ConfigHash", string(repmat('a', 1, 64)));

sixgr.runtime.RuntimeCallLedger.reset();
sixgr.runtime.RuntimeCallLedger.configure(root, identity);
sixgr.runtime.RuntimeCallLedger.record("PDSCH_Tx", "PDSCH", "DL", ...
    struct("Trial", 1));
sixgr.runtime.RuntimeCallLedger.record("PDSCH_Rx", "PDSCH", "DL", ...
    struct("Trial", 1));
first = sixgr.runtime.RuntimeCallLedger.flush();
assert(height(first) == 2 && isequal(double(first.Sequence), [1; 2]));

sixgr.runtime.RuntimeCallLedger.reset();
resumeIdentity = identity;
resumeIdentity.PreserveExisting = true;
sixgr.runtime.RuntimeCallLedger.configure(root, resumeIdentity);
preserved = sixgr.runtime.RuntimeCallLedger.snapshot();
assert(height(preserved) == 2, ...
    "Resume must load existing actual runtime entries before finalization.");
sixgr.runtime.RuntimeCallLedger.record("finalize", "REPORT", "", ...
    struct("DerivedOnly", true));
combined = sixgr.runtime.RuntimeCallLedger.flush();
assert(height(combined) == 3 && ...
    isequal(double(combined.Sequence), [1; 2; 3]));
persisted = readtable(fullfile(root, "reports", "csv", ...
    "runtime_call_ledger.csv"), "TextType", "string", ...
    "VariableNamingRule", "preserve");
assert(height(persisted) == 3 && ...
    all(string(persisted.EvidenceClass) == "ACTUAL_RUNTIME_ENTRY"));

sixgr.runtime.RuntimeCallLedger.reset();
badIdentity = resumeIdentity;
badIdentity.ExecutionID = "different_execution";
assert(localThrows(@() sixgr.runtime.RuntimeCallLedger.configure( ...
    root, badIdentity), ...
    "sixgr:runtime:RuntimeCallLedgerResumeIdentityMismatch"));

ok = true;
end

function tf = localThrows(fn, expectedIdentifier)
tf = false;
try
    fn();
catch ME
    tf = string(ME.identifier) == string(expectedIdentifier);
end
end

function localCleanup(root)
sixgr.runtime.RuntimeCallLedger.reset();
if isfolder(root)
    rmdir(root, "s");
end
end
