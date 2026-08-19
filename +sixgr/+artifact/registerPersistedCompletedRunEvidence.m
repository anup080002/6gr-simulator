function [coverage, runtimeIdentity] = registerPersistedCompletedRunEvidence( ...
        registry, result, scfg, cfg, recoveryRunTag)
%REGISTERPERSISTEDCOMPLETEDRUNEVIDENCE Re-register persisted runtime truth.
%
% Completed-run recovery is allowed to rebuild contract artifacts from the
% canonical Result saved by that exact execution.  This function rejects a
% caller that has not explicitly marked the Result as completed-run
% recovery authority, and it binds ScenarioID, ConfigHash, RunID, and
% ExecutionID to every surviving raw PHY table before anything is placed in
% the runtime-only EvidenceRegistry.  Existing CSVs are never read.

% The output retains persisted_completed_run_truth as an explicit evidence
% origin.  This is re-finalization of measured PHY evidence, not a new
% waveform execution and not proxy/fallback evidence.

arguments
    registry (1,1) sixgr.artifact.EvidenceRegistry
    result (1,1) struct
    scfg
    cfg (1,1) struct
    recoveryRunTag (1,1) string
end

if ~logical(sixgr.util.structGet(result, ...
        "RefinalizedFromPersistedCompletedRun", false))
    error("sixgr:artifact:PersistedCompletedRunAuthorityRequired", ...
        "Persisted artifact registration requires a Result loaded from " + ...
        "the completed run's canonical scenario_result.mat.");
end

expected = struct( ...
    "ScenarioID", localScenarioID(scfg), ...
    "ConfigHash", lower(localConfigHash(scfg)), ...
    "RunID", strtrim(recoveryRunTag));
if strlength(expected.RunID) == 0
    error("sixgr:artifact:PersistedRunIDMissing", ...
        "Completed-run artifact recovery requires the immutable logical RunID.");
end

raw = sixgr.util.structGet(result, "Link.RawTrials", struct());
namedTables = { ...
    "PDSCH", sixgr.util.structGet(raw, "DL", table()); ...
    "PUSCH", sixgr.util.structGet(raw, "UL", table()); ...
    "PRACH", sixgr.util.structGet(raw, "PRACH", table())};
observedExecutionIDs = strings(0, 1);
evidenceTableCount = 0;
for index = 1:size(namedTables, 1)
    domain = string(namedTables{index, 1});
    value = namedTables{index, 2};
    if ~(istable(value) && ~isempty(value))
        continue;
    end
    evidenceTableCount = evidenceTableCount + 1;
    localRequireExactIdentity(value, "ScenarioID", expected.ScenarioID, domain);
    localRequireExactIdentity(value, "ConfigHash", expected.ConfigHash, domain);
    localRequireExactIdentity(value, "RunID", expected.RunID, domain);
    observedExecutionIDs(end+1,1) = ... %#ok<AGROW>
        localUniqueIdentity(value, "ExecutionID", domain);
end
if evidenceTableCount == 0
    error("sixgr:artifact:PersistedRuntimeEvidenceMissing", ...
        "The completed Result has no nonempty PDSCH, PUSCH, or PRACH raw " + ...
        "waveform table to re-register.");
end
executionIDs = unique(observedExecutionIDs, "stable");
if numel(executionIDs) ~= 1
    error("sixgr:artifact:PersistedExecutionIdentityMismatch", ...
        "Persisted raw PHY tables contain conflicting ExecutionIDs: %s", ...
        strjoin(executionIDs, ", "));
end

runtimeIdentity = struct( ...
    "RunID", expected.RunID, ...
    "ExecutionID", executionIDs(1), ...
    "ConfigHash", expected.ConfigHash, ...
    "EvidenceOrigin", "persisted_completed_run_truth");
waveformCoverage = sixgr.artifact.registerWaveformLinkEvidence( ...
    registry, result, scfg, cfg, runtimeIdentity, ...
    "persisted_completed_run_truth");
initialAccessCoverage = sixgr.artifact.registerInitialAccessEvidence( ...
    registry, result, scfg, cfg, runtimeIdentity, ...
    "persisted_completed_run_truth");
coverage = [waveformCoverage; initialAccessCoverage];
end

function localRequireExactIdentity(T, name, expected, domain)
observed = localUniqueIdentity(T, name, domain);
if lower(observed) ~= lower(strtrim(string(expected)))
    error("sixgr:artifact:PersistedRuntimeIdentityMismatch", ...
        "Persisted %s %s '%s' does not match expected '%s'.", ...
        domain, name, observed, string(expected));
end
end

function value = localUniqueIdentity(T, name, domain)
if ~ismember(name, string(T.Properties.VariableNames))
    error("sixgr:artifact:PersistedRuntimeIdentityMissing", ...
        "Persisted %s evidence lacks required lifecycle column %s.", ...
        domain, name);
end
values = strtrim(string(T.(char(name))));
if any(ismissing(values) | strlength(values) == 0)
    error("sixgr:artifact:PersistedRuntimeIdentityMissing", ...
        "Persisted %s evidence contains a blank %s.", domain, name);
end
values = unique(values, "stable");
if numel(values) ~= 1
    error("sixgr:artifact:PersistedRuntimeIdentityMismatch", ...
        "Persisted %s evidence contains multiple %s values: %s", ...
        domain, name, strjoin(values, ", "));
end
value = values(1);
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
if ~isscalar(value) || strlength(value) == 0
    error("sixgr:artifact:ScenarioIDMissing", ...
        "Completed-run artifact recovery requires one ScenarioID.");
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
if ~isscalar(value) || strlength(value) ~= 64 || ...
        isempty(regexp(char(value), "^[0-9a-fA-F]{64}$", "once"))
    error("sixgr:artifact:ConfigHashMissing", ...
        "Completed-run artifact recovery requires one 64-character ConfigHash.");
end
end
