function ok = testChannelEstimateOraclePath()
setup6GRSimToolkit("Verbose", false);

carrier = nrCarrierConfig;
carrier.NCellID = 17;
carrier.NSizeGrid = 6;
carrier.SubcarrierSpacing = 30;
carrier.CyclicPrefix = "normal";
carrier.NSlot = 0;

K = 12 * double(carrier.NSizeGrid);
L = double(carrier.SymbolsPerSlot);
R = 2;
P = 1;
pilotSymbol = 4;
pilotK = (1:K).';
refInd = sub2ind([K L P], pilotK, repmat(pilotSymbol, K, 1), ones(K, 1));
refSym = ones(K, 1);

Htrue = complex(zeros(K, L, R, P));
Htrue(:, :, 1, 1) = 0.75 + 0.25i;
Htrue(:, :, 2, 1) = -0.20 + 0.90i;
rxGrid = complex(zeros(K, L, R));
for rr = 1:R
    rxGrid(pilotK, pilotSymbol, rr) = Htrue(pilotK, pilotSymbol, rr, 1) .* refSym;
end

[Hest, nVar, info] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, refInd, refSym, ...
    "CDMLengths", [1 1], ...
    "TrueChannel", Htrue, ...
    "OracleTestMode", true, ...
    "EffectiveChannelConvention", "unit_test_effective_channel_grid", ...
    "ContextLabel", "testChannelEstimateOraclePath");

assert(~isempty(Hest) && isfinite(double(nVar)), "Practical channel estimate must return Hest and nVar.");
assert(string(info.EngineUsed) == "nrChannelEstimate", "Default estimator must remain practical nrChannelEstimate.");
assert(logical(info.OracleTestMode) && logical(info.OracleAvailable), ...
    "Oracle diagnostics must be available only when explicitly requested by the test harness.");
assert(string(info.UsedOracleFields) == "", ...
    "Practical runtime estimator must not consume TrueChannel as an estimator input.");
assert(double(info.PilotRECount) == K && nnz(info.PilotMask) == K, ...
    "Estimator diagnostics must expose the pilot RE mask and count.");
assert(isfinite(double(info.PilotResidualNMSE_dB)) && double(info.PilotResidualNMSE_dB) < -120, ...
    "Flat noiseless pilot LS residual must be numerically zero.");
assert(isfinite(double(info.OracleNMSE_dB)) && double(info.OracleNMSE_dB) < -120, ...
    "True-channel oracle NMSE must be zero in the flat noiseless anchor.");
assert(string(info.EffectiveChannelConvention) == "unit_test_effective_channel_grid", ...
    "Effective-channel convention must be preserved in estimator metadata.");

[Hideal, nVarIdeal, idealInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, refInd, refSym, ...
    "Method", "ideal", ...
    "TrueChannel", Htrue, ...
    "OracleTestMode", true, ...
    "Config", struct("channel", struct("snr_dB", 30)), ...
    "ContextLabel", "testChannelEstimateOraclePath");
assert(isequal(size(Hideal), size(Htrue)) && max(abs(Hideal(:) - Htrue(:))) == 0, ...
    "Ideal test oracle must return the supplied true effective channel exactly.");
assert(abs(double(nVarIdeal) - 1e-3) < 1e-15, "Ideal test oracle nVar must follow explicit config.");
assert(string(idealInfo.EngineUsed) == "ideal_true_channel_test_oracle" && ...
    string(idealInfo.UsedOracleFields) == "TrueChannel", ...
    "Ideal channel path must be labeled as a test-only true-channel oracle.");

threw = false;
try
    sixgr.phy.rx.channelEstimate(carrier, rxGrid, refInd, refSym, ...
        "Method", "ideal", ...
        "TrueChannel", Htrue, ...
        "ContextLabel", "testChannelEstimateOraclePath");
catch ME
    threw = strcmp(string(ME.identifier), "sixgr:phy:channelEstimate:OracleTestModeRequired");
end
assert(threw, "Method='ideal' must fail unless OracleTestMode=true.");

ok = true;
end
