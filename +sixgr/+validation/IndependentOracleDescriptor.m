classdef IndependentOracleDescriptor
    %INDEPENDENTORACLEDESCRIPTOR Immutable, independently sourced oracle metadata.
    properties (SetAccess=private)
        Data struct
    end
    methods
        function obj = IndependentOracleDescriptor(input)
            if istable(input)
                if height(input) ~= 1
                    error("sixgr:validation:SchemaDuplicateKey", ...
                        "An oracle descriptor must contain exactly one row.");
                end
                input = table2struct(input);
            end
            required = ["OracleID","OracleType","Feature","ProfileID", ...
                "SourceName","SourceVersion","ArtifactPath","ArtifactSHA256", ...
                "IndependentOfDUT"];
            if ~isstruct(input) || ~isscalar(input)
                error("sixgr:validation:SchemaWrongType", ...
                    "Oracle descriptor must be a scalar struct or table row.");
            end
            for name = required
                if ~isfield(input,char(name))
                    error("sixgr:validation:SchemaMissingColumn", ...
                        "Oracle descriptor is missing %s.",name);
                end
            end
            type = sixgr.validation.OracleType.parse(input.OracleType);
            hash = lower(strtrim(string(input.ArtifactSHA256)));
            if ~localHash(hash)
                error("sixgr:validation:OracleHashMismatch", ...
                    "Oracle artifact hash must be a SHA-256 digest.");
            end
            independent = localBool(input.IndependentOfDUT);
            qualifies = independent && sixgr.validation.OracleType.qualifies(type);
            input.OracleType = type;
            input.ArtifactSHA256 = hash;
            input.IndependentOfDUT = independent;
            input.QualifiesForMandatoryGate = qualifies;
            obj.Data = input;
        end
        function out = qualifies(obj)
            out = obj.Data.QualifiesForMandatoryGate;
        end
        function out = toStruct(obj)
            out = obj.Data;
        end
    end
end

function out = localHash(value)
out = isscalar(value) && strlength(value) == 64 && ...
    ~isempty(regexp(char(value),"^[0-9a-f]{64}$","once"));
end

function out = localBool(value)
if islogical(value) && isscalar(value)
    out = value;
elseif isnumeric(value) && isscalar(value) && ismember(value,[0 1])
    out = logical(value);
else
    text = lower(strtrim(string(value)));
    if text == "true"
        out = true;
    elseif text == "false"
        out = false;
    else
        error("sixgr:validation:SchemaWrongType", ...
            "IndependentOfDUT must be Boolean.");
    end
end
end
