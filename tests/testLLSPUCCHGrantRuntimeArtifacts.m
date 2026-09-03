function ok = testLLSPUCCHGrantRuntimeArtifacts()
%TESTLLSPUCCHGRANTRUNTIMEARTIFACTS Verify canonical PUCCH grant/runtime artifact export.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scfg = sixgr.lls6g.config.loadScenarioConfig( ...
    fullfile(pwd, "simulator", "configs", "scenarios", "lls_100mhz_tdlc_bidirectional_truth.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
frameIdentity = sixgr.util.structGet(cfg, "phy.frame.DefaultIdentity", struct());
canonicalCC = double(sixgr.util.structGet(frameIdentity, "ScheduledCCID", NaN));
canonicalULBWP = double(sixgr.util.structGet(frameIdentity, "ULBWPID", NaN));
assert(isfinite(canonicalCC) && isfinite(canonicalULBWP), ...
    "Focused PUCCH runtime artifact fixture requires canonical CC/UL-BWP identity.");
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 35;
cfg.phy.pucch.format = 2;
cfg.run.noiseOperatingMode = "receiver_noise_figure_thermal_noise";
cfg.run.interferenceExecutionMode = "full_per_link_channel_waveform_sum";

multiUserRuntime = struct( ...
    "Enabled", true, ...
    "NumUsers", 2, ...
    "RNTIStart", 320, ...
    "ExecutionModel", "slot_coupled_truth");
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg, fullfile(tmp, "runtime"), multiUserRuntime, struct(), 1);
state.CurrentServingIdx(1:2) = 1;
state.CurrentServingMetric_dBm(1:2) = -70;
state.LargeScaleState.BeamIndex = ones(2, 1);
state.LargeScaleState.BeamGain_dB = zeros(2, 1);
state.LargeScaleState.RxPower_dBm = -70 * ones(2, 1);
state.LargeScaleState.BasePathloss_dB = 100 * ones(2, 1);
state.LargeScaleState.Pathloss_dB = 100 * ones(2, 1);
state.LargeScaleState.Shadow_dB = zeros(2, 1);
state.LargeScaleState.O2I_dB = zeros(2, 1);
state.CurrentSlot = 5;
state.CurrentFrame = 1;
state.CurrentSNR_dB = 35;

feedbackRows = repmat(localEmptyFeedbackRow(), 2, 1);
for ueIdx = 1:2
    feedbackRows(ueIdx).Direction = "DL";
    feedbackRows(ueIdx).UEIndex = ueIdx;
    feedbackRows(ueIdx).RNTI = double(multiUserRuntime.RNTIStart + ueIdx - 1);
    feedbackRows(ueIdx).HarqID = ueIdx - 1;
    feedbackRows(ueIdx).SourceSlot = 1;
    feedbackRows(ueIdx).DueSlot = 5;
    feedbackRows(ueIdx).Ack = true;
    feedbackRows(ueIdx).CurrentDecodeOK = true;
    feedbackRows(ueIdx).CombinedDecodeOK = true;
    feedbackRows(ueIdx).ServingCell = 1;
    feedbackRows(ueIdx).BaseStationID = 1;
    feedbackRows(ueIdx).ComponentCarrier = canonicalCC;
    feedbackRows(ueIdx).ActiveULBWP = canonicalULBWP;
    feedbackRows(ueIdx).TBSBits = 5376;
    feedbackRows(ueIdx).UCIBitCount = 1;
    seedRow = struct2table(feedbackRows(ueIdx), "AsArray", true);
    resource = sixgr.truth.CoupledTruthRuntime.resolvePUCCHResourceAssignmentRuntime(state, seedRow);
    feedbackRows(ueIdx).RequestedFormat = double(resource.RequestedFormat);
    feedbackRows(ueIdx).ResolvedFormat = double(resource.ResolvedFormat);
    feedbackRows(ueIdx).PUCCHResourceId = char(string(resource.ResourceId));
    feedbackRows(ueIdx).PUCCHPRBStart = double(resource.PRBStart);
    feedbackRows(ueIdx).PUCCHPRBCount = double(resource.PRBCount);
    feedbackRows(ueIdx).PUCCHSymbolStart = double(resource.SymbolStart);
    feedbackRows(ueIdx).PUCCHNumSymbols = double(resource.NumSymbols);
    feedbackRows(ueIdx).UCIType = char(string(resource.UCIType));
    feedbackRows(ueIdx).ControlResourceSource = char(string(resource.ControlResourceSource));
end
state.PendingFeedbackTable = struct2table(feedbackRows, "AsArray", true);
for ueIdx = 1:2
    state = sixgr.truth.CoupledTruthRuntime.schedulePUCCHGrantRuntime(state, state.PendingFeedbackTable(ueIdx, :));
end
[state, ~] = sixgr.truth.CoupledTruthRuntime.observePUCCHFeedbackRuntime(state, state.PUCCHGrantTraceTable(1, :));
state = sixgr.truth.CoupledTruthRuntime.writeTables(state, fullfile(tmp, "runtime"));

grantCsv = fullfile(tmp, "runtime", "packet_flow", "csv", "live_pucch_grants.csv");
trialCsv = fullfile(tmp, "runtime", "air_interface", "csv", "pucch_trials.csv");
assert(exist(grantCsv, "file") == 2, ...
    "Canonical runtime PUCCH grant artifact must be exported to packet_flow/csv/live_pucch_grants.csv.");
assert(exist(trialCsv, "file") == 2, ...
    "Canonical runtime PUCCH trial artifact must still be exported to air_interface/csv/pucch_trials.csv.");

grants = readtable(grantCsv, "VariableNamingRule", "preserve");
trials = readtable(trialCsv, "VariableNamingRule", "preserve");
assert(~isempty(grants) && ~isempty(trials), ...
    "Generated PUCCH grant and trial artifacts must contain runtime-backed rows.");
assert(all(ismember(["UEID","BaseStationID","Frame","Slot","PUCCHGrantId","PUCCHResourceId","UCIType","InterferenceMode","RuntimeStateConsumer","StateChangeApplied"], ...
    string(grants.Properties.VariableNames))), ...
    "Canonical PUCCH grant artifact must expose truthful runtime context and state-change fields.");
assert(all(ismember(["UEID","BaseStationID","Frame","Slot","PUCCHGrantId","PUCCHResourceId","UCIType","InterferenceMode","RuntimeStateConsumer","StateChangeApplied"], ...
    string(trials.Properties.VariableNames))), ...
    "Canonical PUCCH trial artifact must expose truthful runtime context and state-change fields.");
assert(all(ismember(["SignalFamily","SourceClassification","RuntimeMaterializationStatus","ControlGatingEffect", ...
    "DecodeSuccess","SuccessFlag","FailureFlag","ControlObservationAvailable","ValueStatus","NAReason"], ...
    string(grants.Properties.VariableNames))), ...
    "Canonical PUCCH grant artifact must expose the source/status contract for observed and pending feedback.");
assert(all(ismember(["SignalFamily","SourceClassification","RuntimeMaterializationStatus","ControlGatingEffect", ...
    "DecodeSuccess","SuccessFlag","FailureFlag","ControlObservationAvailable","ValueStatus"], ...
    string(trials.Properties.VariableNames))), ...
    "Canonical PUCCH trial artifact must expose the source/status contract for waveform-observed feedback.");
assert(all(ismember(["ConfiguredSNR_dB","ConfiguredSNRSource","SNRValueRole","ReceiverHestSINR_dB","ReceiverHestSINRSource", ...
    "ReceiverHestSINRValueRole","ReceiverHestSINRValueStatus","MeasuredTrialSINR_dB","MeasuredTrialSINRSource", ...
    "MeasuredTrialSINRValueRole","MeasuredTrialSINRValueStatus","MeasuredSINR_dB","SINRValueRole","SINRSource","SINRValueStatus","SINRValueDefinition"], ...
    string(trials.Properties.VariableNames))), ...
    "Canonical PUCCH trial artifact must expose the honest control SINR separation contract.");
assert(~any(strcmpi(string(trials.SINRValueRole), "estimated_control_dmrs_measurement")), ...
    "Canonical PUCCH trial artifact must not use the old flattened control SINR role.");
measuredMask = isfinite(double(trials.MeasuredTrialSINR_dB));
if any(measuredMask)
    assert(all(abs(double(trials.MeasuredSINR_dB(measuredMask)) - double(trials.MeasuredTrialSINR_dB(measuredMask))) < 1e-9), ...
        "Canonical PUCCH trial artifact must alias MeasuredSINR only from real measured-trial SINR.");
    assert(all(strcmpi(string(trials.MeasuredTrialSINRValueRole(measuredMask)), "measured")) && ...
        all(strcmpi(string(trials.MeasuredTrialSINRValueStatus(measuredMask)), "OK")), ...
        "Canonical PUCCH trial artifact must label measured-trial SINR explicitly as measured.");
end
receiverOnlyMask = ~isfinite(double(trials.MeasuredTrialSINR_dB)) & isfinite(double(trials.ReceiverHestSINR_dB));
if any(receiverOnlyMask)
    assert(all(~isfinite(double(trials.MeasuredSINR_dB(receiverOnlyMask)))), ...
        "Canonical PUCCH trial artifact must not fabricate MeasuredSINR when only receiver-estimated SINR exists.");
    assert(all(~strcmpi(string(trials.SINRValueRole(receiverOnlyMask)), "measured")), ...
        "Canonical PUCCH trial artifact must not label receiver-only SINR rows as measured.");
end
assert(any(strcmpi(string(grants.Status), "PENDING")) && any(strcmpi(string(grants.SourceClassification), "active_but_simplified")), ...
    "Scheduled PUCCH grants whose feedback due slot was not processed must be labeled pending, not as successful decode truth.");
assert(any(strcmpi(string(trials.SourceClassification), "active_integrated")) && ...
    all(strcmpi(string(trials.RuntimeMaterializationStatus), "active_integrated_waveform_feedback_runtime")), ...
    "PUCCH waveform observation rows must be labeled as active integrated runtime evidence.");

grantRow = grants(end, :);
trialRow = trials(end, :);
matchIdx = find(strcmp(string(grants.PUCCHGrantId), string(trialRow.PUCCHGrantId(1))), 1, "last");
assert(~isempty(matchIdx), ...
    "Canonical PUCCH trial rows must reference an existing explicit PUCCH grant row.");
grantRow = grants(matchIdx, :);
assert(strlength(string(grantRow.PUCCHGrantId(1))) > 0 && strcmpi(char(string(grantRow.PUCCHGrantId(1))), char(string(trialRow.PUCCHGrantId(1)))), ...
    "PUCCH trial rows must link back to the explicit runtime PUCCH grant row.");
assert(double(grantRow.UEID(1)) == double(grantRow.UEIndex(1)) && double(grantRow.BaseStationID(1)) == 1 && ...
    strlength(string(grantRow.PUCCHResourceId(1))) > 0 && strcmpi(char(string(grantRow.UCIType(1))), "harq_ack"), ...
    "Canonical PUCCH grant rows must expose UE/base-station identity, resource identity, and UCI content type.");
assert(logical(grantRow.GrantScheduledFlag(1)) && logical(grantRow.GrantExecutedFlag(1)) && ...
    strcmpi(char(string(grantRow.RuntimeStateConsumer(1))), "HARQEntity.onFeedback") && ...
    logical(grantRow.StateChangeApplied(1)) == logical(grantRow.PUCCHDecodeOk(1)), ...
    "Canonical PUCCH grant rows must disclose scheduled/executed state and the runtime state consumer honestly.");

ok = true;
end

function row = localEmptyFeedbackRow()
row = struct( ...
    "Direction", "", "UEIndex", NaN, "RNTI", NaN, ...
    "HarqID", NaN, "SourceSlot", NaN, "DueSlot", NaN, "Ack", false, ...
    "CurrentDecodeOK", false, "CombinedDecodeOK", false, ...
    "ServingCell", NaN, "BaseStationID", NaN, ...
    "ComponentCarrier", NaN, "ActiveULBWP", NaN, ...
    "TBSBits", NaN, "UCIBitCount", NaN, ...
    "RequestedFormat", NaN, "ResolvedFormat", NaN, "PUCCHResourceId", "", ...
    "PUCCHPRBStart", NaN, "PUCCHPRBCount", NaN, ...
    "PUCCHSymbolStart", NaN, "PUCCHNumSymbols", NaN, ...
    "UCIType", "", "ControlResourceSource", "", "PUCCHGrantId", "", "Processed", false);
end
