function csvWriteTable(filePath, T)
%CSVWRITETABLE Unified CSV export for simulator KPIs and logs.
%
%   sixgr.util.csvWriteTable("results/run1/csv/kpis.csv", T)

arguments
    filePath {mustBeTextScalar}
    T table
end

filePath = char(filePath);
if ~sixgr.util.persistenceEnabled()
    return;
end
T = sixgr.util.pruneStructurallyBlankTableColumns(T);
sixgr.util.ensureDir(filePath);

try
    writetable(T, filePath, 'Delimiter', ',', 'QuoteStrings', true);
catch
    writetable(T, filePath);
end

if sixgr.db.isArtifactStoreActive()
    try
        sixgr.db.storeTableArtifact(filePath, T);
    catch ME
        warning("sixgr:util:csvWriteTable:ArtifactStoreMirrorFailed", ...
            "Local CSV '%s' was written, but DB artifact mirroring failed: %s", ...
            string(filePath), string(ME.message));
    end
end

end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:util:csvWriteTable:BadType","filePath must be char or string scalar.");
end
end
