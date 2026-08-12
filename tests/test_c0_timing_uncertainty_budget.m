function test_c0_timing_uncertainty_budget()
%TEST_C0_TIMING_UNCERTAINTY_BUDGET Total channel+random delay stays searchable.
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","tdoc_preflight");
b=sixgr.phy.ia.c0.waveform.buildNRAnchorA(cfg,"PayloadSeed",9108);
row=sixgr.phy.ia.c0.campaigns.runC0Trial(b,cfg,20,5,0);
prefix=sum(double(b.OFDMInfo.SymbolLengths(1:b.CandidateStartSymbol)));
totalOffset=double(row.AppliedTimingSamples)-prefix;
assert(totalOffset>=0 && ...
    totalOffset<=double(cfg.search.timing_uncertainty_samples));
assert(row.PSSIdentityCorrect && row.SSSCorrect && row.PBCHOk, ...
    "High-SNR C0 receiver did not recover after respecting timing budget.");
fprintf('test_c0_timing_uncertainty_budget: PASS\n');
end
