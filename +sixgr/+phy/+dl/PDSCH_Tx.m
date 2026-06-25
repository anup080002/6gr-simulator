function [tx, info] = PDSCH_Tx(cfg, varargin)
%PDSCH_Tx Generate a basic PDSCH transmission (DL-SCH -> PDSCH -> OFDM).
%
%   [TX,INFO] = sixgr.phy.dl.PDSCH_Tx(CFG) builds a carrier and PDSCH
%   allocation from CFG (plus safe defaults), generates or accepts a
%   transport block, performs LDPC-based DL-SCH encoding (CRC, segmentation,
%   LDPC encode, rate matching), maps PDSCH + DMRS (and optional PTRS) into
%   a resource grid, and returns an OFDM waveform.
%
%   The TB/coding blocks are factored so PDSCH and PUSCH can reuse them.
%
%   Name-Value options:
%     "Carrier"      : nrCarrierConfig override
%     "PDSCH"        : nrPDSCHConfig override
%     "TransportBlockBits" : column vector of bits (int8/double)
%     "TransportBlockSizeOverride" : stored HARQ TB size to preserve during replay
%     "RV"           : redundancy version (0..3)
%     "TargetCodeRate": code rate (0..1)
%     "XOverhead"    : xOverhead for nrTBS (default 0)
%     "NumTxAnt"     : number of TX antennas / mapped antenna ports
%     "PrecodingMatrix" : wideband PDSCH precoder, Nports-by-Nlayers or transpose
%     "PHYGrant"     : frozen canonical grant dimensional contract
%
%   Outputs:
%     TX.Waveform      : time-domain OFDM waveform
%     TX.Grid          : frequency-domain transmit resource grid; may contain
%                        more pages than the PDSCH port count when auxiliary
%                        runtime signals such as CSI-RS reserve additional
%                        transmit pages
%     TX.TransportBlock: original TB bits
%     TX.Codeword      : rate-matched codeword bits (pre-scramble)
%     TX.Carrier       : carrier config object
%     TX.PDSCH         : PDSCH config object
%     TX.PDSCHIndices  : linear indices for PDSCH mapping
%     TX.DMRSIndices   : linear indices for PDSCH DMRS mapping
%     TX.DMRSSymbols   : DMRS symbols
%     TX.PTRSIndices   : linear indices for PTRS mapping (maybe empty)
%     TX.PTRSSymbols   : PTRS symbols (maybe empty)
%     TX.PDSCHAntennaIndices : antenna-oriented PDSCH indices after precoding
%     TX.DMRSAntennaIndices  : antenna-oriented DMRS indices after precoding
%     TX.ResourceGridPortContract : truthful page-count provenance for the
%                        full transmit grid versus the PDSCH/DM-RS signals
%     TX.PrecodeInfo    : explicit precoding metadata / guard decisions
%
%   Notes:
%     * nrPDSCH internally performs scrambling using pdsch.NID / pdsch.RNTI.
%       Therefore, TX.Codeword is NOT scrambled here.
%     * This transmitter currently supports a single codeword only
%       (NumLayers <= 4). Unsupported higher-rank combinations error early.

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDSCH', [], @(x) isempty(x) || isobject(x));
ip.addParameter('TransportBlockBits', [], @(x) isempty(x) || isnumeric(x) || islogical(x));
ip.addParameter('TransportBlockSizeOverride', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
ip.addParameter('RV', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0 && x<=3));
ip.addParameter('TargetCodeRate', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0 && x<1));
ip.addParameter('XOverhead', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
ip.addParameter('NumTxAnt', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('PrecodingMatrix', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('PHYGrant', struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;
phyGrant = opt.PHYGrant;
hasPHYGrant = isstruct(phyGrant) && ~isempty(fieldnames(phyGrant));
if hasPHYGrant
    sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, "pdsch_tx_entry");
    cfg = sixgr.phy.grant.applyPHYGrantToConfig(cfg, phyGrant);
    opt.NumTxAnt = double(phyGrant.AntennaArchitecture.NumWaveformColumns);
    opt.PrecodingMatrix = double(phyGrant.PrecodingState.Matrix);
end
localGuardUnsupportedNumLayers(cfg, opt.PDSCH);

% Carrier
if isempty(opt.Carrier)
    [carrier, cinfo] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
    cinfo = struct();
end

% Allocation / PDSCH config
if isempty(opt.PDSCH)
    if hasPHYGrant
        [pdschInd, pdschInfo, pdsch] = localBuildPDSCHFromFrozenGrant(carrier, cfg, phyGrant);
    else
        [pdschInd, pdschInfo, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfg);
    end
else
    pdsch = opt.PDSCH;
    if hasPHYGrant
        localAssertExplicitPDSCHMatchesGrant(pdsch, phyGrant);
    end
    try
        [pdschInd, pdschInfo] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
    catch
        [pdschInd, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
    end
end

% PDSCH parameters
rv = localResolvePDSCHRV(cfg, opt.RV, phyGrant, hasPHYGrant);
targetCodeRate = localResolvePDSCHTargetCodeRate(cfg, opt.TargetCodeRate, phyGrant, hasPHYGrant);
xOverhead = localResolvePDSCHXOverheadExact(cfg, opt.XOverhead, phyGrant, hasPHYGrant, pdsch);

prec = sixgr.phy.dl.resolvePDSCHPrecoding(pdsch, cfg, ...
    "PrecodingMatrix", opt.PrecodingMatrix, ...
    "FixedReferenceMode", hasPHYGrant);

numTxAnt = localResolveNumTxAnt(cfg, opt.NumTxAnt, prec);
phyGrantContract = struct();
if hasPHYGrant
    phyGrantContract = sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, ...
        "pdsch_tx_before_waveform", ...
        "PDSCH", pdsch, ...
        "Precoding", prec, ...
        "NumTxAnt", numTxAnt);
end

% Transport block size
nPRB = numel(pdsch.PRBSet);
resourceAccounting = sixgr.phy.resource.computeResourceAccounting("PDSCH", carrier, pdsch, ...
    "ChannelIndices", pdschInd, ...
    "AllocationInfo", pdschInfo, ...
    "IndexBase", "1based", ...
    "TargetCodeRate", targetCodeRate, ...
    "XOverhead", xOverhead);
localAssertPDSCHResourceAccounting(resourceAccounting, pdsch, hasPHYGrant);
pdschInfo.ResourceAccounting = resourceAccounting;
pdschInfo.LayerDataRE = resourceAccounting.LayerDataRE;
pdschInfo.PortMappedRE = resourceAccounting.PortMappedRE;
pdschInfo.ModulationSymbolCount = resourceAccounting.ModulationSymbolCount;
pdschInfo.CodedBitCountG = resourceAccounting.CodedBitCountG;
pdschInfo.G = resourceAccounting.CodedBitCountG;
pdschInfo.NREPerPRB = resourceAccounting.NREPerPRBForTBS;
nrePerPRB = resourceAccounting.NREPerPRBForTBS;
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    error('sixgr:phy:dl:PDSCHNoDataRE', ...
        'PDSCH allocation has no schedulable data RE: PRBs=%d SymbolAllocation=%s Modulation=%s Layers=%d.', ...
        round(double(nPRB)), mat2str(localObjectValue(pdsch, "SymbolAllocation", [NaN NaN])), char(string(pdsch.Modulation)), round(double(pdsch.NumLayers)));
end
[trBlkSize, scheduledTrBlkSize, transportBlockSizeSource] = localResolvePDSCHTransportBlockSize( ...
    opt.TransportBlockSizeOverride, phyGrant, hasPHYGrant, pdsch, nPRB, nrePerPRB, targetCodeRate, xOverhead);

% Transport block bits
if isempty(opt.TransportBlockBits)
    trBlk = int8(randi([0 1], trBlkSize, 1));
else
    trBlk = opt.TransportBlockBits;
    trBlk = int8(trBlk(:));
    if numel(trBlk) ~= trBlkSize
        error('PDSCH_Tx:BadTBSize', 'TransportBlockBits length %d does not match expected TBS %d.', numel(trBlk), trBlkSize);
    end
end

G = double(resourceAccounting.CodedBitCountG);
if ~(isfinite(G) && G > 0)
    error('sixgr:phy:dl:PDSCHNoDataRE', ...
        'PDSCH rate matching has no positive data-bit budget: PRBs=%d SymbolAllocation=%s Modulation=%s Layers=%d.', ...
        round(double(nPRB)), mat2str(localObjectValue(pdsch, "SymbolAllocation", [NaN NaN])), char(string(pdsch.Modulation)), round(double(pdsch.NumLayers)));
end
codingLayout = localResolveTxCodingLayout(phyGrant, hasPHYGrant, trBlkSize, targetCodeRate, rv, pdsch, G);
tbCRCType = char(codingLayout.TBCRCType);
tbCRCLen = double(codingLayout.TBCRCLength);
bgn = double(codingLayout.BaseGraph);

% ---------------------- DL-SCH encoding (modular blocks) ----------------------
% Match the TB CRC selected by nrDLSCHInfo for this transport block size.
tbCrc = sixgr.phy.tb.attachCRC(trBlk, tbCRCType);
crcInfo = struct("Type", string(tbCRCType), "Length", double(tbCRCLen));
B = numel(tbCrc);

% Code block segmentation
[cbs, segInfo] = sixgr.phy.tb.segmentLDPC(tbCrc, bgn);

% LDPC encode all code blocks in one toolbox call to avoid repeated
% per-code-block MATLAB loop overhead.
ldpcEnc = int8(sixgr.phy.phycode.ldpcEncode(cbs, bgn));

% Rate match to G bits
[codeword, rateMatchInfo] = sixgr.phy.phycode.rateMatchLDPC(ldpcEnc, G, rv, pdsch.Modulation, pdsch.NumLayers);
codeword = int8(codeword(:));
localAssertRateMatchMapAgreement(rateMatchInfo, codingLayout);

% ---------------------- PDSCH modulation & mapping ----------------------
% nrPDSCH expects codewords as a cell array (up to 2 codewords)
codewords = {codeword};
codewordLayerMapping = localBuildPDSCHCodewordLayerContract(pdsch, codewords, {codingLayout}, resourceAccounting);

try
    [pdschSym, pdschSymInfo] = nrPDSCH(carrier, pdsch, codewords);
catch
    pdschSym = nrPDSCH(carrier, pdsch, codewords);
    pdschSymInfo = struct();
end
codewordLayerMapping = localFinalizePDSCHCodewordLayerContract(codewordLayerMapping, pdschSym);
localAssertPDSCHLayerSymbolContract(codewords, pdschSym, pdschInd, resourceAccounting, pdsch, {codingLayout}, codewordLayerMapping);

% DMRS
[dmrsInd, dmrsSym] = sixgr.phy.refsig.dmrsPDSCH(carrier, pdsch);

% PTRS (optional)
[ptrsInd, ptrsSym, ptrsInfo] = sixgr.phy.refsig.ptrsPDSCH(carrier, pdsch);

[csirsInd, csirsSym, csirsInfo, csirsCfg, csirsEvent] = localGenerateCSIRSRuntimeResource(carrier, cfg);

pdschAntInd = pdschInd;
pdschAntSym = pdschSym;
dmrsAntInd = dmrsInd;
dmrsAntSym = dmrsSym;
ptrsAntInd = ptrsInd;
ptrsAntSym = ptrsSym;
if prec.Active
    % Precode layer/reference-domain signals before the final antenna-port map.
    [pdschAntSym, pdschAntInd] = nrPDSCHPrecode(carrier, pdschSym, pdschInd, prec.MatrixNR);
    [dmrsAntSym, dmrsAntInd] = nrPDSCHPrecode(carrier, dmrsSym, dmrsInd, prec.MatrixNR);
    if ~isempty(ptrsInd)
        [ptrsAntSym, ptrsAntInd] = nrPDSCHPrecode(carrier, ptrsSym, ptrsInd, prec.MatrixNR);
    end
end
localAssertPortDomainContract(pdschSym, pdschInd, pdschAntSym, pdschAntInd, resourceAccounting, prec);
localAssertSignalResourceDisjoint(pdschAntInd, dmrsAntInd, ptrsAntInd);
pdschLayerOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, pdschInd, "layer");
pdschPortOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, pdschAntInd, "port");

% Build resource grid and map
nPages = max([size(pdschAntInd,2), size(dmrsAntInd,2), size(ptrsAntInd,2), size(csirsInd,2), ...
    double(sixgr.util.structGet(csirsEvent, "NumPorts", NaN)), numTxAnt, 1]);
try
    txGrid = nrResourceGrid(carrier, nPages);
catch
    txGrid = complex(zeros(carrier.NSizeGrid*12, carrier.SymbolsPerSlot, nPages));
end

txGrid = localMapToGrid(txGrid, pdschAntInd, pdschAntSym);

% Map DMRS/PTRS
if ~isempty(dmrsInd)
    txGrid = localMapToGrid(txGrid, dmrsAntInd, dmrsAntSym);
end
if ~isempty(ptrsAntInd)
    txGrid = localMapToGrid(txGrid, ptrsAntInd, ptrsAntSym);
end
if logical(sixgr.util.structGet(csirsEvent, "Scheduled", false)) && ~isempty(csirsInd)
    [collision, collisionWith] = localCSIRSResourceCollision(csirsInd, pdschAntInd, dmrsAntInd, ptrsAntInd);
    if collision
        csirsEvent.Transmitted = false;
        csirsEvent.RuntimeMaterializationStatus = "blocked_resource_collision";
        csirsEvent.Blocker = "csirs_re_collision_with_" + collisionWith;
    else
        txGrid = localMapToGrid(txGrid, csirsInd, csirsSym);
        csirsEvent.Transmitted = true;
        csirsEvent.RuntimeMaterializationStatus = "runtime_grid_mapped";
        csirsEvent.UpdateOutcome = "transmitted_on_dl_resource_grid";
    end
end

gridPortContract = localBuildResourceGridPortContract(txGrid, pdschAntInd, pdschAntSym, ...
    dmrsAntInd, dmrsAntSym, ptrsAntInd, ptrsAntSym, csirsInd, csirsSym, csirsEvent, numTxAnt, prec);
localValidateResourceGridPortContract(gridPortContract, prec);
precodePowerInfo = localBuildPrecodePowerInfo(pdschSym, pdschAntSym, prec);

% OFDM modulation
[windowingSamples, windowingInfo] = sixgr.phy.waveform.resolveOFDMWindowing(cfg, carrier);
[txWaveform, ofdmInfo] = sixgr.phy.waveform.ofdmModulate(carrier, txGrid, ...
    "Windowing", double(windowingSamples));
if hasPHYGrant
    phyGrantContract = sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, ...
        "pdsch_tx_after_waveform", ...
        "PDSCH", pdsch, ...
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
tx.PDSCH = pdsch;
tx.PDSCHIndices = pdschInd;
tx.PDSCHSymbolsForEvidence = pdschSym;
tx.PDSCHLayerSymbolsForEvidence = pdschSym;
tx.PDSCHPortSymbolsForEvidence = pdschAntSym;
tx.PDSCHLayerSymbols = pdschSym;
tx.PDSCHPortSymbols = pdschAntSym;
tx.PDSCHLayerIndices = pdschInd;
tx.PDSCHPortIndices = pdschAntInd;
tx.LayerSymbolOrder = pdschLayerOrder;
tx.PortSymbolOrder = pdschPortOrder;
tx.LayerSymbolDomain = "layer";
tx.PortSymbolDomain = "port";
tx.XOverhead = double(xOverhead);
tx.G = G;
tx.NREPerPRB = double(nrePerPRB);
tx.LayerDataRE = double(resourceAccounting.LayerDataRE);
tx.PortMappedRE = double(resourceAccounting.PortMappedRE);
tx.ModulationSymbolCount = double(resourceAccounting.ModulationSymbolCount);
tx.QAMSymbolCount = double(numel(pdschSym));
tx.PortIndexCellCount = double(numel(pdschAntInd));
tx.RateMatchedBitCount = double(G);
tx.NumCodewords = double(codewordLayerMapping.NumCodewords);
tx.RateMatchedBitCountPerCodeword = double(codewordLayerMapping.RateMatchedBitCountPerCodeword);
tx.CodewordLayerMapping = codewordLayerMapping;
tx.ResourceAccounting = resourceAccounting;
tx.PrecodeInfo = prec;
tx.PrecodePowerInfo = precodePowerInfo;
tx.SymbolDomainInfo = struct( ...
    "ReferenceDomain", "layer", ...
    "PortDomain", "port", ...
    "Transform", "nrPDSCHPrecode_when_active", ...
    "NumLayers", double(pdsch.NumLayers), ...
    "NumPorts", double(size(pdschAntSym, 2)), ...
    "Status", "native_layer_symbols_and_port_grid_symbols", ...
    "Equation", "b_G_to_QAM_d_to_layers_S_to_ports_X_equals_S_times_W_transpose");
tx.OFDMWindowingSamples = double(windowingSamples);
tx.OFDMWindowingSource = char(string(windowingInfo.OFDMWindowingSource));
tx.OFDMWindowingEnabled = logical(windowingInfo.OFDMWindowingEnabled);
if ~logical(opt.CompactOutput)
    tx.Grid = txGrid;
    tx.TransportBlockCRC = tbCrc;
    tx.BaseGraph = bgn;
    tx.Codeword = codeword;
    tx.Codewords = codewords;
    tx.PDSCHInfo = pdschInfo;
    tx.PDSCHSymbols = pdschSym;
    tx.DMRSIndices = dmrsInd;
    tx.DMRSSymbols = dmrsSym;
    tx.PDSCHAntennaIndices = pdschAntInd;
    tx.PDSCHAntennaSymbols = pdschAntSym;
    tx.DMRSAntennaIndices = dmrsAntInd;
    tx.DMRSAntennaSymbols = dmrsAntSym;
    tx.PTRSIndices = ptrsInd;
    tx.PTRSSymbols = ptrsSym;
    tx.PTRSAntennaIndices = ptrsAntInd;
    tx.PTRSAntennaSymbols = ptrsAntSym;
    tx.CSIRSIndices = csirsInd;
    tx.CSIRSSymbols = csirsSym;
    tx.CSIRSInfo = csirsInfo;
    tx.CSIRS = csirsCfg;
    tx.CSIRSRuntimeEvent = csirsEvent;
    tx.ResourceGridPortContract = gridPortContract;
end
tx.TxContext = localBuildTxContext(tx, trBlk, tbCrc, codewords, txGrid, txWaveform, pdschInd, pdschSym, pdschAntInd, pdschAntSym, ...
    dmrsInd, dmrsSym, dmrsAntInd, dmrsAntSym, ptrsInd, ptrsSym, ptrsAntInd, ptrsAntSym, ...
    carrier, pdsch, {codingLayout}, resourceAccounting, prec, precodePowerInfo, codewordLayerMapping, phyGrant, hasPHYGrant);

info = struct();
info.CarrierInfo = cinfo;
info.CRC = crcInfo;
info.Segmentation = segInfo;
info.RateMatch = rateMatchInfo;
info.CodingLayout = codingLayout;
info.PDSCHSymbols = pdschSymInfo;
info.PTRS = ptrsInfo;
info.CSIRS = csirsInfo;
info.CSIRSRuntimeEvent = csirsEvent;
info.ResourceGridPortContract = gridPortContract;
info.OFDM = ofdmInfo;
info.OFDMWindowing = windowingInfo;
info.Precoding = prec;
info.PrecodePowerInfo = precodePowerInfo;
info.XOverhead = double(xOverhead);
info.ResourceAccounting = resourceAccounting;
info.CodewordLayerMapping = codewordLayerMapping;
info.TxContext = tx.TxContext;
if hasPHYGrant
    info.PHYGrant = phyGrant;
    info.PHYGrantDimensionContract = phyGrantContract;
end

end

function [pdschInd, pdschInfo, pdsch] = localBuildPDSCHFromFrozenGrant(carrier, cfg, phyGrant)
ra = sixgr.util.structGet(phyGrant, "ResourceAllocation", struct());
cl = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
pdschArgs = { ...
    "PRBSet", double(sixgr.util.structGet(ra, "PRBSet", [])), ...
    "SymbolAllocation", double(sixgr.util.structGet(ra, "SymbolAllocation", [])), ...
    "NumLayers", localPositiveIntegerValue(sixgr.util.structGet(cl, "NumLayers", 1), "PHYGrant.CodingLayout.NumLayers"), ...
    "Modulation", char(string(sixgr.util.structGet(cl, "Modulation", "QPSK"))), ...
    "RNTI", localResolveGrantRNTI(cfg, phyGrant), ...
    "NID", localResolveGrantNID(cfg, carrier), ...
    "MappingType", localResolveGrantMappingType(cfg, phyGrant), ...
    "FixedReferenceMode", true};
[pdschInd, pdschInfo, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfg, pdschArgs{:});
localAssertExplicitPDSCHMatchesGrant(pdsch, phyGrant);
end

function rnti = localResolveGrantRNTI(cfg, phyGrant)
rnti = localFirstFiniteScalarValue( ...
    sixgr.util.structGet(phyGrant, "ChannelStateKey.RNTI", []), ...
    sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.RNTI", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.RNTI", []), ...
    1);
rnti = localNonnegativeIntegerValue(rnti, "PDSCH RNTI");
end

function nid = localResolveGrantNID(cfg, carrier)
nid = sixgr.util.structGet(cfg, "phy.pdsch.NID", ...
    sixgr.util.structGet(cfg, "phy.pdsch.nid", []));
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
nid = localNonnegativeIntegerValue(nid, "PDSCH NID");
end

function mappingType = localResolveGrantMappingType(cfg, phyGrant)
mappingType = string(sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.MappingType", ""));
if strlength(strtrim(mappingType)) == 0
    mappingType = string(sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.mappingType", ""));
end
if strlength(strtrim(mappingType)) == 0
    mappingType = string(sixgr.util.structGet(cfg, "phy.pdsch.mappingType", "A"));
end
if strlength(strtrim(mappingType)) == 0
    mappingType = "A";
end
mappingType = upper(strtrim(mappingType));
end

function localAssertExplicitPDSCHMatchesGrant(pdsch, phyGrant)
ra = sixgr.util.structGet(phyGrant, "ResourceAllocation", struct());
cl = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
localAssertSameVector(localObjectValue(pdsch, "PRBSet", []), sixgr.util.structGet(ra, "PRBSet", []), ...
    "sixgr:phy:dl:PDSCHGrantPRBMismatch", "PDSCH PRBSet does not match frozen PHYGrant.");
localAssertSameVector(localObjectValue(pdsch, "SymbolAllocation", []), sixgr.util.structGet(ra, "SymbolAllocation", []), ...
    "sixgr:phy:dl:PDSCHGrantSymbolMismatch", "PDSCH SymbolAllocation does not match frozen PHYGrant.");
localAssertSameScalar(localObjectValue(pdsch, "NumLayers", NaN), sixgr.util.structGet(cl, "NumLayers", NaN), ...
    "sixgr:phy:dl:PDSCHGrantLayerMismatch", "PDSCH NumLayers does not match frozen PHYGrant.");
grantMod = char(string(sixgr.util.structGet(cl, "Modulation", "")));
pdschMod = char(string(localObjectValue(pdsch, "Modulation", "")));
if strlength(string(grantMod)) > 0 && ~strcmpi(strtrim(pdschMod), strtrim(grantMod))
    error("sixgr:phy:dl:PDSCHGrantModulationMismatch", ...
        "PDSCH Modulation '%s' does not match frozen PHYGrant '%s'.", pdschMod, grantMod);
end
grantRNTI = localFirstFiniteScalarValue(sixgr.util.structGet(phyGrant, "ChannelStateKey.RNTI", []), ...
    sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.RNTI", []), NaN);
if isfinite(grantRNTI)
    localAssertSameScalar(localObjectValue(pdsch, "RNTI", NaN), grantRNTI, ...
        "sixgr:phy:dl:PDSCHGrantRNTIMismatch", "PDSCH RNTI does not match frozen PHYGrant.");
end
grantMap = localResolveGrantMappingType(struct(), phyGrant);
if strlength(strtrim(grantMap)) > 0
    pdschMap = upper(strtrim(string(localObjectValue(pdsch, "MappingType", ""))));
    if strlength(pdschMap) > 0 && pdschMap ~= grantMap
        error("sixgr:phy:dl:PDSCHGrantMappingMismatch", ...
            "PDSCH MappingType '%s' does not match frozen PHYGrant '%s'.", char(pdschMap), char(grantMap));
    end
end
end

function rv = localResolvePDSCHRV(cfg, optRV, phyGrant, hasPHYGrant)
if ~isempty(optRV)
    rv = optRV;
elseif hasPHYGrant
    rv = localFirstFiniteScalarValue(sixgr.util.structGet(phyGrant, "HARQProcessKey.RV", []), ...
        sixgr.util.structGet(phyGrant, "CodingLayout.RV", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.rv", []), 0);
else
    rv = double(sixgr.util.structGet(cfg, 'phy.pdsch.rv', 0));
end
rv = localNonnegativeIntegerValue(rv, "PDSCH RV");
if rv > 3
    error("sixgr:phy:dl:PDSCHBadRV", "PDSCH RV must be in [0,3].");
end
end

function targetCodeRate = localResolvePDSCHTargetCodeRate(cfg, optRate, phyGrant, hasPHYGrant)
grantRate = NaN;
if hasPHYGrant
    grantRate = double(sixgr.util.structGet(phyGrant, "CodingLayout.TargetCodeRate", NaN));
end
if isfinite(grantRate) && grantRate > 0
    if ~isempty(optRate) && abs(double(optRate) - grantRate) > 1e-12
        error("sixgr:phy:dl:PDSCHGrantCodeRateMismatch", ...
            "TargetCodeRate %.15g does not match frozen PHYGrant %.15g.", double(optRate), grantRate);
    end
    targetCodeRate = grantRate;
elseif ~isempty(optRate)
    targetCodeRate = double(optRate);
else
    targetCodeRate = double(sixgr.util.structGet(cfg, 'phy.pdsch.codeRate', 0.4785));
end
if ~(isscalar(targetCodeRate) && isfinite(targetCodeRate) && targetCodeRate > 0 && targetCodeRate < 1)
    error("sixgr:phy:dl:PDSCHBadCodeRate", "PDSCH TargetCodeRate must be finite in (0,1).");
end
end

function xOverhead = localResolvePDSCHXOverheadExact(cfg, optXOverhead, phyGrant, hasPHYGrant, pdsch)
grantXOverhead = NaN;
if hasPHYGrant
    grantXOverhead = double(sixgr.util.structGet(phyGrant, "CodingLayout.XOverhead", NaN));
end
if isfinite(grantXOverhead) && grantXOverhead >= 0
    if ~isempty(optXOverhead) && abs(double(optXOverhead) - grantXOverhead) > 1e-12
        error("sixgr:phy:dl:PDSCHGrantXOverheadMismatch", ...
            "XOverhead %.15g does not match frozen PHYGrant %.15g.", double(optXOverhead), grantXOverhead);
    end
    xOverhead = grantXOverhead;
elseif ~isempty(optXOverhead)
    xOverhead = double(optXOverhead);
else
    xOverhead = sixgr.phy.dl.resolvePDSCHXOverhead(cfg, localObjectValue(pdsch, "SymbolAllocation", [0 14]));
end
if ~(isscalar(xOverhead) && isfinite(xOverhead) && xOverhead >= 0)
    error("sixgr:phy:dl:PDSCHBadXOverhead", "PDSCH XOverhead must be finite and non-negative.");
end
end

function [trBlkSize, scheduledTrBlkSize, source] = localResolvePDSCHTransportBlockSize( ...
    overrideTBS, phyGrant, hasPHYGrant, pdsch, nPRB, nrePerPRB, targetCodeRate, xOverhead)
scheduledTrBlkSize = double(nrTBS(pdsch.Modulation, pdsch.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead));
grantTBS = NaN;
if hasPHYGrant
    grantTBS = double(sixgr.util.structGet(phyGrant, "CodingLayout.TBSBits", NaN));
end
if isfinite(grantTBS) && grantTBS > 0
    trBlkSize = round(grantTBS);
    if abs(double(scheduledTrBlkSize) - double(trBlkSize)) > 0
        error("sixgr:phy:dl:PDSCHGrantTBSMismatch", ...
            "Frozen PHYGrant TBS=%d but exact nrTBS from the frozen resource contract is %d.", ...
            trBlkSize, round(double(scheduledTrBlkSize)));
    end
    if ~isempty(overrideTBS) && round(double(overrideTBS)) ~= trBlkSize
        error("sixgr:phy:dl:PDSCHReplayTBSMismatch", ...
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
    error('PDSCH_Tx:BadReplayTBSize', 'PDSCH transport block size must be a positive finite integer.');
end
end

function codingLayout = localResolveTxCodingLayout(phyGrant, hasPHYGrant, trBlkSize, targetCodeRate, rv, pdsch, G)
codingLayout = sixgr.phy.phycode.resolveCodingLayout( ...
    "Direction", "DL", ...
    "TransportBlockSize", trBlkSize, ...
    "TargetCodeRate", targetCodeRate, ...
    "RV", rv, ...
    "Modulation", pdsch.Modulation, ...
    "NumLayers", pdsch.NumLayers, ...
    "RateMatchedBitCount", G);
if hasPHYGrant
    localAssertCodingLayoutMatchesGrant(codingLayout, phyGrant);
end
end

function localAssertCodingLayoutMatchesGrant(codingLayout, phyGrant)
cl = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
localAssertSameScalar(double(codingLayout.A), sixgr.util.structGet(cl, "TBSBits", NaN), ...
    "sixgr:phy:dl:PDSCHCodingGrantTBSMismatch", "Canonical CodingLayout A does not match frozen PHYGrant TBSBits.");
localAssertSameScalar(double(codingLayout.NumLayers), sixgr.util.structGet(cl, "NumLayers", NaN), ...
    "sixgr:phy:dl:PDSCHCodingGrantLayerMismatch", "Canonical CodingLayout NumLayers does not match frozen PHYGrant.");
grantE = double(sixgr.util.structGet(cl, "RateMatchedBitCount", NaN));
if isfinite(grantE)
    localAssertSameScalar(double(codingLayout.RateMatchedBitCount), grantE, ...
        "sixgr:phy:dl:PDSCHCodingGrantGMismatch", "Canonical CodingLayout G does not match frozen PHYGrant.");
end
grantMod = string(sixgr.util.structGet(cl, "Modulation", ""));
if strlength(strtrim(grantMod)) > 0 && upper(strtrim(string(codingLayout.Modulation))) ~= upper(strtrim(grantMod))
    error("sixgr:phy:dl:PDSCHCodingGrantModulationMismatch", ...
        "Canonical CodingLayout modulation '%s' does not match frozen PHYGrant '%s'.", ...
        char(string(codingLayout.Modulation)), char(grantMod));
end
end

function localAssertPDSCHResourceAccounting(resourceAccounting, pdsch, fixedReferenceMode)
requiredInts = ["LayerDataRE", "PortMappedRE", "ModulationSymbolCount", "CodedBitCountG", "NREPerPRBForTBS"];
for i = 1:numel(requiredInts)
    name = char(requiredInts(i));
    value = double(resourceAccounting.(name));
    if ~(isscalar(value) && isfinite(value) && value > 0 && abs(value - round(value)) < 1e-9)
        error("sixgr:phy:dl:PDSCHResourceAccountingBadInteger", ...
            "PDSCH resource accounting field %s must be a positive integer. Got %.15g.", name, value);
    end
end
if ~logical(resourceAccounting.GMatchesLayerRE)
    error("sixgr:phy:dl:PDSCHResourceAccountingGMismatch", ...
        "PDSCH G=%d does not equal LayerDataRE=%d * Qm=%d * NumLayers=%d.", ...
        round(double(resourceAccounting.CodedBitCountG)), round(double(resourceAccounting.LayerDataRE)), ...
        round(double(resourceAccounting.Qm)), round(double(resourceAccounting.NumLayers)));
end
if logical(fixedReferenceMode) && ~logical(resourceAccounting.DisjointMasks)
    error("sixgr:phy:dl:PDSCHResourceAccountingOverlap", ...
        "PDSCH frozen grant has overlapping or duplicate data/DMRS/PTRS/reserved RE masks. OverlapCount=%d.", ...
        round(double(resourceAccounting.OverlapCount)));
end
if round(double(resourceAccounting.NumLayers)) ~= round(double(pdsch.NumLayers))
    error("sixgr:phy:dl:PDSCHResourceAccountingLayerMismatch", ...
        "PDSCH resource accounting NumLayers=%d but pdsch.NumLayers=%d.", ...
        round(double(resourceAccounting.NumLayers)), round(double(pdsch.NumLayers)));
end
end

function mapping = localBuildPDSCHCodewordLayerContract(pdsch, codewords, codingLayouts, resourceAccounting)
nLayers = localPositiveIntegerValue(localObjectValue(pdsch, "NumLayers", 1), "PDSCH.NumLayers");
nCodewords = localResolvePDSCHNumCodewords(pdsch, nLayers);
if nCodewords > 1 || nLayers > 4
    error("sixgr:phy:dl:PDSCHPrecoding:MultiCodewordUnsupported", ...
        "PDSCH truth TX supports one codeword for ranks 1-4. Requested NumLayers=%d NumCodewords=%d needs a two-codeword TB/coding contract.", ...
        nLayers, nCodewords);
end
if ~iscell(codewords)
    codewords = {codewords};
end
if ~iscell(codingLayouts)
    codingLayouts = {codingLayouts};
end
if numel(codewords) ~= nCodewords || numel(codingLayouts) ~= nCodewords
    error("sixgr:phy:dl:PDSCHCodewordContainerMismatch", ...
        "PDSCH codeword/coding-layout container count must equal NumCodewords=%d. Got %d codeword(s), %d layout(s).", ...
        nCodewords, numel(codewords), numel(codingLayouts));
end
rateBits = zeros(1, nCodewords);
layoutBits = zeros(1, nCodewords);
for c = 1:nCodewords
    rateBits(c) = double(numel(codewords{c}));
    layoutBits(c) = double(codingLayouts{c}.RateMatchedBitCount);
end
mapping = struct();
mapping.ContractVersion = "PDSCHCodewordLayer/v1";
mapping.Direction = "DL";
mapping.MappingStandard = "3GPP_TS_38_211_codeword_to_layer_mapping";
mapping.MappingEngine = "nrPDSCH_internal_nrLayerMap";
mapping.InverseEngine = "nrPDSCHDecode_internal_nrLayerDemap";
mapping.SupportedScope = "single_codeword_ranks_1_to_4";
mapping.UnsupportedScope = "two_codeword_ranks_5_to_8_require_two_transport_blocks_and_per_codeword_coding_layouts";
mapping.NumCodewords = double(nCodewords);
mapping.NumLayers = double(nLayers);
mapping.GrantNumLayers = double(nLayers);
mapping.CodewordIndexByLayer = ones(1, nLayers);
mapping.LayerIndexWithinCodeword = double(1:nLayers);
mapping.LayerCountPerCodeword = double(nLayers);
mapping.RateMatchedBitCountPerCodeword = double(rateBits);
mapping.CodingLayoutRateMatchedBitCountPerCodeword = double(layoutBits);
mapping.ResourceAccountingG = double(resourceAccounting.CodedBitCountG);
mapping.ExpectedLayerDataRE = double(resourceAccounting.LayerDataRE);
mapping.ExpectedLayerSymbolCount = double(resourceAccounting.LayerDataRE) * double(nLayers);
mapping.ActualLayerColumns = NaN;
mapping.ActualLayerSymbolCount = NaN;
mapping.ActualLayersEqualGrantLayers = false;
mapping.LayerColumnEnergy = NaN(1, nLayers);
mapping.AllLayerStreamsNonzero = false;
mapping.Equation = "b_G_c_to_QAM_d_c_to_layers_S_using_TS38211_7_3_1_3_then_ports_X_equals_S_times_W_transpose";
end

function mapping = localFinalizePDSCHCodewordLayerContract(mapping, layerSym)
if isempty(layerSym)
    nCols = 0;
    energy = zeros(1, 0);
else
    if isvector(layerSym)
        layerSym2D = layerSym(:);
    else
        layerSym2D = layerSym;
    end
    nCols = size(layerSym2D, 2);
    energy = sum(abs(layerSym2D).^2, 1);
end
mapping.ActualLayerColumns = double(nCols);
mapping.ActualLayerSymbolCount = double(numel(layerSym));
mapping.ActualLayersEqualGrantLayers = logical(nCols == double(mapping.NumLayers));
mapping.LayerColumnEnergy = double(energy);
mapping.AllLayerStreamsNonzero = logical(~isempty(energy) && all(energy > 0));
end

function nCodewords = localResolvePDSCHNumCodewords(pdsch, nLayers)
nCodewords = 1 + (double(nLayers) > 4);
raw = localObjectValue(pdsch, "NumCodewords", []);
if ~isempty(raw)
    nCodewords = double(raw);
end
if ~(isscalar(nCodewords) && isfinite(nCodewords) && nCodewords >= 1 && abs(nCodewords - round(nCodewords)) < 1e-9)
    error("sixgr:phy:dl:PDSCHBadCodewordCount", "PDSCH NumCodewords must be a positive integer scalar.");
end
nCodewords = round(nCodewords);
end

function localAssertPDSCHLayerSymbolContract(codewords, pdschSym, pdschInd, resourceAccounting, pdsch, codingLayouts, codewordLayerMapping)
if ~iscell(codewords)
    codewords = {codewords};
end
if ~iscell(codingLayouts)
    codingLayouts = {codingLayouts};
end
if numel(codewords) ~= double(codewordLayerMapping.NumCodewords)
    error("sixgr:phy:dl:PDSCHCodewordCountContract", ...
        "PDSCH emitted %d codeword(s), but the mapping contract requires %d.", ...
        numel(codewords), round(double(codewordLayerMapping.NumCodewords)));
end
rateMatchedBits = zeros(1, numel(codewords));
for c = 1:numel(codewords)
    rateMatchedBits(c) = numel(codewords{c});
    if numel(codewords{c}) ~= double(codingLayouts{c}.RateMatchedBitCount)
        error("sixgr:phy:dl:PDSCHCodewordCodingLayoutContract", ...
            "PDSCH codeword %d length %d does not match CodingLayout RateMatchedBitCount=%d.", ...
            c, numel(codewords{c}), round(double(codingLayouts{c}.RateMatchedBitCount)));
    end
end
if sum(rateMatchedBits) ~= double(resourceAccounting.CodedBitCountG)
    error("sixgr:phy:dl:PDSCHCodewordGContract", ...
        "PDSCH total codeword length %d does not match resource-accounting G=%d.", ...
        sum(rateMatchedBits), round(double(resourceAccounting.CodedBitCountG)));
end
expectedLayerSymbols = double(resourceAccounting.LayerDataRE) * double(pdsch.NumLayers);
if numel(pdschSym) ~= expectedLayerSymbols
    error("sixgr:phy:dl:PDSCHLayerSymbolCountContract", ...
        "PDSCH layer symbol count %d does not equal LayerDataRE=%d * NumLayers=%d.", ...
        numel(pdschSym), round(double(resourceAccounting.LayerDataRE)), round(double(pdsch.NumLayers)));
end
if numel(pdschInd) ~= expectedLayerSymbols
    error("sixgr:phy:dl:PDSCHLayerIndexCountContract", ...
        "PDSCH layer index cell count %d does not equal layer symbol count %d.", ...
        numel(pdschInd), expectedLayerSymbols);
end
if double(codewordLayerMapping.ActualLayerColumns) ~= double(pdsch.NumLayers)
    error("sixgr:phy:dl:PDSCHLayerColumnContract", ...
        "PDSCH actual layer columns %d do not match grant NumLayers=%d.", ...
        round(double(codewordLayerMapping.ActualLayerColumns)), round(double(pdsch.NumLayers)));
end
if double(pdsch.NumLayers) > 1 && ~logical(codewordLayerMapping.AllLayerStreamsNonzero)
    error("sixgr:phy:dl:PDSCHLayerStreamEnergyContract", ...
        "PDSCH rank-%d transmission must materialize nonzero symbols on every layer stream.", ...
        round(double(pdsch.NumLayers)));
end
end

function localAssertPortDomainContract(layerSym, layerInd, portSym, portInd, resourceAccounting, prec)
if numel(layerInd) ~= numel(layerSym)
    error("sixgr:phy:dl:PDSCHLayerDomainMismatch", ...
        "PDSCH layer-domain index count %d does not match symbol count %d.", numel(layerInd), numel(layerSym));
end
if numel(portInd) ~= numel(portSym)
    error("sixgr:phy:dl:PDSCHPortDomainMismatch", ...
        "PDSCH port-domain index count %d does not match symbol count %d.", numel(portInd), numel(portSym));
end
if logical(prec.Active)
    expectedPortSymbols = double(resourceAccounting.LayerDataRE) * double(prec.NumPorts);
else
    expectedPortSymbols = numel(layerSym);
end
if numel(portSym) ~= expectedPortSymbols
    error("sixgr:phy:dl:PDSCHPortSymbolCountContract", ...
        "PDSCH port symbol count %d does not match expected port-domain count %d.", ...
        numel(portSym), round(double(expectedPortSymbols)));
end
end

function localAssertSignalResourceDisjoint(dataInd, dmrsInd, ptrsInd)
checks = {dataInd, "data"; dmrsInd, "dmrs"; ptrsInd, "ptrs"};
for i = 1:size(checks, 1)
    raw = double(checks{i, 1}(:));
    if numel(raw) ~= numel(unique(raw))
        error("sixgr:phy:dl:PDSCHDuplicateMappedRE", ...
            "PDSCH %s indices contain duplicate port-domain RE.", char(checks{i, 2}));
    end
end
dataSet = localIndexSet(dataInd);
dmrsSet = localIndexSet(dmrsInd);
ptrsSet = localIndexSet(ptrsInd);
if ~isempty(intersect(dataSet, dmrsSet))
    error("sixgr:phy:dl:PDSCHDataDMRSOverlap", "PDSCH data and DMRS port-domain RE overlap.");
end
if ~isempty(intersect(dataSet, ptrsSet))
    error("sixgr:phy:dl:PDSCHDataPTRSOverlap", "PDSCH data and PTRS port-domain RE overlap.");
end
if ~isempty(intersect(dmrsSet, ptrsSet))
    error("sixgr:phy:dl:PDSCHDMRSPTRSOverlap", "PDSCH DMRS and PTRS port-domain RE overlap.");
end
end

function powerInfo = localBuildPrecodePowerInfo(layerSym, portSym, prec)
W = double(prec.MatrixPorts);
if isempty(W)
    W = eye(max(1, round(double(prec.NumLayers))));
end
columnNorms = sqrt(sum(abs(W).^2, 1));
gram = W' * W;
identityRef = eye(size(gram));
layerEnergy = sum(abs(layerSym(:)).^2);
portEnergy = sum(abs(portSym(:)).^2);
powerInfo = struct();
powerInfo.ContractVersion = "PDSCHPrecodePower/v1";
powerInfo.NormalizeW = logical(prec.NormalizeW);
powerInfo.NumLayers = double(prec.NumLayers);
powerInfo.NumPorts = double(prec.NumPorts);
powerInfo.ColumnNorms = double(columnNorms);
powerInfo.ColumnNormMaxError = double(max(abs(columnNorms(:) - 1), [], "omitnan"));
powerInfo.OrthonormalColumnMaxError = double(max(abs(gram(:) - identityRef(:)), [], "omitnan"));
powerInfo.LayerTotalEnergy = double(layerEnergy);
powerInfo.PortTotalEnergy = double(portEnergy);
powerInfo.TotalEnergyDelta = double(portEnergy - layerEnergy);
powerInfo.TotalPowerMaxAbsError = double(abs(portEnergy - layerEnergy));
powerInfo.TotalPowerRelativeError = double(abs(portEnergy - layerEnergy) / max(layerEnergy, eps));
powerInfo.Equation = "X_equals_S_times_W_transpose";
end

function ctx = localBuildTxContext(tx, trBlk, tbCrc, codewords, txGrid, txWaveform, pdschInd, pdschSym, pdschAntInd, pdschAntSym, ...
    dmrsInd, dmrsSym, dmrsAntInd, dmrsAntSym, ptrsInd, ptrsSym, ptrsAntInd, ptrsAntSym, ...
    carrier, pdsch, codingLayouts, resourceAccounting, prec, precodePowerInfo, codewordLayerMapping, phyGrant, hasPHYGrant)
ctx = struct();
ctx.ContractVersion = "PDSCH_TxContext/v1";
ctx.GrantDriven = logical(hasPHYGrant);
ctx.GrantContextId = string(sixgr.util.structGet(phyGrant, "GrantContextId", ""));
ctx.TransportBlock = int8(trBlk(:));
ctx.TransportBlockCRC = int8(tbCrc(:));
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
ctx.LayerSymbols = pdschSym;
ctx.LayerIndices = pdschInd;
ctx.PortSymbols = pdschAntSym;
ctx.PortIndices = pdschAntInd;
ctx.DMRSLayerSymbols = dmrsSym;
ctx.DMRSLayerIndices = dmrsInd;
ctx.DMRSPortSymbols = dmrsAntSym;
ctx.DMRSPortIndices = dmrsAntInd;
ctx.PTRSLayerSymbols = ptrsSym;
ctx.PTRSLayerIndices = ptrsInd;
ctx.PTRSPortSymbols = ptrsAntSym;
ctx.PTRSPortIndices = ptrsAntInd;
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
ctx.PDSCH = struct( ...
    "PRBSet", double(localObjectValue(pdsch, "PRBSet", [])), ...
    "SymbolAllocation", double(localObjectValue(pdsch, "SymbolAllocation", [])), ...
    "MappingType", string(localObjectValue(pdsch, "MappingType", "")), ...
    "Modulation", string(localObjectValue(pdsch, "Modulation", "")), ...
    "NumLayers", double(localObjectValue(pdsch, "NumLayers", NaN)), ...
    "RNTI", double(localObjectValue(pdsch, "RNTI", NaN)), ...
    "NID", double(localObjectValue(pdsch, "NID", NaN)));
ctx.DimensionContract = struct( ...
    "LayerDataRE", double(resourceAccounting.LayerDataRE), ...
    "PortIndexCellCount", double(numel(pdschAntInd)), ...
    "QAMSymbolCount", double(numel(pdschSym)), ...
    "NumCodewords", double(codewordLayerMapping.NumCodewords), ...
    "ActualNumLayers", double(codewordLayerMapping.ActualLayerColumns), ...
    "RateMatchedBitCount", double(numel(ctx.Codeword)), ...
    "RateMatchedBitCountPerCodeword", double(codewordLayerMapping.RateMatchedBitCountPerCodeword), ...
    "LayerIndexCellCount", double(numel(pdschInd)), ...
    "PortSymbolCount", double(numel(pdschAntSym)), ...
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
    error("sixgr:phy:dl:PDSCHBadInteger", "%s must be a positive integer scalar.", char(string(name)));
end
value = round(value);
end

function value = localNonnegativeIntegerValue(raw, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value >= 0 && abs(value - round(value)) < 1e-9)
    error("sixgr:phy:dl:PDSCHBadInteger", "%s must be a non-negative integer scalar.", char(string(name)));
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

function localAssertRateMatchMapAgreement(rateMatchInfo, codingLayout)
txMap = sixgr.util.structGet(rateMatchInfo, "PositionMap", struct());
layoutMap = sixgr.util.structGet(codingLayout, "RateMatchPositionMap", struct());
txIdx = sixgr.util.structGet(txMap, "MotherCodeLinearIndex", []);
layoutIdx = sixgr.util.structGet(layoutMap, "MotherCodeLinearIndex", []);
if isempty(txIdx) || isempty(layoutIdx) || numel(txIdx) ~= numel(layoutIdx) || any(uint32(txIdx(:)) ~= uint32(layoutIdx(:)))
    error("sixgr:phy:dl:PDSCHCodingLayoutMapMismatch", ...
        "PDSCH rate-match position map does not match canonical CodingLayout.");
end
end

function localGuardUnsupportedNumLayers(cfg, pdsch)
if isempty(pdsch)
    nLayers = double(sixgr.util.structGet(cfg, 'phy.pdsch.numLayers', ...
        sixgr.util.structGet(cfg, 'phy.pdsch.nLayers', 1)));
    nCodewords = double(sixgr.util.structGet(cfg, 'phy.pdsch.numCodewords', ...
        sixgr.util.structGet(cfg, 'phy.pdsch.NumCodewords', 1 + (nLayers > 4))));
else
    try
        nLayers = double(pdsch.NumLayers);
    catch
        nLayers = 1;
    end
    nCodewords = double(localObjectValue(pdsch, "NumCodewords", 1 + (nLayers > 4)));
end
if ~(isscalar(nLayers) && isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
nLayers = round(nLayers);
if ~(isscalar(nCodewords) && isfinite(nCodewords) && nCodewords >= 1)
    nCodewords = 1 + (nLayers > 4);
end
nCodewords = round(nCodewords);
if nLayers > 4 || nCodewords > 1
    error("sixgr:phy:dl:PDSCHPrecoding:MultiCodewordUnsupported", ...
        "PDSCH_Tx/PDSCH_Rx support one codeword for ranks 1-4. Requested NumLayers=%d NumCodewords=%d.", ...
        nLayers, nCodewords);
end
end
function [csirsInd, csirsSym, csirsInfo, csirsCfg, event] = localGenerateCSIRSRuntimeResource(carrier, cfg)
csirsInd = zeros(0, 1);
csirsSym = complex(zeros(0, 1));
csirsInfo = struct("Channel", "CSI-RS", "Enabled", false);
csirsCfg = [];
event = localEmptyCSIRSEvent(cfg);
if ~logical(sixgr.util.structGet(cfg, "phy.csirs.enable", false))
    event.RuntimeMaterializationStatus = "disabled";
    event.Blocker = "phy.csirs.enable_false";
    event.UpdateOutcome = "not_scheduled";
    return;
end
event.Scheduled = true;
try
    [csirsInd, csirsSym, csirsInfo, csirsCfg] = sixgr.phy.refsig.csirs(carrier, cfg);
catch ME
    event.RuntimeMaterializationStatus = "blocked_generation_failed";
    event.Blocker = string(ME.identifier) + ":" + string(ME.message);
    event.UpdateOutcome = "not_transmitted";
    return;
end
event.RuntimeEvidenceSource = "sixgr.phy.dl.PDSCH_Tx:csirs_runtime_grid_mapping";
event.NRE = double(numel(csirsSym));
event.SymbolLocations = localFormatNumericVector(localObjectValue(csirsCfg, "SymbolLocations", []));
event.SubcarrierLocations = localFormatNumericVector(localObjectValue(csirsCfg, "SubcarrierLocations", []));
event.RBOffset = double(localObjectValue(csirsCfg, "RBOffset", NaN));
event.NumRB = double(localObjectValue(csirsCfg, "NumRB", NaN));
event.NumPorts = double(sixgr.util.structGet(csirsInfo, "NumCSIRSPorts", NaN));
event.RowNumber = double(sixgr.util.structGet(csirsInfo, "RowNumber", NaN));
event.CSIRSType = string(localObjectValue(csirsCfg, "CSIRSType", "nzp"));
event.Density = string(localObjectValue(csirsCfg, "Density", ""));
event.Periodicity = localFormatCSIRSPeriod(localObjectValue(csirsCfg, "CSIRSPeriod", ""));
if isempty(csirsSym)
    event.RuntimeMaterializationStatus = "blocked_empty_resource";
    event.Blocker = "nrCSIRS_returned_empty_symbols";
    event.UpdateOutcome = "not_transmitted";
else
    event.RuntimeMaterializationStatus = "generated_not_yet_mapped";
    event.UpdateOutcome = "generated_runtime_symbols";
end
end

function event = localEmptyCSIRSEvent(cfg)
event = struct();
event.SignalFamily = "CSI-RS";
event.SignalDirection = "DL";
event.ResourceID = double(sixgr.util.structGet(cfg, "phy.csirs.resourceID", 0));
event.ResourceSetID = double(sixgr.util.structGet(cfg, "phy.csirs.resourceSetID", 0));
event.Scheduled = false;
event.Transmitted = false;
event.Observed = false;
event.Consumed = false;
event.Consumer = "";
event.RuntimeMaterializationStatus = "";
event.Blocker = "";
event.UpdateOutcome = "";
event.RuntimeEvidenceSource = "";
event.NRE = NaN;
event.NumPorts = NaN;
event.RowNumber = NaN;
event.CSIRSType = "";
event.Density = "";
event.Periodicity = "";
event.SymbolLocations = "";
event.SubcarrierLocations = "";
event.RBOffset = NaN;
event.NumRB = NaN;
end

function [collision, collisionWith] = localCSIRSResourceCollision(csirsInd, pdschInd, dmrsInd, ptrsInd)
collision = false;
collisionWith = "";
csirsSet = localIndexSet(csirsInd);
if isempty(csirsSet)
    return;
end
checks = {pdschInd, "pdsch"; dmrsInd, "dmrs"; ptrsInd, "ptrs"};
for i = 1:size(checks, 1)
    other = localIndexSet(checks{i, 1});
    if ~isempty(other) && ~isempty(intersect(csirsSet, other))
        collision = true;
        collisionWith = string(checks{i, 2});
        return;
    end
end
end

function values = localIndexSet(ind)
values = [];
if isempty(ind)
    return;
end
try
    values = unique(double(ind(:)));
    values = values(isfinite(values));
catch
    values = [];
end
end

function text = localFormatNumericVector(values)
try
    values = double(values(:).');
catch
    values = [];
end
values = values(isfinite(values));
if isempty(values)
    text = "";
else
    text = strjoin(string(values), "|");
end
end

function text = localFormatCSIRSPeriod(value)
if isnumeric(value)
    text = localFormatNumericVector(value);
else
    text = string(value);
end
end

function value = localObjectValue(obj, propName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    raw = obj.(propName);
catch
    return;
end
if isempty(raw)
    return;
end
value = raw;
end

function grid = localMapToGrid(grid, ind, sym)
if isempty(ind) || isempty(sym)
    return;
end

indLin = ind(:);
symLin = sym(:);
if numel(indLin) == numel(symLin)
    grid(indLin) = symLin;
    return;
end

if isnumeric(ind) && size(ind,1) == numel(symLin) && size(ind,2) >= 1
    grid(ind(:,1)) = symLin;
    return;
end

error('sixgr:phy:dl:PDSCHGridMappingMismatch', ...
    ['PDSCH grid mapping requires one symbol per resource element. ' ...
     'IndexCount=%d SymbolCount=%d IndexShape=%s SymbolShape=%s.'], ...
    numel(indLin), numel(symLin), mat2str(size(ind)), mat2str(size(sym)));
end

function numTxAnt = localResolveNumTxAnt(cfg, requested, prec)
if isempty(requested)
    if prec.Active
        numTxAnt = prec.NumPorts;
    else
        numTxAnt = double(sixgr.util.structGet(cfg, 'phy.nTxAnt', 1));
    end
else
    numTxAnt = double(requested);
end

numTxAnt = max(1, round(numTxAnt));
if prec.Active && numTxAnt ~= prec.NumPorts
    error("PDSCH_Tx:NumTxAntMismatch", ...
        "Explicit PDSCH precoding resolves to %d antenna port(s), but NumTxAnt=%d.", ...
        prec.NumPorts, numTxAnt);
end
end

function contract = localBuildResourceGridPortContract(txGrid, pdschAntInd, pdschAntSym, ...
    dmrsAntInd, dmrsAntSym, ptrsInd, ptrsSym, csirsInd, csirsSym, csirsEvent, numTxAnt, prec)
gridNumPages = max(1, size(txGrid, 3));
pdschPorts = localResolveMappedPortCount(pdschAntInd, pdschAntSym, 0);
dmrsPorts = localResolveMappedPortCount(dmrsAntInd, dmrsAntSym, 0);
ptrsPorts = localResolveMappedPortCount(ptrsInd, ptrsSym, 0);
csirsIndexPorts = localResolveMappedPortCount(csirsInd, csirsSym, 0);
csirsRequestedPorts = localNormalizeNonnegativePortCount(sixgr.util.structGet(csirsEvent, "NumPorts", 0));
primarySignalPorts = max([pdschPorts, dmrsPorts, ptrsPorts, 1]);
channelEstimatePorts = max([pdschPorts, dmrsPorts, 1]);
expansionSources = strings(0, 1);

if gridNumPages > primarySignalPorts
    if numTxAnt > primarySignalPorts
        expansionSources(end+1, 1) = "configured_tx_antennas";
    end
    if csirsRequestedPorts > primarySignalPorts
        expansionSources(end+1, 1) = "csirs_runtime_ports";
    end
    if csirsIndexPorts > primarySignalPorts
        expansionSources(end+1, 1) = "csirs_index_pages";
    end
end
if isempty(expansionSources)
    expansionSources = "primary_signal_ports_only";
end

contract = struct();
contract.GridNumPages = double(gridNumPages);
contract.ConfiguredTxAntennaPages = double(max(1, round(numTxAnt)));
contract.PDSCHAntennaPortCount = double(pdschPorts);
contract.DMRSAntennaPortCount = double(dmrsPorts);
contract.PTRSAntennaPortCount = double(ptrsPorts);
contract.CSIRSRequestedPortCount = double(csirsRequestedPorts);
contract.CSIRSIndexPageCount = double(csirsIndexPorts);
contract.PrimarySignalPortCount = double(primarySignalPorts);
contract.ChannelEstimateSignalPortCount = double(channelEstimatePorts);
contract.GridPagesExceedPrimarySignalPorts = logical(gridNumPages > primarySignalPorts);
contract.GridPageExpansionSources = expansionSources;
contract.PDSCHDMRSPortAlignmentOk = logical(dmrsPorts <= 0 || dmrsPorts == pdschPorts);
contract.PrecodingPortAlignmentOk = logical(~logical(prec.Active) || ...
    (pdschPorts == double(prec.NumPorts) && dmrsPorts == double(prec.NumPorts)));
contract.ResourceSelectiveChannelEstimateRequired = logical(channelEstimatePorts > 1);
contract.ScalarOrUnitShortcutEligibleBySignalGeometry = logical(channelEstimatePorts <= 1);
end

function localValidateResourceGridPortContract(contract, prec)
gridNumPages = double(contract.GridNumPages);
primarySignalPorts = double(contract.PrimarySignalPortCount);
configuredTxPages = double(contract.ConfiguredTxAntennaPages);
if gridNumPages < max([primarySignalPorts, configuredTxPages, 1])
    error("PDSCH_Tx:ResourceGridPageContractViolation", ...
        "Transmit grid has %d page(s), but truthful DL mapping requires at least %d page(s).", ...
        round(gridNumPages), round(max([primarySignalPorts, configuredTxPages, 1])));
end
if ~logical(contract.PDSCHDMRSPortAlignmentOk)
    error("PDSCH_Tx:DMRSPortAlignmentViolation", ...
        "PDSCH antenna port count (%d) and DM-RS antenna port count (%d) must match.", ...
        round(double(contract.PDSCHAntennaPortCount)), round(double(contract.DMRSAntennaPortCount)));
end
if ~logical(contract.PrecodingPortAlignmentOk)
    error("PDSCH_Tx:PrecodingPortAlignmentViolation", ...
        "Precoding resolves to %d port(s), but the mapped PDSCH/DM-RS antenna ports are %d/%d.", ...
        round(double(prec.NumPorts)), round(double(contract.PDSCHAntennaPortCount)), ...
        round(double(contract.DMRSAntennaPortCount)));
end
end

function numPorts = localResolveMappedPortCount(ind, sym, emptyValue)
if nargin < 3
    emptyValue = 0;
end
numPorts = emptyValue;
if isnumeric(ind) && ~isempty(ind)
    if ~isvector(ind)
        numPorts = size(ind, 2);
    else
        numPorts = 1;
    end
elseif isnumeric(sym) && ~isempty(sym)
    if ~isvector(sym)
        numPorts = size(sym, 2);
    else
        numPorts = 1;
    end
end
numPorts = localNormalizeNonnegativePortCount(numPorts);
end

function numPorts = localNormalizeNonnegativePortCount(value)
numPorts = double(value);
if ~(isscalar(numPorts) && isfinite(numPorts) && numPorts >= 0)
    numPorts = 0;
end
numPorts = round(numPorts);
end
