function [tx, info] = PUSCH_Tx(cfg, varargin)
%PUSCH_Tx Generate a basic PUSCH transmission (UL-SCH -> PUSCH -> OFDM).
%
%   [TX,INFO] = sixgr.phy.ul.PUSCH_Tx(CFG) builds a carrier and PUSCH
%   allocation from CFG (plus safe defaults), generates or accepts a
%   transport block, performs LDPC-based UL-SCH encoding (CRC, segmentation,
%   LDPC encode, rate matching), maps PUSCH + DMRS (and optional PTRS) into
%   a resource grid, and returns an OFDM waveform.
%
%   Name-Value options:
%     "Carrier"            : nrCarrierConfig override
%     "PUSCH"              : nrPUSCHConfig override
%     "TransportBlockBits" : column vector of bits (int8/double/logical)
%     "TransportBlockSizeOverride" : stored HARQ TB size to preserve during replay
%     "RV"                 : redundancy version (0..3)
%     "TargetCodeRate"     : code rate (0..1)
%     "XOverhead"          : xOverhead for nrTBS (default 0)
%     "NumTxAnt"           : number of TX antennas for resource grid pages
%     "PHYGrant"           : frozen canonical grant dimensional contract
%
%   CFG.phy.pusch.dmrs.dataToDMRSEPREDifference_dB controls the PUSCH
%   data-EPRE minus DM-RS-EPRE difference. The default is 0 dB. The
%   normative -3 dB token maps to exact beta=sqrt(2), with configured and
%   realized dB values retained separately in the output metadata.
%
%   Outputs:
%     TX.Waveform          : time-domain OFDM waveform
%     TX.Grid              : frequency-domain resource grid
%     TX.TransportBlock    : original TB bits
%     TX.Codeword          : rate-matched codeword bits (pre-scramble)
%     TX.Carrier           : carrier config object
%     TX.PUSCH             : PUSCH config object
%     TX.PUSCHIndices      : linear indices for PUSCH mapping
%     TX.DMRSIndices       : linear indices for PUSCH DMRS mapping
%     TX.DMRSSymbols       : DMRS symbols
%     TX.PTRSIndices       : linear indices for PTRS mapping (maybe empty)
%     TX.PTRSSymbols       : PTRS symbols (maybe empty)
%     TX.PrecodeInfo       : runtime-applied native PUSCH precoding metadata
%
%   Notes:
%     * nrPUSCH internally performs scrambling using pusch.NID / pusch.RNTI.
%       Therefore, TX.Codeword is NOT scrambled here.

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PUSCH', [], @(x) isempty(x) || isobject(x));
ip.addParameter('TransportBlockBits', [], @(x) isempty(x) || isnumeric(x) || islogical(x) || iscell(x));
ip.addParameter('TransportBlockSizeOverride', [], @(x) isempty(x) || ...
    (isnumeric(x) && isvector(x) && all(x>0)));
ip.addParameter('RV', [], @(x) isempty(x) || ...
    (isnumeric(x) && isvector(x) && all(x>=0 & x<=3)));
ip.addParameter('TargetCodeRate', [], @(x) isempty(x) || ...
    (isnumeric(x) && isvector(x) && all(x>0 & x<1)));
ip.addParameter('XOverhead', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
ip.addParameter('NumTxAnt', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('UCIPayload', [], @(x) isempty(x) || ...
    isa(x, "sixgr.phy.ul.pusch.PUSCHUCIPayload"));
ip.addParameter('InitialIMCSPerCodeword', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('PHYGrant', struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;
phyGrant = opt.PHYGrant;
hasPHYGrant = isstruct(phyGrant) && ~isempty(fieldnames(phyGrant));
if hasPHYGrant
    sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, "pusch_tx_entry");
    cfg = sixgr.phy.grant.applyPHYGrantToConfig(cfg, phyGrant);
    opt.NumTxAnt = double(phyGrant.AntennaArchitecture.NumWaveformColumns);
end

% Carrier
if isempty(opt.Carrier)
    [carrier, cinfo] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
    cinfo = struct();
end

% Allocation / PUSCH config
if isempty(opt.PUSCH)
    if hasPHYGrant
        [puschInd, puschInfo, pusch] = localBuildPUSCHFromFrozenGrant(carrier, cfg, phyGrant);
    else
        [puschInd, puschInfo, pusch] = sixgr.phy.grid.allocREsPUSCH(carrier, cfg);
    end
else
    pusch = opt.PUSCH;
    pusch = localEnsureTransformPrecodingOwnership(pusch, cfg);
    if hasPHYGrant
        localAssertExplicitPUSCHMatchesGrant(pusch, phyGrant);
    end
    try
        [puschInd, puschInfo] = nrPUSCHIndices(carrier, pusch, 'IndexStyle', 'index');
    catch
        [puschInd, puschInfo] = nrPUSCHIndices(carrier, pusch);
    end
end

% PUSCH parameters
nCodewords = double(pusch.NumCodewords);
rv = localResolvePUSCHRV(cfg, opt.RV, phyGrant, hasPHYGrant, nCodewords);
targetCodeRate = localResolvePUSCHTargetCodeRate( ...
    cfg, opt.TargetCodeRate, phyGrant, hasPHYGrant, nCodewords);
xOverhead = localResolvePUSCHXOverhead(cfg, opt.XOverhead, phyGrant, hasPHYGrant);

prec = sixgr.phy.ul.resolvePUSCHPrecoding(pusch, cfg, "FixedReferenceMode", hasPHYGrant);

uePhysicalTxAnt = double(sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "tx", ...
    sixgr.util.structGet(prec, "NumPorts", 1)));
numTxAnt = opt.NumTxAnt;
if isempty(numTxAnt)
    numTxAnt = max([size(puschInd, 2), double(sixgr.util.structGet(prec, "NumPorts", 1)), 1]);
end
if logical(sixgr.util.structGet(prec, "NativeCodebookApplied", false))
    numTxAnt = max(double(numTxAnt), double(sixgr.util.structGet(prec, "NumPorts", 1)));
end
numTxAnt = max(1, round(numTxAnt));
phyGrantContract = struct();
if hasPHYGrant
    phyGrantContract = sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, ...
        "pusch_tx_before_waveform", ...
        "PUSCH", pusch, ...
        "Precoding", prec, ...
        "NumTxAnt", numTxAnt);
end

% Transport block size
nPRB = numel(pusch.PRBSet);
resourceAccounting = sixgr.phy.resource.computeResourceAccounting("PUSCH", carrier, pusch, ...
    "ChannelIndices", puschInd, ...
    "AllocationInfo", puschInfo, ...
    "IndexBase", "1based", ...
    "TargetCodeRate", targetCodeRate(1), ...
    "XOverhead", xOverhead);
localAssertPUSCHResourceAccounting(resourceAccounting, pusch, hasPHYGrant);
puschInfo.ResourceAccounting = resourceAccounting;
puschInfo.LayerDataRE = resourceAccounting.LayerDataRE;
puschInfo.PortMappedRE = resourceAccounting.PortMappedRE;
puschInfo.ModulationSymbolCount = resourceAccounting.ModulationSymbolCount;
allocationG = double(sixgr.util.structGet(puschInfo, "G", resourceAccounting.CodedBitCountG));
allocationG = allocationG(:).';
puschInfo.CodedBitCountG = allocationG;
puschInfo.G = allocationG;
puschInfo.NREPerPRB = resourceAccounting.NREPerPRBForTBS;
nrePerPRB = resourceAccounting.NREPerPRBForTBS;
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    error('sixgr:phy:ul:PUSCHNoDataRE', ...
        'PUSCH allocation has no schedulable data RE: PRBs=%d SymbolAllocation=%s Modulation=%s Layers=%d.', ...
        round(double(nPRB)), mat2str(localResolveSymbolAllocation(pusch)), char(string(pusch.Modulation)), round(double(pusch.NumLayers)));
end
[trBlkSize, scheduledTrBlkSize, transportBlockSizeSource] = localResolvePUSCHTransportBlockSize( ...
    opt.TransportBlockSizeOverride, phyGrant, hasPHYGrant, pusch, nPRB, nrePerPRB, targetCodeRate, xOverhead);

% Transport block bits
trBlkCells = localResolveTransportBlockCells(opt.TransportBlockBits, trBlkSize);
trBlk = localUnwrapSingleCell(trBlkCells);

G = allocationG;
if numel(G) ~= nCodewords || any(~isfinite(G) | G <= 0 | G ~= fix(G))
    error('sixgr:phy:ul:PUSCHNoDataRE', ...
        'PUSCH requires one positive integer coded-bit budget per codeword: G=%s.', mat2str(G));
end
uciPayload = opt.UCIPayload;
if isempty(uciPayload)
    uciPayload = sixgr.phy.ul.pusch.PUSCHUCIPayload();
end
initialIMCS = opt.InitialIMCSPerCodeword;
if isempty(initialIMCS)
    initialIMCS = double(sixgr.util.structGet(phyGrant, ...
        "CodingLayout.InitialMCSIndex", ...
        sixgr.util.structGet(phyGrant, "CodingLayout.MCSIndex", 0)));
end
[dataBitBudgetG, uciInfo] = localResolvePUSCHUCIBitBudget( ...
    pusch, targetCodeRate, trBlkSize, G, uciPayload, initialIMCS);
codingLayouts = localResolveTxCodingLayouts( ...
    phyGrant, hasPHYGrant, trBlkSize, targetCodeRate, rv, pusch, dataBitBudgetG);
codingLayout = codingLayouts{1};
tbCRCType = string(cellfun(@(x) string(x.TBCRCType), codingLayouts));
tbCRCLen = double(cellfun(@(x) x.TBCRCLength, codingLayouts));
bgn = double(cellfun(@(x) x.BaseGraph, codingLayouts));

% ---------------------- UL-SCH encoding ----------------------
tbCrcCells = cell(1, nCodewords);
segInfoCells = cell(1, nCodewords);
rateMatchInfoCells = cell(1, nCodewords);
if nCodewords == 1
    tbCrcCells{1} = sixgr.phy.tb.attachCRC(trBlkCells{1}, char(tbCRCType(1)));
    [cbs, segInfoCells{1}] = sixgr.phy.tb.segmentLDPC(tbCrcCells{1}, bgn(1));
    ldpcEnc = int8(sixgr.phy.phycode.ldpcEncode(cbs, bgn(1)));
    [ulSchCodeword, rateMatchInfoCells{1}] = sixgr.phy.phycode.rateMatchLDPC( ...
        ldpcEnc, dataBitBudgetG(1), rv(1), localModulationAt(pusch.Modulation, 1), pusch.NumLayers);
    codewords = {int8(ulSchCodeword(:))};
else
    % The release-valid rank-5-to-8 path uses the 5G Toolbox UL-SCH
    % coder with one transport block and rate-matching budget per codeword.
    ulschEncoder = nrULSCH("MultipleHARQProcesses", false, ...
        "TargetCodeRate", targetCodeRate);
    setTransportBlock(ulschEncoder, trBlkCells);
    codewords = ulschEncoder(pusch.Modulation, pusch.NumLayers, dataBitBudgetG, rv);
    codewords = reshape(codewords, 1, []);
    for cw = 1:nCodewords
        codewords{cw} = int8(codewords{cw}(:));
        tbCrcCells{cw} = sixgr.phy.tb.attachCRC(trBlkCells{cw}, char(tbCRCType(cw)));
        segInfoCells{cw} = sixgr.util.structGet(codingLayouts{cw}, "Segmentation", struct());
        rateMatchInfoCells{cw} = struct( ...
            "E", double(numel(codewords{cw})), ...
            "Source", "nrULSCH_two_codeword_release_valid_path");
    end
end
if uciPayload.hasPayload()
    mux = sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex( ...
        pusch, targetCodeRate, trBlkSize, codewords, ...
        uciPayload, initialIMCS);
    codewords = mux.Codewords;
    uciInfo = localMergeUCIInfo(uciInfo, mux);
end
codeword = codewords{1};
dataRateMatchedBits = double(cellfun(@numel, codewords));
if uciPayload.hasPayload()
    dataRateMatchedBits = double(dataBitBudgetG);
end
tbCrc = localUnwrapSingleCell(tbCrcCells);
segInfo = localUnwrapSingleCell(segInfoCells);
rateMatchInfo = localUnwrapSingleCell(rateMatchInfoCells);
B = double(cellfun(@numel, tbCrcCells));
crcInfo = repmat(struct("Type", "", "Length", 0), 1, nCodewords);
for cw = 1:nCodewords
    crcInfo(cw).Type = tbCRCType(cw);
    crcInfo(cw).Length = tbCRCLen(cw);
end
codewordLayerMapping = localBuildPUSCHCodewordLayerContract( ...
    pusch, codewords, codingLayouts, resourceAccounting, dataRateMatchedBits, uciInfo);
if nCodewords == 1
    localAssertRateMatchMapAgreement(rateMatchInfoCells{1}, codingLayouts{1});
end

% ---------------------- PUSCH modulation & mapping ----------------------
[puschSym, ptrsSym, puschSymInfo] = localModulatePUSCH( ...
    carrier, pusch, localUnwrapSingleCell(codewords));
[puschLayerSym, dftInputSym, puschDomainInfo] = localResolvePUSCHSymbolDomains( ...
    carrier, pusch, localUnwrapSingleCell(codewords), puschSym, prec);
if nCodewords == 1
    localAssertPUSCHSymbolContract(codeword, dftInputSym, puschLayerSym, ...
        puschSym, puschInd, resourceAccounting, pusch, codingLayout, uciInfo);
else
    localAssertPUSCHMultiCodewordSymbolContract( ...
        codewords, dftInputSym, puschLayerSym, puschSym, puschInd, pusch);
end
puschLayerInd = localLayerIndicesFromPortIndices(puschInd, puschLayerSym);
puschLayerOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, puschLayerInd, "layer");
puschPortOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, puschInd, "port");

% DMRS
[dmrsInd, dmrsSym, dmrsInfo] = sixgr.phy.refsig.dmrsPUSCH(carrier, pusch);
[dmrsSym, dmrsPowerInfo] = localApplyPUSCHDMRSEPREDifference(dmrsSym, cfg);
dmrsInfo.DataToDMRSEPREDifference_dB = double(dmrsPowerInfo.DataToDMRSEPREDifference_dB);
dmrsInfo.DMRSPowerBoost_dB = double(dmrsPowerInfo.DMRSPowerBoost_dB);
dmrsInfo.ConfiguredDMRSPowerBoost_dB = double(dmrsPowerInfo.ConfiguredDMRSPowerBoost_dB);
dmrsInfo.RealizedDataToDMRSEPREDifference_dB = double(dmrsPowerInfo.RealizedDataToDMRSEPREDifference_dB);
dmrsInfo.DMRSAmplitudeScale = double(dmrsPowerInfo.DMRSAmplitudeScale);
dmrsInfo.DMRSPowerScale = double(dmrsPowerInfo.DMRSPowerScale);
dmrsInfo.EPREConfigSource = char(string(dmrsPowerInfo.Source));
dmrsInfo.EPREScalePolicy = char(string(dmrsPowerInfo.ScalePolicy));

% PTRS (optional)
ptrsInd = [];
if ~isempty(ptrsSym)
    ptrsInd = sixgr.phy.resource.puschPTRSGridIndices( ...
        carrier, pusch, "IndexBase", "1based");
end
localAssertSignalResourceDisjoint(puschInd, dmrsInd, ptrsInd);

puschWaveformSym = puschSym;
puschWaveformInd = puschInd;
dmrsWaveformSym = dmrsSym;
dmrsWaveformInd = dmrsInd;
ptrsWaveformSym = ptrsSym;
ptrsWaveformInd = ptrsInd;
waveformSymbolDomain = "logical_port";
if logical(sixgr.util.structGet(prec, "HybridElementDomainApplied", false))
    [puschWaveformSym, puschWaveformInd] = localApplyHybridElementPrecode(carrier, puschSym, puschInd, prec, "PUSCH");
    [dmrsWaveformSym, dmrsWaveformInd] = localApplyHybridElementPrecode(carrier, dmrsSym, dmrsInd, prec, "PUSCH DMRS");
    [ptrsWaveformSym, ptrsWaveformInd] = localApplyHybridElementPrecode(carrier, ptrsSym, ptrsInd, prec, "PUSCH PTRS");
    localAssertSignalResourceDisjoint(puschWaveformInd, dmrsWaveformInd, ptrsWaveformInd);
    waveformSymbolDomain = "element";
end
[ptrsGridInd, ptrsGridSym, ptrsGridMapInfo] = localActiveReferenceGridPairs(ptrsWaveformInd, ptrsWaveformSym, "PUSCH PTRS");

% Build resource grid and map
% Use grid pages that cover the indices returned by nrPUSCHIndices
nPages = max([size(puschWaveformInd,2), size(dmrsWaveformInd,2), size(ptrsWaveformInd,2), size(ptrsGridInd,2), numTxAnt, 1]);
try
    txGrid = nrResourceGrid(carrier, nPages);
catch
    txGrid = complex(zeros(carrier.NSizeGrid*12, carrier.SymbolsPerSlot, nPages));
end

% Map PUSCH
txGrid = localMapToGrid(txGrid, puschWaveformInd, puschWaveformSym);

% Map DMRS/PTRS
if ~isempty(dmrsWaveformInd)
    txGrid = localMapToGrid(txGrid, dmrsWaveformInd, dmrsWaveformSym);
end
if ~isempty(ptrsGridInd)
    txGrid = localMapToGrid(txGrid, ptrsGridInd, ptrsGridSym);
end
precodePowerInfo = localBuildPUSCHPowerInfo(puschLayerSym, puschWaveformSym, prec);

% OFDM modulation
[windowingSamples, windowingInfo] = sixgr.phy.waveform.resolveOFDMWindowing(cfg, carrier);
[txWaveform, ofdmInfo] = sixgr.phy.waveform.ofdmModulate(carrier, txGrid, ...
    "Windowing", double(windowingSamples));
if hasPHYGrant
    phyGrantContract = sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, ...
        "pusch_tx_after_waveform", ...
        "PUSCH", pusch, ...
        "Precoding", prec, ...
        "NumTxAnt", numTxAnt, ...
        "Grid", txGrid, ...
        "Waveform", txWaveform);
end

% ---------------------- Outputs ----------------------
tx = struct();
tx.Waveform = txWaveform;
tx.OFDMInfo = ofdmInfo;
tx.OFDM = ofdmInfo;
if hasPHYGrant
    tx.PHYGrant = phyGrant;
    tx.PHYGrantDimensionContract = phyGrantContract;
end
tx.TransportBlockSize = trBlkSize;
tx.ScheduledTransportBlockSize = scheduledTrBlkSize;
tx.TransportBlockSizeSource = transportBlockSizeSource;
tx.TransportBlock = trBlk;
tx.TransportBlocks = trBlkCells;
tx.TransportBlockCRCType = char(tbCRCType(1));
tx.TransportBlockCRCTypes = cellstr(tbCRCType);
tx.TransportBlockCRCLength = double(tbCRCLen);
tx.TransportBlockLenWithCRC = B;
tx.RV = rv;
tx.TargetCodeRate = targetCodeRate;
tx.CodingLayout = codingLayout;
tx.CodingLayouts = codingLayouts;
tx.Carrier = carrier;
tx.PUSCH = pusch;
tx.PUSCHIndices = puschInd;
tx.PUSCHSymbolsForEvidence = puschLayerSym;
tx.PUSCHLayerSymbolsForEvidence = puschLayerSym;
tx.PUSCHPortSymbolsForEvidence = puschSym;
tx.PUSCHLayerSymbols = puschLayerSym;
tx.PUSCHPortSymbols = puschSym;
tx.PUSCHWaveformSymbols = puschWaveformSym;
tx.PUSCHWaveformIndices = puschWaveformInd;
tx.PUSCHWaveformSymbolDomain = waveformSymbolDomain;
tx.PUSCHDFTInputSymbols = dftInputSym;
tx.PUSCHLayerIndices = puschLayerInd;
tx.PUSCHPortIndices = puschInd;
tx.LayerSymbolOrder = puschLayerOrder;
tx.PortSymbolOrder = puschPortOrder;
tx.LayerSymbolDomain = "layer";
tx.PortSymbolDomain = "port";
tx.XOverhead = double(xOverhead);
tx.G = G;
tx.NREPerPRB = double(nrePerPRB);
tx.LayerDataRE = double(resourceAccounting.LayerDataRE);
tx.PortMappedRE = double(resourceAccounting.PortMappedRE);
tx.ModulationSymbolCount = double(resourceAccounting.ModulationSymbolCount);
tx.QAMSymbolCount = double(numel(dftInputSym));
tx.LayerRESymbolCount = double(numel(puschLayerSym));
tx.PortIndexCellCount = double(numel(puschInd));
tx.RateMatchedBitCount = double(G);
tx.DataRateMatchedBitCount = double(dataRateMatchedBits);
tx.NumCodewords = double(codewordLayerMapping.NumCodewords);
tx.RateMatchedBitCountPerCodeword = double(codewordLayerMapping.RateMatchedBitCountPerCodeword);
tx.DataRateMatchedBitCountPerCodeword = double(codewordLayerMapping.DataRateMatchedBitCountPerCodeword);
tx.CodewordLayerMapping = codewordLayerMapping;
tx.ResourceAccounting = resourceAccounting;
tx.PrecodeInfo = prec;
tx.PrecodePowerInfo = precodePowerInfo;
tx.DMRSEPREDifference = dmrsPowerInfo;
tx.DMRSDataToDMRSEPREDifference_dB = double(dmrsPowerInfo.DataToDMRSEPREDifference_dB);
tx.DMRSPowerBoost_dB = double(dmrsPowerInfo.DMRSPowerBoost_dB);
tx.DMRSConfiguredPowerBoost_dB = double(dmrsPowerInfo.ConfiguredDMRSPowerBoost_dB);
tx.DMRSRealizedDataToDMRSEPREDifference_dB = double(dmrsPowerInfo.RealizedDataToDMRSEPREDifference_dB);
tx.DMRSAmplitudeScale = double(dmrsPowerInfo.DMRSAmplitudeScale);
tx.DMRSPowerScale = double(dmrsPowerInfo.DMRSPowerScale);
tx.NumWaveformColumns = double(size(txWaveform, 2));
tx.UEPhysicalTxAntennas = double(uePhysicalTxAnt);
tx.SymbolDomainInfo = puschDomainInfo;
tx.UCIOnPUSCHApplied = logical(uciInfo.UCIOnPUSCHApplied);
tx.HARQACKBitCount = double(uciInfo.HARQACKBitCount);
tx.HARQACKBits = int8(uciPayload.HARQACK(:));
tx.CSIPart1Bits = int8(uciPayload.CSIPart1(:));
tx.CSIPart2Bits = int8(uciPayload.CSIPart2(:));
tx.ConfiguredGrantUCIBits = int8(uciPayload.ConfiguredGrantUCI(:));
tx.UCIPayload = uciPayload.toStruct();
tx.UCIOnPUSCHSource = char(string(uciInfo.Source));
tx.OFDMWindowingSamples = double(windowingSamples);
tx.OFDMWindowingSource = char(string(windowingInfo.OFDMWindowingSource));
tx.OFDMWindowingEnabled = logical(windowingInfo.OFDMWindowingEnabled);
if ~logical(opt.CompactOutput)
    tx.Grid = txGrid;
    tx.TransportBlockCRC = tbCrc;
    tx.TransportBlockCRCs = tbCrcCells;
    tx.BaseGraph = bgn;
    tx.Codeword = codeword;
    tx.Codewords = codewords;
    tx.PUSCHInfo = puschInfo;
    tx.PUSCHSymbols = puschLayerSym;
    tx.DFTInputSymbols = dftInputSym;
    tx.DMRSIndices = dmrsInd;
    tx.DMRSSymbols = dmrsSym;
    tx.DMRSWaveformIndices = dmrsWaveformInd;
    tx.DMRSWaveformSymbols = dmrsWaveformSym;
    tx.PTRSIndices = ptrsInd;
    tx.PTRSSymbols = ptrsSym;
    tx.PTRSRawWaveformIndices = ptrsWaveformInd;
    tx.PTRSRawWaveformSymbols = ptrsWaveformSym;
    tx.PTRSWaveformIndices = ptrsGridInd;
    tx.PTRSWaveformSymbols = ptrsGridSym;
    tx.PTRSWaveformMapping = ptrsGridMapInfo;
    tx.PUSCHAntennaIndices = puschWaveformInd;
    tx.PUSCHAntennaSymbols = puschWaveformSym;
    tx.DMRSAntennaIndices = dmrsWaveformInd;
    tx.DMRSAntennaSymbols = dmrsWaveformSym;
end

info = struct();
info.CarrierInfo = cinfo;
info.CRC = crcInfo;
info.Segmentation = segInfo;
info.RateMatch = rateMatchInfo;
info.CodingLayout = codingLayout;
info.CodingLayouts = codingLayouts;
info.CodewordLayerMapping = codewordLayerMapping;
info.PUSCHSymbols = puschSymInfo;
info.SymbolDomain = puschDomainInfo;
info.OFDM = ofdmInfo;
info.OFDMWindowing = windowingInfo;
info.Precoding = prec;
info.PrecodePowerInfo = precodePowerInfo;
info.DMRS = dmrsInfo;
info.DMRSEPREDifference = dmrsPowerInfo;
info.NumWaveformColumns = double(size(txWaveform, 2));
info.UEPhysicalTxAntennas = double(uePhysicalTxAnt);
info.UCIOnPUSCH = uciInfo;
info.TransformPrecodingAppliedBy = localTransformPrecodingSource(pusch, cfg);
info.XOverhead = double(xOverhead);
info.ResourceAccounting = resourceAccounting;
info.TxContext = localBuildTxContext(tx, trBlk, tbCrc, codewords, txGrid, txWaveform, ...
    puschLayerInd, puschLayerSym, puschInd, puschSym, dftInputSym, ...
    dmrsInd, dmrsSym, ptrsInd, ptrsSym, carrier, pusch, codingLayouts, ...
    resourceAccounting, prec, precodePowerInfo, codewordLayerMapping, phyGrant, hasPHYGrant);
tx.TxContext = info.TxContext;
if hasPHYGrant
    info.PHYGrant = phyGrant;
    info.PHYGrantDimensionContract = phyGrantContract;
end

end

function [puschInd, puschInfo, pusch] = localBuildPUSCHFromFrozenGrant(carrier, cfg, phyGrant)
ra = sixgr.util.structGet(phyGrant, "ResourceAllocation", struct());
cl = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
ant = sixgr.util.structGet(phyGrant, "AntennaArchitecture", struct());
args = { ...
    "PRBSet", double(sixgr.util.structGet(ra, "PRBSet", [])), ...
    "SymbolAllocation", double(sixgr.util.structGet(ra, "SymbolAllocation", [])), ...
    "NumLayers", localPositiveIntegerValue(sixgr.util.structGet(cl, "NumLayers", 1), "PHYGrant.CodingLayout.NumLayers"), ...
    "Modulation", char(string(sixgr.util.structGet(cl, "Modulation", "QPSK"))), ...
    "RNTI", localResolveGrantRNTI(cfg, phyGrant), ...
    "NID", localResolveGrantNID(cfg, carrier), ...
    "TransformPrecoding", localResolveGrantTransformPrecoding(cfg, phyGrant), ...
    "TransmissionScheme", localResolveGrantTransmissionScheme(cfg, phyGrant), ...
    "NumAntennaPorts", localPositiveIntegerValue(sixgr.util.structGet(ant, "NumLogicalPorts", 1), "PHYGrant.AntennaArchitecture.NumLogicalPorts"), ...
    "TPMI", localResolveGrantTPMI(cfg, phyGrant), ...
    "MappingType", localResolveGrantMappingType(cfg, phyGrant), ...
    "FixedReferenceMode", true};
[puschInd, puschInfo, pusch] = sixgr.phy.grid.allocREsPUSCH(carrier, cfg, args{:});
localAssertExplicitPUSCHMatchesGrant(pusch, phyGrant);
end

function rnti = localResolveGrantRNTI(cfg, phyGrant)
rnti = localFirstFiniteScalarValue( ...
    sixgr.util.structGet(phyGrant, "ChannelStateKey.RNTI", []), ...
    sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.RNTI", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.RNTI", []), 1);
rnti = localNonnegativeIntegerValue(rnti, "PUSCH RNTI");
end

function nid = localResolveGrantNID(cfg, carrier)
nid = sixgr.util.structGet(cfg, "phy.pusch.NID", ...
    sixgr.util.structGet(cfg, "phy.pusch.nid", []));
if isempty(nid)
    nid = sixgr.util.structGet(cfg, "phy.NCellID", []);
end
if isempty(nid)
    try
        nid = carrier.NCellID;
    catch
        nid = 0;
    end
end
nid = localNonnegativeIntegerValue(nid, "PUSCH NID");
end

function tf = localResolveGrantTransformPrecoding(cfg, phyGrant)
raw = sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.TransformPrecoding", []);
if isempty(raw)
    raw = sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.TransformPrecodingApplied", []);
end
if isempty(raw)
    raw = sixgr.util.structGet(cfg, "phy.pusch.transformPrecoding", false);
end
tf = logical(raw);
end

function scheme = localResolveGrantTransmissionScheme(cfg, phyGrant)
scheme = string(sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.TransmissionScheme", ""));
if strlength(strtrim(scheme)) == 0
    scheme = string(sixgr.util.structGet(cfg, "phy.pusch.transmissionScheme", ...
        sixgr.util.structGet(cfg, "phy.pusch.TransmissionScheme", "")));
end
if strlength(strtrim(scheme)) == 0 && isfinite(localResolveGrantTPMI(cfg, phyGrant))
    scheme = "codebook";
end
if strlength(strtrim(scheme)) == 0
    scheme = "nonCodebook";
end
end

function tpmi = localResolveGrantTPMI(cfg, phyGrant)
tpmi = localFirstFiniteScalarValue( ...
    sixgr.util.structGet(phyGrant, "PrecodingState.TPMI", []), ...
    sixgr.util.structGet(phyGrant, "PrecodingState.PMI", []), ...
    sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.TPMI", []), ...
    sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.PMI", []), NaN);
end

function mappingType = localResolveGrantMappingType(cfg, phyGrant)
mappingType = string(sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.MappingType", ""));
if strlength(strtrim(mappingType)) == 0
    mappingType = string(sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.mappingType", ""));
end
if strlength(strtrim(mappingType)) == 0
    mappingType = string(sixgr.util.structGet(cfg, "phy.pusch.mappingType", "A"));
end
if strlength(strtrim(mappingType)) == 0
    mappingType = "A";
end
mappingType = upper(strtrim(mappingType));
end

function localAssertExplicitPUSCHMatchesGrant(pusch, phyGrant)
ra = sixgr.util.structGet(phyGrant, "ResourceAllocation", struct());
cl = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
ant = sixgr.util.structGet(phyGrant, "AntennaArchitecture", struct());
localAssertSameVector(localObjectValue(pusch, "PRBSet", []), sixgr.util.structGet(ra, "PRBSet", []), ...
    "sixgr:phy:ul:PUSCHGrantPRBMismatch", "PUSCH PRBSet does not match frozen PHYGrant.");
localAssertSameVector(localObjectValue(pusch, "SymbolAllocation", []), sixgr.util.structGet(ra, "SymbolAllocation", []), ...
    "sixgr:phy:ul:PUSCHGrantSymbolMismatch", "PUSCH SymbolAllocation does not match frozen PHYGrant.");
localAssertSameScalar(localObjectValue(pusch, "NumLayers", NaN), sixgr.util.structGet(cl, "NumLayers", NaN), ...
    "sixgr:phy:ul:PUSCHGrantLayerMismatch", "PUSCH NumLayers does not match frozen PHYGrant.");
grantMod = char(string(sixgr.util.structGet(cl, "Modulation", "")));
puschMod = char(string(localObjectValue(pusch, "Modulation", "")));
if strlength(string(grantMod)) > 0 && ~strcmpi(strtrim(puschMod), strtrim(grantMod))
    error("sixgr:phy:ul:PUSCHGrantModulationMismatch", ...
        "PUSCH Modulation '%s' does not match frozen PHYGrant '%s'.", puschMod, grantMod);
end
grantPorts = double(sixgr.util.structGet(ant, "NumLogicalPorts", NaN));
if isfinite(grantPorts) && isprop(pusch, "NumAntennaPorts")
    localAssertSameScalar(localObjectValue(pusch, "NumAntennaPorts", NaN), grantPorts, ...
        "sixgr:phy:ul:PUSCHGrantPortMismatch", "PUSCH NumAntennaPorts does not match frozen PHYGrant.");
end
end

function rv = localResolvePUSCHRV(cfg, optRV, phyGrant, hasPHYGrant, nCodewords)
if ~isempty(optRV)
    rv = double(optRV(:).');
elseif hasPHYGrant
    rv = localFirstFiniteScalarValue(sixgr.util.structGet(phyGrant, "HARQProcessKey.RV", []), ...
        sixgr.util.structGet(phyGrant, "CodingLayout.RV", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.rv", []), 0);
else
    rv = double(sixgr.util.structGet(cfg, 'phy.pusch.rv', 0));
    rv = rv(:).';
end
if numel(rv) ~= nCodewords || any(~isfinite(rv) | rv ~= fix(rv) | rv < 0 | rv > 3)
    error("sixgr:phy:ul:PUSCHBadRV", ...
        "PUSCH RV must provide one integer in [0,3] per codeword (expected %d).", nCodewords);
end
end

function targetCodeRate = localResolvePUSCHTargetCodeRate(cfg, optRate, phyGrant, hasPHYGrant, nCodewords)
grantRate = NaN;
if hasPHYGrant
    grantRate = double(sixgr.util.structGet(phyGrant, "CodingLayout.TargetCodeRate", NaN));
end
if isfinite(grantRate) && grantRate > 0
    if nCodewords ~= 1
        error("sixgr:phy:ul:PUSCHFrozenGrantCodewordMismatch", ...
            "The current frozen PHYGrant contract contains one UL-SCH coding layout and cannot own a two-codeword PUSCH.");
    end
    if ~isempty(optRate) && any(abs(double(optRate) - grantRate) > 1e-12)
        error("sixgr:phy:ul:PUSCHGrantCodeRateMismatch", ...
            "TargetCodeRate does not match frozen PHYGrant %.15g.", grantRate);
    end
    targetCodeRate = grantRate;
elseif ~isempty(optRate)
    targetCodeRate = double(optRate(:).');
else
    targetCodeRate = double(sixgr.util.structGet(cfg, 'phy.pusch.codeRate', []));
    targetCodeRate = targetCodeRate(:).';
end
if numel(targetCodeRate) ~= nCodewords || ...
        any(~isfinite(targetCodeRate) | targetCodeRate <= 0 | targetCodeRate >= 1)
    error("sixgr:phy:ul:PUSCHBadCodeRate", ...
        "PUSCH TargetCodeRate must provide one finite value in (0,1) per codeword (expected %d).", nCodewords);
end
end

function xOverhead = localResolvePUSCHXOverhead(cfg, optXOverhead, phyGrant, hasPHYGrant)
grantXOverhead = NaN;
if hasPHYGrant
    grantXOverhead = double(sixgr.util.structGet(phyGrant, "CodingLayout.XOverhead", NaN));
end
if isfinite(grantXOverhead) && grantXOverhead >= 0
    if ~isempty(optXOverhead) && abs(double(optXOverhead) - grantXOverhead) > 1e-12
        error("sixgr:phy:ul:PUSCHGrantXOverheadMismatch", ...
            "XOverhead %.15g does not match frozen PHYGrant %.15g.", double(optXOverhead), grantXOverhead);
    end
    xOverhead = grantXOverhead;
elseif ~isempty(optXOverhead)
    xOverhead = double(optXOverhead);
else
    xOverhead = double(sixgr.util.structGet(cfg, 'phy.pusch.xOverhead', 0));
end
if ~(isscalar(xOverhead) && isfinite(xOverhead) && xOverhead >= 0)
    error("sixgr:phy:ul:PUSCHBadXOverhead", "PUSCH XOverhead must be finite and non-negative.");
end
end

function [trBlkSize, scheduledTrBlkSize, source] = localResolvePUSCHTransportBlockSize( ...
    overrideTBS, phyGrant, hasPHYGrant, pusch, nPRB, nrePerPRB, targetCodeRate, xOverhead)
scheduledTrBlkSize = double(nrTBS(pusch.Modulation, pusch.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead));
scheduledTrBlkSize = scheduledTrBlkSize(:).';
nCodewords = double(pusch.NumCodewords);
if numel(scheduledTrBlkSize) ~= nCodewords
    error("sixgr:phy:ul:PUSCHTBSCodewordCountMismatch", ...
        "nrTBS returned %d value(s) for NumCodewords=%d.", numel(scheduledTrBlkSize), nCodewords);
end
grantTBS = NaN;
if hasPHYGrant
    grantTBS = double(sixgr.util.structGet(phyGrant, "CodingLayout.TBSBits", NaN));
end
if isfinite(grantTBS) && grantTBS > 0
    trBlkSize = round(grantTBS);
    isHARQRetx = logical(sixgr.util.structGet(phyGrant, "HARQProcessKey.IsRetransmission", false));
    % An override that echoes the frozen grant is not independent evidence.
    % It must not suppress exact nrTBS validation of a new-data grant.
    if ~isHARQRetx && abs(double(scheduledTrBlkSize) - double(trBlkSize)) > 1e-9
        error("sixgr:phy:ul:PUSCHGrantTBSMismatch", ...
            "Frozen PHYGrant TBS=%d does not match exact nrTBS=%d for the materialized allocation. Check mac.scheduler.fastNREApprox / tbsMode on the scenario that produced this grant.", ...
            trBlkSize, round(double(scheduledTrBlkSize)));
    end
    if ~isempty(overrideTBS) && round(double(overrideTBS)) ~= trBlkSize
        error("sixgr:phy:ul:PUSCHReplayTBSMismatch", ...
            "TransportBlockSizeOverride=%d does not match frozen PHYGrant TBS=%d.", ...
            round(double(overrideTBS)), trBlkSize);
    end
    if isHARQRetx
        source = 'frozen_phygrant_harq_original_transport_block_size';
    else
        source = 'frozen_phygrant_transport_block_size';
    end
elseif ~isempty(overrideTBS)
    trBlkSize = round(double(overrideTBS(:).'));
    if numel(trBlkSize) ~= nCodewords
        error("sixgr:phy:ul:PUSCHReplayTBSMismatch", ...
            "TransportBlockSizeOverride must provide one value per codeword.");
    end
    source = 'harq_replay_stored_transport_block';
elseif hasPHYGrant
    trBlkSize = round(double(scheduledTrBlkSize));
    source = 'nrTBS_from_frozen_phygrant_resource_accounting';
else
    trBlkSize = round(double(scheduledTrBlkSize));
    source = 'nrTBS_from_current_allocation';
end
trBlkSize = double(trBlkSize(:).');
if numel(trBlkSize) ~= nCodewords || ...
        any(~isfinite(trBlkSize) | trBlkSize <= 0 | trBlkSize ~= fix(trBlkSize))
    error('PUSCH_Tx:BadReplayTBSize', ...
        'PUSCH must provide one positive finite integer transport block size per codeword.');
end
end

function [dataG, uciInfo] = localResolvePUSCHUCIBitBudget( ...
        pusch, targetCodeRate, trBlkSize, G, payload, initialIMCS)
p = payload.toStruct();
combinedCSI2 = p.OCSI2 + p.OCGUCI;
uciInfo = struct( ...
    "UCIOnPUSCHApplied", false, ...
    "HARQACKBitCount", double(p.OACK), ...
    "CSI1BitCount", double(p.OCSI1), ...
    "CSI2BitCount", double(p.OCSI2), ...
    "ConfiguredGrantUCIBitCount", double(p.OCGUCI), ...
    "Payload", p, ...
    "InitialIMCSPerCodeword", double(initialIMCS(:).'), ...
    "GULSCH", double(G), ...
    "GACK", NaN, ...
    "GCSI1", NaN, ...
    "GCSI2Combined", NaN, ...
    "GACKReserved", NaN, ...
    "Source", "no_uci_payload_requested");
dataG = double(G);
if ~payload.hasPayload()
    return;
end
if exist("nrULSCHMultiplex", "file") ~= 2
    error('sixgr:pusch:UCIProcessingUnavailable', ...
        'Typed UCI on PUSCH requires nrULSCHMultiplex from 5G Toolbox.');
end
rmInfo = nrULSCHInfo(pusch, targetCodeRate, trBlkSize, ...
    p.OACK, p.OCSI1, combinedCSI2);
gULSCH = double(rmInfo.GULSCH);
gACK = double(rmInfo.GACK);
gCSI1 = double(rmInfo.GCSI1);
gCSI2 = double(rmInfo.GCSI2);
if numel(gULSCH) ~= double(pusch.NumCodewords) || ...
        any(~isfinite(gULSCH) | gULSCH <= 0 | gULSCH ~= fix(gULSCH))
    error('sixgr:phy:ul:PUSCHUCIInvalidAllocation', ...
        'PUSCH UCI multiplexing requires one positive integer GULSCH per codeword: %s.', ...
        mat2str(gULSCH));
end
dataG = gULSCH(:).';
uciInfo.GULSCH = gULSCH;
uciInfo.GACK = gACK;
uciInfo.GCSI1 = gCSI1;
uciInfo.GCSI2Combined = gCSI2;
uciInfo.GACKReserved = double(sixgr.util.structGet(rmInfo, "GACKRvd", NaN));
uciInfo.Source = "nrULSCHInfo_ts38212_6_2_7_typed_uci_on_pusch";
end

function info = localMergeUCIInfo(info, mux)
info.UCIOnPUSCHApplied = true;
info.MultiplexInfo = mux.MuxInfo;
info.OwnerCodeword = double(mux.OwnerCodeword);
info.GULSCH = double(mux.GULSCHPerCodeword);
info.GACK = double(mux.GACK);
info.GCSI1 = double(mux.GCSI1);
info.GCSI2Combined = double(mux.GCSI2Combined);
info.PlaceholderXCount = double(mux.PlaceholderXCount);
info.PlaceholderYCount = double(mux.PlaceholderYCount);
info.Source = char(string(mux.Source));
end

function layouts = localResolveTxCodingLayouts(phyGrant, hasPHYGrant, ...
        trBlkSize, targetCodeRate, rv, pusch, G)
nCodewords = double(pusch.NumCodewords);
[layerCounts, ~] = sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(pusch.NumLayers);
layouts = cell(1, nCodewords);
for cw = 1:nCodewords
    layouts{cw} = sixgr.phy.phycode.resolveCodingLayout( ...
        "Direction", "UL", ...
        "TransportBlockSize", trBlkSize(cw), ...
        "TargetCodeRate", targetCodeRate(cw), ...
        "RV", rv(cw), ...
        "Modulation", localModulationAt(pusch.Modulation, cw), ...
        "NumLayers", layerCounts(cw), ...
        "RateMatchedBitCount", G(cw));
end
if hasPHYGrant
    if nCodewords ~= 1
        error("sixgr:phy:ul:PUSCHFrozenGrantCodewordMismatch", ...
            "Frozen PHYGrant validation currently requires one explicit CodingLayout per UL-SCH codeword.");
    end
    localAssertCodingLayoutMatchesGrant(layouts{1}, phyGrant);
end
end

function localAssertCodingLayoutMatchesGrant(codingLayout, phyGrant)
cl = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
localAssertSameScalar(double(codingLayout.A), sixgr.util.structGet(cl, "TBSBits", NaN), ...
    "sixgr:phy:ul:PUSCHCodingGrantTBSMismatch", "Canonical CodingLayout A does not match frozen PHYGrant TBSBits.");
localAssertSameScalar(double(codingLayout.NumLayers), sixgr.util.structGet(cl, "NumLayers", NaN), ...
    "sixgr:phy:ul:PUSCHCodingGrantLayerMismatch", "Canonical CodingLayout NumLayers does not match frozen PHYGrant.");
grantMod = string(sixgr.util.structGet(cl, "Modulation", ""));
if strlength(strtrim(grantMod)) > 0 && upper(strtrim(string(codingLayout.Modulation))) ~= upper(strtrim(grantMod))
    error("sixgr:phy:ul:PUSCHCodingGrantModulationMismatch", ...
        "Canonical CodingLayout modulation '%s' does not match frozen PHYGrant '%s'.", ...
        char(string(codingLayout.Modulation)), char(grantMod));
end
end

function localAssertPUSCHResourceAccounting(resourceAccounting, pusch, fixedReferenceMode)
requiredInts = ["LayerDataRE", "PortMappedRE", "ModulationSymbolCount", "CodedBitCountG", "NREPerPRBForTBS"];
for i = 1:numel(requiredInts)
    name = char(requiredInts(i));
    value = double(resourceAccounting.(name));
    if isscalar(value) && isfinite(value) && value <= 0
        error('sixgr:phy:ul:PUSCHNoDataRE', ...
            'PUSCH allocation has no schedulable data RE/G after resource accounting: %s=%.15g PRBs=%d SymbolAllocation=%s Modulation=%s Layers=%d.', ...
            name, value, numel(pusch.PRBSet), mat2str(localResolveSymbolAllocation(pusch)), ...
            char(string(pusch.Modulation)), round(double(pusch.NumLayers)));
    end
    if ~(isscalar(value) && isfinite(value) && value > 0 && abs(value - round(value)) < 1e-9)
        error("sixgr:phy:ul:PUSCHResourceAccountingBadInteger", ...
            "PUSCH resource accounting field %s must be a positive integer. Got %.15g.", name, value);
    end
end
if ~logical(resourceAccounting.GMatchesLayerRE)
    error("sixgr:phy:ul:PUSCHResourceAccountingGMismatch", ...
        "PUSCH G=%d does not equal LayerDataRE=%d * Qm=%d * NumLayers=%d.", ...
        round(double(resourceAccounting.CodedBitCountG)), round(double(resourceAccounting.LayerDataRE)), ...
        round(double(resourceAccounting.Qm)), round(double(resourceAccounting.NumLayers)));
end
if logical(fixedReferenceMode) && ~localPUSCHLinearMasksDisjoint(resourceAccounting)
    error("sixgr:phy:ul:PUSCHResourceAccountingOverlap", ...
        "PUSCH frozen grant has duplicate data/DMRS/PTRS cells or illegal data-DMRS/DMRS-PTRS overlap. BaseOverlapCount=%d.", ...
        round(double(resourceAccounting.OverlapCount)));
end
if round(double(resourceAccounting.NumLayers)) ~= round(double(pusch.NumLayers))
    error("sixgr:phy:ul:PUSCHResourceAccountingLayerMismatch", ...
        "PUSCH resource accounting NumLayers=%d but pusch.NumLayers=%d.", ...
        round(double(resourceAccounting.NumLayers)), round(double(pusch.NumLayers)));
end
end

function tf = localPUSCHLinearMasksDisjoint(resourceAccounting)
idx = sixgr.util.structGet(resourceAccounting, "Indices", struct());
dataLin = localFiniteIndexVector(sixgr.util.structGet(idx, "DataLinear", []));
dmrsLin = localFiniteIndexVector(sixgr.util.structGet(idx, "DMRSLinear", []));
ptrsLin = localFiniteIndexVector(sixgr.util.structGet(idx, "PTRSLinear", []));
reservedLin = localFiniteIndexVector(sixgr.util.structGet(idx, "ReservedLinear", []));
dup = (numel(dataLin) - numel(unique(dataLin))) + ...
    (numel(dmrsLin) - numel(unique(dmrsLin))) + ...
    (numel(ptrsLin) - numel(unique(ptrsLin)));
overlap = numel(intersect(dataLin, dmrsLin)) + ...
    numel(intersect(dataLin, reservedLin)) + ...
    numel(intersect(dmrsLin, ptrsLin));
tf = dup == 0 && overlap == 0;
end

function values = localFiniteIndexVector(values)
values = double(values(:));
values = values(isfinite(values));
end

function mapping = localBuildPUSCHCodewordLayerContract(pusch, codewords, codingLayouts, resourceAccounting, dataRateMatchedBits, uciInfo)
nLayers = localPositiveIntegerValue(localObjectValue(pusch, "NumLayers", 1), "PUSCH.NumLayers");
nCodewords = double(localObjectValue(pusch, "NumCodewords", 1));
if ~(isscalar(nCodewords) && isfinite(nCodewords) && nCodewords >= 1 && abs(nCodewords - round(nCodewords)) < 1e-9)
    error("sixgr:phy:ul:PUSCHBadCodewordCount", "PUSCH NumCodewords must be a positive integer scalar.");
end
nCodewords = round(nCodewords);
if ~iscell(codewords)
    codewords = {codewords};
end
if ~iscell(codingLayouts)
    codingLayouts = {codingLayouts};
end
if numel(codewords) ~= nCodewords || numel(codingLayouts) ~= nCodewords
    error("sixgr:phy:ul:PUSCHCodewordContainerMismatch", ...
        "PUSCH codeword/coding-layout containers must match NumCodewords=%d.", ...
        nCodewords);
end
[layerCounts, ~] = sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(nLayers);
mapping = struct();
mapping.ContractVersion = "PUSCHCodewordLayer/v1";
mapping.Direction = "UL";
mapping.MappingStandard = "3GPP_TS_38_211_ULSCH_codeword_to_layer_mapping";
mapping.MappingEngine = "nrPUSCH_internal_nrLayerMap";
mapping.InverseEngine = "nrPUSCHDecode_internal_nrLayerDemap";
mapping.SupportedScope = "release_valid_one_or_two_ulsch_codeword_tuples";
mapping.NumCodewords = nCodewords;
mapping.NumLayers = double(nLayers);
mapping.CodewordIndexByLayer = repelem(0:nCodewords-1, layerCounts);
mapping.LayerIndexWithinCodeword = cell2mat(arrayfun( ...
    @(n) 0:n-1, layerCounts, "UniformOutput", false));
mapping.LayerCountPerCodeword = double(layerCounts);
mapping.RateMatchedBitCountPerCodeword = double(cellfun(@numel, codewords));
mapping.DataRateMatchedBitCountPerCodeword = double(dataRateMatchedBits);
mapping.CodingLayoutRateMatchedBitCountPerCodeword = double(cellfun( ...
    @(x) x.RateMatchedBitCount, codingLayouts));
mapping.ResourceAccountingG = double(resourceAccounting.CodedBitCountG);
mapping.UCIOnPUSCHApplied = logical(sixgr.util.structGet(uciInfo, "UCIOnPUSCHApplied", false));
mapping.HARQACKBitCount = double(sixgr.util.structGet(uciInfo, "HARQACKBitCount", 0));
mapping.Equation = "b_G_to_scrambled_bits_to_QAM_d_to_layers_S_to_optional_DFT_to_ports_X";
end
function [layerSym, dftInputSym, info] = localResolvePUSCHSymbolDomains(carrier, pusch, codeword, portSym, prec)
portSym = localEnsure2D(portSym);
nLayers = localPositiveIntegerValue(localObjectValue(pusch, "NumLayers", size(portSym, 2)), "PUSCH.NumLayers");
nPorts = localPositiveIntegerValue(localObjectValue(pusch, "NumAntennaPorts", max(size(portSym, 2), nLayers)), "PUSCH.NumAntennaPorts");
transformPrecoding = logical(localObjectValue(pusch, "TransformPrecoding", false));
scheme = lower(strtrim(string(localObjectValue(pusch, "TransmissionScheme", "nonCodebook"))));
isCodebook = scheme == "codebook";
dftInputSym = localScrambledLayerSymbols(carrier, pusch, codeword);
if transformPrecoding
    if isCodebook
        layerSym = localPostTransformLayerSymbols(carrier, pusch, codeword, nLayers);
    else
        layerSym = portSym;
    end
else
    layerSym = dftInputSym;
end
layerSym = localEnsure2D(layerSym);
if size(layerSym, 2) ~= nLayers
    error("sixgr:phy:ul:PUSCHLayerSymbolShapeMismatch", ...
        "PUSCH layer-symbol shape %s does not match NumLayers=%d.", mat2str(size(layerSym)), nLayers);
end
if isCodebook
    Wtx = prec.MatrixNR;
    if isempty(Wtx)
        [~, status, Wtx] = sixgr.phy.ul.puschCodebookProjectionMatrix(nLayers, nPorts, localObjectValue(pusch, "TPMI", NaN), transformPrecoding);
        if isempty(Wtx)
            error("sixgr:phy:ul:PUSCHCodebookMatrixUnavailable", ...
                "PUSCH codebook matrix unavailable: %s.", char(string(status)));
        end
    end
    expectedPortSym = layerSym * Wtx;
    maxErr = localMaxAbs(portSym(:) - expectedPortSym(:));
    if ~isequal(size(portSym), size(expectedPortSym)) || maxErr > 1e-12
        error("sixgr:phy:ul:PUSCHCodebookPortSymbolMismatch", ...
            "PUSCH port symbols do not equal layer symbols times codebook matrix. Error %.3g.", maxErr);
    end
    transformName = "codebook_X_equals_S_times_W";
    if transformPrecoding
        transformName = "dft_spread_then_codebook_X_equals_S_dft_times_W";
    end
else
    if ~isequal(size(portSym), size(layerSym)) || localMaxAbs(portSym(:) - layerSym(:)) > 1e-12
        error("sixgr:phy:ul:PUSCHDirectPortSymbolMismatch", ...
            "PUSCH non-codebook port symbols must match layer symbols exactly.");
    end
    transformName = "identity";
    if transformPrecoding
        transformName = "dft_spread_before_re_mapping";
    end
end
info = struct( ...
    "ReferenceDomain", "layer", ...
    "PortDomain", "port", ...
    "Transform", transformName, ...
    "NumLayers", double(nLayers), ...
    "NumPorts", double(size(portSym, 2)), ...
    "ConfiguredNumAntennaPorts", double(nPorts), ...
    "TPMI", double(localObjectValue(pusch, "TPMI", NaN)), ...
    "TransformPrecoding", logical(transformPrecoding), ...
    "DFTInputSymbolCount", double(numel(dftInputSym)), ...
    "LayerSymbolCount", double(numel(layerSym)), ...
    "PortSymbolCount", double(numel(portSym)), ...
    "Status", "explicit_pusch_layer_and_port_domains", ...
    "Equation", "b_G_to_scrambled_bits_to_QAM_d_to_layers_S_to_optional_DFT_to_ports_X");
end

function [elementSym, elementInd] = localApplyHybridElementPrecode(carrier, portSym, portInd, prec, label)
elementSym = portSym;
elementInd = portInd;
if isempty(portSym) || isempty(portInd)
    return;
end
portSym = localEnsure2D(portSym);
H = double(sixgr.util.structGet(prec, "HybridElementToPortMatrix", []));
if isempty(H) || ~ismatrix(H)
    error("sixgr:phy:ul:PUSCHHybridPrecode:MissingMatrix", ...
        "Hybrid element precode matrix is missing for %s.", char(string(label)));
end
if size(H, 2) ~= size(portSym, 2)
    error("sixgr:phy:ul:PUSCHHybridPrecode:PortMismatch", ...
        "%s has %d logical port column(s), but the hybrid element matrix is %dx%d.", ...
        char(string(label)), size(portSym, 2), size(H, 1), size(H, 2));
end
elementSym = portSym * H.';

% Expand the logical-port RE locations into the physical antenna planes.
% The RE coordinates are identical for each precoded antenna; only the
% symbol values differ. Keeping this UL operation explicit avoids routing
% PUSCH evidence through a PDSCH-specific helper.
probeGrid = nrResourceGrid(carrier, size(H, 1));
planeSize = size(probeGrid, 1) * size(probeGrid, 2);
portInd = double(portInd);
if isvector(portInd)
    baseInd = mod(portInd(:) - 1, planeSize) + 1;
else
    baseInd = mod(portInd(:, 1) - 1, planeSize) + 1;
end
if size(elementSym, 1) ~= numel(baseInd)
    error("sixgr:phy:ul:PUSCHHybridPrecode:IndexCountMismatch", ...
        "%s produced %d symbol rows for %d allocated RE locations.", ...
        char(string(label)), size(elementSym, 1), numel(baseInd));
end
elementInd = baseInd + (0:size(H, 1)-1) * planeSize;
end

function dftInputSym = localScrambledLayerSymbols(carrier, pusch, codeword)
% nrPUSCH uses carrier.NCellID when pusch.NID is empty. Mirror that
% ownership here so the independently reconstructed layer-domain evidence
% uses the same scrambling sequence as the toolbox modulator.
nid = localObjectValue(pusch, "NID", []);
if isempty(nid)
    nid = localObjectValue(carrier, "NCellID", 0);
end
nid = double(nid);
rnti = double(localObjectValue(pusch, "RNTI", 1));
scrambled = nrPUSCHScramble(codeword, nid, rnti);
if iscell(scrambled)
    modulated = cell(size(scrambled));
    for cw = 1:numel(scrambled)
        modulated{cw} = nrSymbolModulate(scrambled{cw}(:), ...
            localModulationAt(pusch.Modulation, cw));
    end
    dftInputSym = sixgr.phy.ul.pusch.PUSCHLayerMapper.map( ...
        modulated, double(pusch.NumLayers));
else
    modulated = nrSymbolModulate(scrambled(:), char(string(pusch.Modulation)));
    dftInputSym = nrLayerMap(modulated, double(pusch.NumLayers));
end
end

function layerSym = localPostTransformLayerSymbols(carrier, pusch, codeword, nLayers)
puschLayer = pusch;
puschLayer.TransmissionScheme = "nonCodebook";
try
    puschLayer.NumAntennaPorts = nLayers;
catch
end
[layerSym, ~] = nrPUSCH(carrier, puschLayer, codeword);
layerSym = localEnsure2D(layerSym);
end

function localAssertPUSCHSymbolContract(codeword, dftInputSym, layerSym, portSym, portInd, resourceAccounting, pusch, codingLayout, uciInfo)
if numel(codeword) ~= double(resourceAccounting.CodedBitCountG)
    error("sixgr:phy:ul:PUSCHCodewordGContract", ...
        "PUSCH codeword length %d does not match resource-accounting G=%d.", ...
        numel(codeword), round(double(resourceAccounting.CodedBitCountG)));
end

if ~logical(uciInfo.UCIOnPUSCHApplied) && numel(codeword) ~= double(codingLayout.RateMatchedBitCount)
    error("sixgr:phy:ul:PUSCHCodewordCodingLayoutContract", ...
        "PUSCH codeword length %d does not match CodingLayout RateMatchedBitCount=%d.", ...
        numel(codeword), round(double(codingLayout.RateMatchedBitCount)));
end
expectedDataSymbols = double(resourceAccounting.ModulationSymbolCount);
if numel(dftInputSym) ~= expectedDataSymbols
    error("sixgr:phy:ul:PUSCHQAMSymbolCountContract", ...
        "PUSCH data QAM symbol count %d does not equal ModulationSymbolCount=%d.", ...
        numel(dftInputSym), round(double(resourceAccounting.ModulationSymbolCount)));
end
expectedLayerRESymbols = size(portInd, 1) * double(pusch.NumLayers);
if numel(layerSym) ~= expectedLayerRESymbols
    error("sixgr:phy:ul:PUSCHLayerSymbolCountContract", ...
        "PUSCH layer RE symbol count %d does not equal PortIndexRows=%d * NumLayers=%d.", ...
        numel(layerSym), size(portInd, 1), round(double(pusch.NumLayers)));
end
if numel(portSym) ~= double(resourceAccounting.PortMappedRE)
    error("sixgr:phy:ul:PUSCHPortSymbolCountContract", ...
        "PUSCH port symbol count %d does not equal PortMappedRE=%d.", ...
        numel(portSym), round(double(resourceAccounting.PortMappedRE)));
end
if numel(portInd) ~= numel(portSym)
    error("sixgr:phy:ul:PUSCHPortIndexCountContract", ...
        "PUSCH port index count %d does not equal port symbol count %d.", ...
        numel(portInd), numel(portSym));
end
end

function localAssertPUSCHMultiCodewordSymbolContract( ...
        codewords, dftInputSym, layerSym, portSym, portInd, pusch)
if numel(codewords) ~= 2 || double(pusch.NumCodewords) ~= 2
    error("sixgr:phy:ul:PUSCHCodewordContainerMismatch", ...
        "Release-valid high-rank PUSCH requires exactly two UL-SCH codewords.");
end
if size(dftInputSym, 2) ~= double(pusch.NumLayers) || ...
        size(layerSym, 2) ~= double(pusch.NumLayers)
    error("sixgr:phy:ul:PUSCHLayerSymbolShapeMismatch", ...
        "High-rank PUSCH layer-domain evidence must have NumLayers=%d columns.", ...
        double(pusch.NumLayers));
end
if numel(portSym) ~= numel(portInd)
    error("sixgr:phy:ul:PUSCHSymbolIndexCountMismatch", ...
        "High-rank PUSCH port symbol/index counts differ (%d versus %d).", ...
        numel(portSym), numel(portInd));
end
if any(cellfun(@isempty, codewords))
    error("sixgr:phy:ul:PUSCHNoDataRE", ...
        "Each high-rank PUSCH codeword must contain a nonempty coded-bit stream.");
end
end

function localAssertSignalResourceDisjoint(dataInd, dmrsInd, ptrsInd)
checks = {dataInd, "data"; dmrsInd, "dmrs"; ptrsInd, "ptrs"};
for i = 1:size(checks, 1)
    raw = double(checks{i, 1}(:));
    if numel(raw) ~= numel(unique(raw))
        error("sixgr:phy:ul:PUSCHDuplicateMappedRE", ...
            "PUSCH %s indices contain duplicate port-domain RE.", char(checks{i, 2}));
    end
end
dataSet = localIndexSet(dataInd);
dmrsSet = localIndexSet(dmrsInd);
ptrsSet = localIndexSet(ptrsInd);
if ~isempty(intersect(dataSet, dmrsSet))
    error("sixgr:phy:ul:PUSCHDataDMRSOverlap", "PUSCH data and DMRS port-domain RE overlap.");
end
if ~isempty(intersect(dmrsSet, ptrsSet))
    error("sixgr:phy:ul:PUSCHDMRSPTRSOverlap", "PUSCH DMRS and PTRS port-domain RE overlap.");
end
end

function [mapInd, mapSym, info] = localActiveReferenceGridPairs(ind, sym, label)
mapInd = ind;
mapSym = sym;
info = struct( ...
    "Status", "empty", ...
    "Label", string(label), ...
    "RawIndexShape", double(size(ind)), ...
    "RawSymbolShape", double(size(sym)), ...
    "MappedIndexShape", double(size(mapInd)), ...
    "MappedSymbolShape", double(size(mapSym)), ...
    "ActiveColumns", [], ...
    "Equation", "grid(active_reference_indices)=active_reference_symbols");
if isempty(ind) || isempty(sym)
    mapInd = [];
    mapSym = [];
    info.MappedIndexShape = double(size(mapInd));
    info.MappedSymbolShape = double(size(mapSym));
    return;
end
if ~(isnumeric(ind) && isnumeric(sym) && ismatrix(ind) && ismatrix(sym))
    error("sixgr:phy:ul:PUSCHReferenceGridMappingBadType", ...
        "%s grid mapping requires numeric 2-D indices and symbols.", char(string(label)));
end
if size(ind, 1) ~= size(sym, 1)
    if numel(ind) == numel(sym)
        info.Status = "one_to_one_linear";
        info.ActiveColumns = 1:size(sym, 2);
        info.MappedIndexShape = double(size(mapInd));
        info.MappedSymbolShape = double(size(mapSym));
        return;
    end
    error("sixgr:phy:ul:PUSCHReferenceGridMappingRowMismatch", ...
        "%s index rows %d do not match symbol rows %d.", char(string(label)), size(ind, 1), size(sym, 1));
end

colEnergy = sum(abs(sym).^2, 1);
activeCols = find(colEnergy > 0);
if isempty(activeCols)
    mapInd = zeros(size(ind, 1), 0);
    mapSym = complex(zeros(size(sym, 1), 0));
    info.Status = "all_symbol_columns_inactive";
elseif size(ind, 2) == size(sym, 2)
    mapInd = ind(:, activeCols);
    mapSym = sym(:, activeCols);
    if numel(activeCols) == size(sym, 2)
        info.Status = "all_columns_active";
    else
        info.Status = "inactive_zero_columns_removed";
    end
elseif numel(activeCols) == size(ind, 2)
    mapInd = ind;
    mapSym = sym(:, activeCols);
    info.Status = "active_symbol_columns_matched_to_index_columns";
elseif numel(ind) == numel(sym)
    info.Status = "one_to_one_linear";
else
    error("sixgr:phy:ul:PUSCHReferenceGridMappingMismatch", ...
        "%s active reference columns cannot be paired with grid indices. IndexShape=%s SymbolShape=%s ActiveColumns=%s.", ...
        char(string(label)), mat2str(size(ind)), mat2str(size(sym)), mat2str(activeCols));
end
info.RawIndexShape = double(size(ind));
info.RawSymbolShape = double(size(sym));
info.MappedIndexShape = double(size(mapInd));
info.MappedSymbolShape = double(size(mapSym));
info.ActiveColumns = double(activeCols);
end

function powerInfo = localBuildPUSCHPowerInfo(layerSym, portSym, prec)
W = double(prec.MatrixPorts);
if isempty(W)
    W = eye(max(1, round(double(prec.NumLayers))));
end
layerEnergy = sum(abs(layerSym(:)).^2);
portEnergy = sum(abs(portSym(:)).^2);
activePorts = find(sum(abs(portSym).^2, 1) > 0);
powerInfo = struct();
powerInfo.ContractVersion = "PUSCHPower/v1";
powerInfo.Policy = "native_nrPUSCH_port_power";
powerInfo.NumLayers = double(prec.NumLayers);
powerInfo.NumPorts = double(size(portSym, 2));
powerInfo.ConfiguredNumPorts = double(prec.NumPorts);
powerInfo.ActivePorts = double(activePorts);
powerInfo.LayerTotalEnergy = double(layerEnergy);
powerInfo.PortTotalEnergy = double(portEnergy);
powerInfo.PortToLayerEnergyRatio = double(portEnergy / max(layerEnergy, eps));
powerInfo.MatrixColumnNorms = double(sqrt(sum(abs(W).^2, 1)));
powerInfo.MatrixRowNorms = double(sqrt(sum(abs(W).^2, 2)).');
powerInfo.TransformPrecodingApplied = logical(prec.TransformPrecodingApplied);
powerInfo.NativeCodebookApplied = logical(prec.NativeCodebookApplied);
powerInfo.Equation = "X_equals_S_times_W_for_codebook_or_X_equals_S_for_noncodebook";
end

function ctx = localBuildTxContext(tx, trBlk, tbCrc, codewords, txGrid, txWaveform, ...
    layerInd, layerSym, portInd, portSym, dftInputSym, dmrsInd, dmrsSym, ptrsInd, ptrsSym, ...
    carrier, pusch, codingLayouts, resourceAccounting, prec, precodePowerInfo, codewordLayerMapping, phyGrant, hasPHYGrant)
ctx = struct();
ctx.ContractVersion = "PUSCH_TxContext/v1";
ctx.GrantDriven = logical(hasPHYGrant);
ctx.GrantContextId = string(sixgr.util.structGet(phyGrant, "GrantContextId", ""));
trBlkCells = localCellify(trBlk);
tbCrcCells = localCellify(tbCrc);
ctx.TransportBlocks = cellfun(@(x) int8(x(:)), trBlkCells, "UniformOutput", false);
ctx.TransportBlockCRCs = cellfun(@(x) int8(x(:)), tbCrcCells, "UniformOutput", false);
ctx.TransportBlock = ctx.TransportBlocks{1};
ctx.TransportBlockCRC = ctx.TransportBlockCRCs{1};
if ~iscell(codewords)
    codewords = {codewords};
end
if ~iscell(codingLayouts)
    codingLayouts = {codingLayouts};
end
ctx.Codewords = cell(size(codewords));
for c = 1:numel(codewords)
    ctx.Codewords{c} = int8(codewords{c}(:));
end
ctx.Codeword = ctx.Codewords{1};
ctx.CodingLayouts = codingLayouts;
ctx.CodingLayout = codingLayouts{1};
ctx.CodewordLayerMapping = codewordLayerMapping;
ctx.DFTInputSymbols = dftInputSym;
ctx.LayerSymbols = layerSym;
ctx.LayerIndices = layerInd;
ctx.PortSymbols = portSym;
ctx.PortIndices = portInd;
ctx.DMRSSymbols = dmrsSym;
ctx.DMRSIndices = dmrsInd;
ctx.PTRSSymbols = ptrsSym;
ctx.PTRSIndices = ptrsInd;
if isfield(tx, "PTRSWaveformIndices")
    ctx.PTRSWaveformIndices = tx.PTRSWaveformIndices;
    ctx.PTRSWaveformSymbols = tx.PTRSWaveformSymbols;
end
if isfield(tx, "PTRSWaveformMapping")
    ctx.PTRSWaveformMapping = tx.PTRSWaveformMapping;
end
ctx.PortGrid = txGrid;
ctx.Waveform = txWaveform;
ctx.Precoder = prec.MatrixPorts;
ctx.Precoding = prec;
ctx.PowerNormalization = precodePowerInfo;
ctx.ResourceAccounting = resourceAccounting;
ctx.Carrier = struct( ...
    "NCellID", double(localObjectValue(carrier, "NCellID", NaN)), ...
    "NSizeGrid", double(localObjectValue(carrier, "NSizeGrid", NaN)), ...
    "SubcarrierSpacing", double(localObjectValue(carrier, "SubcarrierSpacing", NaN)), ...
    "CyclicPrefix", string(localObjectValue(carrier, "CyclicPrefix", "")), ...
    "NSlot", double(localObjectValue(carrier, "NSlot", NaN)));
ctx.PUSCH = struct( ...
    "PRBSet", double(localObjectValue(pusch, "PRBSet", [])), ...
    "SymbolAllocation", double(localObjectValue(pusch, "SymbolAllocation", [])), ...
    "MappingType", string(localObjectValue(pusch, "MappingType", "")), ...
    "Modulation", string(localObjectValue(pusch, "Modulation", "")), ...
    "NumLayers", double(localObjectValue(pusch, "NumLayers", NaN)), ...
    "NumAntennaPorts", double(localObjectValue(pusch, "NumAntennaPorts", NaN)), ...
    "TransmissionScheme", string(localObjectValue(pusch, "TransmissionScheme", "")), ...
    "TransformPrecoding", logical(localObjectValue(pusch, "TransformPrecoding", false)), ...
    "RNTI", double(localObjectValue(pusch, "RNTI", NaN)), ...
    "NID", double(localObjectValue(pusch, "NID", NaN)));
ctx.DimensionContract = struct( ...
    "LayerDataRE", double(resourceAccounting.LayerDataRE), ...
    "PortIndexCellCount", double(numel(portInd)), ...
    "QAMSymbolCount", double(numel(dftInputSym)), ...
    "DFTInputSymbolCount", double(numel(dftInputSym)), ...
    "LayerRESymbolCount", double(numel(layerSym)), ...
    "NumCodewords", double(codewordLayerMapping.NumCodewords), ...
    "RateMatchedBitCount", double(sum(codewordLayerMapping.RateMatchedBitCountPerCodeword)), ...
    "RateMatchedBitCountPerCodeword", double(codewordLayerMapping.RateMatchedBitCountPerCodeword), ...
    "LayerIndexCellCount", double(numel(layerInd)), ...
    "PortSymbolCount", double(numel(portSym)), ...
    "GridSize", double(size(txGrid)), ...
    "WaveformSize", double(size(txWaveform)));
if isfield(tx, "LayerSymbolOrder")
    ctx.LayerSymbolOrder = tx.LayerSymbolOrder;
end
if isfield(tx, "PortSymbolOrder")
    ctx.PortSymbolOrder = tx.PortSymbolOrder;
end
end

function value = localPositiveIntegerValue(raw, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value > 0 && abs(value - round(value)) < 1e-9)
    error("sixgr:phy:ul:PUSCHBadInteger", "%s must be a positive integer scalar.", char(string(name)));
end
value = round(value);
end

function value = localNonnegativeIntegerValue(raw, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value >= 0 && abs(value - round(value)) < 1e-9)
    error("sixgr:phy:ul:PUSCHBadInteger", "%s must be a non-negative integer scalar.", char(string(name)));
end
value = round(value);
end

function value = localFirstFiniteScalarValue(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
        continue;
    end
    raw = double(raw(:));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function localAssertSameVector(actual, expected, id, message)
expected = double(expected(:).');
actual = double(actual(:).');
if isempty(expected)
    return;
end
if numel(actual) ~= numel(expected) || any(abs(actual - expected) > 1e-9)
    error(id, "%s Actual=%s Expected=%s.", message, mat2str(actual), mat2str(expected));
end
end

function localAssertSameScalar(actual, expected, id, message)
actual = double(actual);
expected = double(expected);
if ~(isscalar(expected) && isfinite(expected))
    return;
end
if ~(isscalar(actual) && isfinite(actual) && abs(actual - expected) <= 1e-9)
    error(id, "%s Actual=%.15g Expected=%.15g.", message, actual, expected);
end
end

function value = localMaxAbs(x)
if isempty(x)
    value = 0;
else
    value = max(abs(x(:)));
end
end

function values = localIndexSet(ind)
values = [];
if isempty(ind)
    return;
end
values = unique(double(ind(:)));
values = values(isfinite(values));
end

function symAlloc = localResolveSymbolAllocation(pusch)
try
    rawSymAlloc = double(pusch.SymbolAllocation);
catch
    rawSymAlloc = [];
end
if isempty(rawSymAlloc)
    symAlloc = [NaN NaN];
elseif numel(rawSymAlloc) < 2
    symAlloc = [double(rawSymAlloc(1)) NaN];
else
    symAlloc = reshape(double(rawSymAlloc(1:2)), 1, 2);
end
end

function localAssertRateMatchMapAgreement(rateMatchInfo, codingLayout)
txMap = sixgr.util.structGet(rateMatchInfo, "PositionMap", struct());
layoutMap = sixgr.util.structGet(codingLayout, "RateMatchPositionMap", struct());
txIdx = sixgr.util.structGet(txMap, "MotherCodeLinearIndex", []);
layoutIdx = sixgr.util.structGet(layoutMap, "MotherCodeLinearIndex", []);
if isempty(txIdx) || isempty(layoutIdx) || numel(txIdx) ~= numel(layoutIdx) || any(uint32(txIdx(:)) ~= uint32(layoutIdx(:)))
    error("sixgr:phy:ul:PUSCHCodingLayoutMapMismatch", ...
        "PUSCH rate-match position map does not match canonical CodingLayout.");
end
end

function [puschSym, ptrsSym, puschSymInfo] = localModulatePUSCH(carrier, pusch, codeword)
puschSymInfo = struct();
[puschSym, ptrsSym] = nrPUSCH(carrier, pusch, codeword);
end

function layerInd = localLayerIndicesFromPortIndices(portInd, layerSym)
layerSym = localEnsure2D(layerSym);
nRows = size(layerSym, 1);
nLayers = size(layerSym, 2);
if isempty(portInd) || isempty(layerSym)
    layerInd = zeros(size(layerSym));
    return;
end
if size(portInd, 1) == nRows && size(portInd, 2) >= nLayers
    layerInd = portInd(:, 1:nLayers);
    return;
end
if numel(portInd) == numel(layerSym)
    layerInd = reshape(portInd, size(layerSym));
    return;
end
error("sixgr:phy:ul:PUSCHLayerIndexDomainMismatch", ...
    "Cannot attach layer-domain ordering map: index shape %s does not match layer-symbol shape %s.", ...
    mat2str(size(portInd)), mat2str(size(layerSym)));
end

function x = localEnsure2D(x)
if isempty(x)
    x = complex(zeros(0, 1));
    return;
end
if isvector(x)
    x = x(:);
end
end

function value = localObjectValue(obj, propName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    if isobject(obj) && isprop(obj, char(propName))
        raw = obj.(char(propName));
    elseif isstruct(obj) && isfield(obj, char(propName))
        raw = obj.(char(propName));
    else
        return;
    end
catch
    return;
end
if ~isempty(raw)
    value = raw;
end
end

function pusch = localEnsureTransformPrecodingOwnership(pusch, cfg)
try
    modToken = upper(strrep(char(string(pusch.Modulation)), ' ', ''));
catch
    error("sixgr:phy:ul:PUSCHMissingModulation", ...
        "An explicit PUSCH modulation is required.");
end
try
    runtimeValue = logical(pusch.TransformPrecoding);
catch ME
    error("sixgr:phy:ul:PUSCHTransformPrecodingUnavailable", ...
        "The runtime PUSCH object does not expose TransformPrecoding: %s", ME.message);
end
if (strcmp(modToken, 'PI/2-BPSK') || strcmp(modToken, 'PI2-BPSK')) && ~runtimeValue
    error("sixgr:phy:ul:PI2BPSKRequiresTransformPrecoding", ...
        "PI/2-BPSK requires TransformPrecoding=true; the transmitter will not silently change the configured waveform.");
end
configuredValue = sixgr.util.structGet(cfg, 'phy.pusch.transformPrecoding', []);
if ~isempty(configuredValue) && logical(configuredValue) ~= runtimeValue
    error("sixgr:phy:ul:PUSCHTransformPrecodingOwnershipMismatch", ...
        "Runtime TransformPrecoding=%d does not match configured phy.pusch.transformPrecoding=%d.", ...
        runtimeValue, logical(configuredValue));
end
end

function source = localTransformPrecodingSource(pusch, cfg)
source = "disabled";
try
    if logical(pusch.TransformPrecoding)
        source = "nrPUSCH_native_transform_precoding";
    end
catch
end
if source == "disabled" && logical(sixgr.util.structGet(cfg, 'phy.pusch.transformPrecoding', false))
    source = "configured_but_not_runtime_applied";
end
end

function blocks = localResolveTransportBlockCells(raw, sizes)
sizes = double(sizes(:).');
nCodewords = numel(sizes);
if isempty(raw)
    blocks = cell(1, nCodewords);
    for cw = 1:nCodewords
        blocks{cw} = int8(randi([0 1], sizes(cw), 1));
    end
elseif iscell(raw)
    blocks = reshape(raw, 1, []);
else
    blocks = {raw};
end
if numel(blocks) ~= nCodewords
    error("PUSCH_Tx:BadTBSize", ...
        "TransportBlockBits must provide one bit vector per codeword.");
end
for cw = 1:nCodewords
    bits = double(blocks{cw}(:));
    if numel(bits) ~= sizes(cw)
        error("PUSCH_Tx:BadTBSize", ...
            "Codeword %d transport block has %d bits; expected %d.", ...
            cw - 1, numel(bits), sizes(cw));
    end
    if any(~isfinite(bits) | (bits ~= 0 & bits ~= 1))
        error("sixgr:pusch:InvalidTransportBlock", ...
            "Codeword %d transport block must be binary.", cw - 1);
    end
    blocks{cw} = int8(bits);
end
end

function value = localUnwrapSingleCell(cells)
if iscell(cells) && isscalar(cells)
    value = cells{1};
else
    value = cells;
end
end

function cells = localCellify(value)
if iscell(value)
    cells = reshape(value, 1, []);
else
    cells = {value};
end
end

function value = localModulationAt(raw, index)
if iscell(raw)
    value = char(string(raw{index}));
else
    values = string(raw);
    value = char(values(index));
end
end

function grid = localMapToGrid(grid, ind, sym)
if isempty(ind) || isempty(sym)
    return;
end

% First try strict one-to-one linear mapping.
try
    indLin = ind(:);
    symLin = sym(:);
    if numel(indLin) == numel(symLin)
        grid(indLin) = symLin;
        return;
    end
catch
end

% If indices are NxM but symbols are Nx1, use first column.
if isnumeric(ind) && size(ind,1) == numel(sym(:)) && size(ind,2) >= 1
    grid(ind(:,1)) = sym(:);
    return;
end

% Reference generators can return zero-filled inactive port columns while
% the index generator returns only active reference-port columns.
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

indLin = ind(:);
symLin = sym(:);
error('sixgr:phy:ul:PUSCHGridMappingMismatch', ...
    ['PUSCH grid mapping requires one symbol per resource element. ' ...
     'IndexCount=%d SymbolCount=%d IndexShape=%s SymbolShape=%s.'], ...
    numel(indLin), numel(symLin), mat2str(size(ind)), mat2str(size(sym)));
end

function [dmrsSym, info] = localApplyPUSCHDMRSEPREDifference(dmrsSym, cfg)
% The configured quantity follows the conformance-table convention:
%   data EPRE / DM-RS EPRE in dB = data EPRE - DM-RS EPRE.
path = "phy.pusch.dmrs.dataToDMRSEPREDifference_dB";
rawDifference = sixgr.util.structGet(cfg, char(path), []);
if isempty(rawDifference)
    difference_dB = 0;
    source = "default_zero_db";
else
    if ~(isnumeric(rawDifference) && isreal(rawDifference) && isscalar(rawDifference) && isfinite(rawDifference))
        error("sixgr:phy:ul:PUSCHDMRSEPREDifferenceInvalid", ...
            "%s must be a finite real numeric scalar.", char(path));
    end
    difference_dB = double(rawDifference);
    source = path;
end

configuredPowerBoost_dB = -difference_dB;
if abs(difference_dB + 3) <= 1e-12
    % TS 38.104 expresses the normative PUSCH-to-DMRS EPRE ratio as
    % -3 dB while the corresponding exact beta is sqrt(2).
    amplitudeScale = sqrt(2);
    powerScale = 2;
    scalePolicy = "ts_38_104_minus3_db_beta_sqrt2";
else
    amplitudeScale = 10.^(configuredPowerBoost_dB ./ 20);
    powerScale = amplitudeScale.^2;
    scalePolicy = "literal_configured_db_ratio";
end
if ~(isfinite(amplitudeScale) && amplitudeScale > 0 && isfinite(powerScale) && powerScale > 0)
    error("sixgr:phy:ul:PUSCHDMRSEPREDifferenceInvalid", ...
        "%s=%g dB produces a non-finite or non-positive DM-RS scale.", ...
        char(path), difference_dB);
end
realizedPowerBoost_dB = 10 .* log10(powerScale);
realizedDifference_dB = -realizedPowerBoost_dB;

dmrsSym = dmrsSym .* cast(amplitudeScale, "like", dmrsSym);
info = struct( ...
    "ContractVersion", "PUSCHDMRSEPREDifference/v1", ...
    "Source", source, ...
    "DataToDMRSEPREDifference_dB", double(difference_dB), ...
    "ConfiguredDMRSPowerBoost_dB", double(configuredPowerBoost_dB), ...
    "RealizedDataToDMRSEPREDifference_dB", double(realizedDifference_dB), ...
    "DMRSPowerBoost_dB", double(realizedPowerBoost_dB), ...
    "DMRSAmplitudeScale", double(amplitudeScale), ...
    "DMRSPowerScale", double(powerScale), ...
    "Applied", logical(abs(difference_dB) > 1e-12), ...
    "NormativeMinus3dBBetaApplied", logical(scalePolicy == "ts_38_104_minus3_db_beta_sqrt2"), ...
    "ScalePolicy", scalePolicy, ...
    "Equation", "normative_minus3_db_uses_beta_sqrt2_otherwise_10_power_minus_delta_db_over_20");
end
