function ok=test5MHzCSIRSSSBSeparation()
% Actual inherited TDD calendars, plus an explicitly colliding old occasion.
setup6GRSimToolkit('Verbose',false);
scenarios=["lls_tdd_5mhz_rank2_shared_awgn_20db", ...
    "lls_tdd_5mhz_rank2_shared_awgn_20db_saturated", ...
    "lls_tdd_5mhz_rank2_shared_awgn_snr_sweep", ...
    "lls_tdd_5mhz_rank2_shared_awgn_snr_sweep_saturated"];
for name=scenarios
    scenario=sixgr.lls6g.config.loadScenarioConfig( ...
        fullfile('simulator','configs','scenarios',name+'.yaml'));
    cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
    before=rng;
    evidence=sixgr.phy.refsig.validateCSIRSSSBSeparation(cfg);
    assert(cfg.phy.csirs.period_slots==5 && cfg.phy.csirs.offset_slots==0);
    assert(isequal(before,rng) && evidence.Applicable && ...
        evidence.CycleSlots==20 && evidence.CheckedOccasions==1, ...
        'Scenario %s RNGPreserved=%d calendar=%s',name,isequal(before,rng),jsonencode(evidence));
    assert(isequal(cfg.phy.csirs.symbolLocationsByResource,6));
    % The same installed calendar must cover later repetitions too.
    % Same-slot SSB/CSI is legal only because their exact symbols differ;
    % Type-0 SIB1 at 2+20n is now outside the authored CSI calendar.
    common=sixgr.phy.frame.CommonDLResourcePlan(cfg);
    common.validateSIB1References();
    for slot0=[0 5 10 15 20 40]
        current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
        carrier=sixgr.phy.grid.makeCarrier(current);
        indices=sixgr.phy.refsig.csirs(carrier,current);
        reserved=sixgr.phy.frame.ssbPRBSymbolReservation(current,carrier,slot0);
        occupied=unique(mod(double(indices(:))-1,12*carrier.NSizeGrid*carrier.SymbolsPerSlot));
        assert(~isempty(indices) && isempty(intersect(occupied,reserved.ReservedCarrierRE0)));
    end
    invalid=scenario.toStruct();
    % Moving back into an SS/PBCH slot and onto symbol 5 must still fail.
    % Symbol 5 alone is not an overlap when the current calendar is disjoint.
    invalid.reference_signals.csi_rs_offset_slots=1;
    invalid.reference_signals.csi_rs_resource_symbol_locations=5;
    rejected=false;
    try
        sixgr.lls6g.buildInternalConfig(invalid,tempname);
    catch cause
        assert(string(cause.identifier)=="sixgr:phy:csirs:SSBResourceCollision", ...
            'Unexpected rejection: %s %s',cause.identifier,cause.message);
        rejected=true;
    end
    assert(rejected,'The retained CSI-RS/SSB collision must fail before execution.');
    fprintf('CSI_SSB_SEPARATION_PASS scenario=%s cycle=%d configured_period=5 configured_offset=0 rejected_offset=1 rejected_symbol=5\n', ...
        name,evidence.CycleSlots);
end
ok=true;
end
