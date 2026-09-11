function T = csvReadTable(filePath, varargin)
%CSVREADTABLE Read a simulator CSV with an explicit comma contract.
%   MATLAB delimiter inference can misclassify semicolon-delimited array
%   text inside very wide, correctly quoted runtime CSV rows.  Canonical
%   simulator artifacts are always comma-delimited, so readers must state
%   that contract instead of relying on inference.

if ~(ischar(filePath) || (isstring(filePath) && isscalar(filePath)))
    error("sixgr:util:csvReadTable:BadType", ...
        "filePath must be char or string scalar.");
end

options = detectImportOptions(char(string(filePath)), ...
    "FileType", "text", ...
    "Delimiter", ",", ...
    "VariableNamingRule", "preserve", ...
    varargin{:});
% Simulator CSVs have one explicit header row. A binary payload is text,
% including leading zeroes and vectors far longer than flintmax. Conversion
% to double followed by string() irreversibly corrupts received evidence.
options.VariableNamesLine = 1;
options.DataLines = [2 Inf];
names = string(options.VariableNames);
vectors = endsWith(names,"BitVector","IgnoreCase",true) | ...
    endsWith(names,"BitErrorVector","IgnoreCase",true);
if any(vectors)
    options = setvartype(options,cellstr(names(vectors)),"string");
    options = setvaropts(options,cellstr(names(vectors)), ...
        "WhitespaceRule","preserve","EmptyFieldRule","missing");
end
T = readtable(char(string(filePath)), options);
end
