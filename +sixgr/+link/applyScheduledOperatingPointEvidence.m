function T = applyScheduledOperatingPointEvidence(T)
%APPLYSCHEDULEDOPERATINGPOINTEVIDENCE Publish the executed grant operating point.
%
% The scheduled operating point is materialized only when the raw row says
% an adaptive scheduler decision was scheduled and the executed waveform is
% explicitly bound to a frozen scheduler grant.  This is not a reconstruction
% from receiver output: MCSIndex/Modulation are the grant-owned values used by
% the Tx chain.  Missing grant authority remains missing and fails downstream.

if ~istable(T)
    error("sixgr:link:InvalidScheduledOperatingPointTable", ...
        "Scheduled operating-point evidence requires a MATLAB table.");
end

n = height(T);
scheduledMCS = localNumber(T, "ScheduledMCS", n);
scheduledMCSIndex = localNumber(T, "ScheduledMCSIndex", n);
scheduledModulation = localText(T, "ScheduledModulation", n);
scheduledSource = localText(T, "ScheduledOperatingPointSource", n);
status = localText(T, "ScheduledOperatingPointEvidenceStatus", n);

adaptive = localLogical(T, "AdaptiveMode", n);
scheduled = localLogical(T, "LinkAdaptationScheduled", n);
transmittedMCS = localNumberFirst(T, ["MCSIndex","MCS"], n);
transmittedModulation = localTextFirst(T, ["Modulation"], n);
grantSource = localTextFirst(T, ...
    ["GrantOperatingPointSource","MCSAuthority"], n);
grantContext = localTextFirst(T, ...
    ["GrantContextId","FrozenGrantContextId"], n);
frozenGrantContext = localText(T, "FrozenGrantContextId", n);
pdcchGrantBound = localLogical(T, "PDCCHGrantBindingOk", n);

% The immutable frozen-grant identifier (or an explicit successful PDCCH
% binding) is execution evidence even when GrantOperatingPointSource keeps
% the upstream selection policy, for example cqi_link_adaptation.  Requiring
% that policy label itself to contain "scheduler_grant" caused real coupled
% trials to lose their scheduled MCS/modulation lineage.
executedFrozenGrant = contains(lower(grantSource), "scheduler_grant") | ...
    strlength(strtrim(frozenGrantContext)) > 0 | pdcchGrantBound;
grantBound = adaptive & scheduled & isfinite(transmittedMCS) & ...
    strlength(strtrim(transmittedModulation)) > 0 & ...
    executedFrozenGrant & ...
    strlength(strtrim(grantContext)) > 0;

priorComparable = isfinite(scheduledMCS) & ...
    strlength(strtrim(scheduledModulation)) > 0;
priorConflict = grantBound & priorComparable & ...
    (scheduledMCS ~= transmittedMCS | ...
    upper(strtrim(scheduledModulation)) ~= ...
    upper(strtrim(transmittedModulation)));

% A pre-grant pass may have left provisional or missing-status values in
% these columns.  Once the immutable grant is available, the exact values
% consumed by the Tx chain are authoritative and materialization must be
% idempotent rather than "fill blanks only".
scheduledMCS(grantBound) = transmittedMCS(grantBound);
scheduledMCSIndex(grantBound) = transmittedMCS(grantBound);
scheduledModulation(grantBound) = transmittedModulation(grantBound);
sourceValue = repmat("scheduler_grant", n, 1);
selectionPolicy = grantBound & strlength(strtrim(grantSource)) > 0 & ...
    ~contains(lower(grantSource), "scheduler_grant");
sourceValue(selectionPolicy) = "scheduler_grant_from_" + ...
    lower(strtrim(grantSource(selectionPolicy)));
alreadyCanonical = grantBound & contains(lower(grantSource), "scheduler_grant");
sourceValue(alreadyCanonical) = grantSource(alreadyCanonical);
scheduledSource(grantBound) = sourceValue(grantBound);

notApplicable = ~adaptive | ~scheduled;
status(notApplicable & strlength(status) == 0) = ...
    "not_applicable_no_adaptive_scheduled_decision";
status(grantBound) = "materialized_from_executed_frozen_scheduler_grant";
missingEvidence = adaptive & scheduled & ~grantBound;
status(missingEvidence & strlength(status) == 0) = ...
    "missing_frozen_scheduler_grant_operating_point_evidence";

matches = false(n, 1);
comparable = isfinite(scheduledMCS) & isfinite(transmittedMCS) & ...
    strlength(strtrim(scheduledModulation)) > 0 & ...
    strlength(strtrim(transmittedModulation)) > 0;
matches(comparable) = scheduledMCS(comparable) == transmittedMCS(comparable) & ...
    upper(strtrim(scheduledModulation(comparable))) == ...
    upper(strtrim(transmittedModulation(comparable)));
conflict = priorConflict | (grantBound & comparable & ~matches);
status(conflict) = "frozen_scheduler_grant_operating_point_conflict";
matches(conflict) = false;

T.ScheduledMCS = scheduledMCS;
T.ScheduledMCSIndex = scheduledMCSIndex;
T.ScheduledModulation = scheduledModulation;
T.ScheduledOperatingPointSource = scheduledSource;
T.ScheduledOperatingPointEvidenceStatus = status;
T.ScheduledOperatingPointMatchesTransmitted = matches;
end

function values = localNumber(T, name, n)
if ismember(name, string(T.Properties.VariableNames))
    values = double(T.(char(name)));
    values = values(:);
else
    values = nan(n, 1);
end
end

function values = localNumberFirst(T, names, n)
values = nan(n, 1);
for name = names
    candidate = localNumber(T, name, n);
    missing = ~isfinite(values) & isfinite(candidate);
    values(missing) = candidate(missing);
end
end

function values = localText(T, name, n)
if ismember(name, string(T.Properties.VariableNames))
    values = string(T.(char(name)));
    values = values(:);
else
    values = strings(n, 1);
end
end

function values = localTextFirst(T, names, n)
values = strings(n, 1);
for name = names
    candidate = localText(T, name, n);
    missing = strlength(strtrim(values)) == 0 & ...
        strlength(strtrim(candidate)) > 0;
    values(missing) = candidate(missing);
end
end

function values = localLogical(T, name, n)
if ~ismember(name, string(T.Properties.VariableNames))
    values = false(n, 1);
    return;
end
input = T.(char(name));
if islogical(input)
    values = input(:);
elseif isnumeric(input)
    input = double(input(:));
    values = isfinite(input) & input ~= 0;
else
    token = lower(strtrim(string(input(:))));
    values = ismember(token, ["1","true","yes","pass","passed","ok"]);
end
end
