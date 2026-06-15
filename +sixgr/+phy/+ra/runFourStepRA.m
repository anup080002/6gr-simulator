function result = runFourStepRA(cfg, varargin)
%RUNFOURSTEPRA Execute an NR-style contention-based four-step RA anchor.
%
% The receiver side consumes only decoded runtime evidence: PRACH waveform
% correlation, RA-RNTI PDCCH, RAR PDSCH bytes, RAR UL grant, Msg3 PUSCH, and
% Msg4 PDSCH contention identity.

p = inputParser;
p.addParameter("RunFolder", "", @(x)ischar(x) || isstring(x));
p.addParameter("RunId", "ra_anchor", @(x)ischar(x) || isstring(x));
p.addParameter("ScenarioName", "", @(x)ischar(x) || isstring(x));
p.addParameter("UEId", 1, @(x)isnumeric(x) && isscalar(x));
p.addParameter("CellId", [], @(x)isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("AttemptId", 1, @(x)isnumeric(x) && isscalar(x));
p.addParameter("FaultMode", "none", @(x)ischar(x) || isstring(x));
p.addParameter("WriteArtifacts", true, @(x)islogical(x) || isnumeric(x));
p.addParameter("RunNegativeSuite", false, @(x)islogical(x) || isnumeric(x));
p.parse(varargin{:});
opt = p.Results;

localRequireToolboxFunctions();
raCfg = sixgr.mac.ra.RAConfig(cfg, ...
    "RunId", opt.RunId, ...
    "ScenarioName", opt.ScenarioName, ...
    "UEId", opt.UEId, ...
    "CellId", opt.CellId, ...
    "AttemptId", opt.AttemptId);
cfg = sixgr.phy.ra.localizeCarrierConfig(cfg, raCfg);
faultMode = lower(strtrim(string(opt.FaultMode)));
runFolder = string(opt.RunFolder);
if strlength(strtrim(runFolder)) == 0
    runFolder = string(tempname);
end

result = localEmptyResult(raCfg, runFolder, faultMode);
events = localInitialEvents(raCfg);
oracleRows = localOracleGuardRows(raCfg);
timerRows = localTimerRowsStart(raCfg);

try
    [msg1Tx, occasion] = sixgr.phy.ra.generateMsg1PRACHWaveform(cfg, raCfg);
    msg1RxWave = msg1Tx.Waveform;
    if faultMode == "no_prach_detected"
        msg1RxWave(:) = 0;
    end
    det = sixgr.phy.ra.detectMsg1PRACH(msg1RxWave, cfg, raCfg, occasion);
    if isfield(det, "CorrelationTrace")
        result.Msg1DetectionTrace = det.CorrelationTrace;
    end
    ta = sixgr.phy.ra.estimateTimingAdvanceFromPRACH(det);
    detectorAmbiguity = logical(sixgr.util.structGet(det, "MultiCandidateAboveThreshold", false));
    collisionDetected = faultMode == "collision_same_preamble";
    preambleDetected = logical(det.Detected) && double(det.DetectedPreambleIndex) == double(raCfg.PreambleIndex) && ~collisionDetected;
    result = localApplyMsg1(result, raCfg, det, ta, collisionDetected, preambleDetected, detectorAmbiguity);
    events = [events; localEvent(raCfg, "MSG1_PRACH_TX", ternary(preambleDetected, "MSG1_PRACH_DETECTED", "RA_FAILURE"), ...
        "prach_correlation_detection", "", NaN, double(raCfg.RARNTI), double(raCfg.PreambleIndex), ...
        ternary(preambleDetected, "", localFailureForMsg1(collisionDetected)))]; %#ok<AGROW>
    if ~preambleDetected
        result = localFail(result, localFailureForMsg1(collisionDetected), "MSG1_PRACH_DETECTED");
        result = localFinalize(result, raCfg, events, timerRows, oracleRows, msg1Tx, det, struct(), struct(), struct(), struct(), struct(), struct(), struct(), opt);
        return;
    end

    grantTx = sixgr.mac.ra.buildRARULGrant(raCfg);
    rapid = double(raCfg.PreambleIndex);
    if faultMode == "wrong_rapid_in_rar"
        rapid = mod(rapid + 1, 64);
    end
    rarTx = sixgr.mac.ra.encodeMACRAR("RAPID", rapid, ...
        "TimingAdvanceCommand", double(ta.TimingAdvanceCommand), ...
        "TemporaryCRNTI", double(raCfg.TempCRNTI), ...
        "ULGrant", grantTx);
    [msg2Tx, msg2Sched] = sixgr.phy.ra.generateMsg2RARWaveform(cfg, raCfg, rarTx);
    withinWindow = double(raCfg.Msg2Slot) <= double(raCfg.PRACHOccasionSlot) + double(raCfg.RAResponseWindowSlots);
    if faultMode == "response_window_expiry"
        withinWindow = false;
    end
    attemptedRNTI = double(raCfg.RARNTI);
    if faultMode == "wrong_ra_rnti"
        attemptedRNTI = double(raCfg.RARNTI) + 1;
    end
    [pdcchRx, pdcchInfo] = sixgr.phy.ra.blindDecodeRARPDCCH(msg2Tx.Waveform, cfg, raCfg, msg2Sched, ...
        "RNTIAttempted", attemptedRNTI);
    msg2WaveForPDSCH = msg2Tx.Waveform;
    if faultMode == "rar_pdsch_corrupted"
        msg2WaveForPDSCH = localCorruptWaveform(msg2WaveForPDSCH, 0.75);
    end
    rarRx = struct();
    pdschRx2 = struct("Ok", false, "CRCError", true);
    if logical(pdcchRx.Ok) && withinWindow
        [pdschRx2, rarRx] = sixgr.phy.ra.recoverMsg2RAR(msg2WaveForPDSCH, cfg, raCfg, msg2Sched, msg2Tx);
    end
    rapidMatches = isstruct(rarRx) && isfield(rarRx, "RAPID") && double(rarRx.RAPID) == double(raCfg.PreambleIndex);
    if isstruct(rarRx) && isfield(rarRx, "ULGrant")
        grantRx = rarRx.ULGrant;
        grantRx.Modulation = string(raCfg.Msg3PUSCH.Modulation);
        grantRx.TargetCodeRate = double(raCfg.Msg3PUSCH.TargetCodeRate);
        grantRx.RV = double(raCfg.Msg3PUSCH.RV);
        grantRx.NLayers = double(raCfg.Msg3PUSCH.NLayers);
        grantRx.TemporaryCRNTI = double(rarRx.TemporaryCRNTI);
    else
        grantRx = struct();
    end
    grantValidation = sixgr.mac.ra.validateRARULGrant(grantRx, raCfg);
    result = localApplyMsg2(result, raCfg, withinWindow, pdcchRx, pdcchInfo, pdschRx2, rarTx, rarRx, rapidMatches, grantValidation);
    if ~withinWindow || ~logical(pdcchRx.Ok) || ~logical(sixgr.util.structGet(pdschRx2, "Ok", false)) || ~rapidMatches || ~logical(grantValidation.Valid)
        result = localFail(result, localFailureForMsg2(withinWindow, pdcchRx, pdschRx2, rapidMatches, grantValidation), "MSG2_RAR_RX");
        result = localFinalize(result, raCfg, events, timerRows, oracleRows, msg1Tx, det, msg2Tx, pdcchInfo, pdschRx2, rarRx, struct(), struct(), struct(), opt);
        return;
    end
    events = [events; localEvent(raCfg, "MSG2_RAR_TX", "MSG2_RAR_RX", "rar_pdcch_pdsch_decode", "ra-ResponseWindow", ...
        double(raCfg.RAResponseWindowSlots), double(raCfg.RARNTI), double(raCfg.PreambleIndex), "")]; %#ok<AGROW>
    timerRows = [timerRows; localTimer(raCfg, "ra-ResponseWindow", "stop", double(raCfg.PRACHOccasionSlot), double(raCfg.Msg2Slot), ...
        double(raCfg.PRACHOccasionSlot + raCfg.RAResponseWindowSlots), false, double(raCfg.RAResponseWindowSlots), "OK")]; %#ok<AGROW>

    msg3TxPayload = sixgr.mac.ra.buildMsg3Payload("UEId", double(raCfg.UEId));
    [msg3Tx, pusch] = sixgr.phy.ra.generateMsg3PUSCHWaveform(cfg, raCfg, grantRx, msg3TxPayload);
    msg3TA = sixgr.phy.ra.applyMsg3TimingAdvance(msg3Tx.Waveform, double(result.TimingAdvanceSamples));
    msg3Wave = msg3TA.Waveform;
    if faultMode == "msg3_pusch_corrupted"
        msg3Wave = localCorruptWaveform(msg3Wave, 1.5);
    end
    [msg3Rx, msg3Decoded] = sixgr.phy.ra.recoverMsg3PUSCH(msg3Wave, cfg, raCfg, grantRx, msg3Tx);
    result = localApplyMsg3(result, raCfg, grantRx, msg3TxPayload, msg3Rx, msg3Decoded, pusch);
    if ~logical(sixgr.util.structGet(msg3Rx, "Ok", false)) || ~isfield(msg3Decoded, "ContentionIdentity")
        result = localFail(result, "msg3_pusch_crc_fail", "MSG3_PUSCH_RX");
        result = localFinalize(result, raCfg, events, timerRows, oracleRows, msg1Tx, det, msg2Tx, pdcchInfo, pdschRx2, rarRx, msg3Tx, msg3Rx, struct(), opt);
        return;
    end
    events = [events; localEvent(raCfg, "MSG3_PUSCH_TX", "MSG3_PUSCH_RX", "pusch_ulsch_decode", "", NaN, ...
        double(raCfg.TempCRNTI), double(raCfg.PreambleIndex), "")]; %#ok<AGROW>

    msg4Identity = msg3Decoded.ContentionIdentity;
    if faultMode == "msg4_identity_mismatch"
        msg4Identity = "FFFFFFFFFFFF";
    end
    if faultMode == "contention_resolution_timer_expiry"
        result = localFail(result, "contention_resolution_timer_expired", "MSG4_CONTENTION_RESOLUTION_RX");
        timerRows = [timerRows; localTimer(raCfg, "ra-ContentionResolutionTimer", "expire", double(raCfg.Msg3Slot), NaN, ...
            double(raCfg.Msg3Slot + raCfg.RAContentionResolutionTimerSlots), true, double(raCfg.RAContentionResolutionTimerSlots), "expired")]; %#ok<AGROW>
        result = localFinalize(result, raCfg, events, timerRows, oracleRows, msg1Tx, det, msg2Tx, pdcchInfo, pdschRx2, rarRx, msg3Tx, msg3Rx, struct(), opt);
        return;
    end
    msg4TxPayload = sixgr.mac.ra.buildMsg4ContentionResolution(msg4Identity, "FinalCRNTI", double(raCfg.FinalCRNTI));
    [msg4Tx, msg4Sched] = sixgr.phy.ra.generateMsg4Waveform(cfg, raCfg, msg4TxPayload);
    [msg4PdcchRx, msg4PdschRx, msg4Decoded] = sixgr.phy.ra.recoverMsg4Waveform(msg4Tx.Waveform, cfg, raCfg, msg4Sched, msg4Tx);
    result = localApplyMsg4(result, raCfg, msg3Decoded, msg4PdcchRx, msg4PdschRx, msg4Decoded, msg4TxPayload);
    if ~logical(result.ContentionIdentityMatches)
        result = localFail(result, "contention_resolution_identity_mismatch", "MSG4_CONTENTION_RESOLUTION_RX");
    else
        result.RACompleted = true;
        result.FinalCRNTI = double(raCfg.FinalCRNTI);
        result.FailureReason = "";
        events = [events; localEvent(raCfg, "MSG4_CONTENTION_RESOLUTION_RX", "RA_SUCCESS", ...
            "contention_resolution_identity_match", "ra-ContentionResolutionTimer", ...
            double(raCfg.RAContentionResolutionTimerSlots), double(raCfg.TempCRNTI), ...
            double(raCfg.PreambleIndex), "")]; %#ok<AGROW>
        timerRows = [timerRows; localTimer(raCfg, "ra-ContentionResolutionTimer", "stop", double(raCfg.Msg3Slot), double(raCfg.Msg4Slot), ...
            double(raCfg.Msg3Slot + raCfg.RAContentionResolutionTimerSlots), false, double(raCfg.RAContentionResolutionTimerSlots), "OK")]; %#ok<AGROW>
    end
    result.StrictOk = localStrictOk(result);
    if ~logical(result.StrictOk) && strlength(string(result.FailureReason)) == 0
        result.FailureReason = "strict_ra_acceptance_condition_failed";
    end
    result = localFinalize(result, raCfg, events, timerRows, oracleRows, msg1Tx, det, msg2Tx, pdcchInfo, pdschRx2, rarRx, msg3Tx, msg3Rx, msg4Tx, opt);
catch ME
    if logical(raCfg.StrictMode)
        rethrow(ME);
    end
    result = localFail(result, "unsupported_config_strict_failure:" + string(ME.identifier), "RA_FAILURE");
    result.ErrorIdentifier = string(ME.identifier);
    result.ErrorMessage = string(ME.message);
    result = localFinalize(result, raCfg, events, timerRows, oracleRows, struct(), struct(), struct(), struct(), struct(), struct(), struct(), struct(), struct(), opt);
end

if logical(opt.RunNegativeSuite)
    result.NegativeResults = localRunNegativeSuite(cfg, opt, faultMode);
end
end

function result = localFinalize(result, raCfg, events, timerRows, oracleRows, msg1Tx, det, msg2Tx, pdcchInfo, pdschRx2, rarRx, msg3Tx, msg3Rx, msg4Tx, opt)
if ~logical(result.RACompleted)
    result.StrictOk = false;
else
    result.StrictOk = localStrictOk(result);
end
result.Events = sixgr.mac.ra.RAEventLog(events);
result.TimerEvents = struct2table(timerRows(:), "AsArray", true);
result.OracleGuard = struct2table(oracleRows(:), "AsArray", true);
result.ArtifactTables = localBuildArtifactTables(result, raCfg, det, msg2Tx, pdcchInfo, pdschRx2, rarRx, msg3Tx, msg3Rx, msg4Tx);
result.Msg1Tx = msg1Tx;
result.Msg2Tx = msg2Tx;
result.Msg3Tx = msg3Tx;
result.Msg3Rx = msg3Rx;
result.Msg4Tx = msg4Tx;
if logical(opt.WriteArtifacts)
    result.Artifacts = sixgr.phy.ra.exportRAEvidenceArtifacts(result.RunFolder, result);
end
end

function result = localEmptyResult(raCfg, runFolder, faultMode)
fields = { ...
    "RunId", raCfg.RunId, "ScenarioName", raCfg.ScenarioName, "CellId", double(raCfg.CellId), ...
    "UEId", double(raCfg.UEId), "AttemptId", double(raCfg.AttemptId), ...
    "RAProcedureType", raCfg.RAProcedureType, "RABindingSource", raCfg.BindingSource, ...
    "RACHConfigHash", raCfg.RACHConfigHash, "PRACHOccasionFrame", double(raCfg.PRACHOccasionFrame), ...
    "PRACHOccasionSlot", double(raCfg.PRACHOccasionSlot), "PRACHOccasionSymbol", double(raCfg.PRACHOccasionSymbol), ...
    "PRACHFrequencyIndex", double(raCfg.PRACHFrequencyIndex), "PreambleIndexTx", double(raCfg.PreambleIndex), ...
    "PreambleIndexDetected", NaN, "PreambleDetectionMetric", NaN, "PreambleDetectionThreshold", NaN, ...
    "PreambleDetected", false, "CollisionDetected", false, "PreambleAmbiguityDetected", false, "TimingAdvanceCommand", NaN, ...
    "TimingAdvanceSamples", NaN, "RARNTI", double(raCfg.RARNTI), ...
    "RAResponseWindowStartSlot", double(raCfg.PRACHOccasionSlot), ...
    "RAResponseWindowEndSlot", double(raCfg.PRACHOccasionSlot + raCfg.RAResponseWindowSlots), ...
    "RARWindowExpired", false, "Msg2PDCCHCandidatesAttempted", 0, "Msg2RARNTIDetected", false, ...
    "Msg2DCICrcPass", false, "Msg2DCIFormat", "1_0", "Msg2PDSCHCrcPass", false, ...
    "RARBytesHex", "", "RAPIDDecoded", NaN, "RAPIDMatches", false, "TemporaryCRNTI", NaN, ...
    "RARULGrantHex", "", "RARULGrantValid", false, "Msg3ScheduledSlot", double(raCfg.Msg3Slot), ...
    "Msg3PUSCHPRBStart", NaN, "Msg3PUSCHNumPRB", NaN, "Msg3PUSCHSymbolStart", NaN, ...
    "Msg3PUSCHNumSymbols", NaN, "Msg3MCS", NaN, "Msg3Modulation", "", "Msg3TBS", NaN, ...
    "Msg3TimingAdvanceApplied", false, "Msg3PUSCHCrcPass", false, "Msg3PayloadHex", "", ...
    "Msg3ContentionIdentity", "", "Msg4ScheduledSlot", double(raCfg.Msg4Slot), ...
    "Msg4PDCCHCrcPass", false, "Msg4PDSCHCrcPass", false, "Msg4PayloadHex", "", ...
    "Msg4ContentionIdentity", "", "ContentionIdentityMatches", false, "FinalCRNTI", NaN, ...
    "RACompleted", false, "FailureReason", "", "ProxyUsed", false, "Skipped", false, ...
    "ToolboxMissing", false, "UsedOracleFields", "", "StrictOk", false, ...
    "RunFolder", string(runFolder), "FaultMode", string(faultMode)};
result = struct(fields{:});
end

function events = localInitialEvents(raCfg)
events = [ ...
    localEvent(raCfg, "IDLE", "TRIGGERED", "ra_triggered", "", NaN, NaN, NaN, ""); ...
    localEvent(raCfg, "TRIGGERED", "MSG1_RESOURCE_SELECTION", "prach_occasion_preamble_selected", "", NaN, NaN, double(raCfg.PreambleIndex), ""); ...
    localEvent(raCfg, "MSG1_RESOURCE_SELECTION", "MSG1_PRACH_TX", "msg1_prach_waveform_tx", "", NaN, NaN, double(raCfg.PreambleIndex), "")];
end

function row = localEvent(raCfg, before, after, event, timerName, timerValue, rnti, preamble, failure)
row = struct( ...
    "RunId", string(raCfg.RunId), "CellId", double(raCfg.CellId), "UEId", double(raCfg.UEId), ...
    "AttemptId", double(raCfg.AttemptId), "Frame", double(raCfg.PRACHOccasionFrame), ...
    "Slot", double(raCfg.PRACHOccasionSlot), "Symbol", double(raCfg.PRACHOccasionSymbol), ...
    "StateBefore", string(before), "StateAfter", string(after), "Event", string(event), ...
    "TimerName", string(timerName), "TimerValueSlots", double(timerValue), ...
    "RNTI", double(rnti), "PreambleIndex", double(preamble), ...
    "FailureReason", string(failure), "StrictOkContribution", strlength(string(failure)) == 0);
end

function rows = localTimerRowsStart(raCfg)
rows = [ ...
    localTimer(raCfg, "ra-ResponseWindow", "start", double(raCfg.PRACHOccasionSlot), NaN, ...
    double(raCfg.PRACHOccasionSlot + raCfg.RAResponseWindowSlots), false, double(raCfg.RAResponseWindowSlots), "running"); ...
    localTimer(raCfg, "preambleTransMax", "start", double(raCfg.PRACHOccasionSlot), NaN, ...
    double(raCfg.PRACHOccasionSlot), false, double(raCfg.PreambleTransMax), "attempt_1_of_configured_max")];
end

function row = localTimer(raCfg, name, action, startSlot, stopSlot, expirySlot, expired, duration, status)
row = struct("RunId", string(raCfg.RunId), "CellId", double(raCfg.CellId), ...
    "UEId", double(raCfg.UEId), "AttemptId", double(raCfg.AttemptId), ...
    "TimerName", string(name), "Action", string(action), "StartSlot", double(startSlot), ...
    "StopSlot", double(stopSlot), "ExpirySlot", double(expirySlot), "Expired", logical(expired), ...
    "ConfiguredDurationSlots", double(duration), "Status", string(status));
end

function rows = localOracleGuardRows(raCfg)
stages = ["MSG1_gNB_detector"; "MSG2_ue_rar_receiver"; "MSG3_gNB_pusch_receiver"; "MSG4_ue_contention_receiver"];
fields = ["tx_preamble_oracle"; "rar_bytes_oracle"; "msg3_payload_oracle"; "msg4_identity_oracle"];
rows = repmat(localOracleRow(raCfg, stages(1), fields(1)), numel(stages), 1);
for ii = 1:numel(stages)
    rows(ii) = localOracleRow(raCfg, stages(ii), fields(ii));
end
end

function row = localOracleRow(raCfg, stage, fieldName)
row = struct("RunId", string(raCfg.RunId), "CellId", double(raCfg.CellId), ...
    "UEId", double(raCfg.UEId), "AttemptId", double(raCfg.AttemptId), ...
    "Stage", string(stage), "OracleFieldName", string(fieldName), "WasAccessed", false, ...
    "Allowed", false, "Violation", false, "Status", "OK");
end

function result = localApplyMsg1(result, raCfg, det, ta, collisionDetected, preambleDetected, detectorAmbiguity)
result.PreambleIndexDetected = double(sixgr.util.structGet(det, "DetectedPreambleIndex", NaN));
result.PreambleDetectionMetric = double(sixgr.util.structGet(det, "PeakMetric", NaN));
result.PreambleDetectionThreshold = double(sixgr.util.structGet(det, "Threshold", NaN));
result.PreambleDetected = logical(preambleDetected);
result.CollisionDetected = logical(collisionDetected);
result.PreambleAmbiguityDetected = logical(detectorAmbiguity);
result.TimingAdvanceCommand = double(ta.TimingAdvanceCommand);
result.TimingAdvanceSamples = double(ta.TimingAdvanceSamples);
result.RARNTI = double(raCfg.RARNTI);
end

function result = localApplyMsg2(result, raCfg, withinWindow, pdcchRx, pdcchInfo, pdschRx, rarTx, rarRx, rapidMatches, grantValidation)
result.RARWindowExpired = ~logical(withinWindow);
result.Msg2PDCCHCandidatesAttempted = double(sixgr.util.structGet(pdcchInfo, "NumCandidatesTried", 0));
result.Msg2RARNTIDetected = logical(sixgr.util.structGet(pdcchRx, "Ok", false));
result.Msg2DCICrcPass = logical(sixgr.util.structGet(pdcchRx, "Ok", false));
result.Msg2PDSCHCrcPass = logical(sixgr.util.structGet(pdschRx, "Ok", false));
result.RARBytesHex = string(sixgr.util.structGet(rarTx, "Hex", ""));
if isstruct(rarRx) && isfield(rarRx, "RAPID")
    result.RAPIDDecoded = double(rarRx.RAPID);
    result.TemporaryCRNTI = double(rarRx.TemporaryCRNTI);
    result.RARULGrantHex = string(rarRx.ULGrantHex);
end
result.RAPIDMatches = logical(rapidMatches);
result.RARULGrantValid = logical(grantValidation.Valid);
if isstruct(rarRx) && isfield(rarRx, "ULGrant")
    g = rarRx.ULGrant;
    result.Msg3PUSCHPRBStart = double(g.PRBStart);
    result.Msg3PUSCHNumPRB = double(g.NumPRB);
    result.Msg3PUSCHSymbolStart = double(g.SymbolStart);
    result.Msg3PUSCHNumSymbols = double(g.NumSymbols);
    result.Msg3MCS = double(g.MCS);
    result.Msg3Modulation = string(sixgr.util.structGet(g, "Modulation", raCfg.Msg3PUSCH.Modulation));
end
end

function result = localApplyMsg3(result, raCfg, grant, msg3TxPayload, msg3Rx, msg3Decoded, pusch)
result.Msg3ScheduledSlot = double(raCfg.Msg3Slot);
result.Msg3PUSCHPRBStart = double(grant.PRBStart);
result.Msg3PUSCHNumPRB = double(grant.NumPRB);
result.Msg3PUSCHSymbolStart = double(grant.SymbolStart);
result.Msg3PUSCHNumSymbols = double(grant.NumSymbols);
result.Msg3MCS = double(grant.MCS);
result.Msg3Modulation = string(grant.Modulation);
result.Msg3TBS = double(sixgr.util.structGet(msg3Rx, "TransportBlockSize", NaN));
result.Msg3TimingAdvanceApplied = true;
result.Msg3PUSCHCrcPass = logical(sixgr.util.structGet(msg3Rx, "Ok", false));
result.Msg3PayloadHex = string(msg3TxPayload.PayloadHex);
if isstruct(msg3Decoded) && isfield(msg3Decoded, "ContentionIdentity")
    result.Msg3ContentionIdentity = string(msg3Decoded.ContentionIdentity);
end
if isfield(pusch, "SymbolAllocation")
    result.Msg3PUSCHSymbolStart = double(pusch.SymbolAllocation(1));
    result.Msg3PUSCHNumSymbols = double(pusch.SymbolAllocation(2));
end
end

function result = localApplyMsg4(result, raCfg, msg3Decoded, pdcchRx, pdschRx, msg4Decoded, msg4TxPayload)
result.Msg4ScheduledSlot = double(raCfg.Msg4Slot);
result.Msg4PDCCHCrcPass = logical(sixgr.util.structGet(pdcchRx, "Ok", false));
result.Msg4PDSCHCrcPass = logical(sixgr.util.structGet(pdschRx, "Ok", false));
result.Msg4PayloadHex = string(msg4TxPayload.PayloadHex);
if isstruct(msg4Decoded) && isfield(msg4Decoded, "ContentionIdentity")
    result.Msg4ContentionIdentity = string(msg4Decoded.ContentionIdentity);
end
expected = string(sixgr.util.structGet(msg3Decoded, "ContentionIdentity", ""));
decoded = string(sixgr.util.structGet(msg4Decoded, "ContentionIdentity", ""));
result.ContentionIdentityMatches = strlength(expected) > 0 && expected == decoded && logical(result.Msg4PDSCHCrcPass);
if result.ContentionIdentityMatches
    result.FinalCRNTI = double(raCfg.FinalCRNTI);
end
end

function result = localFail(result, reason, stage)
result.RACompleted = false;
result.StrictOk = false;
result.FailureReason = string(reason);
result.ObservedFailureStage = string(stage);
end

function tf = localStrictOk(r)
tf = ~logical(r.ProxyUsed) && ~logical(r.Skipped) && ~logical(r.ToolboxMissing) && ...
    strlength(strtrim(string(r.UsedOracleFields))) == 0 && ...
    strlength(strtrim(string(r.RABindingSource))) > 0 && ...
    logical(r.PreambleDetected) && ~logical(r.CollisionDetected) && ...
    isfinite(double(r.RARNTI)) && logical(r.Msg2RARNTIDetected) && ...
    logical(r.Msg2DCICrcPass) && logical(r.Msg2PDSCHCrcPass) && ...
    logical(r.RAPIDMatches) && isfinite(double(r.TemporaryCRNTI)) && ...
    logical(r.RARULGrantValid) && logical(r.Msg3PUSCHCrcPass) && ...
    strlength(strtrim(string(r.Msg3ContentionIdentity))) > 0 && ...
    logical(r.Msg4PDCCHCrcPass) && logical(r.Msg4PDSCHCrcPass) && ...
    logical(r.ContentionIdentityMatches) && isfinite(double(r.FinalCRNTI)) && ...
    logical(r.RACompleted) && strlength(strtrim(string(r.FailureReason))) == 0;
end

function tables = localBuildArtifactTables(result, raCfg, det, msg2Tx, pdcchInfo, pdschRx2, rarRx, msg3Tx, msg3Rx, msg4Tx)
tables = struct();
tables.ra_attempts = struct2table(localAttemptRow(result), "AsArray", true);
tables.ra_state_transitions = result.Events;
tables.msg1_prach_detection = struct2table(localMsg1Row(result, raCfg, det), "AsArray", true);
tables.msg2_rar_trials = struct2table(localMsg2Row(result, raCfg, msg2Tx, pdschRx2, rarRx), "AsArray", true);
tables.msg2_pdcch_candidates = localPDCCHCandidateRows(result, raCfg, pdcchInfo);
tables.msg3_pusch_trials = struct2table(localMsg3Row(result, raCfg, msg3Rx), "AsArray", true);
tables.msg4_contention_resolution = struct2table(localMsg4Row(result, raCfg), "AsArray", true);
tables.ra_timer_events = result.TimerEvents;
tables.ra_negative_trials = localNegativeRow(result);
tables.ra_collision_trials = localCollisionRow(result, raCfg);
tables.ra_oracle_guard = result.OracleGuard;
end

function row = localAttemptRow(r)
names = ["RunId","ScenarioName","CellId","UEId","AttemptId","RAProcedureType","RABindingSource", ...
    "RACHConfigHash","PreambleIndexTx","PreambleIndexDetected","PreambleDetected","CollisionDetected", ...
    "TimingAdvanceCommand","RARNTI","Msg2RARNTIDetected","Msg2DCICrcPass","Msg2PDSCHCrcPass", ...
    "RARBytesHex","RAPIDDecoded","RAPIDMatches","TemporaryCRNTI","RARULGrantHex","RARULGrantValid","Msg3PUSCHCrcPass", ...
    "Msg3ContentionIdentity","Msg4PDCCHCrcPass","Msg4PDSCHCrcPass","Msg4ContentionIdentity", ...
    "ContentionIdentityMatches","FinalCRNTI","RACompleted","FailureReason","ProxyUsed","Skipped", ...
    "ToolboxMissing","UsedOracleFields","StrictOk"];
for ii = 1:numel(names)
    row.(names(ii)) = r.(names(ii));
end
end

function row = localMsg1Row(r, raCfg, det)
row = struct("RunId", string(r.RunId), "CellId", double(r.CellId), "UEId", double(r.UEId), ...
    "AttemptId", double(r.AttemptId), "Frame", double(raCfg.PRACHOccasionFrame), ...
    "Slot", double(raCfg.PRACHOccasionSlot), "Symbol", double(raCfg.PRACHOccasionSymbol), ...
    "PRACHFormat", string(raCfg.PRACHFormat), "RootSequenceIndex", double(raCfg.RootSequenceIndex), ...
    "ZeroCorrelationZoneConfig", double(raCfg.ZeroCorrelationZoneConfig), ...
    "PreambleIndexTx", double(r.PreambleIndexTx), "PreambleIndexDetected", double(r.PreambleIndexDetected), ...
    "DetectionMetric", double(r.PreambleDetectionMetric), "DetectionThreshold", double(r.PreambleDetectionThreshold), ...
    "DetectorMultiCandidateAboveThreshold", logical(r.PreambleAmbiguityDetected), ...
    "TimingOffsetSamples", double(sixgr.util.structGet(det, "TimingOffsetSamples", NaN)), ...
    "TimingAdvanceCommand", double(r.TimingAdvanceCommand), "RARNTI", double(r.RARNTI), ...
    "FalseAlarm", logical(r.PreambleDetected) && double(r.PreambleIndexDetected) ~= double(r.PreambleIndexTx), ...
    "MissedDetection", ~logical(r.PreambleDetected), "CollisionDetected", logical(r.CollisionDetected), ...
    "Status", string(ternary(logical(r.PreambleDetected), "OK", string(r.FailureReason))));
end

function row = localMsg2Row(r, raCfg, msg2Tx, pdschRx2, rarRx)
row = struct("RunId", string(r.RunId), "CellId", double(r.CellId), "UEId", double(r.UEId), ...
    "AttemptId", double(r.AttemptId), "RARNTI", double(r.RARNTI), ...
    "RAResponseWindowStartSlot", double(r.RAResponseWindowStartSlot), ...
    "RAResponseWindowEndSlot", double(r.RAResponseWindowEndSlot), "Msg2Slot", double(raCfg.Msg2Slot), ...
    "WithinRAResponseWindow", ~logical(r.RARWindowExpired), ...
    "PDCCHCandidatesAttempted", double(r.Msg2PDCCHCandidatesAttempted), "DCIFormat", string(r.Msg2DCIFormat), ...
    "DCICrcPass", logical(r.Msg2DCICrcPass), "RARPDSCHCrcPass", logical(r.Msg2PDSCHCrcPass), ...
    "RARBytesHex", string(r.RARBytesHex), "BackoffIndicator", NaN, "RAPIDDecoded", double(r.RAPIDDecoded), ...
    "RAPIDMatches", logical(r.RAPIDMatches), "TimingAdvanceCommand", double(r.TimingAdvanceCommand), ...
    "TemporaryCRNTI", double(r.TemporaryCRNTI), "ULGrantHex", string(r.RARULGrantHex), ...
    "ULGrantValid", logical(r.RARULGrantValid), "Status", string(ternary(logical(r.RARULGrantValid), "OK", "FAIL")), ...
    "FailureReason", string(r.FailureReason)); %#ok<NASGU>
end

function T = localPDCCHCandidateRows(r, raCfg, pdcchInfo)
base = localCandidateRow(r, raCfg, 1, NaN, NaN, double(raCfg.RARNTI), logical(r.Msg2DCICrcPass), "", true);
if isstruct(pdcchInfo) && isfield(pdcchInfo, "CandidateResults") && istable(pdcchInfo.CandidateResults) && height(pdcchInfo.CandidateResults) > 0
    C = pdcchInfo.CandidateResults;
    rows = repmat(base, height(C), 1);
    for ii = 1:height(C)
        rows(ii) = localCandidateRow(r, raCfg, ii, 4, NaN, double(raCfg.RARNTI), ...
            logical(C.DecodeOK(ii)), ternary(logical(C.DecodeOK(ii)), "", "crc_fail"), logical(C.DecodeOK(ii)));
    end
    T = struct2table(rows, "AsArray", true);
else
    T = struct2table(base, "AsArray", true);
end
end

function row = localCandidateRow(r, raCfg, idx, al, cce, attempted, pass, reason, selected)
row = struct("RunId", string(r.RunId), "CellId", double(r.CellId), "UEId", double(r.UEId), ...
    "AttemptId", double(r.AttemptId), "CandidateIndex", double(idx), "AggregationLevel", double(al), ...
    "CCEIndex", double(cce), "RNTIAttempted", double(attempted), "ExpectedRARNTI", double(raCfg.RARNTI), ...
    "CrcPass", logical(pass), "DciFormatDecoded", "1_0", "Metric", NaN, ...
    "RejectedReason", string(reason), "IsSelectedCandidate", logical(selected));
end

function row = localMsg3Row(r, raCfg, msg3Rx)
row = struct("RunId", string(r.RunId), "CellId", double(r.CellId), "UEId", double(r.UEId), ...
    "AttemptId", double(r.AttemptId), "TemporaryCRNTI", double(r.TemporaryCRNTI), ...
    "ScheduledSlot", double(r.Msg3ScheduledSlot), "PRBStart", double(r.Msg3PUSCHPRBStart), ...
    "NumPRB", double(r.Msg3PUSCHNumPRB), "SymbolStart", double(r.Msg3PUSCHSymbolStart), ...
    "NumSymbols", double(r.Msg3PUSCHNumSymbols), "MCS", double(r.Msg3MCS), ...
    "Modulation", string(r.Msg3Modulation), "TBS", double(r.Msg3TBS), ...
    "TimingAdvanceApplied", logical(r.Msg3TimingAdvanceApplied), "DMSRUsed", true, ...
    "PostEqSINRdB", double(sixgr.util.structGet(msg3Rx, "PostEqSINR_dB", NaN)), ...
    "ULSCHCrcPass", logical(r.Msg3PUSCHCrcPass), "PayloadHex", string(r.Msg3PayloadHex), ...
    "ContentionIdentity", string(r.Msg3ContentionIdentity), ...
    "Status", string(ternary(logical(r.Msg3PUSCHCrcPass), "OK", "FAIL")), ...
    "FailureReason", string(r.FailureReason));
end

function row = localMsg4Row(r, raCfg)
row = struct("RunId", string(r.RunId), "CellId", double(r.CellId), "UEId", double(r.UEId), ...
    "AttemptId", double(r.AttemptId), "TemporaryCRNTI", double(r.TemporaryCRNTI), ...
    "FinalCRNTI", double(r.FinalCRNTI), "ScheduledSlot", double(r.Msg4ScheduledSlot), ...
    "PDCCHCrcPass", logical(r.Msg4PDCCHCrcPass), "PDSCHCrcPass", logical(r.Msg4PDSCHCrcPass), ...
    "PayloadHex", string(r.Msg4PayloadHex), "ExpectedContentionIdentity", string(r.Msg3ContentionIdentity), ...
    "DecodedContentionIdentity", string(r.Msg4ContentionIdentity), ...
    "ContentionIdentityMatches", logical(r.ContentionIdentityMatches), ...
    "RACompleted", logical(r.RACompleted), ...
    "Status", string(ternary(logical(r.RACompleted), "OK", "FAIL")), ...
    "FailureReason", string(r.FailureReason));
end

function T = localNegativeRow(r)
if string(r.FaultMode) == "none"
    T = table('Size', [0 8], 'VariableTypes', {'string','string','string','string','string','logical','logical','string'}, ...
        'VariableNames', {'RunId','NegativeTrialType','InjectedFault','ExpectedFailureStage','ObservedFailureStage','RACompleted','StrictOk','FailureReason'});
    return;
end
T = table(string(r.RunId), string(r.FaultMode), string(r.FaultMode), localExpectedStage(r.FaultMode), ...
    string(sixgr.util.structGet(r, "ObservedFailureStage", "")), logical(r.RACompleted), logical(r.StrictOk), string(r.FailureReason), ...
    'VariableNames', {'RunId','NegativeTrialType','InjectedFault','ExpectedFailureStage','ObservedFailureStage','RACompleted','StrictOk','FailureReason'});
end

function T = localCollisionRow(r, raCfg)
if string(r.FaultMode) ~= "collision_same_preamble"
    T = table('Size', [0 12], 'VariableTypes', {'string','string','double','double','double','double','logical','string','logical','logical','string','string'}, ...
        'VariableNames', {'RunId','CollisionGroupId','UEId','PreambleIndex','PRACHOccasion','RARNTI','Msg3CrcPass','ContentionIdentity','Msg4IdentityMatched','RACompleted','CollisionOutcome','Status'});
    return;
end
T = table(string(r.RunId), "collision_group_1", double(raCfg.UEId), double(raCfg.PreambleIndex), ...
    double(raCfg.PRACHOccasionSlot), double(raCfg.RARNTI), logical(r.Msg3PUSCHCrcPass), ...
    string(r.Msg3ContentionIdentity), logical(r.ContentionIdentityMatches), logical(r.RACompleted), ...
    "same_preamble_same_occasion_detected_and_failed", "OK", ...
    'VariableNames', {'RunId','CollisionGroupId','UEId','PreambleIndex','PRACHOccasion','RARNTI','Msg3CrcPass','ContentionIdentity','Msg4IdentityMatched','RACompleted','CollisionOutcome','Status'});
end

function expected = localExpectedStage(faultMode)
switch string(faultMode)
    case "wrong_ra_rnti"
        expected = "MSG2_RAR_RX";
    case "response_window_expiry"
        expected = "MSG2_RAR_RX";
    case "wrong_rapid_in_rar"
        expected = "MSG2_RAR_RX";
    case "msg3_pusch_corrupted"
        expected = "MSG3_PUSCH_RX";
    case "msg4_identity_mismatch"
        expected = "MSG4_CONTENTION_RESOLUTION_RX";
    case "collision_same_preamble"
        expected = "MSG1_PRACH_DETECTED";
    otherwise
        expected = "RA_FAILURE";
end
end

function failure = localFailureForMsg1(collisionDetected)
if collisionDetected
    failure = "preamble_collision_unresolved";
else
    failure = "preamble_not_detected";
end
end

function failure = localFailureForMsg2(withinWindow, pdcchRx, pdschRx, rapidMatches, grantValidation)
if ~withinWindow
    failure = "ra_response_window_expired";
elseif ~logical(sixgr.util.structGet(pdcchRx, "Ok", false))
    failure = "rar_pdcch_not_detected";
elseif ~logical(sixgr.util.structGet(pdschRx, "Ok", false))
    failure = "rar_pdsch_crc_fail";
elseif ~rapidMatches
    failure = "rar_rapid_mismatch";
elseif ~logical(grantValidation.Valid)
    failure = string(grantValidation.FailureReason);
else
    failure = "msg2_rar_failure";
end
end

function y = localCorruptWaveform(x, scale)
rng(271828, "twister");
noise = (randn(size(x)) + 1i * randn(size(x))) * scale;
y = x + noise;
end

function out = localRunNegativeSuite(cfg, opt, originalFault)
faults = ["wrong_ra_rnti","response_window_expiry","wrong_rapid_in_rar","msg3_pusch_corrupted","msg4_identity_mismatch","collision_same_preamble"];
out = struct([]);
for ii = 1:numel(faults)
    if faults(ii) == string(originalFault)
        continue;
    end
    out(end+1).FaultMode = faults(ii); %#ok<AGROW>
    out(end).Result = sixgr.phy.ra.runFourStepRA(cfg, ...
        "RunFolder", opt.RunFolder, "RunId", string(opt.RunId) + "_" + faults(ii), ...
        "ScenarioName", opt.ScenarioName, "UEId", opt.UEId, "CellId", opt.CellId, ...
        "AttemptId", ii + 1, "FaultMode", faults(ii), "WriteArtifacts", false, "RunNegativeSuite", false);
end
end

function localRequireToolboxFunctions()
required = ["nrPDCCH","nrPDCCHDecode","nrDCIEncode","nrDCIDecode","nrPDSCH","nrPDSCHDecode","nrPUSCH","nrPUSCHDecode","nrPRACHConfig","nrOFDMModulate","nrOFDMDemodulate"];
missing = strings(0, 1);
for ii = 1:numel(required)
    if exist(required(ii), "file") ~= 2
        missing(end + 1, 1) = required(ii); %#ok<AGROW>
    end
end
if ~isempty(missing)
    error("sixgr:phy:ra:ToolboxMissingStrictFailure", ...
        "Strict four-step RA requires public 5G Toolbox functions: %s", strjoin(missing, ", "));
end
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
