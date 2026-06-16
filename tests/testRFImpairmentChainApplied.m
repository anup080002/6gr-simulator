function testRFImpairmentChainApplied
T = channelRFStrictAnchorResult().Result.RFImpairmentChain;
assert(height(T) > 0, "RF impairment chain evidence must be exported.");
assert(all(T.WaveformChanged), "RF impairment chain must mutate waveform samples.");
assert(all(T.CFOEnabled & T.IQImbalanceEnabled & T.PAEnabled), ...
    "Strict mini RF chain must apply CFO, IQ imbalance, and PA nonlinearity.");
assert(all(isfinite(T.EVMMeasuredPercent) & T.EVMMeasuredPercent > 0), ...
    "RF EVM must be measured from before/after samples.");
end
