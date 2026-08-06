function T = canonicalizeLLSLiveSignalChainTable(scopeToken, T)
%CANONICALIZELLSLIVESIGNALCHAINTABLE Fill blank semantic fields truthfully.
% This helper is used by live exporters and post-hoc rehydration so
% persisted signal-chain tables do not carry structurally blank semantic
% columns when the active runtime simply did not emit those fields.

if nargin < 2 || ~istable(T) || isempty(T)
    if nargin < 2 || ~istable(T)
        T = table();
    end
    return;
end

scopeToken = lower(regexprep(char(string(scopeToken)), "[^a-z0-9]+", "_"));
names = string(T.Properties.VariableNames);
for i = 1:numel(names)
    fieldName = char(names(i));
    if sixgr.truth.isImmutableIdentityField(fieldName)
        % Missing provenance identity must remain visibly missing so the
        % strict identity gate can fail closed.  Never decorate it with a
        % semantic availability token.
        continue;
    end
    rawCol = T.(fieldName);
    if ~localIsStringLikeColumn(rawCol)
        continue;
    end
    values = string(rawCol);
    normalized = lower(strtrim(fillmissing(values, "constant", "")));
    blankMask = ismissing(values) | strlength(normalized) == 0 | normalized == "nan" | normalized == "<missing>";
    if ~any(blankMask)
        continue;
    end
    companionMask = localCompanionAvailabilityMask(T, fieldName);
    fillValues = localSemanticFillValues(fieldName, scopeToken, companionMask);
    assignMask = blankMask & strlength(fillValues) > 0;
    if any(assignMask)
        values(assignMask) = fillValues(assignMask);
        T.(fieldName) = values;
    end
end
keepMask = false(1, numel(names));
for i = 1:numel(names)
    col = T.(char(names(i)));
    keepMask(i) = any(localColumnAvailabilityMask(col)) && ~localColumnContainsOnlyInactiveSentinels(col);
end
if localPreserveDeclaredSchema(scopeToken)
    keepMask(:) = true;
end
if any(~keepMask)
    T(:, ~keepMask) = [];
end
end

function tf = localPreserveDeclaredSchema(scopeToken)
scope = lower(string(scopeToken));
tf = any(scope == ["dl_pdsch_trials", "ul_pusch_trials", "pdcch_trials", ...
    "pucch_trials", "prach_trials", "pbch_trials", "srs_trials", "trs_trials", ...
    "pdcch", "pucch", "prach", "pbch", "srs", "trs", ...
    "channel_state", "channel_estimation", "modulation_demodulation", "tx_rx_stage_trace"]);
end

function tf = localIsStringLikeColumn(col)
tf = isstring(col) || ischar(col) || iscell(col) || iscategorical(col);
end

function mask = localCompanionAvailabilityMask(T, fieldName)
nRows = height(T);
mask = false(nRows, 1);
base = regexprep(lower(char(string(fieldName))), "(source|valuerole|valuestatus|nareason|definition)$", "");
if strlength(string(base)) == 0
    return;
end
names = string(T.Properties.VariableNames);
for i = 1:numel(names)
    candidate = char(names(i));
    candidateLower = lower(candidate);
    if strcmpi(candidate, fieldName)
        continue;
    end
    if ~strcmp(candidateLower, base) && ~startsWith(candidateLower, base)
        continue;
    end
    if ~isempty(regexp(candidateLower, "(source|valuerole|valuestatus|nareason|definition)$", "once"))
        continue;
    end
    mask = mask | localColumnAvailabilityMask(T.(candidate));
end
end

function mask = localColumnAvailabilityMask(col)
if isnumeric(col)
    mask = isfinite(double(col));
    return;
end
if islogical(col)
    mask = true(numel(col), 1);
    return;
end
try
    vals = string(col);
    mask = strlength(strtrim(vals)) > 0;
catch
    mask = false(numel(col), 1);
end
mask = reshape(logical(mask), [], 1);
end

function tf = localColumnContainsOnlyInactiveSentinels(col)
tf = false;
if ~(isstring(col) || ischar(col) || iscell(col) || iscategorical(col))
    return;
end
try
    vals = string(col);
catch
    return;
end
normalized = lower(strtrim(fillmissing(vals, "constant", "")));
    mask = strlength(normalized) > 0 & normalized ~= "nan" & normalized ~= "<missing>";
    if ~any(mask)
        return;
    end
    uniqueVals = unique(normalized(mask), "stable");
    inactivePrefixes = ["not_recorded_by_active_", "not_emitted_by_active_", "field_not_emitted_by_active_", "not_applicable_for_active_", "not_applicable"];
    tf = all(arrayfun(@(token) any(token == "not_applicable" | startsWith(token, inactivePrefixes)), uniqueVals));
end

function fill = localSemanticFillValues(fieldName, scopeToken, companionMask)
nRows = numel(companionMask);
fieldName = lower(char(string(fieldName)));
scope = string(scopeToken);
fill = strings(nRows, 1);
if startsWith(fieldName, "interferencechannel")
    % These columns describe explicit runtime interferer channel objects. In
    % a no-overlap/no-interferer slot the truthful value is blank/missing,
    % not an inactive sentinel that looks like a measured provenance token.
    return;
end
if endsWith(fieldName, "source")
    fill(companionMask) = "active_" + scope + "_runtime_table";
    fill(~companionMask) = "not_emitted_by_active_" + scope + "_runtime";
elseif endsWith(fieldName, "valuerole")
    fill(companionMask) = "runtime_observation";
    fill(~companionMask) = "not_available";
elseif endsWith(fieldName, "valuestatus")
    fill(companionMask) = "available";
    fill(~companionMask) = "not_emitted_by_active_" + scope + "_runtime";
elseif strcmp(fieldName, "nareason")
    % Row-level lifecycle NAReason is intentionally blank for finalized
    % rows; only field-specific *NAReason columns should receive sentinels.
    return;
elseif endsWith(fieldName, "nareason")
    fill(companionMask) = "not_required_when_metric_present";
    fill(~companionMask) = "field_not_emitted_by_active_" + scope + "_runtime";
elseif endsWith(fieldName, "definition")
    fill(companionMask) = "derived_from_active_" + scope + "_runtime_table";
    fill(~companionMask) = "not_emitted_by_active_" + scope + "_runtime";
elseif contains(fieldName, "blocker")
    fill(:) = "not_blocked_in_active_" + scope + "_runtime";
elseif contains(fieldName, "limitation")
    fill(:) = "no_additional_" + scope + "_limitation_recorded";
elseif contains(fieldName, "beam") || contains(fieldName, "precoder") || ...
        contains(fieldName, "interferer") || contains(fieldName, "antenna") || ...
        contains(fieldName, "channelarray") || contains(fieldName, "geometryadapter") || ...
        contains(fieldName, "authority") || contains(fieldName, "interference")
    fill(:) = "not_recorded_by_active_" + scope + "_runtime";
end
end
