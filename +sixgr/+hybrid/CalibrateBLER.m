function calib = CalibrateBLER(ctx, params)
%CALIBRATEBLER Build context-aware BLER calibration DB from link-level sweeps.
%
% Performance-oriented options (all optional via params):
%   UseParallel                   : use existing/auto-started pool for core cases
%   AutoStartParallelPool         : start parpool when UseParallel=true and none exists
%   ReuseCoreAcrossChannelDoppler : run truth sweep once per core case and
%                                   reuse across channel/doppler via lightweight shift model
%                                   (disabled in strict mode)
%   EnableCheckpoint              : periodically save calibration progress
%   ResumeFromCheckpoint          : resume from saved checkpoint when signature matches
%   CheckpointChunkSize           : number of core cases per checkpoint flush
%   CheckpointFile                : MAT checkpoint path

if nargin < 2 || isempty(params)
    params = struct();
end

cfg = ctx.Cfg;
log = ctx.Logger;
strictMode = logical(sixgr.util.structGet(cfg, "run.strictMode", false));

allowFallbackFill = logical(sixgr.util.structGet(params, "AllowFallbackFill", ...
    sixgr.util.structGet(cfg, "hybrid.allowFallbackFill", false)));
if strictMode
    allowFallbackFill = false;
end

snrGrid = sixgr.util.structGet(params, "SNRGrid_dB", ...
          sixgr.util.structGet(cfg, "hybrid.snrGrid_dB", -8:2:24));
snrGrid = double(snrGrid(:));
if isempty(snrGrid)
    error("sixgr:hybrid:CalibrateBLER:EmptySNRGrid", "SNR grid is empty.");
end

numFrames = double(sixgr.util.structGet(params, "CalibFrames", ...
          min(12, max(4, sixgr.util.structGet(cfg, "run.numFrames", 10)))));
numFrames = max(1, round(numFrames));
verboseCalib = logical(sixgr.util.structGet(params, "CalibVerbose", false));

useParallelReq = logical(sixgr.util.structGet(params, "UseParallel", ...
    sixgr.util.structGet(params, "CalibUseParallel", ...
    sixgr.util.structGet(cfg, "run.useParallel", false))));
autoStartPool = logical(sixgr.util.structGet(params, "AutoStartParallelPool", ...
    sixgr.util.structGet(params, "CalibAutoStartPool", false)));
[useParallel, nWorkers] = localResolveParallel(useParallelReq, autoStartPool);

reuseAcrossContext = logical(sixgr.util.structGet(params, "ReuseCoreAcrossChannelDoppler", ...
    sixgr.util.structGet(params, "CalibReuseCoreAcrossChannelDoppler", ...
    sixgr.util.structGet(cfg, "hybrid.reuseCoreAcrossChannelDoppler", false))));
if strictMode
    reuseAcrossContext = false;
end

checkpointEnable = logical(sixgr.util.structGet(params, "EnableCheckpoint", ...
    sixgr.util.structGet(params, "CalibEnableCheckpoint", true)));
checkpointResume = logical(sixgr.util.structGet(params, "ResumeFromCheckpoint", ...
    sixgr.util.structGet(params, "CalibResumeFromCheckpoint", true)));
checkpointFile = localResolveCheckpointFile(ctx, params);

axesCfg = localResolveAxes(cfg, params);
dirAxis = string(axesCfg.Direction(:).');
mcsAxis = double(axesCfg.MCS(:).');
prbAxis = double(axesCfg.PRB(:).');
layerAxis = double(axesCfg.Layers(:).');
scsAxis = double(axesCfg.SCS(:).');
doppAxis = double(axesCfg.DopplerHz(:).');
chAxis = upper(string(axesCfg.ChannelModel(:).'));

blankB = zeros(numel(dirAxis), numel(mcsAxis), numel(prbAxis), numel(layerAxis), ...
    numel(scsAxis), numel(doppAxis), numel(chAxis), numel(snrGrid));
db = sixgr.system.BLER_DB("SNR_dB", snrGrid, ...
    "Direction", dirAxis, "MCS", mcsAxis, "PRB", prbAxis, ...
    "Layers", layerAxis, "SCS", scsAxis, "DopplerHz", doppAxis, ...
    "ChannelModel", chAxis, "BLER", blankB, "Source", "lls_calibration_truth");
B = NaN(size(db.BLER));
skipped = false(size(db.BLER));

refLut = [];
if allowFallbackFill
    refLut = sixgr.system.BLER_LUT("SNR_dB", snrGrid);
end

coreIndex = localBuildCoreIndex(numel(dirAxis), numel(mcsAxis), numel(prbAxis), ...
    numel(layerAxis), numel(scsAxis));
nCore = size(coreIndex, 1);
contextsPerCore = numel(doppAxis) * numel(chAxis);

sig = localBuildCheckpointSignature(dirAxis, mcsAxis, prbAxis, layerAxis, ...
    scsAxis, doppAxis, chAxis, snrGrid, numFrames, strictMode, ...
    allowFallbackFill, reuseAcrossContext);

completedCore = false(nCore, 1);
if checkpointEnable && checkpointResume && strlength(string(checkpointFile)) > 0 && exist(checkpointFile, "file") == 2
    try
        ck = load(checkpointFile);
        if isfield(ck, "Signature") && localCheckpointSignatureMatch(ck.Signature, sig) && ...
                isfield(ck, "B") && isequal(size(ck.B), size(B)) && ...
                isfield(ck, "Skipped") && isequal(size(ck.Skipped), size(skipped)) && ...
                isfield(ck, "CompletedCore") && numel(ck.CompletedCore) == nCore
            B = double(ck.B);
            skipped = logical(ck.Skipped);
            completedCore = logical(ck.CompletedCore(:));
        end
    catch
    end
end

if verboseCalib
    try
        log.info("CalibrateBLER: coreCases=" + string(nCore) + ...
            ", contextsPerCore=" + string(contextsPerCore) + ...
            ", parallel=" + string(useParallel) + ...
            ", workers=" + string(nWorkers) + ...
            ", reuseAcrossChannelDoppler=" + string(reuseAcrossContext));
    catch
    end
end

if nCore == 0
    error("sixgr:hybrid:CalibrateBLER:NoCombos", "No calibration combinations resolved.");
end

defaultChunk = 1;
if useParallel
    defaultChunk = max(1, 2 * max(1, nWorkers));
end
chunkSize = max(1, round(double(sixgr.util.structGet(params, "CheckpointChunkSize", ...
    sixgr.util.structGet(params, "CalibChunkSize", defaultChunk)))));

for c0 = 1:chunkSize:nCore
    c1 = min(nCore, c0 + chunkSize - 1);
    chunk = c0:c1;
    pending = chunk(~completedCore(chunk));
    if isempty(pending)
        continue;
    end

    resultCell = cell(numel(pending), 1);
    loggerForSweep = [];
    if verboseCalib && ~useParallel
        loggerForSweep = log;
    end

    if useParallel && numel(pending) > 1
        parfor ii = 1:numel(pending)
            core = coreIndex(pending(ii), :);
            resultCell{ii} = localEvaluateCoreCase(cfg, core, dirAxis, mcsAxis, prbAxis, ...
                layerAxis, scsAxis, doppAxis, chAxis, snrGrid, numFrames, ...
                loggerForSweep, reuseAcrossContext);
        end
    else
        for ii = 1:numel(pending)
            core = coreIndex(pending(ii), :);
            resultCell{ii} = localEvaluateCoreCase(cfg, core, dirAxis, mcsAxis, prbAxis, ...
                layerAxis, scsAxis, doppAxis, chAxis, snrGrid, numFrames, ...
                loggerForSweep, reuseAcrossContext);
        end
    end

    for ii = 1:numel(pending)
        core = coreIndex(pending(ii), :);
        iDir = core(1); iM = core(2); iP = core(3); iL = core(4); iS = core(5);
        R = resultCell{ii};
        B(iDir,iM,iP,iL,iS,:,:, :) = reshape(R.BLER, 1,1,1,1,1, ...
            numel(doppAxis), numel(chAxis), numel(snrGrid));
        skipped(iDir,iM,iP,iL,iS,:,:, :) = reshape(R.Skipped, 1,1,1,1,1, ...
            numel(doppAxis), numel(chAxis), numel(snrGrid));
        completedCore(pending(ii)) = true;
    end

    if checkpointEnable && strlength(string(checkpointFile)) > 0
        localWriteCheckpoint(checkpointFile, sig, B, skipped, completedCore);
    end
end

if ~all(completedCore)
    error("sixgr:hybrid:CalibrateBLER:Incomplete", ...
        "Calibration did not complete all core combinations.");
end

if any(~isfinite(B), "all")
    if strictMode || ~allowFallbackFill
        localThrowMissingPoint(B, dirAxis, mcsAxis, prbAxis, layerAxis, scsAxis, doppAxis, chAxis, snrGrid);
    end
    B = localFillNaNWithReference(B, refLut.BLER);
end

% Enforce physically meaningful trend: BLER non-increasing with SNR.
for iDir = 1:numel(dirAxis)
    for iM = 1:numel(mcsAxis)
        for iP = 1:numel(prbAxis)
            for iL = 1:numel(layerAxis)
                for iS = 1:numel(scsAxis)
                    for iD = 1:numel(doppAxis)
                        for iC = 1:numel(chAxis)
                            b = squeeze(B(iDir,iM,iP,iL,iS,iD,iC,:));
                            for k = 2:numel(b)
                                b(k) = min(b(k), b(k-1));
                            end
                            b = min(max(b, 1e-4), 0.9999);
                            B(iDir,iM,iP,iL,iS,iD,iC,:) = reshape(b, 1,1,1,1,1,1,1,[]);
                        end
                    end
                end
            end
        end
    end
end

if strictMode && any(~isfinite(B), "all")
    error("sixgr:hybrid:CalibrateBLER:StrictNaN", ...
        "Strict mode requires complete calibration DB without NaNs.");
end

B(~isfinite(B)) = 0.9999;
db.BLER = B;
db.Source = "lls_calibration_truth";
db = sixgr.system.BLER_DB(db);

dlCurve = localDirectionAverage(db, "DL");
ulCurve = localDirectionAverage(db, "UL");
sysCurve = min(max(0.5 * (dlCurve + ulCurve), 1e-4), 0.9999);
lut = sixgr.system.BLER_LUT("SNR_dB", snrGrid, "BLER", sysCurve);
lut.Source = "calibrated_db_avg";

[T, C] = localBuildCalibrationTables(db, skipped);

calib = struct();
calib.DB = db;
calib.LUT = lut;
calib.Table = T;
calib.ComboTable = C;
calib.NumFrames = numFrames;
calib.StrictMode = strictMode;
calib.AllowFallbackFill = allowFallbackFill;
calib.UseParallel = useParallel;
calib.NumWorkers = nWorkers;
calib.ReuseCoreAcrossChannelDoppler = reuseAcrossContext;
calib.CheckpointFile = string(checkpointFile);
end

function [useParallel, nWorkers] = localResolveParallel(useParallelReq, autoStartPool)
useParallel = false;
nWorkers = 0;
if ~logical(useParallelReq)
    return;
end
if exist("gcp", "file") ~= 2 || exist("parfor", "builtin") ~= 5
    return;
end
pool = [];
try
    pool = gcp("nocreate");
catch
    pool = [];
end
if isempty(pool) && logical(autoStartPool)
    try
        pool = parpool("local");
    catch
        pool = [];
    end
end
if isempty(pool)
    return;
end
nWorkers = max(1, round(double(pool.NumWorkers)));
useParallel = (nWorkers >= 2);
end

function checkpointFile = localResolveCheckpointFile(ctx, params)
checkpointFile = char(string(sixgr.util.structGet(params, "CheckpointFile", ...
    sixgr.util.structGet(params, "CalibCheckpointFile", ""))));
if strlength(string(checkpointFile)) > 0
    sixgr.util.ensureDir(checkpointFile);
    return;
end
runFolder = "";
try
    runFolder = string(ctx.RunFolder);
catch
    runFolder = "";
end
if strlength(runFolder) > 0
    checkpointFile = fullfile(char(runFolder), "mat", "hybrid_calibration_checkpoint.mat");
    sixgr.util.ensureDir(checkpointFile);
else
    checkpointFile = "";
end
end

function sig = localBuildCheckpointSignature(dirAxis, mcsAxis, prbAxis, layerAxis, ...
    scsAxis, doppAxis, chAxis, snrGrid, numFrames, strictMode, allowFallbackFill, reuseAcrossContext)
sig = struct();
sig.Version = 2;
sig.Direction = string(dirAxis(:).');
sig.MCS = double(mcsAxis(:).');
sig.PRB = double(prbAxis(:).');
sig.Layers = double(layerAxis(:).');
sig.SCS = double(scsAxis(:).');
sig.DopplerHz = double(doppAxis(:).');
sig.ChannelModel = upper(string(chAxis(:).'));
sig.SNR_dB = double(snrGrid(:).');
sig.NumFrames = double(numFrames);
sig.StrictMode = logical(strictMode);
sig.AllowFallbackFill = logical(allowFallbackFill);
sig.ReuseCoreAcrossChannelDoppler = logical(reuseAcrossContext);
end

function tf = localCheckpointSignatureMatch(a, b)
tf = false;
req = ["Version","Direction","MCS","PRB","Layers","SCS","DopplerHz", ...
    "ChannelModel","SNR_dB","NumFrames","StrictMode","AllowFallbackFill","ReuseCoreAcrossChannelDoppler"];
for i = 1:numel(req)
    if ~isfield(a, req(i)) || ~isfield(b, req(i))
        return;
    end
end
tf = isequaln(double(a.Version), double(b.Version)) && ...
    isequaln(upper(string(a.Direction(:).')), upper(string(b.Direction(:).'))) && ...
    isequaln(double(a.MCS(:).'), double(b.MCS(:).')) && ...
    isequaln(double(a.PRB(:).'), double(b.PRB(:).')) && ...
    isequaln(double(a.Layers(:).'), double(b.Layers(:).')) && ...
    isequaln(double(a.SCS(:).'), double(b.SCS(:).')) && ...
    isequaln(double(a.DopplerHz(:).'), double(b.DopplerHz(:).')) && ...
    isequaln(upper(string(a.ChannelModel(:).')), upper(string(b.ChannelModel(:).'))) && ...
    isequaln(double(a.SNR_dB(:).'), double(b.SNR_dB(:).')) && ...
    isequaln(double(a.NumFrames), double(b.NumFrames)) && ...
    isequaln(logical(a.StrictMode), logical(b.StrictMode)) && ...
    isequaln(logical(a.AllowFallbackFill), logical(b.AllowFallbackFill)) && ...
    isequaln(logical(a.ReuseCoreAcrossChannelDoppler), logical(b.ReuseCoreAcrossChannelDoppler));
end

function localWriteCheckpoint(checkpointFile, sig, B, skipped, completedCore)
if strlength(string(checkpointFile)) == 0
    return;
end
payload = struct();
payload.Signature = sig;
payload.B = B;
payload.Skipped = skipped;
payload.CompletedCore = logical(completedCore(:));
payload.GeneratedUTC = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
try
    sixgr.util.matSave(checkpointFile, payload);
catch
end
end

function idx = localBuildCoreIndex(nDir, nM, nP, nL, nS)
idx = zeros(nDir*nM*nP*nL*nS, 5);
k = 0;
for iDir = 1:nDir
    for iM = 1:nM
        for iP = 1:nP
            for iL = 1:nL
                for iS = 1:nS
                    k = k + 1;
                    idx(k, :) = [iDir iM iP iL iS];
                end
            end
        end
    end
end
end

function R = localEvaluateCoreCase(cfg, core, dirAxis, mcsAxis, prbAxis, layerAxis, ...
    scsAxis, doppAxis, chAxis, snrGrid, numFrames, caseLogger, reuseAcrossContext)
iDir = core(1); iM = core(2); iP = core(3); iL = core(4); iS = core(5);
nD = numel(doppAxis);
nC = numel(chAxis);
nN = numel(snrGrid);

blerOut = NaN(nD, nC, nN);
skipOut = false(nD, nC, nN);

if reuseAcrossContext
    iDRef = 1;
    iCRef = 1;
    cfgRef = localBuildCalibCfg(cfg, dirAxis(iDir), mcsAxis(iM), prbAxis(iP), ...
        layerAxis(iL), scsAxis(iS), doppAxis(iDRef), chAxis(iCRef), caseLogger);
    [baseCurve, baseSkip] = localRunSingleSweep(cfgRef, dirAxis(iDir), snrGrid, numFrames, caseLogger);
    for iD = 1:nD
        for iC = 1:nC
            adj = localApplyContextAdjustments(baseCurve, snrGrid, scsAxis(iS), ...
                doppAxis(iDRef), chAxis(iCRef), doppAxis(iD), chAxis(iC));
            blerOut(iD, iC, :) = reshape(adj, 1, 1, nN);
            skipOut(iD, iC, :) = reshape(baseSkip, 1, 1, nN);
        end
    end
else
    for iD = 1:nD
        for iC = 1:nC
            cCfg = localBuildCalibCfg(cfg, dirAxis(iDir), mcsAxis(iM), prbAxis(iP), ...
                layerAxis(iL), scsAxis(iS), doppAxis(iD), chAxis(iC), caseLogger);
            [blerCtx, skipCtx] = localRunSingleSweep(cCfg, dirAxis(iDir), snrGrid, numFrames, caseLogger);
            blerOut(iD, iC, :) = reshape(blerCtx, 1, 1, nN);
            skipOut(iD, iC, :) = reshape(skipCtx, 1, 1, nN);
        end
    end
end

R = struct("BLER", blerOut, "Skipped", skipOut);
end

function b = localApplyContextAdjustments(baseCurve, snrGrid, scs_kHz, doppRef, chRef, doppCur, chCur)
b = double(baseCurve(:));
if isempty(b)
    return;
end

penRef = localContextPenalty(scs_kHz, doppRef, chRef);
penCur = localContextPenalty(scs_kHz, doppCur, chCur);
snrShift_dB = penCur - penRef;

if ~isfinite(snrShift_dB)
    snrShift_dB = 0;
end

snr = double(snrGrid(:));
q = interp1(snr, b, snr - snrShift_dB, "linear", "extrap");
q = min(max(q, 1e-4), 0.9999);
for k = 2:numel(q)
    q(k) = min(q(k), q(k-1));
end
b = q;
end

function p = localContextPenalty(scs_kHz, dopplerHz, channelModel)
p = 0;
% Higher Doppler is harder (small positive SNR penalty).
p = p + 0.003 * max(0, double(dopplerHz));

% Mild SCS dependency around 30 kHz baseline.
p = p + 0.02 * (double(scs_kHz) - 30) / 30;

ch = upper(string(channelModel));
if startsWith(ch, "AWGN")
    p = p + 0;
elseif startsWith(ch, "TDL")
    p = p + 0.8;
elseif startsWith(ch, "CDL")
    p = p + 1.3;
else
    p = p + 0.5;
end
end

function B = localFillNaNWithReference(B, refBler)
for iN = 1:numel(refBler)
    sl = B(:,:,:,:,:,:,:,iN);
    m = ~isfinite(sl);
    if any(m, "all")
        sl(m) = double(refBler(iN));
        B(:,:,:,:,:,:,:,iN) = sl;
    end
end
end

function localThrowMissingPoint(B, dirAxis, mcsAxis, prbAxis, layerAxis, scsAxis, doppAxis, chAxis, snrGrid)
ix = find(~isfinite(B), 1, "first");
if isempty(ix)
    error("sixgr:hybrid:CalibrateBLER:StrictMissingPoint", ...
        "Missing truth calibration points.");
end
[iDir, iM, iP, iL, iS, iD, iC, iN] = ind2sub(size(B), ix);
error("sixgr:hybrid:CalibrateBLER:StrictMissingPoint", ...
    "Missing truth calibration point (dir=%s, MCS=%d, PRB=%d, L=%d, SCS=%d, Dopp=%d, Ch=%s, SNR=%g).", ...
    char(dirAxis(iDir)), round(mcsAxis(iM)), round(prbAxis(iP)), round(layerAxis(iL)), ...
    round(scsAxis(iS)), round(doppAxis(iD)), char(chAxis(iC)), double(snrGrid(iN)));
end

function axesCfg = localResolveAxes(cfg, params)
nRB = localEstimateNRB(cfg);
defSCS = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
                 sixgr.util.structGet(cfg, "channel.subcarrierSpacing_kHz", 30)));
defDopp = max(0, double(sixgr.util.structGet(cfg, "channel.dopplerHz", 0)));
defCh = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
defLayersDL = max(1, round(double(sixgr.util.structGet(cfg, "phy.pdsch.numLayers", ...
    sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1)))));
defLayersUL = max(1, round(double(sixgr.util.structGet(cfg, "phy.pusch.numLayers", ...
    sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1)))));
defLayers = unique([1 defLayersDL defLayersUL], "stable");
defMCS = unique([4 10 16], "stable");
if nRB >= 80
    defPRB = unique([20 50 100], "stable");
elseif nRB >= 40
    defPRB = unique([10 25 50], "stable");
else
    defPRB = unique([8 max(10, floor(nRB/2)) nRB], "stable");
end
defPRB = min(max(defPRB, 4), nRB);

axesCfg = struct();
axesCfg.Direction = localStringAxis( ...
    sixgr.util.structGet(params, "CalibDirection", ...
    sixgr.util.structGet(params, "CalibDirections", ...
    sixgr.util.structGet(cfg, "hybrid.calibDirection", ["DL","UL"]))), ["DL","UL"]);
axesCfg.MCS = localNumericAxis( ...
    sixgr.util.structGet(params, "CalibMCS", sixgr.util.structGet(cfg, "hybrid.calibMCS", defMCS)), 0, 27, defMCS);
axesCfg.PRB = localNumericAxis( ...
    sixgr.util.structGet(params, "CalibPRB", sixgr.util.structGet(cfg, "hybrid.calibPRB", defPRB)), 4, nRB, defPRB);
axesCfg.Layers = localNumericAxis( ...
    sixgr.util.structGet(params, "CalibLayers", sixgr.util.structGet(cfg, "hybrid.calibLayers", defLayers)), 1, 8, defLayers);
axesCfg.SCS = localNumericAxis( ...
    sixgr.util.structGet(params, "CalibSCS_kHz", sixgr.util.structGet(cfg, "hybrid.calibSCS_kHz", defSCS)), 15, 240, defSCS);
axesCfg.DopplerHz = localNumericAxis( ...
    sixgr.util.structGet(params, "CalibDopplerHz", sixgr.util.structGet(cfg, "hybrid.calibDopplerHz", [0 defDopp])), 0, 2000, [0 defDopp]);
axesCfg.ChannelModel = localStringAxis( ...
    sixgr.util.structGet(params, "CalibChannelModels", sixgr.util.structGet(cfg, "hybrid.calibChannelModels", defCh)), ...
    [defCh "AWGN" "TDL-C" "CDL-D"]);
end

function cfgOut = localBuildCalibCfg(cfg, direction, mcs, prbCount, layers, scs, dopplerHz, channelModel, logObj)
cfgOut = cfg;
cfgOut.channel.snr_dB = double(sixgr.util.structGet(cfgOut, "channel.snr_dB", 10));
cfgOut.phy.carrier.SubcarrierSpacing = double(scs);
cfgOut.channel.dopplerHz = double(dopplerHz);
cfgOut.channel.doppler_Hz = double(dopplerHz);
if isfield(cfgOut, "channel") && isfield(cfgOut.channel, "fading")
    cfgOut.channel.fading.maxDoppler_Hz = double(dopplerHz);
end

ch = upper(string(channelModel));
if startsWith(ch, "TDL")
    cfgOut.channel.model = "TDL";
    cfgOut.channel.type = "TDL";
    cfgOut.channel.awgnOnly = false;
    cfgOut.channel.tdlProfile = char(ch);
elseif startsWith(ch, "CDL")
    cfgOut.channel.model = "CDL";
    cfgOut.channel.type = "CDL";
    cfgOut.channel.awgnOnly = false;
    cfgOut.channel.cdlProfile = char(ch);
else
    cfgOut.channel.model = "AWGN";
    cfgOut.channel.type = "AWGN";
    cfgOut.channel.awgnOnly = true;
end

[modStr, codeRate] = localMCSProfile(double(mcs));
prbSet = 0:(max(1, round(double(prbCount))) - 1);
if upper(string(direction)) == "UL"
    cfgOut.phy.pusch.modulation = char(modStr);
    cfgOut.phy.pusch.codeRate = double(codeRate);
    cfgOut.phy.pusch.numLayers = max(1, round(double(layers)));
    cfgOut.phy.pusch.nLayers = cfgOut.phy.pusch.numLayers;
    cfgOut.phy.pusch.prbSet = prbSet;
else
    cfgOut.phy.pdsch.modulation = char(modStr);
    cfgOut.phy.pdsch.codeRate = double(codeRate);
    cfgOut.phy.pdsch.numLayers = max(1, round(double(layers)));
    cfgOut.phy.pdsch.nLayers = cfgOut.phy.pdsch.numLayers;
    cfgOut.phy.pdsch.prbSet = prbSet;
end

if ~isempty(logObj)
    try
        logObj.debug("CalibrateBLER: dir=%s mcs=%d prb=%d L=%d scs=%d dop=%d ch=%s", char(direction), ...
            round(mcs), round(prbCount), round(layers), round(scs), round(dopplerHz), char(ch));
    catch
    end
end
end

function [bler, skipped] = localRunSingleSweep(cfg, direction, snrGrid, numFrames, caseLogger)
bler = NaN(size(snrGrid));
skipped = false(size(snrGrid));
dir = upper(string(direction));
for i = 1:numel(snrGrid)
    cCfg = cfg;
    cCfg.channel.snr_dB = snrGrid(i);
    try
        if dir == "UL"
            c = sixgr.link.runULPUSCHThroughput(cCfg, "Logger", caseLogger, ...
                "NumFrames", numFrames, "SNR_dB", snrGrid(i));
        else
            c = sixgr.link.runDLPDSCHThroughput(cCfg, "Logger", caseLogger, ...
                "NumFrames", numFrames, "SNR_dB", snrGrid(i));
        end
        if logical(sixgr.util.structGet(c, "Skipped", false))
            skipped(i) = true;
        else
            bler(i) = double(sixgr.util.structGet(c, "BLER", NaN));
        end
    catch
        % Keep NaN for strict-mode failure or non-strict post fill.
    end
end
end

function [modStr, codeRate] = localMCSProfile(mcs)
mcs = max(0, min(27, round(double(mcs))));
if mcs <= 9
    modStr = "QPSK";
    codeRate = 0.10 + 0.035 * mcs;
elseif mcs <= 16
    modStr = "16QAM";
    codeRate = 0.28 + 0.045 * (mcs - 10);
elseif mcs <= 23
    modStr = "64QAM";
    codeRate = 0.46 + 0.040 * (mcs - 17);
else
    modStr = "256QAM";
    codeRate = 0.62 + 0.035 * (mcs - 24);
end
codeRate = min(max(codeRate, 0.08), 0.92);
end

function v = localNumericAxis(vIn, lo, hi, fallback)
if isempty(vIn)
    v = double(fallback(:).');
else
    v = double(vIn(:).');
end
v = v(isfinite(v));
if isempty(v)
    v = double(fallback(:).');
end
v = unique(round(v), "stable");
v = min(max(v, lo), hi);
v = unique(v, "stable");
end

function s = localStringAxis(sIn, fallback)
if isempty(sIn)
    s = upper(string(fallback(:).'));
else
    s = upper(string(sIn(:).'));
end
s = s(strlength(s) > 0);
if isempty(s)
    s = upper(string(fallback(:).'));
end
s = unique(s, "stable");
end

function nRB = localEstimateNRB(cfg)
bw_Hz = double(sixgr.util.structGet(cfg, "channel.bandwidth_Hz", 20e6));
scs_kHz = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "channel.subcarrierSpacing_kHz", 30)));
scs_Hz = max(1, scs_kHz * 1e3);
nRB = max(4, floor(bw_Hz / (12 * scs_Hz)));
end

function curve = localDirectionAverage(db, direction)
a = db.Axes;
iDir = find(upper(string(a.Direction)) == upper(string(direction)), 1, "first");
if isempty(iDir)
    curve = nan(numel(a.SNR_dB),1);
    return;
end
Bdir = squeeze(db.BLER(iDir,:,:,:,:,:,:,:));
Bflat = reshape(Bdir, [], numel(a.SNR_dB));
curve = mean(Bflat, 1, "omitnan").';
curve = min(max(curve, 1e-4), 0.9999);
end

function [T, C] = localBuildCalibrationTables(db, skipped)
a = db.Axes;
B = db.BLER;
rows = numel(a.Direction) * numel(a.MCS) * numel(a.PRB) * numel(a.Layers) * ...
    numel(a.SCS) * numel(a.DopplerHz) * numel(a.ChannelModel) * numel(a.SNR_dB);

Direction = strings(rows,1);
MCSIndex = zeros(rows,1);
PRB = zeros(rows,1);
Layers = zeros(rows,1);
SCS_kHz = zeros(rows,1);
DopplerHz = zeros(rows,1);
ChannelModel = strings(rows,1);
SNR_dB = zeros(rows,1);
BLER = zeros(rows,1);
SkippedPoint = false(rows,1);

idx = 0;
for iDir = 1:numel(a.Direction)
    for iM = 1:numel(a.MCS)
        for iP = 1:numel(a.PRB)
            for iL = 1:numel(a.Layers)
                for iS = 1:numel(a.SCS)
                    for iD = 1:numel(a.DopplerHz)
                        for iC = 1:numel(a.ChannelModel)
                            for iN = 1:numel(a.SNR_dB)
                                idx = idx + 1;
                                Direction(idx) = string(a.Direction(iDir));
                                MCSIndex(idx) = double(a.MCS(iM));
                                PRB(idx) = double(a.PRB(iP));
                                Layers(idx) = double(a.Layers(iL));
                                SCS_kHz(idx) = double(a.SCS(iS));
                                DopplerHz(idx) = double(a.DopplerHz(iD));
                                ChannelModel(idx) = string(a.ChannelModel(iC));
                                SNR_dB(idx) = double(a.SNR_dB(iN));
                                BLER(idx) = double(B(iDir,iM,iP,iL,iS,iD,iC,iN));
                                SkippedPoint(idx) = logical(skipped(iDir,iM,iP,iL,iS,iD,iC,iN));
                            end
                        end
                    end
                end
            end
        end
    end
end

T = table(Direction, MCSIndex, PRB, Layers, SCS_kHz, DopplerHz, ChannelModel, ...
    SNR_dB, BLER, SkippedPoint);

G = groupsummary(T, {'Direction','MCSIndex','PRB','Layers','SCS_kHz','DopplerHz','ChannelModel'}, ...
    {'mean','max'}, 'BLER');
G.Properties.VariableNames = strrep(G.Properties.VariableNames, "mean_BLER", "BLER_Mean");
G.Properties.VariableNames = strrep(G.Properties.VariableNames, "max_BLER", "BLER_Max");
C = G;
end

