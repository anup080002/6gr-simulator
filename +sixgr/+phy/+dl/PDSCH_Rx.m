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
%     "PrecodingMatrix": wideband PDSCH precoder used by the transmitter
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
%     PDSCH allocation and explicit wideband precoder as the transmitter.

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
ip.addParameter('PrecodingMatrix', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('FastAWGNPath', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('SkipTimingEstimate', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
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

prec = sixgr.phy.dl.resolvePDSCHPrecoding(pdsch, cfg, ...
    "PrecodingMatrix", opt.PrecodingMatrix);

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
tbCRCType = '24A';
tbCRCLen = 24;
try
    dlschInfo = nrDLSCHInfo(trBlkSize, targetCodeRate);
    bgn = double(dlschInfo.BGN);
    [tbCRCType, tbCRCLen] = localResolveTBCRCSpec(dlschInfo, tbCRCType, tbCRCLen);
catch
    bgn = 2;
end

% DMRS
[dmrsInd, dmrsSym] = sixgr.phy.refsig.dmrsPDSCH(carrier, pdsch);
useFastAWGNPath = logical(opt.FastAWGNPath);
strictMode = logical(sixgr.util.structGet(cfg, 'run.strictMode', false));
channelModelToken = localResolveEstimatorChannelModel(cfg);
numTxPorts = localExpectedTxPorts(pdsch, prec);
localValidateFastScalarShortcut(channelModelToken, numTxPorts, max(1, size(rxWaveform, 2)), useFastAWGNPath, "PDSCH_Rx");

pdschAntInd = pdschInd;
dmrsAntInd = dmrsInd;
dmrsAntSym = dmrsSym;
if prec.Active
    pdschAntInd = localPrecodeIndices(carrier, pdschInd, prec.MatrixNR);
    [dmrsAntSym, dmrsAntInd] = nrPDSCHPrecode(carrier, dmrsSym, dmrsInd, prec.MatrixNR);
end

% ---------------------- Timing estimate ----------------------
timingOffset = 0;
if ~useFastAWGNPath && ~logical(opt.SkipTimingEstimate) && ~isempty(dmrsInd)
    try
        timingOffset = nrTimingEstimate(carrier, rxWaveform, dmrsInd, dmrsSym);
        timingOffset = double(timingOffset);
    catch
        timingOffset = 0;
    end
end

% Apply timing correction
if timingOffset > 0 && timingOffset < size(rxWaveform,1)
    rxWave = [rxWaveform(1+timingOffset:end, :); ...
        zeros(timingOffset, size(rxWaveform,2), 'like', rxWaveform)];
else
    rxWave = rxWaveform;
end

% ---------------------- OFDM demodulate ----------------------
[rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, rxWave);

% ---------------------- Channel estimate ----------------------
estInfo = struct();
useFastChEstMex = logical(sixgr.util.structGet(cfg, 'phy.rx.useFastChannelEstMex', false)) ...
    && logical(sixgr.util.structGet(cfg, 'run.useMex', false));
if useFastAWGNPath
    hEst = ones(size(rxGrid), 'like', rxGrid);
    nVarEst = 0;
    estInfo = struct( ...
        "EngineUsed", "unit-flat-shortcut", ...
        "ChannelModel", string(channelModelToken), ...
        "ExpectedTxPorts", double(numTxPorts), ...
        "NumRxAnt", double(max(1, size(rxGrid, 3))), ...
        "ScalarFastPathUsed", true);
elseif ~isempty(dmrsAntInd)
    % Under explicit precoding, the reference ports already define the
    % effective layer-domain channel seen by the receiver.
    [hEst, nVarEst, estInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, dmrsInd, dmrsSym, ...
        "UseFastMex", useFastChEstMex, ...
        "StrictMode", strictMode, ...
        "ChannelModel", channelModelToken, ...
        "ExpectedTxPorts", numTxPorts, ...
        "ContextLabel", "PDSCH_Rx");
else
    hEst = ones(size(rxGrid));
    nVarEst = 0;
    estInfo = struct( ...
        "EngineUsed", "unit-channel-no-dmrs", ...
        "ChannelModel", string(channelModelToken), ...
        "ExpectedTxPorts", double(numTxPorts), ...
        "NumRxAnt", double(max(1, size(rxGrid, 3))), ...
        "ScalarFastPathUsed", true);
end

nVar = opt.NoiseVar;
if isempty(nVar)
    nVar = nVarEst;
else
    nVar = localConvertNoiseVarToGridDomain(nVar, ofdmInfo);
end
nVar = double(max(0, nVar));

% ---------------------- Extract and equalize PDSCH REs ----------------------
[rxSym, hestSym] = nrExtractResources(pdschInd, rxGrid, hEst);
[eqSym, csi] = nrEqualizeMMSE(rxSym, hestSym, nVar);
% ---------------------- PDSCH demodulate to soft bits ----------------------
% nrPDSCHDecode returns a cell array (one per codeword). Newer releases can
% also return the sliced symbol estimates used during demodulation.
pdschRxSym = [];
try
    [llrCW, pdschRxSym] = nrPDSCHDecode(carrier, pdsch, eqSym, nVar);
catch
    llrCW = nrPDSCHDecode(carrier, pdsch, eqSym, nVar);
end
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
actIter = NaN(1, C);
parity = NaN(1, C);
decodeTic = tic;
useMexLDPC = logical(sixgr.util.structGet(cfg, 'phy.ldpc.useMexBatchDecode', false)) ...
    && (exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3 || exist("sixgr_ldpc_decode_batch_kernel","file") == 2);

if useMexLDPC
    useNormMinSum = uint8(strcmpi(char(alg), 'Normalized min-sum'));
    try
        if exist("sixgr_ldpc_decode_batch_kernel_mex","file") == 3
            try
                [decMat, decLen, actIterV, parityV] = sixgr_ldpc_decode_batch_kernel_mex(recLLRBatch, bgn, maxIter, useNormMinSum);
            catch
                [decMat, decLen] = sixgr_ldpc_decode_batch_kernel_mex(recLLRBatch, bgn, maxIter, useNormMinSum);
                actIterV = NaN(C, 1);
                parityV = NaN(C, 1);
            end
        else
            try
                [decMat, decLen, actIterV, parityV] = sixgr_ldpc_decode_batch_kernel(recLLRBatch, bgn, maxIter, useNormMinSum);
            catch
                [decMat, decLen] = sixgr_ldpc_decode_batch_kernel(recLLRBatch, bgn, maxIter, useNormMinSum);
                actIterV = NaN(C, 1);
                parityV = NaN(C, 1);
            end
        end
        maxLen = max(1, min(size(decMat,1), round(max(decLen(:)))));
        decCbs = int8(decMat(1:maxLen, :));
        actIter = reshape(double(actIterV(:)), 1, []);
        parity = reshape(double(parityV(:)), 1, []);
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
        itV = NaN(C,1);
        pcV = NaN(C,1);
        parfor c = 1:C
            [d, it, pc] = sixgr.phy.phycode.ldpcDecode(recLLRBatch(:,c), bgn, maxIter, alg);
            d = int8(d(:));
            dCell{c} = d;
            dLen(c) = min(numel(d), nRow);
            it = it(:);
            pc = pc(:);
            if isempty(it), it = NaN; end
            if isempty(pc), pc = NaN; end
            itV(c) = double(it(1));
            pcV(c) = double(pc(1));
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
            if isempty(it), it = NaN; end
            if isempty(pc), pc = NaN; end
            actIter(c) = double(it(1));
            parity(c) = double(pc(1));
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
decodeLatency_s = toc(decodeTic);

% Desegment to TB+CRC using the CRC selected by nrDLSCHInfo for this TBS.
B = trBlkSize + tbCRCLen;
[tbCrcRx, cbCrcErr] = sixgr.phy.tb.desegmentLDPC(decCbs, bgn, B);

% CRC check must match the transmitter's TB CRC type for this TBS.
[tbRx, crcOk, crcErr] = sixgr.phy.tb.checkCRC(tbCrcRx, tbCRCType);

% ---------------------- Outputs ----------------------
rx = struct();
rx.TransportBlockSize = trBlkSize;
rx.CRCError = logical(crcErr);
rx.Ok = logical(crcOk);
rx.TimingOffset = timingOffset;
rx.NoiseVar = nVar;
rx.DecodeLatency_s = double(decodeLatency_s);
rx.MaxDecoderIterations = double(maxIter);
if ~logical(opt.CompactOutput)
    rx.TransportBlock = tbRx;
    rx.CodewordLLR = llr;
    rx.RecLLR = recLLR;
    rx.BaseGraph = bgn;
    rx.DecodedCodeBlocks = decCbs;
    rx.ActiveIterations = actIter;
    rx.ParityChecks = parity;
    rx.CodeBlockCRCError = cbCrcErr;
    rx.ChannelEstimate = hEst;
    rx.DMRSIndices = dmrsInd;
    rx.DMRSAntennaIndices = dmrsAntInd;
    rx.PDSCHAntennaIndices = pdschAntInd;
    rx.PDSCHIndices = pdschInd;
    rx.CSI = csi;
    rx.PrecodeInfo = prec;
    rx.EqualizedSymbols = eqSym;
    rx.PDSCHRxSymbols = pdschRxSym;
end

info = struct();
info.CarrierInfo = cinfo;
info.OFDM = ofdmInfo;
info.PDSCHInfo = pdschInfo;
info.Precoding = prec;
info.ChannelEstimation = estInfo;

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

function nVarGrid = localConvertNoiseVarToGridDomain(nVarTime, ofdmInfo)
nVarGrid = double(nVarTime);
if nargin < 2 || ~isstruct(ofdmInfo)
    return;
end
nfft = double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN));
if isfinite(nfft) && nfft > 0
    nVarGrid = nVarGrid * nfft;
end
end

function antInd = localPrecodeIndices(carrier, portInd, Wnr)
dummySym = complex(zeros(size(portInd)));
[~, antInd] = nrPDSCHPrecode(carrier, dummySym, portInd, Wnr);
end

function numTxPorts = localExpectedTxPorts(pdsch, prec)
numTxPorts = 1;
try
    numTxPorts = max(numTxPorts, double(pdsch.NumLayers));
catch
end
if nargin >= 2 && isstruct(prec) && logical(sixgr.util.structGet(prec, "Active", false))
    Wnr = sixgr.util.structGet(prec, "MatrixNR", []);
    if ~isempty(Wnr)
        numTxPorts = max(numTxPorts, size(Wnr, 1));
    end
end
if ~(isscalar(numTxPorts) && isfinite(numTxPorts) && numTxPorts >= 1)
    numTxPorts = 1;
end
numTxPorts = max(1, round(numTxPorts));
end

function localValidateFastScalarShortcut(channelToken, numTxPorts, numRxAnt, useFastAWGNPath, contextLabel)
if ~logical(useFastAWGNPath)
    return;
end
if ~(localIsExplicitFlatChannel(channelToken) && numTxPorts <= 1 && numRxAnt <= 1)
    error("sixgr:phy:rx:InvalidFastScalarShortcut", ...
        "%s requires an explicit AWGN/flat SISO validation mode. Channel='%s', TxPorts=%d, RxAnt=%d.", ...
        contextLabel, localDisplayChannelToken(channelToken), numTxPorts, numRxAnt);
end
end

function channelToken = localResolveEstimatorChannelModel(cfg)
candidates = { ...
    sixgr.util.structGet(cfg, 'channel.tdlProfile', ''), ...
    sixgr.util.structGet(cfg, 'channel.cdlProfile', ''), ...
    sixgr.util.structGet(cfg, 'channel.delayProfile', ''), ...
    sixgr.util.structGet(cfg, 'channel.fading.profile', ''), ...
    sixgr.util.structGet(cfg, 'channel.model', ''), ...
    sixgr.util.structGet(cfg, 'channel.fading.model', '') ...
    };

channelToken = "";
for i = 1:numel(candidates)
    token = localNormalizeChannelToken(candidates{i});
    if startsWith(token, "TDL") || startsWith(token, "CDL")
        channelToken = token;
        return;
    end
    if strlength(token) > 0 && strlength(channelToken) == 0
        channelToken = token;
    end
end
end

function token = localNormalizeChannelToken(rawValue)
token = upper(strtrim(string(rawValue)));
end

function tf = localIsExplicitFlatChannel(channelToken)
tf = any(strcmpi(char(string(channelToken)), {'AWGN', 'NONE', 'OFF'}));
end

function token = localDisplayChannelToken(channelToken)
token = char(string(channelToken));
if isempty(token)
    token = '<unspecified>';
end
end
