function ok = testCodexLLSRemediationHelpers()
%TESTCODEXLLSREMEDIATIONHELPERS Guard new LLS helper behavior.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

T = sixgr.phy.grid.nrNumerologyTable();
for mu = 0:4
    mask = T.mu == mu;
    assert(any(mask), "Numerology table missing mu=%d.", mu);
    assert(T.slots_per_frame(mask) == 10 * 2^mu, ...
        "Slots/frame for mu=%d must be 10*2^mu.", mu);
    assert(T.symbols_per_slot(mask) == 14, ...
        "Normal CP symbols/slot for mu=%d must be 14.", mu);
end

L60 = sixgr.channel.OxygenAbsorption.pathLoss_dB(60e9, 1000);
assert(L60 > 10 && L60 < 25, ...
    "Oxygen absorption at 60 GHz / 1 km must be 10-25 dB, got %.3f.", L60);
L4 = sixgr.channel.OxygenAbsorption.pathLoss_dB(4e9, 1000);
assert(L4 < 0.5, "Oxygen absorption at 4 GHz must be negligible.");

assert(sixgr.l2.mac.resolveHARQFeedbackK1(0, "DDDSU", 1) == 4, ...
    "K1 for DDDSU slot 0 must resolve to the next UL slot.");
assert(sixgr.l2.mac.resolveHARQFeedbackK1(3, "DDDSU", 1) >= 1, ...
    "K1 must remain positive for special/downlink-adjacent slots.");

short = sixgr.l2.mac.BSR_PHR.buildBSR(struct("LCG0", 1500), 10);
assert(string(short.Format) == "short" && ~short.Truncated, ...
    "One active LCG must use Short BSR.");
trunc = sixgr.l2.mac.BSR_PHR.buildBSR([100 200 0 0 0 0 0 0], 2);
assert(string(trunc.Format) == "short_truncated" && trunc.Truncated, ...
    "Multiple active LCGs with <3 bytes padding must use Short Truncated BSR.");
long = sixgr.l2.mac.BSR_PHR.buildBSR([100 200 0 0 0 0 0 0], 4);
assert(string(long.Format) == "long" && ~long.Truncated, ...
    "Multiple active LCGs with enough padding must use Long BSR.");

pdcpCfg = sixgr.util.structSet(struct(), "l2.pdcp.rohc.enable", true);
pdcp = sixgr.l2.pdcp.PDCP(pdcpCfg);
ipPacket = uint8((1:80).');
compressed = pdcp.compress(ipPacket);
restored = pdcp.decompress(compressed);
assert(numel(compressed) < numel(ipPacket), "ROHC hook must reduce packet length after context setup.");
assert(isequal(ipPacket, restored), "ROHC compress/decompress round-trip must restore the packet.");

rlc = sixgr.l2.rlc.RLC_AM(struct());
[pdus, metas] = rlc.txSegment(uint8(mod((0:9999).', 256)), 900);
assert(numel(pdus) > 1, "RLC AM txSegment must split a 10 KB SDU.");
siVals = double([metas.SI]);
assert(any(siVals == 1) && any(siVals == 2), ...
    "RLC AM segmentation must emit first and last segment indicators.");

rrc = sixgr.l3.rrc.RRC(sixgr.config.defaultConfig(), "UE");
[trig1, ev1] = rrc.checkMeasurementEventA3(-90, -84, 0, 1, 3);
[trig2, ev2] = rrc.checkMeasurementEventA3(-90, -84, 0, 1, 3);
[trig3, ev3] = rrc.checkMeasurementEventA3(-90, -84, 0, 1, 3);
assert(~trig1 && ~trig2 && trig3, "A3 event must respect TTT before triggering.");
assert(ev1.ConditionMet && ev2.ConditionMet && ev3.ConditionMet, ...
    "A3 entry condition must be true for all three samples.");

rateLow = sixgr.l2.mac.SchedulerPF.cqiToApproxThroughputBps(3, 10, 0.5e-3);
rateHigh = sixgr.l2.mac.SchedulerPF.cqiToApproxThroughputBps(13, 10, 0.5e-3);
assert(rateHigh > rateLow, "PF instantaneous rate must increase with CQI.");

clear pdcp rlc rrc
ok = true;
end
