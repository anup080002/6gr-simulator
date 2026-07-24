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
p.addParameter("SIB1Recovery", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("RequireDecodedSIB1", false, @(x)islogical(x) || isnumeric(x));
p.addParameter("RuntimeIntegrationMode", "standalone_self_loop", @(x)ischar(x) || isstring(x));
p.addParameter("RuntimeStageWaveforms", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("RequireRuntimeStageWaveforms", false, @(x)islogical(x) || isnumeric(x));
p.addParameter("AllowRuntimeStageWaveformComposition", false, @(x)islogical(x) || isnumeric(x));
p.addParameter("UseRuntimeChannel", false, @(x)islogical(x) || isnumeric(x));
p.addParameter("RuntimeNoiseSNR_dB", Inf, @(x)isnumeric(x) && isscalar(x));
p.addParameter("RuntimeSlot", NaN, @(x)isnumeric(x) && isscalar(x));
p.parse(varargin{:});
opt = p.Results;
localProgress(opt, "start", "runFourStepRA entered");

localRequireToolboxFunctions();
localProgress(opt, "toolbox_checked", "required toolbox functions are available");
[cfg, sib1BindingEvidence] = localApplyDecodedSIB1IfPresent(cfg, opt.SIB1Recovery);
if logical(opt.RequireDecodedSIB1) && (~istable(sib1BindingEvidence) || height(sib1BindingEvidence) == 0)
    error("sixgr:mac:ra:UE_RACH_CONFIG_ORACLE_READ", ...
        "UE_RACH_CONFIG_ORACLE_READ: Phase 4 four-step RA requires receiver-owned RACH configuration from decoded SIB1; YAML-owned random_access is not allowed.");
end
raCfg = sixgr.mac.ra.RAConfig(cfg, ...
    "RunId", opt.RunId, ...
    "ScenarioName", opt.ScenarioName, ...
    "UEId", opt.UEId, ...
    "CellId", opt.CellId, ...
    "AttemptId", opt.AttemptId);
localProgress(opt, "ra_config_resolved", sprintf("ue=%g cell=%s preamble=%g", ...
    double(opt.UEId), localDisplayScalar(opt.CellId), double(raCfg.PreambleIndex)));
cfg = sixgr.phy.ra.localizeCarrierConfig(cfg, raCfg);
faultMode = lower(strtrim(string(opt.FaultMode)));
runFolder = string(opt.RunFolder);
if strlength(strtrim(runFolder)) == 0
    runFolder = string(tempname);
end

result = localEmptyResult(raCfg, runFolder, faultMode);
localProgress(opt, "runtime_transport_resolve_start", "");
runtime = localResolveRuntimeTransport(cfg, raCfg, opt);
localProgress(opt, "runtime_transport_resolve_done", string(runtime.Mode));
result = localApplyRuntimeTransportToResult(result, runtime);
result.SIB1RACHBindingEvidence = sib1BindingEvidence;
result.SIB1RACHBindingApplied = istable(sib1BindingEvidence) && height(sib1BindingEvidence) > 0;
if logical(result.SIB1RACHBindingApplied)
    result.SIB1RACHBindingSource = "decoded_sib1_rach_config_common";
    result.SIB1RACHPayloadHash = string(sib1BindingEvidence.PayloadHash(1));
    result.SIB1RACHTreeHash = string(sib1BindingEvidence.TreeHash(1));
end
powerState = localResolveRATransmitPower(cfg, raCfg);
result = localApplyPowerStateToResult(result, powerState);
events = localInitialEvents(raCfg);
oracleRows = localOracleGuardRows(raCfg);
timerRows = localTimerRowsStart(raCfg);

try
    localProgress(opt, "msg1_tx_start", "");
    [msg1Tx, occasion] = sixgr.phy.ra.generateMsg1PRACHWaveform(cfg, raCfg);
    localProgress(opt, "msg1_tx_done", sprintf("samples=%d", size(msg1Tx.Waveform, 1)));
    [msg1Tx.Waveform, msg1Power] = localApplyWaveformTxPower(msg1Tx.Waveform, ...
        powerState.PreambleTxPower_dBm, powerState.ReferenceTxPower_dBm);
    msg1Tx.PowerControl = powerState;
    msg1Tx.PowerControl.PreambleTxAmplitudeScale = double(msg1Power.AmplitudeScale);
    result.PreambleTxAmplitudeScale = double(msg1Power.AmplitudeScale);
    localProgress(opt, "msg1_channel_start", "");
    [msg1RxWave, runtime, stageInfo] = localResolveStageRxWaveform("Msg1", "UL", msg1Tx.Waveform, cfg, raCfg, msg1Tx, runtime);
    localProgress(opt, "msg1_channel_done", "");
    result = localAppendRuntimeStage(result, stageInfo);
    if faultMode == "no_prach_detected"
        msg1RxWave(:) = 0;
    end
    localProgress(opt, "msg1_detect_start", "");
    det = sixgr.phy.ra.detectMsg1PRACH(msg1RxWave, cfg, raCfg, occasion);
    localProgress(opt, "msg1_detect_done", sprintf("detected=%d", logical(det.Detected)));
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
    localProgress(opt, "msg2_tx_start", "");
    [msg2Tx, msg2Sched] = sixgr.phy.ra.generateMsg2RARWaveform(cfg, raCfg, rarTx);
    localProgress(opt, "msg2_tx_done", sprintf("samples=%d", size(msg2Tx.Waveform, 1)));
    [msg2Tx.Waveform, msg2Power] = localApplyWaveformTxPower(msg2Tx.Waveform, ...
        powerState.Msg2TxPower_dBm, powerState.ReferenceTxPower_dBm);
    msg2Tx.PowerControl = powerState;
    msg2Tx.PowerControl.Msg2TxAmplitudeScale = double(msg2Power.AmplitudeScale);
    result.Msg2TxAmplitudeScale = double(msg2Power.AmplitudeScale);
    withinWindow = double(raCfg.Msg2Slot) <= double(raCfg.PRACHOccasionSlot) + double(raCfg.RAResponseWindowSlots);
    if faultMode == "response_window_expiry"
        withinWindow = false;
    end
    attemptedRNTI = double(raCfg.RARNTI);
    if faultMode == "wrong_ra_rnti"
        attemptedRNTI = double(raCfg.RARNTI) + 1;
    end
    localProgress(opt, "msg2_channel_start", "");
    [msg2RxWave, runtime, stageInfo] = localResolveStageRxWaveform("Msg2", "DL", msg2Tx.Waveform, cfg, raCfg, msg2Tx, runtime);
    localProgress(opt, "msg2_channel_done", "");
    result = localAppendRuntimeStage(result, stageInfo);
    localProgress(opt, "msg2_pdcch_start", "");
    [pdcchRx, pdcchInfo] = sixgr.phy.ra.blindDecodeRARPDCCH(msg2RxWave, cfg, raCfg, msg2Sched, ...
        "RNTIAttempted", attemptedRNTI);
    localProgress(opt, "msg2_pdcch_done", sprintf("ok=%d", logical(pdcchRx.Ok)));
    msg2WaveForPDSCH = msg2RxWave;
    if faultMode == "rar_pdsch_corrupted"
        msg2WaveForPDSCH = localCorruptWaveform(msg2WaveForPDSCH, 0.75);
    end
    rarRx = struct();
    pdschRx2 = struct("Ok", false, "CRCError", true);
    if logical(pdcchRx.Ok) && withinWindow
        cfgMsg2Rx = localApplyRuntimeReceiverSyncContext(cfg, runtime, "DL");
        localProgress(opt, "msg2_pdsch_start", "");
        [pdschRx2, rarRx] = sixgr.phy.ra.recoverMsg2RAR(msg2WaveForPDSCH, cfgMsg2Rx, raCfg, msg2Sched, msg2Tx);
        localProgress(opt, "msg2_pdsch_done", sprintf("ok=%d", logical(sixgr.util.structGet(pdschRx2, "Ok", false))));
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
    result = localApplyMsg2(result, raCfg, withinWindow, pdcchRx, pdcchInfo, pdschRx2, msg2Tx, rarTx, rarRx, rapidMatches, grantValidation);
    if ~withinWindow || ~logical(pdcchRx.Ok) || ~logical(sixgr.util.structGet(pdschRx2, "Ok", false)) || ~rapidMatches || ~logical(grantValidation.Valid)
        result = localFail(result, localFailureForMsg2(withinWindow, pdcchRx, pdschRx2, rapidMatches, grantValidation), "MSG2_RAR_RX");
        result = localFinalize(result, raCfg, events, timerRows, oracleRows, msg1Tx, det, msg2Tx, pdcchInfo, pdschRx2, rarRx, struct(), struct(), struct(), opt);
        return;
    end
    events = [events; localEvent(raCfg, "MSG2_RAR_TX", "MSG2_RAR_RX", "rar_pdcch_pdsch_decode", "ra-ResponseWindow", ...
        double(raCfg.RAResponseWindowSlots), double(raCfg.RARNTI), double(raCfg.PreambleIndex), "")]; %#ok<AGROW>
    timerRows = [timerRows; localTimer(raCfg, "ra-ResponseWindow", "stop", double(raCfg.PRACHOccasionSlot), double(raCfg.Msg2Slot), ...
        double(raCfg.PRACHOccasionSlot + raCfg.RAResponseWindowSlots), false, double(raCfg.RAResponseWindowSlots), "OK")]; %#ok<AGROW>

    localProgress(opt, "msg3_tx_start", "");
    msg3TxPayload = sixgr.mac.ra.buildMsg3Payload("UEId", double(raCfg.UEId));
    [msg3Tx, pusch] = sixgr.phy.ra.generateMsg3PUSCHWaveform(cfg, raCfg, grantRx, msg3TxPayload);
    localProgress(opt, "msg3_tx_done", sprintf("samples=%d", size(msg3Tx.Waveform, 1)));
    [msg3Tx.Waveform, msg3Power] = localApplyWaveformTxPower(msg3Tx.Waveform, ...
        powerState.Msg3TxPower_dBm, powerState.ReferenceTxPower_dBm);
    msg3Tx.PowerControl = powerState;
    msg3Tx.PowerControl.Msg3TxAmplitudeScale = double(msg3Power.AmplitudeScale);
    result.Msg3TxAmplitudeScale = double(msg3Power.AmplitudeScale);
    msg3TA = sixgr.phy.ra.applyMsg3TimingAdvance(msg3Tx.Waveform, double(result.TimingAdvanceSamples));
    localProgress(opt, "msg3_channel_start", "");
    [msg3Wave, runtime, stageInfo] = localResolveStageRxWaveform("Msg3", "UL", msg3TA.Waveform, cfg, raCfg, msg3Tx, runtime);
    localProgress(opt, "msg3_channel_done", "");
    result = localAppendRuntimeStage(result, stageInfo);
    if faultMode == "msg3_pusch_corrupted"
        msg3Wave = localCorruptWaveform(msg3Wave, 1.5);
    end
    localProgress(opt, "msg3_pusch_start", "");
    [msg3Rx, msg3Decoded] = sixgr.phy.ra.recoverMsg3PUSCH(msg3Wave, cfg, raCfg, grantRx, msg3Tx);
    localProgress(opt, "msg3_pusch_done", sprintf("ok=%d", logical(sixgr.util.structGet(msg3Rx, "Ok", false))));
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
    localProgress(opt, "msg4_tx_start", "");
    msg4TxPayload = sixgr.mac.ra.buildMsg4ContentionResolution(msg4Identity, "FinalCRNTI", double(raCfg.FinalCRNTI));
    [msg4Tx, msg4Sched] = sixgr.phy.ra.generateMsg4Waveform(cfg, raCfg, msg4TxPayload);
    localProgress(opt, "msg4_tx_done", sprintf("samples=%d", size(msg4Tx.Waveform, 1)));
    [msg4Tx.Waveform, msg4Power] = localApplyWaveformTxPower(msg4Tx.Waveform, ...
        powerState.Msg4TxPower_dBm, powerState.ReferenceTxPower_dBm);
    msg4Tx.PowerControl = powerState;
    msg4Tx.PowerControl.Msg4TxAmplitudeScale = double(msg4Power.AmplitudeScale);
    result.Msg4TxAmplitudeScale = double(msg4Power.AmplitudeScale);
    localProgress(opt, "msg4_channel_start", "");
    [msg4RxWave, runtime, stageInfo] = localResolveStageRxWaveform("Msg4", "DL", msg4Tx.Waveform, cfg, raCfg, msg4Tx, runtime);
    localProgress(opt, "msg4_channel_done", "");
    result = localAppendRuntimeStage(result, stageInfo);
    cfgMsg4Rx = localApplyRuntimeReceiverSyncContext(cfg, runtime, "DL");
    localProgress(opt, "msg4_rx_start", "");
    [msg4PdcchRx, msg4PdschRx, msg4Decoded] = sixgr.phy.ra.recoverMsg4Waveform(msg4RxWave, cfgMsg4Rx, raCfg, msg4Sched, msg4Tx);
    localProgress(opt, "msg4_rx_done", sprintf("pdcch=%d pdsch=%d", ...
        logical(sixgr.util.structGet(msg4PdcchRx, "Ok", false)), logical(sixgr.util.structGet(msg4PdschRx, "Ok", false))));
    result = localApplyMsg4(result, raCfg, msg3Decoded, msg4PdcchRx, msg4PdschRx, msg4Tx, msg4Decoded, msg4TxPayload);
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
    localProgress(opt, "complete", sprintf("ra_completed=%d strict=%d", logical(result.RACompleted), logical(result.StrictOk)));
catch ME
    localProgress(opt, "error", string(ME.identifier) + ":" + string(ME.message));
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

function localProgress(opt, stage, detail)
if nargin < 3
    detail = "";
end
runFolder = string(opt.RunFolder);
if strlength(strtrim(runFolder)) == 0
    return;
end
try
    sixgr.util.ensureFolder(runFolder);
    runId = matlab.lang.makeValidName(char(string(opt.RunId)));
    if strlength(string(runId)) == 0
        runId = "ra_anchor";
    end
    path = fullfile(char(runFolder), "logs", "ra_progress_" + string(runId) + ".log");
    sixgr.util.ensureFolder(fileparts(char(path)));
    fid = fopen(char(path), "a");
    if fid > 0
        cleaner = onCleanup(@() fclose(fid));
        fprintf(fid, "%s stage=%s detail=%s\n", char(string(datetime("now", "Format", "yyyy-MM-dd'T'HH:mm:ss.SSS"))), ...
            char(string(stage)), char(string(detail)));
        clear cleaner;
    end
catch
end
end

function txt = localDisplayScalar(x)
if isempty(x)
    txt = "[]";
    return;
end
try
    v = double(x);
    if isscalar(v) && isfinite(v)
        txt = sprintf("%g", v);
    else
        txt = "NaN";
    end
catch
    txt = char(string(x));
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
result.Msg2Rx = pdschRx2;
result.Msg3Tx = msg3Tx;
result.Msg3Rx = msg3Rx;
result.Msg4Tx = msg4Tx;
if logical(opt.WriteArtifacts)
    result.Artifacts = sixgr.phy.ra.exportRAEvidenceArtifacts(result.RunFolder, result);
end
end

function [cfg, evidenceT] = localApplyDecodedSIB1IfPresent(cfg, sib1Recovery)
evidenceT = table('Size', [0 16], 'VariableTypes', ...
    {'string','string','string','string','string','string','string','string', ...
    'string','string','string','string','string','string','string','string'}, ...
    'VariableNames', {'Parameter','ValueBefore','ValueAfter','Source','Note','PayloadHash','TreeHash', ...
    'DecodedASN1Path','DecodedValue','Units','StandardsDefault','SourceCallId', ...
    'SourceMessageId','SourceBitRange','ValidationStatus','RunPhase'});
if isempty(sib1Recovery) || ~(isstruct(sib1Recovery) && ~isempty(fieldnames(sib1Recovery)))
    return;
end
[cfg, evidenceT] = sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg, sib1Recovery);
if istable(evidenceT) && ~isempty(evidenceT)
    evidenceT.RunPhase = repmat("sib1_to_ra_config_install", height(evidenceT), 1);
end
end

function result = localEmptyResult(raCfg, runFolder, faultMode)
fields = { ...
    "RunId", raCfg.RunId, "ScenarioName", raCfg.ScenarioName, "CellId", double(raCfg.CellId), ...
    "UEId", double(raCfg.UEId), "AttemptId", double(raCfg.AttemptId), ...
    "RAProcedureType", raCfg.RAProcedureType, "RABindingSource", raCfg.BindingSource, ...
    "SIB1RACHBindingApplied", false, "SIB1RACHBindingSource", "", ...
    "SIB1RACHPayloadHash", "", "SIB1RACHTreeHash", "", ...
    "RACHConfigHash", raCfg.RACHConfigHash, "PRACHOccasionFrame", double(raCfg.PRACHOccasionFrame), ...
    "PRACHOccasionSlot", double(raCfg.PRACHOccasionSlot), "PRACHOccasionSymbol", double(raCfg.PRACHOccasionSymbol), ...
    "PRACHFrequencyIndex", double(raCfg.PRACHFrequencyIndex), "PreambleIndexTx", double(raCfg.PreambleIndex), ...
    "PreambleIndexDetected", NaN, "PreambleDetectionMetric", NaN, "PreambleDetectionThreshold", NaN, ...
    "Msg1RxAntennaCount", NaN, "Msg1PDPAverageNoiseFloor", NaN, ...
    "Msg1PeakToThresholdRatio", NaN, "Msg1PeakToNoiseRatio", NaN, ...
    "Msg1PeakToNoiseRatio_dB", NaN, "Msg1CandidateCount", NaN, ...
    "Msg1CandidatesAboveThreshold", NaN, "Msg1TargetFalseAlarmProbability", NaN, ...
    "Msg1ThresholdBackgroundComponent", NaN, "Msg1ThresholdGlobalPeakComponent", NaN, ...
    "Msg1PeakGuardFactor", NaN, "Msg1DetectorPeakLagSamples", NaN, ...
    "PreambleDetected", false, "CollisionDetected", false, "PreambleAmbiguityDetected", false, "TimingAdvanceCommand", NaN, ...
    "PreambleReceivedTargetPower_dBm", double(raCfg.PreambleReceivedTargetPower_dBm), ...
    "PowerRampingStep_dB", double(raCfg.PowerRampingStep_dB), ...
    "PreambleTransMax", double(raCfg.PreambleTransMax), "PreambleAttemptNumber", 1, ...
    "PowerPathloss_dB", NaN, "PowerBasePathloss_dB", NaN, "PowerPathlossSource", "", ...
    "ReferenceTxPower_dBm", NaN, "PreambleDelta_dB", NaN, ...
    "PreambleTargetReceivedPower_dBm", NaN, "PreambleRequestedTxPower_dBm", NaN, ...
    "PreambleTxPower_dBm", NaN, "PreamblePowerHeadroom_dB", NaN, "PreambleTxAmplitudeScale", NaN, ...
    "PowerControlStatus", "", "P0PUSCH_dBm", double(raCfg.P0PUSCH_dBm), ...
    "AlphaPUSCH", double(raCfg.AlphaPUSCH), "Pcmax_dBm", double(raCfg.Pcmax_dBm), ...
    "Msg3Pathloss_dB", NaN, "Msg3P0PUSCH_dBm", double(raCfg.P0PUSCH_dBm), ...
    "Msg3Alpha", double(raCfg.AlphaPUSCH), "Msg3NumPRBForPower", NaN, ...
    "Msg3DeltaTF_dB", NaN, "Msg3ClosedLoopCorrection_dB", NaN, ...
    "Msg3RequestedTxPower_dBm", NaN, "Msg3TxPower_dBm", NaN, ...
    "Msg3PowerHeadroom_dB", NaN, "Msg3TxAmplitudeScale", NaN, ...
    "DownlinkTxPower_dBm", NaN, "DownlinkTxPowerSource", "", ...
    "Msg2TxPower_dBm", NaN, "Msg2TxAmplitudeScale", NaN, ...
    "Msg4TxPower_dBm", NaN, "Msg4TxAmplitudeScale", NaN, ...
    "TimingAdvanceSamples", NaN, "RARNTI", double(raCfg.RARNTI), ...
    "RAResponseWindowStartSlot", double(raCfg.PRACHOccasionSlot), ...
    "RAResponseWindowEndSlot", double(raCfg.PRACHOccasionSlot + raCfg.RAResponseWindowSlots), ...
    "RARWindowExpired", false, "Msg2PDCCHCandidatesAttempted", 0, "Msg2RARNTIDetected", false, ...
    "Msg2DCICrcPass", false, "Msg2DCIFormat", "1_0", "Msg2PDSCHCrcPass", false, ...
    "Msg2PDSCHNumLayers", NaN, "Msg2PDSCHConfiguredNumPorts", NaN, ...
    "Msg2PDSCHResolvedNumPorts", NaN, "Msg2PDSCHExplicitMatrixPresent", false, ...
    "Msg2PDSCHPrecodingActive", false, "Msg2PDSCHPrecodingMode", "", ...
    "Msg2PDSCHPrecodingSource", "", ...
    "Msg2TimingEstimateUsed", false, "Msg2RawTimingEstimate_samples", NaN, ...
    "Msg2AppliedTimingCorrection_samples", NaN, "Msg2TimingEstimateSource", "", ...
    "Msg2PostEqSINR_dB", NaN, "Msg2ReceiverHestSINR_dB", NaN, ...
    "Msg2PreEqualizationNoiseVar", NaN, "Msg2DecoderNoiseVar", NaN, ...
    "Msg2ChannelEstimateAvailable", false, "Msg2ChannelEstimateMethod", "", ...
    "Msg2ChannelEstimatePilotResidualNMSE_dB", NaN, "Msg2EqualizationAvailable", false, ...
    "Msg2LLRFinite", false, "Msg2DemapperLLRCount", NaN, "Msg2DecoderIterations", NaN, ...
    "RARBytesHex", "", "RAPIDDecoded", NaN, "RAPIDMatches", false, "TemporaryCRNTI", NaN, ...
    "RARULGrantHex", "", "RARULGrantValid", false, "Msg3ScheduledSlot", double(raCfg.Msg3Slot), ...
    "Msg3PUSCHPRBStart", NaN, "Msg3PUSCHNumPRB", NaN, "Msg3PUSCHSymbolStart", NaN, ...
    "Msg3PUSCHNumSymbols", NaN, "Msg3MCS", NaN, "Msg3Modulation", "", "Msg3TBS", NaN, ...
    "Msg3TimingAdvanceApplied", false, "Msg3PUSCHCrcPass", false, "Msg3PayloadHex", "", ...
    "Msg3ContentionIdentity", "", "Msg4ScheduledSlot", double(raCfg.Msg4Slot), ...
    "Msg4PDCCHCrcPass", false, "Msg4PDSCHCrcPass", false, ...
    "Msg4PDSCHNumLayers", NaN, "Msg4PDSCHConfiguredNumPorts", NaN, ...
    "Msg4PDSCHResolvedNumPorts", NaN, "Msg4PDSCHExplicitMatrixPresent", false, ...
    "Msg4PDSCHPrecodingActive", false, "Msg4PDSCHPrecodingMode", "", ...
    "Msg4PDSCHPrecodingSource", "", ...
    "Msg4TimingEstimateUsed", false, "Msg4RawTimingEstimate_samples", NaN, ...
    "Msg4AppliedTimingCorrection_samples", NaN, "Msg4TimingEstimateSource", "", ...
    "Msg4PostEqSINR_dB", NaN, "Msg4ReceiverHestSINR_dB", NaN, ...
    "Msg4PreEqualizationNoiseVar", NaN, "Msg4DecoderNoiseVar", NaN, ...
    "Msg4ChannelEstimateAvailable", false, "Msg4ChannelEstimateMethod", "", ...
    "Msg4ChannelEstimatePilotResidualNMSE_dB", NaN, "Msg4EqualizationAvailable", false, ...
    "Msg4LLRFinite", false, "Msg4DemapperLLRCount", NaN, "Msg4DecoderIterations", NaN, ...
    "Msg4PayloadHex", "", ...
    "Msg4ContentionIdentity", "", "ContentionIdentityMatches", false, "FinalCRNTI", NaN, ...
    "RACompleted", false, "FailureReason", "", "ProxyUsed", false, "Skipped", false, ...
    "ToolboxMissing", false, "UsedOracleFields", "", "StrictOk", false, ...
    "RuntimeIntegrationMode", "", "RuntimeTransportMode", "", ...
    "RuntimeStageWaveformsRequired", false, "RuntimeStageWaveformsUsed", false, ...
    "RuntimeSelfLoopWaveformsUsed", false, "RuntimeChannelStateUsed", false, ...
    "RuntimeNoiseApplied", false, "RuntimeNoiseVarianceMean", NaN, ...
    "RuntimeChannelLinkKeys", "", "RuntimeStageCount", 0, ...
    "RuntimeStageRows", table(), ...
    "RunFolder", string(runFolder), "FaultMode", string(faultMode), ...
    "SIB1RACHBindingEvidence", table()};
result = struct(fields{:});
end

function runtime = localResolveRuntimeTransport(cfg, raCfg, opt)
mode = lower(strtrim(string(opt.RuntimeIntegrationMode)));
if strlength(mode) == 0
    mode = "standalone_self_loop";
end
useRuntimeChannel = logical(opt.UseRuntimeChannel) || ...
    logical(sixgr.util.structGet(cfg, "random_access.use_runtime_channel", false)) || ...
    logical(sixgr.util.structGet(cfg, "validation.random_access_evidence.use_runtime_channel", false)) || ...
    any(mode == ["coupled_truth_runtime","slot_coupled_runtime","runtime_channel_state"]);
requireStageWaveforms = logical(opt.RequireRuntimeStageWaveforms) || ...
    logical(sixgr.util.structGet(cfg, "random_access.require_runtime_stage_waveforms", false)) || ...
    logical(sixgr.util.structGet(cfg, "validation.random_access_evidence.require_runtime_stage_waveforms", false));
allowComposition = logical(opt.AllowRuntimeStageWaveformComposition) || ...
    logical(sixgr.util.structGet(cfg, "random_access.allow_runtime_stage_waveform_composition", false)) || ...
    logical(sixgr.util.structGet(cfg, "validation.random_access_evidence.allow_runtime_stage_waveform_composition", false));
runtime = struct();
runtime.Mode = char(mode);
runtime.StageWaveforms = opt.RuntimeStageWaveforms;
runtime.RequireStageWaveforms = logical(requireStageWaveforms);
runtime.AllowStageWaveformComposition = logical(allowComposition);
runtime.UseRuntimeChannel = logical(useRuntimeChannel);
runtime.RuntimeSlot = double(opt.RuntimeSlot);
runtime.RuntimeNoiseSNR_dB = double(opt.RuntimeNoiseSNR_dB);
runtime.StageRows = repmat(localEmptyRuntimeStageRow(), 0, 1);
runtime.ULChannelState = sixgr.channel.ChannelFactory.emptyRuntimeChannelState();
runtime.DLChannelState = sixgr.channel.ChannelFactory.emptyRuntimeChannelState();
runtime.UEIndex = max(1, round(double(raCfg.UEId)));
runtime.ServingCell = max(1, round(double(raCfg.CellId)));
runtime.NSizeGrid = double(raCfg.NSizeGrid);
runtime.CarrierSCSkHz = double(raCfg.CarrierSCSkHz);
runtime.CarrierFrequencyHz = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.fc_Hz", []), ...
    sixgr.util.structGet(cfg, "channel.fc_Hz", []), ...
    sixgr.util.structGet(cfg, "frequency.center_frequency_hz", []), ...
    sixgr.util.structGet(cfg, "random_access.carrier_frequency_hz", []), 4e9);
runtime.TransportMode = "standalone_self_loop";
if runtime.RequireStageWaveforms && runtime.AllowStageWaveformComposition && runtime.UseRuntimeChannel
    runtime.TransportMode = "coupled_runtime_stage_waveform_composer";
elseif runtime.RequireStageWaveforms
    runtime.TransportMode = "provided_runtime_stage_waveforms_required";
elseif runtime.UseRuntimeChannel
    runtime.TransportMode = "persistent_runtime_channel_state";
end
end

function result = localApplyRuntimeTransportToResult(result, runtime)
result.RuntimeIntegrationMode = string(runtime.Mode);
result.RuntimeTransportMode = string(runtime.TransportMode);
result.RuntimeStageWaveformsRequired = logical(runtime.RequireStageWaveforms);
result.RuntimeStageRows = struct2table(runtime.StageRows, "AsArray", true);
end

function [rxWave, runtime, row] = localResolveStageRxWaveform(stageName, direction, txWave, cfg, raCfg, txStruct, runtime)
stageName = string(stageName);
direction = upper(strtrim(string(direction)));
row = localEmptyRuntimeStageRow();
row.RunId = string(raCfg.RunId);
row.CellId = double(raCfg.CellId);
row.UEId = double(raCfg.UEId);
row.AttemptId = double(raCfg.AttemptId);
row.StageName = stageName;
row.Direction = direction;
row.TxSampleCount = size(txWave, 1);
row.TxPortCount = size(txWave, 2);
row.RuntimeIntegrationMode = string(runtime.Mode);
row.RuntimeTransportMode = string(runtime.TransportMode);
row.StageSlot = localStageSlot(raCfg, stageName);
rxWave = txWave;

[provided, providedField] = localRuntimeProvidedWaveform(runtime.StageWaveforms, stageName);
if ~isempty(provided)
    localAssertRuntimeWaveformCompatible(provided, txWave, stageName, providedField);
    rxWave = provided;
    row.RxSampleCount = size(rxWave, 1);
    row.RxPortCount = size(rxWave, 2);
    row.WaveformSource = "provided_runtime_stage_waveform";
    row.ProvidedWaveformField = providedField;
    row.RuntimeStageWaveformUsed = true;
    row.SelfLoopWaveformUsed = false;
    runtime.StageRows(end + 1, 1) = row;
    return;
end

if logical(runtime.RequireStageWaveforms)
    if logical(runtime.AllowStageWaveformComposition) && logical(runtime.UseRuntimeChannel)
        [rxWave, runtime, row] = localApplyRuntimeChannelForStage(row, direction, txWave, cfg, txStruct, runtime);
        row.WaveformSource = "coupled_runtime_stage_waveform_composer";
        row.RuntimeStageWaveformUsed = true;
        row.ProvidedWaveformField = "runtime_channel_state";
        runtime.StageRows(end + 1, 1) = row;
        return;
    end
    error("sixgr:phy:ra:MissingRuntimeStageWaveform", ...
        "Four-step RA runtime mode requires a propagated receive waveform for %s, but none was provided.", stageName);
end

if logical(runtime.UseRuntimeChannel)
    [rxWave, runtime, row] = localApplyRuntimeChannelForStage(row, direction, txWave, cfg, txStruct, runtime);
    runtime.StageRows(end + 1, 1) = row;
    return;
end

row.RxSampleCount = size(rxWave, 1);
row.RxPortCount = size(rxWave, 2);
row.WaveformSource = "standalone_self_loop_waveform";
row.SelfLoopWaveformUsed = true;
runtime.StageRows(end + 1, 1) = row;
end

function [rxWave, runtime, row] = localApplyRuntimeChannelForStage(row, direction, txWave, cfg, txStruct, runtime)
cfgStage = localRuntimeStageConfig(cfg, direction, runtime);
txInfo = localStageTxInfo(txStruct);
stateField = "DLChannelState";
if direction == "UL"
    stateField = "ULChannelState";
end
chState = runtime.(stateField);
if ~(isstruct(chState) && isfield(chState, "ContractVersion") && logical(sixgr.util.structGet(chState, "Initialized", false)))
    linkKey = sixgr.channel.ChannelFactory.runtimeChannelKey(cfgStage, direction, ...
        "UEIndex", runtime.UEIndex, "ServingCell", runtime.ServingCell);
    chState = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfgStage, direction, ...
        "LinkKey", linkKey, ...
        "Seed", sixgr.channel.ChannelFactory.runtimeChannelSeed(cfgStage, linkKey), ...
        "UEIndex", runtime.UEIndex, "ServingCell", runtime.ServingCell);
end
numTx = max(1, size(txWave, 2));
numRx = localResolveStageRxPorts(cfgStage, direction, numTx);
[txRuntimeAntenna, txRuntimeMeta] = localStageRuntimeAntenna(cfgStage, direction, "tx", numTx);
[rxRuntimeAntenna, rxRuntimeMeta] = localStageRuntimeAntenna(cfgStage, direction, "rx", numRx);
chState = sixgr.channel.ChannelFactory.materializeRuntimeChannelState(chState, cfgStage, ...
    txWave, txInfo, ...
    "NumTxAnt", numTx, "NumRxAnt", numRx, ...
    "TransmitAntennaRuntime", txRuntimeAntenna, ...
    "ReceiveAntennaRuntime", rxRuntimeAntenna, ...
    "TransmitAntennaMeta", txRuntimeMeta, ...
    "ReceiveAntennaMeta", rxRuntimeMeta);
slotStart_s = localStageSlotStartTime(cfgStage, double(row.StageSlot));
if isfinite(slotStart_s)
    chState = sixgr.channel.ChannelFactory.advanceRuntimeChannelStateToTime(chState, slotStart_s, numTx, txWave);
end
[rxWave, replay, chState] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(chState, txWave);
runtime.(stateField) = chState;
row.RxSampleCount = size(rxWave, 1);
row.RxPortCount = size(rxWave, 2);
row.WaveformSource = "runtime_channel_state";
row.SelfLoopWaveformUsed = false;
row.RuntimeChannelStateUsed = logical(sixgr.util.structGet(replay, "RuntimeChannelStateUsed", false));
row.ChannelFadingApplied = logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false));
row.ChannelFadingExecutionStatus = string(sixgr.util.structGet(replay, "ChannelFadingExecutionStatus", ""));
row.RuntimeChannelLinkKey = string(sixgr.util.structGet(replay, "RuntimeChannelLinkKey", ""));
row.RuntimeChannelSeed = double(sixgr.util.structGet(replay, "RuntimeChannelSeed", NaN));
row.RuntimeChannelStartSample = double(sixgr.util.structGet(replay, "RuntimeChannelStartSample", NaN));
row.RuntimeChannelEndSample = double(sixgr.util.structGet(replay, "RuntimeChannelEndSample", NaN));
row.RuntimeChannelIdleAdvancedSamples = double(sixgr.util.structGet(replay, "RuntimeChannelIdleAdvancedSamples", NaN));
if isfinite(double(runtime.RuntimeNoiseSNR_dB))
    sigPow = mean(abs(rxWave(:)).^2, "omitnan");
    if ~(isfinite(sigPow) && sigPow >= 0)
        sigPow = 0;
    end
    [rxWave, nVar] = sixgr.util.addAwgnComplex(rxWave, double(runtime.RuntimeNoiseSNR_dB), "SignalPower", sigPow);
    row.NoiseApplied = true;
    row.NoiseSNR_dB = double(runtime.RuntimeNoiseSNR_dB);
    row.NoiseVariance = double(nVar);
end
end

function result = localAppendRuntimeStage(result, row)
if ~istable(result.RuntimeStageRows)
    result.RuntimeStageRows = table();
end
rowT = struct2table(row, "AsArray", true);
if isempty(result.RuntimeStageRows)
    result.RuntimeStageRows = rowT;
else
    result.RuntimeStageRows = [result.RuntimeStageRows; rowT];
end
result.RuntimeStageCount = height(result.RuntimeStageRows);
result.RuntimeStageWaveformsUsed = any(logical(result.RuntimeStageRows.RuntimeStageWaveformUsed));
result.RuntimeSelfLoopWaveformsUsed = any(logical(result.RuntimeStageRows.SelfLoopWaveformUsed));
result.RuntimeChannelStateUsed = any(logical(result.RuntimeStageRows.RuntimeChannelStateUsed));
result.RuntimeNoiseApplied = any(logical(result.RuntimeStageRows.NoiseApplied));
noiseVars = double(result.RuntimeStageRows.NoiseVariance);
noiseVars = noiseVars(isfinite(noiseVars));
if ~isempty(noiseVars)
    result.RuntimeNoiseVarianceMean = mean(noiseVars);
end
keys = string(result.RuntimeStageRows.RuntimeChannelLinkKey);
keys = keys(strlength(strtrim(keys)) > 0);
result.RuntimeChannelLinkKeys = strjoin(unique(keys, "stable"), "|");
end

function cfgOut = localApplyRuntimeReceiverSyncContext(cfg, runtime, direction)
cfgOut = cfg;
direction = upper(strtrim(string(direction)));
stateField = "DLChannelState";
if direction == "UL"
    stateField = "ULChannelState";
end
if ~(isstruct(runtime) && isfield(runtime, stateField) && isstruct(runtime.(stateField)))
    return;
end
chState = runtime.(stateField);
trimSamples = double(sixgr.util.structGet(chState, "ChannelTrimSamples", 0));
padSamples = double(sixgr.util.structGet(chState, "ChannelPadSamples", NaN));
if ~isfinite(trimSamples)
    trimSamples = 0;
end
pathDelaySamples = NaN;
if isfinite(padSamples)
    pathDelaySamples = max(0, double(padSamples) - max(0, double(trimSamples)));
end
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.receiverSync.ChannelFilterDelay_samples", max(0, double(trimSamples)));
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.receiverSync.ChannelTrimSamples", max(0, double(trimSamples)));
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.RuntimeChannelFilterDelay_samples", max(0, double(trimSamples)));
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.RuntimeChannelTrimSamples", max(0, double(trimSamples)));
if isfinite(padSamples)
    cfgOut = sixgr.util.structSet(cfgOut, "lls6g.receiverSync.ChannelPadSamples", max(0, double(padSamples)));
    cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.RuntimeChannelPadSamples", max(0, double(padSamples)));
end
if isfinite(pathDelaySamples)
    cfgOut = sixgr.util.structSet(cfgOut, "lls6g.receiverSync.ChannelPathDelay_samples", double(pathDelaySamples));
    cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.RuntimeChannelPathDelay_samples", double(pathDelaySamples));
end
end

function [wave, fieldName] = localRuntimeProvidedWaveform(stageWaveforms, stageName)
wave = [];
fieldName = "";
if ~(isstruct(stageWaveforms) && ~isempty(fieldnames(stageWaveforms)))
    return;
end
stageName = string(stageName);
candidates = [stageName + "RxWaveform", stageName + "Waveform", lower(stageName) + "_rx_waveform", ...
    lower(stageName) + "_waveform"];
for i = 1:numel(candidates)
    f = char(candidates(i));
    if isfield(stageWaveforms, f)
        candidate = stageWaveforms.(f);
        if isnumeric(candidate) && ~isempty(candidate)
            wave = candidate;
            fieldName = string(f);
            return;
        end
    end
end
end

function localAssertRuntimeWaveformCompatible(rxWave, txWave, stageName, fieldName)
if ~(isnumeric(rxWave) && ndims(rxWave) <= 2)
    error("sixgr:phy:ra:BadRuntimeStageWaveform", ...
        "Runtime waveform %s for %s must be a numeric sample-by-port matrix.", string(fieldName), string(stageName));
end
if size(rxWave, 1) ~= size(txWave, 1)
    error("sixgr:phy:ra:RuntimeStageWaveformLengthMismatch", ...
        "Runtime waveform %s for %s has %d samples; expected %d.", ...
        string(fieldName), string(stageName), size(rxWave, 1), size(txWave, 1));
end
if size(rxWave, 2) < 1
    error("sixgr:phy:ra:RuntimeStageWaveformPortMismatch", ...
        "Runtime waveform %s for %s has no receive ports.", string(fieldName), string(stageName));
end
end

function cfgStage = localRuntimeStageConfig(cfg, direction, runtime)
cfgStage = cfg;
cfgStage = sixgr.util.structSet(cfgStage, "lls6g.userContext.RuntimeCurrentDirection", char(direction));
cfgStage = sixgr.util.structSet(cfgStage, "lls6g.userContext.Direction", char(direction));
cfgStage = sixgr.util.structSet(cfgStage, "lls6g.userContext.UEIndex", double(runtime.UEIndex));
cfgStage = sixgr.util.structSet(cfgStage, "lls6g.userContext.RuntimeUEIndex", double(runtime.UEIndex));
cfgStage = sixgr.util.structSet(cfgStage, "lls6g.userContext.RuntimeServingCell", double(runtime.ServingCell));
cfgStage = sixgr.util.structSet(cfgStage, "lls6g.userContext.RuntimeServingCellIndex", double(runtime.ServingCell));
cfgStage = sixgr.util.structSet(cfgStage, "phy.carrier.NSizeGrid", double(runtime.NSizeGrid));
cfgStage = sixgr.util.structSet(cfgStage, "phy.carrier.SubcarrierSpacing", double(runtime.CarrierSCSkHz));
cfgStage = sixgr.util.structSet(cfgStage, "phy.carrier.SubcarrierSpacing_kHz", double(runtime.CarrierSCSkHz));
cfgStage = sixgr.util.structSet(cfgStage, "phy.fc_Hz", double(runtime.CarrierFrequencyHz));
cfgStage = sixgr.util.structSet(cfgStage, "carrier.fc_Hz", double(runtime.CarrierFrequencyHz));
end

function txInfo = localStageTxInfo(txStruct)
txInfo = struct("OFDM", struct());
if isstruct(txStruct)
    if isfield(txStruct, "OFDMInfo") && isstruct(txStruct.OFDMInfo)
        txInfo.OFDM = txStruct.OFDMInfo;
    elseif isfield(txStruct, "Info") && isstruct(txStruct.Info)
        candidate = sixgr.util.structGet(txStruct.Info, "OFDM", struct());
        if isstruct(candidate) && ~isempty(fieldnames(candidate))
            txInfo.OFDM = candidate;
        end
    end
    if ~isfield(txInfo.OFDM, "SampleRate") || isempty(txInfo.OFDM.SampleRate)
        sampleRate = sixgr.util.structGet(txStruct, "PRACHRuntimeConfig.SampleRate_Hz", []);
        if isempty(sampleRate) && isfield(txStruct, "Carrier")
            sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve( ...
                txStruct.Carrier);
            sampleRate = double(sampling.SampleRateHz);
        end
        if ~isempty(sampleRate)
            txInfo.OFDM.SampleRate = double(sampleRate);
        end
    end
end
end

function nRx = localResolveStageRxPorts(cfg, direction, numTx)
if direction == "UL"
    nRx = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "random_access.num_rx_antennas", []), ...
        sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "rx", numTx), ...
        sixgr.util.structGet(cfg, "phy.nRxAnt", []), NaN);
else
    userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
    nRx = localFirstFiniteScalar( ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumWaveformColumns", []), ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumPorts", []), ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumWaveformColumns", []), ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumPorts", []), ...
        sixgr.util.structGet(cfg, "random_access.ue_num_rx_antennas", []), ...
        sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", []), ...
        sixgr.util.structGet(cfg, "ue.nRxAnt", []), ...
        sixgr.util.structGet(cfg, "phy.nRxAntUE", []), ...
        sixgr.util.structGet(cfg, "phy.nRxAnt", []), NaN);
end
if ~(isfinite(nRx) && nRx >= 1)
    nRx = max(1, double(numTx));
end
nRx = max(1, round(double(nRx)));
end

function [ant, meta] = localStageRuntimeAntenna(cfg, direction, endpoint, portCount)
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
role = localStageRuntimeRole(direction, endpoint);
if role == "BS"
    ant = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
    meta = sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct());
else
    ant = sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct());
    meta = sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct());
end
[ant, meta] = localLogicalPortViewForStage(ant, meta, portCount);
end

function role = localStageRuntimeRole(direction, endpoint)
direction = upper(strtrim(string(direction)));
endpoint = lower(strtrim(string(endpoint)));
if direction == "UL"
    if endpoint == "tx"
        role = "UE";
    else
        role = "BS";
    end
else
    if endpoint == "tx"
        role = "BS";
    else
        role = "UE";
    end
end
end

function [ant, meta] = localLogicalPortViewForStage(ant, meta, portCount)
portCount = max(1, round(double(portCount)));
if ~(isstruct(ant) && ~isempty(fieldnames(ant)))
    ant = struct();
end
if ~(isstruct(meta) && ~isempty(fieldnames(meta)))
    meta = struct();
end
numElements = localFirstFiniteScalar( ...
    sixgr.util.structGet(meta, "NumElements", []), ...
    sixgr.util.structGet(ant, "NumElements", []), ...
    sixgr.util.structGet(ant, "Nant", []), ...
    portCount);
ant.NumPorts = double(portCount);
ant.NumLogicalPorts = double(portCount);
ant.LogicalPortCount = double(portCount);
ant.NumWaveformColumns = double(portCount);
ant.WaveformColumnCount = double(portCount);
ant.NumRFChains = max(portCount, round(double(localFirstFiniteScalar(sixgr.util.structGet(ant, "NumRFChains", []), portCount))));
ant.WaveformDomain = "logical_port";
ant.PortCountSource = "four_step_ra_stage_logical_waveform_ports";
ant.RFChainCountSource = "four_step_ra_stage_logical_waveform_ports";
proj = localPortProjectionMatrix(numElements, portCount);
ant.PortToElementMatrix = proj;
ant.ElementToPortMatrix = proj';
meta.NumPorts = double(portCount);
meta.NumLogicalPorts = double(portCount);
meta.LogicalPortCount = double(portCount);
meta.NumWaveformColumns = double(portCount);
meta.WaveformColumnCount = double(portCount);
meta.NumRFChains = double(ant.NumRFChains);
meta.WaveformDomain = "logical_port";
meta.PortCountSource = "four_step_ra_stage_logical_waveform_ports";
meta.RFChainCountSource = "four_step_ra_stage_logical_waveform_ports";
end

function proj = localPortProjectionMatrix(numElements, numPorts)
numElements = max(1, round(double(numElements)));
numPorts = max(1, round(double(numPorts)));
proj = zeros(numElements, numPorts);
edges = round(linspace(0, numElements, numPorts + 1));
for pIdx = 1:numPorts
    idx = (edges(pIdx) + 1):max(edges(pIdx + 1), edges(pIdx) + 1);
    idx = idx(idx >= 1 & idx <= numElements);
    if isempty(idx)
        idx = min(numElements, pIdx);
    end
    proj(idx, pIdx) = 1 / sqrt(max(1, numel(idx)));
end
end

function slot = localStageSlot(raCfg, stageName)
switch string(stageName)
    case "Msg1"
        slot = double(raCfg.PRACHOccasionSlot);
    case "Msg2"
        slot = double(raCfg.Msg2Slot);
    case "Msg3"
        slot = double(raCfg.Msg3Slot);
    case "Msg4"
        slot = double(raCfg.Msg4Slot);
    otherwise
        slot = NaN;
end
end

function t = localStageSlotStartTime(cfg, slot)
t = NaN;
if ~(isfinite(slot) && slot >= 0)
    return;
end
slotDuration_s = sixgr.time.slotDurationSec(cfg);
t = double(slot) * slotDuration_s;
end

function row = localEmptyRuntimeStageRow()
row = struct( ...
    "RunId", "", "CellId", NaN, "UEId", NaN, "AttemptId", NaN, ...
    "StageName", "", "Direction", "", "StageSlot", NaN, ...
    "RuntimeIntegrationMode", "", "RuntimeTransportMode", "", ...
    "WaveformSource", "", "ProvidedWaveformField", "", ...
    "RuntimeStageWaveformUsed", false, "SelfLoopWaveformUsed", false, ...
    "RuntimeChannelStateUsed", false, "ChannelFadingApplied", false, ...
    "ChannelFadingExecutionStatus", "", "RuntimeChannelLinkKey", "", ...
    "RuntimeChannelSeed", NaN, "RuntimeChannelStartSample", NaN, ...
    "RuntimeChannelEndSample", NaN, "RuntimeChannelIdleAdvancedSamples", NaN, ...
    "NoiseApplied", false, "NoiseSNR_dB", NaN, "NoiseVariance", NaN, ...
    "TxSampleCount", NaN, "TxPortCount", NaN, "RxSampleCount", NaN, "RxPortCount", NaN);
end

function pc = localResolveRATransmitPower(cfg, raCfg)
pcmax = localFirstFiniteScalar(raCfg.Pcmax_dBm, ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.pcmax_dBm", []), ...
    sixgr.util.structGet(cfg, "powerAndRF.uePcmax_dBm", []), 23);
p0 = localFirstFiniteScalar(raCfg.P0PUSCH_dBm, ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.p0PUSCH_dBm", []), -80);
alpha = localFirstFiniteScalar(raCfg.AlphaPUSCH, ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.alpha", []), 0.8);
alpha = min(max(double(alpha), 0), 1);
deltaPreamble = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "random_access.delta_preamble_db", []), ...
    sixgr.util.structGet(cfg, "phy.prach.deltaPreamble_dB", []), 0);
deltaTF = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.deltaTF_dB", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.power_control.delta_tf_db", []), 0);
closedLoop = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.closedLoopAccumulation_dB", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.power_control.closed_loop_accumulation_db", []), 0);
referenceTxPower = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, "phy.pusch.powerControl.referenceTxPower_dBm", []), ...
    sixgr.util.structGet(cfg, "powerAndRF.referenceTxPower_dBm", []), 0);
[downlinkTxPower, downlinkPowerSource] = localFirstFiniteScalarWithSource( ...
    "lls6g.resolvedConfig.power_and_rf_frontend.bs_tx_power_dbm", ...
        sixgr.util.structGet(cfg, "lls6g.resolvedConfig.power_and_rf_frontend.bs_tx_power_dbm", []), ...
    "powerAndRF.bsTxPower_dBm", sixgr.util.structGet(cfg, "powerAndRF.bsTxPower_dBm", []), ...
    "scenario.bs.txPower_dBm", sixgr.util.structGet(cfg, "scenario.bs.txPower_dBm", []), ...
    "lls6g.energy_efficiency.bs_tx_power_dbm", ...
        sixgr.util.structGet(cfg, "lls6g.energy_efficiency.bs_tx_power_dbm", []), ...
    "lls6g.energy_efficiency.tx_power_dbm", ...
        sixgr.util.structGet(cfg, "lls6g.energy_efficiency.tx_power_dbm", []), ...
    "default_gnb_ra_downlink_tx_power_dBm", 46);

[pathloss_dB, basePathloss_dB, pathlossSource] = localResolveRATxPathloss(cfg, raCfg);
attemptNumber = max(1, round(double(raCfg.AttemptId)));
mRB = max(1, round(double(raCfg.Msg3PUSCH.NumPRB)));

preambleTarget = double(raCfg.PreambleReceivedTargetPower_dBm) + double(deltaPreamble) + ...
    (attemptNumber - 1) * double(raCfg.PowerRampingStep_dB);
preambleRequested = NaN;
preambleTx = NaN;
preambleHeadroom = NaN;
msg3Requested = NaN;
msg3Tx = NaN;
msg3Headroom = NaN;
status = "pathloss_unavailable_power_not_applied";
if isfinite(pathloss_dB) && pathloss_dB >= 0
    preambleRequested = double(preambleTarget) + double(pathloss_dB);
    preambleTx = min(double(pcmax), preambleRequested);
    preambleHeadroom = double(pcmax) - double(preambleTx);
    msg3Requested = double(p0) + 10 * log10(double(mRB)) + double(alpha) * double(pathloss_dB) + ...
        double(deltaTF) + double(closedLoop);
    msg3Tx = min(double(pcmax), msg3Requested);
    msg3Headroom = double(pcmax) - double(msg3Tx);
    status = "applied_open_loop_ts38213_ra_power_control";
end

pc = struct( ...
    "PowerPathloss_dB", double(pathloss_dB), ...
    "PowerBasePathloss_dB", double(basePathloss_dB), ...
    "PowerPathlossSource", string(pathlossSource), ...
    "ReferenceTxPower_dBm", double(referenceTxPower), ...
    "PreambleReceivedTargetPower_dBm", double(raCfg.PreambleReceivedTargetPower_dBm), ...
    "PreambleDelta_dB", double(deltaPreamble), ...
    "PreamblePowerRampingStep_dB", double(raCfg.PowerRampingStep_dB), ...
    "PreamblePowerRampingCounter", double(attemptNumber), ...
    "PreambleTargetReceivedPower_dBm", double(preambleTarget), ...
    "PreambleRequestedTxPower_dBm", double(preambleRequested), ...
    "PreambleTxPower_dBm", double(preambleTx), ...
    "PreamblePowerHeadroom_dB", double(preambleHeadroom), ...
    "PreambleTxAmplitudeScale", NaN, ...
    "P0PUSCH_dBm", double(p0), ...
    "AlphaPUSCH", double(alpha), ...
    "Pcmax_dBm", double(pcmax), ...
    "Msg3Pathloss_dB", double(pathloss_dB), ...
    "Msg3P0PUSCH_dBm", double(p0), ...
    "Msg3Alpha", double(alpha), ...
    "Msg3NumPRBForPower", double(mRB), ...
    "Msg3DeltaTF_dB", double(deltaTF), ...
    "Msg3ClosedLoopCorrection_dB", double(closedLoop), ...
    "Msg3RequestedTxPower_dBm", double(msg3Requested), ...
    "Msg3TxPower_dBm", double(msg3Tx), ...
    "Msg3PowerHeadroom_dB", double(msg3Headroom), ...
    "Msg3TxAmplitudeScale", NaN, ...
    "DownlinkTxPower_dBm", double(downlinkTxPower), ...
    "DownlinkTxPowerSource", string(downlinkPowerSource), ...
    "Msg2TxPower_dBm", double(downlinkTxPower), ...
    "Msg2TxAmplitudeScale", NaN, ...
    "Msg4TxPower_dBm", double(downlinkTxPower), ...
    "Msg4TxAmplitudeScale", NaN, ...
    "PowerControlStatus", string(status));
end

function result = localApplyPowerStateToResult(result, pc)
fields = fieldnames(pc);
for i = 1:numel(fields)
    result.(fields{i}) = pc.(fields{i});
end
end

function [waveOut, info] = localApplyWaveformTxPower(waveIn, txPower_dBm, referenceTxPower_dBm)
waveOut = waveIn;
info = struct("TxPower_dBm", double(txPower_dBm), ...
    "ReferenceTxPower_dBm", double(referenceTxPower_dBm), ...
    "AmplitudeScale", 1);
if ~(isnumeric(waveIn) && ~isempty(waveIn) && isfinite(double(txPower_dBm)) && isfinite(double(referenceTxPower_dBm)))
    return;
end
scale = 10 .^ ((double(txPower_dBm) - double(referenceTxPower_dBm)) / 20);
if isfinite(scale) && scale > 0
    waveOut = waveIn .* cast(scale, "like", waveIn);
    info.AmplitudeScale = double(scale);
end
end

function [pathloss_dB, basePathloss_dB, source] = localResolveRATxPathloss(cfg, raCfg)
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
[pathloss_dB, source] = localFirstFiniteScalarWithSource( ...
    "lls6g.userContext.RuntimeServingPathloss_dB", sixgr.util.structGet(userMeta, "RuntimeServingPathloss_dB", []), ...
    "lls6g.userContext.RuntimeServingBasePathloss_dB", sixgr.util.structGet(userMeta, "RuntimeServingBasePathloss_dB", []), ...
    "random_access.pathloss_dB", sixgr.util.structGet(cfg, "random_access.pathloss_dB", []), ...
    "channel.pathloss_dB", sixgr.util.structGet(cfg, "channel.pathloss_dB", []), ...
    "channel.largeScale.pathloss_dB", sixgr.util.structGet(cfg, "channel.largeScale.pathloss_dB", []));
basePathloss_dB = localFirstFiniteScalar( ...
    sixgr.util.structGet(userMeta, "RuntimeServingBasePathloss_dB", []), ...
    sixgr.util.structGet(cfg, "channel.largeScale.basePathloss_dB", []), NaN);
if isfinite(pathloss_dB) && pathloss_dB >= 0
    return;
end

pathloss_dB = NaN;
source = "unavailable";
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", ""))));
pathlossEnabled = logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", false));
needsLargeScale = pathlossEnabled || any(model == ["TR38901","TR38.901","TR38_901","ABG","TDL","CDL"]);
if awgnOnly && ~pathlossEnabled
    return;
end
if ~needsLargeScale
    return;
end

try
    layout = sixgr.scenario.generateLayout(cfg);
    ue = sixgr.scenario.dropUEs(cfg, layout);
    seed = double(sixgr.util.structGet(cfg, "run.seed", 1));
    plModel = sixgr.channel.TR38901Plus(cfg, "Seed", seed + 17);
    state = sixgr.system.buildLargeScaleStateCache(cfg, layout, ue, [], [], plModel, ...
        "NumRB", max(1, round(double(raCfg.Msg3PUSCH.NumPRB))));
    ueIdx = max(1, min(size(state.Pathloss_dB, 1), round(double(raCfg.UEId))));
    cellIdx = localResolveServingCellIndex(raCfg, state);
    pathloss_dB = double(state.Pathloss_dB(ueIdx, cellIdx));
    if isfield(state, "BasePathloss_dB")
        basePathloss_dB = double(state.BasePathloss_dB(ueIdx, cellIdx));
    end
    source = "scenario_layout_large_scale_state";
catch
    pathloss_dB = NaN;
    basePathloss_dB = NaN;
    source = "unavailable";
end
end

function cellIdx = localResolveServingCellIndex(raCfg, state)
nCells = max(1, size(state.Pathloss_dB, 2));
cellIdx = 1;
candidate = round(double(raCfg.CellId));
if isfinite(candidate) && candidate >= 1 && candidate <= nCells
    cellIdx = candidate;
end
end

function val = localFirstFiniteScalar(varargin)
val = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    vals = double(raw(:));
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        val = vals(1);
        return;
    end
end
end

function [val, source] = localFirstFiniteScalarWithSource(varargin)
val = NaN;
source = "unavailable";
for i = 1:2:nargin
    label = string(varargin{i});
    raw = varargin{i + 1};
    if isempty(raw)
        continue;
    end
    vals = double(raw(:));
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        val = vals(1);
        source = label;
        return;
    end
end
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
result.Msg1RxAntennaCount = double(sixgr.util.structGet(det, "RxAntennaCount", NaN));
result.Msg1PDPAverageNoiseFloor = double(sixgr.util.structGet(det, "PDPNoiseFloor", NaN));
result.Msg1PeakToThresholdRatio = double(sixgr.util.structGet(det, "PeakToThresholdRatio", NaN));
result.Msg1PeakToNoiseRatio = double(sixgr.util.structGet(det, "PeakToNoiseRatio", NaN));
result.Msg1PeakToNoiseRatio_dB = double(sixgr.util.structGet(det, "PeakToNoiseRatio_dB", NaN));
result.Msg1CandidateCount = double(sixgr.util.structGet(det, "CandidateCount", NaN));
result.Msg1CandidatesAboveThreshold = double(sixgr.util.structGet(det, "CandidatesAboveThreshold", NaN));
result.Msg1TargetFalseAlarmProbability = double(sixgr.util.structGet(det, "TargetFalseAlarmProbability", NaN));
result.Msg1ThresholdBackgroundComponent = double(sixgr.util.structGet(det, "ThresholdBackgroundComponent", NaN));
result.Msg1ThresholdGlobalPeakComponent = double(sixgr.util.structGet(det, "ThresholdGlobalPeakComponent", NaN));
result.Msg1PeakGuardFactor = double(sixgr.util.structGet(det, "PeakGuardFactor", NaN));
result.Msg1DetectorPeakLagSamples = double(sixgr.util.structGet(det, "PeakLagSamples", NaN));
result.PreambleDetected = logical(preambleDetected);
result.CollisionDetected = logical(collisionDetected);
result.PreambleAmbiguityDetected = logical(detectorAmbiguity);
result.TimingAdvanceCommand = double(ta.TimingAdvanceCommand);
result.TimingAdvanceSamples = double(ta.TimingAdvanceSamples);
result.RARNTI = double(raCfg.RARNTI);
end

function result = localApplyMsg2(result, raCfg, withinWindow, pdcchRx, pdcchInfo, pdschRx, msg2Tx, rarTx, rarRx, rapidMatches, grantValidation)
result.RARWindowExpired = ~logical(withinWindow);
result.Msg2PDCCHCandidatesAttempted = double(sixgr.util.structGet(pdcchInfo, "NumCandidatesTried", 0));
result.Msg2RARNTIDetected = logical(sixgr.util.structGet(pdcchRx, "Ok", false));
result.Msg2DCICrcPass = logical(sixgr.util.structGet(pdcchRx, "Ok", false));
result.Msg2PDSCHCrcPass = logical(sixgr.util.structGet(pdschRx, "Ok", false));
result = localApplyPDSCHEvidence(result, "Msg2", sixgr.util.structGet(msg2Tx, "RAPDSCHConfig", struct()));
result = localApplyPDSCHRxDiagnostics(result, "Msg2", pdschRx);
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

function result = localApplyMsg4(result, raCfg, msg3Decoded, pdcchRx, pdschRx, msg4Tx, msg4Decoded, msg4TxPayload)
result.Msg4ScheduledSlot = double(raCfg.Msg4Slot);
result.Msg4PDCCHCrcPass = logical(sixgr.util.structGet(pdcchRx, "Ok", false));
result.Msg4PDSCHCrcPass = logical(sixgr.util.structGet(pdschRx, "Ok", false));
result = localApplyPDSCHEvidence(result, "Msg4", sixgr.util.structGet(msg4Tx, "RAPDSCHConfig", struct()));
result = localApplyPDSCHRxDiagnostics(result, "Msg4", pdschRx);
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
tables.sib1_rach_config_binding = result.SIB1RACHBindingEvidence;
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
tables.ra_runtime_stage_waveforms = localRuntimeStageTable(result);
end

function result = localApplyPDSCHEvidence(result, prefix, ev)
if ~(isstruct(ev) && ~isempty(fieldnames(ev)))
    return;
end
prefix = char(string(prefix));
result.([prefix 'PDSCHNumLayers']) = double(sixgr.util.structGet(ev, "NumLayers", NaN));
result.([prefix 'PDSCHConfiguredNumPorts']) = double(sixgr.util.structGet(ev, "ConfiguredNumPorts", NaN));
result.([prefix 'PDSCHResolvedNumPorts']) = double(sixgr.util.structGet(ev, "ResolvedNumPorts", NaN));
result.([prefix 'PDSCHExplicitMatrixPresent']) = logical(sixgr.util.structGet(ev, "ExplicitMatrixPresent", false));
result.([prefix 'PDSCHPrecodingActive']) = logical(sixgr.util.structGet(ev, "PrecodingActive", false));
result.([prefix 'PDSCHPrecodingMode']) = string(sixgr.util.structGet(ev, "PrecodingMode", ""));
result.([prefix 'PDSCHPrecodingSource']) = string(sixgr.util.structGet(ev, "PrecodingSource", ""));
end

function result = localApplyPDSCHRxDiagnostics(result, prefix, rx)
if ~(isstruct(rx) && ~isempty(fieldnames(rx)))
    return;
end
prefix = char(string(prefix));
result.([prefix 'TimingEstimateUsed']) = logical(sixgr.util.structGet(rx, "TimingEstimateUsed", false));
result.([prefix 'RawTimingEstimate_samples']) = double(sixgr.util.structGet(rx, "RawTimingEstimate_samples", NaN));
result.([prefix 'AppliedTimingCorrection_samples']) = double(sixgr.util.structGet(rx, "AppliedTimingCorrection_samples", NaN));
result.([prefix 'TimingEstimateSource']) = string(sixgr.util.structGet(rx, "TimingEstimateSource", ""));
result.([prefix 'PostEqSINR_dB']) = double(sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
result.([prefix 'ReceiverHestSINR_dB']) = double(sixgr.util.structGet(rx, "ReceiverHestSINR_dB", NaN));
result.([prefix 'PreEqualizationNoiseVar']) = double(sixgr.util.structGet(rx, "PreEqualizationNoiseVar", NaN));
result.([prefix 'DecoderNoiseVar']) = double(sixgr.util.structGet(rx, "DecoderNoiseVar", NaN));
result.([prefix 'ChannelEstimateAvailable']) = logical(sixgr.util.structGet(rx, "ChannelEstimateAvailable", false));
result.([prefix 'ChannelEstimateMethod']) = string(sixgr.util.structGet(rx, "ChannelEstimateMethod", ""));
result.([prefix 'ChannelEstimatePilotResidualNMSE_dB']) = double(sixgr.util.structGet(rx, "ChannelEstimatePilotResidualNMSE_dB", NaN));
result.([prefix 'EqualizationAvailable']) = logical(sixgr.util.structGet(rx, "EqualizationAvailable", false));
result.([prefix 'LLRFinite']) = logical(sixgr.util.structGet(rx, "LLRFinite", false));
result.([prefix 'DemapperLLRCount']) = double(sixgr.util.structGet(rx, "DemapperLLRCount", NaN));
result.([prefix 'DecoderIterations']) = double(sixgr.util.structGet(rx, "DecoderIterations", NaN));
end

function row = localAttemptRow(r)
names = ["RunId","ScenarioName","CellId","UEId","AttemptId","RAProcedureType","RABindingSource", ...
    "SIB1RACHBindingApplied","SIB1RACHBindingSource","SIB1RACHPayloadHash","SIB1RACHTreeHash", ...
    "RACHConfigHash","PreambleIndexTx","PreambleIndexDetected","PreambleDetected","CollisionDetected", ...
    "Msg1RxAntennaCount","Msg1PDPAverageNoiseFloor","Msg1PeakToThresholdRatio", ...
    "Msg1PeakToNoiseRatio","Msg1PeakToNoiseRatio_dB","Msg1CandidateCount", ...
    "Msg1CandidatesAboveThreshold","Msg1TargetFalseAlarmProbability", ...
    "Msg1ThresholdBackgroundComponent","Msg1ThresholdGlobalPeakComponent", ...
    "Msg1PeakGuardFactor","Msg1DetectorPeakLagSamples", ...
    "PreambleReceivedTargetPower_dBm","PowerRampingStep_dB","PreambleTransMax","PreambleAttemptNumber", ...
    "PowerPathloss_dB","PowerBasePathloss_dB","PowerPathlossSource","ReferenceTxPower_dBm", ...
    "PreambleDelta_dB","PreambleTargetReceivedPower_dBm","PreambleRequestedTxPower_dBm", ...
    "PreambleTxPower_dBm","PreamblePowerHeadroom_dB","PreambleTxAmplitudeScale","PowerControlStatus", ...
    "P0PUSCH_dBm","AlphaPUSCH","Pcmax_dBm", ...
    "Msg3Pathloss_dB","Msg3P0PUSCH_dBm","Msg3Alpha","Msg3NumPRBForPower", ...
    "Msg3DeltaTF_dB","Msg3ClosedLoopCorrection_dB","Msg3RequestedTxPower_dBm", ...
    "Msg3TxPower_dBm","Msg3PowerHeadroom_dB","Msg3TxAmplitudeScale", ...
    "DownlinkTxPower_dBm","DownlinkTxPowerSource", ...
    "Msg2TxPower_dBm","Msg2TxAmplitudeScale","Msg4TxPower_dBm","Msg4TxAmplitudeScale", ...
    "TimingAdvanceCommand","RARNTI","Msg2RARNTIDetected","Msg2DCICrcPass","Msg2PDSCHCrcPass", ...
    "Msg2PDSCHNumLayers","Msg2PDSCHConfiguredNumPorts","Msg2PDSCHResolvedNumPorts", ...
    "Msg2PDSCHExplicitMatrixPresent","Msg2PDSCHPrecodingActive","Msg2PDSCHPrecodingMode","Msg2PDSCHPrecodingSource", ...
    "Msg2TimingEstimateUsed","Msg2RawTimingEstimate_samples","Msg2AppliedTimingCorrection_samples", ...
    "Msg2TimingEstimateSource","Msg2PostEqSINR_dB","Msg2ReceiverHestSINR_dB", ...
    "Msg2PreEqualizationNoiseVar","Msg2DecoderNoiseVar","Msg2ChannelEstimateAvailable", ...
    "Msg2ChannelEstimateMethod","Msg2ChannelEstimatePilotResidualNMSE_dB", ...
    "Msg2EqualizationAvailable","Msg2LLRFinite","Msg2DemapperLLRCount","Msg2DecoderIterations", ...
    "RARBytesHex","RAPIDDecoded","RAPIDMatches","TemporaryCRNTI","RARULGrantHex","RARULGrantValid","Msg3PUSCHCrcPass", ...
    "Msg3ContentionIdentity","Msg4PDCCHCrcPass","Msg4PDSCHCrcPass", ...
    "Msg4PDSCHNumLayers","Msg4PDSCHConfiguredNumPorts","Msg4PDSCHResolvedNumPorts", ...
    "Msg4PDSCHExplicitMatrixPresent","Msg4PDSCHPrecodingActive","Msg4PDSCHPrecodingMode","Msg4PDSCHPrecodingSource", ...
    "Msg4TimingEstimateUsed","Msg4RawTimingEstimate_samples","Msg4AppliedTimingCorrection_samples", ...
    "Msg4TimingEstimateSource","Msg4PostEqSINR_dB","Msg4ReceiverHestSINR_dB", ...
    "Msg4PreEqualizationNoiseVar","Msg4DecoderNoiseVar","Msg4ChannelEstimateAvailable", ...
    "Msg4ChannelEstimateMethod","Msg4ChannelEstimatePilotResidualNMSE_dB", ...
    "Msg4EqualizationAvailable","Msg4LLRFinite","Msg4DemapperLLRCount","Msg4DecoderIterations", ...
    "Msg4ContentionIdentity", ...
    "ContentionIdentityMatches","FinalCRNTI","RACompleted","FailureReason","ProxyUsed","Skipped", ...
    "ToolboxMissing","UsedOracleFields","StrictOk", ...
    "RuntimeIntegrationMode","RuntimeTransportMode","RuntimeStageWaveformsRequired", ...
    "RuntimeStageWaveformsUsed","RuntimeSelfLoopWaveformsUsed","RuntimeChannelStateUsed", ...
    "RuntimeNoiseApplied","RuntimeNoiseVarianceMean","RuntimeChannelLinkKeys","RuntimeStageCount"];
for ii = 1:numel(names)
    row.(names(ii)) = r.(names(ii));
end
end

function T = localRuntimeStageTable(r)
if istable(r.RuntimeStageRows)
    T = r.RuntimeStageRows;
else
    T = struct2table(repmat(localEmptyRuntimeStageRow(), 0, 1));
end
end

function row = localMsg1Row(r, raCfg, det)
row = struct("RunId", string(r.RunId), "CellId", double(r.CellId), "UEId", double(r.UEId), ...
    "AttemptId", double(r.AttemptId), "Frame", double(raCfg.PRACHOccasionFrame), ...
    "Slot", double(raCfg.PRACHOccasionSlot), "Symbol", double(raCfg.PRACHOccasionSymbol), ...
    "PRACHFormat", string(raCfg.PRACHFormat), "RootSequenceIndex", double(raCfg.RootSequenceIndex), ...
    "ZeroCorrelationZoneConfig", double(raCfg.ZeroCorrelationZoneConfig), ...
    "PreambleReceivedTargetPower_dBm", double(raCfg.PreambleReceivedTargetPower_dBm), ...
    "PowerRampingStep_dB", double(raCfg.PowerRampingStep_dB), ...
    "PreambleTransMax", double(raCfg.PreambleTransMax), ...
    "PreambleAttemptNumber", 1, ...
    "PowerPathloss_dB", double(r.PowerPathloss_dB), ...
    "PowerBasePathloss_dB", double(r.PowerBasePathloss_dB), ...
    "PowerPathlossSource", string(r.PowerPathlossSource), ...
    "ReferenceTxPower_dBm", double(r.ReferenceTxPower_dBm), ...
    "Pcmax_dBm", double(r.Pcmax_dBm), ...
    "PreambleDelta_dB", double(r.PreambleDelta_dB), ...
    "PreambleTargetReceivedPower_dBm", double(r.PreambleTargetReceivedPower_dBm), ...
    "PreambleRequestedTxPower_dBm", double(r.PreambleRequestedTxPower_dBm), ...
    "PreambleTxPower_dBm", double(r.PreambleTxPower_dBm), ...
    "PreamblePowerHeadroom_dB", double(r.PreamblePowerHeadroom_dB), ...
    "PreambleTxAmplitudeScale", double(r.PreambleTxAmplitudeScale), ...
    "PowerControlStatus", string(r.PowerControlStatus), ...
    "PreambleIndexTx", double(r.PreambleIndexTx), "PreambleIndexDetected", double(r.PreambleIndexDetected), ...
    "DetectionMetric", double(r.PreambleDetectionMetric), "DetectionThreshold", double(r.PreambleDetectionThreshold), ...
    "RxAntennaCount", double(r.Msg1RxAntennaCount), ...
    "PDPAverageNoiseFloor", double(r.Msg1PDPAverageNoiseFloor), ...
    "PeakToThresholdRatio", double(r.Msg1PeakToThresholdRatio), ...
    "PeakToNoiseRatio", double(r.Msg1PeakToNoiseRatio), ...
    "PeakToNoiseRatio_dB", double(r.Msg1PeakToNoiseRatio_dB), ...
    "CandidateCount", double(r.Msg1CandidateCount), ...
    "CandidatesAboveThreshold", double(r.Msg1CandidatesAboveThreshold), ...
    "TargetFalseAlarmProbability", double(r.Msg1TargetFalseAlarmProbability), ...
    "ThresholdBackgroundComponent", double(r.Msg1ThresholdBackgroundComponent), ...
    "ThresholdGlobalPeakComponent", double(r.Msg1ThresholdGlobalPeakComponent), ...
    "PeakGuardFactor", double(r.Msg1PeakGuardFactor), ...
    "PeakLagSamples", double(r.Msg1DetectorPeakLagSamples), ...
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
    "DownlinkTxPower_dBm", double(r.DownlinkTxPower_dBm), ...
    "DownlinkTxPowerSource", string(r.DownlinkTxPowerSource), ...
    "Msg2TxPower_dBm", double(r.Msg2TxPower_dBm), ...
    "Msg2TxAmplitudeScale", double(r.Msg2TxAmplitudeScale), ...
    "TimingEstimateUsed", logical(r.Msg2TimingEstimateUsed), ...
    "RawTimingEstimate_samples", double(r.Msg2RawTimingEstimate_samples), ...
    "AppliedTimingCorrection_samples", double(r.Msg2AppliedTimingCorrection_samples), ...
    "TimingEstimateSource", string(r.Msg2TimingEstimateSource), ...
    "PostEqSINR_dB", double(r.Msg2PostEqSINR_dB), ...
    "ReceiverHestSINR_dB", double(r.Msg2ReceiverHestSINR_dB), ...
    "PreEqualizationNoiseVar", double(r.Msg2PreEqualizationNoiseVar), ...
    "DecoderNoiseVar", double(r.Msg2DecoderNoiseVar), ...
    "ChannelEstimateAvailable", logical(r.Msg2ChannelEstimateAvailable), ...
    "ChannelEstimateMethod", string(r.Msg2ChannelEstimateMethod), ...
    "ChannelEstimatePilotResidualNMSE_dB", double(r.Msg2ChannelEstimatePilotResidualNMSE_dB), ...
    "EqualizationAvailable", logical(r.Msg2EqualizationAvailable), ...
    "LLRFinite", logical(r.Msg2LLRFinite), ...
    "DemapperLLRCount", double(r.Msg2DemapperLLRCount), ...
    "DecoderIterations", double(r.Msg2DecoderIterations), ...
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
    "TimingAdvanceApplied", logical(r.Msg3TimingAdvanceApplied), "DMRSUsed", true, "DMSRUsed", true, ...
    "P0PUSCH_dBm", double(raCfg.P0PUSCH_dBm), "AlphaPUSCH", double(raCfg.AlphaPUSCH), ...
    "Pcmax_dBm", double(raCfg.Pcmax_dBm), ...
    "PowerPathloss_dB", double(r.PowerPathloss_dB), ...
    "PowerBasePathloss_dB", double(r.PowerBasePathloss_dB), ...
    "PowerPathlossSource", string(r.PowerPathlossSource), ...
    "ReferenceTxPower_dBm", double(r.ReferenceTxPower_dBm), ...
    "Msg3Pathloss_dB", double(r.Msg3Pathloss_dB), ...
    "Msg3P0PUSCH_dBm", double(r.Msg3P0PUSCH_dBm), ...
    "Msg3Alpha", double(r.Msg3Alpha), ...
    "Msg3NumPRBForPower", double(r.Msg3NumPRBForPower), ...
    "Msg3DeltaTF_dB", double(r.Msg3DeltaTF_dB), ...
    "Msg3ClosedLoopCorrection_dB", double(r.Msg3ClosedLoopCorrection_dB), ...
    "Msg3RequestedTxPower_dBm", double(r.Msg3RequestedTxPower_dBm), ...
    "Msg3TxPower_dBm", double(r.Msg3TxPower_dBm), ...
    "Msg3PowerHeadroom_dB", double(r.Msg3PowerHeadroom_dB), ...
    "Msg3TxAmplitudeScale", double(r.Msg3TxAmplitudeScale), ...
    "PowerControlStatus", string(r.PowerControlStatus), ...
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
    "DownlinkTxPower_dBm", double(r.DownlinkTxPower_dBm), ...
    "DownlinkTxPowerSource", string(r.DownlinkTxPowerSource), ...
    "Msg4TxPower_dBm", double(r.Msg4TxPower_dBm), ...
    "Msg4TxAmplitudeScale", double(r.Msg4TxAmplitudeScale), ...
    "TimingEstimateUsed", logical(r.Msg4TimingEstimateUsed), ...
    "RawTimingEstimate_samples", double(r.Msg4RawTimingEstimate_samples), ...
    "AppliedTimingCorrection_samples", double(r.Msg4AppliedTimingCorrection_samples), ...
    "TimingEstimateSource", string(r.Msg4TimingEstimateSource), ...
    "PostEqSINR_dB", double(r.Msg4PostEqSINR_dB), ...
    "ReceiverHestSINR_dB", double(r.Msg4ReceiverHestSINR_dB), ...
    "PreEqualizationNoiseVar", double(r.Msg4PreEqualizationNoiseVar), ...
    "DecoderNoiseVar", double(r.Msg4DecoderNoiseVar), ...
    "ChannelEstimateAvailable", logical(r.Msg4ChannelEstimateAvailable), ...
    "ChannelEstimateMethod", string(r.Msg4ChannelEstimateMethod), ...
    "ChannelEstimatePilotResidualNMSE_dB", double(r.Msg4ChannelEstimatePilotResidualNMSE_dB), ...
    "EqualizationAvailable", logical(r.Msg4EqualizationAvailable), ...
    "LLRFinite", logical(r.Msg4LLRFinite), ...
    "DemapperLLRCount", double(r.Msg4DemapperLLRCount), ...
    "DecoderIterations", double(r.Msg4DecoderIterations), ...
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
