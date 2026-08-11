function ok = testProtocolHARQDeliveryCausality()
%TESTPROTOCOLHARQDELIVERYCAUSALITY Keep data delivery before later packets.

setup6GRSimToolkit("Verbose", false);

state = struct("SlotDuration_s", 0.5e-3, "CurrentSlot", 16);
timing = sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime( ...
    state, 16, 20);
assert(timing.DeliveryCanonicalSlot == 16);
assert(timing.HARQFeedbackDueSlot == 20);
assert(abs(timing.DeliveryTime_s - 8.0e-3) < 1e-15, ...
    "Slot-16 TB delivery must occur at the end of slot 16.");
assert(abs(timing.HARQFeedbackTime_s - 9.5e-3) < 1e-15, ...
    "K1=4 HARQ feedback for slot 16 must remain due at slot 20.");
assert(timing.DeliveryTime_s < timing.HARQFeedbackTime_s, ...
    "Application delivery and HARQ feedback must remain distinct events.");

bridge = sixgr.protocol.WaveformProtocolBridge(localProtocolConfig(), 1);
tbsBits = 1024;
payloadBytes = bridge.maximumPayloadBytes(tbsBits);
payload = uint8(mod(0:(payloadBytes - 1), 256));
slot16Start = sixgr.time.slotStartTimeSec(16, state.SlotDuration_s);
slot18Start = sixgr.time.slotStartTimeSec(18, state.SlotDuration_s);

[slot16Bits, ~] = bridge.encodeFragment(1, "DL", "tb-slot16", ...
    "runtime-DL-UE-001-packet-1", payload, tbsBits, slot16Start);
[delivered, evidence] = bridge.deliverDecoded( ...
    "tb-slot16", slot16Bits, timing.DeliveryTime_s);
assert(delivered && evidence.Status == "delivered_after_exact_phy_decode");

% This is the production sequence that previously threw LineageViolation:
% a new slot-18 PDU follows a successful slot-16 decode while its HARQ ACK
% remains scheduled for slot 20.
[bits, nextEvidence] = bridge.encodeFragment(1, "DL", "tb-slot18", ...
    "runtime-DL-UE-001-packet-2", payload, tbsBits, slot18Start);
assert(numel(bits) == tbsBits && nextEvidence.SameWaveformPayloadTruth);

localAssertError(@() ...
    sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime(state, 16, 15), ...
    "sixgr:protocol:InvalidHARQFeedbackSlot");

ok = true;
end

function cfg = localProtocolConfig()
cfg = struct();
cfg.enabled = true;
cfg.strict = true;
cfg.configuration_epoch = 1;
cfg.rlc = struct("sn_bits", 18, "poll_pdu", 16, "poll_byte", 65536, ...
    "max_retx_threshold", 8);
cfg.pdcp = struct("sn_bits", 18, "cipher_algorithm", "NEA0", ...
    "integrity_algorithm", "NIA0");
cfg.sdap = struct("pdu_session_id", 1, ...
    "qfi_to_drb", struct("qfi", 9, "drb_id", 1));
cfg.mac = struct("lcid", 4);
cfg.traffic.sessions = struct("flow_id", "data-1", "pdu_session_id", 1, ...
    "qfi", 9, "direction", "BIDIR");
end

function localAssertError(fcn, expectedIdentifier)
try
    fcn();
catch cause
    assert(string(cause.identifier) == string(expectedIdentifier), ...
        "Expected %s, received %s.", expectedIdentifier, cause.identifier);
    return;
end
error("sixgr:test:ExpectedErrorNotThrown", ...
    "Expected error %s was not thrown.", expectedIdentifier);
end
