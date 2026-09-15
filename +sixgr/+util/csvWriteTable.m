function csvWriteTable(filePath, T, varargin)
%CSVWRITETABLE Unified CSV export for simulator KPIs and logs.
%
%   sixgr.util.csvWriteTable("results/run1/csv/kpis.csv", T)

if ~(ischar(filePath) || (isstring(filePath) && isscalar(filePath)))
    error("sixgr:util:csvWriteTable:BadType", ...
        "filePath must be char or string scalar.");
end
if ~istable(T)
    error("sixgr:util:csvWriteTable:BadTable", "T must be a table.");
end
p = inputParser;
p.addParameter("PreserveSchema", false, ...
    @(x) islogical(x) && isscalar(x));
p.addParameter("RoundTripNumericText", false, ...
    @(x) islogical(x) && isscalar(x));
p.parse(varargin{:});

filePath = char(filePath);
if ~sixgr.util.persistenceEnabled()
    return;
end
% An evaluated-but-empty artifact still needs a decodable header.  Pruning
% structurally blank columns from a zero-row table removes its entire
% schema and produces a two-byte, unreadable CSV.  Preserve typed empty
% schemas automatically; callers must explicitly define the columns they
% claim to export.
if ~p.Results.PreserveSchema && height(T) > 0
    T = sixgr.util.pruneStructurallyBlankTableColumns(T);
end
sixgr.util.ensureDir(filePath);

targetDir = fileparts(filePath);
if isempty(targetDir)
    targetDir = pwd;
end
temporaryPath = [tempname(targetDir), '.csv'];
temporaryCleanup = onCleanup(@() localDeleteIfPresent(temporaryPath)); %#ok<NASGU>
wireTable = T;
if p.Results.RoundTripNumericText
    % Evidence at a decision boundary must survive decimal serialization.
    % Keep the original typed table for the database mirror.
    for name = string(T.Properties.VariableNames)
        values = T.(name);
        if isfloat(values)
            assert(isreal(values), "sixgr:util:csvWriteTable:ComplexRoundTrip", ...
                "RoundTripNumericText requires real floating-point columns.");
            wireTable.(name) = compose('%.17g', double(values));
        end
    end
end
try
    writetable(wireTable, temporaryPath, 'Delimiter', ',', 'QuoteStrings', true);
catch
    writetable(wireTable, temporaryPath);
end
localPublishWithRetry(temporaryPath, filePath);

if sixgr.db.isArtifactStoreActive()
    try
        sixgr.db.storeTableArtifact(filePath, T, ...
            "PreserveSchema", p.Results.PreserveSchema);
    catch ME
        warning("sixgr:util:csvWriteTable:ArtifactStoreMirrorFailed", ...
            "Local CSV '%s' was written, but DB artifact mirroring failed: %s", ...
            string(filePath), string(ME.message));
    end
end

end

function localPublishWithRetry(temporaryPath, filePath)
% Publish from the target directory so replacement remains on one volume.
% OneDrive and virus scanners can hold a short-lived read handle after a
% CSV is inspected.  Retrying the atomic replacement avoids truncating the
% canonical artifact and fails loudly if ownership is not recovered.
maxAttempts = 12;
lastMessage = "";
lastIdentifier = "";
for attempt = 1:maxAttempts
    [published, message, identifier] = movefile(temporaryPath, filePath, 'f');
    if published
        return;
    end
    lastMessage = string(message);
    lastIdentifier = string(identifier);
    if attempt < maxAttempts
        pause(min(0.05 * 2^(attempt - 1), 1.0));
    end
end
error("sixgr:util:csvWriteTable:AtomicPublishFailed", ...
    "Unable to atomically publish CSV '%s' after %d attempts (%s): %s", ...
    string(filePath), maxAttempts, lastIdentifier, lastMessage);
end

function localDeleteIfPresent(filePath)
if isfile(filePath)
    delete(filePath);
end
end
