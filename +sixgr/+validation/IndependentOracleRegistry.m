classdef IndependentOracleRegistry
    %INDEPENDENTORACLEREGISTRY Exact-key oracle registry with hash enforcement.
    methods (Static)
        function out = validate(input)
            if ~istable(input) || height(input) == 0
                error("sixgr:validation:SchemaMissingColumn", ...
                    "A nonempty oracle registry is required.");
            end
            ids = string(input.OracleID);
            if numel(unique(ids)) ~= numel(ids)
                error("sixgr:validation:SchemaDuplicateKey", ...
                    "OracleID values must be unique.");
            end
            qualifies = false(height(input),1);
            for index = 1:height(input)
                descriptor = sixgr.validation.IndependentOracleDescriptor(input(index,:));
                qualifies(index) = descriptor.qualifies();
            end
            out = input;
            out.QualifiesForMandatoryGate = qualifies;
            out.Status = repmat("PASS",height(out),1);
            out.Status(~qualifies) = "REGRESSION_ONLY";
        end
        function out = resolve(input,oracleID)
            input = sixgr.validation.IndependentOracleRegistry.validate(input);
            rows = find(string(input.OracleID) == string(oracleID));
            if isempty(rows)
                error("sixgr:validation:OracleFailure", ...
                    "OracleID %s was not found.",string(oracleID));
            elseif numel(rows) ~= 1
                error("sixgr:validation:SchemaDuplicateKey", ...
                    "OracleID %s is not unique.",string(oracleID));
            end
            out = sixgr.validation.IndependentOracleDescriptor(input(rows,:));
        end
    end
end
