function ok=testConfiguredDCISymbolBudget()
% Clipped TDD budgets cannot create receiver TDRA rows implicitly.
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
supports=@(c,d,a)sixgr.phy.pdcch.DCIContextFactory.supportsSymbolAllocation(c,d,a);
assert(supports(cfg,'DL',[2 12]));
assert(~supports(cfg,'DL',[2 8]));
assert(~supports(cfg,'DL',[0 0]));
% Explicitly configuring a shorter row makes it eligible; the runtime must
% not achieve the same result by silently truncating a full-slot row.
cfg.phy.pdsch.timeDomainAllocations=[0 2 12 0; 1 2 8 0];
assert(supports(cfg,'DL',[2 8]));
assert(~supports(cfg,'DL',[3 7]));
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator','configs', ...
    'validation','lls_fdd_staged_data_connected_dci.yaml'));
connected=sixgr.lls6g.buildInternalConfig(scenario,tempname);
assert(supports(connected,'DL',[2 12]));
assert(~supports(connected,'DL',[2 8]));
ok=true;
end
