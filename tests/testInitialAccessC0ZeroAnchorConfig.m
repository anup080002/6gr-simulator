function ok=testInitialAccessC0ZeroAnchorConfig()
%TESTINITIALACCESSC0ZEROANCHORCONFIG Guard YAML-owned zero-noise anchor seeds.
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","smoke");
assert(double(cfg.validation.zero_impairment_anchor_snr_db)==35);
assert(double(cfg.validation.zero_impairment_anchor_trial_index)==200000);
seeds=sixgr.phy.ia.c0.util.trialSeeds(cfg, ...
    cfg.validation.zero_impairment_anchor_snr_db, ...
    cfg.validation.zero_impairment_anchor_trial_index);
assert(all([seeds.Channel seeds.CFO seeds.Noise seeds.Timing] <= 2^32-1));

bad=cfg; bad.validation.zero_impairment_anchor_snr_db=35.1;
localAssertError(@()sixgr.phy.ia.c0.config.validateScenario(bad), ...
    "sixgr:phy:ia:c0:config:ZeroImpairmentAnchorSNR");
bad=cfg; bad.validation.zero_impairment_anchor_trial_index=cfg.run.max_trials_per_snr;
localAssertError(@()sixgr.phy.ia.c0.config.validateScenario(bad), ...
    "sixgr:phy:ia:c0:config:ZeroImpairmentAnchorSeedCollision");
fprintf("InitialAccessC0ZeroAnchorConfig: YAML SNR/seed authority PASS.\n");
ok=true;
end

function localAssertError(fcn,id)
try
    fcn();
catch ME
    assert(strcmp(ME.identifier,id),"Expected %s, received %s.",id,ME.identifier);
    return;
end
error("testInitialAccessC0ZeroAnchorConfig:MissingError","Expected %s.",id);
end
