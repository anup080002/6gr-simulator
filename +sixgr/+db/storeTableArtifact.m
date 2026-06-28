function handled = storeTableArtifact(filePath, T)
%STORETABLEARTIFACT Persist a table artifact through the active DB sink.

handled = false;
if ~sixgr.util.persistenceEnabled() || ~sixgr.db.isArtifactStoreActive()
    return;
end

tmpPath = char(string(tempname) + ".csv");
cleanupTmp = onCleanup(@() localDeleteIfExists(tmpPath)); %#ok<NASGU>
sixgr.util.ensureDir(tmpPath);

try
    T = sixgr.util.pruneStructurallyBlankTableColumns(T);
    try
        writetable(T, tmpPath, "Delimiter", ",", "QuoteStrings", true);
    catch
        writetable(T, tmpPath);
    end

    fid = fopen(tmpPath, "r");
    if fid < 0
        error("sixgr:db:storeTableArtifact:ReadFailed", ...
            "Unable to read temporary CSV artifact '%s'.", tmpPath);
    end
    cleanupRead = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid, Inf, "*uint8").';

    metadata = struct( ...
        "row_count", height(T), ...
        "column_names", {cellstr(string(T.Properties.VariableNames(:)).')}, ...
        "variable_count", width(T), ...
        "source_path", char(string(filePath)));
    handled = sixgr.db.storeBinaryArtifact(filePath, bytes, ...
        "table_csv", "text/csv; charset=UTF-8", metadata);
catch ME
    error("sixgr:db:storeTableArtifact:Failed", ...
        "Failed to persist table artifact '%s': %s", string(filePath), ME.message);
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
