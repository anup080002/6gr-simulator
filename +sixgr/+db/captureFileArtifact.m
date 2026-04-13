function handled = captureFileArtifact(filePath, artifactKind, mimeType, deleteAfter, logicalPath)
if nargin < 4
    deleteAfter = true;
end
if nargin < 5
    logicalPath = filePath;
end
handled = sixgr.db.artifactStore("capture_file", filePath, artifactKind, mimeType, deleteAfter, logicalPath);
end
