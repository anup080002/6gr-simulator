function [complete, missingPaths] = isStrictPRACHComponentAnchorComplete(anchorRoot)
%ISSTRICTPRACHCOMPONENTANCHORCOMPLETE Preflight resumable PRACH evidence.
%   This function checks only that the complete persisted evidence set is
%   present. restoreStrictPRACHComponentAnchor remains the authority for
%   identity, hash, schema and truth validation and still fails closed if
%   any present artifact is corrupt or belongs to another execution.

anchorRoot = char(string(anchorRoot));
required = [ ...
    fullfile(anchorRoot, "component_anchor_identity.json"); ...
    fullfile(anchorRoot, "reports", "json", "prach_conformance_summary.json"); ...
    fullfile(anchorRoot, "control", "csv", "prach_strict_artifact_manifest.csv"); ...
    fullfile(anchorRoot, "control", "csv", "prach_config_strict.csv"); ...
    fullfile(anchorRoot, "control", "csv", "prach_strict_trials.csv")];
present = arrayfun(@(p)isfile(p), string(required));
missingPaths = string(required(~present));
complete = isfolder(anchorRoot) && all(present);
end
