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
%     "RV"                 : redundancy version (0..3)
%     "TargetCodeRate"     : code rate (0..1)
%     "XOverhead"          : xOverhead for nrTBS (default 0)
%     "NumTxAnt"           : number of TX antennas for resource grid pages
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
ip.addParameter('RV', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0 && x<=3));
ip.addParameter('TargetCodeRate', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0 && x<1));
ip.addParameter('XOverhead', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
ip.addParameter('NumTxAnt', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

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

% Transport block size
nPRB = numel(pusch.PRBSet);
[nrePerPRB, dataBitBudget] = localResolveDataNREPerPRB(puschInfo, nPRB, pusch.Modulation, pusch.NumLayers);
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    error('sixgr:phy:ul:PUSCHNoDataRE', ...
        'PUSCH allocation has no schedulable data RE: PRBs=%d SymbolAllocation=%s Modulation=%s Layers=%d.', ...
        round(double(nPRB)), mat2str(localResolveSymbolAllocation(pusch)), char(string(pusch.Modulation)), round(double(pusch.NumLayers)));
end
trBlkSize = nrTBS(pusch.Modulation, pusch.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead);
trBlkSize = double(trBlkSize);

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

% Rate match to G bits
if isfinite(dataBitBudget) && dataBitBudget > 0
    G = double(dataBitBudget);
elseif isfield(puschInfo, 'G')
    G = double(puschInfo.G);
else
    qm = localQm(pusch.Modulation);
    G = double(qm * pusch.NumLayers * nPRB * nrePerPRB);
end
if ~(isfinite(G) && G > 0)
    error('sixgr:phy:ul:PUSCHNoDataRE', ...
        'PUSCH rate matching has no positive data-bit budget: PRBs=%d SymbolAllocation=%s Modulation=%s Layers=%d.', ...
        round(double(nPRB)), mat2str(localResolveSymbolAllocation(pusch)), char(string(pusch.Modulation)), round(double(pusch.NumLayers)));
end
codeword = sixgr.phy.phycode.rateMatchLDPC(ldpcEnc, G, rv, pusch.Modulation, pusch.NumLayers);
codeword = int8(codeword(:));

% ---------------------- PUSCH modulation & mapping ----------------------
[puschSym, ptrsSym, puschSymInfo] = localModulatePUSCH(carrier, pusch, codeword);

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
[txWaveform, ofdmInfo] = sixgr.phy.waveform.ofdmModulate(carrier, txGrid);

% ---------------------- Outputs ----------------------
tx = struct();
tx.Waveform = txWaveform;
tx.TransportBlockSize = trBlkSize;
tx.RV = rv;
tx.TargetCodeRate = targetCodeRate;
tx.Carrier = carrier;
tx.PUSCH = pusch;
tx.PUSCHIndices = puschInd;
tx.PUSCHSymbolsForEvidence = puschSym;
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
    tx.PUSCHInfo = puschInfo;
    tx.PUSCHSymbols = puschSym;
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
info.OFDM = ofdmInfo;
info.Precoding = prec;

end

function [nrePerPRB, gBits] = localResolveDataNREPerPRB(puschInfo, nPRB, modStr, nLayers)
nrePerPRB = NaN;
gBits = NaN;
qm = localQm(modStr);
if isfield(puschInfo, 'G')
    gBits = double(puschInfo.G);
    if isfinite(gBits)
        if gBits <= 0
            nrePerPRB = 0;
            return;
        end
        nrePerPRB = floor(double(gBits) / max(double(qm) * double(nLayers) * max(double(nPRB), 1), 1));
        if isfinite(nrePerPRB) && nrePerPRB > 0
            return;
        end
    end
end
if isfield(puschInfo, 'NRE')
    nrePerPRB = floor(double(puschInfo.NRE) / max(double(nPRB), 1));
elseif isfield(puschInfo, 'NREPerPRB')
    nrePerPRB = double(puschInfo.NREPerPRB);
end
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    nrePerPRB = NaN;
end
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

% Last-resort safe truncation.
indLin = ind(:);
symLin = sym(:);
L = min(numel(indLin), numel(symLin));
if L > 0
    grid(indLin(1:L)) = symLin(1:L);
end
end
