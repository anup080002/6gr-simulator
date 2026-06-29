function ok = testPAPRAndConditionNumberContracts()
%TESTPAPRANDCONDITIONNUMBERCONTRACTS Guard RF diagnostics contracts.

setup6GRSimToolkit("Verbose", false);

tx = struct();
tx.Waveform = [100; 100; 1; 1; 1; 1];
tx.OFDMInfo = struct("Nfft", 4, "CyclicPrefixLengths", 2);
[metrics, ~] = sixgr.link.deriveModulationTrackingMetrics(tx, struct(), struct(), "DL");
assert(isfinite(double(metrics.PAPR_dB)), "CP-excluded PAPR must be finite.");
assert(abs(double(metrics.PAPR_dB)) < 1e-9, ...
    "PAPR must exclude cyclic-prefix samples when OFDM metadata is present.");

[condRank1, statusRank1, rankRank1] = sixgr.mimo.channelConditionNumber((1:64).');
assert(isnan(double(condRank1)), "Rank-1 vector condition number must be NaN.");
assert(string(statusRank1) == "not_applicable_rank1", "Rank-1 condition status must be explicit.");
assert(double(rankRank1) == 1, "Rank estimate for a nonzero vector must be one.");

[condRank2, statusRank2, rankRank2] = sixgr.mimo.channelConditionNumber(diag([1 0.1]));
assert(abs(double(condRank2) - 20) < 1e-9, "2x2 condition number must match 20log10(s1/s2).");
assert(string(statusRank2) == "valid", "Well-conditioned rank-2 matrix must be valid.");
assert(double(rankRank2) == 2, "Rank estimate for diag([1 0.1]) must be two.");

[condBad, statusBad] = sixgr.mimo.channelConditionNumber([ones(4,1), ones(4,1) * 1e-12]);
assert(isnan(double(condBad)), "Rank-deficient condition number must be NaN.");
assert(any(string(statusBad) == ["not_applicable_rank_deficient","overflow_clipped"]), ...
    "Rank-deficient condition status must fail closed.");

rx = struct("ChannelEstimate", (1:64).', "NoiseVar", 1e-3);
ch = sixgr.link.analyzeWaveformChannelMetrics(rx, struct());
assert(isnan(double(ch.ConditionNumber_dB)), ...
    "Runtime channel metric path must not export zero or overflow for rank-1 channels.");

ok = true;
end
