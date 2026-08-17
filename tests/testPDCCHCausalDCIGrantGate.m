function ok = testPDCCHCausalDCIGrantGate()
%TESTPDCCHCAUSALDCIGRANTGATE Verify decoded DCI payload gates grants.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.useMex = false;
cfg.phy.carrier.NSizeGrid = 52;
cfg.phy.pdcch.enable = true;
cfg.phy.pdcch.dmrs.enable = true;
cfg.phy.pdcch.blindSearch = false;
cfg.phy.pdcch.rnti = 4660;
cfg = sixgr.config.normalizeConfig(cfg);

dciBits = int8(mod((0:31).', 2));
[tx, ~] = sixgr.phy.dl.PDCCH_Tx(cfg, "DCIBits", dciBits, "K", numel(dciBits));

[rx, info] = sixgr.phy.dl.PDCCH_Rx(tx.Waveform, cfg, ...
    "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(dciBits), ...
    "ExpectedDCIBits", dciBits, "NoiseVar", 1e-9);
assert(logical(rx.Ok) && logical(rx.DCIPayloadMatch) && logical(rx.CausalGrantDecodeOk), ...
    "PDCCH receiver must require DCI CRC and exact finalized payload match for causal grant decode.");
assert(double(rx.DCIBitErrors) == 0 && double(rx.DCIBitsCompared) == numel(dciBits), ...
    "PDCCH receiver must compare the decoded DCI against the expected grant bit vector.");
assert(logical(info.CausalGrantDecodeOk) && ~logical(info.FalseAlarm) && ~logical(info.MissedDetection), ...
    "PDCCH info must expose causal decode, false-alarm and missed-detection fields.");

wrongBits = dciBits;
wrongBits(1) = int8(~logical(wrongBits(1)));
[rxWrong, ~] = sixgr.phy.dl.PDCCH_Rx(tx.Waveform, cfg, ...
    "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(dciBits), ...
    "ExpectedDCIBits", wrongBits, "NoiseVar", 1e-9);
assert(logical(rxWrong.Ok) && ~logical(rxWrong.DCIPayloadMatch) && ~logical(rxWrong.CausalGrantDecodeOk), ...
    "A CRC-passing DCI with the wrong payload must not authorize the scheduler grant.");
assert(logical(rxWrong.FalseAlarm) && double(rxWrong.DCIBitErrors) == 1, ...
    "A payload-mismatched CRC pass must be classified as a false grant decode.");

goodTrial = table("PASS", true, true, true, false, false, true, false, true, true, ...
    'VariableNames', {'Status','DCICrcPass','PDCCHPayloadMatch','PDCCHCausalGrantDecodeOk','PDCCHFalseAlarm','PDCCHMissedDetection', ...
    'GrantValid','NegativeExpectedOk','PDCCHBlindSearchEnabled','PDCCHREGMappingAvailable'});
badTrial = table("PASS", true, false, false, true, false, false, false, true, true, ...
    'VariableNames', {'Status','DCICrcPass','PDCCHPayloadMatch','PDCCHCausalGrantDecodeOk','PDCCHFalseAlarm','PDCCHMissedDetection', ...
    'GrantValid','NegativeExpectedOk','PDCCHBlindSearchEnabled','PDCCHREGMappingAvailable'});

state = localMinimalPDCCHGateState();
grant = struct("UEIndex", 1, "Slot", 1, "Frame", 0, "ServingCell", 1);
[state, goodGrant, allowGood] = sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial(state, grant, "DL", goodTrial); %#ok<ASGLU>
assert(logical(allowGood) && logical(goodGrant.ControlDecodeOk) && ...
    strcmpi(char(string(goodGrant.PDCCHControlFailureReason)), "pdcch_dci_crc_and_payload_match"), ...
    "Coupled runtime PDCCH gate must accept a CRC-passing payload match.");
assert(logical(goodGrant.DCICrcPass) && logical(goodGrant.PDCCHPayloadMatch) && ...
    logical(goodGrant.PDCCHCausalGrantDecodeOk) && logical(goodGrant.GrantValid) && ...
    logical(goodGrant.PDCCHBlindSearchEnabled) && logical(goodGrant.PDCCHREGMappingAvailable), ...
    "Coupled runtime must propagate decoded PDCCH truth fields onto the finalized data grant.");

state = localMinimalPDCCHGateState();
[state, badGrant, allowBad] = sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial(state, grant, "DL", badTrial); %#ok<ASGLU>
assert(~logical(allowBad) && ~logical(badGrant.ControlDecodeOk) && ...
    any(strcmpi(char(string(badGrant.PDCCHControlFailureReason)), ...
    ["pdcch_dci_payload_mismatch","pdcch_false_alarm_payload_rejected"])), ...
    "Coupled runtime PDCCH gate must reject a CRC pass when the DCI payload is not the finalized grant.");
assert(logical(badGrant.DCICrcPass) && ~logical(badGrant.PDCCHPayloadMatch) && ...
    ~logical(badGrant.PDCCHCausalGrantDecodeOk) && logical(badGrant.PDCCHFalseAlarm) && ...
    ~logical(badGrant.GrantValid), ...
    "Rejected PDCCH trials must keep CRC/pass and false-alarm lineage instead of erasing it.");

ok = true;
end

function state = localMinimalPDCCHGateState()
state = struct();
state.NumUsers = 1;
state.MultiUser = struct("RNTIStart", 4660);
state.ControlGating = struct("PDCCHRequired", true);
state.LastPDCCHStatus = strings(1, 1);
state.LastSuccessfulPDCCHSlotByUE = NaN;
state.PDCCHFailureCount = 0;
state.GrantsBlockedByGatingCount = 0;
state.CurrentSlot = 1;
state.CurrentFrame = 0;
state.CurrentServingIdx = 1;
state.SlotDuration_s = 1e-3;
state.DLGrantTraceTable = table();
state.ULGrantTraceTable = table();
state.InitialAccessEvents = table();
state.InitialAccessLifecycleTraceTable = table();
end
