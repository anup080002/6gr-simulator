function ok = testWriteYAMLStructArrayRoundTrip()
%TESTWRITEYAMLSTRUCTARRAYROUNDTRIP Preserve every mapping in YAML sequences.

root = string(tempname);
mkdir(root);
cleanup = onCleanup(@() rmdir(root, "s")); %#ok<NASGU>
pathValue = fullfile(root, "struct_array.yaml");
resources = repmat(struct( ...
    "id", 0, "format", 0, "starting_prb", 0), 1, 3);
resources(1) = struct("id", 0, "format", 0, "starting_prb", 0);
resources(2) = struct("id", 10, "format", 2, "starting_prb", 4);
resources(3) = struct("id", 12, "format", 4, "starting_prb", 12);
source = struct("pucch_resources", struct("resources", resources));

sixgr.lls6g.config.writeYAML(pathValue, source);
decoded = sixgr.lls6g.config.readConfigFile(pathValue);
actual = decoded.pucch_resources.resources;
assert(isstruct(actual) && numel(actual) == 3, ...
    "YAML round trip must preserve every struct-array element.");
assert(isequal(double([actual.id]), [0 10 12]));
assert(isequal(double([actual.format]), [0 2 4]));
assert(isequal(double([actual.starting_prb]), [0 4 12]));
ok = true;
end
