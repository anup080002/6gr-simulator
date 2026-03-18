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
%     "NumTxAnt"     : number of TX antennas (default 1)
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
%
%   Notes:
%     * nrPDSCH internally performs scrambling using pdsch.NID / pdsch.RNTI.
%       Therefore, TX.Codeword is NOT scrambled here.

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDSCH', [], @(x) isempty(x) || isobject(x));
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

numTxAnt = opt.NumTxAnt;
if isempty(numTxAnt)
    numTxAnt = double(sixgr.util.structGet(cfg, 'phy.nTxAnt', 1));
end
numTxAnt = max(1, round(numTxAnt));

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
try
    dlschInfo = nrDLSCHInfo(trBlkSize, targetCodeRate);
    bgn = double(dlschInfo.BGN);
catch
    % Fallback: conservative choice
    bgn = 2;
end

% ---------------------- DL-SCH encoding (modular blocks) ----------------------
% TB CRC (24A)
tbCrc = sixgr.phy.tb.attachCRC(trBlk, '24A');
crcInfo = struct();
B = numel(tbCrc);

% Code block segmentation
[cbs, segInfo] = sixgr.phy.tb.segmentLDPC(tbCrc, bgn);
C = size(cbs, 2);

% LDPC encode each code block
enc1 = sixgr.phy.phycode.ldpcEncode(cbs(:, 1), bgn);
ldpcEnc = zeros(size(enc1,1), C, 'int8');
ldpcEnc(:, 1) = int8(enc1(:));
if C > 1
    usePar = logical(sixgr.util.structGet(cfg, 'run.useParallel', false)) ...
        && license('test','Distrib_Computing_Toolbox') && ~isempty(gcp('nocreate'));
    if usePar
        encRest = cell(C-1,1);
        parfor c = 2:C
            encRest{c-1} = int8(sixgr.phy.phycode.ldpcEncode(cbs(:, c), bgn));
        end
        for c = 2:C
            ldpcEnc(:, c) = encRest{c-1}(:);
        end
    else
        for c = 2:C
            ldpcEnc(:, c) = int8(sixgr.phy.phycode.ldpcEncode(cbs(:, c), bgn));
        end
    end
end

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

% Build resource grid and map
try
    txGrid = nrResourceGrid(carrier, numTxAnt);
catch
    txGrid = nrResourceGrid(carrier);
end

% Map PDSCH (single codeword/single layer path)
txGrid = localMapToGrid(txGrid, pdschInd, pdschSym);

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
tx.PDSCH = pdsch;
tx.PDSCHIndices = pdschInd;
if ~logical(opt.CompactOutput)
    tx.Grid = txGrid;
    tx.TransportBlock = trBlk;
    tx.TransportBlockCRC = tbCrc;
    tx.TransportBlockLenWithCRC = B;
    tx.BaseGraph = bgn;
    tx.Codeword = codeword;
    tx.G = G;
    tx.PDSCHInfo = pdschInfo;
    tx.DMRSIndices = dmrsInd;
    tx.DMRSSymbols = dmrsSym;
    tx.PTRSIndices = ptrsInd;
    tx.PTRSSymbols = ptrsSym;
end

info = struct();
info.CarrierInfo = cinfo;
info.CRC = crcInfo;
info.Segmentation = segInfo;
info.PDSCHSymbols = pdschSymInfo;
info.PTRS = ptrsInfo;
info.OFDM = ofdmInfo;

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
