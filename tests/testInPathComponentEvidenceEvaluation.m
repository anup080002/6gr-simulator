function ok = testInPathComponentEvidenceEvaluation()
%TESTINPATHCOMPONENTEVIDENCEEVALUATION In-path gates consume runtime rows only.

cfg = struct("users", struct("n_users", 2));
common = table([1;2], [1;2], repmat("PASS",2,1), true(2,1), ...
    false(2,1), false(2,1), false(2,1), false(2,1), ...
    repmat("active_integrated",2,1), ...
    'VariableNames', {'UEIndex','UEID','Status','StrictOk','Crash', ...
    'Skipped','ProxyUsed','FallbackFlag','SourceClassification'});

pbch = common;
for name = ["BCHCrcPass","MIBDecoded","SIB1StrictOk","SIB1TreeEqual", ...
        "SIB1DCICrcPass","SIB1DLSCHCrcPass","SIB1ASN1DecodeOk"]
    pbch.(char(name)) = true(2,1);
end
prach = common;
for name = ["RACompleted","PreambleDetected","Msg2DCICrcPass", ...
        "Msg2PDSCHCrcPass","Msg3PUSCHCrcPass","Msg4PDCCHCrcPass", ...
        "Msg4PDSCHCrcPass","ContentionIdentityMatches"]
    prach.(char(name)) = true(2,1);
end
prach.DetectionAttempted = true(2,1);
prach.RAProcedureType = repmat("contention_based_four_step",2,1);
prach.FullRAEvidenceSource = repmat("sixgr.phy.ra.runFourStepRA",2,1);
prach.RuntimeStageWaveformsUsed = true(2,1);
prach.RuntimeChannelStateUsed = true(2,1);
prach.RuntimeNoiseApplied = true(2,1);
srs = common;
for name = ["DetectionSuccess","ResourceExtractionAvailable", ...
        "SRSChannelEstimateAvailable","SRSRuntimeEvidenceUsable"]
    srs.(char(name)) = true(2,1);
end
trs = common(1,:);
trs.ServingCell = 1;
for name = ["DetectionSuccess","MeasurementUsable","TRSProcessed", ...
        "TRSTimingEstimateUsable","TRSCFOEstimateUsable", ...
        "TRSChannelEstimateAvailable","TRSRuntimeEvidenceUsable"]
    trs.(char(name)) = true;
end
raw = struct("PBCH",pbch,"PRACH",prach,"SRS",srs,"TRS",trs);

pdcch = common(1,:);
for name = ["DCICrcPass","PDCCHPayloadMatch", ...
        "PDCCHCausalGrantDecodeOk","GrantValid"]
    pdcch.(char(name)) = true;
end
pdcch.PDCCHMissedDetection = false;
pdcch.PDCCHFalseAlarm = false;
pucch = common(1,:);
pucch.CRCApplicable = false;
pucch.CRCOutcome = "not_applicable";
pucch.UCIContentMatch = true;
pucch.PUCCHDecodeOk = true;
pucch.DetectionAttempted = true;
pucch.DetectionUsable = true;
pucch.ReceiverUsable = true;
pucch.StrictReceiverEvidenceOk = true;
raw.PDCCH = pdcch;
raw.PUCCH = pucch;
puschUCI = common;
puschUCI.UCIOnPUSCHApplied = true(2,1);
puschUCI.UCIOnPUSCHFeedbackBitCount = ones(2,1);
puschUCI.ExpectedHARQACKBits = ["1";"0"];
puschUCI.DecodedHARQACKBits = ["1";"0"];
puschUCI.HARQACKContentMatch = true(2,1);
puschUCI.HARQACKDecodeStatus = repmat("decoded_match",2,1);
puschUCI.UCIOnPUSCHEvidenceSource = repmat("same_waveform_pusch_rx_crc",2,1);
puschUCI.CRCApplicable = true(2,1);
puschUCI.CRCPass = true(2,1);
raw.UL = puschUCI;

for component = ["sib1","prach","srs","trs"]
    result = sixgr.truth.evaluateInPathComponentEvidence(cfg, raw, component);
    assert(result.StrictOk && result.SameScenarioInPathEligible && ...
        result.EvidenceScope == "in_path" && ...
        ~result.LaunchedSupplementalWaveform);
end

% Blind SIB1 acquisition keeps failed alternate beams.  A later complete
% decode for every UE qualifies acquisition without deleting those misses.
mixedSIB1 = raw;
missedSIB1 = mixedSIB1.PBCH;
missedSIB1.Status(:) = "FAIL";
missedSIB1.StrictOk(:) = false;
for name = ["BCHCrcPass","MIBDecoded","SIB1StrictOk","SIB1TreeEqual", ...
        "SIB1DCICrcPass","SIB1DLSCHCrcPass","SIB1ASN1DecodeOk"]
    missedSIB1.(char(name))(:) = false;
end
mixedSIB1.PBCH = [missedSIB1; mixedSIB1.PBCH];
result = sixgr.truth.evaluateInPathComponentEvidence(cfg, mixedSIB1, "sib1");
assert(result.StrictOk && ~result.AllRowsComponentPass && ...
    result.SuccessfulEntityCount == 2, ...
    'Failed alternate SSB beams must not erase complete per-UE SIB1 acquisition evidence.');

control = sixgr.truth.evaluateInPathControlEvidence(cfg, raw, ...
    "EnablePDCCH",true, "EnablePUCCH",true);
assert(control.StrictOk && ~control.LaunchedSupplementalWaveform && ...
    height(control.SummaryTable) == 2);

control = sixgr.truth.evaluateInPathControlEvidence(cfg, raw, ...
    "EnablePDCCH",false, "EnablePUCCH",false, "EnablePUSCHUCI",true);
assert(control.StrictOk && height(control.SummaryTable) == 1 && ...
    string(control.SummaryTable.SignalFamily) == "PUSCH_UCI", ...
    "Transferred HARQ-ACK must qualify through its actual PUSCH receiver rows.");
badPUSCHUCI = raw;
badPUSCHUCI.UL.HARQACKDecodeStatus(2) = "decoded_mismatch";
control = sixgr.truth.evaluateInPathControlEvidence(cfg, badPUSCHUCI, ...
    "EnablePDCCH",false, "EnablePUCCH",false, "EnablePUSCHUCI",true);
assert(~control.StrictOk, ...
    "A mismatched same-waveform PUSCH UCI row must fail closed.");
badPUSCHCRC = raw;
badPUSCHCRC.UL.CRCPass(2) = false;
control = sixgr.truth.evaluateInPathControlEvidence(cfg, badPUSCHCRC, ...
    "EnablePDCCH",false, "EnablePUCCH",false, "EnablePUSCHUCI",true);
assert(control.StrictOk, ...
    ["A failed UL-SCH transport-block CRC must not invalidate independently " ...
     "decoded same-waveform HARQ-ACK evidence."]);
missingPUSCHCRC = raw;
missingPUSCHCRC.UL(:, ["CRCApplicable","CRCPass"]) = [];
control = sixgr.truth.evaluateInPathControlEvidence(cfg, missingPUSCHCRC, ...
    "EnablePDCCH",false, "EnablePUCCH",false, "EnablePUSCHUCI",true);
assert(control.StrictOk, ...
    ["PUSCH HARQ-ACK evidence is independently auditable from decoded bits " ...
     "and must not require an UL-SCH CRC column."]);

csiOnlyUCI = raw;
csiOnlyUCI.UL = [csiOnlyUCI.UL; csiOnlyUCI.UL(1,:)];
csiOnlyUCI.UL.UCIOnPUSCHFeedbackBitCount(end) = 0;
csiOnlyUCI.UL.ExpectedHARQACKBits(end) = "";
csiOnlyUCI.UL.DecodedHARQACKBits(end) = "";
control = sixgr.truth.evaluateInPathControlEvidence(cfg, csiOnlyUCI, ...
    "EnablePDCCH",false, "EnablePUCCH",false, "EnablePUSCHUCI",true);
puschUCISummary = control.PUSCH_UCI.SummaryTable;
assert(control.StrictOk && puschUCISummary.ObservedRows == 2 && ...
    puschUCISummary.PassingRows == 2, ...
    "CSI-only UCI rows must not be mislabeled as HARQ-ACK attempts.");

badPUCCH = raw;
badPUCCH.PUCCH.DetectionUsable(:) = false;
control = sixgr.truth.evaluateInPathControlEvidence(cfg, badPUCCH, ...
    "EnablePDCCH",true, "EnablePUCCH",true);
assert(~control.StrictOk, ...
    "Actual Format-0 receiver usability remains mandatory even without CRC.");

bad = raw;
bad.SRS.ProxyUsed(1) = true;
result = sixgr.truth.evaluateInPathComponentEvidence(cfg, bad, "srs");
assert(~result.StrictOk && contains(result.FailureReason, "proxy_placeholder"));

missingUser = raw;
missingUser.PRACH = missingUser.PRACH(1,:);
result = sixgr.truth.evaluateInPathComponentEvidence(cfg, missingUser, "prach");
assert(~result.StrictOk && contains(result.FailureReason, "runtime_successful_entity_coverage"));

% Low-SNR missed detections remain failed receiver outcomes, but they are
% valid same-chain attempts when a later attempt completes access per UE.
mixed = raw;
misses = mixed.PRACH;
misses.Status(:) = "FAIL";
misses.StrictOk(:) = false;
misses.RACompleted(:) = false;
misses.PreambleDetected(:) = false;
for name = ["Msg2DCICrcPass","Msg2PDSCHCrcPass","Msg3PUSCHCrcPass", ...
        "Msg4PDCCHCrcPass","Msg4PDSCHCrcPass","ContentionIdentityMatches"]
    misses.(char(name))(:) = false;
end
mixed.PRACH = [misses; mixed.PRACH];
result = sixgr.truth.evaluateInPathComponentEvidence(cfg, mixed, "prach");
assert(result.StrictOk && ~result.AllRowsComponentPass && ...
    result.AllRowsValidRuntimeAttempts && result.SuccessfulEntityCount == 2, ...
    "Expected low-SNR misses must remain failed outcomes without invalidating later per-UE access success.");

noSuccess = raw;
noSuccess.PRACH = misses;
result = sixgr.truth.evaluateInPathComponentEvidence(cfg, noSuccess, "prach");
assert(~result.StrictOk && contains(result.FailureReason, "successful_entity_coverage_0_of_2"), ...
    "A campaign containing only valid missed detections must not claim successful initial access.");

cfgRRC = cfg;
cfgRRC.initial_access.rrc.require_setup_complete = true;
rrcRaw = raw;
rrcRaw.PRACH.UEID(:) = NaN;
rrcRaw.PRACH.RequireRRCSetupComplete = true(2,1);
rrcRaw.PRACH.RRCTransactionID = [0;1];
rrcRaw.PRACH.RRCSetupCompleteDecodedTransactionID = [0;1];
rrcRaw.PRACH.SRB1LCID = ones(2,1);
rrcRaw.PRACH.RRCSetupCompleteDecodedSRB1LCID = ones(2,1);
rrcRaw.PRACH.RRCSetupCompleteDecodedUEIdentity = ["UE-1";"UE-2"];
rrcRaw.PRACH.RRCSetupCompletePayloadSHA256 = repmat( ...
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", 2, 1);
for name = ["RRCSetupRequestDecoded","RRCSetupDecoded","SRB1Installed", ...
        "RRCSetupCompleteCRC","RRCSetupCompleteDecoded","RRCConnected", ...
        "SetupCompleteReceiverOk","SetupCompleteChannelEstimateAvailable", ...
        "SetupCompleteEqualizationAvailable","SetupCompleteLLRFinite"]
    rrcRaw.PRACH.(char(name)) = true(2,1);
end
rrcRaw.PRACH.SetupCompleteDemapperLLRCount = [480;480];
result = sixgr.truth.evaluateInPathComponentEvidence(cfgRRC, rrcRaw, "prach");
assert(result.StrictOk, ...
    "In-path PRACH must pass only with complete waveform RRCSetupComplete evidence.");
rrcRaw.PRACH.RRCSetupCompleteDecoded(2) = false;
result = sixgr.truth.evaluateInPathComponentEvidence(cfgRRC, rrcRaw, "prach");
assert(~result.StrictOk && contains(result.FailureReason, "runtime_successful_entity_coverage_1_of_2"), ...
    "Missing required RRCSetupComplete decode must fail the in-path PRACH gate.");
ok = true;
end
