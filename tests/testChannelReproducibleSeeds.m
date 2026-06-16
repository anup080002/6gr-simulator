function testChannelReproducibleSeeds
a = channelRFStrictAnchorResult("Refresh", true).Result;
b = channelRFStrictAnchorResult("Refresh", true).Result;
assert(isequal(string(a.ChannelRealizations.ChannelRealizationId), string(b.ChannelRealizations.ChannelRealizationId)), ...
    "Same strict Channel/RF config and seed must reproduce realization identifiers.");
assert(isequal(string(a.RFImpairmentChain.WaveformAfterHash), string(b.RFImpairmentChain.WaveformAfterHash)), ...
    "Same strict Channel/RF config and seed must reproduce RF waveform hashes.");
end
