classdef PUCCHUEContext
    %PUCCHUECONTEXT Immutable active UE/cell/BWP PUCCH state.

    properties (SetAccess=private)
        Data
        Digest
    end

    methods
        function obj = PUCCHUEContext(data)
            required = ["UEID","RNTI","ServingCell","PUCCHCell", ...
                "ComponentCarrier","ActiveULBWP","ConfigurationEpoch", ...
                "RRCContext","PowerControlState","SpatialRelationState"];
            sixgr.phy.pucch.UCIReport.requireFields(data,required);
            if ~isa(data.RRCContext,"sixgr.phy.pucch.PUCCHRRCContext")
                error("sixgr:phy:pucch:StaleConfiguration", ...
                    "PUCCHUEContext requires a typed RRC context.");
            end
            if double(data.ConfigurationEpoch) ~= ...
                    data.RRCContext.ConfigurationEpoch
                error("sixgr:phy:pucch:StaleConfiguration", ...
                    "UE and RRC PUCCH configuration epochs differ.");
            end
            obj.Data = data;
            digestData = rmfield(data,["RRCContext","PowerControlState", ...
                "SpatialRelationState"]);
            digestData.RRCContextDigest = data.RRCContext.Digest;
            digestData.PowerStateDigest = data.PowerControlState.Digest;
            digestData.SpatialStateDigest = data.SpatialRelationState.Digest;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(digestData);
        end
    end
end
