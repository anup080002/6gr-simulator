function ok=testMobileCSIRSCalendar()
% Validate the actual mobile YAML without launching the 64-TXRU waveform run.
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_mobile_2ue_100kmh_1sector_full_capture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
assert(cfg.phy.csirs.period_slots==10 && cfg.phy.csirs.offset_slots==6);
assert(cfg.phy.csi.reportPeriodicitySlots==5 && cfg.phy.csi.reportOffsetSlots==4);
e=sixgr.phy.refsig.validateCSIRSSSBSeparation(cfg);
assert(e.Applicable && e.CycleSlots==40);
for slot0=0:79
    [due,~]=sixgr.phy.refsig.csirsOccasion(cfg,slot0);
    assert(due==(mod(slot0,10)==6),'Runtime CSI-RS calendar differs from the YAML period/offset.');
    if ~due, continue; end
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
    carrier=sixgr.phy.grid.makeCarrier(current);
    indices=sixgr.phy.refsig.csirs(carrier,current);
    reserved=sixgr.phy.frame.ssbPRBSymbolReservation(current,carrier,slot0);
    occupied=unique(mod(double(indices(:))-1,12*carrier.NSizeGrid*carrier.SymbolsPerSlot));
    assert(~isempty(indices) && isempty(intersect(occupied,reserved.ReservedCarrierRE0)));
end
% Reproduce the original inherited-zero collision; keep the strict guard.
bad=scenario.toStruct(); bad.reference_signals.csi_rs_offset_slots=0;
caught=false;
try
    sixgr.lls6g.buildInternalConfig(bad,tempname);
catch err
    caught=strcmp(err.identifier,'sixgr:phy:csirs:SSBResourceCollision');
    if ~caught, rethrow(err); end
end
assert(caught,'Original CSI-RS/SSB overlap was not rejected.');
ok=true;
fprintf('MOBILE_CSIRS_CALENDAR_PASS period_slots=10 offset_slots=6 checked_slots=80 original_collision_rejected=1\n');
end
