function ok=testMasterRATimingAllocation()
% Verify the operator master with real RA/TDD resource planners, not PHY claims.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/master_geometry_based.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
ra=sixgr.mac.ra.RAConfig(cfg,'UEId',1,'AttemptId',1);
frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
assert(frame.DuplexMode=="TDD");
assert(frame.IsDLAllocation(ra.Msg2Slot,[ra.Msg2PDSCH.SymbolStart ra.Msg2PDSCH.NumSymbols]));
assert(frame.IsULAllocation(ra.Msg3Slot,[ra.Msg3PUSCH.SymbolStart ra.Msg3PUSCH.NumSymbols]));
assert(frame.IsDLAllocation(ra.Msg4Slot,[ra.Msg4PDSCH.SymbolStart ra.Msg4PDSCH.NumSymbols]));
assert(frame.IsULAllocation(ra.SetupCompleteSlot, ...
    [ra.SetupCompletePUSCH.SymbolStart ra.SetupCompletePUSCH.NumSymbols]));
assert(ra.SetupCompleteSlot-ra.Msg4Slot==cfg.random_access.timing.setup_complete_k2_slots);
assert(ra.Msg4Slot<ra.Msg3Slot+cfg.random_access.ra_contention_resolution_timer_slots);
plan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
assert(plan.checkPDSCH(ra.Msg2PDSCH,ra.Msg2Slot) && plan.checkPDSCH(ra.Msg4PDSCH,ra.Msg4Slot));
assert(~ra.TimingSchedule.SetupCompleteGrantQualified, ...
    'Legal resource scheduling does not establish physical UL grant reception.');
bad=cfg; bad.random_access.timing.setup_complete_k2_slots=1;
try
    sixgr.mac.ra.RAConfig(bad,'UEId',1,'AttemptId',1);
catch err
    assert(strcmp(err.identifier,'sixgr:phy:ia:NoLegalMsg4SetupAllocation'), ...
        'Expected original allocation rejection, got %s: %s',err.identifier,err.message);
    fprintf('MASTER_RA_TIMING_PASS msg2=%d msg3=%d msg4=%d setup=%d invalid_k2_rejected=1\n', ...
        ra.Msg2Slot,ra.Msg3Slot,ra.Msg4Slot,ra.SetupCompleteSlot);
    ok=true;
    return;
end
error('testMasterRATimingAllocation:MissingRejection', ...
    'The original one-slot offset must remain illegal for this master allocation.');
end
