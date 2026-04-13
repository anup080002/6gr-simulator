function ok = testTraceReplayTrafficMode()
%TESTTRACEREPLAYTRAFFICMODE Trace replay traffic must be deterministic and exact.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.traffic.model = "traceReplay";
cfg.traffic.trace.offeredBitsDL = [100 200; 300 400; 500 600];
cfg.traffic.trace.offeredBitsUL = [10 20; 30 40; 50 60];
cfg.traffic.trace.transport = "UDP";
cfg.traffic.trace.flowDirection = "BIDIR";
cfg.traffic.trace.packetDelayBudget_ms = 15;
cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);

t1 = sixgr.system.TrafficFactory.generate(cfg, 2, 3, 1e-3);
t2 = sixgr.system.TrafficFactory.generate(cfg, 2, 3, 1e-3);

assert(strcmpi(string(t1.Model), "traceReplay"), "Trace replay traffic should report model='traceReplay'.");
assert(logical(t1.Deterministic), "Trace replay traffic should mark itself deterministic.");
assert(~logical(t1.ProxyShapingUsed), "Trace replay traffic should not use proxy transport shaping.");
assert(isequal(double(t1.OfferedBitsDL), [100 200; 300 400; 500 600]), ...
    "Trace replay DL bits should match the configured trace exactly.");
assert(isequal(double(t1.OfferedBitsUL), [10 20; 30 40; 50 60]), ...
    "Trace replay UL bits should match the configured trace exactly.");
assert(isequal(double(t1.OfferedBits), double(t1.OfferedBitsDL + t1.OfferedBitsUL)), ...
    "Trace replay total bits should equal DL+UL.");
assert(isequal(double(t1.OfferedBitsDL), double(t2.OfferedBitsDL)) && ...
    isequal(double(t1.OfferedBitsUL), double(t2.OfferedBitsUL)), ...
    "Trace replay traffic should be repeatable across calls.");

ok = true;
end
