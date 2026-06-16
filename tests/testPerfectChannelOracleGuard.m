function testPerfectChannelOracleGuard
T = channelRFStrictAnchorResult().Result.OracleGuard;
assert(height(T) > 0, "Oracle guard evidence must be exported.");
assert(all(~T.Violation), "Perfect-channel/path-gain oracle fields must not be used for strict pass/fail.");
end
