classdef ReferenceDatasetRegistry
    %REFERENCEDATASETREGISTRY Exact reference lookup; no nearest fallback.
    methods (Static)
        function out = validate(input)
            if ~istable(input) || height(input) == 0
                error("sixgr:validation:SchemaMissingColumn", ...
                    "A nonempty reference registry is required.");
            end
            ids = string(input.ReferenceID);
            if numel(ids) ~= numel(unique(ids))
                error("sixgr:validation:SchemaDuplicateKey", ...
                    "ReferenceID values must be unique.");
            end
            for index = 1:height(input)
                sixgr.validation.ReferenceDatasetDescriptor(input(index,:));
            end
            out = input;
        end
        function out = resolve(input,referenceID)
            input = sixgr.validation.ReferenceDatasetRegistry.validate(input);
            index = find(string(input.ReferenceID)==string(referenceID));
            if isempty(index)
                error("sixgr:validation:OperatingPointMissing", ...
                    "ReferenceID %s was not found.",string(referenceID));
            end
            out = sixgr.validation.ReferenceDatasetDescriptor(input(index,:));
        end
    end
end
