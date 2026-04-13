function handled = storeTextArtifact(filePath, txt, mimeType, artifactKind, metadata)
if nargin < 3
    mimeType = "text/plain; charset=UTF-8";
end
if nargin < 4
    artifactKind = "text";
end
if nargin < 5
    metadata = struct();
end
handled = sixgr.db.artifactStore("store_text", filePath, txt, mimeType, artifactKind, metadata);
end
