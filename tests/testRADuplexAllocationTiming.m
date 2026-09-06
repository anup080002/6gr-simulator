function ok = testRADuplexAllocationTiming()
% Test the actual TDD/FDD profiles' allocation planner, without launching a run.
for suffix = ["_tdd", ""]
    path = fullfile("simulator","configs","scenarios", ...
        "lls_causal_access_to_data_wiring"+suffix+".yaml");
    sc = sixgr.lls6g.config.loadScenarioConfig(path);
    cfg = sixgr.config.normalizeConfig(sixgr.lls6g.buildInternalConfig(sc,tempname));
    ra = sixgr.mac.ra.RAConfig(cfg);
    frame = sixgr.phy.FrameStructureEngine(cfg,"FrameCoreOnly",true);
    slots = [ra.Msg2Slot ra.Msg3Slot ra.Msg4Slot ra.SetupCompleteSlot];
    if suffix == "_tdd"
        assert(isequal(slots,[6 9 12 14]),"The configured five-slot TDD pattern must produce legal RA allocations.");
    else
        assert(frame.DuplexMode == "FDD" && isequal(slots,[2 5 6 7]));
    end
    assert(frame.IsDLAllocation(ra.Msg2Slot,[ra.Msg2PDSCH.SymbolStart ra.Msg2PDSCH.NumSymbols]));
    assert(frame.IsULAllocation(ra.Msg3Slot,[ra.Msg3PUSCH.SymbolStart ra.Msg3PUSCH.NumSymbols]));
    assert(frame.IsDLAllocation(ra.Msg4Slot,[ra.Msg4PDSCH.SymbolStart ra.Msg4PDSCH.NumSymbols]));
    assert(frame.IsULAllocation(ra.SetupCompleteSlot,[ra.SetupCompletePUSCH.SymbolStart ra.SetupCompletePUSCH.NumSymbols]));
    grant = sixgr.mac.ra.buildRARULGrant(ra);
    assert(ra.Msg3Slot == ra.Msg2Slot + grant.K2 + grant.Msg3AdditionalDelaySlots);
    assert(sixgr.phy.ra.resolveMsg3SlotFromRAR(ra,grant) == ra.Msg3Slot);
    wrong = ra; wrong.Msg3Slot = ra.Msg3Slot + 1;
    localThrows(@()sixgr.phy.ra.resolveMsg3SlotFromRAR(wrong,grant), ...
        "sixgr:phy:ra:DecodedRARSlotMismatch");
    missing = rmfield(grant,"Msg3AdditionalDelaySlots");
    localThrows(@()sixgr.phy.ra.resolveMsg3SlotFromRAR(ra,missing), ...
        "sixgr:phy:ra:MissingDecodedRARTiming");
    wrongCfg = cfg; wrongCfg.random_access.timing.msg3_k2_slots = 2;
    localThrows(@()sixgr.mac.ra.RAConfig(wrongCfg),"sixgr:phy:ia:RARConfiguredK2Mismatch");
    if frame.DuplexMode == "FDD"
        zeroDelay = cfg;
        zeroDelay.random_access.timing.msg4_processing_delay_slots = 0;
        dependent = sixgr.mac.ra.RAConfig(zeroDelay);
        assert(dependent.Msg4Slot > dependent.Msg3Slot, ...
            "FDD does not permit dependent Msg4 transmission before full-slot Msg3 reception ends.");
    end
    if suffix == "_tdd"
        wrongCfg = cfg; wrongCfg.random_access.timing.setup_complete_k2_slots = 1;
        localThrows(@()sixgr.mac.ra.RAConfig(wrongCfg),"sixgr:phy:ia:NoLegalMsg4SetupAllocation");
        wrongCfg = cfg; wrongCfg.random_access.ra_response_window_slots = 1;
        localThrows(@()sixgr.mac.ra.RAConfig(wrongCfg),"sixgr:phy:ia:NoLegalRARMsg3Allocation");
        % A cached PRACH resolution must not bypass a changed canonical map.
        wrongCfg = cfg;
        wrongCfg.phy.duplex.tddCommon.Pattern1.NumDownlinkSlots = 4;
        wrongCfg.phy.duplex.tddCommon.Pattern1.NumUplinkSlots = 0;
        localThrows(@()sixgr.mac.ra.RAConfig(wrongCfg),"sixgr:mac:ra:ConfiguredPRACHOccasionNotUL");
    end
end
anchor = raStrictAnchorConfig();
ra = sixgr.mac.ra.RAConfig(anchor);
assert(ra.PRACHAbsoluteSlot == 2 && ra.PRACHOccasionEndSlot == 3, ...
    "A long Msg1 spans two 30 kHz slots; response timing must start after its end.");
assert(ra.TimingSchedule.ResponseWindowStartSlot == 4);
assert(~ra.TimingSchedule.ControlMonitoringQualified && ~ra.TimingSchedule.SetupCompleteGrantQualified, ...
    "Allocation legality alone must not qualify undecoded control authority.");
ok = true;
fprintf('PASS testRADuplexAllocationTiming: TDD/FDD plans, RAR K2+delta, Msg1 span and invalid-schedule rejection.\n');
end

function localThrows(f,id)
try
    f();
catch err
    assert(string(err.identifier) == id,"Expected %s, received %s: %s",id,err.identifier,err.message);
    return;
end
error("testRADuplexAllocationTiming:MissingRejection","Expected %s.",id);
end
