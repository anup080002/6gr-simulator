function ok = testPDSCHLLRScalingConvention()
%TESTPDSCHLLRSCALINGCONVENTION Guard PDSCH RX against double LLR weighting.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
if ~localHaveRequired5G()
    warning("testPDSCHLLRScalingConvention:Missing5G", ...
        "Skipping PDSCH LLR scaling test because required 5G Toolbox APIs are unavailable.");
    ok = true;
    return;
end

rng(1818, "twister");
localAssertPDSCHRxUsesOneDemapperConvention();
localAssertToolboxLLRSignsAndNoiseScaling();
localAssertCodingLineageAndPerturbationSensitivity();

fprintf("PDSCHLLRScalingConvention: direct-demapper match, G lineage and perturbation sensitivity verified.\n");
ok = true;
end

function localAssertPDSCHRxUsesOneDemapperConvention()
cfg = localPDSCHCfg();
[tx, ~] = sixgr.phy.dl.PDSCH_Tx(cfg);

declaredGridNoiseVar = 0.25;
rx = sixgr.phy.dl.PDSCH_Rx(tx.Waveform, cfg, ...
    "Carrier", tx.Carrier, ...
    "PDSCH", tx.PDSCH, ...
    "PDSCHIndices", tx.PDSCHIndices, ...
    "TransportBlockSize", tx.TransportBlockSize, ...
    "TargetCodeRate", tx.TargetCodeRate, ...
    "RV", tx.RV, ...
    "NoiseVar", declaredGridNoiseVar, ...
    "NoiseVarDomain", "grid", ...
    "CodingLayout", tx.CodingLayout);

directLLR = nrPDSCHDecode(rx.Carrier, rx.PDSCH, rx.EqualizedSymbols, rx.NoiseVar);
directCell = localNormalizeLLRCell(directLLR);
assert(numel(directCell) == numel(rx.CodewordLLRCell), ...
    "Direct nrPDSCHDecode codeword count must match receiver output.");
for c = 1:numel(directCell)
    ref = double(directCell{c}(:));
    got = double(rx.CodewordLLRCell{c}(:));
    tol = 1e-10 * max(1, max(abs(ref), [], "omitnan"));
    assert(numel(got) == numel(ref), ...
        "Receiver codeword %d LLR count must match direct nrPDSCHDecode.", c);
    assert(max(abs(got - ref), [], "omitnan") <= tol, ...
        "Receiver codeword %d LLRs must equal direct nrPDSCHDecode without second CSI weighting.", c);
end

csiMedian = median(double(rx.CSI(:)), "omitnan");
assert(isfinite(csiMedian) && abs(csiMedian - 1) > 1e-3, ...
    "Test must exercise a non-unity CSI reliability path; got median CSI %.6g.", csiMedian);
assert(~logical(rx.LLRCSIWeightApplied), ...
    "PDSCH RX must not apply CSI weighting after post-equalization variance demapping.");
assert(string(rx.LLRScalingConvention) == "post_equalization_variance_only", ...
    "PDSCH RX must declare the post-equalization variance-only LLR convention.");
assert(logical(rx.LLRDoubleWeightingGuard), ...
    "PDSCH RX must expose the double-weighting guard.");
assert(double(rx.DemapperLLRCount) == double(tx.RateMatchedBitCount), ...
    "PDSCH demapper must produce exactly G codeword LLRs.");
end

function localAssertToolboxLLRSignsAndNoiseScaling()
mods = ["QPSK", "16QAM", "64QAM", "256QAM"];
for m = 1:numel(mods)
    carrier = nrCarrierConfig;
    carrier.NSizeGrid = 6;
    carrier.SubcarrierSpacing = 30;

    pdsch = nrPDSCHConfig;
    pdsch.PRBSet = 0:5;
    pdsch.SymbolAllocation = [2 10];
    pdsch.Modulation = char(mods(m));
    pdsch.NumLayers = 1;
    pdsch.RNTI = 31;
    pdsch.NID = 17;

    [~, info] = nrPDSCHIndices(carrier, pdsch);
    G = double(info.G);
    bits = int8(randi([0 1], G, 1));
    sym = nrPDSCH(carrier, pdsch, {bits});

    llrA = localNormalizeLLRCell(nrPDSCHDecode(carrier, pdsch, sym, 0.5));
    llrB = localNormalizeLLRCell(nrPDSCHDecode(carrier, pdsch, sym, 1.0));
    llrA = double(llrA{1}(:));
    llrB = double(llrB{1}(:));

    hard = int8(llrA < 0);
    assert(isequal(hard, bits), ...
        "Direct %s PDSCH LLR signs must recover the transmitted codeword bits.", mods(m));
    magA = median(abs(llrA), "omitnan");
    magB = median(abs(llrB), "omitnan");
    assert(abs((magA / magB) - 2) < 1e-10, ...
        "%s LLR magnitudes must scale inversely with the demapper noise variance.", mods(m));
end
end

function localAssertCodingLineageAndPerturbationSensitivity()
cfg = localPDSCHCfg();
[tx, ~] = sixgr.phy.dl.PDSCH_Tx(cfg);
rx = sixgr.phy.dl.PDSCH_Rx(tx.Waveform, cfg, ...
    "Carrier", tx.Carrier, ...
    "PDSCH", tx.PDSCH, ...
    "PDSCHIndices", tx.PDSCHIndices, ...
    "TransportBlockSize", tx.TransportBlockSize, ...
    "TargetCodeRate", tx.TargetCodeRate, ...
    "RV", tx.RV, ...
    "CodingLayout", tx.CodingLayout);

lineage = rx.DecodedBitLineagePerCodeword{1};
layout = tx.CodingLayout;
assert(double(lineage.DemapperLLRCount) == double(layout.RateMatchedBitCount), ...
    "Decoded lineage must preserve demapper LLR count G.");
assert(double(lineage.RateRecoveredRows) == double(layout.MotherCodeLength) && ...
        double(lineage.RateRecoveredCodeBlocks) == double(layout.NumCodeBlocks), ...
    "Decoded lineage must preserve mother-code recovery dimensions.");

goodLLR = 40 * (1 - 2 * double(tx.Codeword(:)));
[recGood, recInfo] = sixgr.phy.phycode.rateRecoverLDPC(goodLLR, ...
    double(layout.TransportBlockSize), tx.TargetCodeRate, tx.RV, tx.PDSCH.Modulation, ...
    double(layout.NumLayers), double(layout.NumCodeBlocks), [], "CodingLayout", layout);
assert(string(recInfo.OutputDomain) == "mother_code_llr_by_code_block", ...
    "Rate recovery must declare mother-code LLR output domain.");
decGood = sixgr.phy.phycode.ldpcDecode(recGood, double(layout.BaseGraph), 12, "Normalized min-sum");
tbCrcGood = sixgr.phy.tb.desegmentLDPC(decGood, layout);
[tbGood, okGood] = sixgr.phy.tb.checkCRC(tbCrcGood, layout.TBCRCType);
assert(logical(okGood) && isequal(int8(tbGood(:)), int8(tx.TransportBlock(:))), ...
    "High-confidence direct codeword LLRs must decode to the transmitted TB.");

recBad = sixgr.phy.phycode.rateRecoverLDPC(-goodLLR, ...
    double(layout.TransportBlockSize), tx.TargetCodeRate, tx.RV, tx.PDSCH.Modulation, ...
    double(layout.NumLayers), double(layout.NumCodeBlocks), [], "CodingLayout", layout);
decBad = sixgr.phy.phycode.ldpcDecode(recBad, double(layout.BaseGraph), 12, "Normalized min-sum");
tbCrcBad = sixgr.phy.tb.desegmentLDPC(decBad, layout);
[~, okBad] = sixgr.phy.tb.checkCRC(tbCrcBad, layout.TBCRCType);
assert(~logical(okBad), ...
    "Flipping the LLR sign must change decoder behavior and fail the TB CRC.");
end

function cfg = localPDSCHCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 20;
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.pdsch.prbSet = 0:5;
cfg.phy.pdsch.symbolAllocation = [0 10];
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.30;
cfg.phy.pdsch.mcsIndex = 4;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.equalizer = "MMSE";
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.channelEstimation.method = "LS";
cfg.phy.ldpc.maxIterations = 12;
end

function cells = localNormalizeLLRCell(raw)
if iscell(raw)
    cells = reshape(raw, 1, []);
else
    cells = {raw};
end
for i = 1:numel(cells)
    cells{i} = double(cells{i}(:));
end
end

function tf = localHaveRequired5G()
tf = exist("nrPDSCH", "file") == 2 && ...
    exist("nrPDSCHDecode", "file") == 2 && ...
    exist("nrPDSCHIndices", "file") == 2 && ...
    exist("nrDLSCHInfo", "file") == 2 && ...
    exist("nrRateRecoverLDPC", "file") == 2 && ...
    exist("nrLDPCDecode", "file") == 2;
end
