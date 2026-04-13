function ok = test6G4GHzTrafficPeriodicity()
%TEST6G4GHZTRAFFICPERIODICITY Keep SCN00 flow ownership and periodic traffic honest.

setup6GRSimToolkit("Verbose", false);

scenarioPath = "simulator/configs/scenarios/variants/SCN00_BASELINE_CAPACITY.yaml";
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, "scn00_traffic_periodicity_check"));

nUE = double(scfg.get("users.n_users"));
nSteps = 8;
tti_s = 5e-4;
traffic = sixgr.system.TrafficFactory.generate(cfg, nUE, nSteps, tti_s);

assert(height(traffic.FlowTable) == 5, "SCN00 traffic mix should resolve to five configured flows.");
assert(sum(double(traffic.FlowTable.UECount), "omitnan") == 100, ...
    "SCN00 flow ownership should cover exactly 100 UEs.");

startIdx = 1;
periodicFlowNames = ["xr_stream", "voip_conversational"];
for i = 1:height(traffic.FlowTable)
    ueCount = double(traffic.FlowTable.UECount(i));
    stopIdx = startIdx + ueCount - 1;
    idx = startIdx:stopIdx;
    name = string(traffic.FlowTable.Name(i));
    if any(name == periodicFlowNames)
        activeCounts = sum(double(traffic.OfferedBitsDL(:, idx)) > 0, 2);
        assert(any(activeCounts < numel(idx)), ...
            "Periodic SCN00 flow '%s' must not activate every owned UE in every runtime step.", name);
        assert(any(activeCounts > 0), ...
            "Periodic SCN00 flow '%s' must still emit traffic for at least one owned UE.", name);
    end
    startIdx = stopIdx + 1;
end

ok = true;
end
