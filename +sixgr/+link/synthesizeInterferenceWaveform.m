function [sumWaveform, meta] = synthesizeInterferenceWaveform(direction, desiredWaveform, replay, interferenceBundle)
%SYNTHESIZEINTERFERENCEWAVEFORM Sum shared-slot receiver-side interference.
% Keep this file ASCII-only.
%
% The full truth interference contract is slot-centric:
%   schedule -> build each transmitter waveform once -> propagate each
%   transmitter-to-receiver link with its persistent channel -> sum receiver
%   contributions -> add receiver noise once.
%
% This helper therefore accepts only already-propagated, sample-aligned
% receiver contribution waveforms. It does not rebuild transmitter PHY
% waveforms, reset channels, invent receive phases, or renormalize power
% after the channel.

direction = upper(string(direction));
targetSize = localWaveformTargetSize(desiredWaveform);
sumWaveform = complex(zeros(targetSize(1), targetSize(2), "like", desiredWaveform));
meta = localEmptyMeta(targetSize);

if nargin < 4 || isempty(interferenceBundle) || ~isstruct(interferenceBundle)
    return;
end
if isempty(fieldnames(interferenceBundle))
    return;
end

entries = interferenceBundle(:);
victimPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
victimPowerSource = string(sixgr.util.structGet(replay, "ServingRxPowerSource", ...
    sixgr.util.structGet(replay, "ServingRSRPSource", "")));
samplePowerPerMilliwatt = localResolveSamplePowerPerMilliwatt(desiredWaveform, victimPower_dBm);

contributionTensor = complex(zeros(targetSize(1), targetSize(2), numel(entries), "like", desiredWaveform));
sourceIds = strings(0, 1);
modeTokens = strings(0, 1);
powerSources = strings(0, 1);
powerReferencePlanes = strings(0, 1);
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
aggMilliwatt = 0;
count = 0;

for i = 1:numel(entries)
    entry = entries(i);
    if logical(sixgr.util.structGet(entry, "Muted", false))
        continue;
    end
    [entryResolved, cachePayload] = localResolveCachedInterferenceEntry(entry);
    [contribution, rxPower_dBm, entryMeta] = localResolveSharedSlotContribution( ...
        direction, entry, entryResolved, cachePayload, targetSize, samplePowerPerMilliwatt, replay);

    count = count + 1;
    contribution = cast(contribution, "like", desiredWaveform);
    contributionTensor(:, :, count) = contribution;
    sumWaveform = sumWaveform + contribution;

    if isfinite(rxPower_dBm)
        aggMilliwatt = aggMilliwatt + 10.^(double(rxPower_dBm) / 10);
    end
    modeTokens = localAppendToken(modeTokens, sixgr.util.structGet(entryMeta, "InterferenceMode", "")); %#ok<AGROW>
    powerSources = localAppendToken(powerSources, sixgr.util.structGet(entryMeta, "PowerSource", "")); %#ok<AGROW>
    powerReferencePlanes = localAppendToken(powerReferencePlanes, sixgr.util.structGet(entryMeta, "PowerReferencePlane", "")); %#ok<AGROW>
    sourceIds = localAppendToken(sourceIds, sixgr.util.structGet(entryMeta, "SourceId", "")); %#ok<AGROW>
    channelObjectSources = localAppendToken(channelObjectSources, sixgr.util.structGet(entryMeta, "ChannelObjectSource", "")); %#ok<AGROW>
    channelObjectClasses = localAppendToken(channelObjectClasses, sixgr.util.structGet(entryMeta, "ChannelObjectClass", "")); %#ok<AGROW>
    channelHandlingStatuses = localAppendToken(channelHandlingStatuses, sixgr.util.structGet(entryMeta, "ChannelArrayHandlingStatus", "")); %#ok<AGROW>
    channelHandlingBlockers = localAppendToken(channelHandlingBlockers, sixgr.util.structGet(entryMeta, "ChannelArrayHandlingBlocker", "")); %#ok<AGROW>
    channelGeometryLevels = localAppendToken(channelGeometryLevels, sixgr.util.structGet(entryMeta, "ChannelGeometryCouplingLevel", "")); %#ok<AGROW>
    geometryAdapterTypes = localAppendToken(geometryAdapterTypes, sixgr.util.structGet(entryMeta, "GeometryAdapterType", "")); %#ok<AGROW>
    geometryAdapterSources = localAppendToken(geometryAdapterSources, sixgr.util.structGet(entryMeta, "GeometryAdapterSource", "")); %#ok<AGROW>
    geometryAdapterLimitations = localAppendToken(geometryAdapterLimitations, sixgr.util.structGet(entryMeta, "GeometryAdapterLimitation", "")); %#ok<AGROW>
    geometryAdapterPortMappings = localAppendToken(geometryAdapterPortMappings, sixgr.util.structGet(entryMeta, "GeometryAdapterPortMapping", "")); %#ok<AGROW>
    channelUsesSameRuntime(end + 1, 1) = logical(sixgr.util.structGet(entryMeta, "ChannelUsesSameRuntimeAntennaAssumptions", false)); %#ok<AGROW>
    beamformingCount = beamformingCount + double(logical(sixgr.util.structGet(entryMeta, "BeamformingApplied", false)));
    explicitBeamWeightCount = explicitBeamWeightCount + double(logical(sixgr.util.structGet(entryMeta, "ExplicitBeamWeightsApplied", false)));
    transformPrecodingCount = transformPrecodingCount + double(logical(sixgr.util.structGet(entryMeta, "TransformPrecodingApplied", false)));
    precoderSources = localAppendToken(precoderSources, sixgr.util.structGet(entryMeta, "PrecoderSource", "")); %#ok<AGROW>
    precodingModes = localAppendToken(precodingModes, sixgr.util.structGet(entryMeta, "PrecodingMode", "")); %#ok<AGROW>
    beamIndexSets = localAppendToken(beamIndexSets, sixgr.util.structGet(entryMeta, "BeamIndexSet", "")); %#ok<AGROW>
end

if count < 1
    return;
end

contributionTensor = contributionTensor(:, :, 1:count);
reconstructed = sum(contributionTensor, 3);
identityError = max(abs(double(sumWaveform(:)) - double(reconstructed(:))), [], "omitnan");
if isempty(identityError)
    identityError = 0;
end

meta.InterferenceMode = localSafeCharToken(localUniqueTokenSet(modeTokens));
meta.Contributors = double(count);
meta.AggregatedRxPower_dBm = localAggregatedPowerDbm(aggMilliwatt);
meta.VictimPowerReference_dBm = double(victimPower_dBm);
meta.VictimPowerReferenceSource = localSafeCharToken(victimPowerSource);
meta.PowerSource = localSafeCharToken(localUniqueTokenSet(powerSources));
meta.InterferencePowerReferencePlane = localSafeCharToken(localUniqueTokenSet(powerReferencePlanes));
meta.FullPerLinkChannelTruthUsed = true;
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
meta.ContributionTensor = contributionTensor;
meta.ContributionTensorAvailable = true;
meta.ContributionSourceIdSet = localSafeCharToken(localUniqueTokenSet(sourceIds));
meta.ContributionSampleCount = double(targetSize(1));
meta.ContributionRxPortCount = double(targetSize(2));
meta.SampleExactSuperpositionOk = identityError <= 10 * eps(max(1, max(abs(double(sumWaveform(:))))));
meta.SampleExactSuperpositionError = double(identityError);
meta.InterferenceCovariance = localEstimateSampleCovariance(sumWaveform);
meta.InterferenceCovarianceAvailable = ~isempty(meta.InterferenceCovariance);
meta.InterferenceCovarianceSource = "shared_slot_contribution_sample_covariance";
meta.InterferenceCovarianceStatus = "available_from_shared_slot_contributions";
meta.TxRegenerationUsed = false;
meta.PostChannelNormalizationApplied = false;
meta.RandomPhaseApplied = false;
end

function meta = localEmptyMeta(targetSize)
meta = struct( ...
    "InterferenceMode", "none", ...
    "Contributors", 0, ...
    "AggregatedRxPower_dBm", NaN, ...
    "VictimPowerReference_dBm", NaN, ...
    "VictimPowerReferenceSource", "", ...
    "PowerSource", "", ...
    "InterferencePowerReferencePlane", "", ...
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
    "InterfererBeamIndexSetSummary", "", ...
    "ContributionTensor", complex(zeros(targetSize(1), targetSize(2), 0)), ...
    "ContributionTensorAvailable", false, ...
    "ContributionSourceIdSet", "", ...
    "ContributionSampleCount", double(targetSize(1)), ...
    "ContributionRxPortCount", double(targetSize(2)), ...
    "SampleExactSuperpositionOk", true, ...
    "SampleExactSuperpositionError", 0, ...
    "InterferenceCovariance", [], ...
    "InterferenceCovarianceAvailable", false, ...
    "InterferenceCovarianceSource", "", ...
    "InterferenceCovarianceStatus", "no_interference_contributions", ...
    "TxRegenerationUsed", false, ...
    "PostChannelNormalizationApplied", false, ...
    "RandomPhaseApplied", false);
end

function targetSize = localWaveformTargetSize(waveform)
targetSize = size(waveform);
if isempty(targetSize)
    targetSize = [0 1];
elseif numel(targetSize) < 2
    targetSize(2) = 1;
end
targetSize = [max(0, round(double(targetSize(1)))), max(1, round(double(targetSize(2))))];
end

function samplePowerPerMilliwatt = localResolveSamplePowerPerMilliwatt(desiredWaveform, victimPower_dBm)
samplePowerPerMilliwatt = NaN;
desiredPower = mean(abs(double(desiredWaveform(:))).^2, "omitnan");
if ~(isfinite(victimPower_dBm) && isfinite(desiredPower) && desiredPower > 0)
    return;
end
victimMilliwatt = 10.^(double(victimPower_dBm) / 10);
if isfinite(victimMilliwatt) && victimMilliwatt > 0
    samplePowerPerMilliwatt = desiredPower / victimMilliwatt;
end
end

function [waveform, rxPower_dBm, entryMeta] = localResolveSharedSlotContribution(direction, entry, entryResolved, cachePayload, targetSize, samplePowerPerMilliwatt, replay)
grant = sixgr.util.structGet(entryResolved, "GrantSnapshot", struct());
entryMeta = struct( ...
    "InterferenceMode", localSafeCharToken(sixgr.util.structGet(entry, "InterferenceMode", "full_per_link_channel_waveform_sum")), ...
    "PowerSource", "shared_slot_rx_contribution_samples", ...
    "PowerReferencePlane", localSafeCharToken(sixgr.util.structGet(entryResolved, ...
        "ContributionPowerReferencePlane", sixgr.util.structGet(entry, "ContributionPowerReferencePlane", ""))), ...
    "SourceId", localSourceId(entry, entryResolved), ...
    "ChannelObjectSource", localSafeCharToken(sixgr.util.structGet(entryResolved, "ChannelObjectSource", sixgr.util.structGet(entry, "ChannelObjectSource", ""))), ...
    "ChannelObjectClass", localSafeCharToken(sixgr.util.structGet(entryResolved, "ChannelObjectClass", sixgr.util.structGet(entry, "ChannelObjectClass", ""))), ...
    "ChannelArrayHandlingStatus", localSafeCharToken(sixgr.util.structGet(entryResolved, "ChannelArrayHandlingStatus", sixgr.util.structGet(entry, "ChannelArrayHandlingStatus", ""))), ...
    "ChannelArrayHandlingBlocker", localSafeCharToken(sixgr.util.structGet(entryResolved, "ChannelArrayHandlingBlocker", sixgr.util.structGet(entry, "ChannelArrayHandlingBlocker", ""))), ...
    "ChannelGeometryCouplingLevel", localSafeCharToken(sixgr.util.structGet(entryResolved, "ChannelGeometryCouplingLevel", sixgr.util.structGet(entry, "ChannelGeometryCouplingLevel", ""))), ...
    "GeometryAdapterType", localSafeCharToken(sixgr.util.structGet(entryResolved, "GeometryAdapterType", sixgr.util.structGet(entry, "GeometryAdapterType", ""))), ...
    "GeometryAdapterSource", localSafeCharToken(sixgr.util.structGet(entryResolved, "GeometryAdapterSource", sixgr.util.structGet(entry, "GeometryAdapterSource", ""))), ...
    "GeometryAdapterLimitation", localSafeCharToken(sixgr.util.structGet(entryResolved, "GeometryAdapterLimitation", sixgr.util.structGet(entry, "GeometryAdapterLimitation", ""))), ...
    "GeometryAdapterPortMapping", localSafeCharToken(sixgr.util.structGet(entryResolved, "GeometryAdapterPortMapping", sixgr.util.structGet(entry, "GeometryAdapterPortMapping", ""))), ...
    "ChannelUsesSameRuntimeAntennaAssumptions", logical(sixgr.util.structGet(entryResolved, "ChannelUsesSameRuntimeAntennaAssumptions", sixgr.util.structGet(entry, "ChannelUsesSameRuntimeAntennaAssumptions", false))), ...
    "PrecoderSource", localSafeCharToken(sixgr.util.structGet(grant, "PrecoderSource", "none")), ...
    "PrecodingMode", localSafeCharToken(sixgr.util.structGet(grant, "PrecodingMode", "")), ...
    "BeamIndexSet", localSafeCharToken(sixgr.util.structGet(grant, "AppliedBeamIndexSet", "")), ...
    "BeamformingApplied", logical(sixgr.util.structGet(grant, "BeamformingApplied", false)), ...
    "ExplicitBeamWeightsApplied", logical(sixgr.util.structGet(grant, "ExplicitBeamWeightsApplied", false)), ...
    "TransformPrecodingApplied", logical(sixgr.util.structGet(grant, "TransformPrecodingApplied", false)));

mode = lower(strtrim(string(sixgr.util.structGet(entry, "InterferenceMode", entryMeta.InterferenceMode))));
if mode ~= "full_per_link_channel_waveform_sum" && mode ~= "shared_slot_waveform_superposition"
    error("sixgr:link:UnsupportedInterferenceContributionMode", ...
        "Interference mode '%s' is not a shared-slot waveform truth mode.", char(mode));
end

[waveform, fieldName] = localFirstContributionWaveform(entryResolved, entry, cachePayload);
if isempty(waveform)
    error("sixgr:link:MissingSharedSlotInterferenceContribution", ...
        "Full-truth interference entry '%s' has no receiver-side contribution waveform. Build all slot transmitters and propagate each source before calling synthesizeInterferenceWaveform.", ...
        char(string(entryMeta.SourceId)));
end
waveform = localValidateContributionWaveform(waveform, targetSize, fieldName);
localValidateContributionSampleRate(entryResolved, entry, cachePayload, replay);

rxPower_dBm = localResolveWaveformPowerdBm(waveform, samplePowerPerMilliwatt, ...
    double(sixgr.util.structGet(entryResolved, "ContributionRxPower_dBm", ...
    sixgr.util.structGet(entry, "ContributionRxPower_dBm", NaN))));
if isfinite(rxPower_dBm)
    entryMeta.PowerSource = "shared_slot_rx_contribution_sample_power_calibrated_to_serving_link_budget";
elseif isfinite(double(sixgr.util.structGet(entryResolved, "ContributionRxPower_dBm", sixgr.util.structGet(entry, "ContributionRxPower_dBm", NaN))))
    rxPower_dBm = double(sixgr.util.structGet(entryResolved, "ContributionRxPower_dBm", sixgr.util.structGet(entry, "ContributionRxPower_dBm", NaN)));
    entryMeta.PowerSource = "shared_slot_rx_contribution_declared_power";
end

if strlength(strtrim(string(entryMeta.ChannelObjectSource))) < 1
    entryMeta.ChannelObjectSource = localSafeCharToken(sixgr.util.structGet(cachePayload, "ChannelObjectSource", ""));
end
if strlength(strtrim(string(entryMeta.ChannelObjectClass))) < 1
    entryMeta.ChannelObjectClass = localSafeCharToken(sixgr.util.structGet(cachePayload, "ChannelObjectClass", ""));
end
entryMeta.InterferenceMode = localSafeCharToken(mode);
end

function [waveform, fieldName] = localFirstContributionWaveform(entryResolved, entry, cachePayload)
waveform = [];
fieldName = "";
fields = ["SharedSlotContributionWaveform", "ContributionWaveform", ...
    "RxContributionWaveform", "PrecomputedRxWaveform", "PrecomputedContributionWaveform"];
containers = {entryResolved, entry, cachePayload};
for ci = 1:numel(containers)
    c = containers{ci};
    if ~(isstruct(c) && ~isempty(fieldnames(c)))
        continue;
    end
    for fi = 1:numel(fields)
        f = char(fields(fi));
        if isfield(c, f)
            candidate = c.(f);
            if ~isempty(candidate)
                waveform = candidate;
                fieldName = f;
                return;
            end
        end
    end
end
end

function waveform = localValidateContributionWaveform(waveform, targetSize, fieldName)
if ~isnumeric(waveform)
    error("sixgr:link:BadInterferenceContributionType", ...
        "Shared-slot contribution field '%s' must be a numeric sample matrix.", char(string(fieldName)));
end
if ndims(waveform) > 2
    error("sixgr:link:BadInterferenceContributionRank", ...
        "Shared-slot contribution field '%s' must be Ns-by-Nrx, not a higher-rank array.", char(string(fieldName)));
end
if isvector(waveform)
    waveform = waveform(:);
end
if size(waveform, 1) ~= targetSize(1)
    error("sixgr:link:InterferenceContributionSampleMismatch", ...
        "Shared-slot contribution field '%s' has %d samples but the victim waveform has %d samples. Incompatible slot timing is rejected.", ...
        char(string(fieldName)), size(waveform, 1), targetSize(1));
end
if size(waveform, 2) ~= targetSize(2)
    error("sixgr:link:InterferenceContributionPortMismatch", ...
        "Shared-slot contribution field '%s' has %d receive port(s) but the victim waveform has %d. Receiver phases/ports are not synthesized to hide mismatches.", ...
        char(string(fieldName)), size(waveform, 2), targetSize(2));
end
end

function localValidateContributionSampleRate(entryResolved, entry, cachePayload, replay)
entryFs = localFirstFinite( ...
    sixgr.util.structGet(entryResolved, "ContributionSampleRate_Hz", NaN), ...
    sixgr.util.structGet(entry, "ContributionSampleRate_Hz", NaN), ...
    sixgr.util.structGet(cachePayload, "ContributionSampleRate_Hz", NaN));
replayFs = double(sixgr.util.structGet(replay, "SampleRate_Hz", NaN));
if ~(isfinite(entryFs) && entryFs > 0 && isfinite(replayFs) && replayFs > 0)
    return;
end
tolHz = max(1e-6 * max(abs(entryFs), abs(replayFs)), 1e-3);
if abs(entryFs - replayFs) > tolHz
    error("sixgr:link:InterferenceContributionSampleRateMismatch", ...
        "Shared-slot contribution sample rate %.6f Hz does not match victim sample rate %.6f Hz.", ...
        double(entryFs), double(replayFs));
end
end

function [entryResolved, cachePayload] = localResolveCachedInterferenceEntry(entry)
entryResolved = entry;
cachePayload = struct();
cacheKey = string(sixgr.util.structGet(entry, "CacheKey", ""));
cacheIndex = double(sixgr.util.structGet(entry, "CacheIndex", NaN));
if strlength(strtrim(cacheKey)) < 1 || ~(isfinite(cacheIndex) && cacheIndex >= 1)
    return;
end
[hit, cachePayload] = sixgr.link.interferenceReplayCache("get", char(cacheKey));
if ~hit
    error("sixgr:link:MissingInterferenceReplayCache", ...
        "Interference replay cache key '%s' is not installed on this worker.", char(cacheKey));
end
resolvedGrantCache = sixgr.util.structGet(cachePayload, "ResolvedGrantCache", struct([]));
cacheIndex = round(cacheIndex);
if ~(isstruct(resolvedGrantCache) && cacheIndex >= 1 && cacheIndex <= numel(resolvedGrantCache))
    error("sixgr:link:BadInterferenceReplayCacheIndex", ...
        "Interference replay cache key '%s' has no resolved grant entry at index %d.", char(cacheKey), cacheIndex);
end
resolvedEntry = resolvedGrantCache(cacheIndex);
copyFields = ["Cfg","GrantSnapshot","TransportBlockBits","RV","ExpectedUCIBits", ...
    "ResolvedFormat","RNTI","SignalType","SharedSlotContributionWaveform", ...
    "ContributionWaveform","RxContributionWaveform","PrecomputedRxWaveform", ...
    "PrecomputedContributionWaveform","ContributionSampleRate_Hz","ContributionRxPower_dBm", ...
    "ContributionPowerReferencePlane", ...
    "ChannelObjectSource","ChannelObjectClass","ChannelArrayHandlingStatus", ...
    "ChannelArrayHandlingBlocker","ChannelGeometryCouplingLevel","GeometryAdapterType", ...
    "GeometryAdapterSource","GeometryAdapterLimitation","GeometryAdapterPortMapping", ...
    "ChannelUsesSameRuntimeAntennaAssumptions"];
for i = 1:numel(copyFields)
    fieldName = char(copyFields(i));
    if isfield(resolvedEntry, fieldName)
        entryResolved.(fieldName) = resolvedEntry.(fieldName);
    end
end
end

function sourceId = localSourceId(entry, entryResolved)
sourceId = string(sixgr.util.structGet(entryResolved, "SourceId", sixgr.util.structGet(entry, "SourceId", "")));
if strlength(strtrim(sourceId)) > 0
    sourceId = char(sourceId);
    return;
end
grant = sixgr.util.structGet(entryResolved, "GrantSnapshot", sixgr.util.structGet(entry, "GrantSnapshot", struct()));
ueIdx = double(sixgr.util.structGet(entryResolved, "InterfererUEIndex", sixgr.util.structGet(entry, "InterfererUEIndex", NaN)));
cellIdx = double(sixgr.util.structGet(entryResolved, "ServingCell", sixgr.util.structGet(entry, "ServingCell", NaN)));
frameIdx = double(sixgr.util.structGet(grant, "Frame", sixgr.util.structGet(entry, "Frame", NaN)));
slotIdx = double(sixgr.util.structGet(grant, "Slot", sixgr.util.structGet(entry, "Slot", NaN)));
sourceId = char(sprintf("cell%d_ue%d_f%d_s%d", round(cellIdx), round(ueIdx), round(frameIdx), round(slotIdx)));
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

function R = localEstimateSampleCovariance(waveform)
R = [];
if isempty(waveform)
    return;
end
X = reshape(double(waveform), size(waveform, 1), size(waveform, 2));
if isempty(X) || size(X, 1) < 1
    return;
end
R = (X' * X) ./ double(size(X, 1));
end

function value = localFirstFinite(varargin)
value = NaN;
for i = 1:nargin
    candidate = double(varargin{i});
    if isscalar(candidate) && isfinite(candidate)
        value = candidate;
        return;
    end
end
end

function powerDbm = localAggregatedPowerDbm(milliwatt)
powerDbm = NaN;
if isfinite(milliwatt) && milliwatt > 0
    powerDbm = 10 * log10(milliwatt);
end
end

function values = localAppendToken(values, value)
token = string(value);
token = token(~ismissing(token));
if isempty(token)
    return;
end
token = strtrim(token(1));
if strlength(token) > 0
    values(end + 1, 1) = token;
end
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
