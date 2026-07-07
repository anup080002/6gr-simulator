function ok = testPDCCHGrantBindingEvidenceCompleteness()
%TESTPDCCHGRANTBINDINGEVIDENCECOMPLETENESS Bound status alone is not DCI evidence.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("honest_study");
scfg = sixgr.util.structSet(ctx.ScenarioConfig, "validation.dl_pdsch.require_pdcch_grant_reference", true);
cfg = sixgr.util.structSet(ctx.InternalConfig, "validation.dl_pdsch.require_pdcch_grant_reference", true);

pathValue = fullfile(ctx.Layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv");
T = readtable(pathValue, "VariableNamingRule", "preserve");
n = height(T);

T.GrantContextId = "grant_missing_dci_" + string((1:n).');
T.BaseStationID = ones(n, 1);
T.UEID = ones(n, 1);
T.RNTI = repmat(4660, n, 1);
T.HARQProcessId = zeros(n, 1);
T.DCICrcPass = false(n, 1);
T.PDCCHGrantBindingRequired = true(n, 1);
T.PDCCHGrantBindingOk = true(n, 1);
T.PDCCHGrantBindingStatus = repmat("bound", n, 1);
T.PDCCHGrantBindingFailureCode = repmat("", n, 1);
T.PDCCHGrantDCIId = repmat("", n, 1);
T.PDCCHGrantDCIFieldsHash = "hash_" + string((1:n).');
T.PDCCHGrantFieldsHash = T.PDCCHGrantDCIFieldsHash;
T.PDCCHGrantSearchSpaceId = ones(n, 1);
T.PDCCHGrantCORESETId = 2 * ones(n, 1);
T.PDCCHGrantAggregationLevel = 4 * ones(n, 1);
T.PDCCHGrantCandidateIndex = zeros(n, 1);
T.PDCCHGrantDCIFormat = repmat("1_0", n, 1);
sixgr.util.csvWriteTable(pathValue, T);

sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, scfg, cfg);

statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), "VariableNamingRule", "preserve");
bindingT = readtable(fullfile(ctx.Layout.ReportCSVDir, "pdcch_grant_binding_evidence.csv"), "VariableNamingRule", "preserve");

assert(~logical(statusT.PDCCHGrantBindingOk(1)), ...
    "Strict result gate must fail when a required bound data grant lacks decoded DCI evidence.");
assert(all(string(bindingT.BindingStatus) == "failed"), ...
    "Evidence rows with missing decoded DCI must be rewritten to failed.");
assert(any(contains(string(bindingT.FailureCode), "decoded_dci_missing")), ...
    "Missing decoded DCI identity must be reported explicitly.");
assert(any(contains(string(bindingT.FailureCode), "decoded_dci_crc_failed")), ...
    "Failed or missing decoded PDCCH CRC evidence must be reported explicitly.");

ok = true;
end
