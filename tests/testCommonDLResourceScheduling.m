function ok = testCommonDLResourceScheduling()
% Allocation/planning evidence only; actual broadcast-grid regression is separate.
for suffix = ["_tdd", ""]
    sc = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
        "lls_causal_access_to_data_wiring"+suffix+".yaml"));
    cfg = sixgr.config.normalizeConfig(sixgr.lls6g.buildInternalConfig(sc,tempname));
    ra = sixgr.mac.ra.RAConfig(cfg);
    before = rng;
    plan = sixgr.phy.frame.CommonDLResourcePlan(cfg);
    plan.validateSIB1TRS();
    [free,conflict] = plan.checkPDSCH(ra.Msg4PDSCH,22);
    assert(~free && any(conflict.ConflictingOwners=="SIB1_PDSCH_and_Type0_PDCCH"));
    assert(all(conflict.OverlapRECounts>0) && ~conflict.ProxyUsed && ~conflict.FallbackUsed);
    assert(~plan.checkPDSCH(ra.Msg4PDSCH,27),'TRS in slot 27 must retain ownership.');
    assert(plan.checkPDSCH(ra.Msg4PDSCH,32),'Slot 32 has no SIB1/TRS collision for this allocation.');
    assert(isequal(before,rng),'Planning must not generate waveforms or consume payload/noise RNG.');
    invalid = cfg; invalid.phy.trs.slotNumbers = [2 3 7 8];
    collisionPlan = sixgr.phy.frame.CommonDLResourcePlan(invalid);
    localReject(@()collisionPlan.validateSIB1TRS(),'sixgr:phy:frame:SIB1TRSCollision');
    localReject(@()sixgr.mac.ra.RAConfig(invalid),'sixgr:phy:frame:SIB1TRSCollision');
    % Changing allocation is resolved through the same TX helper, not a
    % min(24,NSizeGrid) preflight reconstruction.
    changed = cfg; changed.initial_access.sib1.pdsch.num_prb = 12;
    changedPlan = sixgr.phy.frame.CommonDLResourcePlan(changed);
    assert(isequal(changedPlan.SIB1PDSCH.PRBSet,0:11));
    outer = ra.Msg4PDSCH; outer.PRBStart=24; outer.NumPRB=1;
    assert(changedPlan.checkPDSCH(outer,22),'An unrelated free PRB must not be suppressed by whole-slot blocking.');
    invalid = cfg; invalid.phy.mib.pdcchConfigSIB1 = 0.5;
    localReject(@()sixgr.phy.frame.CommonDLResourcePlan(invalid), ...
        'sixgr:phy:broadcast:InvalidPDCCHConfigSIB1');
end
anchor = raStrictAnchorConfig();
anchorPlan = sixgr.phy.frame.CommonDLResourcePlan(anchor);
assert(anchorPlan.SIB1Slot0>=anchorPlan.BroadcastPeriodSlots, ...
    'This fixture must exercise a Type-0 occasion beyond the first SSB period.');
anchorRA = sixgr.mac.ra.RAConfig(anchor);
assert(~anchorPlan.checkPDSCH(anchorRA.Msg4PDSCH,anchorPlan.SIB1Slot0));
ok = true;
fprintf('PASS testCommonDLResourceScheduling: configured SI/TRS ownership, both duplex profiles, RNG preservation.\n');
end

function localReject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; received %s: %s',id,cause.identifier,cause.message);
    return;
end
error('testCommonDLResourceScheduling:MissingRejection','Expected %s',id);
end
