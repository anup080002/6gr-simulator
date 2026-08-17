function ok = testYAMLLongPathRoundTrip()
%TESTYAMLLONGPATHROUNDTRIP External Python must read MAX_PATH YAML files.

setup6GRSimToolkit("Verbose",false);
root = string(tempname);
cleanup = onCleanup(@() localRemove(root)); %#ok<NASGU>
pathValue = char(root);
segment = repmat('x',1,42);
while strlength(string(fullfile(pathValue,"scenario.yaml"))) < 265
    pathValue = fullfile(pathValue,segment);
end
mkdir(pathValue);
yamlPath = fullfile(pathValue,"scenario.yaml");
payload = struct("meta",struct("scenario_id","long_path_unit"), ...
    "value",17);
sixgr.lls6g.config.writeYAML(yamlPath,payload);
assert(strlength(string(char(java.io.File(yamlPath).getAbsolutePath()))) >= 260, ...
    "Fixture must exercise a Windows path at or above MAX_PATH.");
decoded = sixgr.lls6g.config.readConfigFile(yamlPath);
assert(string(decoded.meta.scenario_id)=="long_path_unit" && ...
    double(decoded.value)==17, ...
    "External Python YAML parsing must preserve values on a long path.");
ok=true;
fprintf("PASS testYAMLLongPathRoundTrip: external YAML reader supports Windows long paths.\n");
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue,"s");
end
end
