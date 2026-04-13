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
%     "RV"           : redundancy version (0..3)
%     "TargetCodeRate": code rate (0..1)
%     "XOverhead"    : xOverhead for nrTBS (default 0)
%     "NumTxAnt"     : number of TX antennas / mapped antenna ports
%     "PrecodingMatrix" : wideband PDSCH precoder, Nports-by-Nlayers or transpose
%
%   Outputs:
%     TX.Waveform      : time-domain OFDM waveform
%     TX.Grid          : frequency-domain resource grid
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
ip.addParameter('RV', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0 && x<=3));
ip.addParameter('TargetCodeRate', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0 && x<1));
ip.addParameter('XOverhead', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
ip.addParameter('NumTxAnt', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('PrecodingMatrix', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;
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
    [pdschInd, pdschInfo, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfg);
else
    pdsch = opt.PDSCH;
    try
        [pdschInd, pdschInfo] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
    catch
        [pdschInd, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
    end
end

% PDSCH parameters
rv = opt.RV;
if isempty(rv)
    rv = double(sixgr.util.structGet(cfg, 'phy.pdsch.rv', 0));
end

targetCodeRate = opt.TargetCodeRate;
if isempty(targetCodeRate)
    targetCodeRate = double(sixgr.util.structGet(cfg, 'phy.pdsch.codeRate', 0.4785));
end

xOverhead = opt.XOverhead;
if isempty(xOverhead)
    xOverhead = double(sixgr.util.structGet(cfg, 'phy.pdsch.xOverhead', 0));
end

prec = sixgr.phy.dl.resolvePDSCHPrecoding(pdsch, cfg, ...
    "PrecodingMatrix", opt.PrecodingMatrix);

numTxAnt = localResolveNumTxAnt(cfg, opt.NumTxAnt, prec);

% Transport block size
nPRB = numel(pdsch.PRBSet);
nrePerPRB = [];
if isfield(pdschInfo, 'NREPerPRB')
    nrePerPRB = double(pdschInfo.NREPerPRB);
elseif isfield(pdschInfo, 'NRE')
    nrePerPRB = floor(double(pdschInfo.NRE) / max(nPRB,1));
elseif isfield(pdschInfo, 'G')
    qm = localQm(pdsch.Modulation);
    nrePerPRB = floor(double(pdschInfo.G) / max(qm * pdsch.NumLayers * nPRB, 1));
end
if isempty(nrePerPRB) || ~isfinite(nrePerPRB) || nrePerPRB <= 0
    % Conservative fallback for normal CP with typical DMRS overhead.
    nrePerPRB = 144;
end
trBlkSize = nrTBS(pdsch.Modulation, pdsch.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead);
trBlkSize = double(trBlkSize);

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

% Base graph selection (use toolbox helper when available)
tbCRCType = '24A';
tbCRCLen = 24;
try
    dlschInfo = nrDLSCHInfo(trBlkSize, targetCodeRate);
    bgn = double(dlschInfo.BGN);
    [tbCRCType, tbCRCLen] = localResolveTBCRCSpec(dlschInfo, tbCRCType, tbCRCLen);
catch
    % Fallback: conservative choice
    bgn = 2;
end

% ---------------------- DL-SCH encoding (modular blocks) ----------------------
% Match the TB CRC selected by nrDLSCHInfo for this transport block size.
tbCrc = sixgr.phy.tb.attachCRC(trBlk, tbCRCType);
crcInfo = struct("Type", string(tbCRCType), "Length", double(tbCRCLen));
B = numel(tbCrc);

% Code block segmentation
[cbs, segInfo] = sixgr.phy.tb.segmentLDPC(tbCrc, bgn);
C = size(cbs, 2);

% LDPC encode all code blocks in one toolbox call to avoid repeated
% per-code-block MATLAB loop overhead.
ldpcEnc = int8(sixgr.phy.phycode.ldpcEncode(cbs, bgn));

% Rate match to G bits
if isfield(pdschInfo, 'G')
    G = double(pdschInfo.G);
else
    qm = localQm(pdsch.Modulation);
    G = double(qm * pdsch.NumLayers * nPRB * nrePerPRB);
end
codeword = sixgr.phy.phycode.rateMatchLDPC(ldpcEnc, G, rv, pdsch.Modulation, pdsch.NumLayers);
codeword = int8(codeword(:));

% ---------------------- PDSCH modulation & mapping ----------------------
% nrPDSCH expects codewords as a cell array (up to 2 codewords)
codewords = {codeword};

try
    [pdschSym, pdschSymInfo] = nrPDSCH(carrier, pdsch, codewords);
catch
    pdschSym = nrPDSCH(carrier, pdsch, codewords);
    pdschSymInfo = struct();
end

% DMRS
[dmrsInd, dmrsSym] = sixgr.phy.refsig.dmrsPDSCH(carrier, pdsch);

% PTRS (optional)
[ptrsInd, ptrsSym, ptrsInfo] = sixgr.phy.refsig.ptrsPDSCH(carrier, pdsch);

[csirsInd, csirsSym, csirsInfo, csirsCfg, csirsEvent] = localGenerateCSIRSRuntimeResource(carrier, cfg);

pdschAntInd = pdschInd;
pdschAntSym = pdschSym;
dmrsAntInd = dmrsInd;
dmrsAntSym = dmrsSym;
if prec.Active
    % Precode layer-domain data and DM-RS before the final antenna-port map.
    [pdschAntSym, pdschAntInd] = nrPDSCHPrecode(carrier, pdschSym, pdschInd, prec.MatrixNR);
    [dmrsAntSym, dmrsAntInd] = nrPDSCHPrecode(carrier, dmrsSym, dmrsInd, prec.MatrixNR);
end

% Build resource grid and map
nPages = max([size(pdschAntInd,2), size(dmrsAntInd,2), size(ptrsInd,2), size(csirsInd,2), ...
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
if ~isempty(ptrsInd)
    txGrid = localMapToGrid(txGrid, ptrsInd, ptrsSym);
end
if logical(sixgr.util.structGet(csirsEvent, "Scheduled", false)) && ~isempty(csirsInd)
    [collision, collisionWith] = localCSIRSResourceCollision(csirsInd, pdschAntInd, dmrsAntInd, ptrsInd);
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

% OFDM modulation
[txWaveform, ofdmInfo] = sixgr.phy.waveform.ofdmModulate(carrier, txGrid);

% ---------------------- Outputs ----------------------
tx = struct();
tx.Waveform = txWaveform;
tx.TransportBlockSize = trBlkSize;
tx.RV = rv;
tx.TargetCodeRate = targetCodeRate;
tx.Carrier = carrier;
tx.PDSCH = pdsch;
tx.PDSCHIndices = pdschInd;
tx.PDSCHSymbolsForEvidence = pdschSym;
tx.PrecodeInfo = prec;
if ~logical(opt.CompactOutput)
    tx.Grid = txGrid;
    tx.TransportBlock = trBlk;
    tx.TransportBlockCRC = tbCrc;
    tx.TransportBlockCRCType = char(tbCRCType);
    tx.TransportBlockCRCLength = double(tbCRCLen);
    tx.TransportBlockLenWithCRC = B;
    tx.BaseGraph = bgn;
    tx.Codeword = codeword;
    tx.G = G;
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
    tx.CSIRSIndices = csirsInd;
    tx.CSIRSSymbols = csirsSym;
    tx.CSIRSInfo = csirsInfo;
    tx.CSIRS = csirsCfg;
    tx.CSIRSRuntimeEvent = csirsEvent;
end

info = struct();
info.CarrierInfo = cinfo;
info.CRC = crcInfo;
info.Segmentation = segInfo;
info.PDSCHSymbols = pdschSymInfo;
info.PTRS = ptrsInfo;
info.CSIRS = csirsInfo;
info.CSIRSRuntimeEvent = csirsEvent;
info.OFDM = ofdmInfo;
info.Precoding = prec;

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

function localGuardUnsupportedNumLayers(cfg, pdsch)
nLayers = 1;
if isempty(pdsch)
    nLayers = double(sixgr.util.structGet(cfg, 'phy.pdsch.numLayers', ...
        sixgr.util.structGet(cfg, 'phy.pdsch.nLayers', 1)));
else
    try
        nLayers = double(pdsch.NumLayers);
    catch
        nLayers = 1;
    end
end
if ~(isscalar(nLayers) && isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
nLayers = round(nLayers);
if nLayers > 4
    error("sixgr:phy:dl:PDSCHPrecoding:MultiCodewordUnsupported", ...
        "PDSCH_Tx/PDSCH_Rx support a single codeword only. Requested %d layer(s) implies 2 codeword(s).", ...
        nLayers);
end
end

function qm = localQm(modScheme)
switch upper(char(string(modScheme)))
    case {'PI/2-BPSK','BPSK'}
        qm = 1;
    case 'QPSK'
        qm = 2;
    case '16QAM'
        qm = 4;
    case '64QAM'
        qm = 6;
    case '256QAM'
        qm = 8;
    case '1024QAM'
        qm = 10;
    case '4096QAM'
        qm = 12;
    otherwise
        qm = 2;
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

L = min(numel(indLin), numel(symLin));
if L > 0
    grid(indLin(1:L)) = symLin(1:L);
end
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
