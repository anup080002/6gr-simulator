function ok = testSRSChannelEstimationPositive()
setup6GRSimToolkit("Verbose", false);
R = srsStrictAnchorResult().Result;
T = R.ArtifactTables.srs_trials;
row = T(string(T.TrialType) == "positive_awgn", :);
assert(logical(row.ChannelEstimateAttempted) && logical(row.SRSChannelEstimateAvailable), ...
    "Positive SRS trial must have available receiver-side channel estimate.");
assert(isfinite(double(row.NMSE_dB)) && double(row.NMSE_dB) <= -8, "SRS NMSE must satisfy configured threshold.");

ch = R.ArtifactTables.srs_channel_estimation;
ch = ch(string(ch.TrialType) == "positive_awgn", :);
assert(height(ch) == 1 && logical(ch.PerREEstimateAvailable) && ...
    logical(ch.PerPRBEstimateAvailable) && logical(ch.PerPortEstimateAvailable), ...
    "Positive SRS channel estimation must expose measured per-RE/per-PRB/per-port evidence.");
assert(double(ch.NumPRBEstimates) > 1 && double(ch.NumPortEstimates) >= 1, ...
    "SRS estimator must not collapse all pilots into a single wideband scalar.");
assert(~contains(lower(string(ch.Estimator)), "oracle") && ~contains(lower(string(ch.Estimator)), "proxy"), ...
    "SRS estimator identity must not claim oracle or proxy evidence.");

prb = R.ArtifactTables.srs_channel_estimation_per_prb;
prb = prb(string(prb.TrialType) == "positive_awgn", :);
assert(height(prb) == double(ch.NumPRBEstimates) && all(logical(prb.EstimateAvailable)), ...
    "SRS per-PRB channel-estimation table must contain one available measured row per estimated PRB/port.");

port = R.ArtifactTables.srs_channel_estimation_per_port;
port = port(string(port.TrialType) == "positive_awgn", :);
assert(height(port) == double(ch.NumPortEstimates) && all(logical(port.EstimateAvailable)), ...
    "SRS per-port channel-estimation table must contain available measured rows.");
ok = true;
end
