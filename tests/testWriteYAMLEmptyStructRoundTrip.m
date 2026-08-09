function ok = testWriteYAMLEmptyStructRoundTrip()
%TESTWRITEYAMLEMPTYSTRUCTROUNDTRIP Nested empty maps remain valid YAML.

root = string(tempname);
mkdir(root);
cleanup = onCleanup(@() rmdir(root, "s")); %#ok<NASGU>
pathValue = fullfile(root, "nested_empty_map.yaml");
source = struct( ...
    "suite", struct( ...
        "full", struct("overlay", struct()), ...
        "items", {{struct(), struct("enabled", true)}}), ...
    "next_section", struct("enabled", true));

sixgr.lls6g.config.writeYAML(pathValue, source);
text = string(fileread(pathValue));
assert(contains(text, "overlay: {}"), ...
    "An empty mapping value must be serialized inline with its key.");
assert(contains(text, "- {}"), ...
    "An empty mapping in a sequence must be serialized inline with its item marker.");
assert(~contains(text, newline + "{}" + newline), ...
    "The writer emitted an unindented orphan mapping token.");

decoded = sixgr.lls6g.config.readConfigFile(pathValue);
assert(isstruct(decoded.suite.full.overlay) && ...
    isempty(fieldnames(decoded.suite.full.overlay)));
assert(isstruct(decoded.next_section) && logical(decoded.next_section.enabled));
ok = true;
end
