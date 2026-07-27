classdef CompatibilityAliasGenerator
    %COMPATIBILITYALIASGENERATOR Generate aliases from canonical owners.
    methods (Static)
        function out = apply(canonical,mapping)
            if ~istable(canonical) || ~(isstruct(mapping)&&isscalar(mapping))
                error("sixgr:validation:SchemaWrongType", ...
                    "Alias generation requires a table and scalar mapping struct.");
            end
            out = canonical;
            aliases = string(fieldnames(mapping));
            for alias = aliases.'
                owner = string(mapping.(char(alias)));
                if ~ismember(owner,string(out.Properties.VariableNames))
                    error("sixgr:validation:SchemaMissingColumn", ...
                        "Canonical owner %s is missing.",owner);
                end
                ownerValues = out.(char(owner));
                if ismember(alias,string(out.Properties.VariableNames))
                    if ~isequaln(out.(char(alias)),ownerValues)
                        error("sixgr:validation:CompatibilityAliasDivergence", ...
                            "Compatibility alias %s diverges from %s.", ...
                            alias,owner);
                    end
                else
                    out.(char(alias)) = ownerValues;
                end
            end
        end
    end
end
