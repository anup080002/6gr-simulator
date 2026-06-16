function testThermalNoiseAndNoiseFigure
T = channelRFStrictAnchorResult().Result.ThermalNoise;
assert(height(T) > 0, "Thermal-noise evidence must be exported.");
assert(all(T.ThermalNoiseApplied), "Thermal noise must be applied.");
assert(all(abs(T.NoisePowerErrorDb) <= 1), "Measured noise variance must match kTB/noise-figure calculation.");
end
