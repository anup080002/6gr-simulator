function [cfg, frameSnapshot, frameEngine] = validateConfig(cfg)
% sixgr.config.validateConfig
% Hard checks (errors) to ensure the config is self-consistent.
%
% Keep this strict. Fail early with clear messages.

if nargin < 1 || isempty(cfg) || ~isa(cfg,'struct')
    error('sixgr:config:validateConfig:BadInput','cfg must be a struct.');
end

% Required fields (minimal for bootstrap)
req = { ...
    'run.seed', ...
    'run.mode', ...
    'run.resultsRoot', ...
    'scenario.name', ...
    'scenario.profileName', ...
    'scenario.layout.type', ...
    'scenario.ue.nUE', ...
    'channel.fc_Hz', ...
    'channel.propagationScenario', ...
    'phy.carrier.SubcarrierSpacing', ...
    'phy.carrier.NSizeGrid', ...
    'outputs.saveMAT' ...
    };

localRequire(cfg, req);
cCore = sixgr.config.loadCoreCatalog();
localValidateCatalogFields(cfg, sixgr.util.structGet(cCore, 'parameters', struct()), '');
if startsWith(string(sixgr.util.structGet(cfg,'phy.pusch.mcsTable','')),"experimental_")
    definition=sixgr.phy.research.resolveExperimentalMCSTable(cfg.phy.pusch.mcsTable);
    policy=sixgr.util.structGet(cfg,'lls6g.resolvedConfig',struct());
    assert(~isempty(definition) && ...
        string(sixgr.util.structGet(policy,'meta.research_class',''))==definition.ResearchClass && ...
        string(sixgr.util.structGet(policy,'research_pusch_uci.resource_mapping',''))== ...
        "symbol_preserving_single_codeword_ulsch" && ...
        ~cfg.phy.pusch.transformPrecoding && ~cfg.phy.pusch.enablePTRS, ...
        'sixgr:research:ExplicitUCIAdapterRequired', ...
        'Experimental UL MCS requires resolved research policy, CP-OFDM and PTRS disabled.');
end
sixgr.phy.ul.pusch.resolveShortUCIDecisionPolicy(cfg.phy.pusch.shortUCIDecision);
frameEngine = sixgr.phy.FrameStructureEngine(cfg);
frameSnapshot = frameEngine.toStruct();
cfg = sixgr.util.structSet(cfg, "phy.frameStructure", frameSnapshot);
cfg = sixgr.util.structSet(cfg, ...
    "resolved_runtime_view.frame_structure", frameSnapshot);
localValidateCanonicalFrameGrid(cfg, frameSnapshot);
cfg = localAttachValidatedFrameAliases(cfg, frameSnapshot);

duplexMode = upper(char(cfg.phy.duplex.mode));
if strcmp(duplexMode, 'TDD')
    legacyPattern = sixgr.util.structGet(cfg, 'phy.duplex.tddPattern', []);
    if ~isempty(legacyPattern)
        token = upper(string(legacyPattern));
        if ~(isscalar(token) && all(ismember(char(token), 'DUF')))
            error("sixgr:phy:frame:LegacyCompactTDDPatternNotAllowed", ...
                "The standard frame path does not accept compact S-slot " + ...
                "patterns. Configure phy.duplex.tddCommon instead.");
        end
    end
    localValidateCanonicalTDD(cfg, frameSnapshot);
elseif strcmp(duplexMode, 'FDD')
    localValidateFDDContextIfConfigured(cfg, frameSnapshot);
else
    error('sixgr:config:BadEnum', ...
        'phy.duplex.mode must be one of: TDD, FDD');
end

% Traffic controls
trafficModel = lower(char(string(sixgr.util.structGet(cfg, 'traffic.model', 'fullBuffer'))));
dlRatio = double(sixgr.util.structGet(cfg, 'traffic.dlRatio', 0.8));
ulRatio = double(sixgr.util.structGet(cfg, 'traffic.ulRatio', 0.2));
if ~(isfinite(dlRatio) && isfinite(ulRatio) && dlRatio >= 0 && ulRatio >= 0 && (dlRatio + ulRatio) > 0)
    error('sixgr:config:BadTrafficRatio', 'traffic.dlRatio and traffic.ulRatio must be finite, non-negative, and not both zero.');
end
pdb = double(sixgr.util.structGet(cfg, 'traffic.packetDelayBudget_ms', ...
    sixgr.util.structGet(cfg, 'traffic.qos.latencyBudget_ms', 50)));
if ~(isfinite(pdb) && pdb > 0)
    error('sixgr:config:BadPDB', 'traffic.packetDelayBudget_ms must be > 0.');
end
if strcmp(trafficModel, 'tracereplay')
    traceSpec = sixgr.util.structGet(cfg, 'traffic.trace', struct());
    traceFile = string(sixgr.util.structGet(traceSpec, 'file', sixgr.util.structGet(traceSpec, 'path', '')));
    traceDL = sixgr.util.structGet(traceSpec, 'offeredBitsDL', []);
    traceUL = sixgr.util.structGet(traceSpec, 'offeredBitsUL', []);
    if strlength(traceFile) == 0 && isempty(traceDL) && isempty(traceUL)
        error('sixgr:config:MissingTraceReplaySpec', ...
            'traffic.model=''traceReplay'' requires traffic.trace.offeredBitsDL/UL or traffic.trace.file.');
    end
end

flows = sixgr.util.structGet(cfg, 'traffic.flows', []);
if ~isempty(flows)
    if ~isstruct(flows)
        error('sixgr:config:BadFlows', 'traffic.flows must be a struct array.');
    end
    for i = 1:numel(flows)
        if isfield(flows(i), 'protocol')
            p = upper(char(string(flows(i).protocol)));
            localOneOf(p, localCatalogAllowed(cCore, 'traffic.transport', {'UDP','TCP','MIXED'}), ...
                sprintf('traffic.flows(%d).protocol', i));
        end
        if isfield(flows(i), 'direction')
            d = upper(char(string(flows(i).direction)));
            localOneOf(d, localCatalogAllowed(cCore, 'traffic.flowDirection', {'DL','UL','BIDIR'}), ...
                sprintf('traffic.flows(%d).direction', i));
        end
        if isfield(flows(i), 'packetDelayBudget_ms')
            fpdb = double(flows(i).packetDelayBudget_ms);
            if ~(isfinite(fpdb) && fpdb > 0)
                error('sixgr:config:BadFlowPDB', 'traffic.flows(%d).packetDelayBudget_ms must be > 0.', i);
            end
        end
    end
end

localValidateChannelProfiles(cfg);
localValidateChannelIntent(cfg);
localValidateChannelComplianceMode(cfg);
localValidateScenarioSemantics(cfg);
localValidatePresetMetadata(cfg, cCore);
localValidateChannelEstimator(cfg);

% UL waveform consistency
ulWf = upper(char(cfg.phy.waveform.ul));
if strcmp(ulWf,'DFT-S-OFDM')
    if ~isfield(cfg.phy,'pusch') || ~isfield(cfg.phy.pusch,'transformPrecoding') || ~logical(cfg.phy.pusch.transformPrecoding)
        error('sixgr:config:BadULWaveform', 'DFT-s-OFDM selected but phy.pusch.transformPrecoding is not enabled.');
    end
end

% Output flags should be scalar logical
localScalarLogical(cfg.outputs.saveMAT, 'outputs.saveMAT');
localScalarLogical(cfg.outputs.saveCSV, 'outputs.saveCSV');
localScalarLogical(cfg.outputs.saveFigures, 'outputs.saveFigures');
localScalarLogical(cfg.outputs.saveFIG, 'outputs.saveFIG');
localOutputBackend(cfg.outputs.storageBackend);
if ~(ischar(cfg.outputs.databaseHost) || (isstring(cfg.outputs.databaseHost) && isscalar(cfg.outputs.databaseHost)))
    error('sixgr:config:BadType', 'outputs.databaseHost must be a text scalar.');
end
if ~(isnumeric(cfg.outputs.databasePort) && isscalar(cfg.outputs.databasePort) && isfinite(cfg.outputs.databasePort) && cfg.outputs.databasePort >= 1)
    error('sixgr:config:BadType', 'outputs.databasePort must be a finite scalar >= 1.');
end
if ~(ischar(cfg.outputs.databaseSchema) || (isstring(cfg.outputs.databaseSchema) && isscalar(cfg.outputs.databaseSchema)))
    error('sixgr:config:BadType', 'outputs.databaseSchema must be a text scalar.');
end

end

% -------------------------------------------------------------------------
function localRequire(s, fields)
for i = 1:numel(fields)
    f = fields{i};
    if ~localHasFieldPath(s, f)
        error('sixgr:config:MissingField', 'Missing required config field: %s', f);
    end
end
end

function tf = localHasFieldPath(s, pathStr)
parts = strsplit(pathStr, '.');
tf = true;
cur = s;
for i = 1:numel(parts)
    p = parts{i};
    if ~isa(cur,'struct') || ~isfield(cur, p)
        tf = false;
        return;
    end
    cur = cur.(p);
end
end

function localOneOf(val, allowed, fieldName)
if ~any(strcmp(val, allowed))
    error('sixgr:config:BadEnum', '%s must be one of: %s', fieldName, strjoin(allowed, ', '));
end
end

function localScalarLogical(val, fieldName)
if ~(islogical(val) && isscalar(val))
    error('sixgr:config:BadType', '%s must be a scalar logical.', fieldName);
end
end

function localOutputBackend(val)
token = lower(string(val));
if ~(isscalar(token) && any(token == ["filesystem","mysql_web"]))
    error('sixgr:config:BadEnum', 'outputs.storageBackend must be one of: filesystem, mysql_web');
end
end

function localValidateChannelProfiles(cfg)
localRejectBareProfileName(sixgr.util.structGet(cfg, 'channel.tdlProfile', ''), 'channel.tdlProfile');
localRejectBareProfileName(sixgr.util.structGet(cfg, 'channel.cdlProfile', ''), 'channel.cdlProfile');
localRejectBareProfileName(sixgr.util.structGet(cfg, 'channel.delayProfile', ''), 'channel.delayProfile');
localRejectBareProfileName(sixgr.util.structGet(cfg, 'channel.fading.profile', ''), 'channel.fading.profile');

[tdlProfiles, tdlFields, cdlProfiles, cdlFields] = localCollectConcreteChannelProfiles(cfg);
uTDL = unique(string(tdlProfiles), 'stable');
uCDL = unique(string(cdlProfiles), 'stable');
if numel(uTDL) > 1
    error('sixgr:config:BadChannelProfile', ...
        'Conflicting concrete TDL profiles specified (%s) across %s.', ...
        strjoin(cellstr(uTDL), ', '), strjoin(tdlFields, ', '));
end
if numel(uCDL) > 1
    error('sixgr:config:BadChannelProfile', ...
        'Conflicting concrete CDL profiles specified (%s) across %s.', ...
        strjoin(cellstr(uCDL), ', '), strjoin(cdlFields, ', '));
end
if ~isempty(uTDL) && ~isempty(uCDL)
    error('sixgr:config:BadChannelProfile', ...
        'Config mixes concrete TDL and CDL profiles across %s and %s. Keep only one fading family.', ...
        strjoin(tdlFields, ', '), strjoin(cdlFields, ', '));
end

model = upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.model', '')))));
if localIsTDLModel(model) && ~isempty(uCDL) && isempty(uTDL)
    error('sixgr:config:BadChannelProfile', ...
        'channel.model=''%s'' conflicts with concrete CDL profile(s) across %s. Use a TDL-* profile or set channel.model=''CDL''.', ...
        model, strjoin(cdlFields, ', '));
end
if localIsCDLModel(model) && ~isempty(uTDL) && isempty(uCDL)
    error('sixgr:config:BadChannelProfile', ...
        'channel.model=''%s'' conflicts with concrete TDL profile(s) across %s. Use a CDL-* profile or set channel.model=''TDL''.', ...
        model, strjoin(tdlFields, ', '));
end
if localIsTDLModel(model) && isempty(uTDL)
    error('sixgr:config:AmbiguousChannelModel', ...
        'channel.model=''%s'' requires a concrete TDL profile. Set channel.tdlProfile=''TDL-C'' or channel.fading.profile=''TDL-C''.', ...
        model);
end
if localIsCDLModel(model) && isempty(uCDL)
    error('sixgr:config:AmbiguousChannelModel', ...
        'channel.model=''%s'' requires a concrete CDL profile. Set channel.cdlProfile=''CDL-D'' or channel.fading.profile=''CDL-D''.', ...
        model);
end

fadingModel = upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.fading.model', '')))));
if strcmp(fadingModel, 'TDL') && ~isempty(uCDL) && isempty(uTDL)
    error('sixgr:config:BadChannelProfile', ...
        'channel.fading.model=''TDL'' conflicts with concrete CDL profile(s) across %s. Use a TDL-* profile or set channel.fading.model=''CDL''.', ...
        strjoin(cdlFields, ', '));
end
if strcmp(fadingModel, 'CDL') && ~isempty(uTDL) && isempty(uCDL)
    error('sixgr:config:BadChannelProfile', ...
        'channel.fading.model=''CDL'' conflicts with concrete TDL profile(s) across %s. Use a CDL-* profile or set channel.fading.model=''TDL''.', ...
        strjoin(tdlFields, ', '));
end
if strcmp(fadingModel, 'TDL') && isempty(uTDL)
    error('sixgr:config:AmbiguousChannelModel', ...
        'channel.fading.model=''TDL'' requires a concrete TDL profile. Set channel.fading.profile=''TDL-C''.');
end
if strcmp(fadingModel, 'CDL') && isempty(uCDL)
    error('sixgr:config:AmbiguousChannelModel', ...
        'channel.fading.model=''CDL'' requires a concrete CDL profile. Set channel.fading.profile=''CDL-D''.');
end
end

function localRejectBareProfileName(rawValue, fieldName)
value = upper(strtrim(char(string(rawValue))));
if strcmp(value, 'TDL')
    error('sixgr:config:BadChannelProfile', ...
        '%s must be a concrete TDL profile such as TDL-C. Bare ''TDL'' is ambiguous.', ...
        fieldName);
end
if strcmp(value, 'CDL')
    error('sixgr:config:BadChannelProfile', ...
        '%s must be a concrete CDL profile such as CDL-D. Bare ''CDL'' is ambiguous.', ...
        fieldName);
end
end

function localValidateChannelIntent(cfg)
awgnOnly = logical(sixgr.util.structGet(cfg, 'channel.awgnOnly', false));
model = upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.model', '')))));
delayProfile = upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.delayProfile', '')))));
fadingEnable = logical(sixgr.util.structGet(cfg, 'channel.fading.enable', false));
fadingModel = upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.fading.model', '')))));
fadingProfile = upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.fading.profile', '')))));

hasFadingClaim = localIsConcreteTDLProfile(delayProfile) || localIsConcreteCDLProfile(delayProfile) || ...
    localIsConcreteTDLProfile(fadingProfile) || localIsConcreteCDLProfile(fadingProfile) || ...
    localIsTDLModel(fadingModel) || localIsCDLModel(fadingModel) || fadingEnable;

if awgnOnly
    if ~(isempty(model) || localIsExplicitFlatChannelModel(model))
        error('sixgr:config:ContradictoryChannelIntent', ...
            'channel.awgnOnly=true conflicts with channel.model=''%s''. Use an explicit AWGN/None/Off model only.', ...
            model);
    end
    if hasFadingClaim
        error('sixgr:config:ContradictoryChannelIntent', ...
            ['channel.awgnOnly=true cannot coexist with fading claims. ' ...
             'Clear channel.delayProfile, channel.fading.model/profile, and disable channel.fading.enable.']);
    end
end

if localIsExplicitFlatChannelModel(model) && hasFadingClaim
    error('sixgr:config:ContradictoryChannelIntent', ...
        'channel.model=''%s'' cannot coexist with TDL/CDL fading claims in the same config.', model);
end
end

function localValidateChannelComplianceMode(cfg)
mode = lower(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.complianceMode', 'approximate_38901_plus')))));
allowed = {'strict_38901', 'approximate_38901_plus', 'legacy_fallback'};
if ~any(strcmp(mode, allowed))
    error('sixgr:config:BadChannelComplianceMode', ...
        'channel.complianceMode must be one of: %s', strjoin(allowed, ', '));
end
end

function localValidateScenarioSemantics(cfg)
scenarioName = strtrim(char(string(sixgr.util.structGet(cfg, 'scenario.name', ''))));
profileName = strtrim(char(string(sixgr.util.structGet(cfg, 'scenario.profileName', ''))));
propagationScenario = strtrim(char(string(sixgr.util.structGet(cfg, 'channel.propagationScenario', ''))));

if isempty(profileName)
    error('sixgr:config:MissingScenarioProfileName', ...
        'scenario.profileName must resolve to a non-empty layout/profile selector.');
end
if isempty(propagationScenario)
    error('sixgr:config:MissingPropagationScenario', ...
        'channel.propagationScenario must resolve to a non-empty propagation scenario.');
end
if ~strcmpi(scenarioName, profileName)
    error('sixgr:config:ScenarioNameProfileMismatch', ...
        'scenario.name must mirror scenario.profileName after normalization.');
end
end

function localValidatePresetMetadata(cfg, cCore)
presetClass = lower(strtrim(char(string(sixgr.util.structGet(cfg, 'meta.presetClass', '')))));
if isempty(presetClass)
    return;
end

localOneOf(presetClass, localCatalogAllowed(cCore, 'meta.presetClass', ...
    {'fading_truth'}), 'meta.presetClass');
presetIntent = strtrim(char(string(sixgr.util.structGet(cfg, 'meta.presetIntent', ''))));
if isempty(presetIntent)
    error('sixgr:config:BadPresetMetadata', ...
        'meta.presetIntent must be non-empty when meta.presetClass is set.');
end

awgnOnly = logical(sixgr.util.structGet(cfg, 'channel.awgnOnly', false));
model = upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.model', '')))));
hasConcreteFading = localConfigHasConcreteFadingProfile(cfg);

switch presetClass
    case 'fading_truth'
        if awgnOnly || ~hasConcreteFading
            error('sixgr:config:BadPresetMetadata', ...
                'meta.presetClass=''fading_truth'' requires awgnOnly=false and a concrete TDL/CDL fading profile.');
        end
end
end

function allowed = localCatalogAllowed(cCore, path, fallback)
allowed = fallback;
node = sixgr.util.structGet(cCore, "parameters." + string(path) + ".allowed_values", []);
if isempty(node)
    return;
end
if iscell(node)
    allowed = cellfun(@char, cellstr(string(node(:).')), 'UniformOutput', false);
else
    allowed = cellfun(@char, cellstr(string(node(:).')), 'UniformOutput', false);
end
end

function localValidateCatalogFields(cfg, node, prefix)
fields = fieldnames(node);
for i = 1:numel(fields)
    name = fields{i};
    child = node.(name);
    path = localJoinCatalogPath(prefix, name);
    if localIsCatalogLeaf(child)
        if ~localHasFieldPath(cfg, path)
            continue;
        end
        value = sixgr.util.structGet(cfg, path, []);
        localValidateCatalogLeafValue(value, child, path);
    elseif isstruct(child) && isscalar(child)
        localValidateCatalogFields(cfg, child, path);
    end
end
end

function localValidateCatalogLeafValue(value, entry, fieldName)
valueType = lower(string(sixgr.util.structGet(entry, 'value_type', 'any')));

switch valueType
    case 'boolean'
        if ~(islogical(value) && isscalar(value))
            error('sixgr:config:BadType', '%s must be a scalar logical.', fieldName);
        end
    case 'integer'
        if ~(isnumeric(value) && isscalar(value) && isfinite(value) && mod(double(value), 1) == 0)
            error('sixgr:config:BadType', '%s must be a finite integer.', fieldName);
        end
    case 'number'
        if ~(isnumeric(value) && isscalar(value) && isfinite(value))
            error('sixgr:config:BadType', '%s must be a finite numeric scalar.', fieldName);
        end
    case {'string','string_or_empty'}
        if ~localIsTextScalar(value)
            error('sixgr:config:BadType', '%s must be a scalar text value.', fieldName);
        end
    case 'integer_vector'
        if ~(isnumeric(value) && (isempty(value) || isvector(value)) && ...
                all(isfinite(value(:))) && all(mod(double(value(:)), 1) == 0))
            error('sixgr:config:BadType', '%s must be a finite integer vector.', fieldName);
        end
    case 'number_vector'
        if ~(isnumeric(value) && (isempty(value) || isvector(value)) && all(isfinite(value(:))))
            error('sixgr:config:BadType', '%s must be a finite numeric vector.', fieldName);
        end
    case 'number_array'
        if ~(isnumeric(value) && all(isfinite(value(:))))
            error('sixgr:config:BadType', '%s must be a finite numeric array.', fieldName);
        end
    case 'string_list'
        if ~(isstring(value) || iscellstr(value) || (iscell(value) && all(cellfun(@localIsTextScalar, value(:)))))
            error('sixgr:config:BadType', '%s must be a list of strings.', fieldName);
        end
    case 'table'
        if ~istable(value)
            error('sixgr:config:BadType', '%s must be a table.', fieldName);
        end
    case 'struct_array'
        if ~(isstruct(value) || isempty(value))
            error('sixgr:config:BadType', '%s must be a struct array or empty.', fieldName);
        end
    otherwise
        % Free-form / special fields validated elsewhere.
end

if isfield(entry, 'min') && isnumeric(value)
    if any(double(value(:)) < double(entry.min))
        error('sixgr:config:BadRange', '%s must be >= %g.', fieldName, double(entry.min));
    end
end
if isfield(entry, 'max') && isnumeric(value)
    if any(double(value(:)) > double(entry.max))
        error('sixgr:config:BadRange', '%s must be <= %g.', fieldName, double(entry.max));
    end
end
if isfield(entry, 'min_exclusive') && isnumeric(value)
    if any(double(value(:)) <= double(entry.min_exclusive))
        error('sixgr:config:BadRange', '%s must be > %g.', fieldName, double(entry.min_exclusive));
    end
end
if isfield(entry, 'max_exclusive') && isnumeric(value)
    if any(double(value(:)) >= double(entry.max_exclusive))
        error('sixgr:config:BadRange', '%s must be < %g.', fieldName, double(entry.max_exclusive));
    end
end
if isfield(entry, 'min_length') && isvector(value)
    if numel(value) < double(entry.min_length)
        error('sixgr:config:BadRange', '%s must contain at least %d entries.', fieldName, double(entry.min_length));
    end
end
if isfield(entry, 'max_length') && isvector(value)
    if numel(value) > double(entry.max_length)
        error('sixgr:config:BadRange', '%s must contain at most %d entries.', fieldName, double(entry.max_length));
    end
end

allowed = sixgr.util.structGet(entry, 'allowed_values', []);
if isempty(allowed)
    return;
end

switch valueType
    case {'string','string_or_empty'}
        if ~any(strcmpi(char(string(value)), cellstr(string(allowed(:).'))))
            error('sixgr:config:BadEnum', '%s must be one of: %s', fieldName, strjoin(cellstr(string(allowed(:).')), ', '));
        end
    case 'string_list'
        values = cellstr(string(value(:).'));
        allowedText = cellstr(string(allowed(:).'));
        for i = 1:numel(values)
            if ~any(strcmpi(values{i}, allowedText))
                error('sixgr:config:BadEnum', '%s contains unsupported value ''%s''.', fieldName, values{i});
            end
        end
    otherwise
        if isnumeric(value) && ~all(ismember(double(value(:)), double(allowed(:))))
            error('sixgr:config:BadEnum', '%s must be one of [%s].', fieldName, num2str(double(allowed(:).')));
        end
end
end

function tf = localIsCatalogLeaf(node)
tf = isstruct(node) && isscalar(node) && ...
    (isfield(node, 'value_type') || isfield(node, 'default') || isfield(node, 'default_kind'));
end

function out = localJoinCatalogPath(prefix, name)
if strlength(string(prefix)) == 0
    out = char(string(name));
else
    out = char(string(prefix) + "." + string(name));
end
end

function tf = localIsTextScalar(value)
tf = ischar(value) || (isstring(value) && isscalar(value));
end

function localValidateChannelEstimator(cfg)
strictMode = logical(sixgr.util.structGet(cfg, 'run.strictMode', false));
useFastMex = logical(sixgr.util.structGet(cfg, 'phy.rx.useFastChannelEstMex', false)) ...
    && logical(sixgr.util.structGet(cfg, 'run.useMex', false));
if ~(strictMode && useFastMex)
    return;
end

channelToken = localResolveEstimatorChannelToken(cfg);
dlLayers = double(sixgr.util.structGet(cfg, 'phy.pdsch.numLayers', ...
    sixgr.util.structGet(cfg, 'phy.pdsch.nLayers', 1)));
ulLayers = double(sixgr.util.structGet(cfg, 'phy.pusch.numLayers', ...
    sixgr.util.structGet(cfg, 'phy.pusch.nLayers', 1)));
if ~(isscalar(dlLayers) && isfinite(dlLayers) && dlLayers >= 1)
    dlLayers = 1;
end
if ~(isscalar(ulLayers) && isfinite(ulLayers) && ulLayers >= 1)
    ulLayers = 1;
end

requiresSelectiveEstimate = localIsTDLModel(channelToken) || localIsCDLModel(channelToken) || ...
    localIsConcreteTDLProfile(channelToken) || localIsConcreteCDLProfile(channelToken) || ...
    dlLayers > 1 || ulLayers > 1;
if requiresSelectiveEstimate
    error('sixgr:config:InvalidChannelEstimator', ...
        ['run.strictMode=true cannot combine phy.rx.useFastChannelEstMex=true and run.useMex=true with %s. ' ...
        'Disable the scalar fast estimator or use an explicit AWGN flat validation mode.'], ...
        localDescribeEstimatorConflict(channelToken, dlLayers, ulLayers));
end
end

function [tdlProfiles, tdlFields, cdlProfiles, cdlFields] = localCollectConcreteChannelProfiles(cfg)
paths = { ...
    'channel.tdlProfile', ...
    'channel.cdlProfile', ...
    'channel.delayProfile', ...
    'channel.fading.profile', ...
    'channel.model', ...
    'channel.fading.model' ...
    };

tdlProfiles = {};
tdlFields = {};
cdlProfiles = {};
cdlFields = {};
for i = 1:numel(paths)
    path = paths{i};
    value = upper(strtrim(char(string(sixgr.util.structGet(cfg, path, '')))));
    if localIsConcreteTDLProfile(value)
        tdlProfiles{end+1} = value; %#ok<AGROW>
        tdlFields{end+1} = path; %#ok<AGROW>
    elseif localIsConcreteCDLProfile(value)
        cdlProfiles{end+1} = value; %#ok<AGROW>
        cdlFields{end+1} = path; %#ok<AGROW>
    end
end
end

function tf = localIsTDLModel(model)
tf = any(strcmp(model, {'TDL', 'NRTDL'}));
end

function tf = localIsCDLModel(model)
tf = any(strcmp(model, {'CDL', 'NRCDL'}));
end

function tf = localIsConcreteTDLProfile(profile)
tf = startsWith(profile, 'TDL') && ~strcmp(profile, 'TDL');
end

function tf = localIsConcreteCDLProfile(profile)
tf = startsWith(profile, 'CDL') && ~strcmp(profile, 'CDL');
end

function tf = localIsExplicitFlatChannelModel(model)
tf = any(strcmp(model, {'AWGN', 'NONE', 'OFF'}));
end

function tf = localConfigHasConcreteFadingProfile(cfg)
tf = localIsConcreteTDLProfile(upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.tdlProfile', '')))))) || ...
    localIsConcreteCDLProfile(upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.cdlProfile', '')))))) || ...
    localIsConcreteTDLProfile(upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.delayProfile', '')))))) || ...
    localIsConcreteCDLProfile(upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.delayProfile', '')))))) || ...
    localIsConcreteTDLProfile(upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.fading.profile', '')))))) || ...
    localIsConcreteCDLProfile(upper(strtrim(char(string(sixgr.util.structGet(cfg, 'channel.fading.profile', ''))))));
end

function channelToken = localResolveEstimatorChannelToken(cfg)
paths = { ...
    'channel.tdlProfile', ...
    'channel.cdlProfile', ...
    'channel.delayProfile', ...
    'channel.fading.profile', ...
    'channel.model', ...
    'channel.fading.model' ...
    };

channelToken = '';
for i = 1:numel(paths)
    token = upper(strtrim(char(string(sixgr.util.structGet(cfg, paths{i}, '')))));
    if localIsConcreteTDLProfile(token) || localIsConcreteCDLProfile(token)
        channelToken = token;
        return;
    end
    if isempty(channelToken) && ~isempty(token)
        channelToken = token;
    end
end
end

function desc = localDescribeEstimatorConflict(channelToken, dlLayers, ulLayers)
parts = strings(0,1);
token = string(channelToken);
if strlength(token) > 0 && (localIsTDLModel(char(token)) || localIsCDLModel(char(token)) || ...
        localIsConcreteTDLProfile(char(token)) || localIsConcreteCDLProfile(char(token)))
    parts(end+1) = "channel '" + token + "'";
end
if dlLayers > 1
    parts(end+1) = "DL NumLayers=" + string(dlLayers);
end
if ulLayers > 1
    parts(end+1) = "UL NumLayers=" + string(ulLayers);
end
if isempty(parts)
    desc = 'this truth-validation context';
else
    desc = char(strjoin(parts, ', '));
end
end

function cfg = localAttachValidatedFrameAliases(cfg, frame)
cfg.phy.carrier.SubcarrierSpacing = double(frame.SCSkHz);
cfg.phy.carrier.SubcarrierSpacing_kHz = double(frame.SCSkHz);
cfg.phy.carrier.CyclicPrefix = char(frame.CyclicPrefix);
cfg.phy.carrier.NSizeGrid = double(frame.NRB);
cfg = sixgr.util.structSet(cfg, "phy.numerology.mu", double(frame.Mu));
cfg = sixgr.util.structSet(cfg, ...
    "phy.numerology.scs_kHz", double(frame.SCSkHz));
cfg = sixgr.util.structSet(cfg, ...
    "phy.numerology.SubcarrierSpacing_kHz", double(frame.SCSkHz));
cfg = sixgr.util.structSet(cfg, ...
    "phy.numerology.NRB", double(frame.NRB));
cfg = sixgr.util.structSet(cfg, ...
    "phy.numerology.NSubcarriers", double(12 * frame.NRB));
cfg = sixgr.util.structSet(cfg, ...
    "phy.numerology.slotsPerFrame", double(frame.SlotsPerFrame));
cfg = sixgr.util.structSet(cfg, ...
    "phy.numerology.slotDuration_ms", double(frame.SlotDuration_ms));
cfg = sixgr.util.structSet(cfg, ...
    "phy.numerology.symbolsPerSlot", double(frame.SymbolsPerSlot));
cfg = sixgr.util.structSet(cfg, ...
    "phy.numerology.source", char(frame.Numerology.Source));
cfg = sixgr.util.structSet(cfg, "phy.ofdm", frame.OFDMSampling);
cfg = sixgr.util.structSet(cfg, ...
    "phy.waveform.fftSize", double(frame.FFTSize));
cfg = sixgr.util.structSet(cfg, ...
    "phy.waveform.sampleRate_Hz", double(frame.SampleRate_Hz));
if isfield(cfg, "channel") && isstruct(cfg.channel) && isscalar(cfg.channel)
    cfg.channel.sampleRate_Hz = double(frame.SampleRate_Hz);
    cfg.channel.nfft = double(frame.FFTSize);
end
end

function localValidateCanonicalFrameGrid(cfg, frameSnapshot)
fcHz = localFirstFinite(cfg, [ ...
    "phy.carrier.centerFrequency_Hz", "phy.carrier.fc_Hz", ...
    "channel.fc_Hz"]);
bwHz = localFirstFinite(cfg, [ ...
    "phy.channelBandwidth_Hz", "channel.bandwidth_Hz", ...
    "scenario.bandwidth_Hz"]);
scsKHz = localFirstFinite(cfg, [ ...
    "phy.carrier.SubcarrierSpacing_kHz", ...
    "phy.carrier.SubcarrierSpacing"]);
nSizeGrid = localFirstFinite(cfg, "phy.carrier.NSizeGrid");
nStartGrid = localFirstFinite(cfg, "phy.carrier.NStartGrid");
if ~isfinite(nStartGrid)
    nStartGrid = 0;
end
cp = string(sixgr.util.structGet(cfg, ...
    "phy.carrier.CyclicPrefix", ""));
if ~(isfinite(fcHz) && isfinite(bwHz) && isfinite(scsKHz) && ...
        isfinite(nSizeGrid) && strlength(strtrim(cp)) > 0)
    error("sixgr:config:MissingFrameGridField", ...
        "Standard frame validation requires center frequency, channel " + ...
        "bandwidth, SCS, NSizeGrid, and cyclic prefix.");
end
if ~(isstruct(frameSnapshot) && isscalar(frameSnapshot) && ...
        isfield(frameSnapshot, "CarrierGrid") && ...
        isfield(frameSnapshot, "OFDMSampling"))
    error("sixgr:config:MissingCanonicalFrameSnapshot", ...
        "validateConfig must attach one canonical frame/grid snapshot.");
end
grid = frameSnapshot.CarrierGrid;
if double(grid.CenterFrequencyHz) ~= fcHz || ...
        double(grid.ChannelBandwidthHz) ~= bwHz || ...
        double(grid.SubcarrierSpacingKHz) ~= scsKHz || ...
        double(grid.NSizeGrid) ~= nSizeGrid || ...
        double(grid.NStartGrid) ~= nStartGrid || ...
        ~strcmpi(string(grid.CyclicPrefix), cp)
    error("sixgr:config:CanonicalFrameSnapshotMismatch", ...
        "The canonical frame snapshot does not exactly match configured carrier fields.");
end
localValidateDeclaredFrameValue(cfg, "phy.numerology.mu", ...
    frameSnapshot.Mu);
localValidateDeclaredFrameValue(cfg, "phy.numerology.slotsPerFrame", ...
    frameSnapshot.SlotsPerFrame);
localValidateDeclaredFrameValue(cfg, "phy.numerology.slotDuration_ms", ...
    frameSnapshot.SlotDuration_ms);
localValidateDeclaredFrameValue(cfg, "phy.numerology.symbolsPerSlot", ...
    frameSnapshot.SymbolsPerSlot);
localValidateDeclaredFrameValue(cfg, "frame_timing.slots_per_frame", ...
    frameSnapshot.SlotsPerFrame);
localValidateDeclaredFrameValue(cfg, "frame_timing.slot_duration_ms", ...
    frameSnapshot.SlotDuration_ms);
localValidateDeclaredFrameValue(cfg, "frame_timing.symbols_per_slot", ...
    frameSnapshot.SymbolsPerSlot);
end

function localValidateDeclaredFrameValue(cfg, path, expected)
value = sixgr.util.structGet(cfg, path, []);
if isempty(value)
    return;
end
if ~(isnumeric(value) && isreal(value) && isscalar(value) && ...
        isfinite(double(value))) || ...
        abs(double(value) - double(expected)) > ...
        16 * eps(max(1, abs(double(expected))))
    error("sixgr:config:DeclaredFrameTimingMismatch", ...
        "%s=%.15g does not match canonical resolved value %.15g.", ...
        path, double(value), double(expected));
end
end

function localValidateCanonicalTDD(cfg, frameSnapshot)
node = sixgr.util.structGet(cfg, "phy.duplex.tddCommon", []);
if ~(isstruct(node) && isscalar(node) && ~isempty(fieldnames(node)))
    error("sixgr:phy:frame:MissingTDDCommonConfig", ...
        "TDD requires phy.duplex.tddCommon with an explicit reference " + ...
        "SCS and pattern1. No compact-pattern default is installed.");
end
if string(frameSnapshot.DuplexMode) ~= "TDD" || ...
        ~isstruct(frameSnapshot.SlotState) || ...
        isempty(fieldnames(frameSnapshot.SlotState))
    error("sixgr:config:MissingCanonicalTDDState", ...
        "The validated TDD config must contain canonical symbol-level slot state.");
end
end

function localValidateFDDContextIfConfigured(cfg, frameSnapshot)
fdd = sixgr.util.structGet(cfg, "phy.duplex.fdd", struct());
if isempty(fdd) || ~(isstruct(fdd) && isscalar(fdd)) || ...
        isempty(fieldnames(fdd))
    error("sixgr:phy:frame:MissingFDDContext", ...
        "FDD validation requires explicit separate DL and UL contexts.");
end
contexts = frameSnapshot.FDDContexts;
if string(frameSnapshot.DuplexMode) ~= "FDD" || ...
        ~isstruct(contexts) || ~isfield(contexts, "Downlink") || ...
        ~isfield(contexts, "Uplink") || ...
        double(contexts.Downlink.CenterFrequencyHz) == ...
        double(contexts.Uplink.CenterFrequencyHz)
    error("sixgr:config:MissingCanonicalFDDState", ...
        "The validated FDD snapshot must contain distinct DL and UL grids.");
end
end

function value = localFirstFinite(cfg, paths)
value = NaN;
for path = string(paths)
    candidate = sixgr.util.structGet(cfg, path, []);
    if isempty(candidate)
        continue;
    end
    if ~(isnumeric(candidate) || islogical(candidate)) || ...
            ~isscalar(candidate) || ~isfinite(double(candidate))
        error("sixgr:config:BadFrameGridValue", ...
            "%s must be a finite numeric scalar.", path);
    end
    value = double(candidate);
    return;
end
end

function value = localFirstFiniteOr(cfg, path, defaultValue)
value = localFirstFinite(cfg, path);
if ~isfinite(value)
    value = double(defaultValue);
end
end

function value = localStructField(s, names)
value = [];
fields = string(fieldnames(s));
for name = string(names)
    index = find(strcmpi(fields, name), 1);
    if ~isempty(index)
        value = s.(char(fields(index)));
        return;
    end
end
end
