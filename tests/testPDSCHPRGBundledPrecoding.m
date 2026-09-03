function ok = testPDSCHPRGBundledPrecoding()
%TESTPDSCHPRGBUNDLEDPRECODING Verify truth Tx/Rx PRG matrix ownership.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
if exist("nrPDSCHPrecode", "file") ~= 2 || exist("nrPRGInfo", "file") ~= 2
    warning("testPDSCHPRGBundledPrecoding:Missing5G", ...
        "Skipping because PRG precoding APIs are unavailable.");
    ok = true;
    return;
end

cfg = localConfig();
carrier = nrCarrierConfig;
carrier.NCellID = 0;
carrier.NSizeGrid = 12;
carrier.NStartGrid = 0;
carrier.SubcarrierSpacing = 30;
carrier.CyclicPrefix = "normal";

pdsch = nrPDSCHConfig;
pdsch.NID = 0;
pdsch.RNTI = 1;
pdsch.PRBSet = 0:(carrier.NSizeGrid - 1);
pdsch.SymbolAllocation = [2 12];
pdsch.MappingType = "A";
pdsch.Modulation = "QPSK";
pdsch.NumLayers = 1;
pdsch.DMRS.DMRSConfigurationType = 1;
pdsch.DMRS.DMRSTypeAPosition = 2;
pdsch.DMRS.DMRSAdditionalPosition = 1;
pdsch.DMRS.DMRSLength = 1;
pdsch.DMRS.NumCDMGroupsWithoutData = 1;

prgInfo = nrPRGInfo(carrier, 2);
W = complex(zeros(2, 1, prgInfo.NPRG));
W(1, 1, 1:2:end) = 1;
W(2, 1, 2:2:end) = 1i;

rng(38102, "twister");
[tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfg, ...
    "Carrier", carrier, ...
    "PDSCH", pdsch, ...
    "TargetCodeRate", 0.30, ...
    "RV", 0, ...
    "NumTxAnt", 2, ...
    "PrecodingMatrix", W, ...
    "CompactOutput", false);

assert(string(tx.PrecodeInfo.Mode) == "explicit-prg-bundled", ...
    "Paged PDSCH precoding must be identified as PRG-bundled truth.");
assert(~logical(tx.PrecodeInfo.WidebandOnly) && ...
        tx.PrecodeInfo.NumPRG == prgInfo.NPRG, ...
    "PDSCH PRG provenance must report every carrier PRG.");
assert(isequal(size(tx.PrecodeInfo.MatrixNR), [1 2 prgInfo.NPRG]), ...
    "PDSCH MatrixNR must retain the Nlayers-by-Nports-by-NPRG contract.");
assert(logical(tx.PrecodeInfo.AllPRGTotalPowerPreserving), ...
    "Every PRG precoder page must preserve the configured layer power.");
assert(size(tx.Waveform, 2) == 2, ...
    "PRG-bundled rank-1 PDSCH must materialize both antenna columns.");
assert(string(txInfo.Precoding.Mode) == "explicit-prg-bundled", ...
    "PDSCH Tx info must retain PRG-bundled precoding provenance.");

% Annex-B.1-style full-rank static channel. The receiver estimates the
% effective layer channel from the correspondingly precoded DM-RS.
H = [1, 1i; 1, -1i];
rxWaveform = tx.Waveform * H.';
[rx, ~] = sixgr.phy.dl.PDSCH_Rx(rxWaveform, cfg, ...
    "Carrier", carrier, ...
    "PDSCH", pdsch, ...
    "PDSCHIndices", tx.PDSCHIndices, ...
    "TransportBlockSize", tx.TransportBlockSize, ...
    "TargetCodeRate", tx.TargetCodeRate, ...
    "RV", tx.RV, ...
    "CodingPlan", tx.CodingPlans, ...
    "NoiseVar", 1e-9, ...
    "NoiseVarDomain", "grid", ...
    "CodingLayout", tx.CodingLayout, ...
    "PrecodingMatrix", W, ...
    "CompactOutput", true, ...
    "SkipTimingEstimate", true, ...
    "FastAWGNPath", false);

assert(logical(rx.Ok) && ~logical(rx.CRCError), ...
    "PRG-bundled PDSCH must decode through the measured effective channel.");
assert(all(int8(rx.TransportBlock(:)) == int8(tx.TransportBlock(:))), ...
    "PRG-bundled PDSCH Rx must recover the transmitted transport block.");

fprintf("PDSCHPRGBundledPrecoding: %d PRGs decoded through a 2x2 static channel.\n", ...
    prgInfo.NPRG);
ok = true;
end

function cfg = localConfig()
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = true;
cfg.run.useMex = false;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.30;
cfg.phy.pdsch.mcsTable = "calibration_explicit";
cfg.phy.pdsch.mcsIndex = 0;
cfg.channel.nTxAnt = 2;
cfg.channel.nRxAnt = 2;
cfg.phy.nTxAnt = 2;
cfg.phy.nRxAnt = 2;
cfg.phy.pdsch.numPorts = 2;
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.csirs.enable = false;
cfg.phy.channelEstimation.method = "LS";
cfg.phy.pdsch.equalizer = "MMSE";
cfg.phy.impairments.cfoEstimationMethod = "disabled";
end
