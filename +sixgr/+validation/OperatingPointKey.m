classdef OperatingPointKey
    %OPERATINGPOINTKEY Complete exact validation operating-point identity.
    methods (Static)
        function out = requiredFields()
            out = ["RunClass","Direction","ProfileID","ChannelModel", ...
                "CarrierFrequency_Hz","Bandwidth_Hz","SCS_kHz", ...
                "MCS","Rank","Receiver","SNR_dB"];
        end
        function out = canonical(input)
            values = localValues(input);
            out = "RunClass=" + ...
                sixgr.validation.RunClass.parse(values.RunClass) + ...
                "|Direction=" + upper(strtrim(string(values.Direction))) + ...
                "|ProfileID=" + strtrim(string(values.ProfileID)) + ...
                "|ChannelModel=" + upper(strtrim(string(values.ChannelModel))) + ...
                "|CarrierFrequency_Hz=" + localFixed(values.CarrierFrequency_Hz) + ...
                "|Bandwidth_Hz=" + localFixed(values.Bandwidth_Hz) + ...
                "|SCS_kHz=" + localNumber(values.SCS_kHz) + ...
                "|MCS=" + localInteger(values.MCS,"MCS",0) + ...
                "|Rank=" + localInteger(values.Rank,"Rank",1) + ...
                "|Receiver=" + upper(strtrim(string(values.Receiver))) + ...
                "|SNR_dB=" + localNumber(values.SNR_dB);
        end
        function out = hash(input)
            out = string(sixgr.util.sha256Hex(uint8(unicode2native( ...
                char(sixgr.validation.OperatingPointKey.canonical(input)), ...
                "UTF-8"))));
        end
    end
end

function values = localValues(input)
required = sixgr.validation.OperatingPointKey.requiredFields();
values = struct();
if istable(input)
    if height(input) ~= 1
        error("sixgr:validation:SchemaDuplicateKey", ...
            "OperatingPointKey requires exactly one input row.");
    end
    for name = required
        if ~ismember(name,string(input.Properties.VariableNames))
            error("sixgr:validation:SchemaMissingColumn", ...
                "Operating-point field '%s' is missing.",name);
        end
        values.(char(name)) = input.(char(name))(1);
    end
elseif isstruct(input) && isscalar(input)
    for name = required
        if ~isfield(input,char(name)) || localMissing(input.(char(name)))
            error("sixgr:validation:SchemaMissingColumn", ...
                "Operating-point field '%s' is missing.",name);
        end
        values.(char(name)) = input.(char(name));
    end
else
    error("sixgr:validation:SchemaWrongType", ...
        "OperatingPointKey input must be one table row or scalar struct.");
end
for name = ["Direction","ProfileID","ChannelModel","Receiver"]
    if localMissing(values.(char(name))) || ...
            strlength(strtrim(string(values.(char(name))))) == 0
        error("sixgr:validation:SchemaMissingColumn", ...
            "Operating-point field '%s' is empty.",name);
    end
end
if ~ismember(upper(strtrim(string(values.Direction))),["DL","UL"])
    error("sixgr:validation:SchemaValueOutOfRange", ...
        "Direction must be DL or UL.");
end
end

function tf = localMissing(value)
if isempty(value)
    tf = true;
elseif iscell(value) && isscalar(value)
    tf = localMissing(value{1});
elseif ischar(value)
    tf = isempty(strtrim(value));
elseif isstring(value)
    tf = any(ismissing(value)) || any(strlength(strtrim(value)) == 0);
elseif isnumeric(value) || islogical(value)
    tf = any(~isfinite(double(value(:))));
else
    tf = false;
end
end

function out = localFixed(value)
value = localFinite(value);
if value <= 0
    error("sixgr:validation:SchemaValueOutOfRange", ...
        "Frequency and bandwidth fields must be positive.");
end
out = string(sprintf("%.1f",value));
end

function out = localNumber(value)
out = string(sprintf("%.15g",localFinite(value)));
end

function out = localInteger(value,name,minimum)
value = localFinite(value);
if value ~= fix(value) || value < minimum
    error("sixgr:validation:SchemaValueOutOfRange", ...
        "%s must be an integer not less than %d.",name,minimum);
end
out = string(sprintf("%d",value));
end

function out = localFinite(value)
if iscell(value) && isscalar(value), value = value{1}; end
if ischar(value) || isstring(value), value = str2double(string(value)); end
if ~(isnumeric(value) && isscalar(value) && isfinite(double(value)))
    error("sixgr:validation:SchemaNonFinite", ...
        "Operating-point numeric fields must be finite scalars.");
end
out = double(value);
end
