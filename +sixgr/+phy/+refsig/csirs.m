function [csirsInd, csirsSym, info, csirs] = csirs(carrier, cfgOrCsirs, varargin)
%CSIRS Generate CSI-RS indices and symbols.
%
%   [ind,sym,info,csirs] = sixgr.phy.refsig.csirs(carrier,cfg)
%   builds an nrCSIRSConfig from cfg.phy.csirs and calls nrCSIRSIndices/nrCSIRS.
%
%   If cfg.phy.csirs.enable is false (or missing), the function returns empty
%   indices/symbols and info.Enabled=false.
%
%   [ind,sym,info,csirs] = sixgr.phy.refsig.csirs(carrier,csirsCfg) uses the
%   provided nrCSIRSConfig.
%
%   Name-Value overrides:
%     "IndexBase" - "0based" or "1based" (best-effort; if unsupported by
%                   the installed 5G Toolbox, the function falls back to the
%                   default behavior).

opts.IndexBase = '';
for i = 1:2:numel(varargin)
    if i+1 > numel(varargin), break; end
    key = varargin{i}; val = varargin{i+1};
    if ~(ischar(key) || isstring(key)), continue; end
    switch lower(char(key))
        case 'indexbase'
            opts.IndexBase = char(val);
    end
end

if isa(cfgOrCsirs, 'nrCSIRSConfig')
    csirs = cfgOrCsirs;
    enabled = true;
elseif isstruct(cfgOrCsirs)
    enabled = logical(sixgr.util.structGet(cfgOrCsirs, 'phy.csirs.enable', false));
    if ~enabled
        csirsInd = zeros(0,1);
        csirsSym = complex(zeros(0,1));
        csirs = nrCSIRSConfig;
        info = struct('Channel','CSI-RS','Enabled',false);
        return;
    end
    csirs = localBuildFromCfg(carrier, cfgOrCsirs);
else
    error('csirs:InvalidInput', 'Second input must be a config struct or nrCSIRSConfig.');
end

% Indices and symbols
[csirsInd, csirsIndInfo] = localCSIRSIndices(carrier, csirs, opts.IndexBase);
csirsSym = nrCSIRS(carrier, csirs);

info = struct();
info.Channel = 'CSI-RS';
info.Enabled = true;
info.NRE = size(csirsInd, 1);
info.RowNumber = csirs.RowNumber;
try
    info.NumCSIRSPorts = csirs.NumCSIRSPorts;
catch
    info.NumCSIRSPorts = NaN;
end
info.CSIRSIndicesInfo = csirsIndInfo;

end

function csirs = localBuildFromCfg(carrier, cfg)
csirs = nrCSIRSConfig;

% Desired ports -> choose a RowNumber that matches
nPorts = double(sixgr.util.structGet(cfg, 'phy.csirs.nPorts', 2));
row = sixgr.util.structGet(cfg, 'phy.csirs.rowNumber', []);
if isempty(row)
    row = localFindRowForPorts(nPorts);
end
csirs.RowNumber = double(row);

% Basic placement defaults (can be overridden later when config expands)
csirs.SymbolLocations = double(sixgr.util.structGet(cfg, 'phy.csirs.symbolLocations', 0));
csirs.SubcarrierLocations = double(sixgr.util.structGet(cfg, 'phy.csirs.subcarrierLocations', 0));
csirs.NumRB = double(sixgr.util.structGet(cfg, 'phy.csirs.numRB', carrier.NSizeGrid));
csirs.RBOffset = double(sixgr.util.structGet(cfg, 'phy.csirs.rbOffset', 0));
cdm = sixgr.util.structGet(cfg, 'phy.csirs.cdmType', 'FD-CDM2');
csirs.CDMType = char(cdm);

% Scrambling identity
try
    csirs.NID = carrier.NCellID;
catch
end

end

function row = localFindRowForPorts(nPorts)
row = [];
for r = 1:18
    try
        tmp = nrCSIRSConfig;
        tmp.RowNumber = r;
        if isprop(tmp, 'NumCSIRSPorts')
            if double(tmp.NumCSIRSPorts) == double(nPorts)
                row = r;
                return;
            end
        end
    catch
        % ignore
    end
end
if isempty(row)
    error('csirs:NoMatchingRow', 'No nrCSIRSConfig.RowNumber found for nPorts=%d.', nPorts);
end
end

function [ind, indInfo] = localCSIRSIndices(carrier, csirs, indexBase)
% Some releases may not support IndexBase for nrCSIRSIndices.
if isempty(indexBase)
    [ind, indInfo] = nrCSIRSIndices(carrier, csirs);
    return;
end
try
    [ind, indInfo] = nrCSIRSIndices(carrier, csirs, 'IndexBase', indexBase);
catch
    [ind, indInfo] = nrCSIRSIndices(carrier, csirs);
end
end
