function testChannelConfiguredVsAppliedGate
T = channelRFStrictAnchorResult().Result.ConfiguredVsApplied;
positive = T(T.ExpectedOk, :);
negative = T(~T.ExpectedOk, :);
assert(all(positive.StrictOk & positive.ConfiguredAppliedMatch & positive.FeatureApplied), ...
    "All positive configured-vs-applied rows must pass.");
assert(all(~negative.StrictOk & ~negative.ConfiguredAppliedMatch), ...
    "All negative configured-vs-applied rows must fail closed.");
end
