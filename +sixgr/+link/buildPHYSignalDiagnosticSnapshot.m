function snapshot = buildPHYSignalDiagnosticSnapshot(cfg, direction, tx, rxWave, rx, constellationT, context)
%BUILDPHYSIGNALDIAGNOSTICSNAPSHOT Capture one bounded, same-trial PHY diagnostic.
%
% The snapshot is intentionally built while the actual TX waveform, channel
% output, receiver channel estimate, received data REs, and aligned
% constellation evidence are all available.  It never reconstructs missing
% evidence from configured SNR, trial aggregates, or downsampled previews.

if nargin < 7 || ~isstruct(context)
    context = struct();
end
direction = upper(strtrim(string(direction)));
snapshot = localEmptySnapshot(direction);

if ~logical(sixgr.util.structGet(cfg, "outputs.phySignalDiagnosticEnabled", false))
    snapshot.Reason = string(sixgr.util.structGet(cfg, ...
        "outputs.phySignalDiagnosticUnavailableReason", "capture_disabled_by_config"));
    if strlength(strtrim(snapshot.Reason)) == 0
        snapshot.Reason = "capture_disabled_by_config";
    end
    return;
end
if ~any(direction == ["DL","UL"])
    snapshot.Reason = "unsupported_direction";
    return;
end

txWave = localFirstWaveformColumn(sixgr.util.structGet(tx, "Waveform", []));
rxWave = localFirstWaveformColumn(rxWave);
nAvailable = min(numel(txWave), numel(rxWave));
minWaveformSamples = 64;
if nAvailable < minWaveformSamples
    snapshot.Reason = "contiguous_tx_rx_waveform_unavailable";
    return;
end

sampleRateHz = localFirstFiniteScalar( ...
    sixgr.util.structGet(context, "SampleRate_Hz", NaN), ...
    sixgr.util.structGet(tx, "OFDMInfo.SampleRate", NaN), ...
    sixgr.util.structGet(tx, "OFDM.SampleRate", NaN));
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    snapshot.Reason = "waveform_sample_rate_unavailable";
    return;
end

hest = sixgr.util.structGet(rx, "ChannelEstimate", []);
channelSource = string(sixgr.util.structGet(rx, "ChannelEstimateSource", ""));
channelMethod = string(sixgr.util.structGet(rx, "ChannelEstimateMethod", ""));
channelModel = localChannelModel(cfg);
delayProfile = localDelayProfile(cfg, channelModel);
if strlength(strtrim(channelModel)) == 0
    snapshot.Reason = "channel_model_provenance_unavailable";
    return;
end
if isempty(hest)
    snapshot.Reason = "receiver_channel_estimate_unavailable";
    return;
end
if strlength(strtrim(channelSource)) == 0 || strlength(strtrim(channelMethod)) == 0
    snapshot.Reason = "receiver_channel_estimator_provenance_incomplete";
    return;
end
if localHasForbiddenEvidenceToken(channelSource + "|" + channelMethod)
    snapshot.Reason = "receiver_channel_estimate_has_forbidden_provenance";
    return;
end
if localIsFadingChannel(channelModel, delayProfile)
    if numel(hest) <= 1 || size(hest, 1) <= 1
        snapshot.Reason = "fading_channel_requires_grid_shaped_hest";
        return;
    end
    lowerSource = lower(channelSource + "|" + channelMethod);
    if contains(lowerSource, "awgn") || contains(lowerSource, "unit_channel") || contains(lowerSource, "flat_validation")
        snapshot.Reason = "fading_channel_hest_uses_awgn_shortcut";
        return;
    end
end

[hSlice, hSubcarrier, hSymbolIndex] = localSelectChannelEstimateSlice(hest, cfg);
finiteH = isfinite(real(hSlice)) & isfinite(imag(hSlice));
hSlice = hSlice(finiteH);
hSubcarrier = hSubcarrier(finiteH);
if isempty(hSlice)
    snapshot.Reason = "receiver_channel_estimate_has_no_finite_grid_samples";
    return;
end

if direction == "DL"
    preEq = sixgr.util.structGet(rx, "PDSCHRxSymbolsForEvidence", []);
else
    preEq = sixgr.util.structGet(rx, "PUSCHRxSymbolsForEvidence", []);
end
preEq = localFirstWaveformColumn(preEq);
preMask = isfinite(real(preEq)) & isfinite(imag(preEq));
preEq = preEq(preMask);
if isempty(preEq)
    snapshot.Reason = "pre_equalization_data_re_evidence_unavailable";
    return;
end

[constellationUse, constellationReason] = localSelectConstellationEvidence(constellationT);
if isempty(constellationUse)
    snapshot.Reason = constellationReason;
    return;
end

maxWaveformSamples = localBoundedInteger(cfg, "outputs.phySignalDiagnosticWaveformSamples", 1024, 64, 4096);
maxFFTLength = localBoundedInteger(cfg, "outputs.phySignalDiagnosticFFTLength", 1024, 64, 4096);
maxChannelPoints = localBoundedInteger(cfg, "outputs.phySignalDiagnosticChannelPoints", 1024, 8, 4096);
maxConstellationPoints = localBoundedInteger(cfg, "outputs.phySignalDiagnosticConstellationPoints", 512, 16, 2048);

nTime = min(nAvailable, maxWaveformSamples);
timeIndex = (1:nTime).';
time_s = (double(timeIndex) - 1) ./ sampleRateHz;
txTime = txWave(timeIndex);
rxTime = rxWave(timeIndex);

nFFTAvailable = min(nAvailable, maxFFTLength);
nFFT = 2 ^ floor(log2(double(nFFTAvailable)));
if nFFT < minWaveformSamples
    snapshot.Reason = "contiguous_waveform_window_too_short_for_fft";
    return;
end
[frequencyOffsetHz, txSpectrum_dB, rxSpectrum_dB] = localRelativeSpectrum( ...
    txWave(1:nFFT), rxWave(1:nFFT), sampleRateHz);

if numel(hSlice) > maxChannelPoints
    hKeep = unique(round(linspace(1, numel(hSlice), maxChannelPoints))).';
    hSlice = hSlice(hKeep);
    hSubcarrier = hSubcarrier(hKeep);
end
if numel(preEq) > maxConstellationPoints
    preEq = preEq(1:maxConstellationPoints);
end
if height(constellationUse) > maxConstellationPoints
    constellationUse = constellationUse(1:maxConstellationPoints, :);
end

meta = localMetadata(cfg, direction, rx, context, constellationUse, ...
    sampleRateHz, nFFT, channelModel, delayProfile, channelSource, channelMethod, hSymbolIndex);
sourceT = localEmptySourceTable();

rows = localBaseRows(meta, "time_domain", "tx", numel(timeIndex));
rows.PointIndex = double(timeIndex);
rows.SampleIndex = double(timeIndex);
rows.XValue = time_s;
rows.YValue = abs(txTime);
rows.XUnit(:) = "s";
rows.YUnit(:) = "complex_baseband_amplitude";
rows.IValue = real(txTime);
rows.QValue = imag(txTime);
sourceT = [sourceT; rows]; %#ok<AGROW>

rows = localBaseRows(meta, "time_domain", "rx", numel(timeIndex));
rows.PointIndex = double(timeIndex);
rows.SampleIndex = double(timeIndex);
rows.XValue = time_s;
rows.YValue = abs(rxTime);
rows.XUnit(:) = "s";
rows.YUnit(:) = "complex_baseband_amplitude";
rows.IValue = real(rxTime);
rows.QValue = imag(rxTime);
sourceT = [sourceT; rows]; %#ok<AGROW>

rows = localBaseRows(meta, "spectrum", "tx", numel(frequencyOffsetHz));
rows.PointIndex = (1:numel(frequencyOffsetHz)).';
rows.XValue = frequencyOffsetHz;
rows.YValue = txSpectrum_dB;
rows.XUnit(:) = "Hz_offset";
rows.YUnit(:) = "relative_magnitude_dB_common_reference";
sourceT = [sourceT; rows]; %#ok<AGROW>

rows = localBaseRows(meta, "spectrum", "rx", numel(frequencyOffsetHz));
rows.PointIndex = (1:numel(frequencyOffsetHz)).';
rows.XValue = frequencyOffsetHz;
rows.YValue = rxSpectrum_dB;
rows.XUnit(:) = "Hz_offset";
rows.YUnit(:) = "relative_magnitude_dB_common_reference";
sourceT = [sourceT; rows]; %#ok<AGROW>

hMagnitude_dB = 20 .* log10(max(abs(hSlice), realmin));
hPhase_deg = unwrap(angle(hSlice)) .* 180 ./ pi;
rows = localBaseRows(meta, "channel_estimate", "hest", numel(hSlice));
rows.PointIndex = (1:numel(hSlice)).';
rows.SubcarrierIndex = double(hSubcarrier);
rows.OFDMSymbolIndex(:) = double(hSymbolIndex);
rows.XValue = double(hSubcarrier);
rows.YValue = hMagnitude_dB;
rows.XUnit(:) = "subcarrier_index";
rows.YUnit(:) = "channel_magnitude_dB";
rows.IValue = real(hSlice);
rows.QValue = imag(hSlice);
rows.Magnitude_dB = hMagnitude_dB;
rows.Phase_deg = hPhase_deg;
sourceT = [sourceT; rows]; %#ok<AGROW>

rows = localBaseRows(meta, "pre_equalization_re_cloud", "rx_antenna_1", numel(preEq));
rows.PointIndex = (1:numel(preEq)).';
rows.XValue = real(preEq);
rows.YValue = imag(preEq);
rows.XUnit(:) = "received_data_re_I";
rows.YUnit(:) = "received_data_re_Q";
rows.IValue = real(preEq);
rows.QValue = imag(preEq);
sourceT = [sourceT; rows]; %#ok<AGROW>

eq = complex(double(constellationUse.EqualizedReal), double(constellationUse.EqualizedImag));
ref = complex(double(constellationUse.ReferenceSymbolReal), double(constellationUse.ReferenceSymbolImag));
hard = complex(nan(height(constellationUse), 1));
if all(ismember(["HardDecisionReal","HardDecisionImag"], string(constellationUse.Properties.VariableNames)))
    hard = complex(double(constellationUse.HardDecisionReal), double(constellationUse.HardDecisionImag));
elseif all(ismember(["DecisionReal","DecisionImag"], string(constellationUse.Properties.VariableNames)))
    hard = complex(double(constellationUse.DecisionReal), double(constellationUse.DecisionImag));
end
rows = localBaseRows(meta, "post_equalization_constellation", "layer_1", numel(eq));
rows.PointIndex = (1:numel(eq)).';
rows.XValue = real(eq);
rows.YValue = imag(eq);
rows.XUnit(:) = "normalized_equalized_I";
rows.YUnit(:) = "normalized_equalized_Q";
rows.IValue = real(eq);
rows.QValue = imag(eq);
rows.ReferenceI = real(ref);
rows.ReferenceQ = imag(ref);
rows.EqualizedI = real(eq);
rows.EqualizedQ = imag(eq);
rows.HardDecisionI = real(hard);
rows.HardDecisionQ = imag(hard);
sourceT = [sourceT; rows]; %#ok<AGROW>

kpiRows = localKPIRows(meta);
sourceT = [sourceT; kpiRows]; %#ok<AGROW>

snapshot.Available = true;
snapshot.Reason = "";
snapshot.Direction = direction;
snapshot.SnapshotID = meta.SnapshotID;
snapshot.Metadata = meta;
snapshot.SourceTable = sourceT;
end

function snapshot = localEmptySnapshot(direction)
snapshot = struct( ...
    "Available", false, ...
    "Reason", "capture_not_attempted", ...
    "Direction", string(direction), ...
    "SnapshotID", "", ...
    "Metadata", struct(), ...
    "SourceTable", localEmptySourceTable());
end

function x = localFirstWaveformColumn(x)
if isempty(x)
    x = complex([]);
    return;
end
if iscell(x)
    try
        x = x{1};
    catch
        x = [];
    end
end
if isempty(x)
    x = complex([]);
    return;
end
if ismatrix(x) && size(x, 2) > 1
    x = x(:, 1);
end
x = x(:);
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:nargin
    candidate = varargin{i};
    try
        candidate = double(candidate);
    catch
        continue;
    end
    candidate = candidate(isfinite(candidate));
    if ~isempty(candidate)
        value = candidate(1);
        return;
    end
end
end

function value = localBoundedInteger(cfg, path, fallback, lowerBound, upperBound)
value = double(sixgr.util.structGet(cfg, path, fallback));
if ~(isscalar(value) && isfinite(value))
    value = fallback;
end
value = min(upperBound, max(lowerBound, round(value)));
end

function model = localChannelModel(cfg)
model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", ...
    sixgr.util.structGet(cfg, "channels.model", ...
    sixgr.util.structGet(cfg, "channel.profile", ""))))));
end

function profile = localDelayProfile(cfg, channelModel)
model = upper(strtrim(string(channelModel)));
if startsWith(model, "TDL")
    profile = string(sixgr.util.structGet(cfg, "channel.tdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", ...
        sixgr.util.structGet(cfg, "channel.profile", ...
        sixgr.util.structGet(cfg, "channels.profile", "")))));
elseif startsWith(model, "CDL")
    profile = string(sixgr.util.structGet(cfg, "channel.cdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", ...
        sixgr.util.structGet(cfg, "channel.profile", ...
        sixgr.util.structGet(cfg, "channels.profile", "")))));
else
    profile = string(sixgr.util.structGet(cfg, "channel.profile", ...
        sixgr.util.structGet(cfg, "channels.profile", channelModel)));
end
profile = upper(strtrim(profile));
end

function tf = localIsFadingChannel(model, profile)
token = upper(string(model) + "|" + string(profile));
tf = contains(token, "TDL") || contains(token, "CDL") || contains(token, "FADING");
end

function tf = localHasForbiddenEvidenceToken(text)
text = lower(strtrim(string(text)));
tf = any(contains(text, [ ...
    "fallback","synthetic","proxy","logistic","lut","oracle", ...
    "perfect","ideal","genie"]));
end

function [slice, subcarrier, symbolIndex] = localSelectChannelEstimateSlice(hest, cfg)
slice = complex([]);
subcarrier = [];
symbolIndex = NaN;
if isempty(hest)
    return;
end
hest = complex(double(hest));
if isvector(hest)
    hest = hest(:);
    k = numel(hest);
    l = 1;
    h3 = reshape(hest, k, l, 1);
else
    sz = size(hest);
    k = sz(1);
    l = sz(2);
    h3 = reshape(hest, k, l, []);
end
counts = zeros(l, 1);
for li = 1:l
    candidate = h3(:, li, 1);
    counts(li) = sum(isfinite(real(candidate)) & isfinite(imag(candidate)));
end
[~, symbolIndex] = max(counts);
if isempty(symbolIndex) || counts(symbolIndex) < 1
    slice = complex([]);
    subcarrier = [];
    symbolIndex = NaN;
    return;
end
slice = h3(:, symbolIndex, 1);
subcarrier = (1:k).';
symbolIndex = double(symbolIndex);

% Preserve the receiver grid indexing convention. SCS is resolved by the
% exporter from metadata; no synthetic interpolation is performed here.
if localIsFadingChannel(localChannelModel(cfg), localDelayProfile(cfg, localChannelModel(cfg))) && k <= 1
    slice = complex([]);
    subcarrier = [];
end
end

function [frequencyOffsetHz, txDB, rxDB] = localRelativeSpectrum(tx, rx, sampleRateHz)
n = min(numel(tx), numel(rx));
tx = tx(1:n);
rx = rx(1:n);
if n == 1
    window = 1;
else
    window = 0.5 - 0.5 .* cos(2 .* pi .* (0:n-1).' ./ (n-1));
end
txFFT = fftshift(fft(tx .* window, n));
rxFFT = fftshift(fft(rx .* window, n));
commonReference = max([abs(txFFT(:)); abs(rxFFT(:))], [], "omitnan");
commonReference = max(commonReference, realmin);
txDB = 20 .* log10(max(abs(txFFT), realmin) ./ commonReference);
rxDB = 20 .* log10(max(abs(rxFFT), realmin) ./ commonReference);
frequencyOffsetHz = ((0:n-1).' - floor(n/2)) .* (sampleRateHz ./ n);
end

function [T, reason] = localSelectConstellationEvidence(T)
reason = "post_equalization_constellation_evidence_unavailable";
if ~(istable(T) && ~isempty(T))
    T = table();
    return;
end
required = ["ReferenceSymbolReal","ReferenceSymbolImag","EqualizedReal","EqualizedImag"];
if ~all(ismember(required, string(T.Properties.VariableNames)))
    T = table();
    reason = "post_equalization_constellation_schema_incomplete";
    return;
end
if ismember("truth_status", string(T.Properties.VariableNames))
    truth = lower(strtrim(string(T.truth_status)));
elseif ismember("TruthStatus", string(T.Properties.VariableNames))
    truth = lower(strtrim(string(T.TruthStatus)));
else
    T = table();
    reason = "post_equalization_constellation_provenance_missing";
    return;
end
if any(truth ~= "real_lls_evidence")
    T = table();
    reason = "post_equalization_constellation_truth_status_invalid";
    return;
end
for provenanceField = ["Source","ExecutionBackend","ApproximationMode","Notes"]
    field = char(provenanceField);
    if ismember(provenanceField, string(T.Properties.VariableNames)) && ...
            any(localHasForbiddenEvidenceToken(string(T.(field))))
        T = table();
        reason = "post_equalization_constellation_provenance_conflict:" + provenanceField;
        return;
    end
end
mask = isfinite(double(T.ReferenceSymbolReal)) & isfinite(double(T.ReferenceSymbolImag)) & ...
    isfinite(double(T.EqualizedReal)) & isfinite(double(T.EqualizedImag));
if ismember("LayerIndex", string(T.Properties.VariableNames))
    layer = double(T.LayerIndex);
    finiteLayer = layer(isfinite(layer));
    if ~isempty(finiteLayer)
        mask = mask & layer == finiteLayer(1);
    end
end
T = T(mask, :);
if isempty(T)
    reason = "post_equalization_constellation_has_no_finite_symbol_pairs";
end
end

function meta = localMetadata(cfg, direction, rx, context, constellationT, sampleRateHz, nFFT, channelModel, delayProfile, channelSource, channelMethod, hSymbolIndex)
meta = struct();
meta.Direction = string(direction);
userContext = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
meta.UEIndex = localFirstFiniteScalar( ...
    sixgr.util.structGet(context, "UEIndex", NaN), ...
    sixgr.util.structGet(userContext, "RuntimeUEIndex", ...
    sixgr.util.structGet(userContext, "UEIndex", NaN)));
meta.UEIdentitySource = string(sixgr.util.structGet(context, "UEIdentitySource", ""));
if strlength(strtrim(meta.UEIdentitySource)) == 0
    if isfinite(localFirstFiniteScalar(sixgr.util.structGet(context, "UEIndex", NaN)))
        meta.UEIdentitySource = "trial_context";
    elseif isfinite(localFirstFiniteScalar(sixgr.util.structGet(userContext, "RuntimeUEIndex", NaN)))
        meta.UEIdentitySource = "runtime_user_context";
    elseif isfinite(localFirstFiniteScalar(sixgr.util.structGet(userContext, "UEIndex", NaN)))
        meta.UEIdentitySource = "configured_user_context";
    end
end
if ~isfinite(meta.UEIndex)
    multiUserEnabled = logical(sixgr.util.structGet(cfg, "lls6g.users.enabled", false));
    numUsers = localFirstFiniteScalar(sixgr.util.structGet(cfg, "lls6g.users.n_users", 1));
    if ~multiUserEnabled || ~(isfinite(numUsers) && numUsers > 1)
        meta.UEIndex = 1;
        meta.UEIdentitySource = "standalone_single_user_default";
    end
end
meta.RNTI = localFirstFiniteScalar( ...
    sixgr.util.structGet(context, "RNTI", NaN), ...
    sixgr.util.structGet(userContext, "RNTI", NaN), ...
    sixgr.util.structGet(cfg, "phy.rnti", NaN));
meta.Frame = localFirstFiniteScalar(sixgr.util.structGet(context, "Frame", NaN));
meta.Slot = localFirstFiniteScalar(sixgr.util.structGet(context, "Slot", NaN));
meta.TBId = string(sixgr.util.structGet(context, "TBId", ""));
meta.LayerIndex = localFirstFiniteScalar(sixgr.util.structGet(context, "LayerIndex", 1));
meta.Layers = localFirstFiniteScalar(sixgr.util.structGet(context, "Layers", 1));
meta.RxAntennaIndex = 1;
meta.TxPortIndex = 1;
meta.ChannelModel = string(channelModel);
meta.DelayProfile = string(delayProfile);
meta.ChannelEstimateSource = string(channelSource);
meta.ChannelEstimateMethod = string(channelMethod);
meta.ChannelEstimateEngine = string(sixgr.util.structGet(rx, "ChannelEstimateEngine", ""));
meta.ChannelEstimateInterpolationMethod = string(sixgr.util.structGet(rx, "ChannelEstimateInterpolationMethod", ""));
meta.ChannelEstimateOFDMSymbolIndex = double(hSymbolIndex);
meta.Modulation = string(sixgr.util.structGet(context, "Modulation", ""));
if strlength(strtrim(meta.Modulation)) == 0 && ismember("Modulation", string(constellationT.Properties.VariableNames))
    meta.Modulation = string(constellationT.Modulation(1));
end
meta.MCSIndex = localFirstFiniteScalar(sixgr.util.structGet(context, "MCSIndex", NaN));
meta.ConfiguredSNR_dB = localFirstFiniteScalar(sixgr.util.structGet(context, "ConfiguredSNR_dB", NaN));
meta.ConfiguredSNRSource = string(sixgr.util.structGet(context, "ConfiguredSNRSource", "runner_configured_stimulus"));
meta.PostEqSINR_dB = localFirstFiniteScalar( ...
    sixgr.util.structGet(context, "PostEqSINR_dB", NaN), ...
    sixgr.util.structGet(rx, "PostEqSINR_dB", NaN));
meta.PostEqSINRSource = string(sixgr.util.structGet(context, "PostEqSINRSource", ...
    sixgr.util.structGet(rx, "PostEqSINRSource", "")));
meta.PostEqSINRValueRole = string(sixgr.util.structGet(context, "PostEqSINRValueRole", ...
    sixgr.util.structGet(rx, "PostEqSINRValueRole", "")));
meta.EVM_rms_pct = 100 .* localFirstFiniteScalar(sixgr.util.structGet(context, "EVM_rms", NaN));
meta.CRCPass = localFirstFiniteScalar( ...
    sixgr.util.structGet(context, "CRCPass", NaN), ...
    sixgr.util.structGet(rx, "CRCPass", NaN));
meta.SampleRate_Hz = double(sampleRateHz);
meta.FFTLength = double(nFFT);
meta.CurveConstruction = "runtime_same_trial_phy_signal_snapshot";
meta.TruthStatus = "real_lls_evidence";
meta.SourceArtifact = "runtime_phy_arrays_same_trial";
meta.Status = "available";
meta.NAReason = "";
meta.SnapshotID = localSnapshotID(meta, cfg);
end

function id = localSnapshotID(meta, cfg)
runId = string(sixgr.util.structGet(cfg, "run.runId", ...
    sixgr.util.structGet(cfg, "run.runTag", ...
    sixgr.util.structGet(cfg, "meta.lls6gScenarioID", "run"))));
id = runId + "_" + meta.Direction + "_ue" + string(meta.UEIndex) + ...
    "_f" + string(meta.Frame) + "_s" + string(meta.Slot) + "_tb" + meta.TBId;
id = regexprep(id, "[^A-Za-z0-9_.-]", "_");
end

function T = localBaseRows(meta, panel, series, n)
T = table();
T.SnapshotID = repmat(string(meta.SnapshotID), n, 1);
T.Panel = repmat(string(panel), n, 1);
T.Series = repmat(string(series), n, 1);
T.PointIndex = nan(n, 1);
T.XValue = nan(n, 1);
T.YValue = nan(n, 1);
T.XUnit = strings(n, 1);
T.YUnit = strings(n, 1);
T.Direction = repmat(string(meta.Direction), n, 1);
T.UEIndex = repmat(double(meta.UEIndex), n, 1);
T.UEIdentitySource = repmat(string(meta.UEIdentitySource), n, 1);
T.RNTI = repmat(double(meta.RNTI), n, 1);
T.Frame = repmat(double(meta.Frame), n, 1);
T.Slot = repmat(double(meta.Slot), n, 1);
T.TBId = repmat(string(meta.TBId), n, 1);
T.LayerIndex = repmat(double(meta.LayerIndex), n, 1);
T.Layers = repmat(double(meta.Layers), n, 1);
T.RxAntennaIndex = repmat(double(meta.RxAntennaIndex), n, 1);
T.TxPortIndex = repmat(double(meta.TxPortIndex), n, 1);
T.ChannelModel = repmat(string(meta.ChannelModel), n, 1);
T.DelayProfile = repmat(string(meta.DelayProfile), n, 1);
T.ChannelEstimateSource = repmat(string(meta.ChannelEstimateSource), n, 1);
T.ChannelEstimateMethod = repmat(string(meta.ChannelEstimateMethod), n, 1);
T.ChannelEstimateEngine = repmat(string(meta.ChannelEstimateEngine), n, 1);
T.ChannelEstimateInterpolationMethod = repmat(string(meta.ChannelEstimateInterpolationMethod), n, 1);
T.Modulation = repmat(string(meta.Modulation), n, 1);
T.MCSIndex = repmat(double(meta.MCSIndex), n, 1);
T.ConfiguredSNR_dB = repmat(double(meta.ConfiguredSNR_dB), n, 1);
T.ConfiguredSNRSource = repmat(string(meta.ConfiguredSNRSource), n, 1);
T.PostEqSINR_dB = repmat(double(meta.PostEqSINR_dB), n, 1);
T.PostEqSINRSource = repmat(string(meta.PostEqSINRSource), n, 1);
T.PostEqSINRValueRole = repmat(string(meta.PostEqSINRValueRole), n, 1);
T.EVM_rms_pct = repmat(double(meta.EVM_rms_pct), n, 1);
T.CRCPass = repmat(double(meta.CRCPass), n, 1);
T.SampleRate_Hz = repmat(double(meta.SampleRate_Hz), n, 1);
T.FFTLength = repmat(double(meta.FFTLength), n, 1);
T.SampleIndex = nan(n, 1);
T.SubcarrierIndex = nan(n, 1);
T.OFDMSymbolIndex = nan(n, 1);
T.IValue = nan(n, 1);
T.QValue = nan(n, 1);
T.Magnitude_dB = nan(n, 1);
T.Phase_deg = nan(n, 1);
T.ReferenceI = nan(n, 1);
T.ReferenceQ = nan(n, 1);
T.EqualizedI = nan(n, 1);
T.EqualizedQ = nan(n, 1);
T.HardDecisionI = nan(n, 1);
T.HardDecisionQ = nan(n, 1);
T.KPIName = strings(n, 1);
T.KPINumericValue = nan(n, 1);
T.KPITextValue = strings(n, 1);
T.KPIUnit = strings(n, 1);
T.CurveConstruction = repmat(string(meta.CurveConstruction), n, 1);
T.truth_status = repmat(string(meta.TruthStatus), n, 1);
T.SourceArtifact = repmat(string(meta.SourceArtifact), n, 1);
T.Status = repmat(string(meta.Status), n, 1);
T.NAReason = repmat(string(meta.NAReason), n, 1);
end

function T = localKPIRows(meta)
names = [ ...
    "Direction","UEIndex","UE identity source","RNTI","Frame","Slot","TBId","ChannelModel","DelayProfile", ...
    "Modulation","MCSIndex","Layers","CRC pass","Configured SNR","Post-EQ SINR", ...
    "EVM RMS","Channel estimate source","Channel estimate method","Sample rate","FFT length"];
numeric = [ ...
    NaN,meta.UEIndex,NaN,meta.RNTI,meta.Frame,meta.Slot,NaN,NaN,NaN, ...
    NaN,meta.MCSIndex,meta.Layers,meta.CRCPass,meta.ConfiguredSNR_dB,meta.PostEqSINR_dB, ...
    meta.EVM_rms_pct,NaN,NaN,meta.SampleRate_Hz,meta.FFTLength].';
textValues = [ ...
    meta.Direction,"",meta.UEIdentitySource,"","","",meta.TBId,meta.ChannelModel,meta.DelayProfile, ...
    meta.Modulation,"","","","","","",meta.ChannelEstimateSource,meta.ChannelEstimateMethod,"",""].';
units = ["","","","","","","","","","","","","boolean","dB configured stimulus", ...
    "dB receiver-derived","percent","","","Hz","samples"].';
T = localBaseRows(meta, "kpi", "context", numel(names));
T.PointIndex = (1:numel(names)).';
T.XValue = T.PointIndex;
T.YValue = numeric;
T.XUnit(:) = "kpi_index";
T.YUnit = units;
T.KPIName = names.';
T.KPINumericValue = numeric;
T.KPITextValue = textValues;
T.KPIUnit = units;
end

function T = localEmptySourceTable()
meta = struct( ...
    "SnapshotID", "", "Direction", "", "UEIndex", NaN, "UEIdentitySource", "", "RNTI", NaN, ...
    "Frame", NaN, "Slot", NaN, "TBId", "", "LayerIndex", NaN, "Layers", NaN, ...
    "RxAntennaIndex", NaN, "TxPortIndex", NaN, "ChannelModel", "", ...
    "DelayProfile", "", "ChannelEstimateSource", "", "ChannelEstimateMethod", "", ...
    "ChannelEstimateEngine", "", "ChannelEstimateInterpolationMethod", "", ...
    "Modulation", "", "MCSIndex", NaN, "ConfiguredSNR_dB", NaN, ...
    "ConfiguredSNRSource", "", "PostEqSINR_dB", NaN, "PostEqSINRSource", "", ...
    "PostEqSINRValueRole", "", "EVM_rms_pct", NaN, "CRCPass", NaN, ...
    "SampleRate_Hz", NaN, "FFTLength", NaN, ...
    "CurveConstruction", "", "TruthStatus", "", "SourceArtifact", "", ...
    "Status", "", "NAReason", "");
T = localBaseRows(meta, "", "", 0);
end
