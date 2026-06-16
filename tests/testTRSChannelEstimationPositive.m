function ok = testTRSChannelEstimationPositive()
setup6GRSimToolkit("Verbose", false);
T = trsStrictAnchorResult().Result.ArtifactTables.trs_trials;
row = T(string(T.TrialType) == "positive_awgn", :);
assert(logical(row.ChannelEstimationAttempted(1)) && logical(row.TRSChannelEstimateAvailable(1)), ...
    "Positive TRS trial must expose attempted and available channel estimation.");
assert(double(row.NMSE_dB(1)) < -8, "TRS channel NMSE must meet strict high-SNR threshold.");
ok = true;
end
