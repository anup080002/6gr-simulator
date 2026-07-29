classdef FullStackSubcaseRegistry
    %FULLSTACKSUBCASEREGISTRY Contract-backed 31-child execution registry.
    methods (Static)
        function registry = load(profile)
            T = profile.Subcases;
            ids = string(T.SubcaseID);
            if height(T) ~= 31 || numel(unique(ids)) ~= 31 || ...
                    ~isequal(ids, "SC-" + compose("%02d", (0:30)'))
                error("FULLSTACK:SubcaseRegistryInvalid", ...
                    "Subcase registry must contain unique ordered SC-00..SC-30 rows.");
            end
            first = sixgr.integration.qualification.FullStackSubcase. ...
                fromRow(T(1,:));
            registry = repmat(first, height(T), 1);
            for index = 2:height(T)
                registry(index) = sixgr.integration.qualification. ...
                    FullStackSubcase.fromRow(T(index,:));
            end
        end
    end
end
