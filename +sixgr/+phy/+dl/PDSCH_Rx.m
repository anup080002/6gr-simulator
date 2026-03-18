function [rx, info] = PDSCH_Rx(rxWaveform, cfg, varargin)
%PDSCH_Rx Recover a basic PDSCH transmission (OFDM -> PDSCH -> DL-SCH).
%
%   [RX,INFO] = sixgr.phy.dl.PDSCH_Rx(RXWAVEFORM, CFG) performs
%   DMRS-aided timing, OFDM demodulation, channel estimation,
%   MMSE equalization, nrPDSCHDecode demodulation, LDPC rate recovery,
%   LDPC decoding, and transport block CRC checking.
%
%   Name-Value options:
%     "Carrier"     : nrCarrierConfig override
%     "PDSCH"       : nrPDSCHConfig override
%     "PDSCHIndices": mapping indices override
%     "TransportBlockSize": expected TB size (bits)
%     "TargetCodeRate": code rate (0..1)
%     "RV"          : redundancy version (0..3)
%     "NoiseVar"    : noise variance (if known)
%     "MaxIterations": LDPC iterations (default from cfg)
%     "Algorithm"   : LDPC algorithm ("Normalized min-sum" by default)
%
%   Outputs:
%     RX.TransportBlock     : recovered TB bits (if CRC passes)
%     RX.CRCError           : true if TB CRC fails
%     RX.Ok                 : ~CRCError
%     RX.CodewordLLR        : soft bits before rate recovery
%     RX.ChannelEstimate    : H estimate
%     RX.NoiseVar           : used noise variance
%     RX.TimingOffset       : estimated timing offset (samples)
%
%   Notes:
%     This receiver assumes a single codeword and (by default) uses the same
%     PDSCH allocation as the transmitter.

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDSCH', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDSCHIndices', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('TransportBlockSize', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
ip.addParameter('TargetCodeRate', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0 && x<1));
ip.addParameter('RV', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0 && x<=3));
ip.addParameter('NoiseVar', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
ip.addParameter('MaxIterations', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('Algorithm', [], @(x) isempty(x) || ischar(x) || isstring(x));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('FastAWGNPath', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

% Carrier
if isempty(opt.Carrier)
    [carrier, cinfo] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
    cinfo = struct();
end

% PDSCH config and indices
if isempty(opt.PDSCH)
    [pdschInd, pdschInfo, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfg);
else
    pdsch = opt.PDSCH;
    if isempty(opt.PDSCHIndices)
        try
            [pdschInd, pdschInfo] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
        catch
            [pdschInd, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
        end
    else
        pdschInd = opt.PDSCHIndices;
        try
            [~, pdschInfo] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
        catch
            [~, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
        end
    end
end

% Parameters
rv = opt.RV;
if isempty(rv)
    rv = double(sixgr.util.structGet(cfg, 'phy.pdsch.rv', 0));
end

targetCodeRate = opt.TargetCodeRate;
if isempty(targetCodeRate)
    targetCodeRate = double(sixgr.util.structGet(cfg, 'phy.pdsch.codeRate', 0.4785));
end

maxIter = opt.MaxIterations;
if isempty(maxIter)
    maxIter = double(sixgr.util.structGet(cfg, 'phy.ldpc.maxIterations', 8));
end

alg = opt.Algorithm;
if isempty(alg)
    alg = string(sixgr.util.structGet(cfg, 'phy.ldpc.algorithm', "Normalized min-sum"));
else
    alg = string(alg);
end

% Expected TB size
trBlkSize = opt.TransportBlockSize;
if isempty(trBlkSize)
    xOverhead = double(sixgr.util.structGet(cfg, 'phy.pdsch.xOverhead', 0));
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
        nrePerPRB = 144;
    end
    trBlkSize = nrTBS(pdsch.Modulation, pdsch.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead);
end
trBlkSize = double(trBlkSize);

% Base graph
try
    dlschInfo = nrDLSCHInfo(trBlkSize, targetCodeRate);
    bgn = double(dlschInfo.BGN);
catch
    bgn = 2;
end

% DMRS
[dmrsInd, dmrsSym] = sixgr.phy.refsig.dmrsPDSCH(carrier, pdsch);
useFastAWGNPath = logical(opt.FastAWGNPath);

% ---------------------- Timing estimate ----------------------
timingOffset = 0;
if ~useFastAWGNPath && ~isempty(dmrsInd)
    try
        timingOffset = nrTimingEstimate(carrier, rxWaveform, dmrsInd, dmrsSym);
        timingOffset = double(timingOffset);
    catch
        timingOffset = 0;
    end
end

% Apply timing correction
if timingOffset > 0 && timingOffset < size(rxWaveform,1)
    rxWave = rxWaveform(1+timingOffset:end, :);
else
    rxWave = rxWaveform;
end

% ---------------------- OFDM demodulate ----------------------
[rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, rxWave);

% ---------------------- Channel estimate ----------------------
useFastChEstMex = logical(sixgr.util.structGet(cfg, 'phy.rx.useFastChannelEstMex', false)) ...
    && logical(sixgr.util.structGet(cfg, 'run.useMex', false));
if useFastAWGNPath
    hEst = ones(size(rxGrid), 'like', rxGrid);
    nVarEst = 0;
elseif ~isempty(dmrsInd)
    [hEst, nVarEst] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, dmrsInd, dmrsSym, ...
        "UseFastMex", useFastChEstMex);
else
    hEst = ones(size(rxGrid));
    nVarEst = 0;
end

nVar = opt.NoiseVar;
if isempty(nVar)
    nVar = nVarEst;
end
nVar = double(max(0, nVar));

% ---------------------- Extract and equalize PDSCH REs ----------------------
[rxSym, hestSym] = nrExtractResources(pdschInd, rxGrid, hEst);
[eqSym, csi] = nrEqualizeMMSE(rxSym, hestSym, nVar);
% Apply CSI scaling (as in MathWorks examples)
eqSym = eqSym .* csi;

% ---------------------- PDSCH demodulate to soft bits ----------------------
% nrPDSCHDecode returns a cell array (one per codeword)
llrCW = nrPDSCHDecode(carrier, pdsch, eqSym, nVar);
if iscell(llrCW)
    llr = llrCW{1};
else
    llr = llrCW;
end

% ---------------------- DL-SCH decode (rate recovery + LDPC decode) ----------------------
recLLR = sixgr.phy.phycode.rateRecoverLDPC(llr, trBlkSize, targetCodeRate, rv, pdsch.Modulation, pdsch.NumLayers);
recLLRBatch = localEnsureLLRBatch(recLLR);

% LDPC decode each code block
C = size(recLLRBatch, 2);
useMexLDPC = logical(sixgr.util.structGet(cfg, 'phy.ldpc.useMexBatchDecode', false)) ...
    && (exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3 || exist("sixgr_ldpc_decode_batch_kernel","file") == 2);

if useMexLDPC
    useNormMinSum = uint8(strcmpi(char(alg), 'Normalized min-sum'));
    try
        if exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3
            [decMat, decLen] = sixgr_ldpc_decode_batch_kernel_mex(recLLRBatch, bgn, maxIter, useNormMinSum);
        else
            [decMat, decLen] = sixgr_ldpc_decode_batch_kernel(recLLRBatch, bgn, maxIter, useNormMinSum);
        end
        maxLen = max(1, min(size(decMat,1), round(max(decLen(:)))));
        decCbs = int8(decMat(1:maxLen, :));
    catch
        useMexLDPC = false;
    end
end

if ~useMexLDPC
    nRow = size(recLLRBatch, 1);
    decCbs = zeros(nRow, C, 'int8');
    maxLen = 0;
    usePar = (C > 1) && logical(sixgr.util.structGet(cfg, 'run.useParallel', false)) ...
        && license('test','Distrib_Computing_Toolbox') && ~isempty(gcp('nocreate'));
    if usePar
        dCell = cell(C,1);
        dLen = zeros(C,1);
        parfor c = 1:C
            d = sixgr.phy.phycode.ldpcDecode(recLLRBatch(:,c), bgn, maxIter, alg);
            d = int8(d(:));
            dCell{c} = d;
            dLen(c) = min(numel(d), nRow);
        end
        for c = 1:C
            Ld = dLen(c);
            if Ld > 0
                decCbs(1:Ld, c) = dCell{c}(1:Ld);
                maxLen = max(maxLen, Ld);
            end
        end
    else
        for c = 1:C
            d = sixgr.phy.phycode.ldpcDecode(recLLRBatch(:,c), bgn, maxIter, alg);
            d = int8(d(:));
            Ld = min(numel(d), nRow);
            if Ld > 0
                decCbs(1:Ld, c) = d(1:Ld);
                maxLen = max(maxLen, Ld);
            end
        end
    end
    if maxLen <= 0
        decCbs = zeros(1, C, 'int8');
    else
        decCbs = decCbs(1:maxLen, :);
    end
end

% Desegment to TB+CRC
% NOTE: nrCodeBlockDesegmentLDPC expects the length of the TB with CRC. In
% 38.212 the TB CRC is always 24A for DL-SCH.
B = trBlkSize + 24;
tbCrcRx = sixgr.phy.tb.desegmentLDPC(decCbs, bgn, B);

% CRC check (24A)
[tbRx, crcOk, crcErr] = sixgr.phy.tb.checkCRC(tbCrcRx, '24A');

% ---------------------- Outputs ----------------------
rx = struct();
rx.TransportBlockSize = trBlkSize;
rx.CRCError = logical(crcErr);
rx.Ok = logical(crcOk);
rx.TimingOffset = timingOffset;
rx.NoiseVar = nVar;
if ~logical(opt.CompactOutput)
    rx.TransportBlock = tbRx;
    rx.CodewordLLR = llr;
    rx.RecLLR = recLLR;
    rx.BaseGraph = bgn;
    rx.ChannelEstimate = hEst;
    rx.DMRSIndices = dmrsInd;
    rx.PDSCHIndices = pdschInd;
end

info = struct();
info.CarrierInfo = cinfo;
info.OFDM = ofdmInfo;
info.PDSCHInfo = pdschInfo;

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

function x = localEnsureLLRBatch(xIn)
% Ensure a dense 2-D floating matrix for batch LDPC decode kernels.
x = xIn;
if ~(isa(x, 'double') || isa(x, 'single'))
    x = double(x);
end
if ~ismatrix(x)
    x = reshape(x, size(x,1), []);
else
    x = reshape(x, size(x,1), size(x,2));
end
end
