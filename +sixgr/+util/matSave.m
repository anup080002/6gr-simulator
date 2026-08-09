function matSave(filePath, data)
%MATSAVE Unified MAT export (creates parent directories).
%
%   sixgr.util.matSave("results/run1/mat/run.mat", struct("cfg",cfg,"kpi",kpi))

arguments
    filePath {mustBeTextScalar}
    data
end

filePath = char(filePath);
sixgr.util.ensureDir(filePath);
targetDir = fileparts(filePath);
if isempty(targetDir)
    targetDir = pwd;
end
tmpPath = char(string(tempname(targetDir)) + ".mat");
cleanupTmp = onCleanup(@() localDeleteIfExists(tmpPath)); %#ok<NASGU>

payloadInfo = whos("data");
useV73 = ~isempty(payloadInfo) && double(payloadInfo.bytes) >= 1.75 * 1024^3;
try
    localSavePayload(tmpPath, data, useV73);
catch firstME
    if useV73
        rethrow(firstME);
    end
    % MATLAB's default MAT format cannot represent every large nested
    % payload even when WHOS underestimates the serialized size. Retry the
    % exact payload with HDF5-backed v7.3 instead of dropping run evidence.
    localDeleteIfExists(tmpPath);
    try
        localSavePayload(tmpPath, data, true);
    catch secondME
        secondME = addCause(secondME, firstME);
        rethrow(secondME);
    end
end

if sixgr.db.isArtifactStoreActive()
    handled = sixgr.db.captureFileArtifact(tmpPath, "mat_binary", ...
        "application/octet-stream", true, filePath);
    if ~handled
        error("sixgr:util:matSave:ArtifactStoreRejected", ...
            "The active artifact store did not accept MAT artifact '%s'.", filePath);
    end
    return;
end

localPublishWithRetry(tmpPath, filePath);
end

function localSavePayload(filePath, data, useV73)
args = {};
if useV73
    args = {"-v7.3"};
end

if builtin("isstruct", data) && isscalar(data)
    save(filePath, "-struct", "data", args{:});
else
    save(filePath, "data", args{:});
end
end

function localPublishWithRetry(tmpPath, filePath)
maxAttempts = 12;
lastMessage = "";
lastIdentifier = "";
for attempt = 1:maxAttempts
    [published, message, identifier] = movefile(tmpPath, filePath, "f");
    if published
        return;
    end
    lastMessage = string(message);
    lastIdentifier = string(identifier);
    if attempt < maxAttempts
        pause(min(0.05 * 2^(attempt - 1), 1.0));
    end
end
error("sixgr:util:matSave:AtomicPublishFailed", ...
    "Unable to atomically publish MAT '%s' after %d attempts (%s): %s", ...
    filePath, maxAttempts, lastIdentifier, lastMessage);
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
