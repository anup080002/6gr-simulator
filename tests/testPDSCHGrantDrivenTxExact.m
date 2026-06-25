function ok = testPDSCHGrantDrivenTxExact()
%TESTPDSCHGRANTDRIVENTXEXACT Deterministic frozen-grant PDSCH TX evidence.

setup6GRSimToolkit("Verbose", false);
if ~localHaveRequired5G()
    ok = true;
    return;
end

rng(6306, "twister");
vectors = localVectorSet();
maxGridErr = 0;
maxLayerErr = 0;
maxPortErr = 0;
maxPowerErr = 0;

for i = 1:numel(vectors)
    v = vectors(i);
    cfg = localCfg(v);
    [~, pdsch, acct] = localConfiguredPDSCH(cfg, v);
    tbs = double(nrTBS(pdsch.Modulation, pdsch.NumLayers, numel(pdsch.PRBSet), ...
        acct.NREPerPRBForTBS, v.TargetCodeRate, v.XOverhead));
    tbBits = localPayloadBits(tbs, i);
    phyGrant = localFreezeGrant(cfg, v, acct, tbs);

    [tx, info] = sixgr.phy.dl.PDSCH_Tx(cfg, ...
        "PHYGrant", phyGrant, ...
        "TransportBlockBits", tbBits, ...
        "RV", v.RV);
    exp = localDirectToolboxPDSCH(tx.Carrier, tx.PDSCH, tbBits, ...
        v.TargetCodeRate, v.RV, tx.ResourceAccounting.CodedBitCountG, ...
        tx.PrecodeInfo.MatrixPorts);

    assert(logical(tx.TxContext.GrantDriven), "TxContext must declare frozen-grant mode.");
    assert(strcmp(tx.TransportBlockSizeSource, "frozen_phygrant_transport_block_size"), ...
        "PDSCH_Tx must use the frozen grant TBS when present.");
    assert(isequal(tx.PDSCHIndices, exp.PDSCHIndices), ...
        "Frozen-grant PDSCH data indices changed for vector %d.", i);
    assert(isequal(tx.DMRSIndices, exp.DMRSIndices), ...
        "Frozen-grant PDSCH DMRS indices changed for vector %d.", i);
    assert(isequal(tx.PTRSIndices, exp.PTRSIndices), ...
        "Frozen-grant PDSCH PTRS indices changed for vector %d.", i);
    assert(isequal(int8(tx.Codeword(:)), int8(exp.Codeword(:))), ...
        "Frozen-grant PDSCH codeword bits changed for vector %d.", i);

    layerErr = localMaxAbs(tx.PDSCHLayerSymbols(:) - exp.LayerSymbols(:));
    portErr = localMaxAbs(tx.PDSCHPortSymbols(:) - exp.PortSymbols(:));
    gridErr = localMaxAbs(tx.Grid(:) - exp.Grid(:));
    maxLayerErr = max(maxLayerErr, layerErr);
    maxPortErr = max(maxPortErr, portErr);
    maxGridErr = max(maxGridErr, gridErr);
    assert(layerErr < 1e-12, "Layer-domain PDSCH symbols differ for vector %d.", i);
    assert(portErr < 1e-12, "Port-domain PDSCH symbols differ for vector %d.", i);
    assert(gridErr < 1e-12, "Complete PDSCH port grid differs for vector %d.", i);

    powerErr = double(tx.PrecodePowerInfo.ColumnNormMaxError);
    maxPowerErr = max(maxPowerErr, powerErr);
    assert(powerErr < 1e-12, "PDSCH precoder column normalization drifted for vector %d.", i);
    if double(tx.PrecodePowerInfo.OrthonormalColumnMaxError) < 1e-12
        assert(double(tx.PrecodePowerInfo.TotalPowerMaxAbsError) < 1e-9, ...
            "PDSCH precoding changed total symbol energy for vector %d.", i);
    end

    ctx = tx.TxContext.DimensionContract;
    assert(double(ctx.LayerDataRE) == double(tx.ResourceAccounting.LayerDataRE), ...
        "TxContext LayerDataRE does not match resource accounting.");
    assert(double(ctx.QAMSymbolCount) == numel(tx.PDSCHLayerSymbols), ...
        "TxContext QAMSymbolCount does not match layer symbols.");
    assert(double(ctx.PortIndexCellCount) == numel(tx.PDSCHPortIndices), ...
        "TxContext PortIndexCellCount does not match port indices.");
    assert(double(ctx.RateMatchedBitCount) == numel(tx.Codeword), ...
        "TxContext RateMatchedBitCount does not match codeword.");
    assert(logical(info.ResourceAccounting.DisjointMasks), ...
        "Frozen-grant PDSCH must have disjoint data/DMRS/PTRS masks.");

    if i == 1
        localAssertIndependentNoiselessReceiver(tx, tbBits, v.TargetCodeRate);
    end
end

localAssertFixedReferenceGuards();
fprintf("PDSCH grant-driven exact vectors=%d maxLayerErr=%.3g maxPortErr=%.3g maxGridErr=%.3g maxPowerErr=%.3g\n", ...
    numel(vectors), maxLayerErr, maxPortErr, maxGridErr, maxPowerErr);
ok = true;
end

function vectors = localVectorSet()
mods = ["QPSK", "16QAM", "64QAM", "256QAM"];
layers = [1 2 3 4];
maps = ["A", "B"];
rvs = [0 2 3 1];
mcsTables = ["qam64", "qam256", "qam1024"];
vectors = repmat(struct(), 1, 30);
k = 0;
for m = 1:numel(mods)
    for l = 1:numel(layers)
        for mp = 1:numel(maps)
            k = k + 1;
            if k > numel(vectors)
                return;
            end
            nLayers = layers(l);
            nPorts = nLayers;
            if mod(k, 5) == 0 && nLayers < 4
                nPorts = nLayers + 1;
            end
            vectors(k).Modulation = mods(m);
            vectors(k).NumLayers = nLayers;
            vectors(k).NumPorts = nPorts;
            vectors(k).MappingType = maps(mp);
            vectors(k).SymbolAllocation = localSymbolAllocation(maps(mp));
            vectors(k).PRBSet = 0:(2 + mod(k, 3));
            vectors(k).TargetCodeRate = 0.28 + 0.03 * mod(k, 4);
            vectors(k).XOverhead = 0;
            vectors(k).RV = rvs(1 + mod(k - 1, numel(rvs)));
            vectors(k).RNTI = 100 + k;
            vectors(k).NID = 10 + k;
            vectors(k).EnablePTRS = mod(k, 6) == 0;
            vectors(k).MCSTable = mcsTables(1 + mod(k - 1, numel(mcsTables)));
        end
    end
end
end

function symAlloc = localSymbolAllocation(mappingType)
if string(mappingType) == "B"
    symAlloc = [4 8];
else
    symAlloc = [0 10];
end
end

function cfg = localCfg(v)
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 60;
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.NCellID = v.NID;
cfg.phy.nTxAnt = v.NumPorts;
cfg.channel.nTxAnt = v.NumPorts;
cfg.scenario.bs.nTxAnt = v.NumPorts;
cfg.antenna.bs.numElements = v.NumPorts;
cfg.phy.pdsch.enable = true;
cfg.phy.pdsch.prbSet = v.PRBSet;
cfg.phy.pdsch.symbolAllocation = v.SymbolAllocation;
cfg.phy.pdsch.mappingType = char(v.MappingType);
cfg.phy.pdsch.modulation = char(v.Modulation);
cfg.phy.pdsch.numLayers = v.NumLayers;
cfg.phy.pdsch.nLayers = v.NumLayers;
cfg.phy.pdsch.numPorts = v.NumPorts;
cfg.phy.pdsch.nPorts = v.NumPorts;
cfg.phy.pdsch.RNTI = v.RNTI;
cfg.phy.pdsch.NID = v.NID;
cfg.phy.pdsch.codeRate = v.TargetCodeRate;
cfg.phy.pdsch.xOverhead = v.XOverhead;
cfg.phy.pdsch.rv = v.RV;
cfg.phy.pdsch.mcsTable = char(v.MCSTable);
cfg.phy.pdsch.enablePTRS = logical(v.EnablePTRS);
cfg.phy.pdsch.ptrs.timeDensity = 2;
cfg.phy.pdsch.ptrs.frequencyDensity = 2;
cfg.phy.pdsch.ptrs.reOffset = "00";
cfg.phy.pdsch.ptrs.portSet = 0;
cfg.phy.pdsch.precoding.matrix = localPrecoder(v.NumPorts, v.NumLayers);
cfg.phy.pdsch.precodingMatrix = cfg.phy.pdsch.precoding.matrix;
cfg.phy.pdsch.W = cfg.phy.pdsch.precoding.matrix;
cfg.phy.csirs.enable = false;
end

function [carrier, pdsch, acct] = localConfiguredPDSCH(cfg, v)
carrier = sixgr.phy.grid.makeCarrier(cfg);
[pdschInd, pdschInfo, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfg, ...
    "PRBSet", v.PRBSet, ...
    "SymbolAllocation", v.SymbolAllocation, ...
    "NumLayers", v.NumLayers, ...
    "Modulation", v.Modulation, ...
    "RNTI", v.RNTI, ...
    "NID", v.NID, ...
    "MappingType", v.MappingType, ...
    "FixedReferenceMode", true);
acct = sixgr.phy.resource.computeResourceAccounting("PDSCH", carrier, pdsch, ...
    "ChannelIndices", pdschInd, ...
    "AllocationInfo", pdschInfo, ...
    "IndexBase", "1based", ...
    "TargetCodeRate", v.TargetCodeRate, ...
    "XOverhead", v.XOverhead);
end

function phyGrant = localFreezeGrant(cfg, v, acct, tbs)
grant = struct();
grant.Direction = "DL";
grant.Frame = 0;
grant.Slot = 0;
grant.RNTI = v.RNTI;
grant.UEIndex = 1;
grant.ServingCell = 1;
grant.PRBSet = v.PRBSet;
grant.SymbolAllocation = v.SymbolAllocation;
grant.MappingType = char(v.MappingType);
grant.Modulation = char(v.Modulation);
grant.NumLayers = v.NumLayers;
grant.Layers = v.NumLayers;
grant.NumLogicalPorts = v.NumPorts;
grant.TargetCodeRate = v.TargetCodeRate;
grant.XOverhead = v.XOverhead;
grant.NREPerPRB = acct.NREPerPRBForTBS;
grant.TBSBits = tbs;
grant.MCSIndex = 4 + mod(v.RNTI, 8);
grant.MCS = grant.MCSIndex;
grant.MCSTable = char(v.MCSTable);
grant.PrecodingMatrix = cfg.phy.pdsch.precoding.matrix;
grant.PrecodingActive = true;
grant.GrantContextId = sprintf('DL|exact|rnti=%d|rv=%d|layers=%d|ports=%d', ...
    v.RNTI, v.RV, v.NumLayers, v.NumPorts);
grant.HARQ = struct("HarqID", 0, "NDI", true, "RV", v.RV, "IsRetransmission", false);
phyGrant = sixgr.phy.grant.freezePHYGrant(cfg, "DL", grant, "Frame", 0, "Slot", 0);
end

function exp = localDirectToolboxPDSCH(carrier, pdsch, tbBits, targetCodeRate, rv, G, Wports)
schInfo = nrDLSCHInfo(numel(tbBits), targetCodeRate);
bgn = double(schInfo.BGN);
tbCRCType = char(string(sixgr.util.structGet(schInfo, "CRC", "24A")));
tbCrc = nrCRCEncode(tbBits(:), tbCRCType);
cbs = nrCodeBlockSegmentLDPC(tbCrc, bgn);
codedCB = nrLDPCEncode(cbs, bgn);
codeword = nrRateMatchLDPC(codedCB, double(G), rv, pdsch.Modulation, pdsch.NumLayers);

[pdschInd, ~] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
layerSym = nrPDSCH(carrier, pdsch, {int8(codeword(:))});
Wports = localNormalizeColumns(Wports);
matrixNR = reshape(Wports.', [double(pdsch.NumLayers), size(Wports, 1), 1]);
[portSym, portInd] = nrPDSCHPrecode(carrier, layerSym, pdschInd, matrixNR);

dmrsInd = nrPDSCHDMRSIndices(carrier, pdsch, "IndexStyle", "index");
dmrsSym = nrPDSCHDMRS(carrier, pdsch);
[dmrsPortSym, dmrsPortInd] = nrPDSCHPrecode(carrier, dmrsSym, dmrsInd, matrixNR);

ptrsInd = zeros(0, 1);
ptrsPortInd = zeros(0, size(portInd, 2));
ptrsPortSym = complex(zeros(0, size(portSym, 2)));
if isprop(pdsch, "EnablePTRS") && logical(pdsch.EnablePTRS)
    ptrsInd = nrPDSCHPTRSIndices(carrier, pdsch, "IndexStyle", "index");
    ptrsSym = nrPDSCHPTRS(carrier, pdsch);
    if ~isempty(ptrsInd)
        [ptrsPortSym, ptrsPortInd] = nrPDSCHPrecode(carrier, ptrsSym, ptrsInd, matrixNR);
    end
end

grid = nrResourceGrid(carrier, size(Wports, 1));
grid = localMapGrid(grid, portInd, portSym);
grid = localMapGrid(grid, dmrsPortInd, dmrsPortSym);
grid = localMapGrid(grid, ptrsPortInd, ptrsPortSym);

exp = struct();
exp.Codeword = int8(codeword(:));
exp.LayerSymbols = layerSym;
exp.PortSymbols = portSym;
exp.PDSCHIndices = pdschInd;
exp.PortIndices = portInd;
exp.DMRSIndices = dmrsInd;
exp.DMRSPortIndices = dmrsPortInd;
exp.PTRSIndices = ptrsInd;
exp.PTRSPortIndices = ptrsPortInd;
exp.Grid = grid;
end

function grid = localMapGrid(grid, ind, sym)
if isempty(ind) || isempty(sym)
    return;
end
assert(numel(ind) == numel(sym), "Direct grid mapper requires one symbol per index.");
grid(ind(:)) = sym(:);
end

function localAssertIndependentNoiselessReceiver(tx, tbBits, targetCodeRate)
rxGrid = nrOFDMDemodulate(tx.Carrier, tx.Waveform);
rxSym = nrExtractResources(tx.PDSCHIndices, rxGrid);
llr = nrPDSCHDecode(tx.Carrier, tx.PDSCH, rxSym, 1e-12);
if iscell(llr)
    llr = llr{1};
end
layout = tx.CodingLayout;
rec = nrRateRecoverLDPC(llr, numel(tbBits), targetCodeRate, tx.RV, ...
    tx.PDSCH.Modulation, tx.PDSCH.NumLayers, double(layout.NumCodeBlocks));
dec = nrLDPCDecode(rec, double(layout.BaseGraph), 25);
[blk, ~] = nrCodeBlockDesegmentLDPC(dec, double(layout.BaseGraph), double(layout.B));
[rxBits, crcErr] = nrCRCDecode(blk, layout.TBCRCType);
assert(all(crcErr == 0), "Independent no-channel Toolbox receiver failed TB CRC.");
assert(numel(rxBits) == numel(tbBits) && all(int8(rxBits(:)) == int8(tbBits(:))), ...
    "Independent no-channel Toolbox receiver did not recover the exact TB.");
end

function localAssertFixedReferenceGuards()
pdsch = nrPDSCHConfig;
pdsch.NumLayers = 2;
pdsch.Modulation = "QPSK";
cfg = struct();
cfg.phy.pdsch.tpmi = 0;
cfg.phy.pdsch.numPorts = 2;
try
    sixgr.phy.dl.resolvePDSCHPrecoding(pdsch, cfg, ...
        "PrecodingMatrix", 1, ...
        "FixedReferenceMode", true);
    error("testPDSCHGrantDrivenTxExact:MissingPrecodingGuard", ...
        "Fixed-reference mode should reject rank-mismatched explicit precoding.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:phy:dl:PDSCHPrecoding:ExplicitMatrixLayerMismatch"), ...
        "Unexpected fixed-reference precoding guard: %s", ME.identifier);
end

cfgBad = localCfg(struct("Modulation", "QPSK", "NumLayers", 1, "NumPorts", 1, ...
    "MappingType", "A", "SymbolAllocation", [4 8], "PRBSet", 0:2, ...
    "TargetCodeRate", 0.3, "XOverhead", 0, "RV", 0, "RNTI", 501, ...
    "NID", 7, "EnablePTRS", false, "MCSTable", "qam64"));
carrier = sixgr.phy.grid.makeCarrier(cfgBad);
try
    sixgr.phy.grid.allocREsPDSCH(carrier, cfgBad, ...
        "PRBSet", 0:2, ...
        "SymbolAllocation", [4 8], ...
        "MappingType", "A", ...
        "FixedReferenceMode", true);
    error("testPDSCHGrantDrivenTxExact:MissingMappingGuard", ...
        "Fixed-reference mode should reject invalid MappingType A timing.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:phy:grid:allocREsPDSCH:InvalidTypeADMRSSymbol"), ...
        "Unexpected fixed-reference mapping guard: %s", ME.identifier);
end
end

function bits = localPayloadBits(nBits, seed)
idx = (1:nBits).';
bits = int8(mod(idx + 3 * seed + floor(idx / 7), 2));
end

function W = localPrecoder(nPorts, nLayers)
rows = (0:nPorts-1).';
cols = 0:nLayers-1;
W = exp(-1j * 2 * pi * rows * cols / max(1, nPorts)) / sqrt(max(1, nPorts));
W = localNormalizeColumns(W);
end

function W = localNormalizeColumns(W)
W = double(W);
for c = 1:size(W, 2)
    n = norm(W(:, c));
    assert(isfinite(n) && n > 0, "Invalid precoder column norm.");
    W(:, c) = W(:, c) ./ n;
end
end

function value = localMaxAbs(x)
if isempty(x)
    value = 0;
else
    value = max(abs(x(:)));
end
end

function tf = localHaveRequired5G()
tf = exist("nrPDSCH", "file") == 2 ...
    && exist("nrPDSCHDecode", "file") == 2 ...
    && exist("nrPDSCHPrecode", "file") == 2 ...
    && exist("nrDLSCHInfo", "file") == 2 ...
    && exist("nrLDPCEncode", "file") == 2 ...
    && exist("nrLDPCDecode", "file") == 2 ...
    && exist("nrRateMatchLDPC", "file") == 2 ...
    && exist("nrRateRecoverLDPC", "file") == 2 ...
    && exist("nrPDSCHPTRS", "file") == 2 ...
    && exist("nrPDSCHPTRSIndices", "file") == 2 ...
    && exist("nrOFDMDemodulate", "file") == 2;
end
