classdef PUSCHSchedulingAssignment
    %PUSCHSCHEDULINGASSIGNMENT Immutable PUSCH scheduling value object.

    properties (SetAccess = private)
        AssignmentId
        Profile
        Source
        Digest
        Immutable
    end

    properties (Access = private)
        Data
    end

    methods
        function obj = PUSCHSchedulingAssignment(data)
            if ~(isstruct(data) && isscalar(data))
                error("sixgr:pusch:IncompleteSchedulingAssignment", ...
                    "PUSCH scheduling assignment input must be a scalar struct.");
            end
            data = localCanonicalize(data);
            localValidate(data);
            obj.Data = data;
            obj.AssignmentId = string(data.AssignmentId);
            obj.Profile = string(data.Profile);
            obj.Source = string(data.Source);
            obj.Digest = localDigest(data);
            obj.Immutable = true;
        end

        function value = get(obj, fieldName)
            fieldName = char(string(fieldName));
            if ~isfield(obj.Data, fieldName)
                error("sixgr:pusch:AssignmentFieldMissing", ...
                    "PUSCH assignment has no field '%s'.", fieldName);
            end
            value = obj.Data.(fieldName);
        end

        function value = toStruct(obj)
            value = obj.Data;
            value.AssignmentDigest = char(obj.Digest);
            value.Immutable = true;
        end

        function validateForExecution(obj)
            localValidate(obj.Data);
        end
    end
end

function data = localCanonicalize(data)
required = [ ...
    "AssignmentId","Profile","Source","UEId","RNTI","RNTIType", ...
    "ServingCellId","CCId","BWPId","ConfigurationEpoch", ...
    "PUSCHAbsoluteSlot","K2","SymbolAllocation","MappingType", ...
    "ResourceAllocationType","PRBSetBWPRelative", ...
    "PRBSetCarrierRelative","MCSTablePerCodeword", ...
    "MCSIndexPerCodeword","ModulationPerCodeword", ...
    "TargetCodeRatePerCodeword","NumLayers","NumCodewords", ...
    "LayerCountPerCodeword","TransformPrecoding","DMRSPortSet", ...
    "NDIPerCodeword","RVPerCodeword","HARQProcessId"];
missing = required(~isfield(data, required));
if ~isempty(missing)
    error("sixgr:pusch:IncompleteSchedulingAssignment", ...
        "PUSCH assignment is missing required fields: %s.", ...
        strjoin(cellstr(missing), ", "));
end
data.Profile = char(lower(strtrim(string(data.Profile))));
data.Source = char(lower(strtrim(string(data.Source))));
data.MappingType = char(upper(strtrim(string(data.MappingType))));
data.PRBSetsAreZeroBased = true;
data.SymbolsAreZeroBased = true;
end

function localValidate(data)
profiles = ["connected_dynamic_strict","configured_grant_type1_strict", ...
    "configured_grant_type2_strict","random_access_ul_strict","phy_calibration"];
if ~ismember(string(data.Profile), profiles)
    error("sixgr:pusch:InvalidAssignmentProfile", ...
        "Unsupported PUSCH assignment profile '%s'.", data.Profile);
end
if strlength(strtrim(string(data.AssignmentId))) == 0 ...
        || strlength(strtrim(string(data.Source))) == 0
    error("sixgr:pusch:IncompleteSchedulingAssignment", ...
        "PUSCH assignment identity and source are required.");
end
rank = localInteger(data.NumLayers, 1, 8, "NumLayers");
codewords = localInteger(data.NumCodewords, 1, 2, "NumCodewords");
expectedCodewords = 1 + double(rank > 4);
if codewords ~= expectedCodewords
    error("sixgr:pusch:UnsupportedLayerCodewordTuple", ...
        "PUSCH rank %d requires %d codeword(s).", rank, expectedCodewords);
end
layers = double(data.LayerCountPerCodeword(:).');
if numel(layers) ~= codewords || sum(layers) ~= rank ...
        || any(layers < 1 | layers ~= fix(layers))
    error("sixgr:pusch:UnsupportedLayerCodewordTuple", ...
        "LayerCountPerCodeword does not partition rank %d.", rank);
end
if logical(data.TransformPrecoding) && rank ~= 1
    error("sixgr:pusch:UnsupportedTransformPrecodingLayerCount", ...
        "The selected strict transform-precoded PUSCH profile requires rank one.");
end
modulation = string(data.ModulationPerCodeword);
modulation = reshape(modulation, 1, []);
if numel(modulation) ~= codewords
    error("sixgr:pusch:InvalidMCSContext", ...
        "ModulationPerCodeword must contain one value per codeword.");
end
for cw = 1:codewords
    sixgr.phy.ul.pusch.PUSCHModulator.normalizeModulation(modulation(cw));
end
prb = double(data.PRBSetBWPRelative(:).');
if isempty(prb) || any(~isfinite(prb) | prb ~= fix(prb) | prb < 0) ...
        || numel(unique(prb)) ~= numel(prb)
    error("sixgr:pusch:MissingFrequencyAllocation", ...
        "PUSCH assignment requires a unique nonnegative BWP-relative PRB set.");
end
symbols = double(data.SymbolAllocation(:).');
if numel(symbols) ~= 2 || any(~isfinite(symbols) | symbols ~= fix(symbols)) ...
        || symbols(1) < 0 || symbols(2) < 1 || sum(symbols) > 14
    error("sixgr:pusch:MissingTimeAllocation", ...
        "PUSCH assignment requires SymbolAllocation [start length] inside one slot.");
end
if ~ismember(string(data.MappingType), ["A","B"])
    error("sixgr:pusch:MissingTimeAllocation", ...
        "PUSCH mapping type must be A or B.");
end
ports = double(data.DMRSPortSet(:).');
if isempty(ports) || any(~isfinite(ports) | ports ~= fix(ports) | ports < 0) ...
        || numel(unique(ports)) ~= numel(ports)
    error("sixgr:pusch:InvalidDMRSPortSet", ...
        "PUSCH assignment requires an explicit unique zero-based DM-RS port set.");
end
localPerCodeword(data.MCSIndexPerCodeword, codewords, "MCSIndexPerCodeword");
localPerCodeword(data.TargetCodeRatePerCodeword, codewords, "TargetCodeRatePerCodeword");
localPerCodeword(data.NDIPerCodeword, codewords, "NDIPerCodeword");
localPerCodeword(data.RVPerCodeword, codewords, "RVPerCodeword");
end

function value = localInteger(raw, minimum, maximum, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value == fix(value) ...
        && value >= minimum && value <= maximum)
    error("sixgr:pusch:IncompleteSchedulingAssignment", ...
        "%s must be an integer in [%d,%d].", name, minimum, maximum);
end
end

function localPerCodeword(raw, count, name)
values = double(raw(:).');
if numel(values) ~= count || any(~isfinite(values))
    error("sixgr:pusch:IncompleteSchedulingAssignment", ...
        "%s must contain one finite value per codeword.", name);
end
end

function digest = localDigest(data)
bytes = uint8(unicode2native(jsonencode(orderfields(data)), "UTF-8"));
digest = string(sixgr.util.sha256Hex(bytes));
end
