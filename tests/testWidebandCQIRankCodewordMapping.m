function ok = testWidebandCQIRankCodewordMapping()
%TESTWIDEBANDCQIRANKCODEWORDMAPPING Guard TS 38.211 layer/codeword mapping.

% Ranks one through four use one codeword.  Ranks five through eight use
% two.  This test prevents per-layer CQI reduction from inventing a second
% codeword for ordinary rank-2/rank-4 operation.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "phy.csi.cqiMode", "threshold_table");

common = struct( ...
    "WidebandSINR_dB", 10, ...
    "SINRSource", "post_equalization_receiver_measurement", ...
    "SINRValueRole", "measured_data_channel_scheduling_input", ...
    "SINRValueStatus", "PASS");

rank2 = common;
rank2.RankIndicator = 2;
rank2.PostEqSINRPerLayer_dB = [12 2];
fb2 = sixgr.link.resolveWidebandCQI(rank2, cfg, "DL");
assert(isscalar(fb2.PerCodewordCQI) && isscalar(fb2.PerCodewordSINR_dB), ...
    "Rank-2 must reduce to exactly one codeword CQI/SINR.");

rank4 = common;
rank4.RankIndicator = 4;
rank4.PostEqSINRPerLayer_dB = [12 10 8 6];
fb4 = sixgr.link.resolveWidebandCQI(rank4, cfg, "DL");
assert(isscalar(fb4.PerCodewordCQI) && isscalar(fb4.PerCodewordSINR_dB), ...
    "Rank-4 must reduce to exactly one codeword CQI/SINR.");

rank5 = common;
rank5.RankIndicator = 5;
rank5.PostEqSINRPerLayer_dB = [12 10 8 6 4];
fb5 = sixgr.link.resolveWidebandCQI(rank5, cfg, "DL");
assert(numel(fb5.PerCodewordCQI) == 2 && numel(fb5.PerCodewordSINR_dB) == 2, ...
    "Rank-5 must reduce to two codeword CQI/SINR values.");

ok = true;
end
