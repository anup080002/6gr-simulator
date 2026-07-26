classdef PUCCHRRCContext
    %PUCCHRRCContext Immutable installed RRC PUCCH configuration.

    properties (SetAccess=private)
        Data
        ResourceSets
        Resources
        ConfigurationEpoch
        Digest
    end

    methods
        function obj = PUCCHRRCContext(data)
            required = ["ConfigurationEpoch","ResourceSets","Resources", ...
                "DLDataToULACK","SRResources","CSIResources", ...
                "SPSPUCCHANResources"];
            sixgr.phy.pucch.UCIReport.requireFields(data,required);
            obj.ConfigurationEpoch = double(data.ConfigurationEpoch);
            sets = data.ResourceSets;
            resources = data.Resources;
            resourceSets = sixgr.phy.pucch.PUCCHResourceSet.empty(0,1);
            for index = 1:numel(sets)
                resourceSets(end+1,1) = sixgr.phy.pucch.PUCCHResourceSet(sets(index)); %#ok<AGROW>
            end
            resourceObjects = sixgr.phy.pucch.PUCCHResource.empty(0,1);
            for index = 1:numel(resources)
                resourceObjects(end+1,1) = sixgr.phy.pucch.PUCCHResource(resources(index)); %#ok<AGROW>
            end
            obj.ResourceSets = resourceSets;
            obj.Resources = resourceObjects;
            ids = arrayfun(@(x) x.ID,obj.Resources);
            if numel(unique(ids)) ~= numel(ids)
                error("sixgr:phy:pucch:InvalidResourceIndicator", ...
                    "PUCCH resource IDs must be unique.");
            end
            for index = 1:numel(obj.ResourceSets)
                if any(~ismember(obj.ResourceSets(index).ResourceIDs,ids))
                    error("sixgr:phy:pucch:InvalidResourceIndicator", ...
                        "PUCCH resource set %d references an unknown resource.", ...
                        obj.ResourceSets(index).ID);
                end
            end
            obj.Data = data;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(data);
        end

        function resource = resourceByID(obj,id)
            index = find(arrayfun(@(x) x.ID,obj.Resources) == double(id),1);
            if isempty(index)
                error("sixgr:phy:pucch:InvalidResourceIndicator", ...
                    "Unknown PUCCH resource ID %g.",id);
            end
            resource = obj.Resources(index);
        end
    end
end
