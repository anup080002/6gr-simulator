function ok=test5MHzCSIRSSSBSeparation()
% Actual inherited TDD configurations, plus the retained symbol-5 defect.
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
    assert(isequal(before,rng) && evidence.Applicable && ...
        evidence.CycleSlots==20 && evidence.CheckedOccasions==1);
    assert(isequal(cfg.phy.csirs.symbolLocationsByResource,6));
    % The same installed calendar must cover later repetitions too.
    for slot0=[1 21 41]
        current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
        carrier=sixgr.phy.grid.makeCarrier(current);
        indices=sixgr.phy.refsig.csirs(carrier,current);
        reserved=sixgr.phy.frame.ssbPRBSymbolReservation(current,carrier,slot0);
        occupied=unique(mod(double(indices(:))-1,12*carrier.NSizeGrid*carrier.SymbolsPerSlot));
        assert(~isempty(indices) && isempty(intersect(occupied,reserved.ReservedCarrierRE0)));
    end
    invalid=scenario.toStruct();
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
    fprintf('CSI_SSB_SEPARATION_PASS scenario=%s period=%d guarded_old_symbol=5 valid_symbol=6\n', ...
        name,evidence.CycleSlots);
end
ok=true;
end
