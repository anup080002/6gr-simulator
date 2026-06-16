function testChannelDownstreamReferences
T = channelRFStrictAnchorResult().Result.DownstreamReferences;
assert(height(T) > 0, "Downstream Channel/RF reference contract must be exported.");
assert(all(T.ReferenceValid), "All exported downstream references must be valid.");
assert(all(strlength(string(T.ChannelRealizationId)) > 0), "ChannelRealizationId is required.");
assert(all(strlength(string(T.RFImpairmentChainId)) > 0), "RFImpairmentChainId is required.");
end
