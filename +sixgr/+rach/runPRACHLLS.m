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
    scenarioMatrix = localDefaultScenarioMatrix();
end
baseStruct = localBaseStruct(baseCfg);
outputDir = localResolveOutputDir(baseStruct);

trialRows = cell(0, 1);
roRows = cell(0, 1);
scenarioExports = cell(0, 1);
trialCount = 0;
roCount = 0;
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
                    simOut = localSimulateOccasion(scenarioCfg, occasions(iRO), snrDb, threshold, trialSeed);
                    roCount = roCount + 1;
                    roRows{roCount, 1} = simOut.ROSummary;
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

trialTable = localStructArrayToTable(localCellStructArray(trialRows));
roTable = localStructArrayToTable(localCellStructArray(roRows));
metrics = sixgr.rach.PRACHMetrics(trialTable, roTable, firstResolved, "WriteOutputs", false);

out = struct();
out.Config = localSerializableBase(baseStruct);
out.ScenarioConfigs = localCellStructArray(scenarioExports);
out.TrialTable = trialTable;
out.ROTable = roTable;
out.SummaryBySNR = metrics.SummaryBySNR;
out.SummaryByScenario = metrics.SummaryByScenario;
out.Confusion = metrics.Confusion;
out.TimingErrorSamples = metrics.TimingErrorSamples;
out.FrequencyErrorSamples = metrics.FrequencyErrorSamples;
out.OutputDir = outputDir;

if writeOutputs
    localWriteOutputs(out);
    sixgr.rach.PRACHMetrics(trialTable, roTable, firstResolved, "WriteOutputs", true);
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

function scenarioMatrix = localDefaultScenarioMatrix()
scenarioMatrix = struct( ...
    "ScenarioName", { ...
        "fr1_700mhz_fdd_tdlc_3kmh", ...
        "fr1_2ghz_fdd_cfo_enabled", ...
        "midband_4ghz_tdd_timing_uncertainty", ...
        "7ghz_tdd_high_doppler", ...
        "collision_2ue_per_ro", ...
        "false_alarm_noise_only", ...
        "intercell_interference_optional"}, ...
    "CarrierFrequencyHz", {700e6, 2e9, 4e9, 7e9, 4e9, 700e6, 4e9}, ...
    "DuplexMode", {"FDD","FDD","TDD","TDD","TDD","FDD","TDD"}, ...
    "PRACHSubcarrierSpacing", {1.25, 1.25, 15, 15, 15, 1.25, 15}, ...
    "PRACHConfigurationIndex", {16,16,86,86,86,16,86}, ...
    "PRACHFormat", {"0","0","A1","A1","A1","0","A1"}, ...
    "ChannelModel", {"TDL-C","TDL-C","TDL-C","TDL-C","TDL-C","AWGN","TDL-C"}, ...
    "DelaySpread_ns", {300,300,300,1000,300,30,300}, ...
    "Speed_kmh", {3,3,30,120,30,3,30}, ...
    "EnableFrequencyOffset", {false,true,false,false,false,false,false}, ...
    "EnableFrequencyEstimationMetric", {false,true,false,false,false,false,false}, ...
    "UEFrequencyOffsetHz", {0,450,0,0,0,0,0}, ...
    "EnableTimingUncertainty", {false,false,true,true,false,false,false}, ...
    "TimingUncertaintyMax_us", {0,0,1.5,2.5,0,0,0}, ...
    "NumUEsPerRO", {1,1,1,1,2,0,1}, ...
    "EnableCollisionMode", {false,false,false,false,true,false,false}, ...
    "EnableInterCellInterference", {false,false,false,false,false,false,true}, ...
    "ActivePreamblePattern", {true,true,true,true,true,false,true}, ...
    "NumPRACHOccasions", {4,4,4,4,4,4,4}, ...
    "NumSlots", {80,80,80,80,80,80,80}, ...
    "NumSubframes", {40,40,40,40,40,40,40}, ...
    "NumTrials", {8,8,8,8,8,8,8}, ...
    "SNRSweep_dB", {[-12 -6 0 6 12], [-12 -6 0 6 12], [-12 -6 0 6 12], [-12 -6 0 6 12], [-12 -6 0 6 12], [-12 -6 0 6 12], [-12 -6 0 6 12]}, ...
    "ThresholdSweep", {[0.02 0.05 0.1], [0.02 0.05 0.1], [0.02 0.05 0.1], [0.02 0.05 0.1], [0.02 0.05 0.1], [0.02 0.05 0.1], [0.02 0.05 0.1]} ...
    );
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

refTx = sixgr.rach.generatePRACHWaveform(cfg, "Occasion", occasion, ...
    "PreambleIndex", localReferencePreamble(servingPlan, interfererPlan));
rxWave = complex(zeros(size(refTx.Waveform, 1), cfg.NumRxAntennas));
servingTruth = cell(0, 1);
interfererTruth = cell(0, 1);

for iUE = 1:numel(servingPlan)
    if ~servingPlan(iUE).Active
        continue;
    end
    ueTx = sixgr.rach.generatePRACHWaveform(cfg, "Occasion", occasion, "PreambleIndex", servingPlan(iUE).PreambleIndex);
    servingTruth{end+1, 1} = localApplyChannelAndImpairments(cfg, ueTx, servingPlan(iUE), trialSeed + iUE);
    rxWave = rxWave + servingTruth{end}.RxWaveform;
end

for iUE = 1:numel(interfererPlan)
    if ~interfererPlan(iUE).Active
        continue;
    end
    ueTx = sixgr.rach.generatePRACHWaveform(cfg, "Occasion", occasion, "PreambleIndex", interfererPlan(iUE).PreambleIndex);
    interfererTruth{end+1, 1} = localApplyChannelAndImpairments(cfg, ueTx, interfererPlan(iUE), trialSeed + 100 + iUE);
    rxWave = rxWave + 10^(cfg.InterCellRelativePower_dB / 20) * interfererTruth{end}.RxWaveform;
end

[servingTruth, interfererTruth] = deal(localCellStructArray(servingTruth), localCellStructArray(interfererTruth));
[rxWave, noiseVar] = localAddNoise(rxWave, refTx.Waveform, snrDb, trialSeed + 9000);
tDetect = tic;
det = sixgr.rach.PRACHDetector(rxWave, cfg, "Occasion", occasion, ...
    "DetectionThresholdMode", cfg.DetectionThresholdMode, "DetectionThreshold", threshold, ...
    "EnableFrequencyEstimationMetric", cfg.EnableFrequencyEstimationMetric);
computeLatencyMs = toc(tDetect) * 1e3;
airInterfaceObservationMs = 1e3 * (size(rxWave, 1) / max(double(refTx.SampleRate_Hz), eps));

simOut.ROSummary = localClassifyRO(cfg, det, servingTruth, interfererTruth, occasion, snrDb, threshold, noiseVar, trialSeed, ...
    computeLatencyMs, airInterfaceObservationMs);
simOut.UERows = localExpandUERows(cfg, simOut.ROSummary, servingTruth, occasion, snrDb, threshold);
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
interCfg.PreambleIndex = mod(double(localResolvePreambleSpec(cfg.PreambleIndex, occasionOrdinal, max(1, cfg.NumUEsPerRO), false)) + 7, 64);
plan = localBuildUEPlan(interCfg, occasionOrdinal, true);
end

function plan = localBuildUEPlan(cfg, occasionOrdinal, isInterferer)
numUE = max(1, cfg.NumUEsPerRO);
activePattern = localResolveActivePattern(cfg.ActivePreamblePattern, occasionOrdinal, numUE);
preambleSpec = localResolvePreambleSpec(cfg.PreambleIndex, occasionOrdinal, numUE, cfg.EnableCollisionMode && ~isInterferer);
plan = repmat(struct("UEId",0,"Active",false,"PreambleIndex",0,"TimingOffsetTrue_us",0, ...
    "CFOTrue_Hz",0,"IsInterferer",isInterferer), numUE, 1);
for iUE = 1:numUE
    plan(iUE).UEId = iUE;
    plan(iUE).Active = logical(activePattern(iUE));
    plan(iUE).PreambleIndex = double(preambleSpec(iUE));
    plan(iUE).TimingOffsetTrue_us = localDrawTimingOffsetUs(cfg, plan(iUE).Active);
    plan(iUE).CFOTrue_Hz = localDrawCFO(cfg, plan(iUE).Active);
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
    case {"TDL-A","TDL-C"}
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
    case "CDL-C"
        chan = nrCDLChannel;
        chan.DelayProfile = "CDL-C";
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
    rxWave = localApplyPhaseNoise(rxWave, cfg.PhaseNoiseStdRad, seed + 17);
end
if cfg.EnableFrequencyOffset && abs(plan.CFOTrue_Hz) > 0
    rxWave = localApplyFrequencyOffset(rxWave, plan.CFOTrue_Hz, sampleRateHz);
end

truth = struct();
truth.UEId = plan.UEId;
truth.Active = plan.Active;
truth.PreambleIndex = plan.PreambleIndex;
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
if abs(delaySamples) < 1e-9
    waveOut = waveIn;
    return;
end
n = (0:size(waveIn, 1)-1).';
waveOut = complex(zeros(size(waveIn)));
for iCol = 1:size(waveIn, 2)
    waveOut(:, iCol) = interp1(n, waveIn(:, iCol), n - delaySamples, "linear", 0);
end
end

function waveOut = localApplyFrequencyOffset(waveIn, cfoHz, sampleRateHz)
n = (0:size(waveIn, 1)-1).';
waveOut = waveIn .* exp(1i * 2*pi * double(cfoHz) * n / max(double(sampleRateHz), eps));
end

function waveOut = localApplyPhaseNoise(waveIn, stdRad, seed)
rng(double(seed), "twister");
phaseWalk = cumsum(stdRad * randn(size(waveIn, 1), 1));
waveOut = waveIn .* exp(1i * phaseWalk);
end

function [rxOut, noiseVar] = localAddNoise(rxWave, refWave, snrDb, seed)
rng(double(seed), "twister");
signalPow = mean(abs(rxWave(:)).^2);
if ~(isfinite(signalPow) && signalPow > 0)
    signalPow = max(mean(abs(refWave(:)).^2), 1);
end
noiseVar = signalPow / max(10^(double(snrDb)/10), eps);
noise = sqrt(noiseVar/2) * (randn(size(rxWave)) + 1i * randn(size(rxWave)));
rxOut = rxWave + noise;
end

function roSummary = localClassifyRO(cfg, det, servingTruth, interfererTruth, occasion, snrDb, threshold, noiseVar, trialSeed, computeLatencyMs, airInterfaceObservationMs)
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

wrongPreamble = detected && (~hasServingTx || ~any(servingPreambles == detectedPreamble));
falseAlarm = detected && ~hasServingTx;
missed = ~detected && hasServingTx;
wrongTiming = detected && ~isempty(matchedTruth) && abs(double(timingEst.Error_us)) > double(cfg.TimingTolerance_us);
correct = detected && ~wrongPreamble && ~wrongTiming && ~falseAlarm && hasServingTx;
type1False = detected && ~hasServingTx && ~hasInterfererTx;
type2False = detected && ((~hasServingTx && hasInterfererTx) || (hasServingTx && any(interfererPreambles == detectedPreamble) && ~any(servingPreambles == detectedPreamble)));
mixedFalse = logical(det.MultiCandidateAboveThreshold) && detected;

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
elseif mixedFalse
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

roSummary = struct();
roSummary.scenario_id = string(sixgr.util.structGet(cfg, "ScenarioID", "scenario_1"));
roSummary.trial_id = round(double(trialSeed));
roSummary.ro_id = round(double(occasion.Ordinal));
roSummary.slot_id = round(double(occasion.SlotIndex1));
roSummary.snr_db = double(snrDb);
roSummary.threshold = double(threshold);
roSummary.peak_metric = double(det.PeakMetric);
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
roSummary.CRCPass = double(correct);
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
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_snr.csv"), out.SummaryBySNR);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_scenario.csv"), out.SummaryByScenario);
sixgr.util.csvWriteTable(fullfile(outDir, "confusion_detection_types.csv"), out.Confusion);
sixgr.util.csvWriteTable(fullfile(outDir, "timing_error_samples.csv"), out.TimingErrorSamples);
if ~isempty(out.FrequencyErrorSamples) && any(isfinite(double(out.FrequencyErrorSamples.frequency_error_hz)))
    sixgr.util.csvWriteTable(fullfile(outDir, "optional_frequency_error_samples.csv"), out.FrequencyErrorSamples);
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

function repoRoot = localRepoRoot()
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
