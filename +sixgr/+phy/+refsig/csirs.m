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

% Basic placement defaults. Multi-port CSI-RS rows require different k_i/l_i
% vector lengths; use valid NR Toolbox defaults unless config overrides them.
csirs.SymbolLocations = double(sixgr.util.structGet(cfg, 'phy.csirs.symbolLocations', localDefaultSymbolLocations(row)));
csirs.SubcarrierLocations = double(sixgr.util.structGet(cfg, 'phy.csirs.subcarrierLocations', localDefaultSubcarrierLocations(row)));
csirs.NumRB = double(sixgr.util.structGet(cfg, 'phy.csirs.numRB', carrier.NSizeGrid));
csirs.RBOffset = double(sixgr.util.structGet(cfg, 'phy.csirs.rbOffset', 0));
try
    csirs.Density = char(string(sixgr.util.structGet(cfg, 'phy.csirs.density', localDefaultDensity(row))));
catch
end
cdm = sixgr.util.structGet(cfg, 'phy.csirs.cdmType', 'FD-CDM2');
try
    csirs.CDMType = char(cdm);
catch
    % Some 5G Toolbox releases make CDMType read-only and derive it from
    % RowNumber. Keep generation runtime-backed instead of failing on an
    % optional override that this release cannot apply directly.
end

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

function loc = localDefaultSubcarrierLocations(row)
switch double(row)
    case {6, 11, 12, 16, 17, 18}
        loc = [0 3 6 9];
    case {7, 8}
        loc = [0 6];
    case 9
        loc = [0 2 4 6 8 10];
    case {10, 13, 14, 15}
        loc = [0 4 8];
    otherwise
        loc = 0;
end
end

function loc = localDefaultSymbolLocations(row)
switch double(row)
    case {13, 14, 16, 17}
        loc = [0 2];
    otherwise
        loc = 0;
end
end

function density = localDefaultDensity(row)
if double(row) == 1
    density = "three";
else
    density = "one";
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
