function ok=testTimingSearchGuardAuthority()
% Unit conversion/configuration validation, not a timing measurement.
setup6GRSimToolkit("Verbose",false);
cfg=struct("phy",struct("synchronization",struct("maxTimingUncertainty_us",10)));
for fs=[1.92e6 7.68e6 30.72e6 122.88e6]
    [guard,source]=sixgr.phy.sync.resolveTimingSearchGuard(cfg,fs);
    assert(guard==ceil(10e-6*fs));
    assert(guard/fs>=10e-6 && (guard-1)/fs<10e-6);
    assert(source=="configured_receiver_timing_uncertainty_us_at_actual_sample_rate");
end
bad=cfg;
bad.phy.synchronization.maxTimingUncertaintySamples=77;
localError(@()sixgr.phy.sync.resolveTimingSearchGuard(bad,7.68e6), ...
    "sixgr:phy:sync:AmbiguousTimingSearchBudget");
legacy=struct("phy",struct("synchronization",struct("maxTimingUncertaintySamples",77)));
assert(sixgr.phy.sync.resolveTimingSearchGuard(legacy,7.68e6)==77);
assert(sixgr.phy.sync.resolveTimingSearchGuard(struct(),7.68e6)==0);
root=fullfile("simulator","configs","scenarios");
% Configuration-only check for both authored profiles; no FDD simulation.
for file=["lls_causal_access_to_data_wiring_tdd.yaml","lls_causal_access_to_data_wiring.yaml"]
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile(root,file));
    built=sixgr.lls6g.buildInternalConfig(s,tempname);
    assert(built.phy.synchronization.maxTimingUncertainty_us==s.Data.synchronization.max_timing_uncertainty_us);
    assert(sixgr.phy.sync.resolveTimingSearchGuard(built,7.68e6)==77);
    contradictory=s.Data;
    contradictory.synchronization.max_timing_uncertainty_samples=77;
    inconsistent=sixgr.lls6g.config.ScenarioConfig(contradictory);
    localError(@()sixgr.lls6g.buildInternalConfig(inconsistent,tempname), ...
        "sixgr:lls6g:config:AmbiguousTimingSearchBudget");
end
fprintf('TIMING_SEARCH_GUARD_AUTHORITY_PASS: explicit time budget scales with sample rate; conflicting units rejected.\n');
ok=true;
end

function localError(action,identifier)
try
    action();
catch ME
    assert(string(ME.identifier)==identifier,"Expected %s; got %s: %s",identifier,ME.identifier,ME.message);
    return;
end
error("TEST:MissingExpectedError","Expected %s.",identifier);
end
