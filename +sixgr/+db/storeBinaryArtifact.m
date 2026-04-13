function handled = storeBinaryArtifact(filePath, bytes, artifactKind, mimeType, metadata)
if nargin < 5
    metadata = struct();
end
handled = sixgr.db.artifactStore("store_binary", filePath, bytes, artifactKind, mimeType, metadata);
end
