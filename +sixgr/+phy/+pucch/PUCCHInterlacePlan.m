classdef PUCCHInterlacePlan
    %PUCCHINTERLACEPLAN Exact shared-spectrum interlaced PRB ownership.

    properties (SetAccess=private)
        InterlaceIndex
        InterlaceCount
        PRBSet
        Digest
    end

    methods
        function obj = PUCCHInterlacePlan(interlaceIndex,interlaceCount,nSizeGrid)
            sixgr.phy.pucch.PUCCHUtil.assertInteger(interlaceCount,1,32, ...
                "sixgr:phy:pucch:InvalidHopping","InterlaceCount");
            sixgr.phy.pucch.PUCCHUtil.assertInteger(interlaceIndex,0, ...
                interlaceCount-1,"sixgr:phy:pucch:InvalidHopping", ...
                "InterlaceIndex");
            sixgr.phy.pucch.PUCCHUtil.assertInteger(nSizeGrid,1,275, ...
                "sixgr:phy:pucch:InvalidHopping","NSizeGrid");
            obj.InterlaceIndex = double(interlaceIndex);
            obj.InterlaceCount = double(interlaceCount);
            obj.PRBSet = double(interlaceIndex):double(interlaceCount): ...
                double(nSizeGrid)-1;
            if isempty(obj.PRBSet)
                error("sixgr:phy:pucch:InvalidHopping", ...
                    "The configured interlace owns no PRBs.");
            end
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(struct( ...
                "InterlaceIndex",obj.InterlaceIndex, ...
                "InterlaceCount",obj.InterlaceCount, ...
                "PRBSet",obj.PRBSet));
        end
    end
end
