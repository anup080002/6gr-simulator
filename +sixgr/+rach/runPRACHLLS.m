function out = runPRACHLLS(baseCfg, varargin)
%RUNPRACHLLS Execute a waveform-accurate PRACH LLS study.

p = inputParser;
p.FunctionName = "sixgr.rach.runPRACHLLS";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "WriteOutputs", true, @(x) islogical(x) || isnumeric(x));
addParameter(p, "ScenarioMatrix", struct([]), @(x) isstruct(x));
addParameter(p, "Verbose", false, @(x) islogical(x) || isnumeric(x));
parse(p, baseCfg, varargin{:});

writeOutputs = logical(p.Results.WriteOutputs);
verbose = logical(p.Results.Verbose);
scenarioMatrix = p.Results.ScenarioMatrix;
if isempty(scenarioMatrix)
    % A production invocation without a campaign matrix executes exactly
    % the supplied resolved scenario.  Historical multi-scenario research
    % vectors belong to explicit validation/TDoc catalogs and must never
    % become hidden PRACH runtime defaults.
    scenarioName = string(sixgr.util.structGet(baseCfg, "ScenarioName", ...
        sixgr.util.structGet(baseCfg, "scenario.name", "prach_runtime")));
    scenarioMatrix = struct("ScenarioName", char(scenarioName));
end
baseStruct = localBaseStruct(baseCfg);
outputDir = localResolveOutputDir(baseStruct);

trialRows = cell(0, 1);
roRows = cell(0, 1);
corrRows = cell(0, 1);
scenarioExports = cell(0, 1);
trialCount = 0;
roCount = 0;
corrCount = 0;
firstResolved = struct();

for iScenario = 1:numel(scenarioMatrix)
    scenarioCfg = sixgr.rach.PRACHConfig(localMergeStruct(baseStruct, scenarioMatrix(iScenario)), ...
        "OutputDir", outputDir);
    if isempty(fieldnames(firstResolved))
        firstResolved = scenarioCfg;
    end
    scenarioCfg.ScenarioID = localResolveScenarioID(scenarioCfg, iScenario);
    scenarioExports{iScenario, 1} = struct("ScenarioID", scenarioCfg.ScenarioID, "Config", scenarioCfg.ConfigExport);
    occasions = localResolveOccasionList(scenarioCfg);

    for iSNR = 1:numel(scenarioCfg.SNRSweep_dB)
        snrDb = double(scenarioCfg.SNRSweep_dB(iSNR));
        for iThreshold = 1:numel(scenarioCfg.ThresholdSweep)
            threshold = double(scenarioCfg.ThresholdSweep(iThreshold));
            for iTrial = 1:scenarioCfg.NumTrials
                for iRO = 1:numel(occasions)
                    trialSeed = localTrialSeed(scenarioCfg.Seed, iScenario, iSNR, iThreshold, iTrial, iRO);
                    if verbose
                        fprintf("PRACH simulate start: scenario=%s snr=%.3f threshold=%.6g trial=%d ro=%d\n", ...
                            scenarioCfg.ScenarioID, snrDb, threshold, iTrial, iRO);
                    end
                    simOut = localSimulateOccasion(scenarioCfg, occasions(iRO), snrDb, threshold, trialSeed);
                    if verbose
                        fprintf("PRACH simulate complete: scenario=%s trial=%d ro=%d detected=%d\n", ...
                            scenarioCfg.ScenarioID, iTrial, iRO, logical(simOut.ROSummary.detected));
                    end
                    roCount = roCount + 1;
                    roRows{roCount, 1} = simOut.ROSummary;
                    if isfield(simOut, "CorrelationTraceRows") && ~isempty(simOut.CorrelationTraceRows)
                        % Retain one columnar block per executed occasion.
                        % Expanding every lag into a separate cell-held struct
                        % creates excessive metadata copies during concatenation.
                        % The samples, row order, field types and labels are unchanged.
                        corrCount = corrCount + 1;
                        corrRows{corrCount, 1} = localStructArrayToTable(simOut.CorrelationTraceRows);
                    end
                    for iRow = 1:numel(simOut.UERows)
                        trialCount = trialCount + 1;
                        trialRows{trialCount, 1} = simOut.UERows(iRow);
                    end
                end
                if verbose
                    fprintf("PRACH scenario %s trial %d/%d complete.\n", scenarioCfg.ScenarioID, iTrial, scenarioCfg.NumTrials);
                end
            end
        end
    end
end

if verbose
    fprintf("PRACH materialize tables: trialRows=%d roRows=%d\n", trialCount, roCount);
end
trialTable = localStructArrayToTable(localCellStructArray(trialRows));
roTable = localStructArrayToTable(localCellStructArray(roRows));
if isempty(corrRows)
    correlationTraceTable = table();
else
    correlationTraceTable = vertcat(corrRows{:});
end
if verbose
    fprintf("PRACH metrics start: trialRows=%d roRows=%d\n", height(trialTable), height(roTable));
end
metrics = sixgr.rach.PRACHMetrics(trialTable, roTable, firstResolved, "WriteOutputs", false);
if verbose
    fprintf("PRACH zcdpe metrics start\n");
end
zcdpeMetrics = sixgr.rach.ZCDPEMetrics(trialTable, roTable, firstResolved, "WriteOutputs", false);
if verbose
    fprintf("PRACH metrics complete\n");
end

out = struct();
out.Config = localSerializableBase(baseStruct);
out.ScenarioConfigs = localCellStructArray(scenarioExports);
out.TrialTable = trialTable;
out.ROTable = roTable;
out.CorrelationTraceTable = correlationTraceTable;
out.SummaryBySNR = metrics.SummaryBySNR;
out.SummaryByScenario = metrics.SummaryByScenario;
out.Confusion = metrics.Confusion;
out.TimingErrorSamples = metrics.TimingErrorSamples;
out.FrequencyErrorSamples = metrics.FrequencyErrorSamples;
out.ZCDPEMetrics = zcdpeMetrics;
out.OutputDir = outputDir;

if writeOutputs
    localWriteOutputs(out);
    sixgr.rach.PRACHMetrics(trialTable, roTable, firstResolved, "WriteOutputs", true);
    sixgr.rach.ZCDPEMetrics(trialTable, roTable, firstResolved, "WriteOutputs", true);
end
end

function cfg = localBaseStruct(baseCfg)
if isstruct(baseCfg)
    cfg = baseCfg;
elseif isobject(baseCfg)
    cfg = struct(baseCfg);
else
    error("sixgr:rach:runPRACHLLS:BadInput", "Unsupported base PRACH config input.");
end
end

function outDir = localResolveOutputDir(baseStruct)
configured = sixgr.util.structGet(baseStruct, "prach_lls.OutputDir", []);
if isempty(configured)
    configured = sixgr.util.structGet(baseStruct, "OutputDir", []);
end
if isempty(configured)
    timestamp = char(datetime("now", "TimeZone", "local", "Format", "yyyyMMdd_HHmmss"));
    outDir = fullfile(localRepoRoot(), "results", "prach_lls_" + string(timestamp));
else
    outDir = char(string(configured));
end
end

function s = localSerializableBase(baseStruct)
s = baseStruct;
dropFields = intersect(fieldnames(s), {'ToolboxCarrier','ToolboxPRACH','FirstActiveOccasion','ConfigExport'});
if ~isempty(dropFields)
    s = rmfield(s, dropFields);
end
end

function scenarioID = localResolveScenarioID(cfg, idx)
raw = string(sixgr.util.structGet(cfg, "ScenarioName", ""));
if strlength(raw) == 0
    raw = "scenario_" + string(idx);
end
scenarioID = char(regexprep(lower(raw), "[^a-z0-9]+", "_"));
end

function occasions = localResolveOccasionList(cfg)
occasionCells = cell(cfg.NumPRACHOccasions, 1);
for iOcc = 1:cfg.NumPRACHOccasions
    occasionCells{iOcc, 1} = sixgr.rach.mapPRACHToOccasion(cfg, "OccasionIndex", iOcc);
end
if isempty(occasionCells)
    occasions = struct([]);
else
    occasions = vertcat(occasionCells{:});
end
end

function trialSeed = localTrialSeed(baseSeed, iScenario, iSNR, iThreshold, iTrial, iRO)
trialSeed = round(double(baseSeed) + 100000*iScenario + 10000*iSNR + 1000*iThreshold + 100*iTrial + iRO);
end

function simOut = localSimulateOccasion(cfg, occasion, snrDb, threshold, trialSeed)
rng(double(trialSeed), "twister");
servingPlan = localResolveServingPlan(cfg, occasion.Ordinal);
interfererPlan = localResolveInterfererPlan(cfg, occasion.Ordinal);

refTx = localGeneratePRACHLikeWaveform(cfg, occasion, localReferencePreamble(servingPlan, interfererPlan), ...
    localReferenceDPI(cfg, servingPlan, interfererPlan));
rxWave = complex(zeros(size(refTx.Waveform, 1), cfg.NumRxAntennas));
servingTruth = cell(0, 1);
interfererTruth = cell(0, 1);

for iUE = 1:numel(servingPlan)
    if ~servingPlan(iUE).Active
        continue;
    end
    ueTx = localGeneratePRACHLikeWaveform(cfg, occasion, servingPlan(iUE).PreambleIndex, servingPlan(iUE).DPI_d);
    servingTruth{end+1, 1} = localApplyChannelAndImpairments(cfg, ueTx, servingPlan(iUE), trialSeed + iUE);
    rxWave = rxWave + servingTruth{end}.RxWaveform;
end

for iUE = 1:numel(interfererPlan)
    if ~interfererPlan(iUE).Active
        continue;
    end
    ueTx = localGeneratePRACHLikeWaveform(cfg, occasion, interfererPlan(iUE).PreambleIndex, interfererPlan(iUE).DPI_d);
    interfererTruth{end+1, 1} = localApplyChannelAndImpairments(cfg, ueTx, interfererPlan(iUE), trialSeed + 100 + iUE);
    rxWave = rxWave + 10^(cfg.InterCellRelativePower_dB / 20) * interfererTruth{end}.RxWaveform;
end

[servingTruth, interfererTruth] = deal(localCellStructArray(servingTruth), localCellStructArray(interfererTruth));
[rxWave, noiseVar] = localAddNoise(rxWave, refTx.Waveform, snrDb, trialSeed + 9000);
sixgr.config.publishConfigApplicationEvidence("record", ...
    "random_access.detection_threshold", "Random_Access_PRACH", "phy.prach.detectionThreshold", ...
    "sixgr.rach.runPRACHLLS", threshold, ...
    "TrialId", trialSeed, ...
    "Slot", occasion.SlotIndex1, ...
    "RuntimeObjectType", "PRACHDetector", ...
    "RuntimeObjectPath", "cfg.DetectionThreshold", ...
    "ApplicationScope", "prach_lls_trial");
tDetect = tic;
det = localDetectPRACHLike(rxWave, cfg, occasion, ...
    "DetectionThresholdMode", cfg.DetectionThresholdMode, "DetectionThreshold", threshold, ...
    "EnableFrequencyEstimationMetric", cfg.EnableFrequencyEstimationMetric);
noiseOnlyWave = localNoiseOnlyWaveform(size(rxWave), noiseVar, trialSeed + 9100);
noiseDet = localDetectPRACHLike(noiseOnlyWave, cfg, occasion, ...
    "DetectionThresholdMode", cfg.DetectionThresholdMode, "DetectionThreshold", threshold, ...
    "EnableFrequencyEstimationMetric", cfg.EnableFrequencyEstimationMetric);
computeLatencyMs = toc(tDetect) * 1e3;
airInterfaceObservationMs = 1e3 * (size(rxWave, 1) / max(double(refTx.SampleRate_Hz), eps));

simOut.ROSummary = localClassifyRO(cfg, det, noiseDet, servingTruth, interfererTruth, occasion, snrDb, threshold, noiseVar, trialSeed, ...
    computeLatencyMs, airInterfaceObservationMs);
simOut.CorrelationTraceRows = localBuildCorrelationTraceRows(cfg, det, simOut.ROSummary, servingTruth, occasion, snrDb, threshold, noiseVar, trialSeed);
simOut.UERows = localExpandUERows(cfg, simOut.ROSummary, servingTruth, occasion, snrDb, threshold);
end

function tx = localGeneratePRACHLikeWaveform(cfg, occasion, preambleIndex, dpiIndex)
if localZCDPEEnabled(cfg)
    tx = sixgr.rach.generateZCDPEWaveform(cfg, "Occasion", occasion, ...
        "PreambleIndex", preambleIndex, "DPI_d", dpiIndex);
else
    tx = sixgr.rach.generatePRACHWaveform(cfg, "Occasion", occasion, ...
        "PreambleIndex", preambleIndex);
end
end

function det = localDetectPRACHLike(rxWave, cfg, occasion, varargin)
if localZCDPEEnabled(cfg)
    det = sixgr.rach.ZCDPEDetector(rxWave, cfg, "Occasion", occasion, varargin{:});
else
    det = sixgr.rach.PRACHDetector(rxWave, cfg, "Occasion", occasion, varargin{:});
end
end

function preamble = localReferencePreamble(servingPlan, interfererPlan)
if ~isempty(servingPlan) && any([servingPlan.Active])
    preamble = servingPlan(find([servingPlan.Active], 1, "first")).PreambleIndex;
elseif ~isempty(interfererPlan) && any([interfererPlan.Active])
    preamble = interfererPlan(find([interfererPlan.Active], 1, "first")).PreambleIndex;
else
    preamble = 0;
end
end

function dpi = localReferenceDPI(cfg, servingPlan, interfererPlan)
dpi = localFirstDPIFromConfig(cfg);
if ~isempty(servingPlan) && any([servingPlan.Active])
    dpi = servingPlan(find([servingPlan.Active], 1, "first")).DPI_d;
elseif ~isempty(interfererPlan) && any([interfererPlan.Active])
    dpi = interfererPlan(find([interfererPlan.Active], 1, "first")).DPI_d;
end
end

function plan = localResolveServingPlan(cfg, occasionOrdinal)
plan = localBuildUEPlan(cfg, occasionOrdinal, false);
end

function plan = localResolveInterfererPlan(cfg, occasionOrdinal)
if ~cfg.EnableInterCellInterference
    plan = struct([]);
    return;
end
interCfg = cfg;
interCfg.SequenceIndex = mod(cfg.SequenceIndex + 1, 838);
interCfg.PreambleIndex = localResolvePreambleSpec( ...
    cfg.InterfererPreambleIndex,occasionOrdinal,max(1,cfg.NumUEsPerRO),false);
interCfg.ActivePreamblePattern = cfg.InterfererActivePreamblePattern;
plan = localBuildUEPlan(interCfg, occasionOrdinal, true);
end

function plan = localBuildUEPlan(cfg, occasionOrdinal, isInterferer)
numUE = max(1, cfg.NumUEsPerRO);
activePattern = localResolveActivePattern(cfg.ActivePreamblePattern, occasionOrdinal, numUE);
preambleSpec = localResolvePreambleSpec(cfg.PreambleIndex, occasionOrdinal, numUE, cfg.EnableCollisionMode && ~isInterferer);
dpiSpec = localResolveDPISpec(cfg, occasionOrdinal, numUE);
plan = repmat(struct("UEId",0,"Active",false,"PreambleIndex",0,"DPI_d",0,"TimingOffsetTrue_us",0, ...
    "CFOTrue_Hz",0,"IsInterferer",isInterferer), numUE, 1);
for iUE = 1:numUE
    plan(iUE).UEId = iUE;
    plan(iUE).Active = logical(activePattern(iUE));
    plan(iUE).PreambleIndex = double(preambleSpec(iUE));
    plan(iUE).DPI_d = double(dpiSpec(iUE));
    plan(iUE).TimingOffsetTrue_us = localDrawTimingOffsetUs(cfg, plan(iUE).Active);
    plan(iUE).CFOTrue_Hz = localDrawCFO(cfg, plan(iUE).Active);
end
end

function dpiSpec = localResolveDPISpec(cfg, occasionOrdinal, numUE)
if ~localZCDPEEnabled(cfg)
    dpiSpec = zeros(1, numUE);
    return;
end
raw = sixgr.util.structGet(cfg, "ZCDPE.DPI_d", localFirstDPIFromConfig(cfg));
arr = double(raw);
D = double(sixgr.util.structGet(cfg, "ZCDPE.DPI_D", 4));
if isscalar(arr)
    dpiSpec = repmat(mod(round(arr), D), 1, numUE);
elseif isvector(arr) && numel(arr) == numUE
    dpiSpec = mod(round(arr(:).'), D);
elseif ismatrix(arr) && size(arr, 2) >= numUE
    dpiSpec = mod(round(arr(min(size(arr, 1), occasionOrdinal), 1:numUE)), D);
else
    error("sixgr:rach:runPRACHLLS:BadDPISpec", ...
        "ZCDPE.DPI_d must be scalar, length-NumUEs vector, or NumOccasions-by-NumUEs matrix.");
end
end

function activePattern = localResolveActivePattern(patternSpec, occasionOrdinal, numUE)
arr = patternSpec;
if isscalar(arr)
    activePattern = repmat(logical(arr), 1, numUE);
elseif isvector(arr) && numel(arr) == numUE
    activePattern = logical(arr(:).');
elseif isvector(arr)
    activePattern = repmat(logical(arr(min(numel(arr), occasionOrdinal))), 1, numUE);
elseif ismatrix(arr)
    row = min(size(arr, 1), occasionOrdinal);
    activePattern = logical(arr(row, 1:numUE));
else
    activePattern = true(1, numUE);
end
end

function preambleSpec = localResolvePreambleSpec(spec, occasionOrdinal, numUE, collisionMode)
arr = double(spec);
if isscalar(arr)
    if collisionMode
        preambleSpec = repmat(mod(round(arr), 64), 1, numUE);
    else
        preambleSpec = mod(round(arr) + (0:numUE-1), 64);
    end
elseif isvector(arr) && numel(arr) == numUE
    preambleSpec = mod(round(arr(:).'), 64);
elseif ismatrix(arr) && size(arr, 2) >= numUE
    preambleSpec = mod(round(arr(min(size(arr,1), occasionOrdinal), 1:numUE)), 64);
else
    error("sixgr:rach:runPRACHLLS:BadPreambleSpec", ...
        "PreambleIndex must be scalar, length-NumUEs vector, or NumOccasions-by-NumUEs matrix.");
end
end

function timingUs = localDrawTimingOffsetUs(cfg, isActive)
if ~isActive || ~cfg.EnableTimingUncertainty
    timingUs = 0;
else
    lo = double(cfg.TimingUncertaintyMin_us);
    hi = double(localFirstNonEmpty(cfg.TimingUncertaintyMax_us, 1e6 * cfg.CellRadius_m / physconst("LightSpeed")));
    timingUs = lo + (hi - lo) * rand();
end
end

function cfoHz = localDrawCFO(cfg, isActive)
if ~isActive || ~cfg.EnableFrequencyOffset
    cfoHz = 0;
else
    cfoHz = double(cfg.UEFrequencyOffsetHz) - double(cfg.TRPFrequencyOffsetHz);
end
end

function truth = localApplyChannelAndImpairments(cfg, tx, plan, seed)
wave = tx.Waveform;
sampleRateHz = double(tx.SampleRate_Hz);
timingSamples = double(plan.TimingOffsetTrue_us) * 1e-6 * sampleRateHz;
wave = localApplyFractionalDelay(wave, timingSamples);

channelInfo = struct("ChannelFilterDelay", 0);
switch upper(cfg.ChannelModel)
    case "AWGN"
        rxWave = localReplicateToRx(wave, cfg.NumRxAntennas);
    case {"TDL-A","TDL-B","TDL-C","TDL-D","TDL-E"}
        chan = nrTDLChannel;
        chan.DelayProfile = upper(cfg.ChannelModel);
        chan.DelaySpread = double(cfg.DelaySpread_ns) * 1e-9;
        chan.MaximumDopplerShift = localSpeedToDoppler(cfg.Speed_kmh, cfg.CarrierFrequencyHz);
        chan.SampleRate = sampleRateHz;
        chan.NumTransmitAntennas = size(wave, 2);
        chan.NumReceiveAntennas = cfg.NumRxAntennas;
        chan.Seed = double(seed);
        channelInfo = info(chan);
        rxWave = chan(wave);
    case {"CDL-A","CDL-B","CDL-C","CDL-D","CDL-E"}
        chan = nrCDLChannel;
        chan.DelayProfile = upper(cfg.ChannelModel);
        chan.DelaySpread = double(cfg.DelaySpread_ns) * 1e-9;
        chan.MaximumDopplerShift = localSpeedToDoppler(cfg.Speed_kmh, cfg.CarrierFrequencyHz);
        chan.SampleRate = sampleRateHz;
        chan.Seed = double(seed);
        chan.ReceiveAntennaArray.Size = [cfg.NumRxAntennas 1 1 1 1];
        chan.TransmitAntennaArray.Size = [size(wave, 2) 1 1 1 1];
        channelInfo = info(chan);
        rxWave = chan(wave);
    otherwise
        error("sixgr:rach:runPRACHLLS:UnsupportedChannel", ...
            "Unsupported PRACH channel model %s.", cfg.ChannelModel);
end

if cfg.EnablePhaseNoise
    rxWave = localApplyPhaseNoise(rxWave, sampleRateHz, cfg.CarrierFrequencyHz, seed + 17);
end
if cfg.EnableFrequencyOffset && abs(plan.CFOTrue_Hz) > 0
    rxWave = localApplyFrequencyOffset(rxWave, plan.CFOTrue_Hz, sampleRateHz);
end

truth = struct();
truth.UEId = plan.UEId;
truth.Active = plan.Active;
truth.PreambleIndex = plan.PreambleIndex;
truth.DPI_d = double(sixgr.util.structGet(plan, "DPI_d", 0));
truth.RxWaveform = rxWave;
truth.TimingOffsetTrue_us = plan.TimingOffsetTrue_us;
truth.TimingOffsetTrue_samples = timingSamples + double(channelInfo.ChannelFilterDelay);
truth.CFOTrue_Hz = plan.CFOTrue_Hz;
truth.IsInterferer = plan.IsInterferer;
truth.SampleRate_Hz = sampleRateHz;
end

function dopplerHz = localSpeedToDoppler(speedKmh, carrierFrequencyHz)
speedMps = double(speedKmh) / 3.6;
dopplerHz = speedMps * double(carrierFrequencyHz) / physconst("LightSpeed");
end

function waveOut = localReplicateToRx(waveIn, numRxAnt)
waveOut = repmat(mean(waveIn, 2), 1, numRxAnt);
end

function waveOut = localApplyFractionalDelay(waveIn, delaySamples)
delaySamples = double(delaySamples);
if abs(delaySamples) < 1e-9
    waveOut = waveIn;
    return;
end
N = size(waveIn, 1);
pad = max(128, ceil(abs(delaySamples)) + 64);
nfft = 2^nextpow2(N + pad);
bins = (0:nfft-1).';
bins(bins > floor(nfft/2)) = bins(bins > floor(nfft/2)) - nfft;
phaseShift = exp(-1i * 2*pi * delaySamples .* bins ./ nfft);
wavePad = [waveIn; zeros(nfft - N, size(waveIn, 2), "like", waveIn)];
shifted = ifft(fft(wavePad, nfft, 1) .* phaseShift, nfft, 1);
waveOut = shifted(1:N, :);
end

function waveOut = localApplyFrequencyOffset(waveIn, cfoHz, sampleRateHz)
cfoHz = double(cfoHz);
sampleRateHz = max(double(sampleRateHz), eps);
n = (0:size(waveIn, 1)-1).';
phaseRamp = exp(1i * 2*pi * cfoHz * n / sampleRateHz);
waveOut = waveIn .* repmat(phaseRamp, 1, size(waveIn, 2));
end

function waveOut = localApplyPhaseNoise(waveIn, sampleRateHz, carrierFrequencyHz, seed)
cfgPN = struct();
cfgPN.run.seed = double(seed);
cfgPN.phy.fc_Hz = double(carrierFrequencyHz);
cfgPN.rf.phaseNoise.enable = true;
pn = sixgr.rf.PhaseNoiseModel(cfgPN, double(sampleRateHz), double(seed));
waveOut = pn.apply(waveIn, double(sampleRateHz));
end

function [rxOut, noiseVar] = localAddNoise(rxWave, singleUERefWave, snrDb, seed)
rng(double(seed), "twister");
refPow = mean(abs(singleUERefWave(:)).^2);
if ~(isfinite(refPow) && refPow > 0)
    refPow = 1;
    warning("sixgr:rach:runPRACHLLS:ZeroRefPower", ...
        "Single-UE reference waveform has zero/NaN power. Noise variance set to 1.");
end
noiseVar = refPow / max(10^(double(snrDb)/10), eps);
noise = sqrt(noiseVar/2) * (randn(size(rxWave)) + 1i * randn(size(rxWave)));
rxOut = rxWave + noise;
end

function noiseWave = localNoiseOnlyWaveform(waveSize, noiseVar, seed)
rng(double(seed), "twister");
noiseWave = complex(zeros(waveSize));
if isfinite(double(noiseVar)) && double(noiseVar) > 0
    noiseWave = sqrt(double(noiseVar)/2) .* (randn(waveSize) + 1i * randn(waveSize));
end
end

function roSummary = localClassifyRO(cfg, det, noiseDet, servingTruth, interfererTruth, occasion, snrDb, threshold, noiseVar, trialSeed, computeLatencyMs, airInterfaceObservationMs)
servingPreambles = unique(localStructFieldVector(servingTruth, "PreambleIndex"));
interfererPreambles = unique(localStructFieldVector(interfererTruth, "PreambleIndex"));
hasServingTx = ~isempty(servingPreambles);
hasInterfererTx = ~isempty(interfererPreambles);
detectedPreamble = double(sixgr.util.structGet(det, "DetectedPreambleIndex", NaN));
detected = logical(det.Detected);
activeUECount = numel(servingTruth);
collisionFlag = activeUECount > 1;
distinctServingPreambles = numel(servingPreambles);

matchedTruth = struct([]);
for iTruth = 1:numel(servingTruth)
    if detected && servingTruth(iTruth).PreambleIndex == detectedPreamble
        matchedTruth = servingTruth(iTruth);
        break;
    end
end
if isempty(matchedTruth) && ~isempty(servingTruth)
    matchedTruth = servingTruth(1);
end

timingEst = sixgr.rach.estimateTimingOffset(det.TimingOffsetSamples, sixgr.util.structGet(cfg, "SampleRate_Hz", NaN), NaN);
timingTrueUs = NaN;
timingTrueSamples = NaN;
if ~isempty(matchedTruth)
    timingTrueUs = matchedTruth.TimingOffsetTrue_us;
    timingTrueSamples = matchedTruth.TimingOffsetTrue_samples;
    timingEst = sixgr.rach.estimateTimingOffset(det.TimingOffsetSamples, matchedTruth.SampleRate_Hz, matchedTruth.TimingOffsetTrue_samples);
end

wrongPreamble = detected && hasServingTx && ~any(servingPreambles == detectedPreamble);
falseAlarm = detected && ~hasServingTx;
missed = ~detected && hasServingTx;
numAbove = sum(double(det.CorrelationPeaks) >= double(det.Threshold));
mixedFalse = detected && hasServingTx && (numAbove > 1);
timingTolUs = double(cfg.TimingTolerance_us);
wrongTiming = false;
if detected && ~isempty(matchedTruth) && isfinite(timingTolUs) && ...
        isfield(timingEst, "TruthAvailable") && logical(timingEst.TruthAvailable)
    wrongTiming = abs(double(timingEst.Error_us)) > timingTolUs;
end
correct = detected && hasServingTx && ~wrongPreamble && ~wrongTiming;
type1False = detected && ~hasServingTx && ~hasInterfererTx;
type2False = detected && ~hasServingTx && hasInterfererTx;

if falseAlarm
    if type1False
        detectionType = "type1_false_detection";
    elseif type2False
        detectionType = "type2_false_detection";
    else
        detectionType = "false_alarm";
    end
elseif missed
    detectionType = "no_detection";
elseif wrongPreamble
    detectionType = "wrong_preamble";
elseif wrongTiming
    detectionType = "wrong_timing";
elseif mixedFalse && ~correct
    detectionType = "mixed_detection";
else
    detectionType = "correct_detection";
end

cfoTrue = NaN;
cfoEst = NaN;
if ~isempty(matchedTruth)
    cfoTrue = matchedTruth.CFOTrue_Hz;
end
if logical(sixgr.util.structGet(det.FrequencyEstimate, "Valid", false))
    cfoEst = double(det.FrequencyEstimate.EstimateHz);
end
zcdpe = sixgr.util.structGet(det, "ZCDPE", struct());
zcdpeEnabled = localZCDPEEnabled(cfg);
dpiTrue = NaN;
if ~isempty(matchedTruth) && isfield(matchedTruth, "DPI_d")
    dpiTrue = double(matchedTruth.DPI_d);
end
dpiDetected = double(sixgr.util.structGet(zcdpe, "DPI_Detected", NaN));
dpiCorrect = zcdpeEnabled && isfinite(dpiTrue) && isfinite(dpiDetected) && (round(dpiTrue) == round(dpiDetected));
dopplerEst = double(sixgr.util.structGet(zcdpe, "DopplerEstimate_Hz", NaN));

roSummary = struct();
roSummary.scenario_id = string(sixgr.util.structGet(cfg, "ScenarioID", "scenario_1"));
roSummary.configured_ue_frequency_offset_hz = double(cfg.UEFrequencyOffsetHz);
roSummary.configured_trp_frequency_offset_hz = double(cfg.TRPFrequencyOffsetHz);
roSummary.inter_cell_relative_power_db = double(cfg.InterCellRelativePower_dB);
roSummary.interferer_preamble_index = double(localFirstNonEmpty( ...
    cfg.InterfererPreambleIndex,NaN));
roSummary.trial_id = round(double(trialSeed));
roSummary.ro_id = round(double(occasion.Ordinal));
roSummary.slot_id = round(double(occasion.SlotIndex1));
roSummary.snr_db = double(snrDb);
roSummary.threshold = double(threshold);
roSummary.peak_metric = double(det.PeakMetric);
roSummary.correlation_peak = double(det.PeakMetric);
roSummary.noise_only_peak_metric = double(sixgr.util.structGet(noiseDet, "PeakMetric", NaN));
roSummary.noise_only_detected = logical(sixgr.util.structGet(noiseDet, "Detected", false));
roSummary.noise_only_detected_flag = double(roSummary.noise_only_detected);
roSummary.detector_noise_floor = double(noiseVar);
roSummary.preamble_index_from_peak = double(sixgr.util.structGet(det, "PreambleIndexFromPeak", NaN));
roSummary.detected = logical(detected);
roSummary.detected_flag = double(detected);
roSummary.detected_preamble_index = detectedPreamble;
roSummary.correct_detection = logical(correct);
roSummary.correct_detection_flag = double(correct);
roSummary.wrong_preamble = logical(wrongPreamble);
roSummary.wrong_preamble_flag = double(wrongPreamble);
roSummary.false_alarm = logical(falseAlarm);
roSummary.false_alarm_flag = double(falseAlarm);
roSummary.missed_detection = logical(missed);
roSummary.missed_detection_flag = double(missed);
roSummary.type1_false_detection = logical(type1False);
roSummary.type1_false_detection_flag = double(type1False);
roSummary.type2_false_detection = logical(type2False);
roSummary.type2_false_detection_flag = double(type2False);
roSummary.mixed_false_detection = logical(mixedFalse);
roSummary.mixed_false_detection_flag = double(mixedFalse);
roSummary.detection_type = string(detectionType);
roSummary.multi_candidate_detection = logical(det.MultiCandidateAboveThreshold);
roSummary.timing_offset_true_us = double(timingTrueUs);
roSummary.timing_offset_est_us = double(timingEst.Offset_us);
roSummary.timing_error_us = double(timingEst.Error_us);
roSummary.timing_error_sq_us2 = double(timingEst.Error_us).^2;
roSummary.cfo_true_hz = double(cfoTrue);
roSummary.cfo_est_hz = double(cfoEst);
roSummary.frequency_error_hz = double(cfoEst - cfoTrue);
roSummary.frequency_error_abs_hz = abs(double(cfoEst - cfoTrue));
roSummary.zcdpe_enabled = logical(zcdpeEnabled);
roSummary.prach_design = string(localPRACHDesign(cfg));
roSummary.dpi_D = double(sixgr.util.structGet(cfg, "ZCDPE.DPI_D", NaN));
roSummary.dpi_d_true = double(dpiTrue);
roSummary.dpi_d_detected = double(dpiDetected);
roSummary.dpi_correct = logical(dpiCorrect);
roSummary.dpi_correct_flag = double(dpiCorrect);
roSummary.dpi_confusion_score = double(sixgr.util.structGet(zcdpe, "DPI_ConfusionScore", NaN));
roSummary.doppler_est_hz = double(dopplerEst);
roSummary.doppler_error_hz = double(dopplerEst - cfoTrue);
roSummary.is_backward_compat = logical(sixgr.util.structGet(cfg, "ZCDPE.IsBackwardCompat", false));
roSummary.is_orthogonal_config = logical(sixgr.util.structGet(cfg, "ZCDPE.IsOrthogonal", false));
roSummary.pool_gain_factor = double(sixgr.util.structGet(cfg, "ZCDPE.PoolGainFactor", NaN));
roSummary.channel_model = string(cfg.ChannelModel);
roSummary.delay_spread_ns = double(cfg.DelaySpread_ns);
roSummary.speed_kmh = double(cfg.Speed_kmh);
roSummary.noise_variance = double(noiseVar);
roSummary.threshold_mode = string(cfg.DetectionThresholdMode);
roSummary.seed = round(double(trialSeed));
roSummary.ComputeLatency_ms = double(computeLatencyMs);
roSummary.ProcedureDelay_ms = NaN;
roSummary.AirInterfaceObservation_ms = double(airInterfaceObservationMs);
roSummary.AcquisitionTime_ms = double(airInterfaceObservationMs);
roSummary.TrueTimingOffset_samples = double(timingTrueSamples);
roSummary.EstimatedTimingOffset_samples = double(det.TimingOffsetSamples);
roSummary.TimingError_samples = double(roSummary.EstimatedTimingOffset_samples - roSummary.TrueTimingOffset_samples);
roSummary.ActiveUECount = round(double(activeUECount));
roSummary.CollisionFlag = double(collisionFlag);
roSummary.DistinctTransmittedPreambleCount = round(double(distinctServingPreambles));
% TS 38.211 6.3.3 preamble detection is not a CRC-protected TB decode.
roSummary.CRCApplicable = false;
roSummary.CRCPass = NaN;
roSummary.DetectionSuccess = logical(correct);
roSummary.FalseAlarmFlag = double(falseAlarm);
roSummary.Status = string(localOutcomeStatus(correct));
roSummary.Notes = string(detectionType);
end

function status = localOutcomeStatus(correctDetection)
if logical(correctDetection)
    status = "PASS";
else
    status = "FAIL";
end
end

function ueRows = localExpandUERows(cfg, roSummary, servingTruth, occasion, snrDb, threshold)
if isempty(servingTruth)
    ueRows = struct( ...
        "seed", roSummary.seed, "snr_db", double(snrDb), "scenario_id", string(roSummary.scenario_id), ...
        "ro_id", round(double(occasion.Ordinal)), "slot_id", round(double(occasion.SlotIndex1)), "ue_id", 0, ...
        "preamble_tx_present", false, "transmitted_preamble_index", NaN, ...
        "detected_preamble_index", double(roSummary.detected_preamble_index), "detected", logical(roSummary.detected), ...
        "correct_detection", false, "wrong_preamble", logical(roSummary.wrong_preamble), "false_alarm", logical(roSummary.false_alarm), ...
        "missed_detection", false, "timing_offset_true_us", NaN, "timing_offset_est_us", double(roSummary.timing_offset_est_us), ...
        "timing_error_us", NaN, "cfo_true_hz", NaN, "cfo_est_hz", double(roSummary.cfo_est_hz), ...
        "zcdpe_enabled", logical(roSummary.zcdpe_enabled), "prach_design", string(roSummary.prach_design), ...
        "dpi_d_true", NaN, "dpi_d_detected", double(roSummary.dpi_d_detected), ...
        "dpi_correct", false, "dpi_confusion_score", double(roSummary.dpi_confusion_score), ...
        "doppler_est_hz", double(roSummary.doppler_est_hz), "doppler_error_hz", NaN, ...
        "is_backward_compat", logical(roSummary.is_backward_compat), ...
        "dpi_D", double(roSummary.dpi_D), "is_orthogonal_config", logical(roSummary.is_orthogonal_config), ...
        "pool_gain_factor", double(roSummary.pool_gain_factor), ...
        "channel_model", string(cfg.ChannelModel), "delay_spread_ns", double(cfg.DelaySpread_ns), ...
        "speed_kmh", double(cfg.Speed_kmh), "threshold", double(threshold), "peak_metric", double(roSummary.peak_metric));
    return;
end

ueRows = repmat(struct( ...
    "seed", roSummary.seed, "snr_db", double(snrDb), "scenario_id", string(roSummary.scenario_id), ...
    "ro_id", round(double(occasion.Ordinal)), "slot_id", round(double(occasion.SlotIndex1)), "ue_id", 0, ...
    "preamble_tx_present", true, "transmitted_preamble_index", NaN, ...
    "detected_preamble_index", double(roSummary.detected_preamble_index), "detected", logical(roSummary.detected), ...
    "correct_detection", false, "wrong_preamble", false, "false_alarm", false, ...
    "missed_detection", false, "timing_offset_true_us", NaN, "timing_offset_est_us", double(roSummary.timing_offset_est_us), ...
    "timing_error_us", NaN, "cfo_true_hz", NaN, "cfo_est_hz", double(roSummary.cfo_est_hz), ...
    "zcdpe_enabled", logical(roSummary.zcdpe_enabled), "prach_design", string(roSummary.prach_design), ...
    "dpi_d_true", NaN, "dpi_d_detected", double(roSummary.dpi_d_detected), ...
    "dpi_correct", false, "dpi_confusion_score", double(roSummary.dpi_confusion_score), ...
    "doppler_est_hz", double(roSummary.doppler_est_hz), "doppler_error_hz", NaN, ...
    "is_backward_compat", logical(roSummary.is_backward_compat), ...
    "dpi_D", double(roSummary.dpi_D), "is_orthogonal_config", logical(roSummary.is_orthogonal_config), ...
    "pool_gain_factor", double(roSummary.pool_gain_factor), ...
    "channel_model", string(cfg.ChannelModel), "delay_spread_ns", double(cfg.DelaySpread_ns), ...
    "speed_kmh", double(cfg.Speed_kmh), "threshold", double(threshold), "peak_metric", double(roSummary.peak_metric)), numel(servingTruth), 1);

for iUE = 1:numel(servingTruth)
    ueRows(iUE).ue_id = servingTruth(iUE).UEId;
    ueRows(iUE).transmitted_preamble_index = servingTruth(iUE).PreambleIndex;
    ueRows(iUE).correct_detection = logical(roSummary.detected && roSummary.detected_preamble_index == servingTruth(iUE).PreambleIndex && abs(roSummary.timing_error_us) <= cfg.TimingTolerance_us);
    ueRows(iUE).wrong_preamble = logical(roSummary.detected && roSummary.detected_preamble_index ~= servingTruth(iUE).PreambleIndex && ~roSummary.false_alarm);
    ueRows(iUE).false_alarm = logical(roSummary.false_alarm);
    ueRows(iUE).missed_detection = logical(~roSummary.detected || (roSummary.detected && roSummary.detected_preamble_index ~= servingTruth(iUE).PreambleIndex));
    ueRows(iUE).timing_offset_true_us = double(servingTruth(iUE).TimingOffsetTrue_us);
    ueRows(iUE).timing_error_us = double(roSummary.timing_offset_est_us) - double(servingTruth(iUE).TimingOffsetTrue_us);
    ueRows(iUE).cfo_true_hz = double(servingTruth(iUE).CFOTrue_Hz);
    ueRows(iUE).dpi_d_true = double(servingTruth(iUE).DPI_d);
    ueRows(iUE).dpi_correct = logical(roSummary.zcdpe_enabled && isfinite(roSummary.dpi_d_detected) && ...
        round(double(roSummary.dpi_d_detected)) == round(double(servingTruth(iUE).DPI_d)));
    ueRows(iUE).doppler_error_hz = double(roSummary.doppler_est_hz) - double(servingTruth(iUE).CFOTrue_Hz);
end
end

function rows = localBuildCorrelationTraceRows(cfg, det, roSummary, servingTruth, ~, snrDb, threshold, ~, trialSeed)
trace = sixgr.util.structGet(det, "CorrelationTrace", struct());
lags = double(sixgr.util.structGet(trace, "LagSamples", zeros(0, 1)));
corrAbs = double(sixgr.util.structGet(trace, "CorrelationAbs", zeros(0, 1)));
lags = lags(:);
corrAbs = corrAbs(:);
n = min(numel(lags), numel(corrAbs));
if n == 0
    rows = struct([]);
    return;
end
lags = lags(1:n);
corrAbs = corrAbs(1:n);
validSamples = isfinite(lags) & isfinite(corrAbs);
lags = lags(validSamples);
corrAbs = corrAbs(validSamples);
n = numel(lags);
if n == 0
    rows = struct([]);
    return;
end
sampleRateHz = localCorrelationTraceSampleRate(cfg, servingTruth);
lagUs = lags ./ max(sampleRateHz, eps) .* 1e6;
cfoHz = double(localFirstFinite([roSummary.cfo_true_hz; roSummary.cfo_est_hz]));
if ~isfinite(cfoHz)
    cfoHz = 0;
end
preambleIndex = double(sixgr.util.structGet(trace, "PreambleIndex", ...
    sixgr.util.structGet(det, "PreambleIndexFromPeak", NaN)));
noiseFloor = double(sixgr.util.structGet(trace, "NoiseFloor", NaN));
peakLagSamples = double(sixgr.util.structGet(trace, "PeakLagSamples", sixgr.util.structGet(det, "TimingOffsetSamples", NaN)));
truthStatus = string(sixgr.util.structGet(trace, "TraceStatus", "real_lls_evidence"));
if strlength(truthStatus) == 0
    truthStatus = "real_lls_evidence";
end
rows = repmat(struct( ...
    "trial_id", round(double(trialSeed)), ...
    "preamble_index", double(preambleIndex), ...
    "root_sequence_index", double(cfg.SequenceIndex), ...
    "restricted_set_type", string(cfg.RestrictedSet), ...
    "n_cs", double(sixgr.util.structGet(cfg, "ZCZNCS", NaN)), ...
    "zero_correlation_zone_config", double(cfg.ZeroCorrelationZone), ...
    "lag_samples", NaN, ...
    "lag_us", NaN, ...
    "correlation_abs", NaN, ...
    "threshold", double(sixgr.util.structGet(trace, "Threshold", NaN)), ...
    "decision_threshold", double(det.Threshold), ...
    "threshold_source", string(sixgr.util.structGet(trace, "ThresholdSource", "not_available")), ...
    "noise_floor", double(noiseFloor), ...
    "peak_lag_samples", double(peakLagSamples), ...
    "timing_advance_samples", double(roSummary.EstimatedTimingOffset_samples), ...
    "detection_result", string(roSummary.detection_type), ...
    "false_alarm", logical(roSummary.false_alarm), ...
    "missed_detection", logical(roSummary.missed_detection), ...
    "snr_db", double(snrDb), ...
    "cfo_hz", double(cfoHz), ...
    "seed", round(double(trialSeed)), ...
    "truth_status", truthStatus), n, 1);
for i = 1:n
    rows(i).lag_samples = double(lags(i));
    rows(i).lag_us = double(lagUs(i));
    rows(i).correlation_abs = double(corrAbs(i));
end
end

function sampleRateHz = localCorrelationTraceSampleRate(cfg, servingTruth)
sampleRateHz = double(sixgr.util.structGet(cfg, "SampleRate_Hz", NaN));
if ~(isfinite(sampleRateHz) && sampleRateHz > 0) && ~isempty(servingTruth)
    sampleRateHz = double(sixgr.util.structGet(servingTruth(1), "SampleRate_Hz", NaN));
end
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    sampleRateHz = 30.72e6;
end
end

function T = localStructArrayToTable(rows)
if isempty(rows)
    T = table();
else
    T = struct2table(rows, "AsArray", true);
end
end

function rows = localCellStructArray(rowCells)
if isempty(rowCells)
    rows = struct([]);
else
    rows = vertcat(rowCells{:});
end
end

function values = localStructFieldVector(rows, fieldName)
if isempty(rows)
    values = [];
else
    values = [rows.(fieldName)];
end
end

function localWriteOutputs(out)
outDir = out.OutputDir;
sixgr.util.ensureDir(fullfile(outDir, "stub.txt"));
localWriteJSON(fullfile(outDir, "scenario_config.json"), struct("base_config", out.Config, "scenario_configs", {out.ScenarioConfigs}));
sixgr.util.csvWriteTable(fullfile(outDir, "trial_level_results.csv"), out.TrialTable);
if isfield(out, "CorrelationTraceTable") && istable(out.CorrelationTraceTable) && ~isempty(out.CorrelationTraceTable)
    sixgr.util.csvWriteTable(fullfile(outDir, "prach_correlation_trace.csv"), out.CorrelationTraceTable);
    sixgr.util.csvWriteTable(fullfile(outDir, "prach_correlation_traces.csv"), out.CorrelationTraceTable);
end
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_snr.csv"), out.SummaryBySNR);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_scenario.csv"), out.SummaryByScenario);
sixgr.util.csvWriteTable(fullfile(outDir, "confusion_detection_types.csv"), out.Confusion);
sixgr.util.csvWriteTable(fullfile(outDir, "timing_error_samples.csv"), out.TimingErrorSamples);
if ~isempty(out.FrequencyErrorSamples) && any(isfinite(double(out.FrequencyErrorSamples.frequency_error_hz)))
    sixgr.util.csvWriteTable(fullfile(outDir, "optional_frequency_error_samples.csv"), out.FrequencyErrorSamples);
end
if isfield(out, "ZCDPEMetrics") && isstruct(out.ZCDPEMetrics)
    z = out.ZCDPEMetrics;
    if isfield(z, "DPIConfusionMatrix") && istable(z.DPIConfusionMatrix)
        sixgr.util.csvWriteTable(fullfile(outDir, "dpi_confusion_matrix.csv"), z.DPIConfusionMatrix);
    end
    if isfield(z, "DPIErrorBySnr") && istable(z.DPIErrorBySnr)
        sixgr.util.csvWriteTable(fullfile(outDir, "dpi_error_probability_by_snr.csv"), z.DPIErrorBySnr);
    end
    if isfield(z, "DopplerRMSEBySnr") && istable(z.DopplerRMSEBySnr)
        sixgr.util.csvWriteTable(fullfile(outDir, "doppler_rmse_by_snr.csv"), z.DopplerRMSEBySnr);
    end
    if isfield(z, "PoolAnalysis") && istable(z.PoolAnalysis)
        sixgr.util.csvWriteTable(fullfile(outDir, "pool_analysis.csv"), z.PoolAnalysis);
    end
end
end

function localWriteJSON(filePath, s)
fid = fopen(filePath, "w");
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s", jsonencode(s));
end

function merged = localMergeStruct(baseStruct, overrideStruct)
merged = baseStruct;
fields = fieldnames(overrideStruct);
for iField = 1:numel(fields)
    name = fields{iField};
    value = overrideStruct.(name);
    if isstruct(value) && isfield(merged, name) && isstruct(merged.(name))
        merged.(name) = localMergeStruct(merged.(name), value);
    else
        merged.(name) = value;
    end
end
end

function value = localFirstNonEmpty(varargin)
value = [];
for iArg = 1:nargin
    candidate = varargin{iArg};
    if isempty(candidate)
        continue;
    end
    value = candidate;
    return;
end
end

function value = localFirstFinite(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = values(1);
end
end

function tf = localZCDPEEnabled(cfg)
tf = logical(sixgr.util.structGet(cfg, "ZCDPEEnabled", ...
    sixgr.util.structGet(cfg, "ZCDPE.Enable", false)));
end

function dpi = localFirstDPIFromConfig(cfg)
dpi = sixgr.util.structGet(cfg, "ZCDPE.DPI_d", 0);
dpi = double(dpi(:));
dpi = dpi(isfinite(dpi));
if isempty(dpi)
    dpi = 0;
else
    dpi = dpi(1);
end
end

function design = localPRACHDesign(cfg)
if localZCDPEEnabled(cfg)
    design = "zcdpe";
else
    design = "nr_baseline";
end
end

function repoRoot = localRepoRoot()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
