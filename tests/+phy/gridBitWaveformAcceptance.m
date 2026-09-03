function ok = gridBitWaveformAcceptance()
%GRIDBITWAVEFORMACCEPTANCE Toolbox-direct grid, bit, and OFDM anchors.

localRequire5G();
carrier = nrCarrierConfig;
carrier.NSizeGrid = 24;
carrier.SubcarrierSpacing = 30;

pdsch = nrPDSCHConfig;
pdsch.PRBSet = 0:7;
pdsch.SymbolAllocation = [2 10];
pdsch.Modulation = "16QAM";
pdsch.NumLayers = 2;
pdsch.DMRS.DMRSPortSet = 0:1;
[dutInd, dutInfo] = sixgr.phy.grid.allocREsPDSCH(carrier, pdsch, "IndexBase", "1based");
[refInd, refInfo] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index", "IndexBase", "1based");
assert(isequal(dutInd, refInd), "PDSCH data indices must be bit-exact with nrPDSCHIndices.");
assert(double(dutInfo.ResourceAccounting.CodedBitCountG) == double(refInfo.G), ...
    "PDSCH G must match Toolbox reference G.");

pusch = nrPUSCHConfig;
pusch.PRBSet = 4:15;
pusch.SymbolAllocation = [0 14];
pusch.Modulation = "QPSK";
pusch.NumLayers = 1;
[dutULInd, dutULInfo] = sixgr.phy.grid.allocREsPUSCH(carrier, pusch, "IndexBase", "1based");
[refULInd, refULInfo] = nrPUSCHIndices(carrier, pusch, "IndexStyle", "index", "IndexBase", "1based");
assert(isequal(dutULInd, refULInd), "PUSCH data indices must be bit-exact with nrPUSCHIndices.");
assert(double(dutULInfo.ResourceAccounting.CodedBitCountG) == double(refULInfo.G), ...
    "PUSCH G must match Toolbox reference G.");

cfg = struct("A", 384, "R", 0.45, "Modulation", "QPSK", "NumLayers", 1, "Direction", "DL");
layout = sixgr.phy.phycode.resolveCodingLayout( ...
    "Direction", cfg.Direction, "TransportBlockSize", cfg.A, ...
    "TargetCodeRate", cfg.R, "RV", 0, "Modulation", cfg.Modulation, ...
    "NumLayers", cfg.NumLayers, "RateMatchedBitCount", 1024);
tb = int8(mod((0:cfg.A-1).', 2));
tbCrc = sixgr.phy.tb.attachCRC(tb, layout.TBCRCType);
cbs = sixgr.phy.tb.segmentLDPC(tbCrc, double(layout.BaseGraph));
enc = sixgr.phy.phycode.ldpcEncode(cbs, double(layout.BaseGraph));
rm = sixgr.phy.phycode.rateMatchLDPC(enc, double(layout.RateMatchedBitCount), ...
    0, cfg.Modulation, cfg.NumLayers);
refRM = nrRateMatchLDPC(enc, double(layout.RateMatchedBitCount), 0, cfg.Modulation, cfg.NumLayers);
assert(isequal(rm(:), refRM(:)), "Rate matching must be bit-exact with direct Toolbox reference.");

grid = complex(zeros(carrier.NSizeGrid * 12, 14, 1));
grid(1:48, :) = exp(1j * pi/4) .* ((-1) .^ reshape(0:(48*14-1), 48, 14));
[waveform, modInfo] = sixgr.phy.waveform.ofdmModulate(carrier, grid);
[refWaveform, ~] = nrOFDMModulate(carrier, grid, "Windowing", 0);
assert(max(abs(waveform(:) - refWaveform(:))) < 1e-12, ...
    "Strict zero-window OFDM wrapper must match nrOFDMModulate sample-for-sample.");
[rxGrid, demodInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, waveform);
rxGrid = rxGrid(1:size(grid, 1), 1:size(grid, 2), :);
assert(max(abs(rxGrid(:) - grid(:))) < 1e-11, ...
    "OFDM mod-demod zero-noise loopback must reconstruct occupied grid RE.");
assert(double(modInfo.DimensionContract.GridPorts) == 1 && ...
    isequal(double(demodInfo.GridSize(1:2)), double([size(grid, 1), size(grid, 2)])), ...
    "OFDM dimension contract must preserve grid subcarriers/symbols/ports.");
ok = true;
end

function localRequire5G()
required = ["nrCarrierConfig","nrPDSCHConfig","nrPUSCHConfig", ...
    "nrPDSCHIndices","nrPUSCHIndices","nrRateMatchLDPC", ...
    "nrOFDMModulate","nrOFDMDemodulate"];
missing = required(arrayfun(@(f) exist(char(f), "file") ~= 2 && exist(char(f), "class") ~= 8, required));
assert(isempty(missing), "Missing required 5G Toolbox APIs: %s", strjoin(missing, ", "));
end
