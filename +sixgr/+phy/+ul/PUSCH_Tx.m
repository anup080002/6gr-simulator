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
    [puschInd, puschInfo, pusch] = sixgr.phy.grid.allocREsPUSCH(carrier, cfg);
else
    pusch = opt.PUSCH;
    pusch = localEnsureTransformPrecodingOwnership(pusch, cfg);
    try
        [puschInd, puschInfo] = nrPUSCHIndices(carrier, pusch, 'IndexStyle', 'index');
    catch
        [puschInd, puschInfo] = nrPUSCHIndices(carrier, pusch);
    end
end

% PUSCH parameters
rv = opt.RV;
if isempty(rv)
    rv = double(sixgr.util.structGet(cfg, 'phy.pusch.rv', 0));
end

targetCodeRate = opt.TargetCodeRate;
if isempty(targetCodeRate)
    targetCodeRate = double(sixgr.util.structGet(cfg, 'phy.pusch.codeRate', 0.4785));
end

xOverhead = opt.XOverhead;
if isempty(xOverhead)
    xOverhead = double(sixgr.util.structGet(cfg, 'phy.pusch.xOverhead', 0));
end

prec = sixgr.phy.ul.resolvePUSCHPrecoding(pusch, cfg);

numTxAnt = opt.NumTxAnt;
if isempty(numTxAnt)
    numTxAnt = double(sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "tx", ...
        sixgr.util.structGet(prec, "NumPorts", 1)));
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
scheduledTrBlkSize = double(nrTBS(pusch.Modulation, pusch.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead));
trBlkSize = scheduledTrBlkSize;
if ~isempty(opt.TransportBlockSizeOverride)
    replayTrBlkSize = round(double(opt.TransportBlockSizeOverride));
    if ~(isfinite(replayTrBlkSize) && replayTrBlkSize > 0)
        error('PUSCH_Tx:BadReplayTBSize', 'TransportBlockSizeOverride must be a positive finite scalar.');
    end
    trBlkSize = replayTrBlkSize;
end

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

% Base graph selection
tbCRCType = '24A';
tbCRCLen = 24;
try
    ulschInfo = nrULSCHInfo(trBlkSize, targetCodeRate);
    bgn = double(ulschInfo.BGN);
    [tbCRCType, tbCRCLen] = localResolveTBCRCSpec(ulschInfo, tbCRCType, tbCRCLen);
catch
    bgn = 2;
end

% ---------------------- UL-SCH encoding (modular blocks) ----------------------
% Match the TB CRC selected by nrULSCHInfo for this transport block size.
tbCrc = sixgr.phy.tb.attachCRC(trBlk, tbCRCType);
crcInfo = struct("Type", string(tbCRCType), "Length", double(tbCRCLen));
B = numel(tbCrc);

% Code block segmentation
[cbs, segInfo] = sixgr.phy.tb.segmentLDPC(tbCrc, bgn);
C = size(cbs, 2);

% LDPC encode all code blocks in one toolbox call to avoid repeated
% per-code-block MATLAB loop overhead.
ldpcEnc = int8(sixgr.phy.phycode.ldpcEncode(cbs, bgn));
harqAckBits = localNormalizeHARQACKBits(opt.HARQACKBits);
oack = numel(harqAckBits);
uciInfo = struct( ...
    "UCIOnPUSCHApplied", false, ...
    "HARQACKBitCount", double(oack), ...
    "HARQACKBits", harqAckBits, ...
    "GULSCH", NaN, ...
    "GACK", NaN, ...
    "GACKReserved", NaN, ...
    "Source", "no_uci_payload_requested");

% Rate match to G bits
G = double(resourceAccounting.CodedBitCountG);
if ~(isfinite(G) && G > 0)
    error('sixgr:phy:ul:PUSCHNoDataRE', ...
        'PUSCH rate matching has no positive data-bit budget: PRBs=%d SymbolAllocation=%s Modulation=%s Layers=%d.', ...
        round(double(nPRB)), mat2str(localResolveSymbolAllocation(pusch)), char(string(pusch.Modulation)), round(double(pusch.NumLayers)));
end
if oack > 0
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
    ulSchCodeword = sixgr.phy.phycode.rateMatchLDPC(ldpcEnc, gULSCH, rv, pusch.Modulation, pusch.NumLayers);
    codedAck = nrUCIEncode(harqAckBits, gACK, pusch.Modulation);
    [codeword, muxInfo] = nrULSCHMultiplex(pusch, targetCodeRate, trBlkSize, ulSchCodeword(:), codedAck(:), [], []);
    codeword = int8(codeword(:));
    uciInfo.UCIOnPUSCHApplied = true;
    uciInfo.GULSCH = gULSCH;
    uciInfo.GACK = gACK;
    uciInfo.GACKReserved = double(sixgr.util.structGet(rmInfo, "GACKRvd", NaN));
    uciInfo.MultiplexInfo = muxInfo;
    uciInfo.Source = "nrULSCHMultiplex_ts38212_6_2_7_harq_ack_on_pusch";
else
    codeword = sixgr.phy.phycode.rateMatchLDPC(ldpcEnc, G, rv, pusch.Modulation, pusch.NumLayers);
end
codeword = int8(codeword(:));

% ---------------------- PUSCH modulation & mapping ----------------------
[puschSym, ptrsSym, puschSymInfo] = localModulatePUSCH(carrier, pusch, codeword);
[puschLayerSym, puschDomainInfo] = localResolvePUSCHLayerSymbols(puschSym, pusch);
puschLayerInd = localLayerIndicesFromPortIndices(puschInd, puschLayerSym);
puschLayerOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, puschLayerInd, "layer");
puschPortOrder = sixgr.phy.resource.buildSymbolOrderingMap(carrier, puschInd, "port");

% DMRS
[dmrsInd, dmrsSym] = sixgr.phy.refsig.dmrsPUSCH(carrier, pusch);

% PTRS (optional)
ptrsInd = [];
if ~isempty(ptrsSym)
    try
        ptrsInd = nrPUSCHPTRSIndices(carrier, pusch, "IndexBase", "1based");
    catch
        ptrsInd = [];
    end
end

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
if isempty(opt.TransportBlockSizeOverride)
    tx.TransportBlockSizeSource = 'nrTBS_from_current_allocation';
else
    tx.TransportBlockSizeSource = 'harq_replay_stored_transport_block';
end
tx.TransportBlock = trBlk;
tx.TransportBlockCRCType = char(tbCRCType);
tx.TransportBlockCRCLength = double(tbCRCLen);
tx.TransportBlockLenWithCRC = B;
tx.RV = rv;
tx.TargetCodeRate = targetCodeRate;
tx.Carrier = carrier;
tx.PUSCH = pusch;
tx.PUSCHIndices = puschInd;
tx.PUSCHSymbolsForEvidence = puschLayerSym;
tx.PUSCHLayerSymbolsForEvidence = puschLayerSym;
tx.PUSCHPortSymbolsForEvidence = puschSym;
tx.PUSCHLayerSymbols = puschLayerSym;
tx.PUSCHPortSymbols = puschSym;
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
tx.QAMSymbolCount = double(numel(puschLayerSym));
tx.PortIndexCellCount = double(numel(puschInd));
tx.RateMatchedBitCount = double(G);
tx.ResourceAccounting = resourceAccounting;
tx.PrecodeInfo = prec;
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
info.PUSCHSymbols = puschSymInfo;
info.SymbolDomain = puschDomainInfo;
info.OFDM = ofdmInfo;
info.OFDMWindowing = windowingInfo;
info.Precoding = prec;
info.UCIOnPUSCH = uciInfo;
info.TransformPrecodingAppliedBy = localTransformPrecodingSource(pusch, cfg);
info.XOverhead = double(xOverhead);
info.ResourceAccounting = resourceAccounting;
if hasPHYGrant
    info.PHYGrant = phyGrant;
    info.PHYGrantDimensionContract = phyGrantContract;
end

end

function bits = localNormalizeHARQACKBits(rawBits)
if isempty(rawBits)
    bits = int8([]);
    return;
end
bits = int8(logical(rawBits(:)));
end

function symAlloc = localResolveSymbolAllocation(pusch)
symAlloc = [];
try
    symAlloc = double(pusch.SymbolAllocation);
catch
    symAlloc = [];
end
if isempty(symAlloc)
    symAlloc = [NaN NaN];
elseif numel(symAlloc) < 2
    symAlloc = [double(symAlloc(1)) NaN];
else
    symAlloc = reshape(double(symAlloc(1:2)), 1, 2);
end
end

function [crcType, crcLen] = localResolveTBCRCSpec(schInfo, defaultType, defaultLen)
crcType = defaultType;
crcLen = defaultLen;
if nargin < 1 || ~isstruct(schInfo)
    return;
end
rawType = char(string(sixgr.util.structGet(schInfo, 'CRC', defaultType)));
if ~isempty(rawType)
    crcType = rawType;
end
rawLen = double(sixgr.util.structGet(schInfo, 'L', defaultLen));
if isfinite(rawLen) && rawLen >= 0
    crcLen = rawLen;
end
end

function [puschSym, ptrsSym, puschSymInfo] = localModulatePUSCH(carrier, pusch, codeword)
% MATLAB releases disagree on whether a single-codeword PUSCH call should
% receive the codeword directly or wrapped in a 1x1 cell array. Try the
% older numeric signature first, then fall back to the cell signature used
% by newer releases.
ptrsSym = [];
puschSymInfo = struct();
numericErr = [];
try
    [puschSym, ptrsSym] = nrPUSCH(carrier, pusch, codeword);
    return;
catch ME
    numericErr = ME;
end

codewords = {codeword};
try
    [puschSym, ptrsSym] = nrPUSCH(carrier, pusch, codewords);
    return;
catch
end

try
    puschSym = nrPUSCH(carrier, pusch, codeword);
    return;
catch
end

try
    puschSym = nrPUSCH(carrier, pusch, codewords);
    return;
catch
    rethrow(numericErr);
end
end

function [layerSym, info] = localResolvePUSCHLayerSymbols(portSym, pusch)
portSym = localEnsure2D(portSym);
nLayers = localObjectFiniteScalar(pusch, "NumLayers", size(portSym, 2));
nPorts = localObjectFiniteScalar(pusch, "NumAntennaPorts", size(portSym, 2));
tpmi = localObjectFiniteScalar(pusch, "TPMI", NaN);
scheme = lower(strtrim(string(localObjectValue(pusch, "TransmissionScheme", ""))));
nLayers = max(1, round(double(nLayers)));
nPorts = max(1, round(double(nPorts)));
info = struct( ...
    "ReferenceDomain", "layer", ...
    "PortDomain", "port", ...
    "Transform", "identity", ...
    "NumLayers", double(nLayers), ...
    "NumPorts", double(nPorts), ...
    "TPMI", double(tpmi), ...
    "Status", "native_layer_symbols", ...
    "Equation", "b_G_to_QAM_d_to_layers_S_to_ports_X_equals_S_times_W_transpose");

if isempty(portSym)
    layerSym = portSym;
    info.Status = "empty_symbol_array";
    return;
end

if size(portSym, 2) == nLayers
    layerSym = portSym;
    return;
end

if scheme == "codebook" && size(portSym, 2) == nPorts && nPorts > nLayers
    [Wlayer, status] = sixgr.phy.ul.puschCodebookProjectionMatrix(nLayers, nPorts, tpmi);
    if isempty(Wlayer)
        error("sixgr:phy:ul:PUSCHSymbolDomainUnsupported", ...
            "Cannot derive layer-domain PUSCH symbols from port-domain symbols: %s.", char(string(status)));
    end
    if size(Wlayer, 1) ~= size(portSym, 2) || size(Wlayer, 2) ~= nLayers
        error("sixgr:phy:ul:PUSCHSymbolDomainMismatch", ...
            "PUSCH codebook matrix shape %s does not match port-symbol shape %s.", ...
            mat2str(size(Wlayer)), mat2str(size(portSym)));
    end
    layerSym = portSym * conj(Wlayer);
    info.Transform = "inverse_unitary_codebook_projection_X_times_conj_W";
    info.Status = string(status) + "_recovered_layer_symbols";
    return;
end

error("sixgr:phy:ul:PUSCHSymbolDomainMismatch", ...
    "PUSCH symbol domains are incompatible: port-symbol shape %s, NumLayers=%d, NumPorts=%d, TransmissionScheme=%s.", ...
    mat2str(size(portSym)), nLayers, nPorts, char(scheme));
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

function value = localObjectFiniteScalar(obj, propName, defaultValue)
raw = localObjectValue(obj, propName, defaultValue);
if isnumeric(raw) || islogical(raw)
    value = double(raw);
elseif isstring(raw) || ischar(raw)
    value = str2double(string(raw));
else
    value = double(defaultValue);
end
if numel(value) > 1
    value = value(1);
end
if isempty(value) || ~isscalar(value) || ~isfinite(value)
    value = double(defaultValue);
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

indLin = ind(:);
symLin = sym(:);
error('sixgr:phy:ul:PUSCHGridMappingMismatch', ...
    ['PUSCH grid mapping requires one symbol per resource element. ' ...
     'IndexCount=%d SymbolCount=%d IndexShape=%s SymbolShape=%s.'], ...
    numel(indLin), numel(symLin), mat2str(size(ind)), mat2str(size(sym)));
end
