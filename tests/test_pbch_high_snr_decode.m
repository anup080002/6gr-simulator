function test_pbch_high_snr_decode()
%TEST_PBCH_HIGH_SNR_DECODE Verify exact clean PBCH/polar/BCH recovery.
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","smoke");
b=sixgr.phy.ia.c0.waveform.buildNRAnchorA(cfg,"PayloadSeed",9106);
rx=repmat(b.Waveform,1,double(cfg.mimo.num_rx_antennas));
prefix=sum(double(b.OFDMInfo.SymbolLengths(1:b.CandidateStartSymbol)));
r=sixgr.phy.ia.c0.receiver.runOracleReceiver(rx,b,cfg,0,prefix);
assert(r.PBCHOk&&r.CompleteSSBSuccess);
fprintf('test_pbch_high_snr_decode: PASS\n');
end
