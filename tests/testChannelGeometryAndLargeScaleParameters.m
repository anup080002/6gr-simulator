function testChannelGeometryAndLargeScaleParameters
res = channelRFStrictAnchorResult().Result;
assert(height(res.Geometry.LinkTable) >= 2, "Strict Channel/RF geometry must include link rows.");
T = res.LargeScaleParameters;
assert(height(T) >= 2, "Large-scale evidence rows must be exported.");
assert(all(T.AppliedOk), "Pathloss/shadowing/O2I power deltas must be applied within tolerance.");
assert(any(T.O2IPenetrationLossDbApplied > 0), "At least one strict mini link must apply O2I loss.");
end
