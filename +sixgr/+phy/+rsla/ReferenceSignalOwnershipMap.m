classdef ReferenceSignalOwnershipMap
    %REFERENCESIGNALOWNERSHIPMAP Zero-based reference/data RE ledger.

    properties (SetAccess=private)
        Entries table
    end

    methods
        function obj = ReferenceSignalOwnershipMap()
            names = ["Slot","Symbol","PRB","Subcarrier","ResourceType", ...
                "ResourceID","OwnerUE","Port","OrthogonalityID","Status"];
            obj.Entries = array2table(strings(0,numel(names)), ...
                "VariableNames",cellstr(names));
        end

        function obj = add(obj,entry)
            required = ["Slot","Symbol","PRB","Subcarrier","ResourceType", ...
                "ResourceID","OwnerUE","Port","OrthogonalityID"];
            for name = required
                if ~isfield(entry,char(name))
                    error("RSLA:InvalidResourceOwnership", ...
                        "Ownership entry is missing %s.",name);
                end
            end
            coordinate = [double(entry.Slot),double(entry.Symbol), ...
                double(entry.PRB),double(entry.Subcarrier),double(entry.Port)];
            if any(~isfinite(coordinate)) || entry.Symbol<0 || entry.Symbol>13 || ...
                    entry.PRB<0 || entry.Subcarrier<0 || entry.Subcarrier>11 || ...
                    entry.Port<0
                error("RSLA:InvalidResourceOwnership", ...
                    "Ownership coordinates must be finite and zero based.");
            end
            same = str2double(obj.Entries.Slot)==entry.Slot & ...
                str2double(obj.Entries.Symbol)==entry.Symbol & ...
                str2double(obj.Entries.PRB)==entry.PRB & ...
                str2double(obj.Entries.Subcarrier)==entry.Subcarrier & ...
                str2double(obj.Entries.Port)==entry.Port;
            if any(same)
                orthogonal = obj.Entries.OrthogonalityID(same)== ...
                    string(entry.OrthogonalityID);
                if ~all(orthogonal)
                    error("RSLA:ResourceCollision", ...
                        "Non-orthogonal resources share the same zero-based RE.");
                end
            end
            row = array2table(strings(1,width(obj.Entries)), ...
                "VariableNames",obj.Entries.Properties.VariableNames);
            for name = required
                row.(name) = string(entry.(char(name)));
            end
            row.Status = "PASS";
            obj.Entries = [obj.Entries;row];
        end
    end
end
