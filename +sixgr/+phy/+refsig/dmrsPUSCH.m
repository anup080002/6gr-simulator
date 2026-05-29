function [dmrsInd, dmrsSym, info] = dmrsPUSCH(carrier, puschCfg, varargin)
%DMRSPUSCH Generate PUSCH DM-RS indices and symbols.
%
%   [DMRSIND,DMRSSYM,INFO] = sixgr.phy.refsig.dmrsPUSCH(CARRIER,PUSCHCFG)
%   returns DM-RS RE indices and symbols for the given carrier and PUSCH
%   configuration.
%
%   This wrapper is resilient to 5G Toolbox API changes across releases.
%   In MATLAB R2025b, nrPUSCHDMRSIndices returns a single output argument
%   (indices only). Earlier releases may return a second info output.
%
%   Name-Value:
%     "IndexBase" - "1based" (default) or "0based" (applies for subscript)

    opts.IndexBase = '1based';

    for i = 1:2:numel(varargin)
        if i+1 > numel(varargin), break; end
        key = varargin{i};
        val = varargin{i+1};
        if ~(ischar(key) || isstring(key)), continue; end
        switch lower(char(key))
            case 'indexbase'
                opts.IndexBase = char(val);
        end
    end

    % --- Indices (handle 1-output vs 2-output toolbox behavior) ----------
    dmrsIndInfo = struct();
    try
        [dmrsInd, dmrsIndInfo] = nrPUSCHDMRSIndices(carrier, puschCfg, 'IndexBase', opts.IndexBase);
    catch
        dmrsInd = nrPUSCHDMRSIndices(carrier, puschCfg, 'IndexBase', opts.IndexBase);
        dmrsIndInfo = struct();
    end

    % --- Symbols ----------------------------------------------------------
    dmrsSym = nrPUSCHDMRS(carrier, puschCfg);

    info = struct();
    info.Channel = 'PUSCH';
    info.IndexBase = opts.IndexBase;
    info.DMRSIndicesInfo = dmrsIndInfo;
end
