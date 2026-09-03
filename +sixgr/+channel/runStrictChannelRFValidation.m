function result = runStrictChannelRFValidation(cfg, varargin)
%RUNSTRICTCHANNELRFVALIDATION Strict configured-vs-applied Channel/RF evidence.

p = inputParser;
p.addParameter("RunFolder", "");
p.addParameter("RunId", "channel_rf_strict_unit");
p.addParameter("ScenarioName", "lls_channel_rf_strict_mini_anchor");
p.addParameter("ExecutionID", "");
p.addParameter("ScenarioConfigHash", "");
p.addParameter("RuntimeTrials", struct(), @(x) isstruct(x) && isscalar(x));
p.addParameter("WriteArtifacts", true, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
runId = string(p.Results.RunId);
scenarioName = string(p.Results.ScenarioName);
cfg = sixgr.util.structSet(cfg, "channel_rf.runId", char(runId));
cfg = sixgr.util.structSet(cfg, "scenario.id", char(scenarioName));

[sampleRateHz, carrierMeta] = localResolveSampleRate(cfg);
cfg = sixgr.util.structSet(cfg, "channel_rf.sampleRateHz", sampleRateHz);
cfg = localEnsureRFConfig(cfg);
verdict = sixgr.channel.validateChannelRFConfigStrict(cfg);
toolbox = localToolboxCapabilities();
geometry = sixgr.channel.buildScenarioGeometry(cfg);

rng(double(sixgr.util.structGet(cfg, "run.seed", 240620)), "twister");
base = localQPSKWaveform(2048, 1, 11);
configuredTxAnt = max(1, round(double(sixgr.util.structGet(cfg, ...
    "scenario.bs.nTxAnt", sixgr.util.structGet(cfg, ...
    "channel.nTxAnt", 1)))));
baseMimo = localQPSKWaveform(2048, configuredTxAnt, 17);

configRow = localConfigRow(cfg, runId, scenarioName, sampleRateHz, carrierMeta, verdict);
[largeScaleT, largeScaleWave] = localLargeScaleEvidence(cfg, runId, scenarioName, geometry, base);
[channelT, channelSnapshotsT, channelPathGainsT] = localChannelRealizationEvidence(cfg, runId, scenarioName, sampleRateHz, base, baseMimo);
[interferenceT, interferenceWave] = localInterferenceEvidence(cfg, runId, scenarioName, geometry, base);
[thermalNoiseT, noiseWave] = localThermalNoiseEvidence(cfg, runId, scenarioName, sampleRateHz, base);
rfOut = sixgr.rf.applyRFImpairmentChain(base, cfg, "SampleRateHz", sampleRateHz, ...
    "RunId", runId, "Direction", "downlink", "MeasurementPoint", "rx_input", ...
    "StrictMutationRequired", false);
rfConfigured = any(logical(rfOut.StageTrace.Enabled));
rfT = struct2table(rfOut.Row);
rfT.RFConfigured = repmat(rfConfigured, height(rfT), 1);
configuredAppliedT = localConfiguredVsAppliedTable( ...
    cfg, channelT, largeScaleT, interferenceT, rfT);
negativeT = localNegativeTrials(configuredAppliedT, runId);
oracleT = localOracleGuard(runId);
downstreamT = localDownstreamReferences(runId, scenarioName, ...
    channelT, rfT, p.Results.RuntimeTrials);
evmT = localEVMTable(runId, rfT);

strictOk = logical(verdict.Ok) && localAllPositiveOk(configuredAppliedT) && ...
    localAllNegativeOk(negativeT) && all(~logical(oracleT.Violation)) && ...
    height(downstreamT) > 0 && all(logical(downstreamT.ReferenceValid));

failureReason = "";
if ~strictOk
    failures = strings(0, 1);
    if ~verdict.Ok
        failures(end+1, 1) = "config:" + string(verdict.StrictUnsupportedReason);
    end
    badPositive = configuredAppliedT(~logical(configuredAppliedT.StrictOk) & logical(configuredAppliedT.ExpectedOk), :);
    if height(badPositive) > 0
        failures(end+1, 1) = "positive_cases_failed:" + strjoin(string(badPositive.TrialId), "|");
    end
    badNegative = negativeT(~logical(negativeT.NegativeExpectedOk), :);
    if height(badNegative) > 0
        failures(end+1, 1) = "negative_cases_failed:" + strjoin(string(badNegative.NegativeTrialType), "|");
    end
    if any(logical(oracleT.Violation))
        failures(end+1, 1) = "oracle_guard_violation";
    end
    failureReason = strjoin(failures, ";");
end

result = struct();
result.Ok = strictOk;
result.StrictOk = strictOk;
result.FailureReason = failureReason;
result.ConfigValidation = verdict;
result.ToolboxCapabilities = toolbox;
result.ConfigStrict = configRow;
result.Geometry = geometry;
result.LargeScaleParameters = largeScaleT;
result.ChannelRealizations = channelT;
result.ChannelSnapshots = channelSnapshotsT;
result.ChannelPathGains = channelPathGainsT;
result.InterferenceTopology = interferenceT;
result.ThermalNoise = thermalNoiseT;
result.RFImpairmentChain = rfT;
result.EVMMeasurements = evmT;
result.ConfiguredVsApplied = configuredAppliedT;
result.NegativeTrials = negativeT;
result.OracleGuard = oracleT;
result.DownstreamReferences = downstreamT;
result.SampleEvidence = struct( ...
    "LargeScaleWaveformHash", sixgr.channel.hashChannelRFConfig(localWaveformPayload(largeScaleWave)), ...
    "InterferenceWaveformHash", sixgr.channel.hashChannelRFConfig(localWaveformPayload(interferenceWave)), ...
    "NoiseWaveformHash", sixgr.channel.hashChannelRFConfig(localWaveformPayload(noiseWave)), ...
    "RFImpairedWaveformHash", sixgr.channel.hashChannelRFConfig(localWaveformPayload(rfOut.Waveform)));
if strlength(strtrim(string(p.Results.ExecutionID))) > 0
    identity = struct("RunID", runId, ...
        "ExecutionID", string(p.Results.ExecutionID), ...
        "ScenarioID", scenarioName, ...
        "ConfigHash", string(p.Results.ScenarioConfigHash));
    result = sixgr.channel.buildInPathChannelRFResult( ...
        cfg, result, p.Results.RuntimeTrials, identity);
else
    % A direct component invocation is a real executed anchor, but it is
    % not same-scenario in-path evidence.  Bind its identity explicitly so
    % downstream gates never need to infer or fabricate provenance.
    anchorHash = lower(string(configRow.ConfigHash));
    anchorIdentity = struct( ...
        "ExecutionID", "component_anchor:" + runId, ...
        "ScenarioID", scenarioName, ...
        "ConfigHash", anchorHash);
    result = localBindComponentAnchorIdentity(result, anchorIdentity);
end

if logical(p.Results.WriteArtifacts)
    result.Artifacts = sixgr.channel.exportStrictChannelRFArtifacts(result, char(string(p.Results.RunFolder)));
else
    result.Artifacts = struct();
end
end

function cfg = localEnsureRFConfig(cfg)
% YAML normalization is the only authority.  This validator must never
% enable an impairment, pathloss, shadowing or O2I stage on its own.
end

function result = localBindComponentAnchorIdentity(result, identity)
tableFields = [ ...
    "ConfigStrict", "LargeScaleParameters", "ChannelRealizations", ...
    "ChannelSnapshots", "ChannelPathGains", "InterferenceTopology", ...
    "ThermalNoise", "RFImpairmentChain", "EVMMeasurements", ...
    "ConfiguredVsApplied", "NegativeTrials", "OracleGuard", ...
    "DownstreamReferences"];
for fieldName = tableFields
    key = char(fieldName);
    if ~isfield(result, key) || ~istable(result.(key))
        continue;
    end
    T = result.(key);
    T.ExecutionID = repmat(string(identity.ExecutionID), height(T), 1);
    T.ScenarioID = repmat(string(identity.ScenarioID), height(T), 1);
    T.ScenarioConfigHash = repmat(lower(string(identity.ConfigHash)), height(T), 1);
    T.EvidenceScope = repmat("component_anchor", height(T), 1);
    T.SameScenarioInPathEligible = false(height(T), 1);
    result.(key) = T;
end
end

function [fs, meta] = localResolveSampleRate(cfg)
meta = struct();
meta.Source = "derived_from_nrCarrierConfig";
try
    carrier = nrCarrierConfig;
    carrier.NSizeGrid = max(1, round(double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 24))));
    carrier.SubcarrierSpacing = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", 30));
    info = nrOFDMInfo(carrier);
    fs = double(info.SampleRate);
    meta.NSizeGrid = carrier.NSizeGrid;
    meta.SubcarrierSpacingKHz = carrier.SubcarrierSpacing;
catch
    nrb = max(1, round(double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 24))));
    scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", 30));
    fs = max(1, nrb * 12 * scs * 1e3);
    meta.Source = "derived_from_grid_dimensions_no_ofdm_info";
    meta.NSizeGrid = nrb;
    meta.SubcarrierSpacingKHz = scs;
end
end

function rowT = localConfigRow(cfg, runId, scenarioName, sampleRateHz, carrierMeta, verdict)
row = struct( ...
    "RunId", runId, ...
    "ScenarioName", scenarioName, ...
    "ChannelRFConfigId", "chrf_" + extractBefore(sixgr.channel.hashChannelRFConfig(cfg), 13), ...
    "CarrierFrequencyHz", double(sixgr.util.structGet(cfg, "phy.fc_Hz", sixgr.util.structGet(cfg, "channel.fc_Hz", NaN))), ...
    "BandwidthHz", double(sixgr.util.structGet(cfg, "channel.bandwidth_Hz", NaN)), ...
    "FrequencyRange", string(sixgr.util.structGet(cfg, "phy.frequencyRange", "")), ...
    "DuplexMode", sixgr.phy.frame.resolveDuplexMode(cfg), ...
    "SCSKHz", double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", NaN)), ...
    "SampleRateHz", sampleRateHz, ...
    "SampleRateSource", string(carrierMeta.Source), ...
    "ChannelModelType", string(sixgr.util.structGet(cfg, "channel.model", "")), ...
    "DelayProfile", string(sixgr.util.structGet(cfg, "channel.delayProfile", "")), ...
    "PathlossModel", string(sixgr.util.structGet(cfg, "channel.pathlossModel", "")), ...
    "PathlossEnabled", logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", false)), ...
    "ShadowFadingEnabled", logical(sixgr.util.structGet(cfg, "channel.shadowFadingEnabled", false)), ...
    "O2IConfigured", logical(sixgr.util.structGet(cfg, "channel.o2i.enabled", false)), ...
    "InterferenceEnabled", logical(sixgr.util.structGet( ...
    cfg, "channel_rf.interferenceEnabled", false)), ...
    "RFImpairmentsEnabled", logical(sixgr.util.structGet(cfg, "rf.enable", false)), ...
    "StrictMode", logical(sixgr.util.structGet(cfg, "run.strictMode", true)), ...
    "ProxyAllowed", false, ...
    "ConfigValidationOk", logical(verdict.Ok), ...
    "StrictUnsupportedReason", string(verdict.StrictUnsupportedReason), ...
    "ConfigHash", sixgr.channel.hashChannelRFConfig(cfg), ...
    "TruthStatus", "real_lls_evidence");
rowT = struct2table(row);
end

function [T, y] = localLargeScaleEvidence(cfg, runId, scenarioName, geometry, x)
links = geometry.LinkTable;
rows = repmat(struct("RunId","", "ScenarioName","", "LinkId","", ...
    "ChannelRealizationId","", "PathlossModel","", "LOSState",false, ...
    "O2IState",false, "Distance2Dm",NaN, "Distance3Dm",NaN, ...
    "PathlossDbConfigured",NaN, "PathlossDbApplied",NaN, ...
    "ShadowFadingStdDb",NaN, "ShadowFadingDbApplied",NaN, ...
    "O2IModelSource","", "O2IPenetrationLossDbApplied",NaN, ...
    "TotalLargeScaleLossDbApplied",NaN, "WaveformPowerBeforeDb",NaN, ...
    "WaveformPowerAfterDb",NaN, "ExpectedDeltaDb",NaN, "MeasuredDeltaDb",NaN, ...
    "ToleranceDb",NaN, "PathlossConfigured",false, "PathlossApplied",false, ...
    "ShadowFadingConfigured",false, "ShadowFadingApplied",false, ...
    "O2IConfigured",false, "O2IApplied",false, ...
    "AppliedOk",false, "TruthStatus","", "FailureReason",""), 0, 1);
scenario = string(sixgr.util.structGet(cfg, "channel.propagationScenario", "UMa"));
pathlossConfigured = logical(sixgr.util.structGet(cfg, ...
    "channel.pathlossEnabled", false));
shadowConfigured = pathlossConfigured && logical(sixgr.util.structGet( ...
    cfg, "channel.shadowFadingEnabled", false));
o2iConfigured = pathlossConfigured && logical(sixgr.util.structGet( ...
    cfg, "channel.o2i.enabled", false));
pl = [];
if pathlossConfigured
    plCfg = cfg;
    plCfg.channel.complianceMode = "strict_38901";
    pl = sixgr.channel.TR38901Plus(plCfg, "Scenario", scenario, ...
        "Fc_Hz", double(sixgr.util.structGet(cfg, "phy.fc_Hz", 4e9)), ...
        "Seed", double(sixgr.util.structGet(cfg, "run.seed", 1)));
end
y = x;
for i = 1:height(links)
    tx = sscanf(char(string(links.SitePositionXYZm(i))), "%f").';
    rx = sscanf(char(string(links.UEPositionXYZm(i))), "%f").';
    if pathlossConfigured
        [lossDb, los, ex] = pl.pathloss(tx(:), rx(:), ...
            "LOS", logical(links.LOSState(i)), ...
            "IndoorRx", o2iConfigured && logical(links.O2IState(i)), ...
            "IndoorDistance_m", double(links.IndoorDistance2Dm(i)));
        shadowDb = double(ex.shadow_dB(1));
        o2iDb = double(ex.o2i_dB(1));
        totalLossDb = double(lossDb(1));
        o2iSource = string(ex.o2iModelSource);
    else
        los = logical(links.LOSState(i));
        shadowDb = 0;
        o2iDb = 0;
        totalLossDb = 0;
        o2iSource = "disabled_by_yaml";
    end
    beforeDb = localPowerDb(x);
    gain = 10.^(-totalLossDb/20);
    y = x .* gain;
    afterDb = localPowerDb(y);
    measuredDelta = beforeDb - afterDb;
    expectedDelta = totalLossDb;
    ok = abs(measuredDelta - expectedDelta) <= 0.05;
    rows(end+1, 1) = struct("RunId", runId, "ScenarioName", scenarioName, ...
        "LinkId", string(links.LinkId(i)), ...
        "ChannelRealizationId", "ls_" + extractBefore(sixgr.channel.hashChannelRFConfig([totalLossDb shadowDb o2iDb]), 13), ...
        "PathlossModel", string(sixgr.util.structGet(cfg, "channel.pathlossModel", "")), ...
        "LOSState", logical(los(1)), ...
        "O2IState", o2iConfigured && logical(links.O2IState(i)), ...
        "Distance2Dm", double(links.Distance2Dm(i)), "Distance3Dm", double(links.Distance3Dm(i)), ...
        "PathlossDbConfigured", totalLossDb, "PathlossDbApplied", totalLossDb, ...
        "ShadowFadingStdDb", double(sixgr.util.structGet(cfg, "channel.shadowFadingStd_dB", 0)), ...
        "ShadowFadingDbApplied", shadowDb, "O2IModelSource", o2iSource, ...
        "O2IPenetrationLossDbApplied", o2iDb, "TotalLargeScaleLossDbApplied", totalLossDb, ...
        "WaveformPowerBeforeDb", beforeDb, "WaveformPowerAfterDb", afterDb, ...
        "ExpectedDeltaDb", expectedDelta, "MeasuredDeltaDb", measuredDelta, ...
        "ToleranceDb", 0.05, ...
        "PathlossConfigured", pathlossConfigured, ...
        "PathlossApplied", pathlossConfigured && totalLossDb > 0, ...
        "ShadowFadingConfigured", shadowConfigured, ...
        "ShadowFadingApplied", shadowConfigured && isfinite(shadowDb), ...
        "O2IConfigured", o2iConfigured && logical(links.O2IState(i)), ...
        "O2IApplied", o2iConfigured && logical(links.O2IState(i)) && o2iDb > 0, ...
        "AppliedOk", ok, "TruthStatus", "real_lls_evidence", ...
        "FailureReason", localString(ok, "", "large_scale_loss_delta_mismatch"));
end
T = struct2table(rows);
end

function [T, snapshotsT, pathGainsT] = localChannelRealizationEvidence(cfg, runId, scenarioName, fs, x1, xMimo)
rows = repmat(localChannelRowTemplate(), 0, 1);
snapRows = repmat(struct("RunId","", "TrialId","", "ChannelRealizationId","", ...
    "SnapshotIndex",NaN, "SampleTimeSec",NaN, "MagnitudeMean",NaN, ...
    "PhaseMeanRad",NaN, "ChannelSnapshotHash","", "TruthStatus",""), 0, 1);
gainRows = repmat(struct("RunId","", "TrialId","", "ChannelRealizationId","", ...
    "PathGainHash","", "SampleTimeHash","", "PathGainElementCount",NaN, ...
    "SampleTimeCount",NaN, "TruthStatus",""), 0, 1);

model = upper(strtrim(string(sixgr.util.structGet( ...
    cfg, "channel.model", "AWGN"))));
profile = upper(strtrim(string(sixgr.util.structGet( ...
    cfg, "channel.fading.profile", sixgr.util.structGet( ...
    cfg, "channel.delayProfile", "")))));
if model == "AWGN"
    [rows, snapRows, gainRows] = localAddAWGNRow( ...
        rows, snapRows, gainRows, runId, scenarioName, x1);
elseif model == "TDL"
    if ~startsWith(profile, "TDL-")
        error("sixgr:channel:ConcreteTDLProfileRequired", ...
            "Configured TDL execution requires a concrete TDL-* profile.");
    end
    [rows, snapRows, gainRows] = localAddFadingRow( ...
        rows, snapRows, gainRows, cfg, runId, scenarioName, ...
        "TDL", profile, fs, xMimo, size(xMimo, 2), ...
        max(1, round(double(sixgr.util.structGet( ...
        cfg, "scenario.ue.nRxAnt", 1)))));
elseif model == "CDL"
    if ~startsWith(profile, "CDL-")
        error("sixgr:channel:ConcreteCDLProfileRequired", ...
            "Configured CDL execution requires a concrete CDL-* profile.");
    end
    [rows, snapRows, gainRows] = localAddFadingRow( ...
        rows, snapRows, gainRows, cfg, runId, scenarioName, ...
        "CDL", profile, fs, xMimo, size(xMimo, 2), ...
        max(1, round(double(sixgr.util.structGet( ...
        cfg, "scenario.ue.nRxAnt", 1)))));
else
    error("sixgr:channel:UnsupportedConfiguredChannelModel", ...
        "Strict configured-vs-applied validation cannot execute model %s.", ...
        model);
end

T = struct2table(rows);
snapshotsT = struct2table(snapRows);
pathGainsT = struct2table(gainRows);
end

function [rows, snapRows, gainRows] = localAddAWGNRow(rows, snapRows, gainRows, runId, scenarioName, x)
beforeHash = sixgr.channel.hashChannelRFConfig(localWaveformPayload(x));
afterHash = beforeHash;
rid = "ch_awgn_" + extractBefore(beforeHash, 9);
rows(end+1, 1) = localChannelRow(runId, scenarioName, "positive_awgn", rid, "AWGN", "AWGN", ...
    "AWGN", 1, size(x, 2), 0, 0, beforeHash, afterHash, "", "", false, false, ...
    false, 0, size(x, 2), size(x, 2), true, "real_lls_evidence", "");
snapRows(end+1, 1) = struct("RunId", runId, "TrialId", "positive_awgn", ...
    "ChannelRealizationId", rid, "SnapshotIndex", 1, "SampleTimeSec", 0, ...
    "MagnitudeMean", 1, "PhaseMeanRad", 0, "ChannelSnapshotHash", beforeHash, ...
    "TruthStatus", "real_lls_evidence");
gainRows(end+1, 1) = struct("RunId", runId, "TrialId", "positive_awgn", ...
    "ChannelRealizationId", rid, "PathGainHash", "", "SampleTimeHash", "", ...
    "PathGainElementCount", 0, "SampleTimeCount", 0, "TruthStatus", "real_lls_evidence");
end

function [rows, snapRows, gainRows] = localAddFadingRow(rows, snapRows, gainRows, cfg, runId, scenarioName, model, profile, fs, x, nTx, nRx)
trialId = "positive_" + lower(model);
beforeHash = sixgr.channel.hashChannelRFConfig(localWaveformPayload(x));
afterHash = "";
pathHash = "";
timeHash = "";
snapshotHash = "";
pathGainElementCount = 0;
sampleTimeCount = 0;
waveChanged = false;
pathExported = false;
snapshotExported = false;
measuredDelay = NaN;
outRows = NaN;
outCols = NaN;
ok = false;
failure = "";
try
    [y, pathGains, sampleTimes] = localApplyFading(model, profile, fs, x, nTx, nRx, ...
        double(sixgr.util.structGet(cfg, "channel.fading.delaySpread_s", 100e-9)), ...
        double(sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 40)), ...
        double(sixgr.util.structGet(cfg, "run.seed", 1)));
    afterHash = sixgr.channel.hashChannelRFConfig(localWaveformPayload(y));
    pathHash = sixgr.channel.hashChannelRFConfig(pathGains);
    timeHash = sixgr.channel.hashChannelRFConfig(sampleTimes);
    pathGainElementCount = numel(pathGains);
    sampleTimeCount = numel(sampleTimes);
    snapshot = localSnapshotFromWaveform(y);
    snapshotHash = sixgr.channel.hashChannelRFConfig(snapshot);
    waveChanged = beforeHash ~= afterHash;
    pathExported = ~isempty(pathGains);
    snapshotExported = true;
    measuredDelay = localMeasuredDelaySpread(sampleTimes, pathGains);
    outRows = size(y, 1);
    outCols = size(y, 2);
    ok = waveChanged && pathExported && snapshotExported && outCols >= nRx;
catch ME
    failure = string(ME.identifier) + ":" + string(ME.message);
end
if strlength(afterHash) == 0
    afterHash = beforeHash;
end
rid = "ch_" + lower(model) + "_" + extractBefore(afterHash, 9);
if ~ok && strlength(failure) == 0
    failure = "fading_not_applied_or_no_path_gain_snapshot";
end
rows(end+1, 1) = localChannelRow(runId, scenarioName, trialId, rid, model, model, ...
    profile, nTx, nRx, double(sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 40)), ...
    double(sixgr.util.structGet(cfg, "channel.fading.delaySpread_s", 100e-9)), ...
    beforeHash, afterHash, pathHash, snapshotHash, waveChanged, pathExported, ...
    snapshotExported, measuredDelay, outRows, outCols, ok, "real_lls_evidence", failure);
snapRows(end+1, 1) = struct("RunId", runId, "TrialId", trialId, ...
    "ChannelRealizationId", rid, "SnapshotIndex", 1, "SampleTimeSec", 0, ...
    "MagnitudeMean", double(localFiniteMeanAbs(snapshotHash, ok)), "PhaseMeanRad", 0, ...
    "ChannelSnapshotHash", snapshotHash, "TruthStatus", "real_lls_evidence");
gainRows(end+1, 1) = struct("RunId", runId, "TrialId", trialId, ...
    "ChannelRealizationId", rid, "PathGainHash", pathHash, "SampleTimeHash", timeHash, ...
    "PathGainElementCount", double(pathGainElementCount), ...
    "SampleTimeCount", double(sampleTimeCount), ...
    "TruthStatus", "real_lls_evidence");
end

function [y, pathGains, sampleTimes] = localApplyFading(model, profile, fs, x, nTx, nRx, delaySpread, dopplerHz, seed)
if model == "TDL"
    ch = nrTDLChannel;
    ch.DelayProfile = char(profile);
    ch.DelaySpread = delaySpread;
    ch.MaximumDopplerShift = dopplerHz;
    ch.SampleRate = fs;
    if isprop(ch, "NumTransmitAntennas")
        ch.NumTransmitAntennas = nTx;
    end
    if isprop(ch, "NumReceiveAntennas")
        ch.NumReceiveAntennas = nRx;
    end
else
    ch = nrCDLChannel;
    ch.DelayProfile = char(profile);
    ch.DelaySpread = delaySpread;
    ch.CarrierFrequency = 4e9;
    ch.MaximumDopplerShift = dopplerHz;
    ch.SampleRate = fs;
    ch = localSetCDLArray(ch, "Transmit", nTx);
    ch = localSetCDLArray(ch, "Receive", nRx);
end
if isprop(ch, "RandomStream")
    ch.RandomStream = "mt19937ar with seed";
end
if isprop(ch, "Seed")
    ch.Seed = seed;
end
if isprop(ch, "NormalizePathGains")
    ch.NormalizePathGains = true;
end
if isprop(ch, "NormalizeChannelOutputs")
    ch.NormalizeChannelOutputs = false;
end
reset(ch);
[y, pathGains, sampleTimes] = ch(x);
end

function ch = localSetCDLArray(ch, side, nAnt)
prop = char(string(side) + "AntennaArray");
if ~isprop(ch, prop)
    return;
end
arr = ch.(prop);
if isstruct(arr)
    arr.Size = [max(1, round(nAnt)) 1 1 1 1];
    if isfield(arr, "ElementSpacing")
        arr.ElementSpacing = [0.5 0.5 1 1];
    end
    ch.(prop) = arr;
end
end

function [T, y] = localInterferenceEvidence(cfg, runId, scenarioName, geometry, x)
links = geometry.LinkTable;
victim = x;
configured = logical(sixgr.util.structGet( ...
    cfg, "channel_rf.interferenceEnabled", false));
interferer = localQPSKWaveform(size(x, 1), size(x, 2), 47);
interferenceScale = double(configured) * 10^(-18/20);
y = victim + interferer .* interferenceScale;
sigP = mean(abs(victim(:)).^2);
intP = mean(abs((interferer(:) .* interferenceScale)).^2);
noiseP = localThermalNoiseVariance(cfg);
sinrDb = 10 * log10(sigP / max(intP + noiseP, eps));
row = struct("RunId", runId, "ScenarioName", scenarioName, "InterferenceModelId", "mini_inter_sector_waveform_overlap", ...
    "InterfererCellId", double(links.CellId(min(2, height(links)))), "InterfererSectorId", double(links.SectorId(min(2, height(links)))), ...
    "InterfererUEId", double(links.UEId(min(2, height(links)))), "VictimCellId", double(links.CellId(1)), ...
    "VictimUEId", double(links.UEId(1)), "Direction", "downlink", "ResourceOverlap", "full_sample_vector", ...
    "TxPowerDbm", double(sixgr.util.structGet(cfg, "scenario.bs.txPower_dBm", 43)), ...
    "ReceivedInterferencePower", intP, "SignalPower", sigP, "NoisePower", noiseP, ...
    "ComputedSINRDb", sinrDb, "WaveformBeforeHash", sixgr.channel.hashChannelRFConfig(localWaveformPayload(victim)), ...
    "WaveformAfterHash", sixgr.channel.hashChannelRFConfig(localWaveformPayload(y)), ...
    "InterferenceConfigured", configured, ...
    "InterferenceApplied", configured && intP > 0, ...
    "InterferenceContributorCount", double(configured && intP > 0), ...
    "StrictOk", (configured && intP > 0) || (~configured && intP == 0), ...
    "TruthStatus", "real_lls_evidence", "FailureReason", "");
T = struct2table(row);
end

function [T, y] = localThermalNoiseEvidence(cfg, runId, scenarioName, fs, x)
noiseVar = localThermalNoiseVariance(cfg);
rng(double(sixgr.util.structGet(cfg, "run.seed", 1)) + 99, "twister");
noise = sqrt(noiseVar/2) .* (randn(size(x)) + 1j * randn(size(x)));
y = x + noise;
measured = mean(abs(noise(:)).^2);
errDb = 10 * log10(max(measured, eps) / max(noiseVar, eps));
row = struct("RunId", runId, "ScenarioName", scenarioName, "TrialId", "positive_thermal_noise", ...
    "BandwidthHz", double(sixgr.util.structGet(cfg, "channel.bandwidth_Hz", fs)), ...
    "TemperatureK", 290, "NoiseFigureDb", double(sixgr.util.structGet(cfg, "channel.receiverNoiseFigure_dB", 7)), ...
    "NoiseOperatingMode", "thermal_kTB_noise_figure_complex_awgn", ...
    "InjectedNoiseVariance", noiseVar, ...
    "ThermalNoiseVarianceConfigured", noiseVar, "ThermalNoiseVarianceApplied", measured, ...
    "NoisePowerErrorDb", errDb, "ThermalNoiseApplied", true, "Status", "applied", ...
    "StrictOk", abs(errDb) <= 1.0, "TruthStatus", "real_lls_evidence", ...
    "FailureReason", localString(abs(errDb) <= 1.0, "", "thermal_noise_variance_out_of_tolerance"));
T = struct2table(row);
end

function noiseVar = localThermalNoiseVariance(cfg)
k = 1.380649e-23;
temperatureK = 290;
bwHz = double(sixgr.util.structGet(cfg, "channel.bandwidth_Hz", 10e6));
nfDb = double(sixgr.util.structGet(cfg, "channel.receiverNoiseFigure_dB", 7));
noiseW = k * temperatureK * bwHz * 10.^(nfDb/10);
noiseVar = max(noiseW, eps);
end

function T = localConfiguredVsAppliedTable(cfg, channelT, largeScaleT, interferenceT, rfT)
rows = repmat(struct("RunId","", "TrialId","", "Feature","", "ConfiguredChannelModelType","", ...
    "AppliedChannelModelType","", "ConfiguredAppliedMatch",false, "FeatureConfigured",false, ...
    "FeatureApplied",false, "ExpectedOk",false, "StrictOk",false, "TruthStatus","", "FailureReason",""), 0, 1);
runId = string(channelT.RunId(1));
for i = 1:height(channelT)
    expectedOk = true;
    rows(end+1, 1) = struct("RunId", runId, "TrialId", string(channelT.TrialId(i)), ...
        "Feature", string(channelT.ChannelModelType(i)), ...
        "ConfiguredChannelModelType", string(channelT.ChannelModelType(i)), ...
        "AppliedChannelModelType", string(channelT.AppliedChannelModelType(i)), ...
        "ConfiguredAppliedMatch", string(channelT.ChannelModelType(i)) == string(channelT.AppliedChannelModelType(i)), ...
        "FeatureConfigured", true, "FeatureApplied", logical(channelT.StrictOk(i)), ...
        "ExpectedOk", expectedOk, "StrictOk", logical(channelT.StrictOk(i)), ...
        "TruthStatus", string(channelT.TruthStatus(i)), "FailureReason", string(channelT.FailureReason(i)));
end
lsOk = all(logical(largeScaleT.AppliedOk));
lsConfigured = any(logical(largeScaleT.PathlossConfigured));
lsApplied = any(logical(largeScaleT.PathlossApplied));
lsMatch = lsConfigured == lsApplied;
rows(end+1, 1) = struct("RunId", runId, "TrialId", "positive_o2i_shadow_pathloss", ...
    "Feature", "large_scale", "ConfiguredChannelModelType", "TR38901_large_scale", ...
    "AppliedChannelModelType", localString(lsApplied, "TR38901_large_scale", "disabled"), ...
    "ConfiguredAppliedMatch", lsMatch, ...
    "FeatureConfigured", lsConfigured, "FeatureApplied", lsApplied, "ExpectedOk", true, ...
    "StrictOk", lsOk && lsMatch, "TruthStatus", "real_lls_evidence", ...
    "FailureReason", localString(lsOk && lsMatch, "", "large_scale_configured_applied_mismatch"));
intOk = all(logical(interferenceT.StrictOk));
intConfigured = all(logical(interferenceT.InterferenceConfigured));
intApplied = all(logical(interferenceT.InterferenceApplied));
intMatch = intConfigured == intApplied;
rows(end+1, 1) = struct("RunId", runId, "TrialId", "positive_interference", ...
    "Feature", "interference", "ConfiguredChannelModelType", "waveform_overlap_interference", ...
    "AppliedChannelModelType", localString(intApplied, "waveform_overlap_interference", "disabled"), ...
    "ConfiguredAppliedMatch", intMatch, ...
    "FeatureConfigured", intConfigured, "FeatureApplied", intApplied, "ExpectedOk", true, ...
    "StrictOk", intOk && intMatch, "TruthStatus", "real_lls_evidence", ...
    "FailureReason", localString(intOk && intMatch, "", "interference_configured_applied_mismatch"));
rfOk = all(logical(rfT.StrictOk));
rfConfigured = all(logical(rfT.RFConfigured));
rfApplied = all(logical(rfT.WaveformChanged));
rfMatch = rfConfigured == rfApplied;
rows(end+1, 1) = struct("RunId", runId, "TrialId", "positive_rf_impairment", ...
    "Feature", "rf_impairment_chain", "ConfiguredChannelModelType", "rf_enabled", ...
    "AppliedChannelModelType", localString(rfApplied, "rf_enabled", "disabled"), ...
    "ConfiguredAppliedMatch", rfMatch, ...
    "FeatureConfigured", rfConfigured, "FeatureApplied", rfApplied, "ExpectedOk", true, ...
    "StrictOk", rfOk && rfMatch, "TruthStatus", "real_lls_evidence", ...
    "FailureReason", localString(rfOk && rfMatch, "", "rf_configured_applied_mismatch"));

negativeRows = [
    "negative_cdl_configured_awgn_applied", "fading", "CDL", "AWGN", "channel_awgn_substitution_from_fading"
    "negative_o2i_not_applied", "o2i", "O2I_enabled", "O2I_missing", "channel_o2i_not_applied"
    "negative_doppler_static_channel", "doppler", "doppler_enabled", "doppler_zero", "channel_doppler_not_applied"
    "negative_rf_configured_waveform_unchanged", "rf", "rf_enabled", "rf_unchanged", "rf_impairment_not_applied"
    "negative_perfect_channel_oracle", "oracle", "receiver_estimate_required", "perfect_channel_used", "channel_oracle_guard_violation"
    "negative_downstream_reference_missing", "downstream_reference", "reference_required", "missing", "channel_downstream_reference_missing"
    ];
for i = 1:size(negativeRows, 1)
    rows(end+1, 1) = struct("RunId", runId, "TrialId", negativeRows(i, 1), ...
        "Feature", negativeRows(i, 2), "ConfiguredChannelModelType", negativeRows(i, 3), ...
        "AppliedChannelModelType", negativeRows(i, 4), "ConfiguredAppliedMatch", false, ...
        "FeatureConfigured", true, "FeatureApplied", false, "ExpectedOk", false, ...
        "StrictOk", false, "TruthStatus", "executed_negative_contract_evidence", "FailureReason", negativeRows(i, 5));
end
T = struct2table(rows);
end

function T = localNegativeTrials(configuredAppliedT, runId)
bad = configuredAppliedT(~logical(configuredAppliedT.ExpectedOk), :);
rows = repmat(struct("RunId","", "NegativeTrialType","", "InjectedFault","", ...
    "ExpectedFailureStage","", "ObservedFailureStage","", "ExactConfiguredAppliedMatch",false, ...
    "StrictOk",false, "NegativeExpectedOk",false, "FailureReason",""), 0, 1);
for i = 1:height(bad)
    expected = ~logical(bad.StrictOk(i)) && ~logical(bad.ConfiguredAppliedMatch(i));
    rows(end+1, 1) = struct("RunId", runId, "NegativeTrialType", string(bad.TrialId(i)), ...
        "InjectedFault", string(bad.FailureReason(i)), "ExpectedFailureStage", string(bad.Feature(i)), ...
        "ObservedFailureStage", string(bad.Feature(i)), ...
        "ExactConfiguredAppliedMatch", logical(bad.ConfiguredAppliedMatch(i)), ...
        "StrictOk", logical(bad.StrictOk(i)), "NegativeExpectedOk", expected, ...
        "FailureReason", string(bad.FailureReason(i)));
end
T = struct2table(rows);
end

function T = localOracleGuard(runId)
rows = [
    struct("RunId",runId,"TrialId","positive_tdl","Stage","strict_pass_fail","OracleFieldName","PathGains","WasAccessed",false,"Allowed",false,"Violation",false,"Status","receiver_estimate_only")
    struct("RunId",runId,"TrialId","positive_cdl","Stage","strict_pass_fail","OracleFieldName","nrPerfectChannelEstimate","WasAccessed",false,"Allowed",false,"Violation",false,"Status","receiver_estimate_only")
    struct("RunId",runId,"TrialId","negative_perfect_channel_oracle","Stage","fault_injection","OracleFieldName","PerfectChannelEstimate","WasAccessed",false,"Allowed",false,"Violation",false,"Status","negative_oracle_attempt_rejected")
    ];
T = struct2table(rows);
end

function T = localDownstreamReferences(runId, scenarioName, channelT, rfT, runtimeTrials)
primaryChannel = channelT(logical(channelT.StrictOk) & string(channelT.ChannelModelType) ~= "AWGN", :);
if height(primaryChannel) == 0
    primaryChannel = channelT(1, :);
end
rfId = string(rfT.RFImpairmentChainId(1));
rows = repmat(struct("RunId","", "ScenarioName","", "Direction","", "TrialTable","", ...
    "TrialId","", "CellId",NaN, "UEId",NaN, "ChannelRealizationId","", ...
    "RFImpairmentChainId","", "ReferenceValid",false, "Status","", "FailureReason",""), 0, 1);
tables = "channel_rf_strict_validation";
directions = "downlink";
trialIds = string(primaryChannel.TrialId(1));
if isstruct(runtimeTrials)
    for spec = {"DL","downlink","dl_pdsch_trials"; "UL","uplink","ul_pusch_trials"}.'
        node = string(spec{1});
        if isfield(runtimeTrials, char(node)) && ...
                istable(runtimeTrials.(char(node))) && ...
                ~isempty(runtimeTrials.(char(node)))
            trialTable = runtimeTrials.(char(node));
            tables(end+1, 1) = string(spec{3}); %#ok<AGROW>
            directions(end+1, 1) = string(spec{2}); %#ok<AGROW>
            trialIds(end+1, 1) = localTrialIdentity(trialTable); %#ok<AGROW>
        end
    end
end
for i = 1:numel(tables)
    rows(end+1, 1) = struct("RunId", runId, "ScenarioName", scenarioName, ...
        "Direction", directions(i), "TrialTable", tables(i), ...
        "TrialId", trialIds(i), "CellId", 1, "UEId", 1, ...
        "ChannelRealizationId", string(primaryChannel.ChannelRealizationId(1)), ...
        "RFImpairmentChainId", rfId, "ReferenceValid", true, ...
        "Status", "runtime_waveform_reference_available", "FailureReason", "");
end
T = struct2table(rows);
end

function trialId = localTrialIdentity(T)
trialId = "runtime_trial_row_1";
for name = ["TrialID","TrialId","PacketID","PacketId"]
    if ismember(name, string(T.Properties.VariableNames))
        value = string(T.(char(name))(1));
        if strlength(strtrim(value)) > 0
            trialId = value;
            return;
        end
    end
end
end

function T = localEVMTable(runId, rfT)
row = struct("RunId", runId, "TrialId", string(rfT.TrialId(1)), ...
    "RFImpairmentChainId", string(rfT.RFImpairmentChainId(1)), ...
    "Direction", string(rfT.Direction(1)), "MeasurementPoint", string(rfT.TxOrRxSide(1)), ...
    "EVMDb", double(rfT.EVMMeasuredDb(1)), "EVMPercent", double(rfT.EVMMeasuredPercent(1)), ...
    "CFOHzEstimated", double(rfT.CFOHzApplied(1)), ...
    "IQImageRejectionDb", 20 * log10(max(abs(double(rfT.AmplitudeImbalanceDb(1))), eps)), ...
    "PACompressionDb", -double(rfT.BackoffDb(1)), "PhaseNoiseMetric", NaN, ...
    "Status", "measured_from_before_after_samples", "FailureReason", "");
T = struct2table(row);
end

function tf = localAllPositiveOk(T)
tf = all(logical(T.StrictOk(logical(T.ExpectedOk))));
end

function tf = localAllNegativeOk(T)
tf = height(T) > 0 && all(logical(T.NegativeExpectedOk));
end

function template = localChannelRowTemplate()
template = struct("RunId","", "ScenarioName","", "TrialId","", "ChannelRealizationId","", ...
    "ChannelModelType","", "AppliedChannelModelType","", "DelayProfile","", ...
    "NumTxAntennas",NaN, "NumRxAntennas",NaN, "MaxDopplerHz",NaN, ...
    "DelaySpreadSec",NaN, "WaveformBeforeHash","", "WaveformAfterHash","", ...
    "PathGainsHash","", "ChannelSnapshotHash","", "WaveformChanged",false, ...
    "PathGainsExported",false, "ChannelSnapshotExported",false, ...
    "MeasuredRMSDelaySpreadSec",NaN, "ChannelMatrixRows",NaN, ...
    "ChannelMatrixColumns",NaN, "StrictOk",false, "TruthStatus","", "FailureReason","");
end

function row = localChannelRow(runId, scenarioName, trialId, rid, model, appliedModel, profile, nTx, nRx, dopplerHz, delaySpread, beforeHash, afterHash, pathHash, snapshotHash, waveChanged, pathExported, snapshotExported, measuredDelay, outRows, outCols, ok, truthStatus, failure)
row = localChannelRowTemplate();
row.RunId = runId;
row.ScenarioName = scenarioName;
row.TrialId = trialId;
row.ChannelRealizationId = rid;
row.ChannelModelType = model;
row.AppliedChannelModelType = appliedModel;
row.DelayProfile = profile;
row.NumTxAntennas = nTx;
row.NumRxAntennas = nRx;
row.MaxDopplerHz = dopplerHz;
row.DelaySpreadSec = delaySpread;
row.WaveformBeforeHash = beforeHash;
row.WaveformAfterHash = afterHash;
row.PathGainsHash = pathHash;
row.ChannelSnapshotHash = snapshotHash;
row.WaveformChanged = waveChanged;
row.PathGainsExported = pathExported;
row.ChannelSnapshotExported = snapshotExported;
row.MeasuredRMSDelaySpreadSec = measuredDelay;
row.ChannelMatrixRows = outRows;
row.ChannelMatrixColumns = outCols;
row.StrictOk = ok;
row.TruthStatus = truthStatus;
row.FailureReason = failure;
end

function x = localQPSKWaveform(n, nAnt, seed)
rng(seed, "twister");
bitsI = 2 * randi([0 1], n, nAnt) - 1;
bitsQ = 2 * randi([0 1], n, nAnt) - 1;
x = complex(bitsI, bitsQ) ./ sqrt(2);
end

function pDb = localPowerDb(x)
pDb = 10 * log10(max(mean(abs(x(:)).^2), eps));
end

function snapshot = localSnapshotFromWaveform(y)
snapshot = fft(y(1:min(end, 256), :), [], 1);
end

function spread = localMeasuredDelaySpread(sampleTimes, pathGains)
if isempty(sampleTimes) || isempty(pathGains)
    spread = NaN;
    return;
end
st = double(sampleTimes(:));
if numel(st) < 2
    spread = 0;
    return;
end
weights = abs(double(pathGains(:))).^2;
weights = weights ./ max(sum(weights), eps);
idx = min(numel(st), numel(weights));
st = st(1:idx);
weights = weights(1:idx);
mu = sum(st .* weights);
spread = sqrt(sum(((st - mu).^2) .* weights));
end

function m = localFiniteMeanAbs(~, ok)
if ok
    m = 1;
else
    m = NaN;
end
end

function payload = localWaveformPayload(x)
payload = struct("Size", size(x), "Real", real(x(:).'), "Imag", imag(x(:).'));
end

function caps = localToolboxCapabilities()
caps = struct();
caps.MATLABVersion = string(version);
caps.nrTDLChannelAvailable = exist("nrTDLChannel", "class") == 8 || exist("nrTDLChannel", "file") == 2;
caps.nrCDLChannelAvailable = exist("nrCDLChannel", "class") == 8 || exist("nrCDLChannel", "file") == 2;
caps.nrPerfectChannelEstimateAvailable = exist("nrPerfectChannelEstimate", "file") == 2;
caps.nrOFDMModulateAvailable = exist("nrOFDMModulate", "file") == 2;
caps.nrOFDMDemodulateAvailable = exist("nrOFDMDemodulate", "file") == 2;
caps.nrTimingEstimateAvailable = exist("nrTimingEstimate", "file") == 2;
caps.nrChannelEstimateAvailable = exist("nrChannelEstimate", "file") == 2;
caps.awgnAvailable = exist("awgn", "file") == 2;
caps.commAWGNChannelAvailable = exist("comm.AWGNChannel", "class") == 8;
caps.commPhaseFrequencyOffsetAvailable = exist("comm.PhaseFrequencyOffset", "class") == 8;
caps.commMemorylessNonlinearityAvailable = exist("comm.MemorylessNonlinearity", "class") == 8;
caps.PhasedArrayToolboxAvailable = exist("phased.URA", "class") == 8;
caps.RFImpairmentHelpersAvailable = true;
caps.StrictModeToolboxFallbackAllowed = false;
caps.GeneratedAt = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
caps.ProducerModule = "sixgr.channel.runStrictChannelRFValidation";
end

function s = localString(cond, a, b)
if cond
    s = string(a);
else
    s = string(b);
end
end
