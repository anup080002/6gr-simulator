function ok = testArtifactIntegrity()
%TESTARTIFACTINTEGRITY Verify manifest metadata fields are persisted.

setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

res = sixgr.core.SimResults(tmp);
res.setManifestMeta(struct( ...
    "strictMode", true, ...
    "approximationsUsed", ["none"], ...
    "calibrationSource", "lls_calibration", ...
    "configHash", "abc123", ...
    "codeVersion", "test", ...
    "missingArtifacts", ["x.csv"]));
res.finalize(true);

mFile = fullfile(tmp, "manifest.json");
assert(exist(mFile, "file") == 2, "Manifest not written");
txt = fileread(mFile);
M = jsondecode(txt);
assert(isfield(M, "strictMode"), "Manifest missing strictMode");
assert(isfield(M, "approximationsUsed"), "Manifest missing approximationsUsed");
assert(isfield(M, "calibrationSource"), "Manifest missing calibrationSource");
assert(isfield(M, "configHash"), "Manifest missing configHash");
assert(isfield(M, "codeVersion"), "Manifest missing codeVersion");
assert(isfield(M, "missingArtifacts"), "Manifest missing missingArtifacts");
ok = true;
end
