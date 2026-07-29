classdef FullStackSubcase
    %FULLSTACKSUBCASE Validated view of one contract-matrix row.
    methods (Static)
        function item = fromRow(row)
            required = ["SubcaseID","Name","Category","Direction", ...
                "Mandatory","RequiredCSV","RequiredPNG","WebGUISection"];
            missing = setdiff(required, string(row.Properties.VariableNames));
            if ~isempty(missing)
                error("FULLSTACK:InvalidSubcaseRow", ...
                    "Subcase row is missing columns: %s.", strjoin(missing, ", "));
            end
            item = table2struct(row);
            item.SubcaseID = string(item.SubcaseID);
            item.Name = string(item.Name);
            item.Category = string(item.Category);
            item.Direction = string(item.Direction);
            item.Mandatory = ismember(lower(string(item.Mandatory)), ...
                ["true","1","yes"]);
            item.RequiredCSV = localList(item.RequiredCSV);
            item.RequiredPNG = localList(item.RequiredPNG);
            item.WebGUISection = string(item.WebGUISection);
        end
    end
end

function out = localList(value)
out = strip(split(string(value), "|"));
out = out(strlength(out) > 0);
end
