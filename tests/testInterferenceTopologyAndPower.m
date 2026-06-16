function testInterferenceTopologyAndPower
T = channelRFStrictAnchorResult().Result.InterferenceTopology;
assert(height(T) > 0, "Interference topology must be exported.");
assert(all(T.InterferenceApplied), "Interference must be applied to waveform samples.");
assert(all(T.ReceivedInterferencePower > 0), "Received interference power must be positive.");
assert(all(isfinite(T.ComputedSINRDb)), "SINR reconstruction must be finite.");
end
