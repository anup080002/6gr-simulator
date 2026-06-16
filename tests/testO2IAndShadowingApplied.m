function testO2IAndShadowingApplied
T = channelRFStrictAnchorResult().Result.LargeScaleParameters;
assert(any(T.O2IState & T.O2IPenetrationLossDbApplied > 0), ...
    "Configured O2I link must have nonzero applied penetration loss.");
assert(all(isfinite(T.ShadowFadingDbApplied)), "Shadow-fading evidence must be finite.");
end
