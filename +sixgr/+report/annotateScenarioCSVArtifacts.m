function summary = annotateScenarioCSVArtifacts(runFolder, scenarioID, configHash, runnerProfile)
%ANNOTATESCENARIOCSVARTIFACTS Add scenario identity to mutable report CSVs.
%   Runtime evidence CSVs are append-only, versioned journal projections.
%   Their schemas are owned by RuntimeEvidenceBus and must never be changed
%   by report annotation. Component mirrors are also excluded because they
%   must remain byte-identical to their canonical published artifacts.

runFolder = string(runFolder);
scenarioID = string(scenarioID);
configHash = string(configHash);
runnerProfile = string(runnerProfile);

componentMirrorRoots = ["prach","initial_access","ssb","pdcch", ...
    "pdsch","pusch","pucch","reference_signals","mimo", ...
    "frame_grid","waveform","l3","channel","rf", ...
    "mac_harq_scheduler","l2","traffic","validation", ...
    "component_anchors"];
immutableRoots = ["runtime", componentMirrorRoots];

summary = struct( ...
    "ScannedCount", 0, ...
    "AnnotatedCount", 0, ...
    "SkippedImmutableCount", 0, ...
    "UnreadableCount", 0);

files = dir(fullfile(runFolder, "**", "*.csv"));
normalizedRoot = strip(replace(runFolder, "\", "/"), "right", "/");
for i = 1:numel(files)
    summary.ScannedCount = summary.ScannedCount + 1;
    pathValue = string(fullfile(files(i).folder, files(i).name));
    normalizedFile = replace(pathValue, "\", "/");
    relativePath = normalizedFile;
    if startsWith(lower(normalizedFile), lower(normalizedRoot + "/"))
        relativePath = extractAfter(normalizedFile, strlength(normalizedRoot) + 1);
    end
    topLevel = extractBefore(relativePath + "/", "/");
    if any(lower(topLevel) == lower(immutableRoots))
        summary.SkippedImmutableCount = summary.SkippedImmutableCount + 1;
        continue;
    end

    try
        tableValue = readtable(pathValue, 'Delimiter', ',', ...
            'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
    catch
        summary.UnreadableCount = summary.UnreadableCount + 1;
        continue;
    end

    changed = false;
    variableNames = string(tableValue.Properties.VariableNames);
    if ~any(variableNames == "ScenarioID")
        tableValue = addvars(tableValue, localConstantColumn(height(tableValue), scenarioID), ...
            'Before', 1, 'NewVariableNames', 'ScenarioID');
        changed = true;
    end
    variableNames = string(tableValue.Properties.VariableNames);
    if ~any(variableNames == "ConfigHash")
        tableValue = addvars(tableValue, localConstantColumn(height(tableValue), configHash), ...
            'Before', min(2, width(tableValue) + 1), 'NewVariableNames', 'ConfigHash');
        changed = true;
    end
    variableNames = string(tableValue.Properties.VariableNames);
    if ~any(variableNames == "RunnerProfile")
        tableValue = addvars(tableValue, localConstantColumn(height(tableValue), runnerProfile), ...
            'Before', min(3, width(tableValue) + 1), 'NewVariableNames', 'RunnerProfile');
        changed = true;
    end
    if changed
        sixgr.util.csvWriteTable(pathValue, tableValue);
        summary.AnnotatedCount = summary.AnnotatedCount + 1;
    end
end
end

function values = localConstantColumn(rowCount, value)
values = repmat(string(value), rowCount, 1);
end
