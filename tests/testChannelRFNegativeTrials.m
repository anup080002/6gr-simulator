function testChannelRFNegativeTrials
T = channelRFStrictAnchorResult().Result.NegativeTrials;
assert(height(T) >= 5, "Strict Channel/RF negative trials must be exported.");
assert(all(~T.StrictOk), "Negative Channel/RF trials must fail strict success.");
assert(all(T.NegativeExpectedOk), "Negative Channel/RF trials must fail for expected reasons.");
end
