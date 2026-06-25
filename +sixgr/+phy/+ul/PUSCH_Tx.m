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
ip.addParameter('TransportBlockBits', [], @(x) isempty(x) || isnumeric(x) || islogical(x));
ip.addParameter('TransportBlockSizeOverride', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
ip.addParameter('RV', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0 && x<=3));
ip.addParameter('TargetCodeRate', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0 && x<1));
ip.addParameter('XOverhead', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
ip.addParameter('NumTxAnt', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('HARQACKBits', [], @(x) isempty(x) || isnumeric(x) || islogical(x));
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
rv = localResolvePUSCHRV(cfg, opt.RV, phyGrant, hasPHYGrant);
targetCodeRate = localResolvePUSCHTargetCodeRate(cfg, opt.TargetCodeRate, phyGrant, hasPHYGrant);
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
    "TargetCodeRate", targetCodeRate, ...
    "XOverhead", xOverhead);
localAssertPUSCHResourceAccounting(resourceAccounting, pusch, hasPHYGrant);
puschInfo.ResourceAccounting = resourceAccounting;
puschInfo.LayerDataRE = resourceAccounting.LayerDataRE;
puschInfo.PortMappedRE = resourceAccounting.PortMappedRE;
puschInfo.ModulationSymbolCount = resourceAccounting.ModulationSymbolCount;
puschInfo.CodedBitCountG = resourceAccounting.CodedBitCountG;
puschInfo.G = resourceAccounting.CodedBitCountG;
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
if isempty(opt.TransportBlockBits)
    trBlk = int8(randi([0 1], trBlkSize, 1));
else
    trBlk = opt.TransportBlockBits;
    trBlk = int8(trBlk(:));
    if numel(trBlk) ~= trBlkSize
        error('PUSCH_Tx:BadTBSize', 'TransportBlockBits length %d does not match expected TBS %d.', numel(trBlk), trBlkSize);
    end
end

G = double(resourceAccounting.CodedBitCountG);
if ~(isfinite(G) && G > 0)
    error('sixgr:phy:ul:PUSCHNoDataRE', ...
        'PUSCH rate matching has no positive data-bit budget: PRBs=%d SymbolAllocation=%s Modulation=%s Layers=%d.', ...
        round(double(nPRB)), mat2str(localResolveSymbolAllocation(pusch)), char(string(pusch.Modulation)), round(double(pusch.NumLayers)));
end
harqAckBits = localNormalizeHARQACKBits(opt.HARQACKBits);
oack = numel(harqAckBits);
[dataBitBudgetG, uciInfo] = localResolvePUSCHUCIBitBudget(pusch, targetCodeRate, trBlkSize, G, harqAckBits);
codingLayout = localResolveTxCodingLayout(phyGrant, hasPHYGrant, trBlkSize, targetCodeRate, rv, pusch, dataBitBudgetG);
tbCRCType = char(codingLayout.TBCRCType);
tbCRCLen = double(codingLayout.TBCRCLength);
bgn = double(codingLayout.BaseGraph);

% ---------------------- UL-SCH encoding (modular blocks) ----------------------
% Match the TB CRC selected by nrULSCHInfo for this transport block size.
tbCrc = sixgr.phy.tb.attachCRC(trBlk, tbCRCType);
crcInfo = struct("Type", string(tbCRCType), "Length", double(tbCRCLen));
B = numel(tbCrc);

% Code block segmentation
[cbs, segInfo] = sixgr.phy.tb.segmentLDPC(tbCrc, bgn);

% LDPC encode all code blocks in one toolbox call to avoid repeated
% per-code-block MATLAB loop overhead.
ldpcEnc = int8(sixgr.phy.phycode.ldpcEncode(cbs, bgn));

% Rate match to G bits
if oack > 0
    [ulSchCodeword, rateMatchInfo] = sixgr.phy.phycode.rateMatchLDPC(ldpcEnc, dataBitBudgetG, rv, pusch.Modulation, pusch.NumLayers);
    codedAck = nrUCIEncode(harqAckBits, double(uciInfo.GACK), pusch.Modulation);
    [codeword, muxInfo] = nrULSCHMultiplex(pusch, targetCodeRate, trBlkSize, ulSchCodeword(:), codedAck(:), [], []);
    codeword = int8(codeword(:));
    uciInfo.UCIOnPUSCHApplied = true;
    uciInfo.MultiplexInfo = muxInfo;
    uciInfo.Source = "nrULSCHMultiplex_ts38212_6_2_7_harq_ack_on_pusch";
else
    [codeword, rateMatchInfo] = sixgr.phy.phycode.rateMatchLDPC(ldpcEnc, G, rv, pusch.Modulation, pusch.NumLayers);
end
codeword = int8(codeword(:));
dataRateMatchedBits = double(sixgr.util.structGet(rateMatchInfo, "E", numel(codeword)));
localAssertRateMatchMapAgreement(rateMatchInfo, codingLayout);

% ---------------------- PUSCH modulation & mapping ----------------------
[puschSym, ptrsSym, puschSymInfo] = localModulatePUSCH(carrier, pusch, codeword);
[puschLayerSym, dftInputSym, puschDomainInfo] = localResolvePUSCHSymbolDomains(carrier, pusch, codeword, puschSym, prec);
localAssertPUSCHSymbolContract(codeword, dftInputSym, puschLayerSym, puschSym, puschInd, resourceAccounting, pusch, codingLayout, uciInfo);
puschLayerInd = localLayerIndicesFromPortIndices(puschInd, puschLayerSym);
puschLayerOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, puschLayerInd, "layer");
puschPortOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, puschInd, "port");

% DMRS
[dmrsInd, dmrsSym] = sixgr.phy.refsig.dmrsPUSCH(carrier, pusch);

% PTRS (optional)
ptrsInd = [];
if ~isempty(ptrsSym)
    ptrsInd = nrPUSCHPTRSIndices(carrier, pusch, "IndexBase", "1based");
end
localAssertSignalResourceDisjoint(puschInd, dmrsInd, ptrsInd);

% Build resource grid and map
% Use grid pages that cover the indices returned by nrPUSCHIndices
nPages = max([size(puschInd,2), size(dmrsInd,2), size(ptrsInd,2), numTxAnt, 1]);
try
    txGrid = nrResourceGrid(carrier, nPages);
catch
    txGrid = complex(zeros(carrier.NSizeGrid*12, carrier.SymbolsPerSlot, nPages));
end

% Map PUSCH
txGrid = localMapToGrid(txGrid, puschInd, puschSym);

% Map DMRS/PTRS
if ~isempty(dmrsInd)
    txGrid = localMapToGrid(txGrid, dmrsInd, dmrsSym);
end
if ~isempty(ptrsInd)
    txGrid = localMapToGrid(txGrid, ptrsInd, ptrsSym);
end
precodePowerInfo = localBuildPUSCHPowerInfo(puschLayerSym, puschSym, prec);

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
if hasPHYGrant
    tx.PHYGrant = phyGrant;
    tx.PHYGrantDimensionContract = phyGrantContract;
end
tx.TransportBlockSize = trBlkSize;
tx.ScheduledTransportBlockSize = scheduledTrBlkSize;
tx.TransportBlockSizeSource = transportBlockSizeSource;
tx.TransportBlock = trBlk;
tx.TransportBlockCRCType = char(tbCRCType);
tx.TransportBlockCRCLength = double(tbCRCLen);
tx.TransportBlockLenWithCRC = B;
tx.RV = rv;
tx.TargetCodeRate = targetCodeRate;
tx.CodingLayout = codingLayout;
tx.Carrier = carrier;
tx.PUSCH = pusch;
tx.PUSCHIndices = puschInd;
tx.PUSCHSymbolsForEvidence = puschLayerSym;
tx.PUSCHLayerSymbolsForEvidence = puschLayerSym;
tx.PUSCHPortSymbolsForEvidence = puschSym;
tx.PUSCHLayerSymbols = puschLayerSym;
tx.PUSCHPortSymbols = puschSym;
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
tx.ResourceAccounting = resourceAccounting;
tx.PrecodeInfo = prec;
tx.PrecodePowerInfo = precodePowerInfo;
tx.NumWaveformColumns = double(size(txWaveform, 2));
tx.UEPhysicalTxAntennas = double(uePhysicalTxAnt);
tx.SymbolDomainInfo = puschDomainInfo;
tx.UCIOnPUSCHApplied = logical(uciInfo.UCIOnPUSCHApplied);
tx.HARQACKBitCount = double(uciInfo.HARQACKBitCount);
tx.HARQACKBits = harqAckBits;
tx.UCIOnPUSCHSource = char(string(uciInfo.Source));
tx.OFDMWindowingSamples = double(windowingSamples);
tx.OFDMWindowingSource = char(string(windowingInfo.OFDMWindowingSource));
tx.OFDMWindowingEnabled = logical(windowingInfo.OFDMWindowingEnabled);
if ~logical(opt.CompactOutput)
    tx.Grid = txGrid;
    tx.TransportBlockCRC = tbCrc;
    tx.BaseGraph = bgn;
    tx.Codeword = codeword;
    tx.PUSCHInfo = puschInfo;
    tx.PUSCHSymbols = puschLayerSym;
    tx.DFTInputSymbols = dftInputSym;
    tx.DMRSIndices = dmrsInd;
    tx.DMRSSymbols = dmrsSym;
    tx.PTRSIndices = ptrsInd;
    tx.PTRSSymbols = ptrsSym;
    tx.PUSCHAntennaIndices = puschInd;
    tx.PUSCHAntennaSymbols = puschSym;
    tx.DMRSAntennaIndices = dmrsInd;
    tx.DMRSAntennaSymbols = dmrsSym;
end

info = struct();
info.CarrierInfo = cinfo;
info.CRC = crcInfo;
info.Segmentation = segInfo;
info.RateMatch = rateMatchInfo;
info.CodingLayout = codingLayout;
info.PUSCHSymbols = puschSymInfo;
info.SymbolDomain = puschDomainInfo;
info.OFDM = ofdmInfo;
info.OFDMWindowing = windowingInfo;
info.Precoding = prec;
info.PrecodePowerInfo = precodePowerInfo;
info.NumWaveformColumns = double(size(txWaveform, 2));
info.UEPhysicalTxAntennas = double(uePhysicalTxAnt);
info.UCIOnPUSCH = uciInfo;
info.TransformPrecodingAppliedBy = localTransformPrecodingSource(pusch, cfg);
info.XOverhead = double(xOverhead);
info.ResourceAccounting = resourceAccounting;
info.TxContext = localBuildTxContext(tx, trBlk, tbCrc, codeword, txGrid, txWaveform, ...
    puschLayerInd, puschLayerSym, puschInd, puschSym, dftInputSym, ...
    dmrsInd, dmrsSym, ptrsInd, ptrsSym, carrier, pusch, codingLayout, ...
    resourceAccounting, prec, precodePowerInfo, phyGrant, hasPHYGrant);
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
    sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.PMI", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.TPMI", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.PMI", []), NaN);
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

function rv = localResolvePUSCHRV(cfg, optRV, phyGrant, hasPHYGrant)
if ~isempty(optRV)
    rv = optRV;
elseif hasPHYGrant
    rv = localFirstFiniteScalarValue(sixgr.util.structGet(phyGrant, "HARQProcessKey.RV", []), ...
        sixgr.util.structGet(phyGrant, "CodingLayout.RV", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.rv", []), 0);
else
    rv = double(sixgr.util.structGet(cfg, 'phy.pusch.rv', 0));
end
rv = localNonnegativeIntegerValue(rv, "PUSCH RV");
if rv > 3
    error("sixgr:phy:ul:PUSCHBadRV", "PUSCH RV must be in [0,3].");
end
end

function targetCodeRate = localResolvePUSCHTargetCodeRate(cfg, optRate, phyGrant, hasPHYGrant)
grantRate = NaN;
if hasPHYGrant
    grantRate = double(sixgr.util.structGet(phyGrant, "CodingLayout.TargetCodeRate", NaN));
end
if isfinite(grantRate) && grantRate > 0
    if ~isempty(optRate) && abs(double(optRate) - grantRate) > 1e-12
        error("sixgr:phy:ul:PUSCHGrantCodeRateMismatch", ...
            "TargetCodeRate %.15g does not match frozen PHYGrant %.15g.", double(optRate), grantRate);
    end
    targetCodeRate = grantRate;
elseif ~isempty(optRate)
    targetCodeRate = double(optRate);
else
    targetCodeRate = double(sixgr.util.structGet(cfg, 'phy.pusch.codeRate', 0.4785));
end
if ~(isscalar(targetCodeRate) && isfinite(targetCodeRate) && targetCodeRate > 0 && targetCodeRate < 1)
    error("sixgr:phy:ul:PUSCHBadCodeRate", "PUSCH TargetCodeRate must be finite in (0,1).");
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
grantTBS = NaN;
if hasPHYGrant
    grantTBS = double(sixgr.util.structGet(phyGrant, "CodingLayout.TBSBits", NaN));
end
if isfinite(grantTBS) && grantTBS > 0
    trBlkSize = round(grantTBS);
    if abs(double(scheduledTrBlkSize) - double(trBlkSize)) > 0
        error("sixgr:phy:ul:PUSCHGrantTBSMismatch", ...
            "Frozen PHYGrant TBS=%d but exact nrTBS from the frozen resource contract is %d.", ...
            trBlkSize, round(double(scheduledTrBlkSize)));
    end
    if ~isempty(overrideTBS) && round(double(overrideTBS)) ~= trBlkSize
        error("sixgr:phy:ul:PUSCHReplayTBSMismatch", ...
            "TransportBlockSizeOverride=%d does not match frozen PHYGrant TBS=%d.", ...
            round(double(overrideTBS)), trBlkSize);
    end
    source = 'frozen_phygrant_transport_block_size';
elseif ~isempty(overrideTBS)
    trBlkSize = round(double(overrideTBS));
    source = 'harq_replay_stored_transport_block';
elseif hasPHYGrant
    trBlkSize = round(double(scheduledTrBlkSize));
    source = 'nrTBS_from_frozen_phygrant_resource_accounting';
else
    trBlkSize = round(double(scheduledTrBlkSize));
    source = 'nrTBS_from_current_allocation';
end
if ~(isfinite(trBlkSize) && trBlkSize > 0 && abs(trBlkSize - round(trBlkSize)) < 1e-9)
    error('PUSCH_Tx:BadReplayTBSize', 'PUSCH transport block size must be a positive finite integer.');
end
end

function [dataG, uciInfo] = localResolvePUSCHUCIBitBudget(pusch, targetCodeRate, trBlkSize, G, harqAckBits)
oack = numel(harqAckBits);
uciInfo = struct( ...
    "UCIOnPUSCHApplied", false, ...
    "HARQACKBitCount", double(oack), ...
    "HARQACKBits", harqAckBits, ...
    "GULSCH", double(G), ...
    "GACK", NaN, ...
    "GACKReserved", NaN, ...
    "Source", "no_uci_payload_requested");
dataG = double(G);
if oack == 0
    return;
end
if exist("nrULSCHMultiplex", "file") ~= 2
    error('sixgr:phy:ul:PUSCHUCIUnavailable', ...
        'HARQ-ACK on PUSCH requires nrULSCHMultiplex from 5G Toolbox.');
end
rmInfo = nrULSCHInfo(pusch, targetCodeRate, trBlkSize, oack, 0, 0);
gULSCH = double(rmInfo.GULSCH);
gACK = double(rmInfo.GACK);
if ~(isfinite(gULSCH) && gULSCH > 0 && isfinite(gACK) && gACK > 0)
    error('sixgr:phy:ul:PUSCHUCIInvalidAllocation', ...
        'PUSCH UCI multiplexing has invalid bit allocation: GULSCH=%g GACK=%g OACK=%d.', ...
        gULSCH, gACK, oack);
end
dataG = gULSCH;
uciInfo.GULSCH = gULSCH;
uciInfo.GACK = gACK;
uciInfo.GACKReserved = double(sixgr.util.structGet(rmInfo, "GACKRvd", NaN));
uciInfo.Source = "nrULSCHInfo_ts38212_6_2_7_harq_ack_on_pusch";
end

function codingLayout = localResolveTxCodingLayout(phyGrant, hasPHYGrant, trBlkSize, targetCodeRate, rv, pusch, G)
codingLayout = sixgr.phy.phycode.resolveCodingLayout( ...
    "Direction", "UL", ...
    "TransportBlockSize", trBlkSize, ...
    "TargetCodeRate", targetCodeRate, ...
    "RV", rv, ...
    "Modulation", pusch.Modulation, ...
    "NumLayers", pusch.NumLayers, ...
    "RateMatchedBitCount", G);
if hasPHYGrant
    localAssertCodingLayoutMatchesGrant(codingLayout, phyGrant);
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
        "PUSCH frozen grant has overlapping or duplicate data/DMRS/PTRS port-domain RE cells. BaseOverlapCount=%d.", ...
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

function [layerSym, dftInputSym, info] = localResolvePUSCHSymbolDomains(carrier, pusch, codeword, portSym, prec)
portSym = localEnsure2D(portSym);
nLayers = localPositiveIntegerValue(localObjectValue(pusch, "NumLayers", size(portSym, 2)), "PUSCH.NumLayers");
nPorts = localPositiveIntegerValue(localObjectValue(pusch, "NumAntennaPorts", max(size(portSym, 2), nLayers)), "PUSCH.NumAntennaPorts");
transformPrecoding = logical(localObjectValue(pusch, "TransformPrecoding", false));
scheme = lower(strtrim(string(localObjectValue(pusch, "TransmissionScheme", "nonCodebook"))));
isCodebook = scheme == "codebook";
dftInputSym = localScrambledLayerSymbols(pusch, codeword);
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

function dftInputSym = localScrambledLayerSymbols(pusch, codeword)
nid = double(localObjectValue(pusch, "NID", 0));
rnti = double(localObjectValue(pusch, "RNTI", 1));
scrambled = nrPUSCHScramble(codeword(:), nid, rnti);
modulated = nrSymbolModulate(scrambled(:), char(string(pusch.Modulation)));
dftInputSym = nrLayerMap(modulated, double(pusch.NumLayers));
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

function ctx = localBuildTxContext(tx, trBlk, tbCrc, codeword, txGrid, txWaveform, ...
    layerInd, layerSym, portInd, portSym, dftInputSym, dmrsInd, dmrsSym, ptrsInd, ptrsSym, ...
    carrier, pusch, codingLayout, resourceAccounting, prec, precodePowerInfo, phyGrant, hasPHYGrant)
ctx = struct();
ctx.ContractVersion = "PUSCH_TxContext/v1";
ctx.GrantDriven = logical(hasPHYGrant);
ctx.GrantContextId = string(sixgr.util.structGet(phyGrant, "GrantContextId", ""));
ctx.TransportBlock = int8(trBlk(:));
ctx.TransportBlockCRC = int8(tbCrc(:));
ctx.Codeword = int8(codeword(:));
ctx.CodingLayout = codingLayout;
ctx.DFTInputSymbols = dftInputSym;
ctx.LayerSymbols = layerSym;
ctx.LayerIndices = layerInd;
ctx.PortSymbols = portSym;
ctx.PortIndices = portInd;
ctx.DMRSSymbols = dmrsSym;
ctx.DMRSIndices = dmrsInd;
ctx.PTRSSymbols = ptrsSym;
ctx.PTRSIndices = ptrsInd;
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
    "RateMatchedBitCount", double(numel(codeword)), ...
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

function bits = localNormalizeHARQACKBits(rawBits)
if isempty(rawBits)
    bits = int8([]);
    return;
end
bits = int8(logical(rawBits(:)));
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
    modToken = upper(strrep(char(string(sixgr.util.structGet(cfg, 'phy.pusch.modulation', ''))), ' ', ''));
end
required = strcmp(modToken, 'PI/2-BPSK') || strcmp(modToken, 'PI2-BPSK') || ...
    logical(sixgr.util.structGet(cfg, 'phy.pusch.transformPrecoding', false));
if required
    try
        pusch.TransformPrecoding = true;
    catch ME
        error('sixgr:phy:ul:PUSCHTransformPrecodingUnavailable', ...
            'PUSCH requires TransformPrecoding=true for modulation/config but nrPUSCHConfig rejected it: %s', ME.message);
    end
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
