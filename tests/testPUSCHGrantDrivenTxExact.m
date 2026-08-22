function ok = testPUSCHGrantDrivenTxExact()
%TESTPUSCHGRANTDRIVENTXEXACT Deterministic frozen-grant PUSCH TX evidence.

setup6GRSimToolkit("Verbose", false);
if ~localHaveRequired5G()
    ok = true;
    return;
end

rng(7307, "twister");
vectors = localVectorSet();
maxLayerErr = 0;
maxPortErr = 0;
maxGridErr = 0;
maxDftErr = 0;

for i = 1:numel(vectors)
    v = vectors(i);
    cfg = localCfg(v);
    try
        [~, pusch, acct] = localConfiguredPUSCH(cfg, v);
    catch cause
        failure = MException("sixgr:tests:PUSCHGrantVectorFailed", ...
            "PUSCH grant vector %d failed (%s, rank=%d, ports=%d, transform=%d, PTRS=%d).", ...
            i, char(v.Modulation), v.NumLayers, v.NumPorts, ...
            double(v.TransformPrecoding), double(v.EnablePTRS));
        failure = addCause(failure, cause);
        throw(failure);
    end
    tbs = double(nrTBS(pusch.Modulation, pusch.NumLayers, numel(pusch.PRBSet), ...
        acct.NREPerPRBForTBS, v.TargetCodeRate, v.XOverhead));
    tbBits = localPayloadBits(tbs, i);
    phyGrant = localFreezeGrant(cfg, v, acct, tbs);

    [tx, info] = sixgr.phy.ul.PUSCH_Tx(cfg, ...
        "PHYGrant", phyGrant, ...
        "TransportBlockBits", tbBits, ...
        "RV", v.RV);
    exp = localDirectToolboxPUSCH(tx.Carrier, tx.PUSCH, tbBits, ...
        v.TargetCodeRate, v.RV, tx.ResourceAccounting.CodedBitCountG, ...
        size(tx.Grid, 3), phyGrant);

    assert(logical(tx.TxContext.GrantDriven), "TxContext must declare frozen-grant mode.");
    assert(strcmp(tx.TransportBlockSizeSource, "frozen_phygrant_transport_block_size"), ...
        "PUSCH_Tx must use the frozen grant TBS when present.");
    assert(isequal(tx.PUSCHNativeIndices, exp.NativePUSCHIndices), ...
        "Frozen-grant native PUSCH data indices changed for vector %d.", i);
    assert(isequal(tx.DMRSNativeIndices, exp.NativeDMRSIndices), ...
        "Frozen-grant native PUSCH DMRS indices changed for vector %d.", i);
    assert(isequal(tx.PUSCHIndices, exp.PUSCHIndices), ...
        "Frozen-grant executed logical-port PUSCH indices changed for vector %d.", i);
    assert(isequal(tx.DMRSIndices, exp.DMRSIndices), ...
        "Frozen-grant executed logical-port PUSCH DMRS indices changed for vector %d.", i);
    assert(isequal(int8(tx.Codeword(:)), int8(exp.Codeword(:))), ...
        "Frozen-grant PUSCH codeword bits changed for vector %d.", i);

    layerErr = localMaxAbs(tx.PUSCHLayerSymbols(:) - exp.LayerSymbols(:));
    portErr = localMaxAbs(tx.PUSCHPortSymbols(:) - exp.PortSymbols(:));
    gridErr = localMaxAbs(tx.Grid(:) - exp.Grid(:));
    dftErr = localMaxAbs(tx.PUSCHDFTInputSymbols(:) - exp.DFTInputSymbols(:));
    maxLayerErr = max(maxLayerErr, layerErr);
    maxPortErr = max(maxPortErr, portErr);
    maxGridErr = max(maxGridErr, gridErr);
    maxDftErr = max(maxDftErr, dftErr);
    assert(layerErr < 1e-12, "Layer-domain PUSCH symbols differ for vector %d.", i);
    assert(portErr < 1e-12, "Port-domain PUSCH symbols differ for vector %d.", i);
    assert(gridErr < 1e-12, "Complete PUSCH port grid differs for vector %d.", i);
    assert(dftErr < 1e-12, "DFT-input PUSCH symbols differ for vector %d.", i);

    ctx = tx.TxContext.DimensionContract;
    assert(double(ctx.LayerDataRE) == double(tx.ResourceAccounting.LayerDataRE), ...
        "TxContext LayerDataRE does not match resource accounting.");
    assert(double(ctx.QAMSymbolCount) == numel(tx.PUSCHDFTInputSymbols), ...
        "TxContext QAMSymbolCount does not match data QAM symbols.");
    assert(double(ctx.LayerRESymbolCount) == numel(tx.PUSCHLayerSymbols), ...
        "TxContext LayerRESymbolCount does not match layer RE symbols.");
    assert(double(ctx.PortIndexCellCount) == numel(tx.PUSCHPortIndices), ...
        "TxContext PortIndexCellCount does not match port indices.");
    assert(double(ctx.RateMatchedBitCount) == numel(tx.Codeword), ...
        "TxContext RateMatchedBitCount does not match codeword.");
    assert(localLinearMasksDisjoint(info.ResourceAccounting), ...
        "Frozen-grant PUSCH must have unique maps with no data-DMRS or DMRS-PTRS overlap.");
    if logical(v.EnablePTRS)
        localAssertPTRSWaveformMapping(tx, i);
    end

    if i == 1
        localAssertNoiselessRoundtrip(tx, tbBits, cfg);
    end
end

localAssertAuditedTwoPortOneLayer();
localAssertInvalidCombinationsFail();
fprintf("PUSCH grant-driven exact vectors=%d maxLayerErr=%.3g maxPortErr=%.3g maxGridErr=%.3g maxDftErr=%.3g\n", ...
    numel(vectors), maxLayerErr, maxPortErr, maxGridErr, maxDftErr);
ok = true;
end

function vectors = localVectorSet()
vectors = [ ...
    localVector("QPSK", 1, 1, "nonCodebook", NaN, false, false), ...
    localVector("16QAM", 2, 2, "nonCodebook", NaN, false, false), ...
    localVector("64QAM", 3, 4, "nonCodebook", NaN, false, false), ...
    localVector("256QAM", 4, 4, "nonCodebook", NaN, false, false), ...
    localVector("QPSK", 1, 2, "codebook", 0, false, false), ...
    localVector("QPSK", 1, 2, "codebook", 3, false, false), ...
    localVector("16QAM", 2, 4, "codebook", 1, false, true), ...
    localVector("64QAM", 2, 4, "codebook", 6, false, false), ...
    localVector("QPSK", 3, 4, "codebook", 3, false, false), ...
    localVector("QPSK", 4, 4, "codebook", 0, false, false), ...
    localVector("QPSK", 1, 1, "nonCodebook", NaN, true, false), ...
    localVector("QPSK", 1, 2, "codebook", 0, true, false), ...
    localVector("QPSK", 1, 2, "codebook", 1, true, true)];
rvPattern = [0 2 3 1];
for i = 1:numel(vectors)
    vectors(i).RNTI = 300 + i;
    vectors(i).NID = 30 + i;
    vectors(i).RV = rvPattern(1 + mod(i - 1, 4));
    vectors(i).TargetCodeRate = 0.28 + 0.02 * mod(i, 5);
    vectors(i).XOverhead = 0;
    vectors(i).PRBSet = 0:(3 + mod(i, 3));
    vectors(i).SymbolAllocation = [0 10];
    vectors(i).MappingType = "A";
    vectors(i).MCSTable = "qam256";
    vectors(i).PTRSPortSet = 0;
end
vectors(7).PTRSPortSet = 1;
end

function v = localVector(modulation, nLayers, nPorts, scheme, tpmi, transformPrecoding, enablePTRS)
v = struct();
v.Modulation = string(modulation);
v.NumLayers = double(nLayers);
v.NumPorts = double(nPorts);
v.TransmissionScheme = string(scheme);
v.TPMI = double(tpmi);
v.TransformPrecoding = logical(transformPrecoding);
v.EnablePTRS = logical(enablePTRS);
v.PTRSPortSet = 0;
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
cfg.phy.carrier.NSizeGrid = max(18, max(v.PRBSet) + 1);
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.NCellID = v.NID;
cfg.phy.nTxAnt = v.NumPorts;
cfg.phy.nRxAnt = v.NumPorts;
cfg.channel.nTxAnt = v.NumPorts;
cfg.channel.nRxAnt = v.NumPorts;
cfg.scenario.ue.nTxAnt = v.NumPorts;
cfg.antenna.ue.numElements = v.NumPorts;
cfg.phy.pusch.enable = true;
cfg.phy.pusch.prbSet = v.PRBSet;
cfg.phy.pusch.symbolAllocation = v.SymbolAllocation;
cfg.phy.pusch.mappingType = char(v.MappingType);
cfg.phy.pusch.modulation = char(v.Modulation);
cfg.phy.pusch.numLayers = v.NumLayers;
cfg.phy.pusch.nLayers = v.NumLayers;
cfg.phy.pusch.numAntennaPorts = v.NumPorts;
cfg.phy.pusch.numPorts = v.NumPorts;
cfg.phy.pusch.nPorts = v.NumPorts;
% Frozen-grant execution requires the same explicit per-layer DM-RS port
% pool that a production YAML is required to provide.  Do not inherit the
% scalar rank-1 default while constructing a rank>1 test grant.
cfg.phy.pusch.dmrs.portSet = 0:(v.NumLayers - 1);
cfg.phy.pusch.dmrs.DMRSPortSet = cfg.phy.pusch.dmrs.portSet;
cfg.phy.pusch.RNTI = v.RNTI;
cfg.phy.pusch.NID = v.NID;
cfg.phy.pusch.codeRate = v.TargetCodeRate;
cfg.phy.pusch.xOverhead = v.XOverhead;
cfg.phy.pusch.rv = v.RV;
cfg.phy.pusch.transmissionScheme = char(v.TransmissionScheme);
if string(v.TransmissionScheme) == "codebook"
    if v.NumPorts <= 2
        cfg.phy.pusch.codebookType = "codebook1_ng1n2n2";
    else
        cfg.phy.pusch.codebookType = "codebook1_ng1n4n1";
    end
    cfg.phy.pusch.CodebookType = cfg.phy.pusch.codebookType;
end
cfg.phy.pusch.transformPrecoding = logical(v.TransformPrecoding);
cfg.phy.pusch.enablePTRS = logical(v.EnablePTRS);
cfg.phy.pusch.ptrs.timeDensity = 2;
cfg.phy.pusch.ptrs.frequencyDensity = 2;
cfg.phy.pusch.ptrs.reOffset = "00";
cfg.phy.pusch.ptrs.portSet = v.PTRSPortSet;
if logical(v.TransformPrecoding) && logical(v.EnablePTRS)
    % DFT-s-OFDM PT-RS has a different 38.211 parameterization from
    % CP-OFDM PT-RS.  Keep the grant vector complete instead of silently
    % borrowing frequency-density/RE-offset controls from the CP-OFDM path.
    cfg.phy.pusch.ptrs.numPTRSSamples = 2;
    cfg.phy.pusch.ptrs.numPTRSGroups = 2;
end
if isfinite(v.TPMI)
    cfg.phy.pusch.TPMI = v.TPMI;
    cfg.phy.pusch.PMI = v.TPMI;
end
end

function [carrier, pusch, acct] = localConfiguredPUSCH(cfg, v)
carrier = sixgr.phy.grid.makeCarrier(cfg);
[puschInd, puschInfo, pusch] = sixgr.phy.grid.allocREsPUSCH(carrier, cfg, ...
    "PRBSet", v.PRBSet, ...
    "SymbolAllocation", v.SymbolAllocation, ...
    "NumLayers", v.NumLayers, ...
    "Modulation", v.Modulation, ...
    "RNTI", v.RNTI, ...
    "NID", v.NID, ...
    "TransformPrecoding", v.TransformPrecoding, ...
    "TransmissionScheme", v.TransmissionScheme, ...
    "NumAntennaPorts", v.NumPorts, ...
    "TPMI", v.TPMI, ...
    "MappingType", v.MappingType, ...
    "FixedReferenceMode", true);
acct = sixgr.phy.resource.computeResourceAccounting("PUSCH", carrier, pusch, ...
    "ChannelIndices", puschInd, ...
    "AllocationInfo", puschInfo, ...
    "IndexBase", "1based", ...
    "TargetCodeRate", v.TargetCodeRate, ...
    "XOverhead", v.XOverhead);
end

function phyGrant = localFreezeGrant(cfg, v, acct, tbs)
grant = struct();
grant.Direction = "UL";
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
grant.NumTxAnt = v.NumPorts;
grant.TargetCodeRate = v.TargetCodeRate;
grant.XOverhead = v.XOverhead;
grant.NREPerPRB = acct.NREPerPRBForTBS;
grant.TBSBits = tbs;
grant.MCSIndex = 4 + mod(v.RNTI, 8);
grant.MCS = grant.MCSIndex;
grant.MCSTable = char(v.MCSTable);
grant.TransmissionScheme = char(v.TransmissionScheme);
grant.TransformPrecoding = logical(v.TransformPrecoding);
grant.PrecodingActive = logical(v.TransformPrecoding || string(v.TransmissionScheme) == "codebook");
if isfinite(v.TPMI)
    grant.TPMI = v.TPMI;
    grant.PMI = v.TPMI;
end
grant.GrantContextId = sprintf('UL|exact|rnti=%d|rv=%d|layers=%d|ports=%d', ...
    v.RNTI, v.RV, v.NumLayers, v.NumPorts);
grant.HARQ = struct("HarqID", 0, "NDI", true, "RV", v.RV, "IsRetransmission", false);
phyGrant = sixgr.phy.grant.freezePHYGrant(cfg, "UL", grant, "Frame", 0, "Slot", 0);
end

function exp = localDirectToolboxPUSCH(carrier, pusch, tbBits, targetCodeRate, rv, G, nPages, phyGrant)
if nargin < 7
    nPages = [];
end
if nargin < 8
    phyGrant = struct();
end
schInfo = nrULSCHInfo(numel(tbBits), targetCodeRate);
bgn = double(schInfo.BGN);
tbCRCType = char(string(sixgr.util.structGet(schInfo, "CRC", "24A")));
tbCrc = nrCRCEncode(tbBits(:), tbCRCType);
cbs = nrCodeBlockSegmentLDPC(tbCrc, bgn);
codedCB = nrLDPCEncode(cbs, bgn);
codeword = nrRateMatchLDPC(codedCB, double(G), rv, pusch.Modulation, pusch.NumLayers);

[puschInd, ~] = nrPUSCHIndices(carrier, pusch, "IndexStyle", "index");
[portSym, ptrsSym] = nrPUSCH(carrier, pusch, int8(codeword(:)));
nativePUSCHInd = puschInd;
nativePortSym = portSym;
dftInputSym = localScrambledLayerSymbols(pusch, int8(codeword(:)));
if logical(pusch.TransformPrecoding)
    if strcmpi(char(string(pusch.TransmissionScheme)), "codebook")
        layerSym = localPostTransformLayerSymbols(carrier, pusch, int8(codeword(:)));
    else
        layerSym = portSym;
    end
else
    layerSym = dftInputSym;
end

dmrsInd = nrPUSCHDMRSIndices(carrier, pusch, "IndexStyle", "index");
dmrsSym = nrPUSCHDMRS(carrier, pusch);
nativeDMRSInd = dmrsInd;
nativeDMRSSym = dmrsSym;
ptrsInd = zeros(0, size(portSym, 2));
if ~isempty(ptrsSym)
    ptrsInd = sixgr.phy.resource.puschPTRSGridIndices( ...
        carrier, pusch, "IndexBase", "1based");
end
[portSym, puschInd] = localApplyFrozenLogicalProjection( ...
    carrier, portSym, puschInd, phyGrant);
[dmrsSym, dmrsInd] = localApplyFrozenLogicalProjection( ...
    carrier, dmrsSym, dmrsInd, phyGrant);
if isempty(nPages)
    nPages = max([size(puschInd, 2), size(dmrsInd, 2), size(ptrsInd, 2), 1]);
end
grid = nrResourceGrid(carrier, nPages);
grid = localMapGrid(grid, puschInd, portSym);
grid = localMapGrid(grid, dmrsInd, dmrsSym);
grid = localMapGrid(grid, ptrsInd, ptrsSym);

exp = struct();
exp.Codeword = int8(codeword(:));
exp.DFTInputSymbols = dftInputSym;
exp.LayerSymbols = layerSym;
exp.PortSymbols = portSym;
exp.PUSCHIndices = puschInd;
exp.DMRSIndices = dmrsInd;
exp.NativePortSymbols = nativePortSym;
exp.NativePUSCHIndices = nativePUSCHInd;
exp.NativeDMRSSymbols = nativeDMRSSym;
exp.NativeDMRSIndices = nativeDMRSInd;
exp.PTRSIndices = ptrsInd;
exp.Grid = grid;
end

function [logicalSym, logicalInd] = localApplyFrozenLogicalProjection( ...
        carrier, nativeSym, nativeInd, phyGrant)
logicalSym = nativeSym;
logicalInd = nativeInd;
if isempty(nativeSym) || isempty(nativeInd) || ...
        ~(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)))
    return;
end
prec = sixgr.util.structGet(phyGrant, "PrecodingState", struct());
if logical(sixgr.util.structGet(prec, "NativeCodebookApplied", false))
    return;
end
W = double(sixgr.util.structGet(prec, "MatrixLogicalPorts", []));
% The immutable frozen matrix is the authority.  During replay it is
% projected into cfg and resolvePUSCHPrecoding correctly classifies it as
% explicit even when the original scheduler metadata did not need to set a
% redundant ExplicitBeamWeightsApplied flag.
if isempty(W)
    return;
end
assert(~isempty(W) && size(W, 2) == size(nativeSym, 2), ...
    "Frozen non-codebook logical-port matrix is incompatible with native PUSCH tensors.");
logicalSym = nativeSym * W.';
probeGrid = nrResourceGrid(carrier, size(W, 1));
planeSize = size(probeGrid, 1) * size(probeGrid, 2);
if isvector(nativeInd)
    baseInd = mod(double(nativeInd(:)) - 1, planeSize) + 1;
else
    baseInd = mod(double(nativeInd(:, 1)) - 1, planeSize) + 1;
end
assert(size(logicalSym, 1) == numel(baseInd), ...
    "Frozen logical-port projection changed the PUSCH RE-row count.");
logicalInd = baseInd + (0:size(W, 1)-1) * planeSize;
end

function dftInputSym = localScrambledLayerSymbols(pusch, codeword)
scrambled = nrPUSCHScramble(codeword(:), double(pusch.NID), double(pusch.RNTI));
modulated = nrSymbolModulate(scrambled(:), char(string(pusch.Modulation)));
dftInputSym = nrLayerMap(modulated, double(pusch.NumLayers));
end

function layerSym = localPostTransformLayerSymbols(carrier, pusch, codeword)
puschLayer = pusch;
puschLayer.TransmissionScheme = "nonCodebook";
try
    puschLayer.NumAntennaPorts = double(pusch.NumLayers);
catch
end
layerSym = nrPUSCH(carrier, puschLayer, codeword);
end

function grid = localMapGrid(grid, ind, sym)
if isempty(ind) || isempty(sym)
    return;
end
if isnumeric(ind) && isnumeric(sym) && ismatrix(ind) && ismatrix(sym) && size(ind, 1) == size(sym, 1) ...
        && size(sym, 2) > size(ind, 2)
    colEnergy = sum(abs(sym).^2, 1);
    activeCols = find(colEnergy > 0);
    if isempty(activeCols)
        return;
    end
    if numel(activeCols) == size(ind, 2)
        grid(ind(:)) = sym(:, activeCols);
        return;
    end
end
assert(numel(ind) == numel(sym), "Direct grid mapper requires one symbol per index.");
grid(ind(:)) = sym(:);
end

function localAssertNoiselessRoundtrip(tx, tbBits, cfg)
[rx, ~] = sixgr.phy.ul.PUSCH_Rx(tx.Waveform, cfg, ...
    "Carrier", tx.Carrier, ...
    "PUSCH", tx.PUSCH, ...
    "PUSCHIndices", tx.PUSCHIndices, ...
    "TransportBlockSize", tx.TransportBlockSize, ...
    "TargetCodeRate", tx.TargetCodeRate, ...
    "RV", tx.RV, ...
    "NoiseVar", 1e-12, ...
    "NoiseVarDomain", "grid", ...
    "CompactOutput", false, ...
    "SkipTimingEstimate", true);
metrics = sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfg, "UL");
ber = sum(int8(tbBits(:)) ~= int8(rx.TransportBlock(:))) / numel(tbBits);
assert(logical(rx.Ok) && ~logical(rx.CRCError), "Noiseless PUSCH roundtrip must pass CRC.");
assert(ber == 0, "Noiseless PUSCH roundtrip must have BER=0.");
assert(double(metrics.SymbolErrorRate) == 0 && double(metrics.SymbolErrors) == 0, ...
    "Noiseless PUSCH roundtrip must have SER=0.");
end

function localAssertAuditedTwoPortOneLayer()
v = localVector("QPSK", 1, 2, "codebook", 0, false, true);
v.RNTI = 777;
v.NID = 77;
v.RV = 0;
v.TargetCodeRate = 0.30;
v.XOverhead = 0;
v.PRBSet = 0:272;
v.SymbolAllocation = [0 14];
v.MappingType = "A";
v.MCSTable = "qam64";
cfg = localCfg(v);
cfg.phy.carrier.NSizeGrid = 273;
[~, pusch, acct] = localConfiguredPUSCH(cfg, v);
tbs = double(nrTBS(pusch.Modulation, pusch.NumLayers, numel(pusch.PRBSet), ...
    acct.NREPerPRBForTBS, v.TargetCodeRate, v.XOverhead));
tbBits = localPayloadBits(tbs, 777);
phyGrant = localFreezeGrant(cfg, v, acct, tbs);
[tx, ~] = sixgr.phy.ul.PUSCH_Tx(cfg, ...
    "PHYGrant", phyGrant, ...
    "TransportBlockBits", tbBits, ...
    "RV", v.RV, ...
    "CompactOutput", true);
assert(double(tx.QAMSymbolCount) == 41766, "Audited PUSCH QAM/layer symbol count must be 41766.");
assert(double(tx.G) == 83532, "Audited PUSCH coded bit count G must be 83532.");
assert(double(tx.PortIndexCellCount) == 83532, "Audited PUSCH two-port mapped cell count must be 83532.");
assert(size(tx.PUSCHLayerSymbols, 2) == 1 && size(tx.PUSCHPortSymbols, 2) == 2, ...
    "Audited PUSCH must keep one layer and two port columns separately.");
end

function localAssertInvalidCombinationsFail()
pd = nrPUSCHConfig;
pd.NumLayers = 2;
pd.TransmissionScheme = "codebook";
pd.NumAntennaPorts = 2;
pd.TPMI = 99;
thrown = false;
try
    sixgr.phy.ul.resolvePUSCHPrecoding(pd, struct(), "FixedReferenceMode", true);
catch ME
    thrown = strcmp(ME.identifier, "sixgr:phy:ul:PUSCHPrecoding:UnsupportedCodebook");
end
assert(thrown, "Invalid PUSCH TPMI must fail before waveform generation.");

cfgBad = sixgr.config.defaultConfig();
cfgBad.phy.carrier.NSizeGrid = 18;
cfgBad.phy.pusch.prbSet = 0:3;
cfgBad.phy.pusch.symbolAllocation = [4 8];
cfgBad.phy.pusch.mappingType = "A";
carrier = sixgr.phy.grid.makeCarrier(cfgBad);
thrown = false;
try
    sixgr.phy.grid.allocREsPUSCH(carrier, cfgBad, ...
        "PRBSet", 0:3, ...
        "SymbolAllocation", [4 8], ...
        "MappingType", "A", ...
        "FixedReferenceMode", true);
catch ME
    thrown = strcmp(ME.identifier, "sixgr:phy:grid:allocREsPUSCH:InvalidTypeADMRSSymbol");
end
assert(thrown, "Fixed-reference PUSCH MappingType A timing mutation must fail.");

cfgTransform = sixgr.config.defaultConfig();
cfgTransform.phy.carrier.NSizeGrid = 18;
cfgTransform.phy.pusch.numLayers = 2;
cfgTransform.phy.pusch.nLayers = 2;
cfgTransform.phy.pusch.transformPrecoding = true;
carrier = sixgr.phy.grid.makeCarrier(cfgTransform);
thrown = false;
try
    sixgr.phy.grid.allocREsPUSCH(carrier, cfgTransform, ...
        "PRBSet", 0:3, "SymbolAllocation", [0 10], ...
        "NumLayers", 2, "TransformPrecoding", true, ...
        "FixedReferenceMode", true);
catch ME
    thrown = strcmp(ME.identifier, ...
        "sixgr:pusch:UnsupportedTransformPrecodingLayerCount");
end
assert(thrown, ...
    "Strict transform-precoded rank greater than one must fail explicitly.");
end

function localAssertPTRSWaveformMapping(tx, vectorIndex)
assert(~isempty(tx.PTRSIndices) && ~isempty(tx.PTRSSymbols), ...
    "PTRS-enabled vector %d must expose raw Toolbox PTRS indices and symbols.", vectorIndex);
assert(isfield(tx, "PTRSRawWaveformIndices") && isfield(tx, "PTRSRawWaveformSymbols"), ...
    "PTRS-enabled vector %d must retain raw waveform PTRS tensors.", vectorIndex);
rawInd = tx.PTRSRawWaveformIndices;
rawSym = tx.PTRSRawWaveformSymbols;
activeCols = find(sum(abs(rawSym).^2, 1) > 0);
assert(~isempty(activeCols), "PTRS-enabled vector %d must have at least one active PTRS column.", vectorIndex);
if size(rawInd, 1) == size(rawSym, 1) && size(rawInd, 2) == size(rawSym, 2)
    expInd = rawInd(:, activeCols);
    expSym = rawSym(:, activeCols);
elseif size(rawInd, 1) == size(rawSym, 1) && numel(activeCols) == size(rawInd, 2)
    expInd = rawInd;
    expSym = rawSym(:, activeCols);
else
    assert(numel(rawInd) == numel(rawSym), ...
        "PTRS vector %d has unpairable raw index/symbol shapes.", vectorIndex);
    expInd = rawInd;
    expSym = rawSym;
end
assert(isequal(tx.PTRSWaveformIndices, expInd), ...
    "PTRS vector %d waveform indices must select the active Toolbox PTRS columns.", vectorIndex);
assert(localMaxAbs(tx.PTRSWaveformSymbols(:) - expSym(:)) < 1e-12, ...
    "PTRS vector %d waveform symbols must select the active Toolbox PTRS columns.", vectorIndex);
assert(all(abs(tx.Grid(tx.PTRSWaveformIndices(:)) - tx.PTRSWaveformSymbols(:)) < 1e-12), ...
    "PTRS vector %d active PTRS symbols must be present on their waveform grid pages.", vectorIndex);
if size(rawInd, 2) == size(rawSym, 2) && numel(activeCols) < size(rawSym, 2)
    inactiveCols = setdiff(1:size(rawSym, 2), activeCols);
    assert(isempty(intersect(double(tx.PTRSWaveformIndices(:)), double(rawInd(:, inactiveCols)))), ...
        "PTRS vector %d inactive PTRS columns must not be recorded as PTRS waveform writes.", vectorIndex);
    assert(contains(string(tx.PTRSWaveformMapping.Status), "inactive_zero_columns_removed"), ...
        "PTRS vector %d mapping evidence must disclose inactive-column removal.", vectorIndex);
end
end

function tf = localLinearMasksDisjoint(acct)
idx = acct.Indices;
dataLin = localFiniteIndexVector(idx.DataLinear);
dmrsLin = localFiniteIndexVector(idx.DMRSLinear);
ptrsLin = localFiniteIndexVector(idx.PTRSLinear);
dup = (numel(dataLin) - numel(unique(dataLin))) + ...
    (numel(dmrsLin) - numel(unique(dmrsLin))) + ...
    (numel(ptrsLin) - numel(unique(ptrsLin)));
overlap = numel(intersect(dataLin, dmrsLin)) + ...
    numel(intersect(dmrsLin, ptrsLin));
tf = dup == 0 && overlap == 0;
end

function values = localFiniteIndexVector(values)
values = double(values(:));
values = values(isfinite(values));
end

function bits = localPayloadBits(nBits, seed)
idx = (1:nBits).';
bits = int8(mod(idx + 5 * seed + floor(idx / 11), 2));
end

function value = localMaxAbs(x)
if isempty(x)
    value = 0;
else
    value = max(abs(x(:)));
end
end

function tf = localHaveRequired5G()
tf = exist("nrPUSCH", "file") == 2 ...
    && exist("nrPUSCHDecode", "file") == 2 ...
    && exist("nrPUSCHCodebook", "file") == 2 ...
    && exist("nrPUSCHScramble", "file") == 2 ...
    && exist("nrSymbolModulate", "file") == 2 ...
    && exist("nrLayerMap", "file") == 2 ...
    && exist("nrLDPCEncode", "file") == 2 ...
    && exist("nrLDPCDecode", "file") == 2 ...
    && exist("nrRateMatchLDPC", "file") == 2 ...
    && exist("nrRateRecoverLDPC", "file") == 2;
end
