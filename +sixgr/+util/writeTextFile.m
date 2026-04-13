function writeTextFile(filePath, txt, varargin)
%WRITETEXTFILE Persist a UTF-8 text artifact to the active sink.

p = inputParser;
p.addParameter("MimeType", "text/plain; charset=UTF-8", @(x)ischar(x) || isstring(x));
p.addParameter("ArtifactKind", "text", @(x)ischar(x) || isstring(x));
p.parse(varargin{:});
opt = p.Results;

filePath = char(string(filePath));
txt = char(string(txt));

if sixgr.db.storeTextArtifact(filePath, txt, opt.MimeType, opt.ArtifactKind, struct())
    return;
end

sixgr.util.ensureDir(filePath);
fid = fopen(filePath, "w", "n", "UTF-8");
if fid < 0
    error("sixgr:util:writeTextFile:OpenFailed", "Cannot open for writing: %s", filePath);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, txt, "char");
end
