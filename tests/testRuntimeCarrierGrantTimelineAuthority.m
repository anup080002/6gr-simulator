function ok = testRuntimeCarrierGrantTimelineAuthority()
%TESTRUNTIMECARRIERGRANTTIMELINEAUTHORITY Frozen grants cannot reset time.

setup6GRSimToolkit("Verbose", false);
cfg = struct();
cfg.phy.carrier = struct( ...
    "NCellID", 17, ...
    "SubcarrierSpacing", 30, ...
    "NSizeGrid", 11, ...
    "NStartGrid", 0, ...
    "CyclicPrefix", "normal");
[frozenCarrier, ~] = sixgr.phy.grid.makeCarrier(cfg, "Slot", 0, "Frame", 0);

[cfg, timeline] = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg, 28);
[runtimeCarrier, evidence] = sixgr.phy.grid.materializeRuntimeCarrier( ...
    cfg, frozenCarrier, "DL");
assert(double(runtimeCarrier.NSlot) == 7 && double(runtimeCarrier.NFrame) == 1, ...
    "Absolute one-based slot 28 at 30 kHz must resolve to frame 1, slot 7.");
assert(double(evidence.AbsoluteSlotIndex0) == 27 && ...
    logical(evidence.FrozenCarrierGeometryValidated) && ...
    double(timeline.CarrierSlotIndex0) == 7, ...
    "Runtime carrier evidence must preserve the exact timeline lineage.");
assert(double(frozenCarrier.NSlot) == 0 && double(frozenCarrier.NFrame) == 0, ...
    "Runtime materialization must not mutate the frozen carrier object.");

badFrozen = nrCarrierConfig;
badFrozen.NCellID = frozenCarrier.NCellID;
badFrozen.SubcarrierSpacing = frozenCarrier.SubcarrierSpacing;
badFrozen.NSizeGrid = frozenCarrier.NSizeGrid + 1;
badFrozen.NStartGrid = frozenCarrier.NStartGrid;
badFrozen.CyclicPrefix = frozenCarrier.CyclicPrefix;
threw = false;
try
    sixgr.phy.grid.materializeRuntimeCarrier(cfg, badFrozen, "UL");
catch ME
    threw = strcmp(ME.identifier, "sixgr:grid:FrozenCarrierGeometryMismatch");
end
assert(threw, ...
    "A frozen/runtime carrier geometry mismatch must fail with a typed error.");

ok = true;
end
