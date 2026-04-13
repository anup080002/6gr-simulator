function matSave(filePath, data)
%MATSAVE Unified MAT export (creates parent directories).
%
%   sixgr.util.matSave("results/run1/mat/run.mat", struct("cfg",cfg,"kpi",kpi))

arguments
    filePath {mustBeTextScalar}
    data
end

filePath = char(filePath);
tmpPath = char(string(tempname) + ".mat");
cleanupTmp = onCleanup(@() localDeleteIfExists(tmpPath)); %#ok<NASGU>

if builtin("isstruct", data) && isscalar(data)
    save(tmpPath, "-struct", "data");
else
    save(tmpPath, "data");
end

fid = fopen(tmpPath, "r");
if fid < 0
    error("sixgr:util:matSave:OpenFailed", "Unable to read temporary MAT artifact '%s'.", tmpPath);
end
cleanupRead = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, "*uint8").';
if sixgr.db.storeBinaryArtifact(filePath, bytes, "mat_binary", "application/octet-stream", struct())
    return;
end

sixgr.util.ensureDir(filePath);
if builtin("isstruct", data) && isscalar(data)
    save(filePath, "-struct", "data");
else
    save(filePath, "data");
end

end

function localDeleteIfExists(filePath)
try
    if exist(filePath, "file") == 2
        warnState = warning("off", "all");
        cleanupWarn = onCleanup(@() warning(warnState)); %#ok<NASGU>
        delete(filePath);
    end
catch
end

end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:util:matSave:BadType","filePath must be char or string scalar.");
end
end
