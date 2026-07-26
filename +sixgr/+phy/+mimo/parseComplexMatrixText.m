function value = parseComplexMatrixText(textValue)
%PARSECOMPLEXMATRIXTEXT Parse frozen CSV matrix syntax without eval.
textValue = strtrim(string(textValue));
if strlength(textValue) == 0
    value = [];
    return;
end
rowTokens = split(textValue,";");
nRows = numel(rowTokens);
parsedRows = cell(nRows,1);
nColumns = NaN;
for rowIndex = 1:nRows
    columnTokens = split(strtrim(rowTokens(rowIndex)),",");
    if isnan(nColumns)
        nColumns = numel(columnTokens);
    elseif numel(columnTokens) ~= nColumns
        error("sixgr:mimo:PrecoderDimensionMismatch", ...
            "Frozen complex matrix text is not rectangular.");
    end
    row = complex(zeros(1,nColumns));
    for columnIndex = 1:nColumns
        token = replace(strtrim(columnTokens(columnIndex)),["i","J"],["j","j"]);
        parsed = sscanf(char(token),"%f%fj");
        if numel(parsed) == 2
            row(columnIndex) = complex(parsed(1),parsed(2));
        else
            scalar = str2double(token);
            if ~isfinite(scalar)
                error("sixgr:mimo:PrecoderDimensionMismatch", ...
                    "Invalid complex coefficient '%s'.",token);
            end
            row(columnIndex) = scalar;
        end
    end
    parsedRows{rowIndex} = row;
end
value = vertcat(parsedRows{:});
end
