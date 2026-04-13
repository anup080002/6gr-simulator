function replay = replayGrant(cfgIn, direction, grant, payloadIn, snr_dB, varargin)
%REPLAYGRANT Replay one system grant through waveform PHY TX/channel/RX.

ip = inputParser;
ip.addParameter("InputFormat", "bits", @(x)ischar(x)||isstring(x));
ip.addParameter("StrictMode", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("CompactPHYIO", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("FastAWGNPath", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("AdaptiveLDPC", true, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("LDPCMaxIterations", 0, @(x)isnumeric(x)&&isscalar(x)&&x>=0);
ip.addParameter("UseGPU", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

if nargin < 4
    payloadIn = [];
end

dir = upper(string(direction));
replay = struct( ...
    "Ok", false, ...
    "BLER", 1.0, ...
    "Notes", "", ...
    "UsedFading", false, ...
    "FastAWGNPath", false, ...
    "ChannelModel", localResolveChannelToken(cfgIn), ...
    "ExecutionBackend", "WAVEFORM_GRANT_REPLAY", ...
    "PHYMode", "CRC_WAVEFORM_REPLAY", ...
    "TransportBlockSize", NaN, ...
    "DecoderIterations", NaN, ...
    "EffectiveTxAntennas", NaN, ...
    "EffectiveRxAntennas", NaN);

try
    cfgReplay = localBuildReplayConfig(cfgIn, dir, grant);
    replay.ChannelModel = localResolveChannelToken(cfgReplay);
    replay.EffectiveTxAntennas = double(sixgr.util.structGet(cfgReplay, "channel.nTxAnt", NaN));
    replay.EffectiveRxAntennas = double(sixgr.util.structGet(cfgReplay, "channel.nRxAnt", NaN));

    if dir == "UL"
        [tmpl, ~] = localBuildGrantAlignedPUSCHTx(cfgReplay, grant);
        tbBits = localNormalizeTransportBits(payloadIn, double(tmpl.TransportBlockSize), opt.InputFormat);
        [tx, txInfo] = sixgr.phy.ul.PUSCH_Tx(cfgReplay, ...
            "Carrier", tmpl.Carrier, ...
            "PUSCH", tmpl.PUSCH, ...
            "TransportBlockBits", tbBits, ...
            "RV", tmpl.RV, ...
            "TargetCodeRate", tmpl.TargetCodeRate, ...
            "CompactOutput", logical(opt.CompactPHYIO));
        replay.TransportBlockSize = double(tx.TransportBlockSize);
        chState = localInitChannelState(cfgReplay, tx, txInfo);
        [rxWave, nVar, chState] = localApplyChannelAndAwgn(tx.Waveform, snr_dB, chState);
        fastAWGNPath = logical(opt.FastAWGNPath) && localAllowsFastAWGN(cfgReplay, grant, chState);
        [rx, ~] = sixgr.phy.ul.PUSCH_Rx(rxWave, cfgReplay, ...
            "Carrier", tx.Carrier, ...
            "PUSCH", tx.PUSCH, ...
            "PUSCHIndices", tx.PUSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, ...
            "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, ...
            "NoiseVar", nVar, ...
            "MaxIterations", localLDPCMaxIterations(snr_dB, cfgReplay, opt), ...
            "CompactOutput", logical(opt.CompactPHYIO), ...
            "FastAWGNPath", fastAWGNPath, ...
            "SkipTimingEstimate", logical(chState.UseFading));
    else
        [tmpl, ~] = localBuildGrantAlignedPDSCHTx(cfgReplay, grant);
        tbBits = localNormalizeTransportBits(payloadIn, double(tmpl.TransportBlockSize), opt.InputFormat);
        [tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfgReplay, ...
            "Carrier", tmpl.Carrier, ...
            "PDSCH", tmpl.PDSCH, ...
            "TransportBlockBits", tbBits, ...
            "RV", tmpl.RV, ...
            "TargetCodeRate", tmpl.TargetCodeRate, ...
            "CompactOutput", logical(opt.CompactPHYIO));
        replay.TransportBlockSize = double(tx.TransportBlockSize);
        chState = localInitChannelState(cfgReplay, tx, txInfo);
        [rxWave, nVar, chState] = localApplyChannelAndAwgn(tx.Waveform, snr_dB, chState);
        fastAWGNPath = logical(opt.FastAWGNPath) && localAllowsFastAWGN(cfgReplay, grant, chState);
        [rx, ~] = sixgr.phy.dl.PDSCH_Rx(rxWave, cfgReplay, ...
            "Carrier", tx.Carrier, ...
            "PDSCH", tx.PDSCH, ...
            "PDSCHIndices", tx.PDSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, ...
            "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV, ...
            "NoiseVar", nVar, ...
            "MaxIterations", localLDPCMaxIterations(snr_dB, cfgReplay, opt), ...
            "CompactOutput", logical(opt.CompactPHYIO), ...
            "FastAWGNPath", fastAWGNPath, ...
            "SkipTimingEstimate", logical(chState.UseFading));
    end

    replay.Ok = logical(sixgr.util.structGet(rx, "Ok", false));
    replay.BLER = double(~replay.Ok);
    replay.UsedFading = logical(sixgr.util.structGet(chState, "UseFading", false));
    replay.FastAWGNPath = logical(fastAWGNPath);
    if isfield(rx, "ActiveIterations") && ~isempty(rx.ActiveIterations)
        replay.DecoderIterations = mean(double(rx.ActiveIterations(:)), "omitnan");
    end

    grantBits = double(sixgr.util.structGet(grant, "TBSBits", NaN));
    if isfinite(grantBits) && grantBits > 0 && isfinite(replay.TransportBlockSize) && ...
            round(grantBits) ~= round(replay.TransportBlockSize)
        msg = "Grant TBSBits=" + string(round(grantBits)) + ...
            " differs from waveform replay transport block size=" + string(round(replay.TransportBlockSize));
        if logical(opt.StrictMode)
            error("sixgr:system:WaveformReplay:TBSMismatch", "%s", char(msg));
        end
        replay.Notes = msg;
    end
catch ME
    if logical(opt.StrictMode)
        rethrow(ME);
    end
    replay.Ok = false;
    replay.BLER = 1.0;
    replay.Notes = "waveform_replay_failed: " + string(ME.message);
end
end

function cfgOut = localBuildReplayConfig(cfgIn, dir, grant)
cfgOut = cfgIn;
cfgOut.phy.rx.useFastChannelEstMex = false;

numLayers = max(1, round(double(sixgr.util.structGet(grant, "NumLayers", 1))));
txAnt = localEffectiveTxAntennas(cfgIn, dir, numLayers);
rxAnt = localEffectiveRxAntennas(cfgIn, dir, numLayers);
cfgOut.phy.nTxAnt = txAnt;
cfgOut.phy.nRxAnt = rxAnt;
cfgOut.channel.nTxAnt = txAnt;
cfgOut.channel.nRxAnt = rxAnt;

if dir == "UL"
    cfgOut.phy.pusch.numLayers = numLayers;
    cfgOut.phy.pusch.nLayers = numLayers;
else
    cfgOut.phy.pdsch.numLayers = numLayers;
    cfgOut.phy.pdsch.nLayers = numLayers;
end

cfgOut = localAlignReplayCarrierToGrant(cfgOut, grant);

modelRaw = upper(string(sixgr.util.structGet(cfgOut, "channel.model", "AWGN")));
if startsWith(modelRaw, "TDL")
    cfgOut.channel.model = "TDL";
    if modelRaw ~= "TDL"
        cfgOut.channel.tdlProfile = char(modelRaw);
    end
elseif startsWith(modelRaw, "CDL")
    cfgOut.channel.model = "CDL";
    if modelRaw ~= "CDL"
        cfgOut.channel.cdlProfile = char(modelRaw);
    end
else
    cfgOut.channel.model = char(modelRaw);
end
end

function cfgOut = localAlignReplayCarrierToGrant(cfgOut, grant)
requiredNSizeGrid = NaN;

prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
if ~isempty(prbSet)
    prbSet = unique(prbSet(isfinite(prbSet) & prbSet >= 0));
    if ~isempty(prbSet)
        requiredNSizeGrid = max(prbSet) + 1;
    end
end

if ~(isfinite(requiredNSizeGrid) && requiredNSizeGrid >= 1)
    nprb = double(sixgr.util.structGet(grant, "NPRB", NaN));
    if isfinite(nprb) && nprb >= 1
        requiredNSizeGrid = round(nprb);
    end
end

if ~(isfinite(requiredNSizeGrid) && requiredNSizeGrid >= 1)
    return;
end

currentNSizeGrid = double(sixgr.util.structGet(cfgOut, "phy.carrier.NSizeGrid", NaN));
if ~(isfinite(currentNSizeGrid) && currentNSizeGrid >= 1)
    currentNSizeGrid = requiredNSizeGrid;
end

cfgOut.phy.carrier.NSizeGrid = max(round(currentNSizeGrid), round(requiredNSizeGrid));
cfgOut.phy.carrier.NStartGrid = max(0, round(double(sixgr.util.structGet(cfgOut, "phy.carrier.NStartGrid", 0))));
end

function n = localEffectiveTxAntennas(cfg, dir, numLayers)
explicit = double(sixgr.util.structGet(cfg, "channel.nTxAnt", ...
    sixgr.util.structGet(cfg, "phy.nTxAnt", NaN)));
if isfinite(explicit) && explicit >= 1
    n = max(1, round(explicit));
    return;
end
if dir == "UL"
    ueTx = double(sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", 1));
    n = max(1, min(round(max(1, ueTx)), numLayers));
else
    n = max(1, round(numLayers));
end
end

function n = localEffectiveRxAntennas(cfg, dir, numLayers)
explicit = double(sixgr.util.structGet(cfg, "channel.nRxAnt", ...
    sixgr.util.structGet(cfg, "phy.nRxAnt", NaN)));
if isfinite(explicit) && explicit >= 1
    n = max(1, round(explicit));
    return;
end
if dir == "UL"
    bsRx = double(sixgr.util.structGet(cfg, "scenario.bs.nRxAnt", 1));
    n = max(1, min(round(max(1, bsRx)), max(numLayers, 1)));
else
    ueRx = double(sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", 1));
    n = max(1, min(round(max(1, ueRx)), max(numLayers, 1)));
end
end

function bits = localNormalizeTransportBits(payloadIn, expectedBits, inputFormat)
expectedBits = max(0, round(double(expectedBits)));
if expectedBits == 0
    bits = int8(zeros(0,1));
    return;
end

if isempty(payloadIn)
    bits = int8(randi([0 1], expectedBits, 1));
    return;
end

fmt = lower(char(string(inputFormat)));
if strcmp(fmt, "bytes")
    bits = sixgr.l2.mac.TBAssembler.bytesToBits(uint8(payloadIn(:)));
else
    bits = int8(payloadIn(:) ~= 0);
end

if numel(bits) < expectedBits
    bits(end+1:expectedBits,1) = 0;
elseif numel(bits) > expectedBits
    bits = bits(1:expectedBits);
end
bits = int8(bits(:));
end

function [tx0, grantUsed] = localBuildGrantAlignedPDSCHTx(cfgE, grant)
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgE);
[~, pdschInfo, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfgE);
grantUsed = grant;
if isfield(grant, "PRBSet") && ~isempty(grant.PRBSet) && isprop(pdsch, "PRBSet")
    pdsch.PRBSet = double(unique(grant.PRBSet(:).'));
end
if isfield(grant, "SymbolAllocation") && ~isempty(grant.SymbolAllocation) && isprop(pdsch, "SymbolAllocation")
    sa = double(grant.SymbolAllocation(:).');
    if numel(sa) >= 2
        pdsch.SymbolAllocation = sa(1:2);
    end
end
if isfield(grant, "Modulation") && ~isempty(grant.Modulation) && isprop(pdsch, "Modulation")
    pdsch.Modulation = char(string(grant.Modulation));
end
if isfield(grant, "NumLayers") && ~isempty(grant.NumLayers) && isprop(pdsch, "NumLayers")
    pdsch.NumLayers = max(1, round(double(grant.NumLayers)));
end
rv = localGrantRV(grant);
targetCodeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", ...
    sixgr.util.structGet(cfgE, "phy.pdsch.codeRate", 0.5)));
try
    [~, pdschInfo] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
catch
    [~, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
end
tx0 = struct( ...
    "Carrier", carrier, ...
    "PDSCH", pdsch, ...
    "RV", rv, ...
    "TargetCodeRate", targetCodeRate, ...
    "TransportBlockSize", localComputeTBSBitsFromAlloc(pdsch, pdschInfo, targetCodeRate, ...
        double(sixgr.util.structGet(cfgE, "phy.pdsch.xOverhead", 0))));
end

function [tx0, grantUsed] = localBuildGrantAlignedPUSCHTx(cfgE, grant)
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgE);
[~, puschInfo, pusch] = sixgr.phy.grid.allocREsPUSCH(carrier, cfgE);
grantUsed = grant;
if isfield(grant, "PRBSet") && ~isempty(grant.PRBSet) && isprop(pusch, "PRBSet")
    pusch.PRBSet = double(unique(grant.PRBSet(:).'));
end
if isfield(grant, "SymbolAllocation") && ~isempty(grant.SymbolAllocation) && isprop(pusch, "SymbolAllocation")
    sa = double(grant.SymbolAllocation(:).');
    if numel(sa) >= 2
        pusch.SymbolAllocation = sa(1:2);
    end
end
pusch = localNormalizeReplayPUSCHMapping(pusch);
if isfield(grant, "Modulation") && ~isempty(grant.Modulation) && isprop(pusch, "Modulation")
    pusch.Modulation = char(string(grant.Modulation));
end
if isfield(grant, "NumLayers") && ~isempty(grant.NumLayers) && isprop(pusch, "NumLayers")
    pusch.NumLayers = max(1, round(double(grant.NumLayers)));
end
rv = localGrantRV(grant);
targetCodeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", ...
    sixgr.util.structGet(cfgE, "phy.pusch.codeRate", 0.5)));
try
    [~, puschInfo] = nrPUSCHIndices(carrier, pusch, "IndexStyle", "index");
catch
    [~, puschInfo] = nrPUSCHIndices(carrier, pusch);
end
tx0 = struct( ...
    "Carrier", carrier, ...
    "PUSCH", pusch, ...
    "RV", rv, ...
    "TargetCodeRate", targetCodeRate, ...
    "TransportBlockSize", localComputeTBSBitsFromAlloc(pusch, puschInfo, targetCodeRate, ...
        double(sixgr.util.structGet(cfgE, "phy.pusch.xOverhead", 0))));
end

function tbsBits = localComputeTBSBitsFromAlloc(chCfg, chInfo, targetCodeRate, xOverhead)
nPRB = max(1, numel(chCfg.PRBSet));
nrePerPRB = [];
if isfield(chInfo, "NREPerPRB")
    nrePerPRB = double(chInfo.NREPerPRB);
elseif isfield(chInfo, "NRE")
    nrePerPRB = floor(double(chInfo.NRE) / max(nPRB, 1));
elseif isfield(chInfo, "G")
    qm = localQmFromModulation(chCfg.Modulation);
    nrePerPRB = floor(double(chInfo.G) / max(qm * double(chCfg.NumLayers) * nPRB, 1));
end
if isempty(nrePerPRB) || ~isfinite(nrePerPRB) || nrePerPRB <= 0
    nrePerPRB = 144;
end
tbsBits = double(nrTBS(chCfg.Modulation, chCfg.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead));
tbsBits = max(24, round(tbsBits));
end

function qm = localQmFromModulation(modScheme)
switch upper(char(string(modScheme)))
    case {"PI/2-BPSK","BPSK"}
        qm = 1;
    case "QPSK"
        qm = 2;
    case "16QAM"
        qm = 4;
    case "64QAM"
        qm = 6;
    case "256QAM"
        qm = 8;
    case "1024QAM"
        qm = 10;
    case "4096QAM"
        qm = 12;
    otherwise
        qm = 2;
end
end

function rv = localGrantRV(grant)
rv = double(sixgr.util.structGet(grant, "RV", NaN));
if ~(isscalar(rv) && isfinite(rv))
    harq = sixgr.util.structGet(grant, "HARQ", struct());
    rv = double(sixgr.util.structGet(harq, "RV", 0));
end
if ~(isscalar(rv) && isfinite(rv))
    rv = 0;
end
rv = max(0, min(3, round(rv)));
end

function pusch = localNormalizeReplayPUSCHMapping(pusch)
symAlloc = [0 14];
try
    if isprop(pusch, "SymbolAllocation") && ~isempty(pusch.SymbolAllocation)
        symAlloc = double(pusch.SymbolAllocation(:).');
    end
catch
end
startSym = 0;
if ~isempty(symAlloc)
    startSym = max(0, round(symAlloc(1)));
end

mapType = "A";
try
    if isprop(pusch, "MappingType") && ~isempty(pusch.MappingType)
        mapType = string(pusch.MappingType);
    end
catch
end
if startSym > 3 && upper(mapType) == "A"
    try
        if isprop(pusch, "MappingType")
            pusch.MappingType = 'B';
        end
    catch
    end
elseif strlength(mapType) == 0
    try
        if isprop(pusch, "MappingType")
            pusch.MappingType = 'A';
        end
    catch
    end
end
end

function state = localInitChannelState(cfg, tx, txInfo)
state = struct("Initialized", true, "UseFading", false, "Obj", [], ...
    "ChannelPadSamples", 0, "ChannelTrimSamples", 0);

modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
if awgnOnly || modelRaw == "AWGN" || modelRaw == "NONE" || modelRaw == "OFF"
    return;
end

cfgCh = cfg;
cfgCh.channel.doppler_Hz = max(0, double(sixgr.util.structGet(cfgCh, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfgCh, "channel.dopplerHz", ...
    sixgr.util.structGet(cfgCh, "channel.fading.maxDoppler_Hz", 0)))));

fs = localResolveSampleRate(tx, txInfo);
numTx = max(1, size(tx.Waveform, 2));
numRx = max(1, round(double(sixgr.util.structGet(cfgCh, "channel.nRxAnt", ...
    sixgr.util.structGet(cfgCh, "phy.nRxAnt", 1)))));

ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
    "Model", cfgCh.channel.model, ...
    "SampleRate", fs, ...
    "NumTxAnt", numTx, ...
    "NumRxAnt", numRx, ...
    "Seed", sixgr.util.structGet(cfgCh, "run.seed", 1));
if logical(sixgr.util.structGet(ch, "IsFading", false)) && isfield(ch, "Object") && ~isempty(ch.Object)
    state.UseFading = true;
    state.Obj = ch.Object;
    [padSamples, trimSamples] = localResolveChannelDelaySamples(ch.Object, fs);
    state.ChannelPadSamples = padSamples;
    state.ChannelTrimSamples = trimSamples;
end
end

function [y, nVar, state] = localApplyChannelAndAwgn(x, snr_dB, state)
y = x;
if isstruct(state) && logical(sixgr.util.structGet(state, "UseFading", false)) && ...
        isfield(state, "Obj") && ~isempty(state.Obj)
    try
        reset(state.Obj);
    catch
    end
    xIn = x;
    padSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelPadSamples", 0))));
    trimSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelTrimSamples", 0))));
    if padSamples > 0
        xIn = [x; zeros(padSamples, size(x,2), "like", x)];
    end
    try
        yRaw = state.Obj(xIn);
    catch
        [yRaw, ~] = state.Obj(xIn);
    end
    if trimSamples > 0 && size(yRaw,1) >= (trimSamples + size(x,1))
        y = yRaw(1+trimSamples:trimSamples+size(x,1), :);
    else
        y = yRaw;
        if size(y,1) > size(x,1)
            y = y(1:size(x,1), :);
        elseif size(y,1) < size(x,1)
            y(end+1:size(x,1), :) = cast(0, "like", y); %#ok<AGROW>
        end
    end
end
[y, nVar] = localAddAwgn(y, snr_dB);
end

function [y, nVar] = localAddAwgn(x, snr_dB)
snrLin = 10.^(double(snr_dB)/10);
sigPow = mean(abs(x(:)).^2);
nVar = sigPow / max(snrLin, eps);
n = sqrt(nVar/2) * (randn(size(x)) + 1i*randn(size(x)));
y = x + n;
end

function tf = localAllowsFastAWGN(cfg, grant, chState)
if logical(sixgr.util.structGet(chState, "UseFading", false))
    tf = false;
    return;
end
channelToken = localResolveChannelToken(cfg);
numLayers = max(1, round(double(sixgr.util.structGet(grant, "NumLayers", 1))));
numTxAnt = max(1, round(double(sixgr.util.structGet(cfg, "channel.nTxAnt", 1))));
numRxAnt = max(1, round(double(sixgr.util.structGet(cfg, "channel.nRxAnt", 1))));
tf = any(strcmp(channelToken, ["AWGN","NONE","OFF"])) && numLayers <= 1 && numTxAnt <= 1 && numRxAnt <= 1;
end

function token = localResolveChannelToken(cfg)
paths = { ...
    "channel.tdlProfile", ...
    "channel.cdlProfile", ...
    "channel.delayProfile", ...
    "channel.fading.profile", ...
    "channel.model", ...
    "channel.fading.model" ...
    };
token = "AWGN";
for i = 1:numel(paths)
    raw = string(sixgr.util.structGet(cfg, paths{i}, ""));
    raw = upper(strtrim(raw));
    if startsWith(raw, "TDL") || startsWith(raw, "CDL")
        token = raw;
        return;
    end
    if strlength(raw) > 0 && token == "AWGN"
        token = raw;
    end
end
end

function fs = localResolveSampleRate(tx, txInfo)
fs = [];
if nargin >= 2 && isstruct(txInfo)
    fs = sixgr.util.structGet(txInfo, "OFDM.SampleRate", []);
end
if isempty(fs) && isstruct(tx)
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if ~isempty(carrier)
        try
            ofdmInfo = nrOFDMInfo(carrier);
            fs = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
        catch
            fs = [];
        end
    end
end
if isempty(fs) || ~isfinite(double(fs)) || double(fs) <= 0
    fs = 30.72e6;
else
    fs = double(fs);
end
end

function [padSamples, trimSamples] = localResolveChannelDelaySamples(chObj, fs)
padSamples = 0;
trimSamples = 0;
if isempty(chObj) || ~isfinite(double(fs)) || double(fs) <= 0
    return;
end
filterDelay = 0;
pathDelays = [];
try
    chInfo = info(chObj);
    filterDelay = double(sixgr.util.structGet(chInfo, "ChannelFilterDelay", 0));
    pathDelays = sixgr.util.structGet(chInfo, "PathDelays", []);
catch
end
if isempty(pathDelays)
    try
        pathDelays = double(chObj.PathDelays);
    catch
        pathDelays = [];
    end
end
maxPathDelay = 0;
if ~isempty(pathDelays)
    maxPathDelay = ceil(max(double(pathDelays(:))) * double(fs));
end
% Keep enough waveform padding for the full channel memory, but only trim
% the implementation filter delay. The physical path delay must remain for
% timing and channel estimation to observe on fading grants.
padSamples = max(0, round(filterDelay + maxPathDelay));
trimSamples = max(0, round(filterDelay));
end

function maxIter = localLDPCMaxIterations(snr_dB, cfg, opt)
cfgMaxIter = round(double(sixgr.util.structGet(cfg, "phy.ldpc.maxIterations", 8)));
cfgMaxIter = max(1, cfgMaxIter);
hardMax = round(double(opt.LDPCMaxIterations));
if hardMax > 0
    maxIter = max(1, min(cfgMaxIter, hardMax));
    return;
end
if ~logical(opt.AdaptiveLDPC)
    maxIter = cfgMaxIter;
    return;
end
if snr_dB >= 20
    maxIter = min(cfgMaxIter, 4);
elseif snr_dB >= 12
    maxIter = min(cfgMaxIter, 5);
elseif snr_dB >= 8
    maxIter = min(cfgMaxIter, 6);
elseif snr_dB >= 4
    maxIter = min(cfgMaxIter, 7);
else
    maxIter = cfgMaxIter;
end
maxIter = max(1, round(maxIter));
end
