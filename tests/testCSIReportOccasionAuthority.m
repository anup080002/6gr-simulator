function ok = testCSIReportOccasionAuthority()
%TESTCSIREPORTOCCASIONAUTHORITY Periodic CSI UCI follows YAML timing.

setup6GRSimToolkit("Verbose", false);
cfg = struct();
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCSI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportTrigger", "periodic");
cfg = sixgr.util.structSet(cfg, "phy.csi.reportPeriodicitySlots", 5);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportOffsetSlots", 1);

actual = arrayfun(@(slot) ...
    sixgr.truth.CoupledTruthRuntime.isCSIReportOccasionRuntime( ...
    cfg, slot, "DL"), 1:15);
expected = false(1, 15);
expected([2 7 12]) = true;
assert(isequal(actual, expected), ...
    "Periodic DL CSI reports must occur only at the YAML-owned slot offset.");
assert(sixgr.truth.CoupledTruthRuntime. ...
    isCSIReportOccasionRuntime(cfg, 4, "UL"), ...
    "Decoded UL receiver CSI remains an internal per-PUSCH gNB measurement.");

cfg = sixgr.util.structSet(cfg, "phy.csi.reportCSI", false);
assert(~sixgr.truth.CoupledTruthRuntime. ...
    isCSIReportOccasionRuntime(cfg, 2, "DL"), ...
    "Disabled DL CSI reporting must not emit a UCI report.");

ok = true;
fprintf("testCSIReportOccasionAuthority: PASS\n");
end
