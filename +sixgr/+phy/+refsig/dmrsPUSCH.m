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
    try
        info.DMRSPortSet = double(puschCfg.DMRS.DMRSPortSet(:).');
        info.DMRSPortSetSource = ...
            "executed_nrPUSCHConfig.DMRS.DMRSPortSet";
    catch
        info.DMRSPortSet = [];
        info.DMRSPortSetSource = "";
    end
    try
        info.CDMLengths = reshape(double(dmrsIndInfo.CDMLengths), 1, []);
    catch
        info.CDMLengths = [];
    end
    info.CDMLengthsSource="nrPUSCHDMRSIndices_metadata";
    if isempty(info.CDMLengths)
        % Newer toolbox releases expose no secondary indices output. The
        % computed DM-RS property still owns OCC despreading. Empty lengths
        % make multiport pilot structure appear to be receiver noise.
        try
            info.CDMLengths=reshape(double(puschCfg.DMRS.CDMLengths),1,[]);
        catch
            error('sixgr:phy:dmrsPUSCH:CDMLengthsUnavailable', ...
                'PUSCH channel estimation requires authoritative DM-RS CDM lengths.');
        end
        info.CDMLengthsSource="nrPUSCHDMRSConfig_computed_CDM_lengths";
    end
    assert(numel(info.CDMLengths)==2 && all(isfinite(info.CDMLengths)) && ...
        all(info.CDMLengths>=1 & info.CDMLengths==fix(info.CDMLengths)), ...
        'sixgr:phy:dmrsPUSCH:InvalidCDMLengths','DM-RS CDM lengths must be two positive integers.');
end
