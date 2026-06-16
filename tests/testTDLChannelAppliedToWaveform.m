function testTDLChannelAppliedToWaveform
T = channelRFStrictAnchorResult().Result.ChannelRealizations;
row = T(string(T.ChannelModelType) == "TDL", :);
assert(height(row) == 1, "TDL realization row is required.");
assert(row.StrictOk && row.WaveformChanged && row.PathGainsExported, ...
    "TDL channel must be applied to waveform samples with path-gain evidence.");
end
