function ok = testSRSChannelEstimationPositive()
setup6GRSimToolkit("Verbose", false);
T = srsStrictAnchorResult().Result.ArtifactTables.srs_trials;
row = T(string(T.TrialType) == "positive_awgn", :);
assert(logical(row.ChannelEstimateAttempted) && logical(row.SRSChannelEstimateAvailable), ...
    "Positive SRS trial must have available receiver-side channel estimate.");
assert(isfinite(double(row.NMSE_dB)) && double(row.NMSE_dB) <= -8, "SRS NMSE must satisfy configured threshold.");
ok = true;
end
