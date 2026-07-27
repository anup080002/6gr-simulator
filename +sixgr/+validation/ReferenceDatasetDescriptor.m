classdef ReferenceDatasetDescriptor
    %REFERENCEDATASETDESCRIPTOR Independent DUT/reference dataset contract.
    properties (SetAccess=private)
        Data struct
    end
    methods
        function obj = ReferenceDatasetDescriptor(input)
            if istable(input)
                if height(input) ~= 1
                    error("sixgr:validation:SchemaDuplicateKey", ...
                        "Reference descriptor must contain exactly one row.");
                end
                input = table2struct(input);
            end
            required = ["ReferenceID","SourceName","SourceVersion", ...
                "ReferenceSHA256","DUTSHA256","IndependentOfDUT","Freshness"];
            for name = required
                if ~isstruct(input) || ~isfield(input,char(name))
                    error("sixgr:validation:SchemaMissingColumn", ...
                        "Reference descriptor is missing %s.",name);
                end
            end
            referenceHash = lower(strtrim(string(input.ReferenceSHA256)));
            dutHash = lower(strtrim(string(input.DUTSHA256)));
            if ismissing(referenceHash) || strlength(referenceHash) == 0
                error("sixgr:validation:OperatingPointMissing", ...
                    "The independent reference artifact is missing.");
            end
            if ~localHash(referenceHash) || ~localHash(dutHash)
                error("sixgr:validation:OracleHashMismatch", ...
                    "Reference and DUT hashes must be SHA-256 digests.");
            end
            if upper(string(input.Freshness)) ~= "FRESH"
                error("sixgr:validation:ArtifactStale", ...
                    "Reference dataset is stale.");
            end
            if ~localBool(input.IndependentOfDUT) || referenceHash == dutHash || ...
                    lower(string(input.SourceName)) == "sixgr_dut"
                error("sixgr:validation:ReferenceNotIndependent", ...
                    "Reference dataset is not independent of the DUT.");
            end
            input.ReferenceSHA256 = referenceHash;
            input.DUTSHA256 = dutHash;
            input.Status = "PASS";
            obj.Data = input;
        end
        function out = toStruct(obj), out = obj.Data; end
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
