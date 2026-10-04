function ok = testE2EReportingFixtureConfiguration()
% Configuration equivalence only; not waveform or statistical qualification.
previousRNG=rng;
restoreRNG=onCleanup(@()rng(previousRNG)); %#ok<NASGU>
root=fullfile(pwd,'results','sls','reporting_fixture_configuration');
for model=["mmtc","xr"]
    [cfg,nSlots]=e2eReceivedAccessConfig(root,3,model);
    original=sixgr.config.defaultConfig();
    original.traffic.model=char(model);
    assert(nSlots==100 && cfg.scenario.ue.nUE==3 && cfg.scenario.nUE==3);
    assert(strcmpi(cfg.phy.duplex.mode,'TDD') && cfg.channel.model=="TDL-C");
    assert(strcmpi(cfg.phy.pusch.transmissionScheme,original.phy.pusch.transmissionScheme) && ...
        cfg.phy.pusch.nLayers==original.phy.pusch.nLayers);
    assert(strcmpi(cfg.traffic.flowDirection,'BIDIR'));
    assert(isfinite(cfg.initial_access.type0.monitoring_occasion_ordinal) && ...
        ~isempty(cfg.phy.pucch.dlDataToULACK));
    for budget=[50 .1]
        original.traffic.packetDelayBudget_ms=budget;
        cfg.traffic.packetDelayBudget_ms=budget;
        cfg.traffic.flows.packetDelayBudget_ms=budget;
        for seed=[23 29 41]
            rng(seed,'twister');
            expected=sixgr.system.TrafficFactory.generate(original,3,nSlots, ...
                sixgr.time.slotDurationSec(cfg));
            rng(seed,'twister');
            actual=sixgr.system.TrafficFactory.generate(cfg,3,nSlots, ...
                sixgr.time.slotDurationSec(cfg));
            assert(isequal(actual.OfferedBitsDL,expected.OfferedBitsDL) && ...
                isequal(actual.OfferedBitsUL,expected.OfferedBitsUL), ...
                'Access repair changed the original seeded %s traffic (seed %d).',model,seed);
            assert(actual.PacketDelayBudget_ms==budget && ...
                all(actual.FlowTable.PacketDelayBudget_ms==budget), ...
                'Explicit flow and packet deadlines must agree.');
            assert(sum(actual.OfferedBitsDL,'all')>0 && sum(actual.OfferedBitsUL,'all')>0);
        end
    end
end
% Existing DL-only publication fixtures must remain unchanged.
[cfg,nSlots]=e2eReceivedAccessConfig(root,2);
assert(nSlots==70 && strcmpi(cfg.traffic.model,'traceReplay') && ...
    strcmpi(cfg.traffic.flowDirection,'DL') && ...
    all(cfg.traffic.trace.offeredBitsDL==200,'all') && ...
    all(cfg.traffic.trace.offeredBitsUL==0,'all'));
ok=true;
end
