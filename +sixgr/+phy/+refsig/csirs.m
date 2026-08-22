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
    sixgr.config.assertRuntimeFeatureUse(cfgOrCsirs, "csi_rs", enabled, ...
        "sixgr.phy.refsig.csirs");
    if ~enabled
        csirsInd = zeros(0,1);
        csirsSym = complex(zeros(0,1));
        csirs = nrCSIRSConfig;
        info = struct('Channel','CSI-RS','Enabled',false);
        return;
    end
    numResources = double(sixgr.util.structGet(cfgOrCsirs, 'phy.csirs.numResources', 1));
    if ~(isscalar(numResources) && isfinite(numResources) && ...
            numResources >= 1 && numResources == round(numResources))
        error('sixgr:phy:csirs:InvalidResourceCount', ...
            'phy.csirs.numResources must be a positive integer.');
    end
    if numResources > 1
        [csirsInd, csirsSym, info, csirs] = ...
            localGenerateConfiguredResourceSet(carrier, cfgOrCsirs, opts.IndexBase, numResources);
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
info.RBOffset = double(csirs.RBOffset);
info.NumRB = double(csirs.NumRB);
info.SymbolLocations = double(csirs.SymbolLocations(:).');
info.SubcarrierLocations = double(csirs.SubcarrierLocations(:).');
try
    info.Density = string(csirs.Density);
catch
    info.Density = "";
end
try
    info.CDMType = string(csirs.CDMType);
catch
    info.CDMType = "";
end
resourceID = 0;
if isstruct(cfgOrCsirs)
    resourceID = double(sixgr.util.structGet(cfgOrCsirs, 'phy.csirs.resourceID', 0));
end
info.ResourceID = resourceID;
info.ResourceSetID = double(0);
if isstruct(cfgOrCsirs)
    info.ResourceSetID = double(sixgr.util.structGet(cfgOrCsirs, 'phy.csirs.resourceSetID', 0));
end
info.NumResources = 1;
info.ResourceMappingTable = localCSIRSResourceMappingTable(carrier, csirs, csirsInd, csirsSym, opts.IndexBase, resourceID);
info.CausalMeasurementRole = "CSI-RS -> DL CSI/RI/PMI/CQI measurement producer";
info.MeasurementStateContract = "ProducerSlot/AvailableSlot must be <= consuming grant slot; runtime estimator remains pilot-based";

end

function [combinedInd, combinedSym, info, primaryConfig] = ...
        localGenerateConfiguredResourceSet(carrier, cfg, indexBase, numResources)
resourceIDs = localRequiredResourceVector(cfg, 'phy.csirs.resourceIDs', numResources, ...
    'sixgr:phy:csirs:MissingResourceIDs');
rowNumbers = localRequiredResourceVector(cfg, 'phy.csirs.rowNumbers', numResources, ...
    'sixgr:phy:csirs:MissingRowNumbers');
symbolLocations = localRequiredResourceVector(cfg, ...
    'phy.csirs.symbolLocationsByResource', numResources, ...
    'sixgr:phy:csirs:MissingSymbolLocations');
subcarrierLocations = localRequiredResourceVector(cfg, ...
    'phy.csirs.subcarrierLocationsByResource', numResources, ...
    'sixgr:phy:csirs:MissingSubcarrierLocations');
rbOffsets = localRequiredResourceVector(cfg, 'phy.csirs.rbOffsetsByResource', ...
    numResources, 'sixgr:phy:csirs:MissingRBOffsets');
numRBs = localRequiredResourceVector(cfg, 'phy.csirs.numRBsByResource', ...
    numResources, 'sixgr:phy:csirs:MissingNumRBs');
if numel(unique(resourceIDs)) ~= numResources || any(resourceIDs < 0) || ...
        any(resourceIDs ~= round(resourceIDs))
    error('sixgr:phy:csirs:InvalidResourceIDs', ...
        'CSI-RS resource IDs must be unique nonnegative integers.');
end

resources = repmat(localEmptyResourceEvidence(), numResources, 1);
indexParts = cell(numResources, 1);
symbolParts = cell(numResources, 1);
mappingParts = cell(numResources, 1);
occupied = cell(numResources, 1);
primaryConfig = [];
K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
plane = K * L;
for ordinal = 1:numResources
    cfgResource = cfg;
    cfgResource = sixgr.util.structSet(cfgResource, 'phy.csirs.resourceID', resourceIDs(ordinal));
    cfgResource = sixgr.util.structSet(cfgResource, 'phy.csirs.rowNumber', rowNumbers(ordinal));
    cfgResource = sixgr.util.structSet(cfgResource, 'phy.csirs.symbolLocations', symbolLocations(ordinal));
    cfgResource = sixgr.util.structSet(cfgResource, 'phy.csirs.subcarrierLocations', subcarrierLocations(ordinal));
    cfgResource = sixgr.util.structSet(cfgResource, 'phy.csirs.rbOffset', rbOffsets(ordinal));
    cfgResource = sixgr.util.structSet(cfgResource, 'phy.csirs.numRB', numRBs(ordinal));
    resourceConfig = localBuildFromCfg(carrier, cfgResource);
    [indices, indexInfo] = localCSIRSIndices(carrier, resourceConfig, indexBase);
    symbols = nrCSIRS(carrier, resourceConfig);
    if isempty(indices) || isempty(symbols)
        error('sixgr:phy:csirs:EmptyResource', ...
            'Configured CSI-RS resource %g resolved to no REs.', resourceIDs(ordinal));
    end
    baseOne = unique(mod(double(indices(:)) - 1, plane) + 1);
    for prior = 1:(ordinal - 1)
        if ~isempty(intersect(baseOne, occupied{prior}))
            error('sixgr:phy:csirs:ResourceCollision', ...
                'CSI-RS resources %g and %g overlap on physical REs.', ...
                resourceIDs(prior), resourceIDs(ordinal));
        end
    end
    occupied{ordinal} = baseOne;
    mapping = localCSIRSResourceMappingTable(carrier, resourceConfig, ...
        indices, symbols, indexBase, resourceIDs(ordinal));
    resources(ordinal).ResourceID = resourceIDs(ordinal);
    resources(ordinal).ResourceSetID = double(sixgr.util.structGet(cfg, ...
        'phy.csirs.resourceSetID', 0));
    resources(ordinal).Configuration = resourceConfig;
    resources(ordinal).Indices = indices;
    resources(ordinal).Symbols = symbols;
    resources(ordinal).IndicesInfo = indexInfo;
    resources(ordinal).ResourceMappingTable = mapping;
    resources(ordinal).NRE = numel(symbols);
    resources(ordinal).RowNumber = double(resourceConfig.RowNumber);
    resources(ordinal).SymbolLocations = double(resourceConfig.SymbolLocations(:).');
    resources(ordinal).SubcarrierLocations = double(resourceConfig.SubcarrierLocations(:).');
    resources(ordinal).RBOffset = double(resourceConfig.RBOffset);
    resources(ordinal).NumRB = double(resourceConfig.NumRB);
    resources(ordinal).NumPorts = double(resourceConfig.NumCSIRSPorts);
    indexParts{ordinal} = indices;
    symbolParts{ordinal} = symbols;
    mappingParts{ordinal} = mapping;
    if ordinal == 1
        primaryConfig = resourceConfig;
    end
end
combinedInd = vertcat(indexParts{:});
combinedSym = vertcat(symbolParts{:});
info = struct();
info.Channel = 'CSI-RS';
info.Enabled = true;
info.NumResources = numResources;
info.ResourceIDs = resourceIDs(:).';
info.ResourceSetID = double(sixgr.util.structGet(cfg, 'phy.csirs.resourceSetID', 0));
info.Resources = resources;
info.NRE = numel(combinedSym);
info.RowNumber = rowNumbers(:).';
info.NumCSIRSPorts = resources(1).NumPorts;
info.RBOffset = rbOffsets(:).';
info.NumRB = numRBs(:).';
info.SymbolLocations = symbolLocations(:).';
info.SubcarrierLocations = subcarrierLocations(:).';
info.Density = "one";
info.CDMType = "FD-CDM2";
info.ResourceMappingTable = vertcat(mappingParts{:});
info.CausalMeasurementRole = "CSI-RS resource set -> measured CRI/RI/PMI/CQI";
info.MeasurementStateContract = ...
    "Every CRI candidate is a disjoint transmitted NZP CSI-RS resource measured at the receiver";
end

function values = localRequiredResourceVector(cfg, path, count, identifier)
values = double(sixgr.util.structGet(cfg, path, []));
if ~(isvector(values) && numel(values) == count && all(isfinite(values)))
    error(identifier, '%s must contain one finite value per CSI-RS resource.', path);
end
values = values(:).';
end

function resource = localEmptyResourceEvidence()
resource = struct('ResourceID',NaN,'ResourceSetID',NaN,'Configuration',[], ...
    'Indices',[],'Symbols',[],'IndicesInfo',struct(), ...
    'ResourceMappingTable',table(),'NRE',NaN,'RowNumber',NaN, ...
    'SymbolLocations',[],'SubcarrierLocations',[],'RBOffset',NaN, ...
    'NumRB',NaN,'NumPorts',NaN);
end

function csirs = localBuildFromCfg(carrier, cfg)
csirs = nrCSIRSConfig;

% Desired ports -> choose a RowNumber that matches
nPorts = double(sixgr.util.structGet(cfg, 'phy.csirs.nPorts', 2));
row = sixgr.util.structGet(cfg, 'phy.csirs.rowNumber', []);
densityReq = sixgr.util.structGet(cfg, 'phy.csirs.density', '');
cdmReq = sixgr.util.structGet(cfg, 'phy.csirs.cdmType', '');
if isempty(row)
    row = localFindRowForPorts(nPorts, densityReq, cdmReq);
end
csirs.RowNumber = double(row);
if double(csirs.NumCSIRSPorts) ~= nPorts
    error('sixgr:phy:csirs:ConfiguredPortRowMismatch', ...
        ['phy.csirs.nPorts=%g conflicts with CSI-RS RowNumber=%g, which ' ...
         'defines %g ports in TS 38.211 Table 7.4.1.5.3-1. Correct the ' ...
         'YAML row/port authority; the waveform generator will not ' ...
         'silently change either value.'], ...
        nPorts, double(row), double(csirs.NumCSIRSPorts));
end

% Basic placement defaults. Multi-port CSI-RS rows require different k_i/l_i
% vector lengths; use valid NR Toolbox defaults unless config overrides them.
csirs.SymbolLocations = double(sixgr.util.structGet(cfg, 'phy.csirs.symbolLocations', localDefaultSymbolLocations(row)));
csirs.SubcarrierLocations = double(sixgr.util.structGet(cfg, 'phy.csirs.subcarrierLocations', localDefaultSubcarrierLocations(row)));
csirs.NumRB = double(sixgr.util.structGet(cfg, 'phy.csirs.numRB', carrier.NSizeGrid));
csirs.RBOffset = double(sixgr.util.structGet(cfg, 'phy.csirs.rbOffset', 0));
% Slot occasion selection is enforced by the production PDSCH transmitter
% before calling this generator.  Keep the Toolbox resource active for the
% selected occasion rather than allowing nrCSIRSConfig to hide an empty
% non-occasion behind an apparently enabled feature.
csirs.CSIRSPeriod = 'on';
try
    if isempty(densityReq)
        densityReq = localDefaultDensity(row);
    end
    csirs.Density = char(string(densityReq));
catch
end
cdm = cdmReq;
if isempty(cdm)
    cdm = localDefaultCDMType(row);
end
try
    csirs.CDMType = char(cdm);
catch
    % Some 5G Toolbox releases make CDMType read-only and derive it from
    % RowNumber. Keep generation runtime-backed instead of failing on an
    % optional override that this release cannot apply directly.
end

% Scrambling identity
try
    csirs.NID = localResolveCSIRSScramblingID(cfg, carrier);
catch
end

end

function nID = localResolveCSIRSScramblingID(cfg, carrier)
nID = double(sixgr.util.structGet(cfg, 'phy.csirs.scramblingID', ...
    sixgr.util.structGet(cfg, 'phy.csirs.ScramblingID', ...
    sixgr.util.structGet(cfg, 'reference_signals.csirs_scrambling_id', ...
    sixgr.util.structGet(cfg, 'reference_signals.csi_rs_scrambling_id', carrier.NCellID)))));
if ~(isscalar(nID) && isfinite(nID))
    nID = double(carrier.NCellID);
end
nID = mod(round(nID), 1024);
end

function row = localFindRowForPorts(nPorts, density, cdmType)
% TS 38.211 Table 7.4.1.5.3-1: CSI-RS row mapping.
rows = localCSIRSRowTable();
ports = [rows.NumPorts];
nPorts = max(1, round(double(nPorts)));
validPorts = unique(ports);
idxPort = find(validPorts >= nPorts, 1, 'first');
if isempty(idxPort)
    actualPorts = max(validPorts);
    warning('sixgr:phy:csirs:PortCountUnsupported', ...
        'nPorts=%d is not supported by NR CSI-RS rows; using maximum %d.', nPorts, actualPorts);
else
    actualPorts = validPorts(idxPort);
    if actualPorts ~= nPorts
        warning('sixgr:phy:csirs:PortCountRoundedUp', ...
            'nPorts=%d rounded up to %d (nearest NR CSI-RS configuration).', nPorts, actualPorts);
    end
end
candidates = rows(ports == actualPorts);

densityToken = localNormalizeDensityToken(density);
if strlength(densityToken) > 0
    mask = strcmpi({candidates.Density}, char(densityToken));
    if any(mask)
        candidates = candidates(mask);
    end
end
cdmToken = lower(strtrim(string(cdmType)));
if strlength(cdmToken) > 0
    mask = strcmpi({candidates.CDMType}, char(cdmToken));
    if any(mask)
        candidates = candidates(mask);
    end
end
row = double(candidates(1).RowNumber);
try
    probe = nrCSIRSConfig;
    probe.RowNumber = row;
catch ME
    error('csirs:NoMatchingRow', 'Chosen CSI-RS row %d is not valid in this MATLAB release: %s', row, ME.message);
end
end

function rows = localCSIRSRowTable()
rows = struct('RowNumber',{},'NumPorts',{},'Density',{},'CDMType',{});
rows(end+1) = struct('RowNumber',1,  'NumPorts',1,  'Density','three', 'CDMType','NoCDM');
rows(end+1) = struct('RowNumber',2,  'NumPorts',1,  'Density','one',   'CDMType','NoCDM');
rows(end+1) = struct('RowNumber',3,  'NumPorts',2,  'Density','one',   'CDMType','FD-CDM2');
rows(end+1) = struct('RowNumber',4,  'NumPorts',4,  'Density','one',   'CDMType','FD-CDM2');
rows(end+1) = struct('RowNumber',5,  'NumPorts',4,  'Density','one',   'CDMType','CDM4-FD2-TD2');
rows(end+1) = struct('RowNumber',6,  'NumPorts',8,  'Density','one',   'CDMType','FD-CDM2');
rows(end+1) = struct('RowNumber',7,  'NumPorts',8,  'Density','one',   'CDMType','CDM4-FD2-TD2');
rows(end+1) = struct('RowNumber',8,  'NumPorts',8,  'Density','one',   'CDMType','CDM8-FD2-TD4');
rows(end+1) = struct('RowNumber',9,  'NumPorts',12, 'Density','one',   'CDMType','FD-CDM2');
rows(end+1) = struct('RowNumber',10, 'NumPorts',12, 'Density','one',   'CDMType','CDM4-FD2-TD2');
rows(end+1) = struct('RowNumber',11, 'NumPorts',16, 'Density','one',   'CDMType','FD-CDM2');
rows(end+1) = struct('RowNumber',12, 'NumPorts',16, 'Density','one',   'CDMType','CDM4-FD2-TD2');
rows(end+1) = struct('RowNumber',13, 'NumPorts',24, 'Density','one',   'CDMType','FD-CDM2');
rows(end+1) = struct('RowNumber',14, 'NumPorts',24, 'Density','one',   'CDMType','CDM4-FD2-TD2');
rows(end+1) = struct('RowNumber',15, 'NumPorts',32, 'Density','one',   'CDMType','FD-CDM2');
rows(end+1) = struct('RowNumber',16, 'NumPorts',32, 'Density','one',   'CDMType','CDM4-FD2-TD2');
rows(end+1) = struct('RowNumber',17, 'NumPorts',32, 'Density','one',   'CDMType','CDM8-FD2-TD4');
rows(end+1) = struct('RowNumber',18, 'NumPorts',32, 'Density','one',   'CDMType','CDM8-FD2-TD4');
end

function token = localNormalizeDensityToken(raw)
if isempty(raw)
    token = "";
    return;
end
if isnumeric(raw)
    if abs(double(raw) - 3) < 1e-9
        token = "three";
    else
        token = "one";
    end
else
    token = lower(strtrim(string(raw)));
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

function cdm = localDefaultCDMType(row)
rows = localCSIRSRowTable();
match = find([rows.RowNumber] == round(double(row)), 1, 'first');
if isempty(match)
    cdm = 'FD-CDM2';
else
    cdm = rows(match).CDMType;
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

function T = localCSIRSResourceMappingTable(carrier, csirs, ind, sym, indexBase, resourceID)
if nargin < 6
    resourceID = 0;
end
idx = localFlattenIndex(ind);
sym = localFlattenSymbols(sym);
if strcmpi(string(indexBase), "0based")
    idxForSub = idx + 1;
else
    idxForSub = idx;
end
K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
try
    P = double(csirs.NumCSIRSPorts);
catch
    P = 1;
end
P = max(1, round(P));
N = min(numel(idxForSub), numel(sym));
rows = repmat(localCSIRSResourceRow(), N, 1);
if N == 0
    T = struct2table(rows);
    return;
end
[subcarrier, symbol, port] = ind2sub([K L P], double(idxForSub(1:N)));
for ii = 1:N
    rows(ii) = localCSIRSResourceRow();
    rows(ii).Slot = double(carrier.NSlot);
    rows(ii).ResourceID = double(resourceID);
    rows(ii).Symbol = double(symbol(ii) - 1);
    rows(ii).Subcarrier = double(subcarrier(ii) - 1);
    rows(ii).PRB = double(floor((subcarrier(ii) - 1) / 12));
    rows(ii).Port = double(port(ii) - 1);
    rows(ii).RowNumber = double(csirs.RowNumber);
    rows(ii).RBOffset = double(csirs.RBOffset);
    rows(ii).NumRB = double(csirs.NumRB);
    rows(ii).LinearIndex = double(idx(ii));
    rows(ii).SymbolI = double(real(sym(ii)));
    rows(ii).SymbolQ = double(imag(sym(ii)));
    rows(ii).SourceSignal = "CSI-RS";
    rows(ii).TruthStatus = "real_lls_evidence";
end
T = struct2table(rows, "AsArray", true);
end

function idx = localFlattenIndex(ind)
if iscell(ind)
    parts = cellfun(@(x) double(x(:)), ind(:), "UniformOutput", false);
    idx = vertcat(parts{:});
else
    idx = double(ind(:));
end
end

function sym = localFlattenSymbols(symIn)
if iscell(symIn)
    parts = cellfun(@(x) x(:), symIn(:), "UniformOutput", false);
    sym = vertcat(parts{:});
else
    sym = symIn(:);
end
end

function row = localCSIRSResourceRow()
row = struct("Slot", NaN, "Symbol", NaN, "Subcarrier", NaN, "PRB", NaN, ...
    "Port", NaN, "ResourceID", NaN, "RowNumber", NaN, "RBOffset", NaN, "NumRB", NaN, ...
    "LinearIndex", NaN, "SymbolI", NaN, "SymbolQ", NaN, ...
    "SourceSignal", "", "TruthStatus", "");
end
