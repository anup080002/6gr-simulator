function testDopplerMobilityApplied
T = channelRFStrictAnchorResult().Result.ChannelRealizations;
fading = T(ismember(string(T.ChannelModelType), ["TDL","CDL"]), :);
assert(all(fading.MaxDopplerHz > 0), "Fading channels must export nonzero applied Doppler.");
assert(all(fading.WaveformChanged), "Doppler/fading channels must alter waveform samples.");
end
