function test_tdl_channel_power()
%TEST_TDL_CHANNEL_POWER Verify concrete TDL-C waveform execution.
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","smoke");
b=sixgr.phy.ia.c0.waveform.buildNRAnchorA(cfg,"PayloadSeed",9104);
c=sixgr.phy.ia.c0.channel.applyFading(b.Waveform,b,cfg,9401);
assert(c.ExecutionBackend=="nrTDLChannel");
assert(size(c.Waveform,2)==4);
assert(all(isfinite(real(c.Waveform(:)))) && ...
    all(isfinite(imag(c.Waveform(:)))));
[p,~]=sixgr.phy.ia.c0.channel.measureActiveREPower( ...
    c.Waveform,b,c.TimingOffsetSamples);
assert(isfinite(p)&&p>0);
fprintf('test_tdl_channel_power: PASS\n');
end
