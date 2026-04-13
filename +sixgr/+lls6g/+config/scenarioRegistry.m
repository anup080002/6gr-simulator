function T = scenarioRegistry(varargin)
%SCENARIOREGISTRY List available shipped 6G PHY LLS scenario configs.

ip = inputParser;
ip.addParameter("ScenarioRoot", fullfile(localRepoRoot(), "simulator", "configs", "scenarios"), @(x)ischar(x) || isstring(x));
ip.parse(varargin{:});

root = char(string(ip.Results.ScenarioRoot));
files = dir(fullfile(root, "*.yaml"));
rows = repmat(struct("ScenarioID","", "ConfigPath","", "RunnerProfile","", "Description",""), 0, 1);

for i = 1:numel(files)
    filePath = fullfile(files(i).folder, files(i).name);
    raw = sixgr.lls6g.config.readConfigFile(filePath);
    if isfield(raw, 'execution') || ~isfield(raw, 'scenario')
        continue;
    end
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "ScenarioID", string(sixgr.util.structGet(raw, "meta.scenario_id", files(i).name)), ...
        "ConfigPath", string(filePath), ...
        "RunnerProfile", string(sixgr.util.structGet(raw, "scenario.runner_profile", "")), ...
        "Description", string(sixgr.util.structGet(raw, "meta.description", "")));
end

if isempty(rows)
    T = table('Size', [0 4], ...
        'VariableTypes', {'string','string','string','string'}, ...
        'VariableNames', {'ScenarioID','ConfigPath','RunnerProfile','Description'});
else
    T = struct2table(rows);
end
end

function out = localRepoRoot()
here = fileparts(mfilename("fullpath"));
out = fileparts(fileparts(fileparts(here)));
end
