classdef MIMOCapabilityProfile
    %MIMOCAPABILITYPROFILE Fail-closed Release-18 MIMO capability registry.
    %
    % Resolution is a planning operation. Unsupported requests throw before
    % waveform generation, grant creation, or mutable runtime state exists.

    properties (SetAccess = immutable)
        Specification sixgr.phy.mimo.MIMOSpecificationProfile
    end

    methods
        function obj = MIMOCapabilityProfile()
            obj.Specification = sixgr.phy.mimo.MIMOSpecificationProfile();
        end

        function result = resolve(obj, request)
            arguments
                obj
                request (1,1) struct
            end
            profileID = string(localRequired(request, "ProfileID"));
            direction = upper(string(localRequired(request, "Direction")));
            codebookType = string(localRequired(request, "CodebookType"));
            ports = localPositiveInteger(request, "Ports");
            panels = localPositiveInteger(request, "Panels");
            rankValue = localPositiveInteger(request, "Rank");

            supportedProfiles = [ ...
                "fr1_typeI_single_panel_strict"
                "fr1_typeI_multi_panel_strict"
                "fr1_typeII_strict"
                "fr1_typeII_PortSelection_strict"
                "fr1_enhancedTypeII_strict"
                "fr1_high_rank_ul_strict"
                "fr1_mu_mimo_2ue_strict"
                "fr1_mu_mimo_4ue_strict"
                "fr1_2trp_ncjt_strict"
                "fr1_2trp_cjt_strict"
                "fr2_hybrid_beamforming_strict"
                "beam_management_p1_p2_p3_bfr_strict"];
            if ~any(profileID == supportedProfiles)
                error("sixgr:mimo:UnsupportedProfile", ...
                    "MIMO capability profile '%s' is not enabled.", profileID);
            end
            if ~ismember(direction, ["DL","UL","BIDIRECTIONAL","BOTH"])
                error("sixgr:mimo:UnsupportedAntennaTuple", ...
                    "Direction '%s' is not supported.", direction);
            end
            if rankValue > min(8, ports)
                error("sixgr:mimo:UnsupportedRank", ...
                    "Rank %d is unsupported for %d ports.", rankValue, ports);
            end
            if contains(profileID, "single_panel") && panels ~= 1
                error("sixgr:mimo:UnsupportedAntennaTuple", ...
                    "Single-panel profile requires Panels=1.");
            end
            if contains(profileID, "multi_panel") && panels < 2
                error("sixgr:mimo:UnsupportedMultiPanelProfile", ...
                    "Multi-panel profile requires at least two panels.");
            end
            if contains(profileID, "high_rank_ul") && direction ~= "UL"
                error("sixgr:mimo:UnsupportedAntennaTuple", ...
                    "High-rank UL profile requires Direction=UL.");
            end
            if contains(profileID, "typeII", "IgnoreCase", true) && rankValue > 4
                error("sixgr:mimo:UnsupportedRank", ...
                    "The enabled bounded Type-II profiles support at most rank 4.");
            end
            if contains(profileID, "hybrid") && direction ~= "DL"
                error("sixgr:mimo:UnsupportedAntennaTuple", ...
                    "The enabled FR2 hybrid profile is downlink.");
            end
            if strlength(codebookType) == 0
                error("sixgr:mimo:InvalidCodebookType", ...
                    "CodebookType must be explicit.");
            end
            localValidateSelectedTuple(request,profileID,direction, ...
                codebookType,ports,panels,rankValue);

            independentMatrixPackReady = profileID == ...
                "fr1_typeI_single_panel_strict" && ports == 2;

            result = struct( ...
                "ProfileID", profileID, ...
                "Direction", direction, ...
                "CodebookType", codebookType, ...
                "Ports", ports, ...
                "Panels", panels, ...
                "Rank", rankValue, ...
                "Supported", true, ...
                "IndependentMatrixPackReady",independentMatrixPackReady, ...
                "EnumerationReady",independentMatrixPackReady || ...
                    (profileID == "fr1_typeI_single_panel_strict" && rankValue <= 2) || ...
                    profileID == "fr1_high_rank_ul_strict" || ...
                    any(contains(profileID,["mu_mimo","2trp","hybrid","beam_management"])), ...
                "PlanningRejected", false, ...
                "ParametersMutated", false, ...
                "SpecificationProfile", obj.Specification.ProfileID);
        end
    end
end

function localValidateSelectedTuple(request,profileID,direction,codebookType,ports,panels,rankValue)
cb = lower(codebookType);
n1 = localOptionalInteger(request,"N1");
n2 = localOptionalInteger(request,"N2");
o1 = localOptionalInteger(request,"O1");
o2 = localOptionalInteger(request,"O2");
switch profileID
    case "fr1_typeI_single_panel_strict"
        allowedPorts = [2 4 8 12 16 24 32];
        if direction ~= "DL" || cb ~= "typei-singlepanel" || ...
                panels ~= 1 || ~ismember(ports,allowedPorts)
            localTupleError(profileID);
        end
        maxRank = min(8,ports);
        if ports == 2
            maxRank = 2;
        end
        if rankValue > maxRank
            error("sixgr:mimo:UnsupportedRank", ...
                "Rank %d is not selected for %d-port single-panel Type-I.", ...
                rankValue,ports);
        end
        if all(isfinite([n1 n2 o1 o2]))
            if ports == 2
                validGeometry = n1 == 1 && n2 == 1 && o1 == 1 && o2 == 1;
            else
                validGeometry = n1*n2 == ports/2 && n1 >= n2 && ...
                    o1 == 4 && o2 == localTernary(n2>1,4,1);
            end
            if ~validGeometry
                localTupleError(profileID);
            end
        end
    case "fr1_typeI_multi_panel_strict"
        allowed = [8 2 2 1 4 1;16 2 4 1 4 1;16 4 2 1 4 1; ...
                   32 2 4 2 4 4;32 4 4 1 4 1];
        if direction ~= "DL" || cb ~= "typei-multipanel" || rankValue > 4
            localTupleError(profileID);
        end
        if all(isfinite([n1 n2 o1 o2]))
            tuple = [ports panels n1 n2 o1 o2];
            if ~ismember(tuple,allowed,"rows")
                localTupleError(profileID);
            end
        elseif ~any(allowed(:,1)==ports & allowed(:,2)==panels)
            localTupleError(profileID);
        end
    case "fr1_typeII_strict"
        localRequireExact(profileID,direction,cb,ports,panels,rankValue, ...
            "DL","typeii",8,1,2);
    case "fr1_typeII_PortSelection_strict"
        if direction ~= "DL" || cb ~= "typeii-portselection" || ...
                panels ~= 1 || ~ismember(ports,[4 8]) || rankValue > 2
            localTupleError(profileID);
        end
    case "fr1_enhancedTypeII_strict"
        localRequireExact(profileID,direction,cb,ports,panels,rankValue, ...
            "DL","enhancedtypeii",16,1,4);
    case "fr1_high_rank_ul_strict"
        if direction ~= "UL" || ~ismember(cb,["codebook","noncodebook"]) || ...
                panels ~= 1 || ~ismember(ports,[2 4 8]) || ...
                rankValue > min(4,ports)
            localTupleError(profileID);
        end
    case "fr1_mu_mimo_2ue_strict"
        localRequireExact(profileID,direction,cb,ports,panels,rankValue, ...
            "DL","typei-singlepanel",8,1,2);
    case "fr1_mu_mimo_4ue_strict"
        localRequireExact(profileID,direction,cb,ports,panels,rankValue, ...
            "DL","typei-singlepanel",16,1,4);
    case {"fr1_2trp_ncjt_strict","fr1_2trp_cjt_strict"}
        localRequireExact(profileID,direction,cb,ports,panels,rankValue, ...
            "DL","multitrp",16,2,2);
    case "fr2_hybrid_beamforming_strict"
        localRequireExact(profileID,direction,cb,ports,panels,rankValue, ...
            "DL","hybrid",64,1,2);
    case "beam_management_p1_p2_p3_bfr_strict"
        localRequireExact(profileID,direction,cb,ports,panels,rankValue, ...
            "BOTH","beammanagement",64,1,1);
    otherwise
        error("sixgr:mimo:UnsupportedProfile", ...
            "MIMO capability profile '%s' is not selected.",profileID);
end
end

function localRequireExact(profileID,direction,cb,ports,panels,rankValue, ...
        expectedDirection,expectedCB,expectedPorts,expectedPanels,maxRank)
if direction ~= expectedDirection || cb ~= expectedCB || ...
        ports ~= expectedPorts || panels ~= expectedPanels || rankValue > maxRank
    localTupleError(profileID);
end
end

function localTupleError(profileID)
error("sixgr:mimo:UnsupportedAntennaTuple", ...
    "Requested tuple is outside selected profile %s.",profileID);
end

function value = localOptionalInteger(s,name)
value = NaN;
if isfield(s,name) && ~isempty(s.(name))
    raw = double(s.(name));
    if ~(isscalar(raw) && isfinite(raw) && raw >= 1 && raw == round(raw))
        error("sixgr:mimo:UnsupportedAntennaTuple", ...
            "%s must be a positive integer when provided.",name);
    end
    value = raw;
end
end

function out = localTernary(condition,a,b)
if condition
    out = a;
else
    out = b;
end
end

function value = localRequired(s, name)
if ~isfield(s, name) || isempty(s.(name))
    error("sixgr:mimo:UnsupportedProfile", ...
        "Capability request requires field %s.", name);
end
value = s.(name);
end

function value = localPositiveInteger(s, name)
value = double(localRequired(s, name));
if ~(isscalar(value) && isfinite(value) && value >= 1 && value == round(value))
    error("sixgr:mimo:UnsupportedAntennaTuple", ...
        "%s must be a positive integer.", name);
end
end
