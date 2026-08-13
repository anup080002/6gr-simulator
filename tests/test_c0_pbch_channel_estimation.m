function test_c0_pbch_channel_estimation()
%TEST_C0_PBCH_CHANNEL_ESTIMATION CE-UT1 through CE-UT6.
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","smoke");
b=sixgr.phy.ia.c0.waveform.buildNRAnchorA(cfg,"PayloadSeed",9510);
gates=sixgr.phy.ia.c0.validation.runPBCHCEUnitTests(b,cfg);
if ~all(gates.Pass)
    first=gates(find(~gates.Pass,1),:);
    error("test_c0_pbch_channel_estimation:Failed", ...
        "%s failed (%s = %.6g).",first.UnitTest,first.Definition,first.MeasuredValue);
end
fprintf('test_c0_pbch_channel_estimation: PASS (CE-UT1..CE-UT6)\n');
end
