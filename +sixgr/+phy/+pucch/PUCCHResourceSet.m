classdef PUCCHResourceSet
    %PUCCHRESOURCESET Immutable configured PUCCH resource set.

    properties (SetAccess=private)
        ID
        ResourceIDs
        MaxPayloadBits
        Digest
    end

    methods
        function obj = PUCCHResourceSet(data)
            sixgr.phy.pucch.UCIReport.requireFields(data, ...
                ["ID","ResourceIDs","MaxPayloadBits"]);
            obj.ID = double(data.ID);
            obj.ResourceIDs = double(data.ResourceIDs(:).');
            obj.MaxPayloadBits = double(data.MaxPayloadBits);
            if numel(unique(obj.ResourceIDs)) ~= numel(obj.ResourceIDs)
                error("sixgr:phy:pucch:NoSupportingResourceSet", ...
                    "PUCCH resource-set IDs must not be duplicated.");
            end
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(data);
        end
    end
end
