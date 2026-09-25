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

% Extremely long received-evidence rows can exceed MATLAB's type-inference
% sample. Callers with a declared schema may supply ColumnTypes (a scalar
% struct mapping column names to import types); no values are supplied.
columnTypes = struct();
for k = numel(varargin)-1:-2:1
    if strcmpi(string(varargin{k}),"ColumnTypes")
        columnTypes = varargin{k+1};
        varargin(k:k+1) = [];
    end
end
assert(isstruct(columnTypes) && isscalar(columnTypes), ...
    'sixgr:util:csvReadTable:BadColumnTypes', ...
    'ColumnTypes must be a scalar struct of declared column import types.');
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
declaredNames = string(fieldnames(columnTypes));
assert(all(ismember(declaredNames,names)), ...
    'sixgr:util:csvReadTable:MissingDeclaredColumn', ...
    'CSV is missing a column required by ColumnTypes.');
for name = declaredNames(:)'
    options = setvartype(options,char(name),columnTypes.(name));
end
if ~isempty(declaredNames)
    options.ImportErrorRule = 'error';
end
vectors = endsWith(names,"BitVector","IgnoreCase",true) | ...
    endsWith(names,"BitErrorVector","IgnoreCase",true) | ...
    endsWith(names,"BitsJSON","IgnoreCase",true);
% These producer-owned fields serialize one variable-length vector per
% trial. An early rank-one row is NOT a scalar schema declaration. Wide
% runtime rows can exhaust detectImportOptions' sample before rank changes,
% which otherwise converts a later "a|b" into NaN during finalization.
numericVectorNames=["PostEqSINRPerLayer_dB","AgedPostEqSINRPerLayer_dB", ...
    "PredictedPUSCHPostEqSINRPerLayer_dB","ResidualInterLayerPowerPerLayer", ...
    "EVMPerLayer_rms","LayerSINRdB","PerLayerSINR_dB", ...
    "SelectedLayerSINR_dB","LayerSINR_dB","MeasuredPerLayerSINR_dB", ...
    "BeamScoreVector_dB","TopBeamIndexSet","TopBeamGainSet_dB"];
vectors=vectors | ismember(names,numericVectorNames);
if any(vectors)
    options = setvartype(options,cellstr(names(vectors)),"string");
    options = setvaropts(options,cellstr(names(vectors)), ...
        "WhitespaceRule","preserve","EmptyFieldRule","missing");
end
T = readtable(char(string(filePath)), options);
end
