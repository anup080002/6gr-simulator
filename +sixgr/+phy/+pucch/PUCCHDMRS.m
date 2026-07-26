classdef PUCCHDMRS
    %PUCCHDMRS Exact Toolbox-backed DM-RS generation with fail-closed errors.

    methods (Static)
        function result = generate(carrier,resource)
            if ~isa(resource,"sixgr.phy.pucch.PUCCHResource")
                error("sixgr:phy:pucch:DMRSGenerationFailed", ...
                    "PUCCHDMRS requires a typed resource.");
            end
            pucch = resource.toolboxConfig();
            try
                symbols = nrPUCCHDMRS(carrier,pucch);
                indices = nrPUCCHDMRSIndices(carrier,pucch);
            catch ME
                error("sixgr:phy:pucch:DMRSGenerationFailed", ...
                    "PUCCH format-%d DM-RS generation failed: %s", ...
                    resource.Format,ME.message);
            end
            result = struct("Symbols",symbols,"Indices",indices, ...
                "SequenceSHA256",sixgr.phy.pucch.PUCCHUtil.hash( ...
                [real(symbols(:)).' imag(symbols(:)).']), ...
                "IndexSHA256",sixgr.phy.pucch.PUCCHUtil.hash(double(indices(:).')));
        end
    end
end
