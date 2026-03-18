function [ptrsInd, ptrsSym, info, pdsch] = ptrsPDSCH(carrier, cfgOrPdsch, varargin)
%PTRSPDSCH Generate PDSCH PT-RS indices and symbols.
%
%   [ind,sym,info,pdsch] = sixgr.phy.refsig.ptrsPDSCH(carrier,cfg)
%   builds an nrPDSCHConfig from cfg and calls nrPDSCHPTRSIndices/nrPDSCHPTRS.
%
%   If PTRS is disabled (pdsch.EnablePTRS==false), the function returns empty
%   indices/symbols and info.Enabled=false.
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
    [~, ~, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfgOrPdsch);
end

% Determine PTRS enable flag robustly
enabled = false;
try
    enabled = logical(pdsch.EnablePTRS);
catch
    enabled = false;
end

if ~enabled
    ptrsInd = zeros(0,1);
    ptrsSym = complex(zeros(0,1));
    info = struct('Channel','PDSCH-PTRS','Enabled',false,'IndexBase',opts.IndexBase);
    return;
end

% nrPDSCHPTRSIndices returns indices only (no info output argument).
ptrsInd = nrPDSCHPTRSIndices(carrier, pdsch, 'IndexBase', opts.IndexBase);
ptrsIndInfo = struct('NRE', size(ptrsInd,1));
ptrsSym = nrPDSCHPTRS(carrier, pdsch);

info = struct();
info.Channel = 'PDSCH-PTRS';
info.Enabled = true;
info.IndexBase = opts.IndexBase;
info.NRE = size(ptrsInd, 1);
info.PTRSIndicesInfo = ptrsIndInfo;

end
