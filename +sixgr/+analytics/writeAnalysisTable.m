function writeAnalysisTable(filePath, T)
%WRITEANALYSISTABLE Write post-run analysis CSVs without pruning schemas.
%
% Analysis tables intentionally keep optional all-blank measurement columns so
% auditors can distinguish "not measured in this run" from "column not wired".

arguments
    filePath {mustBeTextScalar}
    T table
end

filePath = char(string(filePath));
sixgr.util.ensureDir(filePath);
if sixgr.db.isArtifactStoreActive()
    sixgr.db.storeTableArtifact(filePath, T);
end
try
    writetable(T, filePath, "Delimiter", ",", "QuoteStrings", true);
catch
    writetable(T, filePath);
end
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:analytics:writeAnalysisTable:BadType", "filePath must be char or string scalar.");
end
end
