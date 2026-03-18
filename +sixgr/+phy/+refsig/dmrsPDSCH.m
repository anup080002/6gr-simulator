function [dmrsInd, dmrsSym, info, pdsch] = dmrsPDSCH(carrier, cfgOrPdsch, varargin)
%DMRSPDSCH Generate PDSCH DM-RS indices and symbols.
%
%   [ind,sym,info,pdsch] = sixgr.phy.refsig.dmrsPDSCH(carrier,cfg)
%   builds an nrPDSCHConfig from cfg and calls nrPDSCHDMRSIndices/nrPDSCHDMRS.
%
%   [ind,sym,info,pdsch] = sixgr.phy.refsig.dmrsPDSCH(carrier,pdschCfg)
%   uses the provided nrPDSCHConfig.
%
%   Name-Value overrides:
%     "IndexBase" - "0based" (default) or "1based"

opts.IndexBase = '0based';
for i = 1:2:numel(varargin)
    if i+1 > numel(varargin), break; end
    key = varargin{i}; val = varargin{i+1};
    if ~(ischar(key) || isstring(key)), continue; end
    switch lower(char(key))
        case 'indexbase'
            opts.IndexBase = char(val);
    end
end

if isa(cfgOrPdsch, 'nrPDSCHConfig')
    pdsch = cfgOrPdsch;
else
    % Reuse allocator to build a consistent nrPDSCHConfig
    [~, ~, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfgOrPdsch);
end

% NOTE (MATLAB R2024b/R2025b+): nrPDSCHDMRSIndices dropped the secondary
% output (dmrsIndInfo) for some calling syntaxes. Keep backward
% compatibility by probing the signature.
dmrsIndInfo = [];
try
    [dmrsInd, dmrsIndInfo] = nrPDSCHDMRSIndices(carrier, pdsch, 'IndexBase', opts.IndexBase);
catch ME
    if contains(ME.message, 'Too many output arguments')
        dmrsInd = nrPDSCHDMRSIndices(carrier, pdsch, 'IndexBase', opts.IndexBase);
        dmrsIndInfo = [];
    else
        rethrow(ME);
    end
end
dmrsSym = nrPDSCHDMRS(carrier, pdsch);

info = struct();
info.Channel = 'PDSCH-DMRS';
info.IndexBase = opts.IndexBase;
info.NumLayers = double(pdsch.NumLayers);
try
    info.DMRSPortSet = pdsch.DMRS.DMRSPortSet;
catch
    info.DMRSPortSet = [];
end
info.NRE = size(dmrsInd, 1);
% dmrsIndInfo may be empty on newer toolbox releases
info.DMRSIndicesInfo = dmrsIndInfo;

end
