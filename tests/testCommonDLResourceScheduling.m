function ok = testCommonDLResourceScheduling()
% Allocation/planning evidence only; actual broadcast-grid regression is separate.
for suffix = ["_tdd", ""]
    sc = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
        "lls_causal_access_to_data_wiring"+suffix+".yaml"));
    cfg = sixgr.config.normalizeConfig(sixgr.lls6g.buildInternalConfig(sc,tempname));
    ra = sixgr.mac.ra.RAConfig(cfg);
    before = rng;
    plan = sixgr.phy.frame.CommonDLResourcePlan(cfg);
    plan.validateSIB1References();
    localVerifyReferenceCalendar(cfg,plan);
    if suffix==""
        % Retain the original production FDD collision as a negative case.
        badCSI=cfg; badCSI.phy.csirs.offset_slots=2;
        localReject(@()sixgr.mac.ra.RAConfig(badCSI), ...
            'sixgr:phy:frame:SIB1CSIRSCollision');
    end
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
assert(anchorPlan.SIB1Slot0==41 && anchorPlan.SIB1PeriodSlots==40);
assert(anchorPlan.SIB1Slot0>=anchorPlan.BroadcastPeriodSlots, ...
    'This fixture must exercise a Type-0 occasion beyond the first SSB period.');
anchorPlan.validateSIB1References();
% The old ordinal selects a genuine same-RE collision, not an invalid
% Type-0 monitoring candidate. Keep its production rejection as evidence.
oldAnchor=anchor;
oldAnchor.initial_access.type0.monitoring_occasion_ordinal=3;
oldPlan=sixgr.phy.frame.CommonDLResourcePlan(oldAnchor);
assert(oldPlan.SIB1Slot0==40);
localReject(@()oldPlan.validateSIB1SSB(),'sixgr:phy:frame:SIB1SSBCollision');
localReject(@()sixgr.mac.ra.RAConfig(oldAnchor),'sixgr:phy:frame:SIB1SSBCollision');
occasions=anchorPlan.sib1TransmissionOccasions(0,122);
assert(isequal(occasions.AbsoluteSlot,[41;81;121]) && ...
    all(occasions.FirstConfiguredAbsoluteSlot==41) && ...
    all(occasions.PeriodSlots==40));
anchorRA = sixgr.mac.ra.RAConfig(anchor);
for slot0=occasions.AbsoluteSlot.'
    % Exercise the same explicit-occasion resolver used by the SI producer,
    % including its symbol-level duplex check; these are not RX outcomes.
    [~,~,~,resolved,actual]=sixgr.phy.broadcast.resolveSIB1ControlOccasion( ...
        anchorPlan.Carrier,anchor,'AbsoluteSlot',slot0);
    assert(actual==slot0 && resolved.SelectedMonitoringOccasion.AbsoluteSlot==slot0);
    [free,conflict]=anchorPlan.checkPDSCH(anchorRA.Msg4PDSCH,slot0);
    assert(~free && any(conflict.ConflictingOwners=="SIB1_PDSCH_and_Type0_PDCCH"));
end
ok = true;
fprintf('PASS testCommonDLResourceScheduling: configured SI/TRS ownership, both duplex profiles, RNG preservation.\n');
end

function localVerifyReferenceCalendar(cfg,plan)
% Exact configured RE geometry, not a claim that CSI was received.
% Subtract only CSI from a second planning view to compare with all other
% common reservations; the scenario under test keeps every signal enabled.
assert(cfg.phy.csirs.enable && cfg.phy.ssb.enable && cfg.phy.sib1.enable && cfg.phy.trs.enable);
other=cfg; other.phy.csirs.enable=false;
otherPlan=sixgr.phy.frame.CommonDLResourcePlan(other);
cycle=lcm(double(cfg.phy.csirs.period_slots),double(plan.BroadcastPeriodSlots));
cycle=lcm(cycle,double(plan.Carrier.SlotsPerFrame)); % Explicit TRS slots recur per frame.
configuredSources=zeros(0,1);
for slot0=0:2*cycle-1
    if ~sixgr.phy.refsig.csirsOccasion(cfg,slot0), continue; end
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
    carrier=sixgr.phy.grid.makeCarrier(current);
    [indices,symbols]=sixgr.phy.refsig.csirs(carrier,current);
    assert(~isempty(indices) && ~isempty(symbols));
    k=12*carrier.NSizeGrid;
    re=unique(mod(double(indices(:))-1,k*carrier.SymbolsPerSlot));
    coordinates=[mod(re,k)+12*carrier.NStartGrid,floor(re/k)];
    assert(isempty(intersect(coordinates,otherPlan.controlReservations(slot0),'rows')), ...
        'testCommonDLResourceScheduling:ReferenceCollision', ...
        'CSI-RS overlaps SSB/SI/TRS in absolute slot0 %d.',slot0);
    configuredSources(end+1,1)=slot0+1; %#ok<AGROW> not received measurements
end
reportSlots=(1:2*cycle).';
reportSlots=reportSlots(sixgr.truth.periodicCSIReportSlotMask(reportSlots, ...
    cfg.phy.csi.reportPeriodicitySlots,cfg.phy.csi.reportOffsetSlots));
eligibleReports=0;
for report=reportSlots.'
    reference=sixgr.truth.periodicCSIReferenceSlot(cfg,report);
    if ~isfinite(reference), continue; end % No pre-start reference is manufactured.
    source=configuredSources(find(configuredSources<=reference,1,'last'));
    assert(~isempty(source) && source<report);
    eligibleReports=eligibleReports+1;
end
assert(eligibleReports>0,'Configured periodic feedback needs an earlier reference opportunity.');
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
