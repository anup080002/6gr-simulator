classdef RunEvidenceLifecycle
    %RUNEVIDENCELIFECYCLE Immutable execution and isolated finalization roots.
    %
    % A raw execution is sealed once.  Every recovery/finalization receives a
    % new attempt directory.  Only a PASS attempt with a real artifact
    % manifest may atomically replace published/current.json.

    methods (Static)
        function raw = sealExecution(runFolder, metadata)
            runFolder = localRunRoot(runFolder);
            localRequireScalarStruct(metadata, "execution metadata");
            rawRoot = fullfile(runFolder, "raw");
            manifestPath = fullfile(rawRoot, "execution_manifest.json");
            if isfile(manifestPath)
                raw = localReadJSON(manifestPath);
                localRequireSameIdentity(raw, metadata);
                return;
            end
            if ~isfolder(rawRoot)
                mkdir(rawRoot);
            else
                presealEntries = string({localDirectoryEntries(rawRoot).name});
                unexpected = setdiff(presealEntries, "evidence");
                if ~isempty(unexpected)
                    error("sixgr:runtime:UnsealedRawEvidenceExists", ...
                        "Raw evidence contains unexpected pre-seal entries: %s", ...
                        strjoin(unexpected, "|"));
                end
            end

            runId = localRequiredText(metadata, "RunID");
            executionId = localRequiredText(metadata, "ExecutionID");
            configHash = localRequiredHash(metadata, "ConfigHash");
            executionStart = localRequiredText(metadata, "ExecutionStartUTC");
            executionEnd = localRequiredText(metadata, "ExecutionEndUTC");
            gitCommit = localRequiredText(metadata, "GitCommit");
            gitDirty = logical(sixgr.util.structGet(metadata, "GitDirty", false));
            patchHash = "";
            patchRelativePath = "";
            if gitDirty
                patchContent = string(sixgr.util.structGet(metadata, "PatchBundleContent", ""));
                if strlength(patchContent) == 0
                    error("sixgr:runtime:DirtyExecutionPatchRequired", ...
                        "A dirty execution cannot be sealed without PatchBundleContent.");
                end
                patchRelativePath = "source_patch.diff";
                patchPath = fullfile(rawRoot, patchRelativePath);
                localAtomicWriteText(patchPath, patchContent);
                patchHash = localFileSHA256(patchPath);
            end

            rawEvidenceRelativePath = string(sixgr.util.structGet(metadata, ...
                "RawEvidenceIndexRelativePath", ""));
            rawEvidenceHash = lower(string(sixgr.util.structGet(metadata, ...
                "RawEvidenceIndexSHA256", "")));
            rawEvidenceTableCount = double(sixgr.util.structGet(metadata, ...
                "RawEvidenceTableCount", 0));
            rawEvidenceRowCount = double(sixgr.util.structGet(metadata, ...
                "RawEvidenceRowCount", 0));
            if strlength(rawEvidenceRelativePath) > 0
                rawEvidencePath = fullfile(rawRoot, char(rawEvidenceRelativePath));
                localAssertChild(rawEvidencePath, rawRoot);
                if ~isfile(rawEvidencePath) || ...
                        strlength(rawEvidenceHash) ~= 64 || ...
                        localFileSHA256(rawEvidencePath) ~= rawEvidenceHash
                    error("sixgr:runtime:RawEvidenceIndexMismatch", ...
                        "Raw evidence index is missing or does not match its execution hash: %s", ...
                        rawEvidencePath);
                end
                if rawEvidenceTableCount < 1 || rawEvidenceRowCount < 1
                    error("sixgr:runtime:RawEvidenceIndexMismatch", ...
                        "Raw evidence metadata requires positive table and row counts.");
                end
            elseif isfolder(fullfile(rawRoot, "evidence"))
                error("sixgr:runtime:RawEvidenceIndexMismatch", ...
                    "Pre-seal raw evidence requires index metadata.");
            end

            manifest = struct( ...
                "SchemaName", "sixgr.raw_execution", ...
                "SchemaVersion", "1.0.0", ...
                "RunID", runId, ...
                "ExecutionID", executionId, ...
                "ConfigHash", configHash, ...
                "ExecutionStartUTC", executionStart, ...
                "ExecutionEndUTC", executionEnd, ...
                "GitCommit", gitCommit, ...
                "GitDirty", gitDirty, ...
                "PatchBundleRelativePath", patchRelativePath, ...
                "PatchBundleSHA256", patchHash, ...
                "RawEvidenceIndexRelativePath", rawEvidenceRelativePath, ...
                "RawEvidenceIndexSHA256", rawEvidenceHash, ...
                "RawEvidenceTableCount", rawEvidenceTableCount, ...
                "RawEvidenceRowCount", rawEvidenceRowCount, ...
                "SealedUTC", sixgr.util.utcNowISO8601(), ...
                "Immutable", true);
            localAtomicWriteJSON(manifestPath, manifest);
            raw = manifest;
            raw.ManifestPath = string(manifestPath);
            raw.ManifestSHA256 = localFileSHA256(manifestPath);
        end

        function attempt = beginFinalization(runFolder, metadata)
            runFolder = localRunRoot(runFolder);
            localRequireScalarStruct(metadata, "finalization metadata");
            rawManifestPath = fullfile(runFolder, "raw", "execution_manifest.json");
            if ~isfile(rawManifestPath)
                error("sixgr:runtime:RawExecutionNotSealed", ...
                    "Finalization requires a sealed raw execution: %s", rawManifestPath);
            end
            raw = localReadJSON(rawManifestPath);
            executionId = localRequiredText(metadata, "ExecutionID");
            if string(raw.ExecutionID) ~= executionId
                error("sixgr:runtime:FinalizationExecutionMismatch", ...
                    "Finalization execution %s does not match sealed execution %s.", ...
                    executionId, string(raw.ExecutionID));
            end
            finalizationRoot = fullfile(runFolder, "finalization");
            if ~isfolder(finalizationRoot)
                mkdir(finalizationRoot);
            end
            attemptNumber = localNextAttemptNumber(finalizationRoot);
            attemptId = "attempt_" + compose("%03d", attemptNumber);
            attemptRoot = fullfile(finalizationRoot, attemptId);
            if isfolder(attemptRoot) || isfile(attemptRoot)
                error("sixgr:runtime:FinalizationAttemptCollision", ...
                    "Finalization attempt already exists: %s", attemptRoot);
            end
            mkdir(attemptRoot);
            mkdir(fullfile(attemptRoot, "outputs"));
            mkdir(fullfile(attemptRoot, "logs"));
            finalizationId = localUUID();
            manifest = struct( ...
                "SchemaName", "sixgr.finalization_attempt", ...
                "SchemaVersion", "1.0.0", ...
                "RunID", string(raw.RunID), ...
                "ExecutionID", executionId, ...
                "FinalizationID", finalizationId, ...
                "AttemptID", attemptId, ...
                "RawManifestSHA256", localFileSHA256(rawManifestPath), ...
                "StartedUTC", sixgr.util.utcNowISO8601(), ...
                "Status", "IN_PROGRESS", ...
                "ImmutableRawRoot", "raw");
            localAtomicWriteJSON(fullfile(attemptRoot, "attempt_manifest.json"), manifest);
            attempt = struct( ...
                "RunFolder", string(runFolder), ...
                "AttemptRoot", string(attemptRoot), ...
                "OutputsRoot", string(fullfile(attemptRoot, "outputs")), ...
                "LogsRoot", string(fullfile(attemptRoot, "logs")), ...
                "RunID", string(raw.RunID), ...
                "ExecutionID", executionId, ...
                "FinalizationID", finalizationId, ...
                "AttemptID", attemptId, ...
                "RawManifestSHA256", string(manifest.RawManifestSHA256));
        end

        function terminal = failFinalization(attempt, failure)
            localValidateAttempt(attempt);
            if isa(failure, "MException")
                identifier = string(failure.identifier);
                message = string(failure.message);
                stack = string({failure.stack.name}).';
            elseif isstruct(failure)
                identifier = string(sixgr.util.structGet(failure, "Identifier", ""));
                message = string(sixgr.util.structGet(failure, "Message", ""));
                stack = string(sixgr.util.structGet(failure, "Stack", strings(0, 1)));
            else
                identifier = "sixgr:runtime:FinalizationFailure";
                message = string(failure);
                stack = strings(0, 1);
            end
            terminal = localTerminal(attempt, "FAIL", struct( ...
                "FailureIdentifier", identifier, ...
                "FailureMessage", message, ...
                "FailureStack", stack, ...
                "PublicationQualified", false));
        end

        function terminal = completeUnpublished(attempt, artifactManifestPath)
            % Functional completion is not publication qualification. Keep
            % the existing qualified-publication pointer byte-for-byte intact.
            localValidateAttempt(attempt);
            artifactManifestPath = localCanonical(artifactManifestPath);
            localAssertChild(artifactManifestPath, attempt.AttemptRoot);
            if ~isfile(artifactManifestPath)
                error("sixgr:runtime:FinalizationArtifactManifestMissing", ...
                    "Completion requires an attempt-owned artifact manifest.");
            end
            manifest = localReadJSON(artifactManifestPath);
            if ~isequal(sixgr.util.structGet(manifest,"ResultOk",false),true) || ...
                    string(sixgr.util.structGet(manifest,"ArtifactContractStatus","")) ~= "PASS" || ...
                    sixgr.util.structGet(manifest,"ArtifactContractRequiredFailureCount",Inf) ~= 0 || ...
                    ~isequal(sixgr.util.structGet(manifest,"PublicationQualified",true),false)
                error("sixgr:runtime:FunctionalCompletionEvidenceInvalid", ...
                    "Unpublished completion requires functional PASS, no required artifact failures, and explicit non-qualification.");
            end
            for field = ["RunID","ExecutionID","FinalizationID","AttemptID"]
                if string(sixgr.util.structGet(manifest,field,"")) ~= string(attempt.(field))
                    error("sixgr:runtime:FinalizationExecutionMismatch", ...
                        "Completion artifact identity mismatch: %s.",field);
                end
            end
            terminal = localTerminal(attempt,"PASS",struct( ...
                "ArtifactManifestRelativePath",string(localRelativePath( ...
                    attempt.AttemptRoot,artifactManifestPath)), ...
                "ArtifactManifestSHA256",localFileSHA256(artifactManifestPath), ...
                "FunctionalFinalizationStatus","PASS", ...
                "PublicationStatus","NOT_QUALIFIED", ...
                "Published",false,"PublicationQualified",false));
        end

        function terminal = publish(attempt, artifactManifestPath)
            localValidateAttempt(attempt);
            artifactManifestPath = localCanonical(artifactManifestPath);
            localAssertChild(artifactManifestPath, attempt.AttemptRoot);
            if ~isfile(artifactManifestPath)
                error("sixgr:runtime:FinalizationArtifactManifestMissing", ...
                    "Cannot publish without an attempt-owned artifact manifest: %s", ...
                    artifactManifestPath);
            end
            artifactHash = localFileSHA256(artifactManifestPath);
            terminal = localTerminal(attempt, "PASS", struct( ...
                "ArtifactManifestRelativePath", string(localRelativePath( ...
                    attempt.AttemptRoot, artifactManifestPath)), ...
                "ArtifactManifestSHA256", artifactHash, ...
                "PublicationQualified", true));
            publishedRoot = fullfile(attempt.RunFolder, "published");
            if ~isfolder(publishedRoot)
                mkdir(publishedRoot);
            end
            pointer = struct( ...
                "SchemaName", "sixgr.published_pointer", ...
                "SchemaVersion", "1.0.0", ...
                "RunID", attempt.RunID, ...
                "ExecutionID", attempt.ExecutionID, ...
                "FinalizationID", attempt.FinalizationID, ...
                "AttemptID", attempt.AttemptID, ...
                "AttemptRelativePath", string(localRelativePath( ...
                    attempt.RunFolder, attempt.AttemptRoot)), ...
                "ArtifactManifestSHA256", artifactHash, ...
                "PublishedUTC", sixgr.util.utcNowISO8601(), ...
                "Status", "PASS");
            localAtomicWriteJSON(fullfile(publishedRoot, "current.json"), pointer);
        end
    end
end

function terminal = localTerminal(attempt, status, details)
terminalPath = fullfile(attempt.AttemptRoot, "terminal_status.json");
if isfile(terminalPath)
    error("sixgr:runtime:FinalizationAttemptAlreadyTerminal", ...
        "Finalization attempt is already terminal: %s", terminalPath);
end
terminal = struct( ...
    "SchemaName", "sixgr.finalization_terminal", ...
    "SchemaVersion", "1.0.0", ...
    "RunID", attempt.RunID, ...
    "ExecutionID", attempt.ExecutionID, ...
    "FinalizationID", attempt.FinalizationID, ...
    "AttemptID", attempt.AttemptID, ...
    "Status", string(status), ...
    "EndedUTC", sixgr.util.utcNowISO8601(), ...
    "RawManifestSHA256", attempt.RawManifestSHA256);
names = fieldnames(details);
for index = 1:numel(names)
    terminal.(names{index}) = details.(names{index});
end
localAtomicWriteJSON(terminalPath, terminal);

% The attempt manifest is the lifecycle index used by recovery tooling.
% Leaving it IN_PROGRESS after an authoritative terminal record has been
% written makes a completed FAIL look resumable and a published PASS look
% abandoned.  Mirror only lifecycle state and immutable terminal pointers;
% the detailed failure/publication evidence remains in terminal_status.json.
attemptManifestPath = fullfile(attempt.AttemptRoot, "attempt_manifest.json");
attemptManifest = localReadJSON(attemptManifestPath);
attemptManifest.Status = string(status);
attemptManifest.EndedUTC = string(terminal.EndedUTC);
attemptManifest.TerminalStatusRelativePath = "terminal_status.json";
attemptManifest.PublicationQualified = logical(sixgr.util.structGet( ...
    terminal, "PublicationQualified", false));
if isfield(terminal, "FailureIdentifier")
    attemptManifest.FailureIdentifier = string(terminal.FailureIdentifier);
end
if isfield(terminal, "ArtifactManifestRelativePath")
    attemptManifest.ArtifactManifestRelativePath = ...
        string(terminal.ArtifactManifestRelativePath);
end
if isfield(terminal, "ArtifactManifestSHA256")
    attemptManifest.ArtifactManifestSHA256 = ...
        string(terminal.ArtifactManifestSHA256);
end
localAtomicWriteJSON(attemptManifestPath, attemptManifest);
end

function localValidateAttempt(attempt)
localRequireScalarStruct(attempt, "finalization attempt");
required = ["RunFolder", "AttemptRoot", "RunID", "ExecutionID", ...
    "FinalizationID", "AttemptID", "RawManifestSHA256"];
for name = required
    if ~isfield(attempt, name) || strlength(string(attempt.(name))) == 0
        error("sixgr:runtime:MalformedFinalizationAttempt", ...
            "Finalization attempt is missing %s.", name);
    end
end
localAssertChild(attempt.AttemptRoot, attempt.RunFolder);
manifestPath = fullfile(attempt.AttemptRoot, "attempt_manifest.json");
if ~isfile(manifestPath)
    error("sixgr:runtime:FinalizationAttemptManifestMissing", ...
        "Attempt manifest is missing: %s", manifestPath);
end
end

function number = localNextAttemptNumber(root)
listing = dir(fullfile(root, "attempt_*"));
numbers = zeros(0, 1);
for index = 1:numel(listing)
    if ~listing(index).isdir
        continue;
    end
    token = regexp(listing(index).name, '^attempt_(\d{3})$', 'tokens', 'once');
    if ~isempty(token)
        numbers(end + 1, 1) = str2double(token{1}); %#ok<AGROW>
    end
end
if isempty(numbers)
    number = 1;
else
    number = max(numbers) + 1;
end
end

function entries = localDirectoryEntries(root)
entries = dir(root);
entries = entries(~ismember(string({entries.name}), [".", ".."])) ;
end

function localRequireSameIdentity(raw, metadata)
fields = ["RunID", "ExecutionID", "ConfigHash", "GitCommit"];
for field = fields
    expected = string(sixgr.util.structGet(metadata, field, ""));
    actual = string(sixgr.util.structGet(raw, field, ""));
    if strlength(expected) == 0 || actual ~= expected
        error("sixgr:runtime:RawExecutionIdentityMismatch", ...
            "Sealed raw execution %s='%s' does not match requested '%s'.", ...
            field, actual, expected);
    end
end
end

function value = localRequiredText(metadata, field)
value = string(sixgr.util.structGet(metadata, field, ""));
if ~isscalar(value) || strlength(strtrim(value)) == 0
    error("sixgr:runtime:ExecutionMetadataMissing", ...
        "Execution metadata requires non-empty %s.", field);
end
end

function value = localRequiredHash(metadata, field)
value = lower(localRequiredText(metadata, field));
if strlength(value) ~= 64 || isempty(regexp(char(value), '^[0-9a-f]{64}$', 'once'))
    error("sixgr:runtime:ExecutionHashInvalid", ...
        "Execution metadata %s must be a 64-character SHA-256 digest.", field);
end
end

function localRequireScalarStruct(value, label)
if ~isstruct(value) || ~isscalar(value)
    error("sixgr:runtime:ScalarStructRequired", "%s must be a scalar struct.", label);
end
end

function root = localRunRoot(runFolder)
root = localCanonical(runFolder);
if isfile(root)
    error("sixgr:runtime:RunRootIsFile", "Run root is a file: %s", root);
end
if ~isfolder(root)
    mkdir(root);
end
end

function localAtomicWriteJSON(pathValue, value)
textValue = string(jsonencode(value, "PrettyPrint", true));
localAtomicWriteText(pathValue, textValue);
end

function localAtomicWriteText(pathValue, textValue)
folder = fileparts(char(string(pathValue)));
if ~isfolder(folder)
    mkdir(folder);
end
temporary = string(pathValue) + ".tmp." + localUUID();
cleanup = onCleanup(@() localDeleteFile(temporary)); %#ok<NASGU>
fid = fopen(temporary, "w");
if fid < 0
    error("sixgr:runtime:LifecycleWriteFailed", ...
        "Unable to open temporary lifecycle artifact: %s", temporary);
end
fileCleanup = onCleanup(@() localSafeClose(fid)); %#ok<NASGU>
fprintf(fid, "%s", char(textValue));
closeStatus = fclose(fid);
if closeStatus ~= 0
    error("sixgr:runtime:LifecycleWriteFailed", ...
        "Unable to close temporary lifecycle artifact: %s", temporary);
end
clear fileCleanup;
[ok, message] = movefile(temporary, pathValue, "f");
if ~ok
    error("sixgr:runtime:LifecyclePublishFailed", ...
        "Unable to atomically publish %s: %s", pathValue, message);
end
end

function value = localReadJSON(pathValue)
value = jsondecode(fileread(pathValue));
end

function hash = localFileSHA256(pathValue)
fid = fopen(pathValue, "rb");
if fid < 0
    error("sixgr:runtime:LifecycleHashReadFailed", ...
        "Unable to hash lifecycle artifact: %s", pathValue);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
hash = sixgr.util.sha256Hex(fread(fid, Inf, "*uint8"));
end

function localAssertChild(pathValue, ownerRoot)
pathValue = localCanonical(pathValue);
ownerRoot = localCanonical(ownerRoot);
if pathValue == ownerRoot || ...
        ~startsWith(pathValue, ownerRoot + string(filesep), "IgnoreCase", ispc)
    error("sixgr:runtime:LifecyclePathEscape", ...
        "Lifecycle path is outside its owner root %s: %s", ownerRoot, pathValue);
end
end

function relative = localRelativePath(root, pathValue)
root = localCanonical(root);
pathValue = localCanonical(pathValue);
localAssertChild(pathValue, root);
relative = extractAfter(pathValue, strlength(root) + strlength(string(filesep)));
end

function value = localCanonical(pathValue)
value = string(char(java.io.File(char(string(pathValue))).getCanonicalPath()));
end

function localDeleteFile(pathValue)
if isfile(pathValue)
    delete(pathValue);
end
end

function localSafeClose(fid)
try
    fclose(fid);
catch
end
end

function value = localUUID()
value = lower(string(char(java.util.UUID.randomUUID())));
end
