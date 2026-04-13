function ok = test6GScenarioRegistry()
%TEST6GSCENARIOREGISTRY Registry should expose shipped scenario files only.

setup6GRSimToolkit("Verbose", false);

T = sixgr.lls6g.config.scenarioRegistry();
ids = string(T.ScenarioID);
assert(height(T) >= 24, "Expected at least 24 shipped scenarios.");
assert(any(ids == "dl_4ghz_baseline"), "Registry missing dl_4ghz_baseline.");
assert(any(ids == "rank_adaptation_sweep"), "Registry missing rank_adaptation_sweep.");
assert(~any(contains(ids, "matrix")), "Scenario registry should not include matrix configs.");

ok = true;
end
