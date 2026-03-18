function out = runULPUSCHThroughput(cfg, varargin)
%RUNULPUSCHTHROUGHPUT UL PUSCH throughput/BLER at one SNR point.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("NumFrames", sixgr.util.structGet(cfg, "run.numFrames", 10), @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 18), @(x) isnumeric(x) && isscalar(x));
p.parse(varargin{:});
log = p.Results.Logger;
numFrames = max(1, round(double(p.Results.NumFrames)));
snr_dB = double(p.Results.SNR_dB);

out = struct();
out.Ok = false;
out.Skipped = false;
out.BER = NaN;
out.BLER = NaN;
out.Throughput_Mbps = NaN;
out.EVM_rms = NaN;
out.Notes = "";
out.NumFrames = numFrames;
out.SNR_dB = snr_dB;
out.TrialTable = localEmptyTrialTable();

if ~logical(sixgr.util.structGet(cfg, "phy.pusch.enable", true))
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: cfg.phy.pusch.enable=false";
    return;
end

if exist("nrPUSCH","file") ~= 2 || exist("nrPUSCHDecode","file") ~= 2
    out.Skipped = true;
    out.Ok = true;
    out.Notes = "Skipped: nrPUSCH APIs unavailable.";
    return;
end

% Keep this smoke path in a robust single-layer mode across releases.
cfgUL = cfg;
cfgUL.phy.pusch.numLayers = 1;
cfgUL.phy.pusch.nLayers = 1;

blockErr = 0;
bitErr = 0;
bitTot = 0;
bitGood = 0;
frameCrash = 0;
firstCrashMsg = "";
chState = struct("Initialized", false, "UseFading", false, "Obj", []);
seedBase = double(sixgr.util.structGet(cfgUL, "run.seed", 1));
chanModel = string(sixgr.util.structGet(cfgUL, "channel.model", "AWGN"));
dopplerHz = double(sixgr.util.structGet(cfgUL, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfgUL, "channel.dopplerHz", ...
    sixgr.util.structGet(cfgUL, "channel.fading.maxDoppler_Hz", 0))));
mcsIdx = double(sixgr.util.structGet(cfgUL, "phy.pusch.mcsIndex", NaN));

trialSeed = NaN(numFrames,1);
trialFrame = (1:numFrames).';
trialSlot = trialFrame;
trialMCS = NaN(numFrames,1);
trialPRB = NaN(numFrames,1);
trialLayers = NaN(numFrames,1);
trialTB = NaN(numFrames,1);
trialCRC = NaN(numFrames,1);
trialDecIt = NaN(numFrames,1);
trialEVM = NaN(numFrames,1);
trialNMSE = NaN(numFrames,1);
trialDet = NaN(numFrames,1);
trialBitErr = NaN(numFrames,1);
trialBitTot = NaN(numFrames,1);
trialStatus = strings(numFrames,1);
trialStatus(:) = "FAIL";
trialCrash = false(numFrames,1);
trialNotes = strings(numFrames,1);
trialChan = repmat(chanModel, numFrames, 1);
trialDopp = dopplerHz * ones(numFrames,1);

for n = 1:numFrames
    trialSeed(n) = seedBase + n - 1;
    trialMCS(n) = mcsIdx;
    try
        [tx, txInfo] = sixgr.phy.ul.PUSCH_Tx(cfgUL);
        if isfield(tx, "PUSCH")
            try
                trialPRB(n) = numel(tx.PUSCH.PRBSet);
            catch
            end
            try
                trialLayers(n) = double(tx.PUSCH.NumLayers);
            catch
            end
        end
        if isfield(tx, "TransportBlockSize")
            trialTB(n) = double(tx.TransportBlockSize);
        end
        if ~chState.Initialized
            chState = localInitChannelState(cfgUL, tx, txInfo);
        end
        rxWave = localApplyChannelAndAwgn(tx.Waveform, snr_dB, chState);

        [rx, ~] = sixgr.phy.ul.PUSCH_Rx(rxWave, cfgUL, ...
            "Carrier", tx.Carrier, ...
            "PUSCH", tx.PUSCH, ...
            "PUSCHIndices", tx.PUSCHIndices, ...
            "TransportBlockSize", tx.TransportBlockSize, ...
            "TargetCodeRate", tx.TargetCodeRate, ...
            "RV", tx.RV);

        txBits = int8(tx.TransportBlock(:));
        rxBits = int8(rx.TransportBlock(:));
        L = min(numel(txBits), numel(rxBits));
        if L == 0
            blockErr = blockErr + 1;
            continue;
        end

        be = sum(txBits(1:L) ~= rxBits(1:L));
        trialBitErr(n) = double(be);
        trialBitTot(n) = double(L);
        bitErr = bitErr + double(be);
        bitTot = bitTot + double(numel(txBits));
        if isfield(rx, "ActiveIterations") && ~isempty(rx.ActiveIterations)
            trialDecIt(n) = mean(double(rx.ActiveIterations(:)), "omitnan");
        end
        if isfield(rx, "EqualizedSymbols") && isfield(rx, "PUSCHRxSymbols")
            try
                e = double(rx.EqualizedSymbols(:)) - double(rx.PUSCHRxSymbols(:));
                p = max(mean(abs(double(rx.PUSCHRxSymbols(:))).^2), eps);
                trialEVM(n) = sqrt(mean(abs(e).^2) / p);
            catch
            end
        end

        if rx.Ok && be == 0 && numel(rxBits) == numel(txBits)
            bitGood = bitGood + double(numel(txBits));
            trialCRC(n) = 1;
            trialStatus(n) = "PASS";
        else
            blockErr = blockErr + 1;
            trialCRC(n) = 0;
            trialStatus(n) = "FAIL";
        end
    catch ME
        blockErr = blockErr + 1;
        frameCrash = frameCrash + 1;
        if strlength(firstCrashMsg) == 0
            firstCrashMsg = string(ME.message);
        end
        trialCrash(n) = true;
        trialStatus(n) = "CRASH";
        trialCRC(n) = 0;
        trialNotes(n) = string(ME.message);
        if ~isempty(log) && frameCrash <= 2
            log.warn("runULPUSCHThroughput frame failed: " + string(ME.message));
        end
    end
end

slotDur_s = localSlotDuration(cfg);
simDur_s = numFrames * slotDur_s;

out.BER = bitErr / max(bitTot, 1);
out.BLER = blockErr / max(numFrames, 1);
out.Throughput_Mbps = (bitGood / max(simDur_s, eps)) / 1e6;
out.Ok = out.BLER < 1;
out.Notes = "Frames=" + string(numFrames) + ", SNR=" + string(snr_dB) + " dB";

if frameCrash == numFrames
    out.Skipped = true;
    out.Ok = true;
    out.BER = NaN;
    out.BLER = NaN;
    out.Throughput_Mbps = NaN;
    out.Notes = "Skipped: UL chain unsupported in this release (" + firstCrashMsg + ")";
end

out.TrialTable = table( ...
    repmat("UL", numFrames, 1), snr_dB * ones(numFrames,1), trialSeed, trialFrame, trialSlot, ...
    trialMCS, trialPRB, trialLayers, trialTB, trialChan, trialDopp, trialCRC, trialDecIt, ...
    trialEVM, trialNMSE, trialDet, trialBitErr, trialBitTot, trialStatus, trialCrash, trialNotes, ...
    'VariableNames', {'Direction','SNR_dB','Seed','Frame','Slot','MCS','PRBs','Layers','TBSize_bits', ...
    'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB','DetectionMetric', ...
    'BitErrors','BitsCompared','Status','Crash','Notes'});
end

function y = localAddAwgn(x, snr_dB)
snrLin = 10.^(snr_dB/10);
sigPow = mean(abs(x(:)).^2);
nVar = sigPow / max(snrLin, eps);
n = sqrt(nVar/2) * (randn(size(x)) + 1i*randn(size(x)));
y = x + n;
end

function state = localInitChannelState(cfg, tx, txInfo)
state = struct("Initialized", true, "UseFading", false, "Obj", []);

modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
if awgnOnly || modelRaw == "AWGN" || modelRaw == "NONE" || modelRaw == "OFF"
    return;
end

cfgCh = cfg;
dopp = double(sixgr.util.structGet(cfgCh, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfgCh, "channel.dopplerHz", ...
    sixgr.util.structGet(cfgCh, "channel.fading.maxDoppler_Hz", 0))));
cfgCh.channel.doppler_Hz = max(0, dopp);

if startsWith(modelRaw, "TDL")
    cfgCh.channel.model = "TDL";
    if modelRaw ~= "TDL"
        cfgCh.channel.tdlProfile = char(modelRaw);
    end
elseif startsWith(modelRaw, "CDL")
    cfgCh.channel.model = "CDL";
    if modelRaw ~= "CDL"
        cfgCh.channel.cdlProfile = char(modelRaw);
    end
else
    cfgCh.channel.model = char(modelRaw);
end

fs = localResolveSampleRate(tx, txInfo);
numTx = max(1, size(tx.Waveform, 2));
numRx = max(1, double(sixgr.util.structGet(cfg, "phy.nRxAnt", numTx)));

ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
    "Model", cfgCh.channel.model, ...
    "SampleRate", fs, ...
    "NumTxAnt", numTx, ...
    "NumRxAnt", numRx, ...
    "Seed", sixgr.util.structGet(cfg, "run.seed", 1));
if logical(sixgr.util.structGet(ch, "IsFading", false)) && isfield(ch, "Object") && ~isempty(ch.Object)
    state.UseFading = true;
    state.Obj = ch.Object;
end
end

function y = localApplyChannelAndAwgn(x, snr_dB, state)
y = x;
if isstruct(state) && logical(sixgr.util.structGet(state, "UseFading", false)) && ...
        isfield(state, "Obj") && ~isempty(state.Obj)
    try
        reset(state.Obj);
    catch
    end
    try
        y = state.Obj(y);
    catch
        [y, ~] = state.Obj(y);
    end
end
y = localAddAwgn(y, snr_dB);
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

function slotDur_s = localSlotDuration(cfg)
scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
mu = log2(scs/15);
if ~isfinite(mu) || mu < 0
    mu = 0;
end
slotDur_s = 1e-3 / (2^mu);
end

function T = localEmptyTrialTable()
T = table(strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    strings(0,1), false(0,1), strings(0,1), ...
    'VariableNames', {'Direction','SNR_dB','Seed','Frame','Slot','MCS','PRBs','Layers','TBSize_bits', ...
    'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB','DetectionMetric', ...
    'BitErrors','BitsCompared','Status','Crash','Notes'});
end
