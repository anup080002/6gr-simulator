function [rx, info] = PUSCH_Rx(rxWaveform, cfg, varargin)
%PUSCH_Rx Recover a basic PUSCH transmission (OFDM -> PUSCH -> UL-SCH).
%
%   [RX,INFO] = sixgr.phy.ul.PUSCH_Rx(RXWAVEFORM, CFG) performs
%   DMRS-aided timing, OFDM demodulation, channel estimation,
%   MMSE equalization, nrPUSCHDecode demodulation, LDPC rate recovery,
%   LDPC decoding, and transport block CRC checking.
%
%   Name-Value options:
%     "Carrier"     : nrCarrierConfig override
%     "PUSCH"       : nrPUSCHConfig override
%     "PUSCHIndices": mapping indices override
%     "TransportBlockSize": expected TB size (bits)
%     "TargetCodeRate": code rate (0..1)
%     "RV"          : redundancy version (0..3)
%     "NoiseVar"    : noise variance (if known)
%     "MaxIterations": LDPC iterations
%     "Algorithm"   : LDPC algorithm ("Normalized min-sum" by default)
%
%   Outputs:
%     RX.TransportBlock     : recovered TB bits
%     RX.CRCError           : true if TB CRC fails
%     RX.Ok                 : ~CRCError
%     RX.CodewordLLR        : soft bits before rate recovery
%     RX.ChannelEstimate    : H estimate
%     RX.NoiseVar           : used noise variance
%     RX.TimingOffset       : estimated timing offset (samples)

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PUSCH', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PUSCHIndices', [], @(x) isempty(x) || isnumeric(x));
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

% PUSCH config and indices
if isempty(opt.PUSCH)
    [puschInd, puschInfo, pusch] = sixgr.phy.grid.allocREsPUSCH(carrier, cfg);
else
    pusch = opt.PUSCH;
    if isempty(opt.PUSCHIndices)
        try
            [puschInd, puschInfo] = nrPUSCHIndices(carrier, pusch, 'IndexStyle', 'index');
        catch
            [puschInd, puschInfo] = nrPUSCHIndices(carrier, pusch);
        end
    else
        puschInd = opt.PUSCHIndices;
        try
            [~, puschInfo] = nrPUSCHIndices(carrier, pusch, 'IndexStyle', 'index'); %#ok<ASGLU>
        catch
            [~, puschInfo] = nrPUSCHIndices(carrier, pusch); %#ok<ASGLU>
        end
    end
end

% Rx params
rv = opt.RV;
if isempty(rv)
    rv = double(sixgr.util.structGet(cfg, 'phy.pusch.rv', 0));
end

targetCodeRate = opt.TargetCodeRate;
if isempty(targetCodeRate)
    targetCodeRate = double(sixgr.util.structGet(cfg, 'phy.pusch.codeRate', 0.4785));
end

maxIter = opt.MaxIterations;
if isempty(maxIter)
    maxIter = double(sixgr.util.structGet(cfg, 'phy.ldpc.maxIterations', ...
        sixgr.util.structGet(cfg, 'phy.ldpc.maxIter', 12)));
end

alg = opt.Algorithm;
if isempty(alg)
    alg = sixgr.util.structGet(cfg, 'phy.ldpc.algorithm', 'Normalized min-sum');
end
alg = char(string(alg));

% Determine TB size
trBlkSize = opt.TransportBlockSize;
if isempty(trBlkSize)
    xOverhead = double(sixgr.util.structGet(cfg, 'phy.pusch.xOverhead', 0));
    nPRB = numel(pusch.PRBSet);
    nrePerPRB = [];
    if isfield(puschInfo, 'NREPerPRB')
        nrePerPRB = double(puschInfo.NREPerPRB);
    elseif isfield(puschInfo, 'NRE')
        nrePerPRB = floor(double(puschInfo.NRE) / max(nPRB,1));
    elseif isfield(puschInfo, 'G')
        qm = localQm(pusch.Modulation);
        nrePerPRB = floor(double(puschInfo.G) / max(qm * pusch.NumLayers * nPRB, 1));
    end
    if isempty(nrePerPRB) || ~isfinite(nrePerPRB) || nrePerPRB <= 0
        nrePerPRB = 144;
    end
    trBlkSize = nrTBS(pusch.Modulation, pusch.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead);
end
trBlkSize = double(trBlkSize);

% Base graph
try
    ulschInfo = nrULSCHInfo(trBlkSize, targetCodeRate);
    bgn = double(ulschInfo.BGN);
catch
    bgn = 2;
end

% DMRS
[dmrsInd, dmrsSym] = sixgr.phy.refsig.dmrsPUSCH(carrier, pusch);
useFastAWGNPath = logical(opt.FastAWGNPath);

% Timing estimate
toffset = 0;
if ~useFastAWGNPath
    try
        toffset = nrTimingEstimate(carrier, rxWaveform, dmrsInd, dmrsSym);
        toffset = max(0, double(toffset));
    catch
        toffset = 0;
    end
end

if toffset > 0 && (toffset+1) <= size(rxWaveform,1)
    rxWaveform = rxWaveform(1+toffset:end, :);
end

% OFDM demod
[rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, rxWaveform);

% Channel estimate
Hest = [];
nVarEst = [];
estInfo = struct();
useFastChEstMex = logical(sixgr.util.structGet(cfg, 'phy.rx.useFastChannelEstMex', false)) ...
    && logical(sixgr.util.structGet(cfg, 'run.useMex', false));
if useFastAWGNPath
    Hest = ones(size(rxGrid), 'like', rxGrid);
    nVarEst = 0;
else
    try
        [Hest, nVarEst, estInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, dmrsInd, dmrsSym, ...
            "UseFastMex", useFastChEstMex);
    catch
        Hest = [];
    end
end

% Noise variance
nVar = opt.NoiseVar;
if isempty(nVar)
    if ~isempty(nVarEst) && isfinite(nVarEst) && nVarEst >= 0
        nVar = nVarEst;
    else
        nVar = 1e-10;
    end
end
nVar = double(nVar);

% Extract resources
try
    [rxSym, hestSym] = nrExtractResources(puschInd, rxGrid, Hest);
catch
    rxSym = nrExtractResources(puschInd, rxGrid);
    % Fallback (SISO back-to-back): assume flat unit channel
    hestSym = ones(size(rxSym));
end

% Equalize
[eqSym, csi] = nrEqualizeMMSE(rxSym, hestSym, nVar);

% Decode PUSCH to codeword LLR
puschRxSym = [];
try
    [cwLLR, puschRxSym] = nrPUSCHDecode(carrier, pusch, eqSym, nVar);
catch
    cwLLR = nrPUSCHDecode(carrier, pusch, eqSym, nVar);
end

if iscell(cwLLR)
    cwLLR = cwLLR{1};
end
cwLLR = double(cwLLR(:));

% Rate recover (to code blocks)
recLLR = sixgr.phy.phycode.rateRecoverLDPC(cwLLR, trBlkSize, targetCodeRate, rv, pusch.Modulation, pusch.NumLayers);
recLLRBatch = localEnsureLLRBatch(recLLR);

% LDPC decode each code block
C = size(recLLRBatch, 2);
actIter = zeros(1, C);
parity = zeros(1, C);
useMexLDPC = logical(sixgr.util.structGet(cfg, 'phy.ldpc.useMexBatchDecode', false)) ...
    && (exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3 || exist("sixgr_ldpc_decode_batch_kernel","file") == 2);

if useMexLDPC
    useNormMinSum = uint8(strcmpi(char(alg), 'Normalized min-sum'));
    try
        if exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3
            [decMat, decLen, actIterV, parityV] = sixgr_ldpc_decode_batch_kernel_mex(recLLRBatch, bgn, maxIter, useNormMinSum);
        else
            [decMat, decLen, actIterV, parityV] = sixgr_ldpc_decode_batch_kernel(recLLRBatch, bgn, maxIter, useNormMinSum);
        end
        maxLen = max(1, min(size(decMat,1), round(max(decLen(:)))));
        decCbs = int8(decMat(1:maxLen, :));
        actIter(:) = reshape(actIterV(:), 1, []);
        parity(:) = reshape(parityV(:), 1, []);
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
        itV = zeros(C,1);
        pcV = zeros(C,1);
        parfor c = 1:C
            [d, it, pc] = sixgr.phy.phycode.ldpcDecode(recLLRBatch(:,c), bgn, maxIter, alg);
            d = int8(d(:));
            dCell{c} = d;
            dLen(c) = min(numel(d), nRow);
            it = it(:);
            pc = pc(:);
            if isempty(it), it = 0; end
            if isempty(pc), pc = 0; end
            itV(c) = it(1);
            pcV(c) = pc(1);
        end
        for c = 1:C
            actIter(c) = itV(c);
            parity(c) = pcV(c);
            Ld = dLen(c);
            if Ld > 0
                decCbs(1:Ld, c) = dCell{c}(1:Ld);
                maxLen = max(maxLen, Ld);
            end
        end
    else
        for c = 1:C
            [d, it, pc] = sixgr.phy.phycode.ldpcDecode(recLLRBatch(:,c), bgn, maxIter, alg);
            it = it(:);
            pc = pc(:);
            if isempty(it), it = 0; end
            if isempty(pc), pc = 0; end
            actIter(c) = it(1);
            parity(c) = pc(1);
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

% Code block desegmentation + TB CRC check
B = trBlkSize + 24;
tbCrc = sixgr.phy.tb.desegmentLDPC(decCbs, bgn, B);
[tbBits, crcOK, crcErr] = sixgr.phy.tb.checkCRC(tbCrc, '24A');

% Outputs
rx = struct();
rx.TransportBlockSize = trBlkSize;
rx.CRCError = logical(crcErr);
rx.Ok = logical(crcOK);
rx.NoiseVar = nVar;
rx.TimingOffset = toffset;
if ~logical(opt.CompactOutput)
    rx.TransportBlock = int8(tbBits(:));
    rx.CodewordLLR = cwLLR;
    rx.RateRecoveredLLR = recLLR;
    rx.DecodedCodeBlocks = decCbs;
    rx.ActiveIterations = actIter;
    rx.ParityChecks = parity;
    rx.ChannelEstimate = Hest;
    rx.Carrier = carrier;
    rx.PUSCH = pusch;
    rx.PUSCHInfo = puschInfo;
    rx.EqualizedSymbols = eqSym;
    rx.PUSCHRxSymbols = puschRxSym;
    rx.CSI = csi;
end

info = struct();
info.CarrierInfo = cinfo;
info.OFDM = ofdmInfo;
info.ChannelEstimation = estInfo;

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
