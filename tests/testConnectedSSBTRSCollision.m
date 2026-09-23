function ok=testConnectedSSBTRSCollision()
% Reproduce the retained slot-1 SSB/TRS overlap using the actual TDD YAML.
% A rejected candidate must not reach the PDSCH DM-RS allocator.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/master_geometry_based.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,2);
plan=sixgr.phy.frame.CommonDLResourcePlan(cfg);
carrier=sixgr.phy.grid.makeCarrier(cfg);
symbols=double(cfg.phy.pdsch.symbolAllocation);
allocation=struct('PRBStart',0,'NumPRB',carrier.NSizeGrid, ...
    'SymbolStart',symbols(1),'NumSymbols',symbols(2));
[free,common]=plan.checkPDSCH(allocation,1);
assert(~free && any(common.ConflictingOwners=="SSB_PRB_symbol_reservation") && ...
    any(common.ConflictingOwners=="TRS"), ...
    'The retained failure fixture must contain both SSB and TRS.');
before=rng;
[free,connected]=plan.checkConnectedPDSCH(allocation,1);
assert(~free && isequal(connected.ConflictingOwners,common.ConflictingOwners) && ...
    isequal(connected.OverlapRECounts,common.OverlapRECounts) && ...
    connected.TRSRateMatchedRECount==0 && isequal(before,rng), ...
    'An already blocked candidate must retain every owner without running TRS-sharing allocation.');

% Check every frequency candidate. Only TRS-only candidates may be admitted
% by exact RE reservation. SSB is never bypassed, punctured or disabled.
blocked=0; shared=0;
for prb=0:carrier.NSizeGrid-1
    candidate=allocation; candidate.PRBStart=prb; candidate.NumPRB=1;
    [~,original]=plan.checkPDSCH(candidate,1);
    [available,resolved]=plan.checkConnectedPDSCH(candidate,1);
    hardConflict=any(original.ConflictingOwners~="TRS");
    if hardConflict
        assert(~available && resolved.TRSRateMatchedRECount==0);
        assert(isequal(resolved.ConflictingOwners,original.ConflictingOwners));
        blocked=blocked+1;
    elseif any(original.ConflictingOwners=="TRS")
        assert(available && resolved.TRSRateMatchedRECount>0 && isempty(resolved.ConflictingOwners));
        shared=shared+1;
    else
        assert(available && resolved.TRSRateMatchedRECount==0);
    end
end
assert(blocked>0 && shared>0,'Exercise blocked and legal shared candidates in the same slot.');
fprintf('CONNECTED_SSB_TRS_COLLISION_PASS slot0=1 blocked_prbs=%d shared_prbs=%d all_owners_retained=1\n',blocked,shared);
ok=true;
end
