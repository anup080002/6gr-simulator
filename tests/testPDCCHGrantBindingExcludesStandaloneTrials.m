function ok = testPDCCHGrantBindingExcludesStandaloneTrials()
%TESTPDCCHGRANTBINDINGEXCLUDESSTANDALONETRIALS Blind-search tests are not grants.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("honest_study");
scfg = sixgr.util.structSet(ctx.ScenarioConfig, ...
    "control_gating.pdcch_required", true);
cfg = sixgr.util.structSet(ctx.InternalConfig, ...
    "control_gating.pdcch_required", true);

dlCount = localWriteBoundDataTrials( ...
    fullfile(ctx.Layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), "DL");
ulCount = localWriteBoundDataTrials( ...
    fullfile(ctx.Layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), "UL");

% These are physical PDCCH conformance trials, including an expected
% negative case. Neither row schedules a data grant.
standalone = table([""; ""], ["positive_waveform"; "wrong_rnti_negative"], ...
    [true; false], [true; true], [false; false], [false; false], ...
    'VariableNames', {'Direction','TrialType','DCICrcPass','StrictOk', ...
    'GrantBindingRequired','GrantBindingOk'});
sixgr.util.csvWriteTable( ...
    fullfile(ctx.Layout.ControlCSVDir, "pdcch_trials.csv"), standalone);

sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, scfg, cfg);
statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, ...
    "result_status_summary.csv"), "VariableNamingRule", "preserve");
bindingT = readtable(fullfile(ctx.Layout.ReportCSVDir, ...
    "pdcch_grant_binding_evidence.csv"), "VariableNamingRule", "preserve");

assert(logical(statusT.PDCCHGrantBindingOk(1)), ...
    "Standalone blind-search trials must not fail the scheduler grant-binding gate.");
assert(height(bindingT) == dlCount + ulCount && ...
    all(strlength(strtrim(string(bindingT.GrantId))) > 0) && ...
    all(string(bindingT.BindingStatus) == "bound"), ...
    "Grant-binding evidence must contain only concrete bound DL/UL grants.");

% Calibration/fixed-link execution that does not require decoded-DCI grant
% binding must expose that objective as non-mandatory.  A vacuous pass may
% describe applicability, but it must not be counted as required evidence.
optionalCtx = llsRootGateFixture("honest_study");
sixgr.truth.evaluateLLSRuntimeTruthContract(optionalCtx.RunFolder, ...
    optionalCtx.ScenarioConfig, optionalCtx.InternalConfig);
objectiveT = readtable(fullfile(optionalCtx.Layout.ReportCSVDir, ...
    "scenario_objective_gates.csv"), "VariableNamingRule", "preserve");
pdcchRow = string(objectiveT.ObjectiveName) == "pdcch_grant_binding";
assert(nnz(pdcchRow) == 1 && ~logical(objectiveT.Mandatory(pdcchRow)) && ...
    logical(objectiveT.Pass(pdcchRow)), ...
    "Non-required PDCCH binding must be explicitly non-mandatory in scenario objectives.");
ok = true;
end

function n = localWriteBoundDataTrials(pathValue, direction)
T = readtable(pathValue, "VariableNamingRule", "preserve");
n = height(T);
suffix = lower(string(direction));
T.GrantContextId = "grant_" + suffix + "_" + string((1:n).');
T.BaseStationID = ones(n, 1);
T.UEID = ones(n, 1);
T.RNTI = repmat(4660, n, 1);
T.HARQProcessId = (0:n-1).';
T.DCICrcPass = true(n, 1);
T.PDCCHGrantBindingRequired = true(n, 1);
T.PDCCHGrantBindingOk = true(n, 1);
T.PDCCHGrantBindingStatus = repmat("bound", n, 1);
T.PDCCHGrantBindingFailureCode = repmat("", n, 1);
T.PDCCHGrantDCIId = "dci_" + suffix + "_" + string((1:n).');
T.PDCCHGrantDCIFieldsHash = "hash_" + suffix + "_" + string((1:n).');
T.PDCCHGrantFieldsHash = T.PDCCHGrantDCIFieldsHash;
T.PDCCHGrantSearchSpaceId = ones(n, 1);
T.PDCCHGrantCORESETId = 2 * ones(n, 1);
T.PDCCHGrantAggregationLevel = 4 * ones(n, 1);
T.PDCCHGrantCandidateIndex = zeros(n, 1);
T.PDCCHGrantDCIFormat = repmat("1_0", n, 1);
sixgr.util.csvWriteTable(pathValue, T);
end
