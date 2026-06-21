function ok = testCSIWeightLLRScaleGuard()
%TESTCSIWEIGHTLLRSCALEGUARD Prevent path-gain CSI from erasing soft bits.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

llr = ones(80, 1);
pathGainCSI = ones(10, 1) * 1e-12;
[guardedLLR, guardedInfo] = sixgr.phy.rx.applyCSIToCodewordLLR( ...
    llr, pathGainCSI, "256QAM", "PostEqSINR_dB", 18);

assert(logical(guardedInfo.Applied), "CSI weighting must still be applied.");
assert(string(guardedInfo.Status) == "applied_normalized_path_gain_scaled_csi", ...
    "Path-gain scaled CSI must be normalized, got '%s'.", guardedInfo.Status);
assert(mean(abs(guardedLLR), "omitnan") > 0.5, ...
    "Usable high-SINR LLRs must not be collapsed by tiny path-gain CSI.");

[lowSINRLLR, lowSINRInfo] = sixgr.phy.rx.applyCSIToCodewordLLR( ...
    llr, pathGainCSI, "256QAM", "PostEqSINR_dB", -8);
assert(string(lowSINRInfo.Status) == "applied", ...
    "Low-SINR tiny CSI should not be normalized into confident LLRs.");
assert(mean(abs(lowSINRLLR), "omitnan") < 1e-6, ...
    "Low-SINR tiny CSI must remain weak evidence.");

boundedCSI = ones(10, 1) * 0.5;
[boundedLLR, boundedInfo] = sixgr.phy.rx.applyCSIToCodewordLLR( ...
    ones(40, 1), boundedCSI, "16QAM", "PostEqSINR_dB", 10);
assert(string(boundedInfo.Status) == "applied", ...
    "Bounded MMSE CSI should be applied without normalization.");
assert(abs(mean(abs(boundedLLR), "omitnan") - 0.5) < 1e-12, ...
    "Bounded CSI weights must be preserved exactly.");

sinrLikeCSI = ones(10, 1) * 10;
[sinrLLR, sinrInfo] = sixgr.phy.rx.applyCSIToCodewordLLR( ...
    ones(20, 1), sinrLikeCSI, "QPSK", "PostEqSINR_dB", 10);
assert(string(sinrInfo.InputKind) == "sinr_like_converted_to_bounded_reliability", ...
    "SINR-like CSI must be converted to bounded reliability weights.");
assert(abs(mean(abs(sinrLLR), "omitnan") - (10 / 11)) < 1e-12, ...
    "SINR-like CSI conversion must use gamma/(1+gamma).");

ok = true;
end
