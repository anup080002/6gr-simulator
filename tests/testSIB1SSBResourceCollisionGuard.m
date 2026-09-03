function ok = testSIB1SSBResourceCollisionGuard()
%TESTSIB1SSBRESOURCECOLLISIONGUARD Keep SSB and Type-0/SIB1 REs disjoint.

setup6GRSimToolkit("Verbose", false);
scenarioDir = fullfile("simulator", "configs", "scenarios");
profiles = ["lls_causal_access_to_data_wiring.yaml", ...
    "lls_causal_access_to_data_wiring_tdd.yaml"];

for profileIndex = 1:numel(profiles)
    scenario = sixgr.lls6g.config.loadScenarioConfig( ...
        fullfile(scenarioDir, profiles(profileIndex)));
    cfg = sixgr.config.normalizeConfig( ...
        sixgr.lls6g.buildInternalConfig(scenario, tempdir));
    tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform( ...
        cfg, "SNRdB", Inf, "Seed", 4700 + profileIndex);
    assert(double(tx.SIB1AbsoluteSlot) == 2, ...
        "%s must resolve the first noncolliding Type-0 occasion to slot 2.", ...
        profiles(profileIndex));
end

scenario = sixgr.lls6g.config.loadScenarioConfig( ...
    fullfile(scenarioDir, profiles(1)));
cfg = sixgr.config.normalizeConfig( ...
    sixgr.lls6g.buildInternalConfig(scenario, tempdir));
cfg = sixgr.util.structSet(cfg, "phy.mib.pdcchConfigSIB1", 0);
localAssertTypedError(@() ...
    sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform( ...
    cfg, "SNRdB", Inf, "Seed", 4799), ...
    "sixgr:phy:broadcast:SIB1SSBResourceCollision");

ok = true;
end

function localAssertTypedError(fcn, expectedIdentifier)
threw = false;
try
    fcn();
catch ME
    threw = true;
    assert(string(ME.identifier) == string(expectedIdentifier), ...
        "Expected %s but received %s: %s", expectedIdentifier, ...
        ME.identifier, ME.message);
end
assert(threw, "Expected %s.", expectedIdentifier);
end
