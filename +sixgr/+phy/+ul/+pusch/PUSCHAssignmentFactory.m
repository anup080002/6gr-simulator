classdef PUSCHAssignmentFactory
    %PUSCHASSIGNMENTFACTORY Separate fail-closed PUSCH assignment factories.

    methods (Static)
        function assignment = fromDecodedDCI(decodedDCI, ueContext, frameState, ...
                harqState, soundingState, powerState)
            data = localMerge(decodedDCI, ueContext, frameState, harqState, ...
                soundingState, powerState);
            localRequirePresent(data, "DecodedDCIId", "sixgr:pusch:MissingDecodedDCI");
            localRequireTrue(data, "DCICRCPass", "sixgr:pusch:DCICRCFailed");
            localRequireTrue(data, "DCIRNTIMatch", "sixgr:pusch:DCIRNTIMismatch");
            format = string(localGet(data, "DCIFormat", ""));
            if ~ismember(format, ["0_0","0_1","0_2","0_3"])
                error("sixgr:pusch:UnsupportedDCIFormat", ...
                    "Dynamic PUSCH requires decoded DCI format 0_0 through 0_3.");
            end
            data.Profile = "connected_dynamic_strict";
            data.Source = "decoded_dci_plus_rrc";
            assignment = localCreate(data);
        end

        function assignment = fromConfiguredGrantType1(cgState, ueContext, ...
                frameState, harqState, soundingState, powerState)
            data = localMerge(cgState, ueContext, frameState, harqState, ...
                soundingState, powerState);
            localRequireTrue(data, "CGInstalled", ...
                "sixgr:pusch:ConfiguredGrantNotInstalled");
            localRequireFalse(data, "CGReleased", ...
                "sixgr:pusch:ConfiguredGrantReleased");
            localRequireTrue(data, "CGOccasionMatch", ...
                "sixgr:pusch:ConfiguredGrantWrongOccasion");
            data.Profile = "configured_grant_type1_strict";
            data.Source = "rrc_configured_grant_type1";
            assignment = localCreate(data);
        end

        function assignment = fromConfiguredGrantType2(cgState, activationDCI, ...
                ueContext, frameState, harqState, soundingState, powerState)
            data = localMerge(cgState, activationDCI, ueContext, frameState, ...
                harqState, soundingState, powerState);
            localRequireTrue(data, "CGInstalled", ...
                "sixgr:pusch:ConfiguredGrantNotInstalled");
            localRequireFalse(data, "CGReleased", ...
                "sixgr:pusch:ConfiguredGrantReleased");
            crcState = localGet(data, "DCICRCPass", []);
            rntiState = localGet(data, "DCIRNTIMatch", []);
            if ~isempty(crcState) && ~localTruthy(crcState)
                error("sixgr:pusch:ConfiguredGrantActivationCRCFailed", ...
                    "Type-2 configured-grant activation DCI failed CRC.");
            end
            if ~isempty(rntiState) && ~localTruthy(rntiState)
                error("sixgr:pusch:ConfiguredGrantActivationRNTIMismatch", ...
                    "Type-2 configured-grant activation DCI has the wrong CS-RNTI.");
            end
            localRequireTrue(data, "CGActivated", ...
                "sixgr:pusch:ConfiguredGrantNotActivated");
            localRequireTrue(data, "CGOccasionMatch", ...
                "sixgr:pusch:ConfiguredGrantWrongOccasion");
            data.Profile = "configured_grant_type2_strict";
            data.Source = "rrc_plus_cs_rnti_activation";
            data.RNTIType = "CS-RNTI";
            assignment = localCreate(data);
        end

        function assignment = fromRARMsg3(rarGrant, randomAccessState, ...
                ueContext, frameState, powerState)
            data = localMerge(rarGrant, randomAccessState, ueContext, ...
                frameState, powerState);
            localRequirePresent(data, "RARGrantId", "sixgr:pusch:RARGrantInvalid");
            localRequireTrue(data, "RAPIDMatch", ...
                "sixgr:pusch:RARGrantIdentityMismatch");
            data.Profile = "random_access_ul_strict";
            data.Source = "decoded_rar_ul_grant";
            assignment = localCreate(data);
        end

        function assignment = fromMsgA(msgAConfig, randomAccessState, ...
                ueContext, frameState, powerState)
            data = localMerge(msgAConfig, randomAccessState, ueContext, ...
                frameState, powerState);
            localRequirePresent(data, "MsgAResourceId", ...
                "sixgr:pusch:MsgAResourceInvalid");
            localRequireTrue(data, "RAPIDMatch", "sixgr:pusch:MsgARAPIDMismatch");
            data.Profile = "random_access_ul_strict";
            data.Source = "msga_pusch_configuration_and_rapid";
            assignment = localCreate(data);
        end

        function assignment = forCalibration(request, frameState)
            data = localMerge(request, frameState);
            localRequirePresent(data, "CalibrationRequestId", ...
                "sixgr:pusch:IncompleteCalibrationRequest");
            data.Profile = "phy_calibration";
            data.Source = "explicit_calibration_request";
            assignment = localCreate(data);
        end

        function assignment = fromVectorRow(row)
            data = localVectorData(row);
            profile = string(data.Profile);
            switch profile
                case "connected_dynamic_strict"
                    assignment = sixgr.phy.ul.pusch.PUSCHAssignmentFactory. ...
                        fromDecodedDCI(data, struct(), struct(), struct(), struct(), struct());
                case "configured_grant_type1_strict"
                    assignment = sixgr.phy.ul.pusch.PUSCHAssignmentFactory. ...
                        fromConfiguredGrantType1(data, struct(), struct(), struct(), struct(), struct());
                case "configured_grant_type2_strict"
                    assignment = sixgr.phy.ul.pusch.PUSCHAssignmentFactory. ...
                        fromConfiguredGrantType2(data, data, struct(), struct(), struct(), struct(), struct());
                case "random_access_ul_strict"
                    if contains(string(data.Source), "msga")
                        assignment = sixgr.phy.ul.pusch.PUSCHAssignmentFactory. ...
                            fromMsgA(data, data, struct(), struct(), struct());
                    else
                        assignment = sixgr.phy.ul.pusch.PUSCHAssignmentFactory. ...
                            fromRARMsg3(data, data, struct(), struct(), struct());
                    end
                case "phy_calibration"
                    assignment = sixgr.phy.ul.pusch.PUSCHAssignmentFactory. ...
                        forCalibration(data, struct());
                otherwise
                    error("sixgr:pusch:InvalidAssignmentProfile", ...
                        "Unknown vector profile '%s'.", profile);
            end
        end
    end
end

function assignment = localCreate(data)
localCommonChecks(data);
data = localMaterialize(data);
assignment = sixgr.phy.ul.pusch.PUSCHSchedulingAssignment(data);
end

function localCommonChecks(data)
if isfield(data, "ConfigurationEpoch") && isfield(data, "CurrentConfigurationEpoch") ...
        && double(data.ConfigurationEpoch) ~= double(data.CurrentConfigurationEpoch)
    error("sixgr:pusch:StaleBWPContext", ...
        "PUSCH assignment configuration epoch does not match the active UL BWP.");
end
k2 = double(localGet(data, "K2", NaN));
if ~(isscalar(k2) && isfinite(k2) && k2 == fix(k2) && k2 >= 0)
    error("sixgr:pusch:InvalidK2", "PUSCH K2 must be a nonnegative integer.");
end
if ~localTruthy(localGet(data, "ULSymbolAvailable", false))
    error("sixgr:pusch:NoULSymbols", ...
        "The resolved target slot does not contain the requested UL symbols.");
end
allocationType = double(localGet(data, "ResourceAllocationType", NaN));
hopping = lower(string(localGet(data, "FrequencyHoppingMode", "none")));
if allocationType == 2 && hopping ~= "none"
    error("sixgr:pusch:FrequencyHoppingResourceTypeConflict", ...
        "Resource-allocation type 2 is incompatible with PUSCH frequency hopping.");
end
end

function data = localMaterialize(data)
data.AssignmentId = char(string(localGet(data, "AssignmentId", ...
    localGet(data, "CaseId", localGet(data, "CaseID", "PUSCH")))));
data.UEId = char(string(localGet(data, "UEId", "UE1")));
data.RNTI = double(localGet(data, "RNTI", 1));
data.RNTIType = char(string(localGet(data, "RNTIType", "C-RNTI")));
data.ServingCellId = double(localGet(data, "ServingCellId", 0));
data.CCId = double(localGet(data, "CCId", 0));
data.BWPId = double(localGet(data, "BWPId", 0));
data.ConfigurationEpoch = double(localGet(data, "ConfigurationEpoch", 0));
data.PUSCHAbsoluteSlot = double(localGet(data, "PUSCHAbsoluteSlot", ...
    localGet(data, "AbsoluteSlot", 0)));
data.K2 = double(localGet(data, "K2", 0));
data.SymbolAllocation = localNumericVector(localGet(data, "SymbolAllocation", []));
data.MappingType = char(string(localGet(data, "MappingType", "")));
data.ResourceAllocationType = double(localGet(data, "ResourceAllocationType", NaN));
data.PRBSetBWPRelative = localNumericVector(localGet(data, "PRBSetBWPRelative", ...
    localGet(data, "PRBSet", [])));
bwpStart = double(localGet(data, "BWPStart", 0));
data.PRBSetCarrierRelative = data.PRBSetBWPRelative + bwpStart;
data.TransformPrecoding = logical(localGet(data, "TransformPrecoding", false));
rank = double(localGet(data, "NumLayers", NaN));
data.NumLayers = rank;
[layerCounts, ~] = sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(rank);
data.NumCodewords = numel(layerCounts);
data.LayerCountPerCodeword = layerCounts;
mcs = double(localGet(data, "MCSIndex", NaN));
mcsTable = string(localGet(data, "MCSTable", "qam64"));
mcsRow = sixgr.phy.ul.pusch.PUSCHMCSResolver.resolve( ...
    mcsTable, mcs, data.TransformPrecoding);
data.MCSTablePerCodeword = repmat(string(mcsRow.MCSTable), 1, data.NumCodewords);
data.MCSIndexPerCodeword = repmat(mcs, 1, data.NumCodewords);
data.ModulationPerCodeword = repmat(string(mcsRow.Modulation), 1, data.NumCodewords);
data.TargetCodeRatePerCodeword = repmat(double(mcsRow.TargetCodeRate), 1, data.NumCodewords);
data.DMRSPortSet = localNumericVector(localGet(data, "DMRSPortSet", 0:rank-1));
data.NDIPerCodeword = repmat(double(localGet(data, "NDI", 1)), 1, data.NumCodewords);
data.RVPerCodeword = repmat(double(localGet(data, "RV", 0)), 1, data.NumCodewords);
data.HARQProcessId = double(localGet(data, "HARQProcessId", ...
    localGet(data, "HARQProcessID", 0)));
end

function data = localVectorData(row)
data = row;
data.CaseId = char(string(localGet(row, "CaseID", "")));
data.AssignmentId = data.CaseId;
data.Profile = char(lower(string(localGet(row, "Profile", ""))));
data.Source = char(lower(string(localGet(row, "SourceType", ""))));
data.UEId = char(string(localGet(row, "UEID", "UE1")));
data.ServingCellId = localNumber(row, "ServingCellID", 0);
data.CCId = localNumber(row, "CCID", 0);
data.BWPId = localNumber(row, "BWPId", 0);
data.AbsoluteSlot = localNumber(row, "AbsoluteSlot", 0);
data.ConfigurationEpoch = localNumber(row, "ConfigurationEpoch", 0);
data.CurrentConfigurationEpoch = 3;
data.DecodedDCIId = char(string(localGet(row, "DecodedDCIId", "")));
data.DCIFormat = char(string(localGet(row, "DCIFormat", "")));
data.DCICRCPass = localOptionalLogical(row, "DCICRCPass");
data.DCIRNTIMatch = localOptionalLogical(row, "DCIRNTIMatch");
data.RNTIType = char(string(localGet(row, "RNTIType", "C-RNTI")));
data.K2 = localNumber(row, "K2", NaN);
data.ULSymbolAvailable = localOptionalLogical(row, "ULSymbolAvailable");
data.ResourceAllocationType = localNumber(row, "ResourceAllocationType", NaN);
data.FrequencyHoppingMode = char(lower(string(localGet(row, "FrequencyHopping", "none"))));
data.SecondHopStartPRB = localNumber(row, "SecondHopStartPRB", NaN);
data.PRBSet = localNumericVector(localGet(row, "PRBSet", []));
data.SymbolAllocation = localNumericVector(localGet(row, "SymbolAllocation", []));
data.MappingType = char(string(localGet(row, "MappingType", "")));
data.MCSTable = char(string(localGet(row, "MCSTable", "qam64")));
data.MCSIndex = localNumber(row, "MCSIndex", NaN);
data.TransformPrecoding = localOptionalLogical(row, "TransformPrecoding");
data.NumLayers = localNumber(row, "NumLayers", NaN);
data.NDI = localNumber(row, "NDI", 1);
data.RV = localNumber(row, "RV", 0);
data.HARQProcessId = localNumber(row, "HARQProcessID", 0);
data.CGInstalled = localOptionalLogical(row, "CGInstalled");
data.CGActivated = localOptionalLogical(row, "CGActivated");
data.CGReleased = localOptionalLogical(row, "CGReleased");
data.CGOccasionMatch = localOptionalLogical(row, "CGOccasionMatch");
data.RARGrantId = char(string(localGet(row, "RARGrantID", "")));
data.MsgAResourceId = data.RARGrantId;
data.RAPIDMatch = localOptionalLogical(row, "RAPIDMatch");
data.CalibrationRequestId = char(string(localGet(row, "CalibrationRequestID", "")));
if contains(data.Source, "msga")
    data.MsgAResourceId = data.RARGrantId;
end
end

function data = localMerge(varargin)
data = struct();
for i = 1:nargin
    value = varargin{i};
    if isempty(value)
        continue;
    end
    if ~isstruct(value) || ~isscalar(value)
        error("sixgr:pusch:InvalidFactoryContext", ...
            "PUSCH assignment factory contexts must be scalar structs.");
    end
    names = fieldnames(value);
    for k = 1:numel(names)
        data.(names{k}) = value.(names{k});
    end
end
end

function localRequirePresent(data, fieldName, id)
value = localGet(data, fieldName, []);
if isempty(value) || strlength(strtrim(string(value))) == 0
    error(id, "Required PUSCH assignment field %s is absent.", fieldName);
end
end

function localRequireTrue(data, fieldName, id)
if ~localTruthy(localGet(data, fieldName, []))
    error(id, "Required PUSCH state %s is not true.", fieldName);
end
end

function localRequireFalse(data, fieldName, id)
value = localGet(data, fieldName, []);
if isempty(value) || localTruthy(value)
    error(id, "Required PUSCH state %s is not false.", fieldName);
end
end

function tf = localTruthy(value)
if islogical(value) || isnumeric(value)
    tf = isscalar(value) && isfinite(double(value)) && logical(value);
else
    tf = any(strcmpi(strtrim(string(value)), ["1","true","yes","pass"]));
end
end

function value = localGet(data, fieldName, defaultValue)
value = defaultValue;
if isfield(data, fieldName)
    candidate = data.(fieldName);
    if ~isempty(candidate)
        value = candidate;
    end
end
end

function value = localNumericVector(raw)
if isnumeric(raw)
    value = double(raw(:).');
    value = value(isfinite(value));
    return;
end
text = strtrim(string(raw));
if strlength(text) == 0 || ismissing(text)
    value = zeros(1, 0);
    return;
end
tokens = split(replace(text, ",", "|"), "|");
value = str2double(tokens).';
value = value(isfinite(value));
end

function value = localNumber(data, fieldName, defaultValue)
raw = localGet(data, fieldName, defaultValue);
if isnumeric(raw)
    value = double(raw);
else
    value = str2double(string(raw));
end
if isempty(value) || ~isscalar(value) || ~isfinite(value)
    value = defaultValue;
end
end

function value = localOptionalLogical(data, fieldName)
raw = localGet(data, fieldName, []);
if isempty(raw) || (isstring(raw) && (ismissing(raw) || strlength(strtrim(raw)) == 0))
    value = [];
elseif isnumeric(raw) || islogical(raw)
    value = logical(raw);
else
    value = localTruthy(raw);
end
end
