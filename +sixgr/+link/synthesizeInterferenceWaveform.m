function [sumWaveform, meta] = synthesizeInterferenceWaveform(direction, desiredWaveform, replay, interferenceBundle)
%SYNTHESIZEINTERFERENCEWAVEFORM Build sample-domain interference for one victim link.
% Keep this file ASCII-only.
%
% This helper supports the no-proxy coupled-truth interference mode:
%   - full_per_link_channel_waveform_sum
%       Each interferer is rebuilt through its real grant-specific PHY Tx
%       path, then propagated through its own fading channel realization
%       into the victim receiver before large-scale loss is applied.
% Legacy large-scale overlap modes are blocked before this helper in the
% active LLS resolver and are not populated as runtime truth.

sumWaveform = complex(zeros(size(desiredWaveform), "like", desiredWaveform));
meta = struct( ...
    "InterferenceMode", "none", ...
    "Contributors", 0, ...
    "AggregatedRxPower_dBm", NaN, ...
    "VictimPowerReference_dBm", NaN, ...
    "VictimPowerReferenceSource", "", ...
    "PowerSource", "", ...
    "FullPerLinkChannelTruthUsed", false, ...
    "ChannelObjectSource", "", ...
    "ChannelObjectClass", "", ...
    "ChannelArrayHandlingStatus", "", ...
    "ChannelArrayHandlingBlocker", "", ...
    "ChannelGeometryCouplingLevel", "", ...
    "GeometryAdapterType", "", ...
    "GeometryAdapterSource", "", ...
    "GeometryAdapterLimitation", "", ...
    "GeometryAdapterPortMapping", "", ...
    "ChannelUsesSameRuntimeAntennaAssumptions", false, ...
    "InterfererBeamformingAppliedCount", 0, ...
    "InterfererExplicitBeamWeightCount", 0, ...
    "InterfererTransformPrecodingCount", 0, ...
    "InterfererPrecoderSourceSet", "", ...
    "InterfererPrecodingModeSet", "", ...
    "InterfererBeamIndexSetSummary", "");

if nargin < 4 || isempty(interferenceBundle) || ~isstruct(interferenceBundle)
    return;
end
if isempty(fieldnames(interferenceBundle))
    return;
end

entries = interferenceBundle(:);
victimPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
victimPowerSource = string(sixgr.util.structGet(replay, "ServingRSRPSource", ""));
desiredPower = mean(abs(double(desiredWaveform(:))).^2, "omitnan");
samplePowerPerMilliwatt = NaN;
if isfinite(victimPower_dBm) && isfinite(desiredPower) && desiredPower > 0
    victimMilliwatt = 10.^(victimPower_dBm / 10);
    if isfinite(victimMilliwatt) && victimMilliwatt > 0
        samplePowerPerMilliwatt = desiredPower / victimMilliwatt;
    end
end

aggMilliwatt = 0;
modeToken = "";
powerSource = "";
count = 0;
fullTruthUsed = false;
precoderSources = strings(0, 1);
precodingModes = strings(0, 1);
beamIndexSets = strings(0, 1);
channelObjectSources = strings(0, 1);
channelObjectClasses = strings(0, 1);
channelHandlingStatuses = strings(0, 1);
channelHandlingBlockers = strings(0, 1);
channelGeometryLevels = strings(0, 1);
geometryAdapterTypes = strings(0, 1);
geometryAdapterSources = strings(0, 1);
geometryAdapterLimitations = strings(0, 1);
geometryAdapterPortMappings = strings(0, 1);
channelUsesSameRuntime = false(0, 1);
beamformingCount = 0;
explicitBeamWeightCount = 0;
transformPrecodingCount = 0;
for i = 1:numel(entries)
    entry = entries(i);
    [waveform, rxPower_dBm, entryMeta] = localBuildOneInterferer(direction, entry, size(desiredWaveform), samplePowerPerMilliwatt);
    if isempty(waveform)
        continue;
    end
    sumWaveform = sumWaveform + cast(waveform, "like", desiredWaveform);
    if isfinite(rxPower_dBm)
        aggMilliwatt = aggMilliwatt + 10.^(rxPower_dBm / 10);
    end
    if strlength(modeToken) == 0
        modeToken = string(sixgr.util.structGet(entryMeta, "InterferenceMode", ...
            sixgr.util.structGet(entry, "InterferenceMode", "none")));
    end
    if strlength(powerSource) == 0
        powerSource = string(sixgr.util.structGet(entryMeta, "PowerSource", ""));
    end
    fullTruthUsed = fullTruthUsed || logical(sixgr.util.structGet(entryMeta, "FullPerLinkChannelTruthUsed", false));
    channelObjectSource = string(sixgr.util.structGet(entryMeta, "ChannelObjectSource", ""));
    if strlength(strtrim(channelObjectSource)) > 0
        channelObjectSources(end + 1, 1) = channelObjectSource; %#ok<AGROW>
    end
    channelObjectClass = string(sixgr.util.structGet(entryMeta, "ChannelObjectClass", ""));
    if strlength(strtrim(channelObjectClass)) > 0
        channelObjectClasses(end + 1, 1) = channelObjectClass; %#ok<AGROW>
    end
    channelHandlingStatus = string(sixgr.util.structGet(entryMeta, "ChannelArrayHandlingStatus", ""));
    if strlength(strtrim(channelHandlingStatus)) > 0
        channelHandlingStatuses(end + 1, 1) = channelHandlingStatus; %#ok<AGROW>
    end
    channelHandlingBlocker = string(sixgr.util.structGet(entryMeta, "ChannelArrayHandlingBlocker", ""));
    if strlength(strtrim(channelHandlingBlocker)) > 0
        channelHandlingBlockers(end + 1, 1) = channelHandlingBlocker; %#ok<AGROW>
    end
    channelGeometryLevel = string(sixgr.util.structGet(entryMeta, "ChannelGeometryCouplingLevel", ""));
    if strlength(strtrim(channelGeometryLevel)) > 0
        channelGeometryLevels(end + 1, 1) = channelGeometryLevel; %#ok<AGROW>
    end
    geometryAdapterType = string(sixgr.util.structGet(entryMeta, "GeometryAdapterType", ""));
    if strlength(strtrim(geometryAdapterType)) > 0
        geometryAdapterTypes(end + 1, 1) = geometryAdapterType; %#ok<AGROW>
    end
    geometryAdapterSource = string(sixgr.util.structGet(entryMeta, "GeometryAdapterSource", ""));
    if strlength(strtrim(geometryAdapterSource)) > 0
        geometryAdapterSources(end + 1, 1) = geometryAdapterSource; %#ok<AGROW>
    end
    geometryAdapterLimitation = string(sixgr.util.structGet(entryMeta, "GeometryAdapterLimitation", ""));
    if strlength(strtrim(geometryAdapterLimitation)) > 0
        geometryAdapterLimitations(end + 1, 1) = geometryAdapterLimitation; %#ok<AGROW>
    end
    geometryAdapterPortMapping = string(sixgr.util.structGet(entryMeta, "GeometryAdapterPortMapping", ""));
    if strlength(strtrim(geometryAdapterPortMapping)) > 0
        geometryAdapterPortMappings(end + 1, 1) = geometryAdapterPortMapping; %#ok<AGROW>
    end
    channelUsesSameRuntime(end + 1, 1) = logical(sixgr.util.structGet(entryMeta, "ChannelUsesSameRuntimeAntennaAssumptions", false)); %#ok<AGROW>
    beamformingCount = beamformingCount + double(logical(sixgr.util.structGet(entryMeta, "BeamformingApplied", false)));
    explicitBeamWeightCount = explicitBeamWeightCount + double(logical(sixgr.util.structGet(entryMeta, "ExplicitBeamWeightsApplied", false)));
    transformPrecodingCount = transformPrecodingCount + double(logical(sixgr.util.structGet(entryMeta, "TransformPrecodingApplied", false)));
    precoderSource = string(sixgr.util.structGet(entryMeta, "PrecoderSource", ""));
    if strlength(strtrim(precoderSource)) > 0
        precoderSources(end + 1, 1) = precoderSource; %#ok<AGROW>
    end
    precodingMode = string(sixgr.util.structGet(entryMeta, "PrecodingMode", ""));
    if strlength(strtrim(precodingMode)) > 0
        precodingModes(end + 1, 1) = precodingMode; %#ok<AGROW>
    end
    beamIndexSet = string(sixgr.util.structGet(entryMeta, "BeamIndexSet", ""));
    if strlength(strtrim(beamIndexSet)) > 0
        beamIndexSets(end + 1, 1) = beamIndexSet; %#ok<AGROW>
    end
    count = count + 1;
end

if count < 1
    return;
end

meta.InterferenceMode = localSafeCharToken(modeToken);
meta.Contributors = double(count);
meta.VictimPowerReference_dBm = double(victimPower_dBm);
meta.VictimPowerReferenceSource = localSafeCharToken(victimPowerSource);
meta.PowerSource = localSafeCharToken(powerSource);
meta.FullPerLinkChannelTruthUsed = logical(fullTruthUsed);
meta.ChannelObjectSource = localSafeCharToken(localUniqueTokenSet(channelObjectSources));
meta.ChannelObjectClass = localSafeCharToken(localUniqueTokenSet(channelObjectClasses));
meta.ChannelArrayHandlingStatus = localSafeCharToken(localUniqueTokenSet(channelHandlingStatuses));
meta.ChannelArrayHandlingBlocker = localSafeCharToken(localUniqueTokenSet(channelHandlingBlockers));
meta.ChannelGeometryCouplingLevel = localSafeCharToken(localUniqueTokenSet(channelGeometryLevels));
meta.GeometryAdapterType = localSafeCharToken(localUniqueTokenSet(geometryAdapterTypes));
meta.GeometryAdapterSource = localSafeCharToken(localUniqueTokenSet(geometryAdapterSources));
meta.GeometryAdapterLimitation = localSafeCharToken(localUniqueTokenSet(geometryAdapterLimitations));
meta.GeometryAdapterPortMapping = localSafeCharToken(localUniqueTokenSet(geometryAdapterPortMappings));
meta.ChannelUsesSameRuntimeAntennaAssumptions = ~isempty(channelUsesSameRuntime) && all(channelUsesSameRuntime);
meta.InterfererBeamformingAppliedCount = double(beamformingCount);
meta.InterfererExplicitBeamWeightCount = double(explicitBeamWeightCount);
meta.InterfererTransformPrecodingCount = double(transformPrecodingCount);
meta.InterfererPrecoderSourceSet = localSafeCharToken(localUniqueTokenSet(precoderSources));
meta.InterfererPrecodingModeSet = localSafeCharToken(localUniqueTokenSet(precodingModes));
meta.InterfererBeamIndexSetSummary = localSafeCharToken(localUniqueTokenSet(beamIndexSets));
if aggMilliwatt > 0
    meta.AggregatedRxPower_dBm = 10 * log10(aggMilliwatt);
end
end

function [waveform, rxPower_dBm, entryMeta] = localBuildOneInterferer(direction, entry, targetSize, samplePowerPerMilliwatt)
waveform = [];
rxPower_dBm = NaN;
grant = sixgr.util.structGet(entry, "GrantSnapshot", struct());
entryMeta = struct( ...
    "InterferenceMode", localSafeCharToken(sixgr.util.structGet(entry, "InterferenceMode", "none")), ...
    "PowerSource", "", ...
    "FullPerLinkChannelTruthUsed", false, ...
    "ChannelObjectSource", "", ...
    "ChannelObjectClass", "", ...
    "ChannelArrayHandlingStatus", "", ...
    "ChannelArrayHandlingBlocker", "", ...
    "ChannelGeometryCouplingLevel", "", ...
    "GeometryAdapterType", "", ...
    "GeometryAdapterSource", "", ...
    "GeometryAdapterLimitation", "", ...
    "GeometryAdapterPortMapping", "", ...
    "ChannelUsesSameRuntimeAntennaAssumptions", false, ...
    "PrecoderSource", localSafeCharToken(sixgr.util.structGet(grant, "PrecoderSource", "none")), ...
    "PrecodingMode", localSafeCharToken(sixgr.util.structGet(grant, "PrecodingMode", "")), ...
    "BeamIndexSet", localSafeCharToken(sixgr.util.structGet(grant, "AppliedBeamIndexSet", "")), ...
    "BeamformingApplied", logical(sixgr.util.structGet(grant, "BeamformingApplied", false)), ...
    "ExplicitBeamWeightsApplied", logical(sixgr.util.structGet(grant, "ExplicitBeamWeightsApplied", false)), ...
    "TransformPrecodingApplied", logical(sixgr.util.structGet(grant, "TransformPrecodingApplied", false)));

cfg = sixgr.util.structGet(entry, "Cfg", struct());
if ~(isstruct(cfg) && ~isempty(fieldnames(cfg)))
    return;
end

direction = upper(string(direction));
signalType = upper(string(sixgr.util.structGet(entry, "SignalType", direction)));
cfg = localApplyPerLinkSeed(cfg, double(sixgr.util.structGet(entry, "Seed", NaN)));
transportBlockBits = sixgr.util.structGet(entry, "TransportBlockBits", []);
rv = sixgr.util.structGet(entry, "RV", []);
seed = double(sixgr.util.structGet(entry, "Seed", NaN));
uciBits = int8(sixgr.util.structGet(entry, "ExpectedUCIBits", int8(1)));
requestedFormat = double(sixgr.util.structGet(entry, "ResolvedFormat", ...
    sixgr.util.structGet(entry, "RequestedFormat", sixgr.util.structGet(cfg, "phy.pucch.format", NaN))));
rnti = double(sixgr.util.structGet(entry, "RNTI", sixgr.util.structGet(cfg, "phy.rnti", NaN)));

txWave = [];
txInfo = struct();
restore = [];
if isfinite(seed) && seed >= 1
    priorRng = rng;
    restore = onCleanup(@() rng(priorRng)); %#ok<NASGU>
    rng(max(1, round(seed)), "twister");
end

args = {"CompactOutput", true};
if ~isempty(transportBlockBits)
    args = [args {"TransportBlockBits", transportBlockBits}]; %#ok<AGROW>
end
if ~isempty(rv)
    args = [args {"RV", rv}]; %#ok<AGROW>
end
if isstruct(grant) && ~isempty(fieldnames(grant))
    if direction == "UL"
        transformPrecoding = sixgr.util.structGet(grant, "TransformPrecoding", []);
        if ~isempty(transformPrecoding)
            cfg = sixgr.util.structSet(cfg, "phy.pusch.transformPrecoding", logical(transformPrecoding));
        end
    else
        precodingMatrix = sixgr.util.structGet(grant, "PrecodingMatrix", []);
        if ~isempty(precodingMatrix)
            args = [args {"PrecodingMatrix", precodingMatrix}]; %#ok<AGROW>
        end
    end
end

try
    if direction == "UL" && signalType == "PUCCH"
        txArgs = {};
        if isfinite(requestedFormat)
            txArgs = [txArgs {"Format", requestedFormat}]; %#ok<AGROW>
        end
        if isfinite(rnti)
            txArgs = [txArgs {"RNTI", rnti}]; %#ok<AGROW>
        end
        [tx, txInfo] = sixgr.phy.ul.PUCCH_Tx(cfg, uciBits, txArgs{:});
    elseif direction == "UL"
        [tx, txInfo] = sixgr.phy.ul.PUSCH_Tx(cfg, args{:});
    else
        [tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfg, args{:});
    end
    txWave = sixgr.util.structGet(tx, "Waveform", []);
catch
    waveform = [];
    return;
end

if isempty(txWave)
    return;
end

mode = lower(strtrim(string(sixgr.util.structGet(entry, "InterferenceMode", "none"))));
fs = localResolveSampleRate(tx, txInfo);
switch mode
    case "full_per_link_channel_waveform_sum"
        [waveform, channelMeta] = localApplyPerLinkChannelTruth(direction, txWave, cfg, fs, targetSize, seed);
        if isempty(waveform)
            return;
        end
        victimCfg = localBuildVictimLinkConfig(cfg, entry);
        [waveform, ~] = sixgr.link.applyWaveformImpairments(waveform, victimCfg, fs);
        waveform = localMatchWaveformLength(waveform, targetSize(1));
        rxPower_dBm = localResolveWaveformPowerdBm(waveform, samplePowerPerMilliwatt, ...
            double(sixgr.util.structGet(entry, "VictimRxPower_dBm", NaN)));
        entryMeta.PowerSource = "sample_domain_full_per_link_channel_waveform_sum";
        entryMeta.FullPerLinkChannelTruthUsed = true;
        entryMeta.ChannelObjectSource = localSafeCharToken(sixgr.util.structGet(channelMeta, "ChannelObjectSource", ""));
        entryMeta.ChannelObjectClass = localSafeCharToken(sixgr.util.structGet(channelMeta, "ChannelObjectClass", ""));
        entryMeta.ChannelArrayHandlingStatus = localSafeCharToken(sixgr.util.structGet(channelMeta, "ChannelArrayHandlingStatus", ""));
        entryMeta.ChannelArrayHandlingBlocker = localSafeCharToken(sixgr.util.structGet(channelMeta, "ChannelArrayHandlingBlocker", ""));
        entryMeta.ChannelGeometryCouplingLevel = localSafeCharToken(sixgr.util.structGet(channelMeta, "ChannelGeometryCouplingLevel", ""));
        entryMeta.GeometryAdapterType = localSafeCharToken(sixgr.util.structGet(channelMeta, "GeometryAdapterType", ""));
        entryMeta.GeometryAdapterSource = localSafeCharToken(sixgr.util.structGet(channelMeta, "GeometryAdapterSource", ""));
        entryMeta.GeometryAdapterLimitation = localSafeCharToken(sixgr.util.structGet(channelMeta, "GeometryAdapterLimitation", ""));
        entryMeta.GeometryAdapterPortMapping = localSafeCharToken(sixgr.util.structGet(channelMeta, "GeometryAdapterPortMapping", ""));
        entryMeta.ChannelUsesSameRuntimeAntennaAssumptions = logical(sixgr.util.structGet(channelMeta, "ChannelUsesSameRuntimeAntennaAssumptions", false));
    otherwise
        waveform = [];
        return;
end
end

function cfgOut = localApplyPerLinkSeed(cfgIn, seed)
cfgOut = cfgIn;
if ~(isfinite(seed) && seed >= 1)
    return;
end
cfgOut = sixgr.util.structSet(cfgOut, "run.seed", double(max(1, round(seed))));
cfgOut = sixgr.util.structSet(cfgOut, "channel.seed", double(max(1, round(seed))));
end

function cfgOut = localBuildVictimLinkConfig(cfgIn, entry)
cfgOut = cfgIn;
userMeta = sixgr.util.structGet(cfgOut, "lls6g.userContext", struct());
userMeta.RuntimeServingCell = double(sixgr.util.structGet(entry, "ServingCell", NaN));
userMeta.RuntimeServingBeamIndex = double(sixgr.util.structGet(entry, "BeamIndex", NaN));
userMeta.RuntimeServingBeamGain_dB = double(sixgr.util.structGet(entry, "BeamGain_dB", NaN));
userMeta.RuntimeServingRSRP_dBm = double(sixgr.util.structGet(entry, "VictimRSRP_dBm", NaN));
userMeta.RuntimeServingRxPower_dBm = double(sixgr.util.structGet(entry, "VictimRxPower_dBm", NaN));
userMeta.RuntimeServingBasePathloss_dB = double(sixgr.util.structGet(entry, "BasePathloss_dB", NaN));
userMeta.RuntimeServingPathloss_dB = double(sixgr.util.structGet(entry, "Pathloss_dB", NaN));
userMeta.RuntimeServingShadowFading_dB = double(sixgr.util.structGet(entry, "ShadowFading_dB", NaN));
userMeta.RuntimeServingO2I_dB = double(sixgr.util.structGet(entry, "O2I_dB", NaN));
userMeta.RuntimeInterferenceMode = localSafeCharToken(sixgr.util.structGet(entry, "InterferenceMode", ""));
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext", userMeta);
end

function token = localUniqueTokenSet(values)
values = string(values(:));
values = values(~ismissing(values));
values = strip(values);
values = values(strlength(values) > 0);
if isempty(values)
    token = "";
    return;
end
values = unique(values, "stable");
token = join(values, ";");
end

function token = localSafeCharToken(value)
value = string(value);
value = value(~ismissing(value));
if isempty(value)
    token = "";
    return;
end
value = strip(value(1));
if strlength(value) < 1
    token = "";
    return;
end
token = char(value);
end

function [waveform, channelMeta] = localApplyPerLinkChannelTruth(direction, txWave, cfg, sampleRateHz, targetSize, seed)
waveform = [];
channelMeta = struct();
numRx = max(1, round(double(targetSize(2))));
modelRaw = upper(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
if awgnOnly || any(modelRaw == ["AWGN", "NONE", "OFF", ""])
    waveform = localCollapseToVictimRx(txWave, numRx, max(1, round(double(seed))));
    waveform = localMatchWaveformLength(waveform, targetSize(1));
    channelMeta = struct( ...
        "ChannelObjectSource", "sixgr.channel.ChannelFactory.create:awgn_shortcut", ...
        "ChannelObjectClass", "none", ...
        "ChannelArrayHandlingStatus", "no_fading_channel_object", ...
        "ChannelArrayHandlingBlocker", "", ...
        "ChannelGeometryCouplingLevel", "not_applicable_no_fading_channel_object", ...
        "GeometryAdapterType", "", ...
        "GeometryAdapterSource", "", ...
        "GeometryAdapterLimitation", "", ...
        "GeometryAdapterPortMapping", "", ...
        "ChannelUsesSameRuntimeAntennaAssumptions", false);
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

numTx = max(1, size(txWave, 2));
userMeta = sixgr.util.structGet(cfgCh, "lls6g.userContext", struct());
txRuntime = struct();
rxRuntime = struct();
txMeta = struct();
rxMeta = struct();
if upper(string(direction)) == "UL"
    txRuntime = sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct());
    rxRuntime = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
    txMeta = sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct());
    rxMeta = sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct());
else
    txRuntime = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
    rxRuntime = sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct());
    txMeta = sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct());
    rxMeta = sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct());
end
ch = sixgr.channel.ChannelFactory.create(cfgCh, ...
    "Model", cfgCh.channel.model, ...
    "SampleRate", sampleRateHz, ...
    "NumTxAnt", numTx, ...
    "NumRxAnt", numRx, ...
    "Seed", max(1, round(double(seed))), ...
    "TransmitAntennaRuntime", txRuntime, ...
    "ReceiveAntennaRuntime", rxRuntime, ...
    "TransmitAntennaMeta", txMeta, ...
    "ReceiveAntennaMeta", rxMeta);
channelMeta = sixgr.util.structGet(ch, "Meta", struct());

if ~(logical(sixgr.util.structGet(ch, "IsFading", false)) && isfield(ch, "Object") && ~isempty(ch.Object))
    waveform = localCollapseToVictimRx(txWave, numRx, max(1, round(double(seed))));
    waveform = localMatchWaveformLength(waveform, targetSize(1));
    return;
end

chObj = ch.Object;
try
    reset(chObj);
catch
end
padSamples = 0;
trimSamples = 0;
[padSamples, trimSamples] = localResolveChannelDelaySamples(chObj, sampleRateHz);
txIn = txWave;
if padSamples > 0
    txIn = [txWave; zeros(padSamples, size(txWave, 2), "like", txWave)];
end
try
    yRaw = chObj(txIn);
catch
    [yRaw, ~] = chObj(txIn);
end
waveform = localTrimWaveform(yRaw, targetSize(1), trimSamples);
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
    chInfo = struct();
end
if isempty(pathDelays)
    pathDelays = sixgr.util.structGet(chInfo, "PathDelays", []);
end
maxPathDelay = 0;
if ~isempty(pathDelays)
    maxPathDelay = ceil(max(double(pathDelays(:))) * double(fs));
end
padSamples = max(0, round(filterDelay + maxPathDelay + 8));
trimSamples = max(0, round(filterDelay));
end

function waveform = localTrimWaveform(yRaw, targetLen, trimSamples)
if trimSamples > 0 && size(yRaw, 1) >= (trimSamples + targetLen)
    waveform = yRaw(1 + trimSamples:trimSamples + targetLen, :);
else
    waveform = yRaw;
    if size(waveform, 1) > targetLen
        waveform = waveform(1:targetLen, :);
    elseif size(waveform, 1) < targetLen
        waveform(end + 1:targetLen, :) = cast(0, "like", waveform); %#ok<AGROW>
    end
end
end

function waveform = localCollapseToVictimRx(txWave, nRx, seed)
if nargin < 3 || ~(isfinite(seed) && seed >= 1)
    seed = 1;
end
if size(txWave, 2) == nRx
    waveform = txWave;
    return;
end

composite = sum(txWave, 2) ./ sqrt(max(1, size(txWave, 2)));
if nRx <= 1
    waveform = composite;
    return;
end

rs = RandStream("mt19937ar", "Seed", max(1, round(double(seed))));
phases = exp(1i * 2 * pi * rand(rs, 1, nRx));
waveform = composite .* reshape(phases, 1, []);
end

function waveform = localMatchWaveformLength(waveform, targetLen)
targetLen = max(0, round(double(targetLen)));
if isempty(waveform) || targetLen < 1
    waveform = complex(zeros(0, size(waveform, 2)));
    return;
end
if size(waveform, 1) > targetLen
    waveform = waveform(1:targetLen, :);
elseif size(waveform, 1) < targetLen
    waveform(end + 1:targetLen, :) = cast(0, "like", waveform); %#ok<AGROW>
end
end

function power_dBm = localResolveWaveformPowerdBm(waveform, samplePowerPerMilliwatt, fallback_dBm)
power_dBm = double(fallback_dBm);
samplePower = mean(abs(double(waveform(:))).^2, "omitnan");
if ~(isfinite(samplePowerPerMilliwatt) && samplePowerPerMilliwatt > 0 && isfinite(samplePower) && samplePower > 0)
    return;
end
milliwatt = samplePower / samplePowerPerMilliwatt;
if isfinite(milliwatt) && milliwatt > 0
    power_dBm = 10 * log10(milliwatt);
end
end
