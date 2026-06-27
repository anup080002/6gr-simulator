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

carrierL = nrCarrierConfig;
carrierL.NCellID = 11;
carrierL.NSizeGrid = 1;
carrierL.SubcarrierSpacing = 30;
carrierL.CyclicPrefix = "normal";
carrierL.NSlot = 0;
KL = 12 * double(carrierL.NSizeGrid);
LL = double(carrierL.SymbolsPerSlot);
pilotSymbolL = 3;
refIndL = sub2ind([KL LL 1], (1:KL).', repmat(pilotSymbolL, KL, 1), ones(KL, 1));
refSymL = ones(KL, 1);
hPilot = 0.6 - 0.2i;
rxGridL = complex(zeros(KL, LL, 1));
rxGridL(:, pilotSymbolL, 1) = hPilot;
noiseVarL = 0.25;
fullCov = eye(KL * LL);
[HLMMSE, nVarL, infoLMMSE] = sixgr.phy.rx.channelEstimate(carrierL, rxGridL, refIndL, refSymL, ...
    "Method", "lmmse", ...
    "ChannelCovariance", fullCov, ...
    "NoiseVariance", noiseVarL, ...
    "ContextLabel", "testChannelEstimateOraclePath_lmmse");
expectedPilot = hPilot ./ (1 + noiseVarL);
assert(string(infoLMMSE.EngineUsed) == "full_covariance_lmmse" && logical(infoLMMSE.FullCovarianceLMMSE), ...
    "Method='lmmse' must use the covariance LMMSE estimator, not nrChannelEstimate smoothing.");
assert(abs(double(nVarL) - noiseVarL) < 1e-15, ...
    "LMMSE estimator must preserve the explicit pilot noise variance.");
assert(max(abs(HLMMSE(:, pilotSymbolL, 1, 1) - expectedPilot)) < 1e-12, ...
    "Full-covariance LMMSE pilot estimates must match Rhp/(Rpp+nVarI)*hLS.");
assert(max(abs(HLMMSE(:, setdiff(1:LL, pilotSymbolL), 1, 1)), [], "all") == 0, ...
    "Identity covariance must not invent non-pilot channel values.");
assert(~logical(infoLMMSE.EstimatorUsesTrueChannel) && string(infoLMMSE.UsedOracleFields) == "", ...
    "Practical LMMSE must not consume true-channel oracle fields.");

cfgCSI = struct();
cfgCSI.phy.csirs.enable = true;
cfgCSI.phy.csirs.nPorts = 1;
cfgCSI.phy.csirs.rowNumber = 2;
cfgCSI.phy.csirs.symbolLocations = 6;
cfgCSI.phy.csirs.subcarrierLocations = 0;
cfgCSI.phy.csirs.numRB = carrier.NSizeGrid;
cfgCSI.phy.csirs.rbOffset = 0;
cfgCSI.phy.csirs.density = "one";
[csirsInd, csirsSym, csirsInfo] = sixgr.phy.refsig.csirs(carrier, cfgCSI);
assert(logical(csirsInfo.Enabled) && ~isempty(csirsInd) && ~isempty(csirsSym), ...
    "CSI-RS oracle campaign anchor must generate real CSI-RS indices and symbols.");
Hcsi = complex(zeros(K, L, 1, 1));
Hcsi(:, :, 1, 1) = 0.35 + 0.45i;
rxGridCSI = complex(zeros(K, L, 1));
for ii = 1:numel(csirsInd)
    [kk, ll, pp] = ind2sub([K L 1], double(csirsInd(ii))); %#ok<ASGLU>
    rxGridCSI(kk, ll, 1) = Hcsi(kk, ll, 1, pp) .* csirsSym(ii);
end
[~, ~, csiInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGridCSI, csirsInd, csirsSym, ...
    "CDMLengths", [1 1], ...
    "ExpectedTxPorts", 1, ...
    "TrueChannel", Hcsi, ...
    "OracleTestMode", true, ...
    "EffectiveChannelConvention", "csirs_effective_channel_grid_validation_only", ...
    "ContextLabel", "testChannelEstimateOraclePath_csirs");
assert(logical(csiInfo.OracleAvailable) && isfinite(double(csiInfo.OracleNMSE_dB)) && ...
        double(csiInfo.OracleNMSE_dB) < -120, ...
    "CSI-RS validation must expose true-channel oracle NMSE through the common estimator metadata path.");
assert(string(csiInfo.UsedOracleFields) == "", ...
    "CSI-RS practical estimator must not consume true-channel oracle fields.");

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
