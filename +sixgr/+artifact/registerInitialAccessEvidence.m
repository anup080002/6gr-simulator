function coverage = registerInitialAccessEvidence(registry, result, scfg, cfg, runtimeIdentity)
%REGISTERINITIALACCESSEVIDENCE Register fresh in-path PRACH contract evidence.
%
% Only the current run's in-memory waveform trial table is accepted.  This
% adapter never reads an existing CSV and never pads a campaign to a
% contract minimum.

arguments
    registry (1,1) sixgr.artifact.EvidenceRegistry
    result (1,1) struct
    scfg
    cfg (1,1) struct
    runtimeIdentity (1,1) struct = struct()
end

domain = "initial_access";
rows = repmat(localCoverage("", "", false, 0, "", ""), 0, 1);
raw = sixgr.util.structGet(result, "Link.RawTrials.PRACH", table());
if ~(istable(raw) && ~isempty(raw))
    rows(end+1,1) = localCoverage("CSV", "prach_detection_trials.csv", ... %#ok<AGROW>
        false, 0, "NOT_REGISTERED", "in_memory_prach_trials_missing");
    coverage = struct2table(rows, "AsArray", true);
    return;
end

try
    detection = localBuildPRACHDetectionTrials(raw, scfg, cfg, runtimeIdentity);
    registry.registerTable(domain, "base", "prach_detection_trials.csv", ...
        detection, "sixgr.artifact.registerInitialAccessEvidence.prach_detection_trials");
    rows(end+1,1) = localCoverage("CSV", "prach_detection_trials.csv", ... %#ok<AGROW>
        true, height(detection), "REGISTERED", "");
catch cause
    rows(end+1,1) = localCoverage("CSV", "prach_detection_trials.csv", ... %#ok<AGROW>
        false, 0, "NOT_REGISTERED", string(cause.identifier) + " | " + string(cause.message));
end
coverage = struct2table(rows, "AsArray", true);
end

function T = localBuildPRACHDetectionTrials(raw, scfg, cfg, runtimeIdentity)
raw = localNormalizePRACHReceiverSchema(raw);
required = ["RARunId","PRACHOccasionID","PreambleIndexTx", ...
    "PreambleIndexDetected","PreambleDetected","PreambleDetectionMetric", ...
    "PreambleDetectionThreshold","PRACHPropagationTimingEstimate_samples", ...
    "PRACHTimingError_samples","PRACHFrequencyEstimationEnabled", ...
    "PRACHFrequencyEstimate_Hz","PRACHFrequencyEstimateValid", ...
    "PreambleAmbiguityDetected","FalseAlarm","MissedDetection", ...
    "DetectionAttempted","TruthStatus","ScenarioID","ConfigHash"];
missing = setdiff(required, string(raw.Properties.VariableNames), "stable");
if ~isempty(missing)
    error("sixgr:artifact:PRACHRawEvidenceMissingColumns", ...
        "In-memory PRACH trials lack required fields: %s", strjoin(missing, ", "));
end

identity = localIdentity(scfg, cfg, runtimeIdentity);
localRequireIdentity(raw, "ScenarioID", identity.ScenarioID);
localRequireIdentity(raw, "ConfigHash", identity.ConfigHash);

eligible = localLogicalColumn(raw, "FinalizedFlag", true) & ...
    localLogicalColumn(raw, "DetectionAttempted", false) & ...
    ~localLogicalColumn(raw, "FallbackFlag", false) & ...
    ~localLogicalColumn(raw, "PlaceholderFlag", false) & ...
    lower(strtrim(string(raw.TruthStatus))) == "real_lls_evidence";
raw = raw(eligible, :);
if isempty(raw)
    error("sixgr:artifact:NoEligiblePRACHTrials", ...
        "No finalized, attempted, non-fallback PRACH waveform trials are eligible.");
end

trialID = strtrim(string(raw.RARunId));
occasionID = strtrim(string(raw.PRACHOccasionID));
peak = double(raw.PreambleDetectionMetric);
threshold = double(raw.PreambleDetectionThreshold);
timing = double(raw.PRACHPropagationTimingEstimate_samples);
timingError = double(raw.PRACHTimingError_samples);
frequencyEnabled = localLogical(raw.PRACHFrequencyEstimationEnabled);
frequencyValid = localLogical(raw.PRACHFrequencyEstimateValid);
frequency = double(raw.PRACHFrequencyEstimate_Hz);
detected = localLogical(raw.PreambleDetected);
if any(ismissing(trialID) | strlength(trialID) == 0) || numel(unique(trialID)) ~= numel(trialID)
    error("sixgr:artifact:InvalidPRACHTrialIdentity", ...
        "Each PRACH evidence row requires a unique nonblank receiver trial ID.");
end
if any(ismissing(occasionID) | strlength(occasionID) == 0)
    error("sixgr:artifact:InvalidPRACHOccasionIdentity", ...
        "Each PRACH evidence row requires its resolved occasion identity.");
end
if any(~isfinite(peak) | ~isfinite(threshold))
    error("sixgr:artifact:InvalidPRACHReceiverMeasurement", ...
        "Every attempted PRACH row requires finite measured peak and threshold values.");
end
if any(detected & (~isfinite(double(raw.PreambleIndexDetected)) ...
        | ~isfinite(timing) | ~isfinite(timingError)))
    error("sixgr:artifact:InvalidPRACHReceiverMeasurement", ...
        "A successfully detected PRACH preamble requires a finite detected " + ...
        "index, propagation timing estimate, and timing error.");
end
if any(detected & frequencyEnabled & (~frequencyValid | ~isfinite(frequency)))
    error("sixgr:artifact:MissingEnabledPRACHFrequencyEstimate", ...
        "YAML-enabled PRACH CFO estimation requires a finite valid estimate " + ...
        "on every successfully detected trial.");
end
if any(~detected & (frequencyValid | isfinite(frequency)))
    error("sixgr:artifact:SpuriousMissedPRACHFrequencyEstimate", ...
        "A missed PRACH detection cannot claim a valid receiver CFO " + ...
        "estimate from the absent preamble.");
end

n = height(raw);
T = table( ...
    trialID, occasionID, double(raw.PreambleIndexTx), ...
    double(raw.PreambleIndexDetected), detected, ...
    peak, threshold, timing, timingError, frequency, ...
    localLogical(raw.FalseAlarm), localLogical(raw.MissedDetection), ...
    localLogical(raw.PreambleAmbiguityDetected), repmat("MEASURED", n, 1), ...
    repmat(identity.ScenarioID, n, 1), repmat(identity.ConfigHash, n, 1), ...
    repmat("in_path", n, 1), repmat(identity.RunID, n, 1), ...
    repmat(identity.ExecutionID, n, 1), repmat(identity.CenterFrequencyHz, n, 1), ...
    repmat(identity.BandwidthHz, n, 1), repmat(identity.SubcarrierSpacingHz, n, 1), ...
    frequencyEnabled, frequencyValid, ...
    'VariableNames', {'TrialID','OccasionID','PreambleIndexTx', ...
    'PreambleIndexDetected','Detected','PeakMetric','Threshold', ...
    'TimingEstimate_samples','TimingError_samples','FrequencyEstimate_Hz', ...
    'FalseAlarm','MissedDetection','Ambiguous','Status','ScenarioID', ...
    'ConfigHash','EvidenceScope','RunID','ExecutionID','CenterFrequencyHz', ...
    'BandwidthHz','SubcarrierSpacingHz','FrequencyEstimationEnabled', ...
    'FrequencyEstimateValid'});
if strlength(identity.ExecutionID) == 0
    T.ExecutionID = [];
end
T = sortrows(T, "TrialID");
end

function raw = localNormalizePRACHReceiverSchema(raw)
% Normalize historical in-memory receiver aliases without manufacturing a
% measurement.  EstimatedCFO_Hz is the canonical link-trial alias populated
% from the same PRACH receiver estimate.  A missing estimate column is only
% materialized as NaN when frequency estimation was explicitly disabled.
vars = string(raw.Properties.VariableNames);
if ismember("PRACHFrequencyEstimate_Hz", vars)
    if ismember("EstimatedCFO_Hz", vars)
        specific = double(raw.PRACHFrequencyEstimate_Hz);
        generic = double(raw.EstimatedCFO_Hz);
        comparable = isfinite(specific) & isfinite(generic);
        scale = 1;
        if any(comparable)
            scale = max(1, max(abs([specific(comparable); generic(comparable)])));
        end
        tolerance = 16 * eps(scale);
        if any(abs(specific(comparable) - generic(comparable)) > tolerance)
            error("sixgr:artifact:PRACHFrequencyEstimateAliasMismatch", ...
                "PRACH-specific and generic receiver CFO estimates disagree.");
        end
    end
    return;
end

if ismember("EstimatedCFO_Hz", vars)
    raw.PRACHFrequencyEstimate_Hz = double(raw.EstimatedCFO_Hz);
    return;
end

if ismember("PRACHFrequencyEstimationEnabled", vars) && ...
        ~any(localLogical(raw.PRACHFrequencyEstimationEnabled))
    raw.PRACHFrequencyEstimate_Hz = NaN(height(raw), 1);
end
end

function identity = localIdentity(scfg, cfg, runtimeIdentity)
identity = struct( ...
    "ScenarioID", localScenarioID(scfg), ...
    "ConfigHash", lower(localConfigHash(scfg)), ...
    "RunID", strtrim(string(sixgr.util.structGet(runtimeIdentity, ...
        "RunID", sixgr.util.structGet(cfg, "run.runTag", "")))), ...
    "ExecutionID", strtrim(string(sixgr.util.structGet(runtimeIdentity, ...
        "ExecutionID", sixgr.util.structGet(cfg, "run.executionID", "")))), ...
    "CenterFrequencyHz", localRequiredNumber(cfg, ...
        ["frequency.centerFrequencyHz","frequency.center_frequency_hz","channel.fc_Hz"]), ...
    "BandwidthHz", localRequiredNumber(cfg, ...
        ["frequency.bandwidthHz","frequency.bandwidth_hz","channel.bandwidth_Hz"]), ...
    "SubcarrierSpacingHz", 1e3 * localRequiredNumber(cfg, ...
        ["channel.subcarrierSpacing_kHz","frame.scs_khz","numerology.scs_khz"]));
if strlength(identity.RunID) == 0
    error("sixgr:artifact:RuntimeRunIDMissing", ...
        "In-path initial-access artifact registration requires the current RunID.");
end
end

function value = localScenarioID(scfg)
if isobject(scfg) && isprop(scfg, "ScenarioID")
    value = strtrim(string(scfg.ScenarioID));
elseif isstruct(scfg)
    value = strtrim(string(sixgr.util.structGet(scfg, "scenario_id", ...
        sixgr.util.structGet(scfg, "meta.scenario_id", ""))));
else
    value = "";
end
if strlength(value) == 0
    error("sixgr:artifact:ScenarioIDMissing", ...
        "Runtime initial-access artifact registration requires ScenarioID.");
end
end

function value = localConfigHash(scfg)
if isobject(scfg) && isprop(scfg, "ConfigHash")
    value = strtrim(string(scfg.ConfigHash));
elseif isstruct(scfg)
    value = strtrim(string(sixgr.util.structGet(scfg, "ConfigHash", ...
        sixgr.util.structGet(scfg, "meta.configHash", ""))));
else
    value = "";
end
if strlength(value) ~= 64 || isempty(regexp(char(value), "^[0-9a-fA-F]{64}$", "once"))
    error("sixgr:artifact:ConfigHashMissing", ...
        "Runtime initial-access artifact registration requires a 64-character ConfigHash.");
end
end

function localRequireIdentity(T, column, expected)
observed = strtrim(string(T.(char(column))));
if any(ismissing(observed) | strlength(observed) == 0) || ...
        any(lower(observed) ~= lower(expected))
    error("sixgr:artifact:RawTrialIdentityMismatch", ...
        "In-memory PRACH trial %s does not match expected '%s'.", column, expected);
end
end

function value = localRequiredNumber(cfg, paths)
value = NaN;
for path = string(paths(:)).'
    candidate = sixgr.util.structGet(cfg, path, []);
    if ~isempty(candidate)
        candidate = double(candidate(1));
        if isfinite(candidate)
            value = candidate;
            break;
        end
    end
end
if ~isfinite(value)
    error("sixgr:artifact:RadioIdentityMissing", ...
        "Runtime initial-access evidence lacks radio identity for %s.", ...
        strjoin(string(paths), "|"));
end
end

function value = localLogicalColumn(T, name, defaultValue)
if ismember(name, string(T.Properties.VariableNames))
    value = localLogical(T.(char(name)));
else
    value = repmat(logical(defaultValue), height(T), 1);
end
end

function value = localLogical(raw)
if islogical(raw)
    value = raw(:);
elseif isnumeric(raw)
    value = isfinite(double(raw(:))) & double(raw(:)) ~= 0;
else
    value = ismember(lower(strtrim(string(raw(:)))), ...
        ["true","1","yes","pass","ok"]);
end
end

function row = localCoverage(artifactType, fileName, registered, sourceRows, status, reason)
row = struct("Domain","initial_access", ...
    "ArtifactType",string(artifactType), "FileName",string(fileName), ...
    "Registered",logical(registered), "SourceRows",double(sourceRows), ...
    "Status",string(status), "Reason",string(reason));
end
