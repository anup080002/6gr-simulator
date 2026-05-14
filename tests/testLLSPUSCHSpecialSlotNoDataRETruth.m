function ok = testLLSPUSCHSpecialSlotNoDataRETruth()
%TESTLLSPUSCHSPECIALSLOTNODATARETRUTH Guard zero-data-RE UL grants truthfully.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg = sixgr.util.structSet(cfg, "phy.carrier.NSizeGrid", 24);
cfg = sixgr.util.structSet(cfg, "phy.pusch.enable", true);
cfg = sixgr.util.structSet(cfg, "phy.pusch.modulation", "QPSK");
cfg = sixgr.util.structSet(cfg, "phy.pusch.nLayers", 1);
cfg = sixgr.util.structSet(cfg, "phy.pusch.numLayers", 1);
cfg = sixgr.util.structSet(cfg, "phy.pusch.codeRate", 0.3);
cfg = sixgr.util.structSet(cfg, "phy.pusch.prbSet", 0:7);
cfg = sixgr.util.structSet(cfg, "phy.pusch.symbolAllocation", [13 1]);
cfg = sixgr.util.structSet(cfg, "run.strictMode", true);

sched = sixgr.l2.mac.SchedulerRR(cfg, "Direction", "UL");
[tbsBits, ~, nrePerPRB] = sched.estimateTBS("QPSK", 1, 8, [13 1], 0.3, "ForceExact", true);
assert((isfinite(double(tbsBits)) && double(tbsBits) == 0) || ~(isfinite(double(nrePerPRB)) && double(nrePerPRB) > 0), ...
    "Exact UL grant sizing must not produce a positive TBS for a one-symbol UL tail with no data RE.");

caught = [];
try
    sixgr.phy.ul.PUSCH_Tx(cfg);
catch ME
    caught = ME;
end
assert(~isempty(caught), ...
    "PUSCH_Tx must reject a zero-data-RE UL allocation instead of reaching rate matching with G<=0.");
assert(contains(string(caught.identifier), "PUSCHNoDataRE"), ...
    "PUSCH_Tx must fail with the explicit no-data-RE truth identifier.");

ok = true;
end
