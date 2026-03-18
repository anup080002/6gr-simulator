function validateConfig(cfg)
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
    'scenario.layout.type', ...
    'scenario.ue.nUE', ...
    'channel.fc_Hz', ...
    'phy.carrier.SubcarrierSpacing', ...
    'phy.carrier.NSizeGrid', ...
    'outputs.saveMAT' ...
    };

localRequire(cfg, req);

% Enums
mode = lower(char(cfg.run.mode));
validModes = {'link','system','hybrid','both'};
localOneOf(mode, validModes, 'run.mode');

layoutType = lower(char(cfg.scenario.layout.type));
localOneOf(layoutType, {'hex','grid','manual'}, 'scenario.layout.type');

duplexMode = upper(char(cfg.phy.duplex.mode));
localOneOf(duplexMode, {'TDD','FDD'}, 'phy.duplex.mode');
if strcmp(duplexMode, 'TDD')
    tddPattern = sixgr.util.structGet(cfg, 'phy.duplex.tddPattern', ...
        sixgr.util.structGet(cfg, 'scenario.tddPattern', 'DDDSU'));
    localValidateTDDPattern(tddPattern, 'phy.duplex.tddPattern');
end

% Traffic controls
transport = upper(char(string(sixgr.util.structGet(cfg, 'traffic.transport', 'UDP'))));
localOneOf(transport, {'UDP','TCP','MIXED'}, 'traffic.transport');
flowDir = upper(char(string(sixgr.util.structGet(cfg, 'traffic.flowDirection', 'BIDIR'))));
localOneOf(flowDir, {'DL','UL','BIDIR'}, 'traffic.flowDirection');
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

flows = sixgr.util.structGet(cfg, 'traffic.flows', []);
if ~isempty(flows)
    if ~isstruct(flows)
        error('sixgr:config:BadFlows', 'traffic.flows must be a struct array.');
    end
    for i = 1:numel(flows)
        if isfield(flows(i), 'protocol')
            p = upper(char(string(flows(i).protocol)));
            localOneOf(p, {'UDP','TCP'}, sprintf('traffic.flows(%d).protocol', i));
        end
        if isfield(flows(i), 'direction')
            d = upper(char(string(flows(i).direction)));
            localOneOf(d, {'DL','UL','BIDIR'}, sprintf('traffic.flows(%d).direction', i));
        end
        if isfield(flows(i), 'packetDelayBudget_ms')
            fpdb = double(flows(i).packetDelayBudget_ms);
            if ~(isfinite(fpdb) && fpdb > 0)
                error('sixgr:config:BadFlowPDB', 'traffic.flows(%d).packetDelayBudget_ms must be > 0.', i);
            end
        end
    end
end

% Numerology constraints
scs = double(cfg.phy.carrier.SubcarrierSpacing);
validSCS = [15 30 60 120 240];
if ~ismember(scs, validSCS)
    error('sixgr:config:BadSCS', 'phy.carrier.SubcarrierSpacing must be one of [%s] kHz.', num2str(validSCS));
end

nRB = double(cfg.phy.carrier.NSizeGrid);
if ~(isfinite(nRB) && nRB >= 1 && mod(nRB,1)==0)
    error('sixgr:config:BadNRB', 'phy.carrier.NSizeGrid must be a positive integer.');
end

% Frequency constraints
fc = double(cfg.channel.fc_Hz);
if ~(isfinite(fc) && fc > 0)
    error('sixgr:config:BadFc', 'channel.fc_Hz must be > 0.');
end

localValidateChannelProfiles(cfg);

% UL waveform consistency
ulWf = upper(char(cfg.phy.waveform.ul));
if strcmp(ulWf,'DFT-S-OFDM')
    if ~isfield(cfg.phy,'pusch') || ~isfield(cfg.phy.pusch,'transformPrecoding') || ~logical(cfg.phy.pusch.transformPrecoding)
        error('sixgr:config:BadULWaveform', 'DFT-s-OFDM selected but phy.pusch.transformPrecoding is not enabled.');
    end
end

% Modulation enums (allow future high-order QAM strings)
if isfield(cfg.phy,'pdsch') && isfield(cfg.phy.pdsch,'modulation')
    localModOK(char(cfg.phy.pdsch.modulation), 'phy.pdsch.modulation');
end
if isfield(cfg.phy,'pusch') && isfield(cfg.phy.pusch,'modulation')
    localModOK(char(cfg.phy.pusch.modulation), 'phy.pusch.modulation');
end

% Output flags should be scalar logical
localScalarLogical(cfg.outputs.saveMAT, 'outputs.saveMAT');
localScalarLogical(cfg.outputs.saveCSV, 'outputs.saveCSV');
localScalarLogical(cfg.outputs.saveFigures, 'outputs.saveFigures');
localScalarLogical(cfg.outputs.saveFIG, 'outputs.saveFIG');

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

function localModOK(modStr, fieldName)
m = upper(strtrim(modStr));
allowed = {'PI/2-BPSK','BPSK','QPSK','16QAM','64QAM','256QAM','1024QAM','4096QAM'};
if ~any(strcmp(m, allowed))
    error('sixgr:config:BadModulation', '%s must be one of: %s', fieldName, strjoin(allowed, ', '));
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

function localValidateTDDPattern(pat, fieldName)
if isstruct(pat)
    dl = double(sixgr.util.structGet(pat, 'dlSlots', NaN));
    ul = double(sixgr.util.structGet(pat, 'ulSlots', NaN));
    sp = double(sixgr.util.structGet(pat, 'specialSlots', 0));
    if ~(isfinite(dl) && isfinite(ul) && isfinite(sp) && dl >= 0 && ul >= 0 && sp >= 0 && (dl + ul + sp) > 0)
        error('sixgr:config:BadTDDPattern', '%s struct must define non-negative dlSlots/ulSlots/specialSlots with a non-zero total.', fieldName);
    end
    return;
end

if ischar(pat) || isstring(pat)
    s = upper(char(string(pat)));
    s = regexprep(s, '[^DUS]', '');
    if isempty(s)
        error('sixgr:config:BadTDDPattern', '%s string must contain at least one D/U/S token.', fieldName);
    end
    return;
end

if isnumeric(pat)
    v = double(pat(:));
    if isempty(v)
        error('sixgr:config:BadTDDPattern', '%s numeric pattern cannot be empty.', fieldName);
    end
    return;
end

error('sixgr:config:BadTDDPattern', '%s must be struct, string pattern, or numeric vector.', fieldName);
end
