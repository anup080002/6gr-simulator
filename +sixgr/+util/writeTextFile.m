function writeTextFile(filePath, txt, varargin)
%WRITETEXTFILE Persist UTF-8 text locally and mirror it to the active sink.

p = inputParser;
p.addParameter("MimeType", "text/plain; charset=UTF-8", @(x)ischar(x) || isstring(x));
p.addParameter("ArtifactKind", "text", @(x)ischar(x) || isstring(x));
p.parse(varargin{:});
opt = p.Results;

filePath = char(string(filePath));
txt = char(string(txt));

sixgr.util.ensureDir(filePath);
fid = fopen(filePath, "w", "n", "UTF-8");
if fid < 0
    error("sixgr:util:writeTextFile:OpenFailed", "Cannot open for writing: %s", filePath);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, txt, "char");
clear cleanupObj;

% The staging copy is required by same-run reducers and failure recovery.
% MySQL remains the durable WebGUI artifact sink, but it must not replace
% the transaction-local file before finalization has finished reading it.
if sixgr.db.isArtifactStoreActive()
    try
        handled = sixgr.db.storeTextArtifact(filePath, txt, ...
            opt.MimeType, opt.ArtifactKind, struct());
        if ~handled
            warning("sixgr:util:writeTextFile:ArtifactStoreRejected", ...
                "The active artifact store did not accept text artifact '%s'.", ...
                string(filePath));
        end
    catch ME
        warning("sixgr:util:writeTextFile:ArtifactStoreMirrorFailed", ...
            "Local text '%s' was written, but DB artifact mirroring failed: %s", ...
            string(filePath), string(ME.message));
    end
end
end
