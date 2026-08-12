function test_cfo_injection()
%TEST_CFO_INJECTION Verify applied CFO and blind-grid recovery signs.
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","smoke");
b=sixgr.phy.ia.c0.waveform.buildNRAnchorA(cfg,"PayloadSeed",9103);
cfg.runtime=struct("sample_rate_hz",b.SampleRateHz);
cfg.oscillator.ue_ppm_range=[-1 -1]; cfg.oscillator.trp_ppm_range=[0 0];
cfg.search.cfo_hypotheses_hz=[-7000 0 7000]; cfg.search.timing_uncertainty_samples=0;
rx=repmat(b.Waveform,1,double(cfg.mimo.num_rx_antennas));
[rx,meta]=sixgr.phy.ia.c0.impairments.applyOscillatorCFO(rx,cfg,9301);
prefix=sum(double(b.OFDMInfo.SymbolLengths(1:b.CandidateStartSymbol)));
r=sixgr.phy.ia.c0.receiver.runCompleteSSBReceiver(rx,b,cfg,0, ...
    "TrueCFOHz",meta.AppliedCFOHz,"TrueTimingSamples",prefix);
assert(abs(meta.AppliedCFOHz-7000)<1e-9);
assert(abs(r.CFOErrorHz)<1e-6);
assert(r.PSSIdentityCorrect&&r.SSSCorrect&&r.PBCHOk);
fprintf('test_cfo_injection: PASS\n');
end
