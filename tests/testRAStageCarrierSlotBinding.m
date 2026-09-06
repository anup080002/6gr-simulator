function ok = testRAStageCarrierSlotBinding()
% Carrier-clock/sequence regression, not qualification of RA slot scheduling.
cfg = raStrictAnchorConfig();
cfg.phy.pusch.transformPrecoding = false;
cfg.random_access.msg3_pusch.transform_precoding = false;
cfg.random_access.setup_complete_pusch.transform_precoding = false;
ra = sixgr.mac.ra.RAConfig(cfg);

% The binding is independent of duplex mode, and must survive both frame
% boundaries and long unwrapped simulation clocks without rounding a slot.
for mode = ["TDD", "FDD"]
    cfg.phy.duplex.mode = mode;
    for scs = [15 30 60 120 240 480 960]
        ra.CarrierSCSkHz = scs;
        n = 10 * scs / 15;
        for slot = [0 n-1 n n+3 1024*n+1]
            localized = sixgr.phy.ra.localizeCarrierConfig(cfg, ra, slot);
            assert(localized.phy.carrier.NSlot == mod(slot,n));
            assert(localized.phy.carrier.NFrame == floor(slot/n));
        end
    end
end
ra.CarrierSCSkHz = 60;
cfg.phy.carrier.CyclicPrefix = "extended";
localized = sixgr.phy.ra.localizeCarrierConfig(cfg, ra, 43);
assert(localized.phy.carrier.NSlot == 3 && localized.phy.carrier.NFrame == 1);
for invalid = [-1 0.5 NaN Inf]
    caught = false;
    try
        sixgr.phy.ra.localizeCarrierConfig(cfg, ra, invalid);
    catch err
        caught = string(err.identifier) == "sixgr:phy:ra:InvalidStageAbsoluteSlot";
    end
    assert(caught, "An invalid stage slot must fail, not inherit a default carrier slot.");
end

% Exercise actual coded waveforms on both sides of a 30 kHz frame boundary.
% These are isolated waveform fixtures, not a TDD/FDD scenario slot plan.
cfg = raStrictAnchorConfig();
cfg.phy.pusch.transformPrecoding = false;
cfg.random_access.msg3_pusch.transform_precoding = false;
cfg.random_access.setup_complete_pusch.transform_precoding = false;
ra = sixgr.mac.ra.RAConfig(cfg);
ra.Msg2Slot = 19;
ra.Msg3Slot = 23;
ra.Msg4Slot = 24;
ra.SetupCompleteSlot = 25;
grant = sixgr.mac.ra.buildRARULGrant(ra);
rar = sixgr.mac.ra.encodeMACRAR("RAPID", ra.PreambleIndex, ...
    "TimingAdvanceCommand", 0, "TemporaryCRNTI", ra.TempCRNTI, "ULGrant", grant);
[tx2, sched2] = sixgr.phy.ra.generateMsg2RARWaveform(cfg, ra, rar);
localCheckCarrier(tx2.Carrier, ra.Msg2Slot);
[rx2, decodedRAR] = sixgr.phy.ra.recoverMsg2RAR(tx2.Waveform, cfg, ra, sched2, tx2);
assert(rx2.Ok && decodedRAR.ULGrant.MCS == grant.MCS, ...
    "RAR PDCCH and PDSCH receivers must use the transmitted slot's sequences.");

msg3 = sixgr.mac.ra.buildMsg3Payload("UEId", 1);
[tx3, pusch] = sixgr.phy.ra.generateMsg3PUSCHWaveform(cfg, ra, decodedRAR.ULGrant, msg3);
localCheckCarrier(tx3.Carrier, ra.Msg3Slot);
% Independent Toolbox sequence at the scheduled slot: a mutually wrong Tx/Rx
% pair can pass CRC, so round-trip decoding alone cannot prove this repair.
expectedCarrier = nrCarrierConfig("NCellID", ra.NCellID, ...
    "NSizeGrid", ra.NSizeGrid, "SubcarrierSpacing", 30, "NFrame", 1, "NSlot", 3);
expectedDMRS = nrPUSCHDMRS(expectedCarrier, pusch);
assert(isequal(tx3.DMRSNativeSymbols, expectedDMRS), ...
    "Msg3 must generate the actual scheduled-slot DM-RS sequence.");
expectedCarrier.NSlot = 0;
assert(~isequal(tx3.DMRSNativeSymbols, nrPUSCHDMRS(expectedCarrier, pusch)), ...
    "The fixture must distinguish the scheduled-slot sequence from slot zero.");
[rx3, decoded3] = sixgr.phy.ra.recoverMsg3PUSCH(tx3.Waveform, cfg, ra, decodedRAR.ULGrant, tx3);
assert(rx3.Ok && decoded3.ContentionIdentity == msg3.ContentionIdentity);

msg4 = sixgr.mac.ra.buildMsg4ContentionResolution(decoded3.ContentionIdentity, ...
    "FinalCRNTI", ra.FinalCRNTI);
[tx4, sched4] = sixgr.phy.ra.generateMsg4Waveform(cfg, ra, msg4);
localCheckCarrier(tx4.Carrier, ra.Msg4Slot);
[control4, rx4, decoded4] = sixgr.phy.ra.recoverMsg4Waveform(tx4.Waveform, cfg, ra, sched4, tx4);
assert(control4.Ok && rx4.Ok && decoded4.ContentionIdentity == msg3.ContentionIdentity);

complete = sixgr.mac.ra.buildRRCSetupComplete("TransactionID", ra.RRCTransactionID, ...
    "SRB1LCID", ra.SRB1LCID, "UEIdentity", "UE-1");
[txComplete, ~] = sixgr.phy.ra.generateRRCSetupCompleteWaveform(cfg, ra, decodedRAR.ULGrant, complete);
localCheckCarrier(txComplete.Carrier, ra.SetupCompleteSlot);
[rxComplete, ~] = sixgr.phy.ra.recoverRRCSetupComplete(txComplete.Waveform, cfg, ra, txComplete);
assert(rxComplete.Ok, "RRCSetupComplete must decode with the frame-bound carrier slot.");
ok = true;
fprintf('PASS testRAStageCarrierSlotBinding: actual RA waveform slots, sequences and CRCs checked.\n');
end

function localCheckCarrier(carrier, absoluteSlot)
assert(carrier.NSlot == mod(absoluteSlot, carrier.SlotsPerFrame));
assert(carrier.NFrame == floor(absoluteSlot / carrier.SlotsPerFrame));
end
