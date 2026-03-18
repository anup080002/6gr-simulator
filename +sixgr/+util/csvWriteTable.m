function csvWriteTable(filePath, T)
%CSVWRITETABLE Unified CSV export for simulator KPIs and logs.
%
%   sixgr.util.csvWriteTable("results/run1/csv/kpis.csv", T)

arguments
    filePath {mustBeTextScalar}
    T table
end

filePath = char(filePath);
sixgr.util.ensureDir(filePath);

writetable(T, filePath);

end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:util:csvWriteTable:BadType","filePath must be char or string scalar.");
end
end
