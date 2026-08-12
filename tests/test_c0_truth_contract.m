function test_c0_truth_contract()
%TEST_C0_TRUTH_CONTRACT Verify fail-closed C0 evidence semantics.
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","smoke");
b=sixgr.phy.ia.c0.waveform.buildNRAnchorA(cfg,"PayloadSeed",9107);
assert(cfg.meta.research_class=="baseline_benchmark");
assert(cfg.output.prohibit_svg);
assert(b.ResourceAudit.Normalization.Passed);
assert(~isempty(which("sixgr.phy.ia.c0.validation.validateC0")));
assert(~isempty(which("sixgr.phy.ia.c0.search.calibrateGlobalFalseAlarm")));
fprintf('test_c0_truth_contract: PASS\n');
end
