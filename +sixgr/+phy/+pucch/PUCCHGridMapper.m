classdef PUCCHGridMapper
    %PUCCHGRIDMAPPER Exact data/DM-RS mapping for the assigned resource.

    methods (Static)
        function result = map(carrier,assignment,pucchSymbols,transmissionPresent)
            if nargin<4, transmissionPresent=true; end
            validateattributes(transmissionPresent,{'logical'},{'scalar'});
            resource = assignment.Resource;
            pucch = resource.toolboxConfig();
            [dataIndices,info] = nrPUCCHIndices(carrier,pucch);
            if ~transmissionPresent
                assert(resource.Format<=1 && isempty(pucchSymbols), ...
                    'sixgr:phy:pucch:InvalidFormatPayload', ...
                    'Only explicitly suppressed short-format SR may map no symbols.');
            elseif numel(pucchSymbols) ~= numel(dataIndices)
                error("sixgr:phy:pucch:UCILengthMismatch", ...
                    "PUCCH symbol count %d does not match %d assigned REs.", ...
                    numel(pucchSymbols),numel(dataIndices));
            end
            dmrs = sixgr.phy.pucch.PUCCHDMRS.generate(carrier,resource);
            if ~transmissionPresent
                dataIndices=dataIndices([],:);
                dmrs.Indices=dmrs.Indices([],:);
                dmrs.Symbols=dmrs.Symbols([],:);
                dmrs.SequenceSHA256=sixgr.phy.pucch.PUCCHUtil.hash([]);
                dmrs.IndexSHA256=sixgr.phy.pucch.PUCCHUtil.hash([]);
            end
            ports = max([size(dataIndices,2),size(dmrs.Indices,2),1]);
            grid = complex(zeros(carrier.NSizeGrid*12, ...
                carrier.SymbolsPerSlot,ports));
            grid(dataIndices) = pucchSymbols;
            grid(dmrs.Indices) = dmrs.Symbols;
            ownership = sixgr.phy.pucch.PUCCHResourceOwnershipMap.build( ...
                carrier,assignment);
            if ~transmissionPresent
                ownership=sixgr.phy.pucch.PUCCHResourceOwnershipMap( ...
                    ownership.Table([],:),resource);
            end
            result = struct("Grid",grid,"DataIndices",dataIndices, ...
                "DMRS",dmrs,"PUCCHInfo",info,"Ownership",ownership, ...
                "GridDigest",sixgr.phy.pucch.PUCCHUtil.hash( ...
                [real(grid(:)).' imag(grid(:)).']));
        end
    end
end
