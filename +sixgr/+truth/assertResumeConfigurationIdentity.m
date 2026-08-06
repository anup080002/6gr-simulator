function evidence = assertResumeConfigurationIdentity(runFolder, expectedScenarioID, expectedConfigHash)
%ASSERTRESUMECONFIGURATIONIDENTITY Bind resume to persisted PHY row identity.

% A completed-runtime finalization retry is allowed to rewrite derived
% artifacts, including resolved snapshots, only when the supplied resolved
% scenario is exactly the one recorded on canonical DL/UL waveform rows.

runFolder = char(string(runFolder));
expectedScenarioID = strtrim(string(expectedScenarioID));
expectedConfigHash = lower(strtrim(string(expectedConfigHash)));
if ~isscalar(expectedScenarioID) || ~isscalar(expectedConfigHash) || ...
        strlength(expectedScenarioID) == 0 || strlength(expectedConfigHash) ~= 64
    error("sixgr:truth:resume:InvalidExpectedConfigurationIdentity", ...
        "Resume requires a nonempty scenario ID and a 64-character resolved configuration hash.");
end

layout = sixgr.report.resultLayout(runFolder);
specs = [ ...
    struct("Direction", "DL", "Path", string(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"))); ...
    struct("Direction", "UL", "Path", string(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv")))];
rows = repmat(struct("Direction", "", "Path", "", "RowCount", 0, ...
    "ScenarioID", "", "ConfigHash", "", "Status", ""), 0, 1);
for index = 1:numel(specs)
    pathValue = specs(index).Path;
    if exist(char(pathValue), "file") ~= 2
        continue;
    end
    try
        T = readtable(char(pathValue), "FileType", "text", "Delimiter", ",", ...
            "ReadVariableNames", true, "VariableNamingRule", "preserve");
    catch ME
        error("sixgr:truth:resume:UnreadableConfigurationIdentityEvidence", ...
            "Unable to read persisted %s runtime evidence %s: %s", ...
            specs(index).Direction, pathValue, ME.message);
    end
    if isempty(T)
        continue;
    end
    required = ["ScenarioID", "ConfigHash"];
    if ~all(ismember(required, string(T.Properties.VariableNames)))
        error("sixgr:truth:resume:MissingConfigurationIdentityColumns", ...
            "Persisted %s runtime evidence must contain ScenarioID and ConfigHash: %s", ...
            specs(index).Direction, pathValue);
    end
    scenarioValues = unique(strtrim(string(T.ScenarioID)));
    hashValues = unique(lower(strtrim(string(T.ConfigHash))));
    scenarioValues = scenarioValues(strlength(scenarioValues) > 0);
    hashValues = hashValues(strlength(hashValues) > 0);
    if numel(scenarioValues) ~= 1 || numel(hashValues) ~= 1
        error("sixgr:truth:resume:AmbiguousConfigurationIdentity", ...
            "Persisted %s runtime evidence contains non-unique or blank configuration identity: %s", ...
            specs(index).Direction, pathValue);
    end
    if scenarioValues(1) ~= expectedScenarioID
        error("sixgr:truth:resume:ScenarioIdentityMismatch", ...
            "Persisted %s scenario '%s' does not match requested resume scenario '%s'.", ...
            specs(index).Direction, scenarioValues(1), expectedScenarioID);
    end
    if hashValues(1) ~= expectedConfigHash
        error("sixgr:truth:resume:ConfigurationHashMismatch", ...
            "Persisted %s configuration hash %s does not match requested resolved hash %s.", ...
            specs(index).Direction, hashValues(1), expectedConfigHash);
    end
    rows(end + 1, 1) = struct( ... %#ok<AGROW>
        "Direction", string(specs(index).Direction), "Path", pathValue, ...
        "RowCount", height(T), "ScenarioID", scenarioValues(1), ...
        "ConfigHash", hashValues(1), "Status", "exact_match");
end
if isempty(rows)
    error("sixgr:truth:resume:MissingConfigurationIdentityEvidence", ...
        "No nonempty canonical DL/UL runtime table exists under %s.", runFolder);
end

evidence = struct();
evidence.Ok = true;
evidence.ScenarioID = expectedScenarioID;
evidence.ConfigHash = expectedConfigHash;
evidence.Table = struct2table(rows, "AsArray", true);
evidence.EvidenceClass = "persisted_canonical_waveform_row_configuration_identity";
end
