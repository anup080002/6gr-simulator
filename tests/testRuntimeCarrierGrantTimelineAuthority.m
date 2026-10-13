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

% CSI-RS occasions in successive H4 reporting periods cross a radio frame.
% Never reuse frame 1 merely because the component started in that frame.
for absoluteSlot = [6 20 21 26 39 40 41]
    [timed, clock] = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg, absoluteSlot);
    frame = floor((absoluteSlot-1)/20)+1;
    assert(clock.FrameIndexOneBased==frame && clock.CarrierSlotIndex0==mod(absoluteSlot-1,20));
    same = sixgr.phy.grid.applyRuntimeCarrierTimeline(timed, absoluteSlot, frame);
    assert(isequaln(timed,same));
end
threw = false;
try
    sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,26,1);
catch ME
    threw = strcmp(ME.identifier,"sixgr:grid:RuntimeFrameSlotMismatch");
end
assert(threw,'An inconsistent explicit frame must remain a production error.');

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
