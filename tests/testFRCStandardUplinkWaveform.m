function ok = testFRCStandardUplinkWaveform()
%TESTFRCSTANDARDUPLINKWAVEFORM Decode from continuous TS 38.104 FRC slots.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

qpsk = localRun("ul_g_fr1_a3a_1_awgn", "awgn_1x2", -5.1);
assert(qpsk.StandardExecution.Exact && qpsk.DataChannelExecution.Exact);
detail = qpsk.PointDetails{1};
localAssertWaveform(detail, 0, 0, 1, [300 14], 7680);
assert(detail.FirstTransmission.StandardUplinkWaveform.Materialized);
assert(~detail.TruthUnavailableRescueUsed && ...
    ~detail.ProxyUsed && ~detail.FallbackUsed);

qam64 = localRun("ul_g_fr1_a13_1_atg_awgn", ...
    "atg_awgn_200hz_1x2", 19.1);
assert(qam64.StandardExecution.Exact && qam64.DataChannelExecution.Exact);
detail = qam64.PointDetails{1};
localAssertWaveform(detail, 0:3, [0 2 3 1], 4, [300 56], 30720);
assert(detail.Propagation.StandardUplinkWaveform.SampleRate_Hz == 7.68e6);
% A one-TB development sample must not become qualification evidence.
assert(~qam64.NormativePass && ~qam64.StatisticallyQualified);

ok = true;
end

function result = localRun(entryId, conditionId, snr)
result = sixgr.conformance.runFRCPoint(entryId, conditionId, ...
    "SNRGrid_dB", snr, "ExecutionProfile", "smoke", ...
    "MinTransportBlocks", 1, "MaxTransportBlocks", 1, ...
    "BatchSize", 1, "EvaluateSymmetricRegression", false, ...
    "RequireExactStandardExecution", true, ...
    "RequireExactDataChannelExecution", true, ...
    "PrintTable", false, "Verbose", false);
assert(height(result.Sweep) == 1 && result.Sweep.TransportBlocks == 1);
end

function localAssertWaveform(detail, slots, rv, spanSlots, gridSize, samples)
waveform = detail.Propagation.StandardUplinkWaveform;
assert(waveform.Materialized && waveform.NoProxyOrFallbackUsed);
assert(isequal(double(waveform.TargetSlotWithinWaveform(:).'), double(slots)));
assert(isequal(double(waveform.RVSequence(:).'), double(rv)));
assert(isequal(double(waveform.FrameGridSize(1:2)), double(gridSize)));
assert(waveform.WaveformSize(1) == samples);
assert(strlength(waveform.FrameGridSHA256) == 64 && ...
    strlength(waveform.FrameWaveformSHA256) == 64);
assert(numel(waveform.TargetSlotWithinWaveform) == spanSlots);
end
