function manifest = writeIntegrityManifest(manifestPath, rows)
%WRITEINTEGRITYMANIFEST Write an artifact manifest from final file bytes.
%
% The manifest is deliberately excluded from its own rows: a file cannot
% embed the SHA-256 of its final byte stream.  All other artifacts must
% exist, and their byte counts/hashes are refreshed after every producer,
% source sanitizer, and plot-lineage writer has completed.

manifestPath = char(string(manifestPath));
if isstruct(rows)
    manifest = struct2table(rows, "AsArray", true);
elseif istable(rows)
    manifest = rows;
else
    error("sixgr:artifact:ManifestRowsRequired", ...
        "Artifact manifest rows must be a struct array or table.");
end

names = string(manifest.Properties.VariableNames);
pathColumn = localFirstColumn(names, ["ArtifactPath","FilePath","Path"]);
hashColumn = localFirstColumn(names, ["SHA256","sha256"]);
byteColumn = localFirstColumn(names, ["ByteCount","byte_count"]);
if strlength(pathColumn) == 0 || strlength(hashColumn) == 0
    error("sixgr:artifact:ManifestSchemaInvalid", ...
        "Artifact manifests require a path column and SHA256 column.");
end

canonicalManifest = localCanonicalPath(manifestPath);
for i = 1:height(manifest)
    artifactPath = strtrim(string(manifest.(pathColumn)(i)));
    if strlength(artifactPath) == 0
        error("sixgr:artifact:ManifestArtifactPathMissing", ...
            "Artifact manifest row %d has no artifact path.", i);
    end
    canonicalArtifact = localCanonicalPath(artifactPath);
    if canonicalArtifact == canonicalManifest
        error("sixgr:artifact:ManifestSelfReferenceForbidden", ...
            "Artifact manifests cannot contain a self-hash row: %s", ...
            manifestPath);
    end
    if exist(canonicalArtifact, "file") ~= 2
        error("sixgr:artifact:ManifestArtifactMissing", ...
            "Artifact manifest row %d refers to a missing file: %s", ...
            i, char(canonicalArtifact));
    end
    manifest.(hashColumn)(i) = localFileSHA256(canonicalArtifact);
    if strlength(byteColumn) > 0
        info = dir(canonicalArtifact);
        manifest.(byteColumn)(i) = double(info(1).bytes);
    end
end
sixgr.util.csvWriteTable(manifestPath, manifest);
end

function name = localFirstColumn(names, candidates)
name = "";
for candidate = string(candidates(:)).'
    index = find(strcmpi(names, candidate), 1, "first");
    if ~isempty(index)
        name = names(index);
        return;
    end
end
end

function value = localCanonicalPath(pathValue)
value = string(char(java.io.File(char(string(pathValue))).getCanonicalPath()));
end

function hash = localFileSHA256(pathValue)
fid = fopen(char(pathValue), "r");
if fid < 0
    error("sixgr:artifact:ManifestArtifactUnreadable", ...
        "Unable to read manifest artifact: %s", char(pathValue));
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
hash = string(sixgr.util.sha256Hex(fread(fid, inf, "*uint8")));
end
