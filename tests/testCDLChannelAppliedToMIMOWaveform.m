function testCDLChannelAppliedToMIMOWaveform
T = channelRFStrictAnchorResult().Result.ChannelRealizations;
row = T(string(T.ChannelModelType) == "CDL", :);
assert(height(row) == 1, "CDL realization row is required.");
assert(row.StrictOk && row.WaveformChanged && row.PathGainsExported, ...
    "CDL channel must be applied to waveform samples with path-gain evidence.");
assert(row.NumTxAntennas >= 2 && row.NumRxAntennas >= 2, ...
    "CDL strict mini evidence must exercise a multi-antenna configuration.");
end
