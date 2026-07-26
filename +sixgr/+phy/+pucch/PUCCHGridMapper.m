classdef PUCCHGridMapper
    %PUCCHGRIDMAPPER Exact data/DM-RS mapping for the assigned resource.

    methods (Static)
        function result = map(carrier,assignment,pucchSymbols)
            resource = assignment.Resource;
            pucch = resource.toolboxConfig();
            [dataIndices,info] = nrPUCCHIndices(carrier,pucch);
            if numel(pucchSymbols) ~= numel(dataIndices)
                error("sixgr:phy:pucch:UCILengthMismatch", ...
                    "PUCCH symbol count %d does not match %d assigned REs.", ...
                    numel(pucchSymbols),numel(dataIndices));
            end
            dmrs = sixgr.phy.pucch.PUCCHDMRS.generate(carrier,resource);
            ports = max([size(dataIndices,2),size(dmrs.Indices,2),1]);
            grid = complex(zeros(carrier.NSizeGrid*12, ...
                carrier.SymbolsPerSlot,ports));
            grid(dataIndices) = pucchSymbols;
            grid(dmrs.Indices) = dmrs.Symbols;
            ownership = sixgr.phy.pucch.PUCCHResourceOwnershipMap.build( ...
                carrier,assignment);
            result = struct("Grid",grid,"DataIndices",dataIndices, ...
                "DMRS",dmrs,"PUCCHInfo",info,"Ownership",ownership, ...
                "GridDigest",sixgr.phy.pucch.PUCCHUtil.hash( ...
                [real(grid(:)).' imag(grid(:)).']));
        end
    end
end
