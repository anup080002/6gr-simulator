function matSave(filePath, data, options)
%MATSAVE Unified MAT export (creates parent directories).
%
%   sixgr.util.matSave("results/run1/mat/run.mat", struct("cfg",cfg,"kpi",kpi))

arguments
    filePath {mustBeTextScalar}
    data
    options.UseArtifactStore (1,1) logical = true
    options.ForceV73 (1,1) logical = false
    options.Compression (1,1) logical = true
    options.TimeChunkedVariables (1,:) string = strings(1,0)
end

matProfileScope=sixgr.runtime.ExecutionStageProfiler.scope("serialization","MAT_save_validate_publish"); %#ok<NASGU>
filePath = char(filePath);
sixgr.util.ensureDir(filePath);
targetDir = fileparts(filePath);
if isempty(targetDir)
    targetDir = pwd;
end
% Serialize the MAT payload on the local temporary volume first.  Writing a
% MAT file incrementally inside a synchronised result tree (for example a
% OneDrive workspace) can expose the still-open HDF5 file to the sync
% provider and has produced reproducible MATLAB:save:unableToWriteToMatFile
% failures. Only a closed file with a native MATLAB variable inventory and
% verified complete byte readbacks is published below. Inventory is not a
% substitute for the consumer's full reload/continuation validation.
tmpPath = char(string(tempname()) + ".mat");
cleanupTmp = onCleanup(@() localDeleteIfExists(tmpPath)); %#ok<NASGU>

assert(options.Compression || isempty(options.TimeChunkedVariables), ...
    'sixgr:util:matSave:CompressionPolicyConflict', ...
    'Time-chunked archives own their compression policy; do not combine overrides.');
useV73 = logical(options.ForceV73) || ~options.Compression || ~isempty(options.TimeChunkedVariables);
if ~useV73
    payloadInfo = whos("data");
    useV73 = ~isempty(payloadInfo) && double(payloadInfo.bytes) >= 1.75 * 1024^3;
end
if builtin("isstruct", data) && isscalar(data)
    expectedVariables = fieldnames(data);
else
    expectedVariables = {'data'};
end
try
    localSavePayload(tmpPath, data, useV73, options.TimeChunkedVariables,options.Compression);
catch firstME
    if useV73
        rethrow(firstME);
    end
    % MATLAB's default MAT format cannot represent every large nested
    % payload even when WHOS underestimates the serialized size. Retry the
    % exact payload with HDF5-backed v7.3 instead of dropping run evidence.
    localDeleteIfExists(tmpPath);
    try
        localSavePayload(tmpPath, data, true, options.TimeChunkedVariables,options.Compression);
    catch secondME
        secondME = addCause(secondME, firstME);
        rethrow(secondME);
    end
end

% Bind the single MAT inventory to immutable serialized bytes. Both
% destination readbacks below must match this exact validated payload.
sourceInfo = dir(tmpPath);
sourceBytes = localFileBytes(sourceInfo);
sourceHash = string(sixgr.util.sha256File(tmpPath));
localValidateSavedPayload(tmpPath, expectedVariables, 1);
if localFileBytes(dir(tmpPath)) ~= sourceBytes || ...
        string(sixgr.util.sha256File(tmpPath)) ~= sourceHash
    error("sixgr:util:matSave:ValidatedSourceChanged", ...
        "Serialized MAT source changed while its inventory was validated.");
end

if options.UseArtifactStore && sixgr.db.isArtifactStoreActive()
    handled = sixgr.db.captureFileArtifact(tmpPath, "mat_binary", ...
        "application/octet-stream", true, filePath);
    if ~handled
        error("sixgr:util:matSave:ArtifactStoreRejected", ...
            "The active artifact store did not accept MAT artifact '%s'.", filePath);
    end
    return;
end

localPublishValidatedCopy(tmpPath, filePath, sourceBytes, sourceHash);
end

function localSavePayload(filePath, data, useV73, timeChunkedVariables,compression)
serializationScope=sixgr.runtime.ExecutionStageProfiler.scope("serialization","MAT_native_save"); %#ok<NASGU>
if ~isempty(timeChunkedVariables)
    % Compression selection is explicit and applies only to the immutable
    % local staging file. All inventory, byte-hash and destination-readback
    % checks below remain identical to ordinary MAT publication.
    sixgr.util.writeTimeChunkedMATPayload(filePath,data,timeChunkedVariables);
    return;
end
args = {};
if useV73
    args = {"-v7.3"};
    if ~compression, args{end+1}="-nocompression"; end
end

if builtin("isstruct", data) && isscalar(data)
    save(filePath, "-struct", "data", args{:});
else
    save(filePath, "data", args{:});
end
end

function localValidateSavedPayload(filePath, expectedVariables, maxAttempts)
if nargin < 3
    maxAttempts = 1;
end
maxAttempts = max(1, round(double(maxAttempts)));
lastME = [];
for attempt = 1:maxAttempts
    try
        % WHOS -file can call LOADOBJ while calculating nested sizes/types.
        % For live checkpoints this reconstructs the channel/decoder/window
        % graph beside the active owners and can exhaust process memory.
        % WHO is MATLAB's native names-only inventory: reopen the MAT and
        % require the exact intended variables without constructing owners.
        % Keep every source/destination byte/hash check below unchanged.
        % Actual state restoration still uses LOAD and is covered by exact
        % CDL/RF/RNG/pending-observation/HARQ continuation regressions.
        payloadInventory = who("-file", filePath);
        if ~isequal(sort(payloadInventory(:)), sort(expectedVariables(:)))
            error("sixgr:util:matSave:VariableInventoryMismatch", ...
                "Serialized MAT inventory does not match the intended variables.");
        end
        return;
    catch ME
        lastME = ME;
        if attempt < maxAttempts
            pause(0.25);
        end
    end
end
wrapped = MException("sixgr:util:matSave:InvalidSerializedPayload", ...
    "MAT payload '%s' could not be reopened after serialization after %d attempt(s).", ...
    filePath, maxAttempts);
if ~isempty(lastME)
    wrapped = addCause(wrapped, lastME);
end
throw(wrapped);
end

function localPublishValidatedCopy(tmpPath, filePath, sourceBytes, sourceHash)
% Do not MOVE a local HDF5 MAT into a synchronised tree.  On OneDrive the
% cross-volume move can be acknowledged before the provider makes the
% destination locally reopenable.  COPY keeps the already-validated source
% alive until the destination bytes match the inventoried source.
%
% A sibling staging copy is validated first so a provider that cannot make
% newly copied bytes readable fails before an existing final artifact is
% replaced.  The final copy is then validated again; no retry can turn an
% unreadable payload into accepted evidence.
[targetDir, ~, targetExt] = fileparts(filePath);
stageId = erase(char(java.util.UUID.randomUUID()), "-");
% Keep the sibling name deliberately short.  A long canonical result name
% combined with a UUID pushed otherwise valid v7.3 paths beyond the Windows
% HDF5 backend's legacy path boundary before byte validation could start.
stagePath = fullfile(targetDir, sprintf("m_%s%s", stageId(1:12), targetExt));
cleanupStage = onCleanup(@() localDeleteIfExists(stagePath)); %#ok<NASGU>

localCopyWithRetry(tmpPath, stagePath, "StagingCopyFailed");
localValidatePublishedBytes(stagePath, sourceBytes, sourceHash, 4);
localCopyWithRetry(stagePath, filePath, "FinalCopyFailed");
localValidatePublishedBytes(filePath, sourceBytes, sourceHash, 8);
end

function localValidatePublishedBytes(publishedPath, sourceBytes, sourceHash, maxAttempts)
% The staged source has already passed MATLAB inventory validation.
% Stream every byte directly from each published destination and verify its
% SHA-256. This does not ask HDF5 to reopen a long pathname and avoids two
% full destination -> temporary-disk copies. Both complete destination
% readbacks remain mandatory; neither mtime nor size substitutes for SHA.
lastME = [];
for attempt = 1:max(1, round(double(maxAttempts)))
    try
        verifyInfo = dir(publishedPath);
        if isempty(verifyInfo) || double(verifyInfo.bytes) ~= sourceBytes
            error("sixgr:util:matSave:PublishedSizeMismatch", ...
                "Published MAT '%s' read back %g byte(s); expected %g.", ...
                publishedPath, localFileBytes(verifyInfo), sourceBytes);
        end
        verifyHash = string(sixgr.util.sha256File(publishedPath));
        if verifyHash ~= sourceHash || localFileBytes(dir(publishedPath))~=sourceBytes
            error("sixgr:util:matSave:PublishedHashMismatch", ...
                "Published MAT '%s' differs from the validated serialized payload.", ...
                publishedPath);
        end
        return;
    catch ME
        lastME = ME;
        if attempt < maxAttempts
            pause(min(0.1 * 2^(attempt - 1), 1));
        end
    end
end
wrapped = MException("sixgr:util:matSave:PublishedPayloadValidationFailed", ...
    "Published MAT '%s' could not be read back and validated after %d attempt(s).", ...
    publishedPath, maxAttempts);
if ~isempty(lastME)
    wrapped = addCause(wrapped, lastME);
end
throw(wrapped);
end

function bytes = localFileBytes(info)
if isempty(info)
    bytes = NaN;
else
    bytes = double(info(1).bytes);
end
end

function localCopyWithRetry(sourcePath, destinationPath, suffix)
maxAttempts = 6;
lastMessage = "";
lastIdentifier = "";
for attempt = 1:maxAttempts
    [published, message, identifier] = copyfile(sourcePath, destinationPath, "f");
    if published
        return;
    end
    lastMessage = string(message);
    lastIdentifier = string(identifier);
    if attempt < maxAttempts
        pause(min(0.05 * 2^(attempt - 1), 0.5));
    end
end
error("sixgr:util:matSave:" + string(suffix), ...
    "Unable to publish MAT copy '%s' -> '%s' after %d attempts (%s): %s", ...
    sourcePath, destinationPath, maxAttempts, lastIdentifier, lastMessage);
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
