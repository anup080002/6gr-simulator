function ok = testArtifactIntegrityManifest()
%TESTARTIFACTINTEGRITYMANIFEST Manifest hashes must bind final file bytes.

setup6GRSimToolkit("Verbose", false);
root = string(tempname);
mkdir(root);
cleanupObj = onCleanup(@() localRemoveTree(root)); %#ok<NASGU>

sourcePath = fullfile(root, "source.csv");
sixgr.util.csvWriteTable(sourcePath, table((1:3).', [10;20;30], ...
    'VariableNames', {'Index','Value'}));
manifestPath = fullfile(root, "artifact_manifest.csv");
rows = struct( ...
    "ArtifactPath", string(sourcePath), ...
    "SHA256", "stale", ...
    "ByteCount", -1, ...
    "Kind", "csv");

manifest = sixgr.artifact.writeIntegrityManifest(manifestPath, rows);
assert(exist(manifestPath, "file") == 2, ...
    "Integrity manifest was not written.");
assert(manifest.SHA256 == localFileSHA256(sourcePath), ...
    "Integrity manifest did not bind the final artifact bytes.");
info = dir(sourcePath);
assert(manifest.ByteCount == info(1).bytes, ...
    "Integrity manifest did not refresh the final artifact byte count.");
persisted = readtable(manifestPath, "TextType", "string", ...
    "VariableNamingRule", "preserve");
assert(height(persisted) == 1 && persisted.SHA256 == manifest.SHA256, ...
    "Persisted integrity manifest differs from the returned manifest.");
assert(~any(strcmpi(string(persisted.ArtifactPath), string(manifestPath))), ...
    "Integrity manifest must not contain a self-reference row.");

selfRow = rows;
selfRow.ArtifactPath = string(manifestPath);
localAssertError(@() sixgr.artifact.writeIntegrityManifest(manifestPath, selfRow), ...
    "sixgr:artifact:ManifestSelfReferenceForbidden");

missingRow = rows;
missingRow.ArtifactPath = fullfile(root, "missing.csv");
localAssertError(@() sixgr.artifact.writeIntegrityManifest(manifestPath, missingRow), ...
    "sixgr:artifact:ManifestArtifactMissing");
ok = true;
end

function localAssertError(fn, expectedId)
threw = false;
try
    fn();
catch ME
    threw = true;
    assert(string(ME.identifier) == string(expectedId), ...
        "Expected %s, received %s.", expectedId, ME.identifier);
end
assert(threw, "Expected error %s was not thrown.", expectedId);
end

function hash = localFileSHA256(pathValue)
fid = fopen(char(pathValue), "r");
assert(fid >= 0, "Unable to read test artifact.");
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
hash = string(sixgr.util.sha256Hex(fread(fid, inf, "*uint8")));
end

function localRemoveTree(root)
if exist(root, "dir") == 7
    rmdir(root, "s");
end
end
