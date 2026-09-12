function ok = testPDCCHGrantBindingEvidenceReport()
%TESTPDCCHGRANTBINDINGEVIDENCEREPORT Strict root gate must export grant/DCI binding evidence.

setup6GRSimToolkit("Verbose", false);

ctx = llsRootGateFixture("honest_study");
scfg = sixgr.util.structSet(ctx.ScenarioConfig, "control_gating.pdcch_required", true);
cfg = sixgr.util.structSet(ctx.InternalConfig, "control_gating.pdcch_required", true);

sixgr.util.ensureDir(fullfile(ctx.Layout.ControlCSVDir, ".keep"));
localWriteBoundDataTrials(fullfile(ctx.Layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), "DL");
localWriteBoundDataTrials(fullfile(ctx.Layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), "UL");
sixgr.util.csvWriteTable(fullfile(ctx.Layout.ControlCSVDir, "pdcch_trials.csv"), localFailingControlBindingTrial());

sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder, scfg, cfg);

statusT = readtable(fullfile(ctx.Layout.ReportCSVDir, "result_status_summary.csv"), "VariableNamingRule", "preserve");
bindingT = readtable(fullfile(ctx.Layout.ReportCSVDir, "pdcch_grant_binding_evidence.csv"), "VariableNamingRule", "preserve");

assert(~isempty(bindingT) && height(bindingT) > 0, ...
    "Strict root gate must write non-empty PDCCH grant binding evidence when binding is required.");
assert(all(ismember(["Direction","CellId","UeId","CanonicalSlot","GrantId","DCIId","HARQProcessId","RNTI", ...
    "SearchSpaceId","CORESETId","AggregationLevel","CandidateIndex","DCIFormat","DCIFieldsHash","GrantFieldsHash", ...
    "DecodedPDCCHCRCOK","BindingStatus","FailureCode"], string(bindingT.Properties.VariableNames))), ...
    "PDCCH grant binding evidence export must contain the requested columns.");
assert(~logical(statusT.PDCCHGrantBindingOk(1)), ...
    "Result status must expose PDCCHGrantBindingOk=false when decoded DCI binding fails.");
assert(~logical(statusT.ResultOk(1)), ...
    "A strict run with decoded DCI/grant binding failure must not pass the final result gate.");

failed = bindingT(string(bindingT.Direction) == "DL" & string(bindingT.GrantId) == "grant_1", :);
assert(height(failed) == 1, ...
    "The failing bound grant must appear exactly once in the exported evidence table.");
assert(string(failed.BindingStatus(1)) == "failed" && string(failed.FailureCode(1)) == "dci_grant_fields_hash_mismatch", ...
    "The evidence row must preserve the concrete binding failure.");
assert(contains(string(statusT.ResultStatusReason(1)), "pdcch_grant_binding_gate_failed"), ...
    "Root result status reason must name the PDCCH grant binding gate when it fails.");

% Presence in only one enabled direction is not complete binding evidence.
% A good control row must not hide contradictory data-side receiver fields.
control=localFailingControlBindingTrial();
control.DCIFieldsHash="hash_dl_1"; control.GrantFieldsHash="hash_dl_1";
control.GrantBindingOk=true; control.GrantBindingStatus="bound";
control.GrantBindingFailureCode="";
sixgr.util.csvWriteTable(fullfile(ctx.Layout.ControlCSVDir,"pdcch_trials.csv"),control);
dlPath=fullfile(ctx.Layout.AirInterfaceCSVDir,"dl_pdsch_trials.csv");
dl=readtable(dlPath,"VariableNamingRule","preserve");
dl.ExecutionBackend=repmat("scheduler_shared_stream_receiver",height(dl),1);
for field=["DCICrcPass","PDCCHGrantBindingRequired","ControlDecodeOk", ...
        "PDCCHPayloadMatch","PDCCHCausalGrantDecodeOk"]
    dl.(field)=true(height(dl),1);
end
for field=["DCICrcPass","PDCCHGrantBindingRequired","ControlDecodeOk", ...
        "PDCCHPayloadMatch","PDCCHCausalGrantDecodeOk"]
    bad=dl; bad.(field)(1)=false;
    sixgr.util.csvWriteTable(dlPath,bad);
    sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder,scfg,cfg);
    binding=readtable(fullfile(ctx.Layout.ReportCSVDir,"pdcch_grant_binding_evidence.csv"), ...
        "VariableNamingRule","preserve");
    row=binding(string(binding.Direction)=="DL" & string(binding.GrantId)=="grant_1",:);
    assert(height(row)==1 && string(row.BindingStatus)=="failed" && ...
        contains(string(row.FailureCode),"data_trial_"), ...
        'A bound control row must not hide missing received data evidence: %s.',field);
end
sixgr.util.csvWriteTable(dlPath,dl);
sixgr.truth.evaluateLLSRuntimeTruthContract(ctx.RunFolder,scfg,cfg);
status=readtable(fullfile(ctx.Layout.ReportCSVDir,"result_status_summary.csv"), ...
    "VariableNamingRule","preserve");
assert(status.PDCCHGrantBindingOk,'Consistent complete control/data evidence must pass.');

% Presence in only one enabled direction is not complete binding evidence.
% This catches the former reduction defect where one bound DL row allowed a
% bidirectional run to report PDCCHGrantBindingOk=true with no UL row.
missingUL = llsRootGateFixture("honest_study");
missingULScfg = sixgr.util.structSet(missingUL.ScenarioConfig, ...
    "control_gating.pdcch_required", true);
missingULCfg = sixgr.util.structSet(missingUL.InternalConfig, ...
    "control_gating.pdcch_required", true);
localWriteBoundDataTrials(fullfile(missingUL.Layout.AirInterfaceCSVDir, ...
    "dl_pdsch_trials.csv"), "DL");
ulPath = fullfile(missingUL.Layout.AirInterfaceCSVDir, ...
    "ul_pusch_trials.csv");
ulT = readtable(ulPath, "VariableNamingRule", "preserve");
sixgr.util.csvWriteTable(ulPath, ulT([], :));
missingULVerdict = sixgr.truth.evaluateLLSRuntimeTruthContract( ...
    missingUL.RunFolder, missingULScfg, missingULCfg);
missingULStatus = readtable(fullfile(missingUL.Layout.ReportCSVDir, ...
    "result_status_summary.csv"), "VariableNamingRule", "preserve");
assert(~logical(missingULStatus.PDCCHGrantBindingOk(1)), ...
    "A bidirectional strict run must fail when UL binding evidence is absent.");
assert(any(contains(lower(string(missingULVerdict.Failures)), ...
    "missing_required_grant_binding_evidence_ul")), ...
    "The PDCCH binding summary must identify the missing UL direction.");

ok = true;
end

function localWriteBoundDataTrials(pathValue, direction)
T = readtable(pathValue, "VariableNamingRule", "preserve");
n = height(T);
suffix = lower(string(direction));

T.GrantContextId = string(T.GrantId);
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

function T = localFailingControlBindingTrial()
T = table();
T.Direction = "DL";
T.LinkedPDSCHOrPUSCH = "DL";
T.BaseStationID = 1;
T.UEID = 1;
T.GrantSlot = 0;
T.GrantContextId = "grant_1";
T.LinkedGrantId = "grant_1";
T.DCIId = "dci_dl_1";
T.HARQProcessId = 0;
T.PDCCHDCICrcRNTI = 4660;
T.SearchSpaceId = 1;
T.CORESETId = 2;
T.AggregationLevel = 4;
T.CandidateIndex = 0;
T.DCIFormat = "1_0";
T.DCIFieldsHash = "dci_hash_bad";
T.GrantFieldsHash = "grant_hash_good";
T.DCICrcPass = true;
T.PDCCHPayloadMatch = true;
T.PDCCHCausalGrantDecodeOk = true;
T.StrictOk = true;
T.GrantValid = true;
T.GrantBindingRequired = true;
T.GrantBindingOk = false;
T.GrantBindingStatus = "failed";
T.GrantBindingFailureCode = "dci_grant_fields_hash_mismatch";
T.ProxyUsed = false;
T.Skipped = false;
T.ToolboxMissing = false;
T.FallbackFlag = false;
T.PlaceholderFlag = false;
T.PDCCHFalseAlarm = false;
T.PDCCHMissedDetection = false;
T.NegativeExpectedOk = true;
T.PDCCHBlindSearchEnabled = true;
T.PDCCHREGMappingAvailable = true;
T.PDCCHRECount = 108;
T.PDCCHDMRSRECount = 36;
T.PDCCHEncodedBits = 216;
T.PDCCHScramblingRNTI = 4660;
T.CandidatesAttempted = 9;
T.PDCCHCandidatesAttempted = 9;
T.BlindDecodeCount = 9;
T.PDCCHGridHash = "grid_hash";
T.PDCCHWaveformHash = "waveform_hash";
T.PDCCHResourceHash = "resource_hash";
T.PDCCHCRCDecodeSource = "nrDCIDecode_crc_masked_by_rnti";
T.PDCCHBlindDecodeEvidenceSource = "nrPDCCHSpace_nrPDCCHDecode_nrDCIDecode";
T.PDCCHCCE_REGMappingEvidence = "nrPDCCHResources_coreset_search_space_candidate_mapping";
T.ChannelEstimateSource = "nrChannelEstimate_pdcch_dmrs";
T.RuntimeEvidenceSource = "sixgr.phy.dl.PDCCH_Tx|sixgr.phy.dl.PDCCH_Rx";
T.TruthStatus = "real_pdcch_waveform_blind_dci_crc_evidence";
T.StrictReceiverEvidenceOk = true;
T.DecodeAttempted = true;
T.DecodeUsable = true;
T.ReceiverUsable = true;
T.DetectionAttempted = true;
T.DetectionUsable = true;
end
