function csvWriteTable(filePath, T)
%CSVWRITETABLE Unified CSV export for simulator KPIs and logs.
%
%   sixgr.util.csvWriteTable("results/run1/csv/kpis.csv", T)

arguments
    filePath {mustBeTextScalar}
    T table
end

filePath = char(filePath);
T = sixgr.util.pruneStructurallyBlankTableColumns(T);
if sixgr.db.isArtifactStoreActive()
    sixgr.db.storeTableArtifact(filePath, T);
end
sixgr.util.ensureDir(filePath);

try
    writetable(T, filePath, 'Delimiter', ',', 'QuoteStrings', true);
catch
    writetable(T, filePath);
end

end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:util:csvWriteTable:BadType","filePath must be char or string scalar.");
end
end
