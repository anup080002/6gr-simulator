function value = readPDSCHVectorTable(fileName)
%READPDSCHVECTORTABLE Read a frozen Prompt-02 CSV without type coercion.

testRoot = fileparts(fileparts(mfilename("fullpath")));
path = fullfile(testRoot, "vectors", "pdsch", string(fileName));
assert(isfile(path), "Mandatory PDSCH vector file is missing: %s", path);
options = detectImportOptions(path, ...
    "Delimiter", ",", "VariableNamingRule", "preserve");
options = setvartype(options, options.VariableNames, "string");
value = readtable(path, options);
for i = 1:width(value)
    column = string(value.(value.Properties.VariableNames{i}));
    column(ismissing(column)) = "";
    value.(value.Properties.VariableNames{i}) = column;
end
end
