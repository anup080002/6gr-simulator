function [puschInd, info, pusch] = allocREsPUSCH(carrier, cfgOrPusch, varargin)
%ALLOCRESPUSCH PUSCH RE allocation indices from config.
%
%   [ind,info,pusch] = sixgr.phy.grid.allocREsPUSCH(carrier,cfg) creates an
%   nrPUSCHConfig from cfg.phy.pusch and calls nrPUSCHIndices.
%
%   [ind,info,pusch] = sixgr.phy.grid.allocREsPUSCH(carrier,puschCfg) uses
%   the provided nrPUSCHConfig.
%
%   Name-Value overrides (all optional):
%     "IndexBase"        - "1based" (default) or "0based"
%     "PRBSet"           - PRB set vector or [start end]
%     "SymbolAllocation" - [startSym nSym]
%     "Modulation"       - e.g., "QPSK", "16QAM"
%     "NumLayers"        - number of layers
%     "RNTI"             - UE RNTI
%     "TransformPrecoding"- true/false
%     "TransmissionScheme"- "nonCodeBook" or "codebook"
%     "NumAntennaPorts"  - UL codebook antenna ports
%     "TPMI"             - UL codebook TPMI/PMI
%     "NID"              - PUSCH scrambling identity
%     "MappingType"      - "A" or "B"
%     "FixedReferenceMode" - true rejects implicit mapping mutations

opts.IndexBase = '1based';
opts.PRBSet = [];
opts.SymbolAllocation = [];
opts.Modulation = '';
opts.NumLayers = [];
opts.RNTI = [];
opts.TransformPrecoding = [];
opts.TransmissionScheme = '';
opts.NumAntennaPorts = [];
opts.TPMI = [];
opts.NID = [];
opts.MappingType = '';
opts.MappingTypeExplicit = false;
opts.FixedReferenceMode = false;

for i = 1:2:numel(varargin)
    if i+1 > numel(varargin), break; end
    key = varargin{i};
    val = varargin{i+1};
    if ~(ischar(key) || isstring(key)), continue; end
    k = lower(char(key));
    switch k
        case 'indexbase'
            opts.IndexBase = char(val);
        case 'prbset'
            opts.PRBSet = val;
        case 'symbolallocation'
            opts.SymbolAllocation = val;
        case 'modulation'
            opts.Modulation = char(val);
        case 'numlayers'
            opts.NumLayers = val;
        case 'rnti'
            opts.RNTI = val;
        case 'transformprecoding'
            opts.TransformPrecoding = val;
        case 'transmissionscheme'
            opts.TransmissionScheme = char(string(val));
        case {'numantennaports','numports','nports'}
            opts.NumAntennaPorts = val;
        case {'tpmi','pmi'}
            opts.TPMI = val;
        case 'nid'
            opts.NID = val;
        case 'mappingtype'
            opts.MappingType = char(string(val));
            opts.MappingTypeExplicit = true;
        case 'fixedreferencemode'
            opts.FixedReferenceMode = logical(val);
    end
end

if isa(cfgOrPusch, 'nrPUSCHConfig')
    pusch = cfgOrPusch;
else
    pusch = localBuildFromCfg(carrier, cfgOrPusch, opts);
end

try
    [puschInd, puschIndInfo] = nrPUSCHIndices(carrier, pusch, 'IndexStyle', 'index', 'IndexBase', opts.IndexBase);
catch
    [puschInd, puschIndInfo] = nrPUSCHIndices(carrier, pusch, 'IndexBase', opts.IndexBase);
end

info = struct();
info.Channel = 'PUSCH';
info.IndexBase = opts.IndexBase;
info.Modulation = char(string(pusch.Modulation));
info.NumLayers = double(pusch.NumLayers);
info.RNTI = double(pusch.RNTI);
info.TransformPrecoding = logical(pusch.TransformPrecoding);
info.TransmissionScheme = char(localObjectValue(pusch, 'TransmissionScheme', ''));
info.NumAntennaPorts = double(localObjectValue(pusch, 'NumAntennaPorts', NaN));
info.TPMI = double(localObjectValue(pusch, 'TPMI', NaN));
info.CodebookType = char(string(localObjectValue(pusch, 'CodebookType', '')));
info.BetaOffsetACK = double(localObjectValue(pusch, 'BetaOffsetACK', NaN));
info.BetaOffsetCSI1 = double(localObjectValue(pusch, 'BetaOffsetCSI1', NaN));
info.BetaOffsetCSI2 = double(localObjectValue(pusch, 'BetaOffsetCSI2', NaN));
info.UCIScaling = double(localObjectValue(pusch, 'UCIScaling', NaN));
info.PRBSet = pusch.PRBSet;
info.SymbolAllocation = pusch.SymbolAllocation;
info.NRE = size(puschInd, 1);
info.PUSCHIndicesInfo = puschIndInfo;
info.ResourceAccounting = sixgr.phy.resource.computeResourceAccounting("PUSCH", carrier, pusch, ...
    "ChannelIndices", puschInd, ...
    "AllocationInfo", info, ...
    "IndexBase", opts.IndexBase);
info.LayerDataRE = info.ResourceAccounting.LayerDataRE;
info.PortMappedRE = info.ResourceAccounting.PortMappedRE;
info.ModulationSymbolCount = info.ResourceAccounting.ModulationSymbolCount;
info.CodedBitCountG = info.ResourceAccounting.CodedBitCountG;
info.G = info.ResourceAccounting.CodedBitCountG;
info.NREPerPRB = info.ResourceAccounting.NREPerPRBForTBS;
info.DMRSRE = info.ResourceAccounting.DMRSRE;
info.PTRSRE = info.ResourceAccounting.PTRSRE;
info.ReservedRE = info.ResourceAccounting.ReservedRE;

end

function pusch = localBuildFromCfg(carrier, cfg, opts)
% Build nrPUSCHConfig from explicit resolved configuration.

pusch = nrPUSCHConfig;

% Basic PHY settings
mod = char(string(sixgr.util.structGet(cfg, 'phy.pusch.modulation', '')));
nl  = double(sixgr.util.structGet(cfg, 'phy.pusch.numLayers', ...
    sixgr.util.structGet(cfg, 'phy.pusch.nLayers', NaN)));
rnti = double(sixgr.util.structGet(cfg, 'phy.pusch.RNTI', NaN));
nid = sixgr.util.structGet(cfg, 'phy.pusch.NID', ...
    sixgr.util.structGet(cfg, 'phy.pusch.nid', []));
prb = sixgr.util.structGet(cfg, 'phy.pusch.prbSet', []);
symAlloc = sixgr.util.structGet(cfg, 'phy.pusch.symbolAllocation', []);
tdraID = string(sixgr.util.structGet(cfg, 'phy.pusch.tdraId', ...
    sixgr.util.structGet(cfg, 'phy.pusch.TDRAID', '')));
tpRaw = sixgr.util.structGet(cfg, 'phy.pusch.transformPrecoding', []);
tp = [];
if ~isempty(tpRaw)
    tp = logical(tpRaw);
end
tpmi = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.tpmi', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.TPMI', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.pmi', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.PMI', []));
transmissionScheme = char(string(sixgr.util.structGet(cfg, 'phy.pusch.transmissionScheme', ...
    sixgr.util.structGet(cfg, 'phy.pusch.TransmissionScheme', ''))));
[numAntennaPorts, numAntennaPortsExplicit] = localResolvePUSCHAntennaPorts(cfg);
codebookType = char(string(sixgr.util.structGet(cfg, 'phy.pusch.codebookType', ...
    sixgr.util.structGet(cfg, 'phy.pusch.CodebookType', ''))));
mapType = upper(char(string(sixgr.util.structGet(cfg, 'phy.pusch.mappingType', ...
    sixgr.util.structGet(cfg, 'phy.pusch.MappingType', '')))));
mapTypeExplicit = strlength(strtrim(string(sixgr.util.structGet(cfg, 'phy.pusch.mappingType', ...
    sixgr.util.structGet(cfg, 'phy.pusch.MappingType', ''))))) > 0;

% Apply overrides
if ~isempty(opts.Modulation), mod = char(opts.Modulation); end
if ~isempty(opts.NumLayers), nl = double(opts.NumLayers); end
if ~isempty(opts.RNTI), rnti = double(opts.RNTI); end
if ~isempty(opts.NID), nid = opts.NID; end
if ~isempty(opts.PRBSet), prb = opts.PRBSet; end
if ~isempty(opts.SymbolAllocation), symAlloc = opts.SymbolAllocation; end
if ~isempty(opts.TransformPrecoding), tp = logical(opts.TransformPrecoding); end
if ~isempty(opts.TPMI), tpmi = localFirstFiniteScalar(opts.TPMI); end
if ~isempty(opts.TransmissionScheme), transmissionScheme = char(string(opts.TransmissionScheme)); end
if ~isempty(opts.NumAntennaPorts)
    numAntennaPorts = localFirstFiniteScalar(opts.NumAntennaPorts);
    numAntennaPortsExplicit = true;
end
if ~isempty(opts.MappingType)
    mapType = upper(char(string(opts.MappingType)));
    mapTypeExplicit = logical(opts.MappingTypeExplicit);
end
if isempty(strtrim(mod))
    error("sixgr:pusch:UnsupportedModulation", ...
        "PUSCH modulation must be explicit in the resolved configuration or assignment.");
end
mod = char(sixgr.phy.ul.pusch.PUSCHModulator.normalizeModulation(mod));
if ~(isscalar(nl) && isfinite(nl) && nl == fix(nl) && nl >= 1 && nl <= 8)
    error("sixgr:pusch:UnsupportedLayerCodewordTuple", ...
        "PUSCH NumLayers must be an explicit integer in [1,8].");
end
if ~(isscalar(rnti) && isfinite(rnti) && rnti == fix(rnti) ...
        && rnti >= 0 && rnti <= 65535)
    error("sixgr:pusch:InvalidRNTIProcedure", ...
        "PUSCH RNTI must be an explicit integer in [0,65535].");
end
if isempty(tp)
    error("sixgr:pusch:TransformPrecodingMismatch", ...
        "PUSCH transformPrecoding must be explicitly true or false.");
end
if strcmpi(strrep(mod, ' ', ''), 'PI/2-BPSK') && ~tp
    error("sixgr:pusch:TransformPrecodingRequired", ...
        "PI/2-BPSK requires an explicitly transform-precoded PUSCH.");
end
if tp && nl ~= 1
    error("sixgr:pusch:UnsupportedTransformPrecodingLayerCount", ...
        "The selected strict transform-precoded PUSCH profile requires rank one.");
end
[symAlloc, mapType, mapTypeExplicit] = localResolvePUSCHTDRA( ...
    carrier, cfg, tdraID, symAlloc, mapType, mapTypeExplicit, ...
    opts.FixedReferenceMode);
if ~numAntennaPortsExplicit && (~isfinite(numAntennaPorts) || numAntennaPorts < nl)
    numAntennaPorts = nl;
end
pusch.Modulation = mod;
pusch.NumLayers = nl;
pusch.RNTI = rnti;
pusch.TransformPrecoding = tp;
if isempty(strtrim(transmissionScheme)) && ~tp && isfinite(tpmi)
    transmissionScheme = 'codebook';
end
if ~isempty(strtrim(transmissionScheme))
    try
        pusch.TransmissionScheme = char(transmissionScheme);
    catch ME
        error("sixgr:phy:grid:allocREsPUSCH:BadTransmissionScheme", ...
            "Invalid phy.pusch.transmissionScheme '%s': %s", char(transmissionScheme), ME.message);
    end
end
if isfinite(numAntennaPorts)
    try
        pusch.NumAntennaPorts = localNormalizePUSCHAntennaPorts(numAntennaPorts, nl, numAntennaPortsExplicit);
    catch ME
        error("sixgr:phy:grid:allocREsPUSCH:BadNumAntennaPorts", ...
            "Invalid phy.pusch.NumAntennaPorts/numPorts value: %s", ME.message);
    end
end
if strcmpi(char(string(localObjectValue(pusch, 'TransmissionScheme', ''))), 'codebook')
    if isfinite(tpmi)
        try
            pusch.TPMI = round(double(tpmi));
        catch ME
            error("sixgr:phy:grid:allocREsPUSCH:BadTPMI", ...
                "Invalid phy.pusch.PMI/TPMI value %g: %s", double(tpmi), ME.message);
        end
    end
    if ~isempty(strtrim(codebookType))
        try
            pusch.CodebookType = char(codebookType);
        catch ME
            error("sixgr:phy:grid:allocREsPUSCH:BadCodebookType", ...
                "Invalid phy.pusch.CodebookType '%s': %s", char(codebookType), ME.message);
        end
    end
end

prbVec = localExpandPRBSet(prb, carrier.NSizeGrid);
pusch.PRBSet = prbVec;
pusch.SymbolAllocation = symAlloc;
pusch = localApplyPUSCHDMRSConfig(pusch, cfg);
scheduledDMRSPorts = sixgr.phy.grant.resolveScheduledDMRSPortSet( ...
    cfg, "UL", pusch.NumLayers, struct());
pusch.DMRS.DMRSPortSet = double(scheduledDMRSPorts(:).');
pusch = localApplyPUSCHPTRSConfig(pusch, cfg);
pusch = localApplyPUSCHUCIConfig(pusch, cfg);
pusch = localApplyPUSCHFrequencyHoppingConfig(pusch, cfg, carrier);
pusch = localNormalizePUSCHMapping(pusch, mapType, mapTypeExplicit, opts.FixedReferenceMode);

% Scrambling NID if available
try
    if isprop(pusch, 'NID')
        if isempty(nid)
            nid = carrier.NCellID;
        end
        pusch.NID = double(nid);
    end
catch
end

end

function [symbolAllocation, mappingType, mappingExplicit] = ...
        localResolvePUSCHTDRA(carrier, cfg, tdraID, ...
        symbolAllocation, mappingType, mappingExplicit, fixedReferenceMode)
strict = logical(fixedReferenceMode);
if isstruct(cfg)
    strict = strict || ...
        logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
        logical(sixgr.util.structGet(cfg, "validation.strict", false));
end
numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    double(carrier.SubcarrierSpacing), string(carrier.CyclicPrefix), ...
    "generic_waveform_test", "");
symbolsPerSlot = double(numerology.SymbolsPerSlot);
tdraID = strtrim(string(tdraID));
if strlength(tdraID) > 0
    raw = struct( ...
        "TDRAID", tdraID, ...
        "Channel", "PUSCH", ...
        "Mu", double(numerology.Mu));
    if ~isempty(symbolAllocation)
        raw.StartSymbol = double(symbolAllocation(1));
        if numel(symbolAllocation) >= 2
            raw.NumSymbols = double(symbolAllocation(2));
        end
    end
    if logical(mappingExplicit)
        raw.MappingType = mappingType;
    end
    tdra = sixgr.phy.frame.ResourceAllocationValidator.resolveTDRA( ...
        raw, symbolsPerSlot);
    symbolAllocation = [tdra.StartSymbol tdra.NumSymbols];
    mappingType = char(tdra.MappingType);
    mappingExplicit = true;
    return;
end

if isempty(symbolAllocation)
    error("sixgr:phy:grid:allocREsPUSCH:MissingExplicitTDRA", ...
        "PUSCH transmission requires phy.pusch.tdraId or an explicit " + ...
        "phy.pusch.symbolAllocation test/configuration grant. A missing " + ...
        "allocation is not expanded to a full slot.");
end
if numel(symbolAllocation) ~= 2
    error("sixgr:phy:grid:allocREsPUSCH:InvalidTDRA", ...
        "PUSCH SymbolAllocation must be [zeroBasedStart positiveLength].");
end
if strict && ~logical(mappingExplicit)
    error("sixgr:phy:grid:allocREsPUSCH:MissingExplicitTDRA", ...
        "Strict PUSCH transmission requires an explicit TDRA MappingType A or B.");
end
raw = struct( ...
    "StartSymbol", double(symbolAllocation(1)), ...
    "NumSymbols", double(symbolAllocation(2)), ...
    "MappingType", string(mappingType));
tdra = sixgr.phy.frame.ResourceAllocationValidator.resolveTDRA( ...
    raw, symbolsPerSlot);
symbolAllocation = [tdra.StartSymbol tdra.NumSymbols];
mappingType = char(tdra.MappingType);
end

function pusch = localNormalizePUSCHMapping(pusch, mapType, explicitMapType, fixedReferenceMode)
if nargin < 2 || strlength(string(mapType)) == 0
    error("sixgr:phy:grid:allocREsPUSCH:MissingExplicitTDRA", ...
        "PUSCH MappingType must be explicitly A or B.");
end
if nargin < 3
    explicitMapType = false;
end
if nargin < 4
    fixedReferenceMode = false;
end

symAlloc = [];
try
    if isprop(pusch, "SymbolAllocation") && ~isempty(pusch.SymbolAllocation)
        symAlloc = double(pusch.SymbolAllocation(:).');
    end
catch
end
if numel(symAlloc) < 2
    error("sixgr:phy:grid:allocREsPUSCH:MissingExplicitTDRA", ...
        "PUSCH SymbolAllocation must be present before mapping validation.");
end
startSym = round(symAlloc(1));

mapType = upper(char(string(mapType)));
typeAPos = NaN;
try
    if isprop(pusch, "DMRS") && isprop(pusch.DMRS, "DMRSTypeAPosition")
        typeAPos = round(double(pusch.DMRS.DMRSTypeAPosition));
    end
catch
end
if ~(isscalar(typeAPos) && isfinite(typeAPos) ...
        && typeAPos == fix(typeAPos) && ismember(typeAPos, [2 3]))
    error("sixgr:pusch:InvalidDMRSConfiguration", ...
        "PUSCH DMRSTypeAPosition must be explicitly 2 or 3.");
end
if startSym > typeAPos && strcmp(mapType, "A")
    error("sixgr:phy:grid:allocREsPUSCH:InvalidTypeADMRSSymbol", ...
        "PUSCH MappingType A starts at symbol %d after configured DMRSTypeAPosition=%d.", ...
        round(double(startSym)), round(double(typeAPos)));
end

try
    if isprop(pusch, "MappingType")
        pusch.MappingType = char(mapType);
    end
catch
end
end

function pusch = localApplyPUSCHDMRSConfig(pusch, cfg)
if ~(isstruct(cfg) && isprop(pusch, 'DMRS'))
    return;
end

dmrs = pusch.DMRS;

typeAPos = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.typeAPosition', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.typeApos', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.DMRSTypeAPosition', []), ...
    sixgr.util.structGet(cfg, 'phy.dmrs.typeAPosition', []), ...
    sixgr.util.structGet(cfg, 'phy.dmrs.typeApos', []));
if isfinite(typeAPos) && isprop(dmrs, 'DMRSTypeAPosition')
    dmrs.DMRSTypeAPosition = localValidatedIntegerSet( ...
        typeAPos, [2 3], "DMRSTypeAPosition");
end

configType = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.configurationType', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.configType', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.DMRSConfigurationType', []), ...
    sixgr.util.structGet(cfg, 'phy.dmrs.configurationType', []), ...
    sixgr.util.structGet(cfg, 'phy.dmrs.configType', []));
if isfinite(configType) && isprop(dmrs, 'DMRSConfigurationType')
    dmrs.DMRSConfigurationType = localValidatedIntegerSet( ...
        configType, [1 2], "DMRSConfigurationType");
end

addPos = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.additionalPositions', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.additionalPosition', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.DMRSAdditionalPosition', []), ...
    sixgr.util.structGet(cfg, 'phy.dmrs.additionalPositions', []), ...
    sixgr.util.structGet(cfg, 'phy.dmrs.DMRSAdditionalPosition', []));
if isfinite(addPos) && isprop(dmrs, 'DMRSAdditionalPosition')
    dmrs.DMRSAdditionalPosition = localValidatedIntegerSet( ...
        addPos, 0:3, "DMRSAdditionalPosition");
end

dmrsLength = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.maxLength', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.length', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.DMRSLength', []), ...
    sixgr.util.structGet(cfg, 'phy.dmrs.maxLength', []), ...
    sixgr.util.structGet(cfg, 'phy.dmrs.DMRSLength', []));
if isfinite(dmrsLength) && isprop(dmrs, 'DMRSLength')
    dmrs.DMRSLength = localValidatedIntegerSet( ...
        dmrsLength, [1 2], "DMRSLength");
end

numCDM = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.numCDMGroupsWithoutData', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.NumCDMGroupsWithoutData', []), ...
    sixgr.util.structGet(cfg, 'phy.dmrs.numCDMGroupsWithoutData', []));
if isfinite(numCDM) && isprop(dmrs, 'NumCDMGroupsWithoutData')
    dmrs.NumCDMGroupsWithoutData = localValidatedIntegerSet( ...
        numCDM, 1:3, "NumCDMGroupsWithoutData");
end

portSet = sixgr.util.structGet(cfg, 'phy.pusch.dmrs.portSet', ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.DMRSPortSet', []));
if ~isempty(portSet) && isprop(dmrs, 'DMRSPortSet')
    portSet = double(portSet(:).');
    if any(~isfinite(portSet) | portSet ~= fix(portSet) | portSet < 0) ...
            || numel(unique(portSet)) ~= numel(portSet)
        error("sixgr:pusch:InvalidDMRSPortSet", ...
            "PUSCH DM-RS port set must contain unique zero-based integers.");
    end
    dmrs.DMRSPortSet = portSet;
end

groupHopping = sixgr.util.structGet(cfg, ...
    'phy.pusch.dmrs.groupHopping', []);
sequenceHopping = sixgr.util.structGet(cfg, ...
    'phy.pusch.dmrs.sequenceHopping', []);
if ~isempty(groupHopping) && ~isempty(sequenceHopping) && ...
        logical(groupHopping) && logical(sequenceHopping)
    error("sixgr:pusch:InvalidDMRSConfiguration", ...
        "PUSCH DM-RS group hopping and sequence hopping cannot both be enabled.");
end
if ~isempty(groupHopping) && isprop(dmrs, 'GroupHopping')
    dmrs.GroupHopping = logical(groupHopping);
end
if ~isempty(sequenceHopping) && isprop(dmrs, 'SequenceHopping')
    dmrs.SequenceHopping = logical(sequenceHopping);
end
nidNSCID = localFirstFiniteScalar(sixgr.util.structGet( ...
    cfg, 'phy.pusch.dmrs.NIDNSCID', []));
if isfinite(nidNSCID) && isprop(dmrs, 'NIDNSCID')
    dmrs.NIDNSCID = localValidatedIntegerRange( ...
        nidNSCID, 0, 65535, "DMRS.NIDNSCID");
end
nscid = localFirstFiniteScalar(sixgr.util.structGet( ...
    cfg, 'phy.pusch.dmrs.NSCID', []));
if isfinite(nscid) && isprop(dmrs, 'NSCID')
    dmrs.NSCID = localValidatedIntegerSet(nscid, [0 1], "DMRS.NSCID");
end
nrsid = localFirstFiniteScalar(sixgr.util.structGet( ...
    cfg, 'phy.pusch.dmrs.NRSID', []));
if isfinite(nrsid) && isprop(dmrs, 'NRSID')
    dmrs.NRSID = localValidatedIntegerRange( ...
        nrsid, 0, 1007, "DMRS.NRSID");
end

pusch.DMRS = dmrs;
end

function pusch = localApplyPUSCHPTRSConfig(pusch, cfg)
if ~(isstruct(cfg) && isprop(pusch, 'EnablePTRS'))
    return;
end

enabled = logical(sixgr.util.structGet(cfg, 'phy.pusch.enablePTRS', ...
    sixgr.util.structGet(cfg, 'phy.ptrs.enable', false)));
pusch.EnablePTRS = enabled;
if ~enabled || ~isprop(pusch, 'PTRS')
    return;
end

ptrs = pusch.PTRS;
timeDensity = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.ptrs.timeDensity', []), ...
    sixgr.util.structGet(cfg, 'phy.ptrs.timeDensity', []));
freqDensity = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.ptrs.frequencyDensity', []), ...
    sixgr.util.structGet(cfg, 'phy.ptrs.frequencyDensity', []));
numPTRSSamples = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.ptrs.numPTRSSamples', []));
numPTRSGroups = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.ptrs.numPTRSGroups', []));
reOffset = string(sixgr.util.structGet(cfg, 'phy.pusch.ptrs.reOffset', ...
    sixgr.util.structGet(cfg, 'phy.ptrs.reOffset', '')));
portSet = sixgr.util.structGet(cfg, 'phy.pusch.ptrs.portSet', ...
    sixgr.util.structGet(cfg, 'phy.ptrs.portSet', []));
scheduledDMRSPorts = [];
try
    if isprop(pusch, 'DMRS') && isprop(pusch.DMRS, 'DMRSPortSet')
        scheduledDMRSPorts = double(pusch.DMRS.DMRSPortSet(:).');
    end
catch
    scheduledDMRSPorts = [];
end
[~, portSet] = sixgr.phy.grant.resolveScheduledPTRSPortSet( ...
    cfg, "UL", scheduledDMRSPorts, struct("PTRSPortSet", portSet));
transformPrecoding = logical(sixgr.util.structGet(cfg, ...
    'phy.pusch.transformPrecoding', false));
if ~isfinite(timeDensity) ...
        || (~transformPrecoding && (~isfinite(freqDensity) || strlength(strtrim(reOffset)) == 0)) ...
        || (transformPrecoding && (~isfinite(numPTRSSamples) || ~isfinite(numPTRSGroups)))
    error("sixgr:pusch:InvalidPTRSConfiguration", ...
        ["Enabled CP-OFDM PUSCH PT-RS requires explicit timeDensity, " ...
         "frequencyDensity, and REOffset; transform-precoded PUSCH PT-RS " ...
         "requires explicit timeDensity, numPTRSSamples, and numPTRSGroups."]);
end

try
    if isprop(ptrs, 'TimeDensity')
        ptrs.TimeDensity = localValidatedIntegerSet( ...
            timeDensity, [1 2 4], "PTRS.TimeDensity");
    end
    if isprop(ptrs, 'FrequencyDensity')
        ptrs.FrequencyDensity = localValidatedIntegerSet( ...
            freqDensity, [2 4], "PTRS.FrequencyDensity");
    end
    if isprop(ptrs, 'NumPTRSSamples')
        ptrs.NumPTRSSamples = localValidatedIntegerSet( ...
            numPTRSSamples, [2 4], "PTRS.NumPTRSSamples");
    end
    if isprop(ptrs, 'NumPTRSGroups')
        ptrs.NumPTRSGroups = localValidatedIntegerSet( ...
            numPTRSGroups, [2 4 8], "PTRS.NumPTRSGroups");
    end
    if isprop(ptrs, 'REOffset')
        if ~ismember(reOffset, ["00","01","10","11"])
            error("sixgr:pusch:InvalidPTRSConfiguration", ...
                "PUSCH PT-RS REOffset must be 00, 01, 10, or 11.");
        end
        ptrs.REOffset = char(reOffset);
    end
    if isprop(ptrs, 'PTRSPortSet')
        portSet = double(portSet(:).');
        if any(~isfinite(portSet) | portSet ~= fix(portSet) | portSet < 0) ...
                || numel(unique(portSet)) ~= numel(portSet)
            error("sixgr:pusch:InvalidPTRSAssociation", ...
                "PUSCH PT-RS ports must be unique zero-based integers.");
        end
        ptrs.PTRSPortSet = portSet;
    end
    nid = localFirstFiniteScalar(sixgr.util.structGet( ...
        cfg, 'phy.pusch.ptrs.NID', []));
    if isfinite(nid) && isprop(ptrs, 'NID')
        ptrs.NID = localValidatedIntegerRange(nid, 0, 1007, "PTRS.NID");
    end
    pusch.PTRS = ptrs;
catch ME
    error("sixgr:phy:grid:allocREsPUSCH:BadPTRSConfig", ...
        "Invalid PUSCH PTRS runtime configuration: %s", ME.message);
end
end

function pusch = localApplyPUSCHUCIConfig(pusch, cfg)
if ~isstruct(cfg)
    return;
end
items = {
    'BetaOffsetACK', 'phy.pusch.uci.betaOffsetACK', 0, Inf
    'BetaOffsetCSI1', 'phy.pusch.uci.betaOffsetCSI1', 0, Inf
    'BetaOffsetCSI2', 'phy.pusch.uci.betaOffsetCSI2', 0, Inf
    'UCIScaling', 'phy.pusch.uci.scaling', 0, 1
    };
for i = 1:size(items, 1)
    propertyName = items{i,1};
    value = localFirstFiniteScalar(sixgr.util.structGet( ...
        cfg, items{i,2}, []));
    if ~isfinite(value)
        continue;
    end
    if value < items{i,3} || value > items{i,4}
        error("sixgr:pusch:InvalidUCIConfiguration", ...
            "%s must be in [%g,%g].", propertyName, ...
            items{i,3}, items{i,4});
    end
    if isprop(pusch, propertyName)
        pusch.(propertyName) = double(value);
    end
end
end

function pusch = localApplyPUSCHFrequencyHoppingConfig(pusch, cfg, carrier)
mode = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    'phy.pusch.frequencyHopping.mode', ...
    sixgr.util.structGet(cfg, 'phy.pusch.frequencyHopping', 'none')))));
if mode == "none"
    pusch.FrequencyHopping = "neither";
    return;
end
if mode == "intra_slot"
    toolboxMode = "intraSlot";
elseif mode == "inter_slot"
    toolboxMode = "interSlot";
else
    error("sixgr:pusch:InvalidFrequencyHoppingMode", ...
        "PUSCH frequency hopping must be none, intra_slot, or inter_slot.");
end
allocationType = double(sixgr.util.structGet(cfg, ...
    'phy.pusch.resourceAllocationType', 1));
if allocationType == 2
    error("sixgr:pusch:FrequencyHoppingResourceTypeConflict", ...
        "PUSCH resource-allocation type 2 cannot use frequency hopping.");
end
secondHop = sixgr.util.structGet(cfg, ...
    'phy.pusch.frequencyHopping.secondHopStartPRB', []);
if isempty(secondHop)
    error("sixgr:pusch:MissingSecondHopStartPRB", ...
        "Enabled PUSCH frequency hopping requires secondHopStartPRB.");
end
secondHop = localValidatedIntegerSet(secondHop, ...
    0:(double(carrier.NSizeGrid)-1), "SecondHopStartPRB");
if secondHop + numel(pusch.PRBSet) > double(carrier.NSizeGrid)
    error("sixgr:pusch:SecondHopOutOfBWP", ...
        "PUSCH second-hop allocation exceeds the active carrier grid.");
end
pusch.FrequencyHopping = char(toolboxMode);
pusch.SecondHopStartPRB = secondHop;
end

function value = localObjectValue(obj, propName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    raw = obj.(propName);
catch
    return;
end
if isempty(raw)
    return;
end
value = raw;
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw) || ~isnumeric(raw)
        continue;
    end
    raw = double(raw(:));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function [value, explicit] = localResolvePUSCHAntennaPorts(cfg)
value = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.numAntennaPorts', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.NumAntennaPorts', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.numPorts', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.nPorts', []));
explicit = isfinite(value);
if explicit
    return;
end

% PUSCH NumAntennaPorts is a UL codebook-port field, not the gNB-wide
% downlink antenna count. Fall back to UL-local port/layer evidence only.
value = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.nPorts', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.dmrs.numPorts', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.numLayers', []), ...
    sixgr.util.structGet(cfg, 'phy.pusch.nLayers', []), ...
    sixgr.util.structGet(cfg, 'scenario.ue.nTxAnt', []));
end

function value = localNormalizePUSCHAntennaPorts(value, numLayers, explicit)
allowed = [1 2 4 8];
value = double(value);
minPorts = round(double(numLayers));
if ~(isscalar(value) && isfinite(value) && value == fix(value) && value >= 1)
    error("NumAntennaPorts must be a positive integer.");
end
if explicit && ~any(value == allowed)
    error("explicit NumAntennaPorts=%g is invalid for nrPUSCHConfig; expected one of [1 2 4 8].", value);
end
value = max(value, minPorts);
idx = find(allowed >= value, 1, 'first');
if isempty(idx)
    if explicit
        error("explicit NumAntennaPorts=%g cannot support NumLayers=%g within nrPUSCHConfig allowed ports [1 2 4 8].", value, minPorts);
    end
    idx = numel(allowed);
end
value = allowed(idx);
end

function prbVec = localExpandPRBSet(prb, nSizeGrid)
% Expand an explicit PRB-set input.
if isempty(prb)
    error("sixgr:phy:grid:allocREsPUSCH:MissingPRBSet", ...
        "PUSCH transmission requires an explicit nonempty PRBSet. A " + ...
        "missing allocation is not expanded to the full carrier grid.");
end
if isnumeric(prb) && isreal(prb)
    prb = double(prb(:).');
    if any(~isfinite(prb)) || any(prb ~= fix(prb)) || ...
            any(prb < 0) || any(prb >= double(nSizeGrid))
        error("sixgr:phy:grid:allocREsPUSCH:InvalidPRBSet", ...
            "PUSCH PRBSet must contain integer indices in [0,%d].", ...
            round(double(nSizeGrid)) - 1);
    end
    if numel(prb) == 2 && prb(2) >= prb(1)
        prbVec = prb(1):prb(2);
        return;
    end
    prbVec = prb;
    return;
end

error("sixgr:phy:grid:allocREsPUSCH:InvalidPRBSet", ...
    "PUSCH PRBSet must be a real numeric vector.");
end

function value = localValidatedIntegerSet(raw, allowed, label)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value == fix(value) ...
        && ismember(value, allowed))
    error("sixgr:pusch:InvalidDMRSConfiguration", ...
        "%s must be one of %s; received %g.", ...
        label, mat2str(double(allowed)), value);
end
end

function value = localValidatedIntegerRange(raw, minimum, maximum, label)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value == fix(value) && ...
        value >= minimum && value <= maximum)
    error("sixgr:pusch:InvalidConfigurationInteger", ...
        "%s must be an integer in [%d,%d].", label, minimum, maximum);
end
end
