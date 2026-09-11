function result = buildInPathChannelRFResult(cfg, anchor, runtimeTrials, identity)
%BUILDINPATHCHANNELRFRESULT Build Channel/RF evidence from executed DL/UL rows.
%
% The active scenario path must not promote the validator's local QPSK
% waveform into same-scenario evidence.  This adapter consumes only the
% canonical rows produced by the real PDSCH/PUSCH Tx-channel-Rx chain.

arguments
    cfg (1,1) struct
    anchor (1,1) struct
    runtimeTrials (1,1) struct
    identity (1,1) struct
end

trialSets = localRuntimeTrialSets(runtimeTrials);
if isempty(trialSets)
    error("sixgr:channel:MissingInPathRuntimeTrials", ...
        "In-path Channel/RF evidence requires nonempty DL or UL runtime trials.");
end
localValidateIdentity(identity);

[channelT, snapshotT, pathGainT] = localChannelTables(cfg, identity, trialSets);
largeScaleT = localLargeScaleTable(cfg, identity, trialSets);
interferenceT = localInterferenceTable(cfg, identity, trialSets);
noiseT = localNoiseTable(cfg, identity, trialSets);
rfT = localRFTable(cfg, identity, trialSets);
evmT = localEVMTable(identity, trialSets);
downstreamT = localDownstreamTable(identity, trialSets);
[positiveT, positiveOk] = localConfiguredAppliedPositive( ...
    cfg, identity, channelT, largeScaleT, interferenceT, rfT);
[negativeConfiguredT, negativeT, oracleT, negativeOk] = ...
    localExecutedNegativeEvidence(identity);
configuredAppliedT = [positiveT; negativeConfiguredT];

result = anchor;
result.ConfigStrict = localMarkConfigAuthority(anchor.ConfigStrict, identity);
result.Geometry = localMarkGeometryAuthority(anchor.Geometry, identity);
result.LargeScaleParameters = largeScaleT;
result.ChannelRealizations = channelT;
result.ChannelSnapshots = snapshotT;
result.ChannelPathGains = pathGainT;
result.InterferenceTopology = interferenceT;
result.ThermalNoise = noiseT;
result.RFImpairmentChain = rfT;
result.EVMMeasurements = evmT;
result.ConfiguredVsApplied = configuredAppliedT;
result.NegativeTrials = negativeT;
result.OracleGuard = oracleT;
result.DownstreamReferences = downstreamT;
result.SampleEvidence = localSampleEvidence(channelT, pathGainT, rfT);

configOk = logical(sixgr.util.structGet( ...
    sixgr.util.structGet(anchor, "ConfigValidation", struct()), "Ok", false));
actualOk = all(logical(channelT.StrictOk)) && ...
    all(logical(largeScaleT.AppliedOk)) && ...
    all(logical(interferenceT.StrictOk)) && ...
    all(logical(noiseT.StrictOk)) && all(logical(rfT.StrictOk)) && ...
    all(logical(downstreamT.ReferenceValid));
result.StrictOk = logical(configOk && actualOk && positiveOk && negativeOk);
result.Ok = result.StrictOk;
if result.StrictOk
    result.FailureReason = "";
else
    result.FailureReason = localFailureSummary(configOk, actualOk, positiveOk, negativeOk);
end
result.ExecutionID = string(identity.ExecutionID);
result.ScenarioConfigHash = lower(string(identity.ConfigHash));
result.EvidenceScope = "in_path";
result.SameScenarioInPathEligible = true;
result.InPathRuntimeValidationComplete = true;
result.ValidationAuthority = "sixgr.channel.buildInPathChannelRFResult/v1";
result.ValidationComponent = "channel_rf";
result.RuntimeEvidenceSource = "CoupledTruthRuntime.RawTrials";
result.LaunchedSupplementalWaveform = false;
result.SourceTableSHA256 = localRuntimeSourceHash(trialSets);
end

function sets = localRuntimeTrialSets(runtimeTrials)
sets = cell(0, 2);
for name = ["DL","UL"]
    T = sixgr.util.structGet(runtimeTrials, name, table());
    if istable(T) && ~isempty(T)
        sets(end+1, :) = {char(name), T}; %#ok<AGROW>
    end
end
end

function localValidateIdentity(identity)
for name = ["RunID","ExecutionID","ScenarioID","ConfigHash"]
    value = strtrim(string(sixgr.util.structGet(identity, name, "")));
    if ~isscalar(value) || strlength(value) == 0
        error("sixgr:channel:MissingInPathIdentity", ...
            "In-path Channel/RF evidence requires nonempty %s.", name);
    end
end
hash = lower(strtrim(string(identity.ConfigHash)));
if strlength(hash) ~= 64 || isempty(regexp(char(hash), '^[0-9a-f]{64}$', 'once'))
    error("sixgr:channel:MissingInPathIdentity", ...
        "In-path Channel/RF ConfigHash must be a SHA-256 digest.");
end
end

function [realizationT, snapshotT, pathGainT] = localChannelTables(cfg, identity, sets)
realRows = repmat(localChannelRow(), 0, 1);
snapRows = repmat(localSnapshotRow(), 0, 1);
gainRows = repmat(localPathGainRow(), 0, 1);
configuredModel = localConcreteConfiguredModel(cfg);
for si = 1:size(sets, 1)
    direction = string(sets{si, 1});
    T = sets{si, 2};
    for ii = 1:height(T)
        if localHasChannelArtifactClaim(T,ii)
            [r,s,g]=localVerifiedChannelRows(cfg,identity,direction,T(ii,:));
            realRows(end+1,1)=r; %#ok<AGROW>
            snapRows=[snapRows;s]; gainRows=[gainRows;g]; %#ok<AGROW>
            continue;
        end
        localRequireColumns(T, ["ChannelRealizationId","RuntimeChannelLinkKey", ...
        "RuntimeChannelStartSample","RuntimeChannelEndSample", ...
        "RuntimeChannelInputWaveformSHA256","RuntimeChannelOutputWaveformSHA256", ...
        "RuntimeChannelPathGainsSHA256","RuntimeChannelPathGainElementCount", ...
        "RuntimeChannelPathGainDimensions","ChannelModelApplied", ...
        "ChannelFadingApplied","ChannelFadingObjectClass"], direction + " Channel/RF");
        trialId = localTrialId(direction, T, ii);
        rid = strtrim(string(T.ChannelRealizationId(ii)));
        inputHash = lower(strtrim(string(T.RuntimeChannelInputWaveformSHA256(ii))));
        outputHash = lower(strtrim(string(T.RuntimeChannelOutputWaveformSHA256(ii))));
        pathHash = lower(strtrim(string(T.RuntimeChannelPathGainsSHA256(ii))));
        appliedModel = upper(strtrim(string(T.ChannelModelApplied(ii))));
        if strlength(appliedModel) == 0
            appliedModel = upper(strtrim(string(localValue(T, "ChannelModel", ii, ""))));
        end
        fading = logical(localValue(T, "ChannelFadingApplied", ii, false));
        modelMatch = appliedModel == configuredModel;
        hashesOk = localIsHash(inputHash) && localIsHash(outputHash);
        if configuredModel == "AWGN"
            pathOk = ~fading;
            waveChanged = false;
        else
            pathOk = fading && localIsHash(pathHash) && ...
                double(T.RuntimeChannelPathGainElementCount(ii)) > 0;
            waveChanged = inputHash ~= outputHash;
        end
        ok = strlength(rid) > 0 && modelMatch && hashesOk && pathOk && ...
            double(T.RuntimeChannelEndSample(ii)) > double(T.RuntimeChannelStartSample(ii));
        row = localChannelRow();
        row.RunId = string(identity.RunID);
        row.ScenarioName = string(identity.ScenarioID);
        row.TrialId = trialId;
        row.ChannelRealizationId = rid;
        row.ChannelModelType = localChannelFamily(configuredModel);
        row.AppliedChannelModelType = appliedModel;
        row.DelayProfile = configuredModel;
        row.NumTxAntennas = double(localValue(T, "PhysicalTxAntennas", ii, ...
            localValue(T, "NumTxPorts", ii, NaN)));
        row.NumRxAntennas = double(localValue(T, "PhysicalRxAntennas", ii, ...
            localValue(T, "NumRxAntennas", ii, NaN)));
        row.MaxDopplerHz = double(localValue(T, "DopplerHz", ii, NaN));
        row.DelaySpreadSec = double(sixgr.util.structGet(cfg, "channel.fading.delaySpread_s", NaN));
        row.WaveformBeforeHash = inputHash;
        row.WaveformAfterHash = outputHash;
        row.PathGainsHash = pathHash;
        row.ChannelSnapshotHash = "";
        row.WaveformChanged = waveChanged;
        row.PathGainsExported = false;
        row.ChannelSnapshotExported = false;
        row.ChannelMatrixRows = NaN;
        row.ChannelMatrixColumns = NaN;
        row.ChannelEvidenceKind = "producer_reported_hashes_not_verified_tensor_artifacts";
        row.WaveformHashScope = "reported_processor_interval";
        row.StrictOk = ok;
        row.TruthStatus = "real_lls_evidence";
        row.FailureReason = localReason(ok, "", "runtime_channel_identity_or_hash_mismatch");
        row = localBindRow(row, identity, "in_path", true);
        [sampleRateHz, sampleRateSource] = localResolveRuntimeSampleRateHz(cfg, T, ii);
        startSample = double(T.RuntimeChannelStartSample(ii));
        if ~(isscalar(startSample) && isfinite(startSample) && startSample >= 0)
            error("sixgr:channel:InvalidRuntimeChannelSampleOffset", ...
                "RuntimeChannelStartSample must be a finite nonnegative scalar for %s.", ...
                trialId);
        end
        row.SampleTimeSec = startSample / sampleRateHz;
        row.SampleRateHz = sampleRateHz;
        row.SampleRateSource = sampleRateSource;
        realRows(end+1, 1) = row; %#ok<AGROW>

        gain = localPathGainRow();
        gain.RunId = string(identity.RunID);
        gain.TrialId = trialId;
        gain.ChannelRealizationId = rid;
        gain.PathGainHash = pathHash;
        gain.SampleTimeHash = "";
        gain.EvidenceKind = "producer_reported_path_gain_hash_only";
        gain.PathGainElementCount = double(T.RuntimeChannelPathGainElementCount(ii));
        % A waveform interval does not reveal how many fading snapshots
        % or sample times were actually retained (they may be decimated).
        gain.SampleTimeCount = NaN;
        gain.PathGainDimensions = string(T.RuntimeChannelPathGainDimensions(ii));
        gain.TruthStatus = "real_lls_evidence";
        gain = localBindRow(gain, identity, "in_path", true);
        gainRows(end+1, 1) = gain; %#ok<AGROW>
    end
end
realizationT = struct2table(realRows, "AsArray", true);
snapshotT = struct2table(snapRows, "AsArray", true);
pathGainT = struct2table(gainRows, "AsArray", true);
end

function tf=localHasChannelArtifactClaim(T,k)
tf=false;
for name=["ChannelObservationID","ChannelObservationManifestJSON","ChannelObservationSource", ...
        "ChannelObservationManifestSHA256","ChannelObservationMATFile", ...
        "ChannelObservationMATFileSHA256","ChannelObservationSegmentsCSV", ...
        "ChannelObservationSegmentsCSVSHA256"]
    value=localValue(T,name,k,"");
    if isnumeric(value) && isscalar(value) && isnan(value), continue; end
    value=string(value);
    tf=tf || (~ismissing(value) && strlength(strtrim(value))>0);
end
count=double(localValue(T,"ChannelObservationSegmentCount",k,NaN));
tf=tf || (isfinite(count) && count>0);
end

function [row,snaps,gains]=localVerifiedChannelRows(cfg,identity,direction,T)
v=sixgr.channel.validateSharedChannelObservationArtifact( ...
    sixgr.util.structGet(cfg,'run.rootRunFolder',""),T);
m=v.Manifest; segments=m.Segments; configured=localConcreteConfiguredModel(cfg);
row=localChannelRow(); row.RunId=string(identity.RunID); row.ScenarioName=string(identity.ScenarioID);
row.TrialId=localTrialId(direction,T,1); row.ChannelRealizationId=string(T.ChannelObservationID);
row.ChannelEvidenceKind="verified_ordered_path_gain_snapshots_not_resource_grid_H";
row.ChannelModelType=localChannelFamily(configured); row.DelayProfile=configured;
models=unique(string({segments.ChannelModelApplied}));
assert(isscalar(models),'sixgr:channel:ChannelProfileChangedWithinObservation','Do not flatten differing applied channel profiles.');
row.AppliedChannelModelType=models;
nt=unique([segments.NumTransmitAntennas]); nr=unique([segments.NumReceiveAntennas]);
assert(isscalar(nt) && isscalar(nr),'sixgr:channel:ChannelArrayChangedWithinObservation','One receiver observation must retain its physical array layout.');
row.NumTxAntennas=nt; row.NumRxAntennas=nr;
row.WaveformChanged=any(string({segments.RuntimeChannelInputWaveformSHA256})~=string({segments.RuntimeChannelOutputWaveformSHA256}));
row.WaveformHashScope="see_original_hashes_per_executed_segment";
row.PathGainsExported=true; row.ChannelSnapshotExported=true;
row.SnapshotManifestSHA256=string(T.ChannelObservationManifestSHA256);
row.CoefficientMATFile=string(T.ChannelObservationMATFile);
row.CoefficientMATFileSHA256=string(T.ChannelObservationMATFileSHA256);
row.SampleTimeSec=m.ObservationStartSample/m.SampleRateHz;
row.SampleRateHz=m.SampleRateHz; row.SampleRateSource="validated_shared_channel_observation";
row.StrictOk=models==configured; row.TruthStatus="real_lls_evidence";
row.FailureReason=localReason(row.StrictOk,"","runtime_channel_profile_mismatch");
row=localBindRow(row,identity,"in_path",true);
snaps=repmat(localSnapshotRow(),0,1); gains=repmat(localPathGainRow(),0,1);
for k=1:numel(segments)
    s=segments(k);
    snap=localSnapshotRow(); snap.RunId=string(identity.RunID); snap.TrialId=row.TrialId;
    snap.ChannelRealizationId=row.ChannelRealizationId; snap.SnapshotIndex=k;
    snap.SampleTimeSec=s.StartSample/m.SampleRateHz; snap.SampleRateHz=m.SampleRateHz;
    snap.SampleRateSource=row.SampleRateSource;
    snap.ChannelSnapshotHash=string(s.PathGainsSHA256);
    snap.SnapshotRepresentation="sample_indexed_path_gain_tensor_not_resource_grid_H";
    snap.PathFiltersHash=string(s.PathFiltersSHA256); snap.SampleTimeHash=string(s.SampleTimesSHA256);
    snap.StartSample=s.StartSample; snap.EndSampleExclusive=s.EndSampleExclusive;
    snap.CoefficientMATFile=row.CoefficientMATFile; snap.CoefficientMATFileSHA256=row.CoefficientMATFileSHA256;
    snap.TruthStatus="real_lls_evidence";
    snaps(end+1,1)=localBindRow(snap,identity,"in_path",true); %#ok<AGROW>
    gain=localPathGainRow(); gain.RunId=string(identity.RunID); gain.TrialId=row.TrialId;
    gain.ChannelRealizationId=row.ChannelRealizationId; gain.PathGainHash=string(s.PathGainsSHA256);
    gain.SampleTimeHash=string(s.SampleTimesSHA256); gain.PathGainElementCount=s.PathGainElementCount;
    gain.SampleTimeCount=s.SampleTimeCount; gain.PathGainDimensions=string(s.PathGainDimensions);
    gain.EvidenceKind="verified_persisted_path_gain_tensor"; gain.SegmentIndex=k;
    gain.CoefficientMATFile=row.CoefficientMATFile; gain.CoefficientMATFileSHA256=row.CoefficientMATFileSHA256;
    gain.TruthStatus="real_lls_evidence";
    gains(end+1,1)=localBindRow(gain,identity,"in_path",true); %#ok<AGROW>
end
end

function T = localLargeScaleTable(cfg, identity, sets)
rows = repmat(localLargeScaleRow(), 0, 1);
pathConfigured = logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", false));
shadowConfigured = pathConfigured && logical(sixgr.util.structGet(cfg, "channel.shadowFadingEnabled", false));
o2iConfigured = pathConfigured && logical(sixgr.util.structGet(cfg, "channel.o2i.enabled", false));
for si = 1:size(sets, 1)
    direction = string(sets{si, 1}); T = sets{si, 2};
    for ii = 1:height(T)
        row = localLargeScaleRow();
        row.RunId = string(identity.RunID); row.ScenarioName = string(identity.ScenarioID);
        row.LinkId = direction + ":" + string(localValue(T, "RuntimeChannelLinkKey", ii, localTrialId(direction,T,ii)));
        row.ChannelRealizationId = string(localValue(T, "ChannelRealizationId", ii, ""));
        if localHasChannelArtifactClaim(T,ii), row.ChannelRealizationId=string(T.ChannelObservationID(ii)); end
        row.PathlossModel = string(localValue(T, "PathlossModelSource", ii, ...
            sixgr.util.structGet(cfg, "channel.pathlossModel", "")));
        row.Distance3Dm = double(localValue(T, "RuntimeGeometryDistance3D_m", ii, NaN));
        row.Distance2Dm = double(localValue(T, "RuntimeGeometryDistance2D_m", ii, NaN));
        row.GeometrySource=string(localValue(T,"RuntimeGeometrySource",ii,"unavailable_executed_link_geometry"));
        row.PathlossDbConfigured = double(localValue(T, "AppliedPathloss_dB", ii, NaN));
        row.PathlossDbApplied = row.PathlossDbConfigured;
        row.ShadowFadingStdDb = double(sixgr.util.structGet(cfg, "channel.shadowFadingStd_dB", NaN));
        row.ShadowFadingDbApplied = double(localValue(T, "AppliedShadowFading_dB", ii, NaN));
        row.O2IModelSource = string(localValue(T, "O2IModelSource", ii, ""));
        row.O2IPenetrationLossDbApplied = double(localValue(T, "AppliedO2I_dB", ii, NaN));
        row.TotalLargeScaleLossDbApplied = double(localValue(T, "AppliedLargeScaleLoss_dB", ii, NaN));
        % Net executed gain includes endpoint gains/additional loss, not
        % pathloss alone. Compare two independently captured sample energies
        % with the expected output energy over the SAME execution segments.
        before=double(localValue(T,"LargeScaleInputEnergy_mWsample",ii,NaN));
        after=double(localValue(T,"LargeScaleOutputEnergy_mWsample",ii,NaN));
        expected=double(localValue(T,"LargeScaleExpectedOutputEnergy_mWsample",ii,NaN));
        count=double(localValue(T,"LargeScaleSampleElementCount",ii,NaN));
        tolerance=double(localValue(T,"LargeScalePowerClosureRelativeTolerance",ii,NaN));
        row.PowerMeasurementSource=string(localValue(T,"LargeScaleMeasurementSource",ii,""));
        row.PowerMeasurementStartSample=double(localValue(T,"LargeScaleMeasurementStartSample",ii,NaN));
        row.PowerMeasurementEndSampleExclusive=double(localValue(T,"LargeScaleMeasurementEndSampleExclusive",ii,NaN));
        captureStart=double(localValue(T,"RuntimeChannelStartSample",ii,NaN));
        captureEnd=double(localValue(T,"RuntimeChannelEndSample",ii,NaN));
        scopeOk=all(isfinite([row.PowerMeasurementStartSample row.PowerMeasurementEndSampleExclusive ...
            captureStart captureEnd])) && captureEnd>captureStart && ...
            row.PowerMeasurementStartSample<=captureStart && row.PowerMeasurementEndSampleExclusive>=captureEnd;
        energyAvailable=all(isfinite([before after expected count tolerance])) && ...
            all([before after expected count]>0) && tolerance>0 && tolerance<1 && ...
            count==fix(count) && scopeOk && strlength(strtrim(row.PowerMeasurementSource))>0;
        powerClosure=false;
        if energyAvailable
            row.WaveformPowerBeforeDb=10*(log10(before)-log10(count));
            row.WaveformPowerAfterDb=10*(log10(after)-log10(count));
            row.ExpectedDeltaDb=10*(log10(before)-log10(expected));
            row.MeasuredDeltaDb=10*(log10(before)-log10(after));
            row.ToleranceDb=-10/log(10)*log1p(-tolerance);
            powerClosure=abs(after-expected)<=tolerance*expected;
        end
        row.PowerMeasurementAvailable=energyAvailable;
        row.PowerClosureOk=powerClosure;
        row.PathlossConfigured = pathConfigured;
        row.PathlossApplied = pathConfigured && isfinite(row.PathlossDbApplied);
        row.ShadowFadingConfigured = shadowConfigured;
        row.ShadowFadingApplied = shadowConfigured && isfinite(row.ShadowFadingDbApplied);
        row.O2IConfigured = o2iConfigured;
        row.O2IApplied = o2iConfigured && isfinite(row.O2IPenetrationLossDbApplied);
        row.AppliedOk = row.PathlossConfigured == row.PathlossApplied && ...
            row.ShadowFadingConfigured == row.ShadowFadingApplied && ...
            row.O2IConfigured == row.O2IApplied && isfinite(row.TotalLargeScaleLossDbApplied) && powerClosure;
        row.TruthStatus = "real_lls_evidence";
        row.FailureReason = localReason(row.AppliedOk, "", "runtime_large_scale_configured_applied_mismatch");
        if ~energyAvailable
            row.FailureReason="runtime_large_scale_independent_energy_missing";
        elseif ~powerClosure
            row.FailureReason="runtime_large_scale_measured_power_mismatch";
        end
        row = localBindRow(row, identity, "in_path", true);
        rows(end+1,1) = row; %#ok<AGROW>
    end
end
T = struct2table(rows, "AsArray", true);
end

function T = localInterferenceTable(cfg, identity, sets)
rows = repmat(localInterferenceRow(), 0, 1);
configured = localInterferenceConfigured(cfg);
for si = 1:size(sets,1)
    direction = string(sets{si,1}); T0 = sets{si,2};
    for ii = 1:height(T0)
        row = localInterferenceRow();
        row.RunId = string(identity.RunID); row.ScenarioName = string(identity.ScenarioID);
        row.InterferenceModelId = string(localValue(T0,"InterferenceMode",ii,"none"));
        row.Direction = lower(direction);
        row.ResourceOverlap = "same_slot_sample_domain";
        row.ReceivedInterferencePower = double(localValue(T0,"InterferenceAggregatedRxPower_dBm",ii,NaN));
        row.SignalPower = double(localValue(T0,"DesiredSignalPowerBeforeNoise",ii,NaN));
        row.NoisePower = double(localValue(T0,"ReplaySampleNoiseVariance",ii,NaN));
        row.ComputedSINRDb = double(localValue(T0,"MeasuredTrialSINR_dB",ii,NaN));
        row.InterferenceConfigured = configured;
        row.InterferenceContributorCount = double(localValue(T0,"InterferenceContributorCount",ii,0));
        row.InterferencePowerSource = string(localValue(T0,"InterferencePowerSource",ii,""));
        row.InterferenceApplied = row.InterferenceContributorCount > 0;
        % A configured multi-user mode may legitimately have zero peers in
        % a particular slot.  The row is valid when the runtime reports
        % the exact contributor count and source instead of inventing one.
        row.StrictOk = ~row.InterferenceApplied || ...
            strlength(strtrim(row.InterferencePowerSource)) > 0;
        row.TruthStatus = "real_lls_evidence";
        row.FailureReason = localReason(row.StrictOk,"","runtime_interference_source_missing");
        row = localBindRow(row, identity, "in_path", true);
        rows(end+1,1) = row; %#ok<AGROW>
    end
end
T = struct2table(rows,"AsArray",true);
end

function configured = localInterferenceConfigured(cfg)
% Interference authority is distributed across the canonical YAML section
% and its normalized execution-mode fields. Do not infer it from observed
% contributors: runtime behavior cannot override scenario configuration.
flagPaths = [ ...
    "channel_rf.interferenceEnabled"
    "interference.inter_cell_interference_flag"
    "interference.intra_cell_interference_flag"
    "interference.mu_mimo_interference_flag"
    "interference.interCellEnabled"
    "interference.intraCellEnabled"
    "channel.interference.interCellEnabled"
    "channel.interference.intraCellEnabled"];
configured = false;
for path = flagPaths.'
    configured = configured || logical(sixgr.util.structGet(cfg, path, false));
end
modePaths = [ ...
    "run.interferenceExecutionMode"
    "run.intraCellInterferenceExecutionMode"
    "interference.inter_cell_execution_mode"
    "interference.intra_cell_execution_mode"
    "channel.phase10_strict.interference.execution"];
for path = modePaths.'
    mode = lower(strtrim(string(sixgr.util.structGet(cfg, path, "none"))));
    configured = configured || ~ismember(mode, ["","none","off","disabled"]);
end
end

function hash = localRuntimeSourceHash(sets)
payload = repmat(struct("Direction", "", "TableSHA256", ""), size(sets,1), 1);
for ii = 1:size(sets,1)
    payload(ii).Direction = char(string(sets{ii,1}));
    payload(ii).TableSHA256 = char(sixgr.kpi.hashKPISourceRows(sets{ii,2}));
end
hash = string(sixgr.channel.hashChannelRFConfig(payload));
end

function T = localNoiseTable(~, identity, sets)
rows = repmat(localNoiseRow(), 0, 1);
for si = 1:size(sets,1)
    direction = string(sets{si,1}); T0 = sets{si,2};
    for ii = 1:height(T0)
        row = localNoiseRow();
        row.RunId = string(identity.RunID); row.ScenarioName = string(identity.ScenarioID);
        row.TrialId = localTrialId(direction,T0,ii);
        row.BandwidthHz = double(localValue(T0,"NoiseBandwidth_Hz",ii,NaN));
        row.NoiseFigureDb = double(localValue(T0,"NoiseFigure_dB",ii,NaN));
        row.NoiseOperatingMode = string(localValue(T0,"NoiseOperatingMode",ii, ...
            localValue(T0,"AppliedNoiseSNRSource",ii,"configured_snr")));
        row.ThermalNoiseVarianceConfigured = double(localValue(T0,"ThermalNoisePower_dBm",ii,NaN));
        row.ThermalNoiseVarianceApplied = double(localValue(T0,"ReplaySampleNoiseVariance",ii,NaN));
        row.ThermalNoiseApplied = contains(lower(row.NoiseOperatingMode),"thermal");
        row.InjectedNoiseVariance = row.ThermalNoiseVarianceApplied;
        row.Status = "applied_from_runtime_replay";
        row.StrictOk = isfinite(row.InjectedNoiseVariance) && row.InjectedNoiseVariance > 0 && ...
            strlength(strtrim(string(localValue(T0,"NoiseVarianceSource",ii,"")))) > 0;
        row.TruthStatus = "real_lls_evidence";
        row.FailureReason = localReason(row.StrictOk,"","runtime_noise_variance_or_source_missing");
        row = localBindRow(row,identity,"in_path",true);
        rows(end+1,1) = row; %#ok<AGROW>
    end
end
T = struct2table(rows,"AsArray",true);
end

function T = localRFTable(cfg, identity, sets)
rows = repmat(localRFRow(), 0, 1);
    configured = localRFConfigured(cfg);
for si = 1:size(sets,1)
    direction = string(sets{si,1}); T0 = sets{si,2};
    localRequireColumns(T0,["RFImpairmentChainId","RxRFImpairmentChainId", ...
        "RxRFInputWaveformSHA256","RxRFOutputWaveformSHA256","RFStrictOk"], ...
        direction + " RF");
    for ii = 1:height(T0)
        row = localRFRow();
        row.RunId = string(identity.RunID); row.TrialId = localTrialId(direction,T0,ii);
        row.RFImpairmentChainId = string(T0.RFImpairmentChainId(ii));
        row.Direction = lower(direction); row.TxOrRxSide = "executed_tx_rx_path";
        row.Endpoint = "txrx";
        row.StageOrder = strjoin([strtrim(string(localValue(T0,"TxRFStageOrder",ii,""))), ...
            strtrim(string(localValue(T0,"RxRFStageOrder",ii,"")))],">");
        row.CFOEnabled = logical(localValue(T0,"CFOApplied",ii,false));
        row.CFOHzConfigured = double(localValue(T0,"InjectedCFO_Hz",ii,0));
        row.CFOHzApplied = row.CFOHzConfigured;
        row.PhaseNoiseEnabled = logical(localValue(T0,"PhaseNoiseConfigured",ii,false));
        row.PhaseNoiseApplied = logical(localValue(T0,"PhaseNoiseApplied",ii,false));
        row.IQImbalanceEnabled = logical(localValue(T0,"IQImbalanceConfigured",ii,false));
        row.AmplitudeImbalanceDb = double(localValue(T0,"ConfiguredIQGainImbalance_dB",ii,0));
        row.PhaseImbalanceDeg = double(localValue(T0,"ConfiguredIQPhaseImbalance_deg",ii,0));
        row.PAEnabled = logical(localValue(T0,"PAEnabled",ii,false));
        row.PAModel = string(localValue(T0,"PAModel",ii,""));
        row.BackoffDb = double(localValue(T0,"PABackoff_dB",ii,NaN));
        row.TimingOffsetEnabled = logical(localValue(T0,"TimingOffsetApplied",ii,false));
        row.TimingOffsetSamplesConfigured = double(localValue(T0,"InjectedTimingOffset_samples",ii,0));
        row.TimingOffsetSamplesApplied = row.TimingOffsetSamplesConfigured;
        row.QuantizationEnabled = logical(localValue(T0,"ADCQuantizationApplied",ii,false));
        row.ADCBits = double(localValue(T0,"ADCBits",ii,NaN));
        row.DACBits = double(localValue(T0,"DACBits",ii,NaN));
        row.WaveformBeforeHash = lower(string(T0.RxRFInputWaveformSHA256(ii)));
        row.WaveformAfterHash = lower(string(T0.RxRFOutputWaveformSHA256(ii)));
        row.WaveformChanged = row.WaveformBeforeHash ~= row.WaveformAfterHash;
        row.EVMMeasuredPercent = 100 * double(localValue(T0,"EVM_rms",ii,NaN));
        row.EVMMeasuredDb = 20*log10(max(double(localValue(T0,"EVM_rms",ii,NaN)),realmin));
        row.RFConfigured = configured || ...
            double(localValue(T0,"TxRFConfiguredStageCount",ii,0)) > 0 || ...
            double(localValue(T0,"RxRFConfiguredStageCount",ii,0)) > 0;
        manifest=string(localValue(T0,"RFExecutionManifestJSON",ii,""));
        retainedClaim=strlength(strtrim(manifest))>0 || ...
            strlength(string(localValue(T0,"RFExecutionEvidenceSource",ii,"")))>0 || ...
            isfinite(double(localValue(T0,"TxRFExecutedStageCount",ii,NaN))) || ...
            isfinite(double(localValue(T0,"RxRFExecutedStageCount",ii,NaN)));
        executionOk=true;
        if retainedClaim
            rfEvidence=sixgr.channel.validateSharedRFExecutionEvidence(T0(ii,:));
            executionOk=rfEvidence.Ok;
            row.RFExecuted=rfEvidence.AnyStageExecuted;
            row.RFExecutionEvidenceSource=rfEvidence.Source;
            row.TXSegmentWaveformChanged=rfEvidence.AnyTXSegmentWaveformChanged;
            row.RXSegmentWaveformChanged=rfEvidence.AnyRXSegmentWaveformChanged;
            row.RFExecutionManifestSHA256=string(localValue(T0,"RFExecutionManifestSHA256",ii,""));
        else
            % Preserve legacy strict/mutation evidence until those producer
            % rows carry independently verifiable retained execution records.
            row.RFExecuted=row.WaveformChanged;
            row.RFExecutionEvidenceSource="legacy_strict_RX_mutation_evidence_not_retained_execution";
        end
        row.StrictOk = logical(T0.RFStrictOk(ii)) && localIsHash(row.WaveformBeforeHash) && ...
            localIsHash(row.WaveformAfterHash) && strlength(row.RFImpairmentChainId) > 0 && executionOk;
        row.TruthStatus = "real_lls_evidence";
        row.FailureReason = localReason(row.StrictOk,"","runtime_rf_chain_identity_or_hash_missing");
        if ~executionOk, row.FailureReason=rfEvidence.FailureReason; end
        row = localBindRow(row,identity,"in_path",true);
        rows(end+1,1) = row; %#ok<AGROW>
    end
end
T = struct2table(rows,"AsArray",true);
end

function T = localEVMTable(identity, sets)
rows = repmat(localEVMRow(),0,1);
for si=1:size(sets,1)
    direction=string(sets{si,1}); T0=sets{si,2};
    for ii=1:height(T0)
        row=localEVMRow(); row.RunId=string(identity.RunID);
        row.TrialId=localTrialId(direction,T0,ii);
        row.RFImpairmentChainId=string(localValue(T0,"RFImpairmentChainId",ii,""));
        row.Direction=lower(direction); row.MeasurementPoint="decoded_data_symbols";
        row.EVMPercent=100*double(localValue(T0,"EVM_rms",ii,NaN));
        row.EVMDb=20*log10(max(double(localValue(T0,"EVM_rms",ii,NaN)),realmin));
        row.CFOHzEstimated=double(localValue(T0,"EstimatedCFO_Hz",ii,NaN));
        row.Status="receiver_measured_data_symbol_evm";
        row.FailureReason=localReason(isfinite(row.EVMPercent),"","receiver_evm_missing");
        row=localBindRow(row,identity,"in_path",true); rows(end+1,1)=row; %#ok<AGROW>
    end
end
T=struct2table(rows,"AsArray",true);
end

function T = localDownstreamTable(identity, sets)
rows=repmat(localDownstreamRow(),0,1);
for si=1:size(sets,1)
    direction=string(sets{si,1}); T0=sets{si,2};
    for ii=1:height(T0)
        row=localDownstreamRow(); row.RunId=string(identity.RunID); row.ScenarioName=string(identity.ScenarioID);
        row.Direction=lower(direction); row.TrialTable=lower(direction)+"_runtime_trials";
        row.TrialId=localTrialId(direction,T0,ii);
        row.CellId=double(localValue(T0,"BaseStationID",ii,NaN));
        row.UEId=double(localValue(T0,"UEIndex",ii,NaN));
        row.ChannelRealizationId=string(localValue(T0,"ChannelRealizationId",ii,""));
        if localHasChannelArtifactClaim(T0,ii), row.ChannelRealizationId=string(T0.ChannelObservationID(ii)); end
        row.RFImpairmentChainId=string(localValue(T0,"RFImpairmentChainId",ii,""));
        row.ReferenceValid=strlength(row.ChannelRealizationId)>0 && strlength(row.RFImpairmentChainId)>0;
        row.Status=localReason(row.ReferenceValid,"runtime_waveform_reference_available","runtime_reference_missing");
        row.FailureReason=localReason(row.ReferenceValid,"","runtime_reference_missing");
        row=localBindRow(row,identity,"in_path",true); rows(end+1,1)=row; %#ok<AGROW>
    end
end
T=struct2table(rows,"AsArray",true);
end

function [T, ok] = localConfiguredAppliedPositive(cfg, identity, channelT, largeT, intT, rfT)
rows=repmat(localConfiguredRow(),0,1);
rows(end+1,1)=localConfiguredPositive(identity,"runtime_channel_model","channel", ...
    localConcreteConfiguredModel(cfg),string(channelT.AppliedChannelModelType(1)), ...
    all(logical(channelT.StrictOk))); %#ok<AGROW>
rows(end+1,1)=localConfiguredPositive(identity,"runtime_large_scale","large_scale", ...
    localOnOff(any(logical(largeT.PathlossConfigured))), ...
    localOnOff(any(logical(largeT.PathlossApplied))),all(logical(largeT.AppliedOk))); %#ok<AGROW>
rows(end+1,1)=localConfiguredPositive(identity,"runtime_interference","interference", ...
    localOnOff(any(logical(intT.InterferenceConfigured))), ...
    localOnOff(any(logical(intT.InterferenceApplied))),all(logical(intT.StrictOk))); %#ok<AGROW>
rows(end+1,1)=localConfiguredPositive(identity,"runtime_rf_chain","rf_impairment_chain", ...
    localOnOff(any(logical(rfT.RFConfigured))), ...
    localOnOff(any(logical(rfT.RFExecuted))),all(logical(rfT.StrictOk))); %#ok<AGROW>
T=struct2table(rows,"AsArray",true);
ok=all(logical(T.StrictOk)) && all(logical(T.ConfiguredAppliedMatch));
end

function row=localConfiguredPositive(identity,trialId,feature,configured,applied,executionOk)
row=localConfiguredRow(); row.RunId=string(identity.RunID); row.TrialId=trialId; row.Feature=feature;
row.ConfiguredChannelModelType=string(configured); row.AppliedChannelModelType=string(applied);
row.ConfiguredAppliedMatch=string(configured)==string(applied);
row.FeatureConfigured=string(configured)~="disabled"; row.FeatureApplied=string(applied)~="disabled";
row.ExpectedOk=true; row.StrictOk=logical(executionOk && row.ConfiguredAppliedMatch);
row.TruthStatus="real_lls_evidence";
row.FailureReason=localReason(row.StrictOk,"","runtime_configured_applied_mismatch");
row=localBindRow(row,identity,"in_path",true);
end

function [configuredT, negativeT, oracleT, ok] = localExecutedNegativeEvidence(identity)
specs = [
    "negative_channel_model_substitution","channel","CDL-C","AWGN","sixgr:channel:ConfiguredAppliedMismatch"
    "negative_pathloss_not_applied","large_scale","enabled","disabled","sixgr:channel:ConfiguredAppliedMismatch"
    "negative_interference_not_applied","interference","enabled","disabled","sixgr:channel:ConfiguredAppliedMismatch"
    "negative_rf_waveform_unchanged","rf_impairment_chain","enabled","disabled","sixgr:channel:ConfiguredAppliedMismatch"
    "negative_oracle_receiver_injection","oracle","receiver_estimate","perfect_channel","sixgr:channel:PerfectChannelOracleForbidden"
    "negative_downstream_reference_missing","downstream_reference","required","missing","sixgr:channel:DownstreamReferenceMissing"];
configuredRows=repmat(localConfiguredRow(),0,1);
negativeRows=repmat(localNegativeRow(),0,1);
oracleRows=repmat(localOracleRow(),0,1);
for ii=1:size(specs,1)
    caught="";
    try
        localExecuteNegativeContract(specs(ii,2),specs(ii,3),specs(ii,4));
    catch ME
        caught=string(ME.identifier);
    end
    passed=caught==specs(ii,5);
    c=localConfiguredRow(); c.RunId=string(identity.RunID); c.TrialId=specs(ii,1); c.Feature=specs(ii,2);
    c.ConfiguredChannelModelType=specs(ii,3); c.AppliedChannelModelType=specs(ii,4);
    c.ConfiguredAppliedMatch=false; c.FeatureConfigured=true; c.FeatureApplied=false;
    c.ExpectedOk=false; c.StrictOk=false; c.TruthStatus="executed_negative_contract_evidence";
    c.FailureReason=caught; c=localBindRow(c,identity,"component_anchor",false);
    configuredRows(end+1,1)=c; %#ok<AGROW>
    n=localNegativeRow(); n.RunId=string(identity.RunID); n.NegativeTrialType=specs(ii,1);
    n.InjectedFault=specs(ii,3)+"->"+specs(ii,4); n.ExpectedFailureStage=specs(ii,2);
    n.ObservedFailureStage=specs(ii,2); n.ExactConfiguredAppliedMatch=false;
    n.StrictOk=false; n.NegativeExpectedOk=passed; n.FailureReason=caught;
    n.ExpectedErrorIdentifier=specs(ii,5); n.ObservedErrorIdentifier=caught;
    n=localBindRow(n,identity,"component_anchor",false); negativeRows(end+1,1)=n; %#ok<AGROW>
    o=localOracleRow(); o.RunId=string(identity.RunID); o.TrialId=specs(ii,1);
    o.Stage="executed_negative_contract"; o.OracleFieldName=specs(ii,2);
    o.WasAccessed=specs(ii,2)=="oracle"; o.Allowed=false; o.Violation=false;
    o.Status=localReason(passed,"typed_negative_rejected","typed_negative_not_rejected");
    o=localBindRow(o,identity,"component_anchor",false); oracleRows(end+1,1)=o; %#ok<AGROW>
end
configuredT=struct2table(configuredRows,"AsArray",true);
negativeT=struct2table(negativeRows,"AsArray",true);
oracleT=struct2table(oracleRows,"AsArray",true);
ok=all(logical(negativeT.NegativeExpectedOk)) && ~any(logical(oracleT.Violation));
end

function localExecuteNegativeContract(feature,configured,applied)
if feature=="oracle"
    error("sixgr:channel:PerfectChannelOracleForbidden", ...
        "Perfect channel state cannot enter a strict receiver decision.");
elseif feature=="downstream_reference"
    error("sixgr:channel:DownstreamReferenceMissing", ...
        "Runtime downstream Channel/RF identifiers are required.");
elseif configured~=applied
    error("sixgr:channel:ConfiguredAppliedMismatch", ...
        "Configured %s state %s does not match applied state %s.",feature,configured,applied);
end
end

function value=localMarkConfigAuthority(value,identity)
value=localMarkValue(value,identity,"config_authority",false);
end
function value=localMarkGeometryAuthority(value,identity)
value=localMarkValue(value,identity,"configured_geometry_authority",false);
end
function value=localMarkValue(value,identity,scope,eligible)
if istable(value)
    value=localBindTable(value,identity,scope,eligible); return;
end
if isstruct(value) && isscalar(value)
    names=fieldnames(value);
    for ii=1:numel(names)
        child=value.(names{ii});
        if istable(child) || (isstruct(child)&&isscalar(child))
            value.(names{ii})=localMarkValue(child,identity,scope,eligible);
        end
    end
end
end

function row=localBindRow(row,identity,scope,eligible)
row.ExecutionID=string(identity.ExecutionID); row.ScenarioID=string(identity.ScenarioID);
row.ScenarioConfigHash=lower(string(identity.ConfigHash)); row.EvidenceScope=string(scope);
row.SameScenarioInPathEligible=logical(eligible);
end
function T=localBindTable(T,identity,scope,eligible)
T.ExecutionID=repmat(string(identity.ExecutionID),height(T),1);
T.ScenarioID=repmat(string(identity.ScenarioID),height(T),1);
T.ScenarioConfigHash=repmat(lower(string(identity.ConfigHash)),height(T),1);
T.EvidenceScope=repmat(string(scope),height(T),1);
T.SameScenarioInPathEligible=repmat(logical(eligible),height(T),1);
end

function evidence=localSampleEvidence(channelT,pathT,rfT)
evidence=struct("RuntimeChannelRealizationDigest", ...
    sixgr.channel.hashChannelRFConfig(table2struct(channelT)), ...
    "RuntimePathGainDigest",sixgr.channel.hashChannelRFConfig(table2struct(pathT)), ...
    "RuntimeRFChainDigest",sixgr.channel.hashChannelRFConfig(table2struct(rfT)));
end

function out=localValue(T,name,row,defaultValue)
if ismember(string(name),string(T.Properties.VariableNames))
    col=T.(char(name)); out=col(row);
else
    out=defaultValue;
end
end

function [sampleRateHz, source] = localResolveRuntimeSampleRateHz(cfg,T,row)
% Resolve the physical sample clock without manufacturing a denominator.
% An explicit trial value is authoritative when present and must agree with
% the normalized scenario authority.  Otherwise the runtime uses the
% sample rate resolved by buildInternalConfig from the active numerology.
trialNames = ["SampleRate_Hz","SampleRateHz"];
configPaths = ["phy.waveform.sampleRate_Hz","waveform.sample_rate_hz", ...
    "phy.sampleRate_Hz"];
[configuredRate, configuredSource] = localFirstPositiveConfigValue(cfg,configPaths);
for name = trialNames
    if ~ismember(name,string(T.Properties.VariableNames))
        continue
    end
    sampleRateHz = double(localValue(T,name,row,NaN));
    if ~(isscalar(sampleRateHz) && isfinite(sampleRateHz) && sampleRateHz > 0)
        error("sixgr:channel:InvalidRuntimeSampleRate", ...
            "Runtime trial field %s must contain a finite positive sample rate.",name);
    end
    if isfinite(configuredRate) && abs(sampleRateHz-configuredRate) > ...
            max(1e-9*configuredRate,1e-6)
        error("sixgr:channel:RuntimeSampleRateMismatch", ...
            "Runtime trial sample rate %.15g Hz does not match %s %.15g Hz.", ...
            sampleRateHz,configuredSource,configuredRate);
    end
    source = "runtime_trial." + name;
    return
end
if ~(isfinite(configuredRate) && configuredRate > 0)
    error("sixgr:channel:RuntimeSampleRateUnavailable", ...
        "Channel snapshot timing requires a runtime trial sample rate or " + ...
        "the normalized scenario sample-rate authority.");
end
sampleRateHz = configuredRate;
source = configuredSource;
end

function [value, source] = localFirstPositiveConfigValue(cfg,paths)
value = NaN;
source = "";
for path = paths
    candidate = double(sixgr.util.structGet(cfg,path,NaN));
    if isscalar(candidate) && isfinite(candidate) && candidate > 0
        value = candidate;
        source = "resolved_config." + path;
        return
    end
end
end
function localRequireColumns(T,names,label)
missing=names(~ismember(names,string(T.Properties.VariableNames)));
if ~isempty(missing)
    error("sixgr:channel:MissingInPathRuntimeColumns", ...
        "%s is missing runtime columns: %s.",label,strjoin(missing,"|"));
end
end
function id=localTrialId(direction,T,row)
id=lower(direction)+"_sfn"+string(localValue(T,"SFN",row,NaN))+ ...
    "_slot"+string(localValue(T,"Slot",row,NaN))+ ...
    "_ue"+string(localValue(T,"UEIndex",row,NaN))+ ...
    "_seed"+string(localValue(T,"Seed",row,NaN));
end
function tf=localIsHash(value)
tf=~isempty(regexp(char(lower(strtrim(string(value)))),'^[0-9a-f]{64}$','once'));
end
function model=localConcreteConfiguredModel(cfg)
model=upper(strtrim(string(sixgr.util.structGet(cfg,"channel.model","AWGN"))));
if model=="TDL"
    model=upper(strtrim(string(sixgr.util.structGet(cfg,"channel.tdlProfile", ...
        sixgr.util.structGet(cfg,"channel.fading.profile","")))));
elseif model=="CDL"
    model=upper(strtrim(string(sixgr.util.structGet(cfg,"channel.cdlProfile", ...
        sixgr.util.structGet(cfg,"channel.fading.profile","")))));
end
if any(model==["TDL","CDL",""])
    error("sixgr:channel:ConcreteFadingProfileRequired", ...
        "In-path Channel/RF evidence requires AWGN or a concrete TDL-/CDL- profile.");
end
end
function family=localChannelFamily(model)
model=upper(strtrim(string(model)));
if startsWith(model,"TDL-"), family="TDL";
elseif startsWith(model,"CDL-"), family="CDL";
else, family=model;
end
end
function tf=localRFConfigured(cfg)
tf=logical(sixgr.util.structGet(cfg,"rf.enable",false)) || ...
    logical(sixgr.util.structGet(cfg,"phy.impairments.phaseNoiseEnabled",false)) || ...
    logical(sixgr.util.structGet(cfg,"phy.impairments.iqImbalanceEnabled",false)) || ...
    logical(sixgr.util.structGet(cfg,"phy.impairments.paNonlinearityEnabled",false)) || ...
    logical(sixgr.util.structGet(cfg,"phy.impairments.adcQuantizationEnabled",false));
end
function token=localOnOff(tf)
if tf, token="enabled"; else, token="disabled"; end
end
function value=localReason(tf,whenTrue,whenFalse)
if tf, value=string(whenTrue); else, value=string(whenFalse); end
end
function txt=localFailureSummary(configOk,actualOk,positiveOk,negativeOk)
parts=strings(0,1);
if ~configOk, parts(end+1)="config_validation_failed"; end %#ok<AGROW>
if ~actualOk, parts(end+1)="runtime_channel_rf_evidence_failed"; end %#ok<AGROW>
if ~positiveOk, parts(end+1)="runtime_configured_applied_mismatch"; end %#ok<AGROW>
if ~negativeOk, parts(end+1)="typed_negative_contract_failed"; end %#ok<AGROW>
txt=strjoin(parts,";");
end

function row=localIdentityFields(row)
row.ExecutionID=""; row.ScenarioID=""; row.ScenarioConfigHash="";
row.EvidenceScope=""; row.SameScenarioInPathEligible=false;
end
function row=localChannelRow()
row=struct("RunId","","ScenarioName","","TrialId","","ChannelRealizationId","", ...
"ChannelModelType","","AppliedChannelModelType","","DelayProfile","","NumTxAntennas",NaN,"NumRxAntennas",NaN, ...
"MaxDopplerHz",NaN,"DelaySpreadSec",NaN,"WaveformBeforeHash","","WaveformAfterHash","","PathGainsHash","", ...
"ChannelSnapshotHash","","WaveformChanged",false,"PathGainsExported",false,"ChannelSnapshotExported",false, ...
"MeasuredRMSDelaySpreadSec",NaN,"ChannelMatrixRows",NaN,"ChannelMatrixColumns",NaN,"StrictOk",false,"TruthStatus","","FailureReason","");
row.ChannelEvidenceKind=""; row.WaveformHashScope=""; row.SnapshotManifestSHA256="";
row.CoefficientMATFile=""; row.CoefficientMATFileSHA256="";
row.SampleTimeSec=NaN; row.SampleRateHz=NaN; row.SampleRateSource="";
row=localIdentityFields(row); end
function row=localSnapshotRow()
row=struct("RunId","","TrialId","","ChannelRealizationId","","SnapshotIndex",NaN,"SampleTimeSec",NaN, ...
"SampleRateHz",NaN,"SampleRateSource","","MagnitudeMean",NaN,"PhaseMeanRad",NaN, ...
"ChannelSnapshotHash","","TruthStatus","");
row.SnapshotRepresentation=""; row.PathFiltersHash=""; row.SampleTimeHash="";
row.StartSample=NaN; row.EndSampleExclusive=NaN; row.CoefficientMATFile=""; row.CoefficientMATFileSHA256="";
row=localIdentityFields(row); end
function row=localPathGainRow()
row=struct("RunId","","TrialId","","ChannelRealizationId","","PathGainHash","","SampleTimeHash","", ...
"PathGainElementCount",NaN,"SampleTimeCount",NaN,"PathGainDimensions","","TruthStatus","");
row.EvidenceKind=""; row.SegmentIndex=NaN; row.CoefficientMATFile=""; row.CoefficientMATFileSHA256="";
row=localIdentityFields(row); end
function row=localLargeScaleRow()
row=struct("RunId","","ScenarioName","","LinkId","","ChannelRealizationId","","PathlossModel","","LOSState",false, ...
"O2IState",false,"Distance2Dm",NaN,"Distance3Dm",NaN,"GeometrySource","", ...
"PathlossDbConfigured",NaN,"PathlossDbApplied",NaN, ...
"ShadowFadingStdDb",NaN,"ShadowFadingDbApplied",NaN,"O2IModelSource","","O2IPenetrationLossDbApplied",NaN, ...
"TotalLargeScaleLossDbApplied",NaN,"WaveformPowerBeforeDb",NaN,"WaveformPowerAfterDb",NaN,"ExpectedDeltaDb",NaN, ...
"MeasuredDeltaDb",NaN,"ToleranceDb",NaN,"PathlossConfigured",false,"PathlossApplied",false, ...
"ShadowFadingConfigured",false,"ShadowFadingApplied",false,"O2IConfigured",false,"O2IApplied",false, ...
"AppliedOk",false,"TruthStatus","","FailureReason","", ...
"PowerMeasurementAvailable",false,"PowerClosureOk",false,"PowerMeasurementSource","", ...
"PowerMeasurementStartSample",NaN,"PowerMeasurementEndSampleExclusive",NaN); row=localIdentityFields(row); end
function row=localInterferenceRow()
row=struct("RunId","","ScenarioName","","InterferenceModelId","","InterfererCellId",NaN,"InterfererSectorId",NaN, ...
"InterfererUEId",NaN,"VictimCellId",NaN,"VictimUEId",NaN,"Direction","","ResourceOverlap","","TxPowerDbm",NaN, ...
"ReceivedInterferencePower",NaN,"SignalPower",NaN,"NoisePower",NaN,"ComputedSINRDb",NaN,"WaveformBeforeHash","", ...
"WaveformAfterHash","","InterferenceConfigured",false,"InterferenceApplied",false,"StrictOk",false,"TruthStatus","","FailureReason","");
row.InterferenceContributorCount=0; row.InterferencePowerSource="";
row=localIdentityFields(row); end
function row=localNoiseRow()
row=struct("RunId","","ScenarioName","","TrialId","","BandwidthHz",NaN,"TemperatureK",290,"NoiseFigureDb",NaN, ...
"ThermalNoiseVarianceConfigured",NaN,"ThermalNoiseVarianceApplied",NaN,"NoisePowerErrorDb",NaN,"ThermalNoiseApplied",false, ...
"NoiseOperatingMode","","InjectedNoiseVariance",NaN,"Status","","StrictOk",false,"TruthStatus","","FailureReason",""); row=localIdentityFields(row); end
function row=localRFRow()
row=struct("RunId","","TrialId","","RFImpairmentChainId","","Direction","","TxOrRxSide","","Endpoint","","StageOrder","", ...
"CFOEnabled",false,"CFOHzConfigured",NaN,"CFOHzApplied",NaN,"PhaseNoiseEnabled",false,"PhaseNoiseApplied",false, ...
"PhaseNoiseProfileId","","PhaseNoiseLevelApplied",NaN,"PhaseNoiseWaveformBeforeHash","","PhaseNoiseWaveformAfterHash","", ...
"PhaseNoiseExecutionStatus","","PhaseNoiseTruthClassification","","IQImbalanceEnabled",false,"AmplitudeImbalanceDb",NaN, ...
"PhaseImbalanceDeg",NaN,"PAEnabled",false,"PAModel","","BackoffDb",NaN,"TimingOffsetEnabled",false, ...
"TimingOffsetSamplesConfigured",NaN,"TimingOffsetSamplesApplied",NaN,"SampleClockOffsetEnabled",false,"SampleClockOffsetPpm",NaN, ...
"QuantizationEnabled",false,"ADCBits",NaN,"DACBits",NaN,"WaveformBeforeHash","","WaveformAfterHash","", ...
"WaveformChanged",false,"EVMMeasuredDb",NaN,"EVMMeasuredPercent",NaN,"RFConfigured",false,"StrictOk",false, ...
"TruthStatus","","FailureReason","", ...
"RFExecuted",false,"RFExecutionEvidenceSource","","RFExecutionManifestSHA256","", ...
"TXSegmentWaveformChanged",false,"RXSegmentWaveformChanged",false); row=localIdentityFields(row); end
function row=localEVMRow()
row=struct("RunId","","TrialId","","RFImpairmentChainId","","Direction","","MeasurementPoint","","EVMDb",NaN, ...
"EVMPercent",NaN,"CFOHzEstimated",NaN,"IQImageRejectionDb",NaN,"PACompressionDb",NaN,"PhaseNoiseMetric",NaN, ...
"Status","","FailureReason",""); row=localIdentityFields(row); end
function row=localDownstreamRow()
row=struct("RunId","","ScenarioName","","Direction","","TrialTable","","TrialId","","CellId",NaN,"UEId",NaN, ...
"ChannelRealizationId","","RFImpairmentChainId","","ReferenceValid",false,"Status","","FailureReason",""); row=localIdentityFields(row); end
function row=localConfiguredRow()
row=struct("RunId","","TrialId","","Feature","","ConfiguredChannelModelType","","AppliedChannelModelType","", ...
"ConfiguredAppliedMatch",false,"FeatureConfigured",false,"FeatureApplied",false,"ExpectedOk",false,"StrictOk",false, ...
"TruthStatus","","FailureReason",""); row=localIdentityFields(row); end
function row=localNegativeRow()
row=struct("RunId","","NegativeTrialType","","InjectedFault","","ExpectedFailureStage","","ObservedFailureStage","", ...
"ExactConfiguredAppliedMatch",false,"StrictOk",false,"NegativeExpectedOk",false,"FailureReason","", ...
"ExpectedErrorIdentifier","","ObservedErrorIdentifier",""); row=localIdentityFields(row); end
function row=localOracleRow()
row=struct("RunId","","TrialId","","Stage","","OracleFieldName","","WasAccessed",false,"Allowed",false, ...
"Violation",false,"Status",""); row=localIdentityFields(row); end
