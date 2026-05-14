function cfg = normalizeConfig(cfg)
% sixgr.config.normalizeConfig
% Convert units, harmonize duplicated fields, and derive dependent parameters.
%
% This function should be side-effect free (returns a new cfg struct).

if nargin < 1 || isempty(cfg) || ~isa(cfg,'struct')
    error('sixgr:config:normalizeConfig:BadInput','cfg must be a struct.');
end

% -------------------------------------------------------------------------
% Backward-compatible key harmonization (old JSON -> canonical fields)
% -------------------------------------------------------------------------
% Run aliases
if isfield(cfg,'run') && isa(cfg.run,'struct')
    if isfield(cfg.run,'saveRoot') && ~isempty(cfg.run.saveRoot)
        cfg.run.resultsRoot = cfg.run.saveRoot;
    end
    if isfield(cfg.run,'nFrames') && (~isfield(cfg.run,'numFrames') || isempty(cfg.run.numFrames))
        cfg.run.numFrames = cfg.run.nFrames;
    end
end

% Scenario/channel aliases used by older configs
if isfield(cfg,'scenario') && isa(cfg.scenario,'struct')
    if isfield(cfg.scenario,'carrierFreq_Hz') && (~isfield(cfg,'channel') || ~isfield(cfg.channel,'fc_Hz') || isempty(cfg.channel.fc_Hz))
        cfg.channel = localStructEnsure(cfg,'channel');
        cfg.channel.fc_Hz = cfg.scenario.carrierFreq_Hz;
    end
    if isfield(cfg.scenario,'bandwidth_Hz') && (~isfield(cfg,'channel') || ~isfield(cfg.channel,'bandwidth_Hz') || isempty(cfg.channel.bandwidth_Hz))
        cfg.channel = localStructEnsure(cfg,'channel');
        cfg.channel.bandwidth_Hz = cfg.scenario.bandwidth_Hz;
    end
    if isfield(cfg.scenario,'sCS_kHz') && (~isfield(cfg.phy,'carrier') || ~isfield(cfg.phy.carrier,'SubcarrierSpacing') || isempty(cfg.phy.carrier.SubcarrierSpacing))
        cfg.phy = localStructEnsure(cfg,'phy');
        cfg.phy.carrier = localStructEnsure(cfg.phy,'carrier');
        cfg.phy.carrier.SubcarrierSpacing = cfg.scenario.sCS_kHz;
    end
    if isfield(cfg.scenario,'nUE') && (~isfield(cfg.scenario,'ue') || ~isfield(cfg.scenario.ue,'nUE') || isempty(cfg.scenario.ue.nUE))
        cfg.scenario.ue = localStructEnsure(cfg.scenario,'ue');
        cfg.scenario.ue.nUE = cfg.scenario.nUE;
    end
end

% Channel model aliases
if isfield(cfg,'channel') && isa(cfg.channel,'struct')
    if ~isfield(cfg.channel,'model') && isfield(cfg.channel,'type')
        cfg.channel.model = cfg.channel.type;
    end
    if isfield(cfg.channel,'awgnOnly') && logical(cfg.channel.awgnOnly)
        cfg.channel.model = 'AWGN';
        cfg.channel.type = 'AWGN';
        cfg.channel.delayProfile = '';
        cfg.channel.tdlProfile = '';
        cfg.channel.cdlProfile = '';
        cfg.channel.fading = localStructEnsure(cfg.channel, 'fading');
        cfg.channel.fading.enable = false;
        cfg.channel.fading.model = '';
        cfg.channel.fading.profile = '';
    end

    if isfield(cfg.channel,'model')
        cfg.channel.model = localNormalizeChannelToken(cfg.channel.model);
    end
    if isfield(cfg.channel,'delayProfile')
        cfg.channel.delayProfile = localNormalizeChannelToken(cfg.channel.delayProfile);
    end
    if isfield(cfg.channel,'tdlProfile')
        cfg.channel.tdlProfile = localNormalizeChannelToken(cfg.channel.tdlProfile);
    end
    if isfield(cfg.channel,'cdlProfile')
        cfg.channel.cdlProfile = localNormalizeChannelToken(cfg.channel.cdlProfile);
    end
    if isfield(cfg.channel,'fading') && isa(cfg.channel.fading,'struct')
        if isfield(cfg.channel.fading,'model')
            cfg.channel.fading.model = localNormalizeChannelToken(cfg.channel.fading.model);
        end
        if isfield(cfg.channel.fading,'profile')
            cfg.channel.fading.profile = localNormalizeChannelToken(cfg.channel.fading.profile);
        end
    end

    cfg.channel = localAdoptConcreteChannelProfile(cfg.channel, sixgr.util.structGet(cfg, 'channel.delayProfile', ""));
    [modelOut, channelOut] = localNormalizeLegacyChannelModel( ...
        sixgr.util.structGet(cfg, 'channel.model', ""), cfg.channel);
    channelOut.model = modelOut;
    cfg.channel = channelOut;
    if isfield(cfg.channel,'fading') && isa(cfg.channel.fading,'struct')
        [fadingModelOut, fadingProfileOut, channelOut] = ...
            localNormalizeLegacyChannelFamily(cfg.channel, ...
            sixgr.util.structGet(cfg, 'channel.fading.model', ""), ...
            sixgr.util.structGet(cfg, 'channel.fading.profile', ""));
        channelOut.fading = localStructEnsure(channelOut, 'fading');
        channelOut.fading.model = fadingModelOut;
        channelOut.fading.profile = fadingProfileOut;
        cfg.channel = channelOut;
    end
    if isfield(cfg.channel,'model') && ~isempty(cfg.channel.model)
        cfg.channel.type = cfg.channel.model;
    end

    if isfield(cfg.channel,'fading') && isa(cfg.channel.fading,'struct')
        if isfield(cfg.channel.fading,'delaySpread_s') && (~isfield(cfg.channel,'delaySpread_s') || isempty(cfg.channel.delaySpread_s))
            cfg.channel.delaySpread_s = cfg.channel.fading.delaySpread_s;
        end
        if isfield(cfg.channel.fading,'maxDoppler_Hz') && (~isfield(cfg.channel,'doppler_Hz') || isempty(cfg.channel.doppler_Hz))
            cfg.channel.doppler_Hz = cfg.channel.fading.maxDoppler_Hz;
        end
    end
    if isfield(cfg.channel,'dopplerHz') && (~isfield(cfg.channel,'doppler_Hz') || isempty(cfg.channel.doppler_Hz))
        cfg.channel.doppler_Hz = cfg.channel.dopplerHz;
    end

end

% PHY legacy hierarchy aliases: phy.dl.pdsch -> phy.pdsch, etc.
if isfield(cfg,'phy') && isa(cfg.phy,'struct')
    % Canonical aliasing for pdsch/pusch layer field names.
    if isfield(cfg.phy,'pdsch') && isstruct(cfg.phy.pdsch)
        if isfield(cfg.phy.pdsch,'nLayers') && (~isfield(cfg.phy.pdsch,'numLayers') || isempty(cfg.phy.pdsch.numLayers))
            cfg.phy.pdsch.numLayers = cfg.phy.pdsch.nLayers;
        end
    end
    if isfield(cfg.phy,'pusch') && isstruct(cfg.phy.pusch)
        if isfield(cfg.phy.pusch,'nLayers') && (~isfield(cfg.phy.pusch,'numLayers') || isempty(cfg.phy.pusch.numLayers))
            cfg.phy.pusch.numLayers = cfg.phy.pusch.nLayers;
        end
    end

    if isfield(cfg.phy,'dl') && isstruct(cfg.phy.dl)
        if isfield(cfg.phy.dl,'pdsch') && isstruct(cfg.phy.dl.pdsch)
            p = cfg.phy.dl.pdsch;
            cfg.phy.pdsch = localStructEnsure(cfg.phy,'pdsch');
            if isfield(p,'Enable'),     cfg.phy.pdsch.enable = logical(p.Enable); end
            if isfield(p,'Modulation'), cfg.phy.pdsch.modulation = char(string(p.Modulation)); end
            if isfield(p,'NumLayers'),  cfg.phy.pdsch.nLayers = double(p.NumLayers); end
            if isfield(p,'NumLayers'),  cfg.phy.pdsch.numLayers = double(p.NumLayers); end
            if isfield(p,'RNTI'),       cfg.phy.pdsch.rnti = double(p.RNTI); end
        end
        if isfield(cfg.phy.dl,'pdcch') && isstruct(cfg.phy.dl.pdcch) && isfield(cfg.phy.dl.pdcch,'Enable')
            cfg.phy.pdcch = localStructEnsure(cfg.phy,'pdcch');
            cfg.phy.pdcch.enable = logical(cfg.phy.dl.pdcch.Enable);
        end
    end

    if isfield(cfg.phy,'ul') && isstruct(cfg.phy.ul)
        if isfield(cfg.phy.ul,'pusch') && isstruct(cfg.phy.ul.pusch)
            p = cfg.phy.ul.pusch;
            cfg.phy.pusch = localStructEnsure(cfg.phy,'pusch');
            if isfield(p,'Enable'), cfg.phy.pusch.enable = logical(p.Enable); end
            if isfield(p,'Modulation'), cfg.phy.pusch.modulation = char(string(p.Modulation)); end
            if isfield(p,'NumLayers'), cfg.phy.pusch.nLayers = double(p.NumLayers); end
            if isfield(p,'NumLayers'), cfg.phy.pusch.numLayers = double(p.NumLayers); end
            if isfield(p,'TransformPrecoding'), cfg.phy.pusch.transformPrecoding = logical(p.TransformPrecoding); end
            if isfield(p,'RNTI'), cfg.phy.pusch.rnti = double(p.RNTI); end
        end
        if isfield(cfg.phy.ul,'prach') && isstruct(cfg.phy.ul.prach) && isfield(cfg.phy.ul.prach,'Enable')
            cfg.phy.prach = localStructEnsure(cfg.phy,'prach');
            cfg.phy.prach.enable = logical(cfg.phy.ul.prach.Enable);
        end
        if isfield(cfg.phy.ul,'pucch') && isstruct(cfg.phy.ul.pucch) && isfield(cfg.phy.ul.pucch,'Enable')
            cfg.phy.pucch = localStructEnsure(cfg.phy,'pucch');
            cfg.phy.pucch.enable = logical(cfg.phy.ul.pucch.Enable);
        end
        if isfield(cfg.phy.ul,'srs') && isstruct(cfg.phy.ul.srs) && isfield(cfg.phy.ul.srs,'Enable')
            cfg.phy.srs = localStructEnsure(cfg.phy,'srs');
            cfg.phy.srs.enable = logical(cfg.phy.ul.srs.Enable);
        end
    end

    if isfield(cfg.phy,'ssb') && isstruct(cfg.phy.ssb)
        if isfield(cfg.phy.ssb,'Enable')
            cfg.phy.ssb.enable = logical(cfg.phy.ssb.Enable);
        end
    end

    if isfield(cfg.phy,'waveform') && isstruct(cfg.phy.waveform) && isfield(cfg.phy.waveform,'type')
        typ = upper(strtrim(char(string(cfg.phy.waveform.type))));
        if strcmp(typ,'CP-OFDM')
            cfg.phy.waveform.dl = 'CP-OFDM';
            cfg.phy.waveform.ul = 'CP-OFDM';
            cfg.phy.pusch = localStructEnsure(cfg.phy, 'pusch');
            cfg.phy.pusch.transformPrecoding = false;
        elseif contains(typ,'DFT')
            cfg.phy.waveform.ul = 'DFT-s-OFDM';
            cfg.phy.pusch = localStructEnsure(cfg.phy, 'pusch');
            cfg.phy.pusch.transformPrecoding = true;
        end
    end

    cfg.phy = localStructEnsure(cfg, 'phy');
    cfg.phy.csi = localStructEnsure(cfg.phy, 'csi');
    cfg.phy.pdsch = localStructEnsure(cfg.phy, 'pdsch');
    cfg.phy.pusch = localStructEnsure(cfg.phy, 'pusch');

    defaultCQITable = char(localNormalizeCQITable(localFirstNonEmpty( ...
        sixgr.util.structGet(cfg, "phy.csi.cqiTable", []), ...
        "table1")));
    cfg.phy.csi.cqiTable = defaultCQITable;
    cfg.phy.csi.dlCQITable = char(localNormalizeCQITable(localFirstNonEmpty( ...
        sixgr.util.structGet(cfg, "phy.csi.dlCQITable", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.cqiTable", []), ...
        defaultCQITable)));
    cfg.phy.csi.ulCQITable = char(localNormalizeCQITable(localFirstNonEmpty( ...
        sixgr.util.structGet(cfg, "phy.csi.ulCQITable", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.cqiTable", []), ...
        defaultCQITable)));
    cfg.phy.pdsch.cqiTable = cfg.phy.csi.dlCQITable;
    cfg.phy.pusch.cqiTable = cfg.phy.csi.ulCQITable;
    % Wideband CQI fallback is intentionally conservative because it maps a
    % single effective SINR into NR CQI without per-RB frequency selectivity.
    cfg.phy.csi.widebandSINRMargin_dB = double(localFirstNonEmpty( ...
        sixgr.util.structGet(cfg, "phy.csi.widebandSINRMargin_dB", []), 5));

    cfg.phy.pdsch.mcsTable = char(localNormalizeMCSTable(localFirstNonEmpty( ...
        sixgr.util.structGet(cfg, "phy.pdsch.mcsTable", []), ...
        localDefaultMCSTableForModulation(sixgr.util.structGet(cfg, "phy.pdsch.modulation", "16QAM")))));
    cfg.phy.pusch.mcsTable = char(localNormalizeMCSTable(localFirstNonEmpty( ...
        sixgr.util.structGet(cfg, "phy.pusch.mcsTable", []), ...
        localDefaultMCSTableForModulation(sixgr.util.structGet(cfg, "phy.pusch.modulation", "16QAM")))));
end

% Output aliases
if isfield(cfg,'outputs') && isa(cfg.outputs,'struct')
    if isfield(cfg.outputs,'saveMat'), cfg.outputs.saveMAT = logical(cfg.outputs.saveMat); end
    if isfield(cfg.outputs,'saveCsv'), cfg.outputs.saveCSV = logical(cfg.outputs.saveCsv); end
    if isfield(cfg.outputs,'saveCSV'), cfg.outputs.saveCSV = logical(cfg.outputs.saveCSV); end
    if isfield(cfg.outputs,'saveFIG') && ~isfield(cfg.outputs,'saveFigures')
        cfg.outputs.saveFigures = logical(cfg.outputs.saveFIG);
    end
    if isfield(cfg.outputs,'saveFigures')
        cfg.outputs.saveFigures = logical(cfg.outputs.saveFigures);
        cfg.outputs.saveFIG = cfg.outputs.saveFigures; % keep legacy alias mirrored
    elseif isfield(cfg.outputs,'saveFIG')
        cfg.outputs.saveFIG = logical(cfg.outputs.saveFIG);
        cfg.outputs.saveFigures = cfg.outputs.saveFIG;
    end
end

% -------------------------------------------------------------------------
% Harmonize carrier / channel parameters
% -------------------------------------------------------------------------
% Prefer cfg.channel.* as the "carrier truth", but keep cfg.phy.carrier aligned.

profileName = localNormalizeScenarioClass(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "scenario.profileName", []), ...
    sixgr.util.structGet(cfg, "deployment_topology.cell_type", []), ...
    sixgr.util.structGet(cfg, "lls6g.resolvedConfig.deployment_topology.cell_type", []), ...
    sixgr.util.structGet(cfg, "scenario.name", []), ...
    "UMa"));
propagationScenario = localNormalizeScenarioClass(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "channel.propagationScenario", []), ...
    sixgr.util.structGet(cfg, "run.scenario", []), ...
    sixgr.util.structGet(cfg, "deployment_topology.cell_type", []), ...
    sixgr.util.structGet(cfg, "lls6g.resolvedConfig.deployment_topology.cell_type", []), ...
    profileName, ...
    "UMa"));

cfg = sixgr.util.structSet(cfg, "scenario.profileName", char(profileName));
cfg = sixgr.util.structSet(cfg, "scenario.name", char(profileName));
cfg = sixgr.util.structSet(cfg, "channel.propagationScenario", char(propagationScenario));
cfg = sixgr.util.structSet(cfg, "run.scenario", char(propagationScenario));
cfg = sixgr.util.structSet(cfg, "phy.fc_Hz", ...
    sixgr.util.structGet(cfg, "phy.fc_Hz", ...
    sixgr.util.structGet(cfg, "channel.fc_Hz", 3.5e9)));
cfg = sixgr.util.structSet(cfg, "channel.pathlossModel", ...
    sixgr.util.structGet(cfg, "channel.pathlossModel", ...
    sixgr.util.structGet(cfg, "channel.pathloss.model", "nrPathLoss")));
cfg = sixgr.util.structSet(cfg, "channel.complianceMode", ...
    localNormalizeChannelComplianceMode(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "channel.complianceMode", []), ...
    sixgr.util.structGet(cfg, "channel.compliance.mode", []), ...
    localDefaultChannelComplianceMode(cfg))));
cfg = sixgr.util.structSet(cfg, "channel.shadowSigma_dB", ...
    sixgr.util.structGet(cfg, "channel.shadowSigma_dB", ...
    sixgr.util.structGet(cfg, "channel.shadowFadingStd_dB", 0)));
cfg = sixgr.util.structSet(cfg, "channel.pathlossEnabled", ...
    localLogicalWithDefault(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "channel.pathlossEnabled", []), ...
    sixgr.util.structGet(cfg, "channel.pathloss.enabled", []), ...
    true), true));
cfg = sixgr.util.structSet(cfg, "channel.shadowFadingEnabled", ...
    localLogicalWithDefault(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "channel.shadowFadingEnabled", []), ...
    sixgr.util.structGet(cfg, "channel.shadowFading.enabled", []), ...
    true), true));
cfg = sixgr.util.structSet(cfg, "channel.losEnabled", ...
    localLogicalWithDefault(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "channel.losEnabled", []), ...
    sixgr.util.structGet(cfg, "channel.los.enabled", []), ...
    true), true));
cfg = sixgr.util.structSet(cfg, "channel.spatialConsistencyEnabled", ...
    localLogicalWithDefault(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "channel.spatialConsistencyEnabled", []), ...
    sixgr.util.structGet(cfg, "channel.spatialConsistency.enabled", []), ...
    false), false));

if isfield(cfg,'channel') && isa(cfg.channel,'struct')
    if isfield(cfg.channel,'fc_Hz')
        cfg.phy.carrier = localStructEnsure(cfg.phy, 'carrier');
        % Do not force overwrite of config values if user explicitly set PHY carrier freq later.
        cfg.phy.carrier.fc_Hz = cfg.channel.fc_Hz;
    end
    if isfield(cfg.channel,'subcarrierSpacing_kHz')
        cfg.phy.carrier.SubcarrierSpacing = cfg.channel.subcarrierSpacing_kHz;
    end
end

% Ensure numeric types where expected
cfg.run.seed = double(cfg.run.seed);

% Normalize mode string to lower-case
cfg.run.mode = lower(char(cfg.run.mode));
cfg.run.module = strtrim(char(string(cfg.run.module)));

% Single public runner entrypoint:
% map legacy runner aliases to the unified campaign function.
legacyModules = { ...
    '', ...
    'SixGR_Simulator', ...
    'sixgr_verify_all', ...
    'sixgr_run_long_linklevel', ...
    'sixgr_run_30min_mobility_system', ...
    'sixgr_run_detailed_lls', ...
    'runSimSuite', ...
    'sixgr_diag_all' ...
    };
if any(strcmpi(cfg.run.module, legacyModules))
    cfg.run.module = 'sixgr_run_3gpp_full_campaign';
end

cfg.mac = localStructEnsure(cfg, 'mac');
cfg.mac.scheduler = localStructEnsure(cfg.mac, 'scheduler');
cfg.mac.scheduler.tbsMode = char(localNormalizeTBSMode(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "mac.scheduler.tbsMode", []), "approximate")));
cfg.mac.scheduler.viennaEquivalent = localLogicalWithDefault(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "mac.scheduler.viennaEquivalent", []), false), false);
cfg.mac.scheduler.allowApproximatePlanningInStrictMode = localLogicalWithDefault(localFirstNonEmpty( ...
    sixgr.util.structGet(cfg, "mac.scheduler.allowApproximatePlanningInStrictMode", []), false), false);
if strcmpi(cfg.mac.scheduler.tbsMode, 'faithful') || strcmpi(cfg.mac.scheduler.tbsMode, 'strict') || ...
        (logical(sixgr.util.structGet(cfg, "run.strictMode", false)) && ~logical(cfg.mac.scheduler.allowApproximatePlanningInStrictMode)) || ...
        logical(cfg.mac.scheduler.viennaEquivalent)
    cfg.mac.scheduler.fastNREApprox = false;
elseif ~isfield(cfg.mac.scheduler, 'fastNREApprox') || isempty(cfg.mac.scheduler.fastNREApprox)
    cfg.mac.scheduler.fastNREApprox = true;
else
    cfg.mac.scheduler.fastNREApprox = logical(cfg.mac.scheduler.fastNREApprox);
end

% -------------------------------------------------------------------------
% Derive numerology helpers
% -------------------------------------------------------------------------
scs = double(cfg.phy.carrier.SubcarrierSpacing); % kHz
nRB = double(cfg.phy.carrier.NSizeGrid);
cfg.phy.numerology = localStructEnsure(cfg.phy,'numerology');
cfg.phy.numerology.SubcarrierSpacing_kHz = scs;
cfg.phy.numerology.NRB = nRB;
cfg.phy.numerology.NSubcarriers = 12*nRB;

% Numerology mu and timing
mu = log2(scs/15);
if ~isfinite(mu) || mu < 0
    mu = 0;
end
cfg.phy.numerology.mu = mu;
cfg.phy.numerology.slotsPerSubframe = 2^mu;
cfg.phy.numerology.slotsPerFrame = 10 * cfg.phy.numerology.slotsPerSubframe;

% -------------------------------------------------------------------------
% OFDM info (optional, uses 5G Toolbox if present)
% -------------------------------------------------------------------------
cfg.phy.ofdm = struct();
if exist('nrOFDMInfo','file') == 2 && exist('nrCarrierConfig','file') == 2
    try
        carrier = nrCarrierConfig;
        carrier.SubcarrierSpacing = scs;
        carrier.NSizeGrid = nRB;
        carrier.CyclicPrefix = cfg.phy.carrier.CyclicPrefix;
        info = nrOFDMInfo(carrier);
        cfg.phy.ofdm = info;
        if isfield(cfg,'channel') && isa(cfg.channel,'struct')
            cfg.channel.sampleRate_Hz = info.SampleRate;
            cfg.channel.nfft = info.Nfft;
        end
    catch
        % Keep cfg.phy.ofdm empty if 5G Toolbox call fails
    end
else
    % Minimal derived values (approx) without 5G Toolbox
    % Nfft: next power of 2 >= NSubcarriers
    nSC = cfg.phy.numerology.NSubcarriers;
    cfg.phy.ofdm.Nfft = 2^nextpow2(max(1,nSC));
    % Sample rate approx: Nfft * SCS
    cfg.phy.ofdm.SampleRate = cfg.phy.ofdm.Nfft * (scs*1e3);
end

% -------------------------------------------------------------------------
% Scenario convenience fields
% -------------------------------------------------------------------------
cfg.scenario.layout.interSiteDistance_m = double(cfg.scenario.layout.interSiteDistance_m);
cfg.scenario.ue.nUE = double(cfg.scenario.ue.nUE);

% Mobility speed vector normalize
if isfield(cfg.scenario,'mobility') && isa(cfg.scenario.mobility,'struct')
    v = cfg.scenario.mobility.speed_kmh;
    if isempty(v)
        v = [0 0];
    end
    v = double(v(:).');
    if numel(v) == 1
        v = [v v];
    elseif numel(v) > 2
        v = v(1:2);
    end
    cfg.scenario.mobility.speed_kmh = v;
end

% -------------------------------------------------------------------------
% Output flags normalize to logical
% -------------------------------------------------------------------------
if ~isfield(cfg.outputs, 'storageBackend') || strlength(string(cfg.outputs.storageBackend)) == 0
    cfg.outputs.storageBackend = "filesystem";
end
if ~isfield(cfg.outputs, 'databaseHost') || strlength(string(cfg.outputs.databaseHost)) == 0
    cfg.outputs.databaseHost = "localhost";
end
if ~isfield(cfg.outputs, 'databasePort') || isempty(cfg.outputs.databasePort)
    cfg.outputs.databasePort = 3306;
end
if ~isfield(cfg.outputs, 'databaseSchema') || strlength(string(cfg.outputs.databaseSchema)) == 0
    cfg.outputs.databaseSchema = "sixgr_results";
end
cfg.outputs.storageBackend = char(string(cfg.outputs.storageBackend));
cfg.outputs.databaseHost = char(string(cfg.outputs.databaseHost));
cfg.outputs.databasePort = double(cfg.outputs.databasePort);
cfg.outputs.databaseSchema = char(string(cfg.outputs.databaseSchema));
cfg.outputs.saveMAT = logical(cfg.outputs.saveMAT);
cfg.outputs.saveCSV = logical(cfg.outputs.saveCSV);
cfg.outputs.saveFigures = logical(cfg.outputs.saveFigures);
cfg.outputs.saveFIG = logical(cfg.outputs.saveFIG);
cfg.outputs.savePNG = logical(cfg.outputs.savePNG);
cfg.outputs.plotVisible = logical(cfg.outputs.plotVisible);

% GUI flags
cfg.gui.enable = logical(cfg.gui.enable);
cfg.gui.useSiteViewer = logical(cfg.gui.useSiteViewer);
cfg.gui.showUEMobility = logical(cfg.gui.showUEMobility);

end

% -------------------------------------------------------------------------
function s = localStructEnsure(parent, fieldName)
% Return parent.(fieldName) if it exists and is struct, else create empty struct.
if isfield(parent, fieldName) && isa(parent.(fieldName),'struct')
    s = parent.(fieldName);
else
    s = struct();
end
end

function value = localFirstNonEmpty(varargin)
value = [];
for i = 1:nargin
    candidate = varargin{i};
    if ischar(candidate) || isstring(candidate)
        if strlength(strtrim(string(candidate))) > 0
            value = candidate;
            return;
        end
    elseif isnumeric(candidate) || islogical(candidate)
        if ~isempty(candidate)
            value = candidate;
            return;
        end
    elseif ~isempty(candidate)
        value = candidate;
        return;
    end
end
end

function tf = localLogicalWithDefault(value, defaultValue)
if isempty(value)
    tf = logical(defaultValue);
else
    tf = logical(value);
end
end

function token = localNormalizeCQITable(value)
token = lower(strtrim(char(string(value))));
switch token
    case {"", "1", "table1", "table_1", "cqi_table1", "cqi_table_1", "nr_table1", "nr_cqi_table1"}
        token = 'table1';
    case {"2", "table2", "table_2", "cqi_table2", "cqi_table_2", "nr_table2", "nr_cqi_table2"}
        token = 'table2';
end
end

function token = localNormalizeMCSTable(value)
token = lower(strtrim(char(string(value))));
switch token
    case {"", "qam64", "table1", "mcs_table1", "qam64table1"}
        token = 'qam64_table1';
    case {"qam256", "table2", "mcs_table2", "qam256table2"}
        token = 'qam256_table2';
    case {"qam64lowse", "table3", "mcs_table3", "qam64lowse_table3"}
        token = 'qam64lowse_table3';
end
end

function token = localDefaultMCSTableForModulation(modulation)
scheme = upper(char(string(modulation)));
if any(strcmp(scheme, {'256QAM','1024QAM','4096QAM'}))
    token = 'qam256_table2';
else
    token = 'qam64_table1';
end
end

function token = localNormalizeTBSMode(value)
token = lower(strtrim(char(string(value))));
switch token
    case {"", "fast", "approx", "approximate"}
        token = 'approximate';
    case {"faithful", "accurate", "exact", "nr"}
        token = 'faithful';
    case {"strict"}
        token = 'strict';
end
end

function scenarioName = localNormalizeScenarioClass(value)
token = lower(strtrim(char(string(value))));
switch token
    case {"uma", "urbanmacro", "urban_macro"}
        scenarioName = "UMa";
    case {"umi", "urbanmicro", "urban_micro", "denseurban", "dense_urban"}
        scenarioName = "UMi";
    case {"rma", "ruralmacro", "rural_macro"}
        scenarioName = "RMa";
    case {"sma", "suburbanmacro", "suburban_macro"}
        scenarioName = "SMa";
    case {"inh", "indoorhotspot", "indoor_hotspot", "indoor", "office"}
        scenarioName = "InH";
    case {"inf", "indoorfactory", "indoor_factory", "factory"}
        scenarioName = "InF";
    otherwise
        if strlength(strtrim(string(value))) == 0
            scenarioName = "UMa";
        else
            scenarioName = string(value);
        end
end
end

function ch = localAdoptConcreteChannelProfile(ch, rawProfile)
profile = localNormalizeChannelToken(rawProfile);
if localIsConcreteTDLProfile(profile)
    if ~isfield(ch,'tdlProfile') || isempty(ch.tdlProfile) || strcmpi(strtrim(char(string(ch.tdlProfile))), 'TDL')
        ch.tdlProfile = profile;
    end
elseif localIsConcreteCDLProfile(profile)
    if ~isfield(ch,'cdlProfile') || isempty(ch.cdlProfile) || strcmpi(strtrim(char(string(ch.cdlProfile))), 'CDL')
        ch.cdlProfile = profile;
    end
end
end

function [modelOut, ch] = localNormalizeLegacyChannelModel(rawModel, ch)
modelOut = localNormalizeChannelToken(rawModel);
if localIsConcreteTDLProfile(modelOut)
    ch = localAdoptConcreteChannelProfile(ch, modelOut);
    modelOut = 'TDL';
elseif localIsConcreteCDLProfile(modelOut)
    ch = localAdoptConcreteChannelProfile(ch, modelOut);
    modelOut = 'CDL';
elseif localIsTDLModelAlias(modelOut)
    modelOut = 'TDL';
elseif localIsCDLModelAlias(modelOut)
    modelOut = 'CDL';
end
end

function [modelOut, profileOut, ch] = localNormalizeLegacyChannelFamily(ch, rawModel, rawProfile)
modelOut = localNormalizeChannelToken(rawModel);
profileOut = localNormalizeChannelToken(rawProfile);

ch = localAdoptConcreteChannelProfile(ch, profileOut);

if localIsConcreteTDLProfile(modelOut)
    ch = localAdoptConcreteChannelProfile(ch, modelOut);
    if isempty(profileOut) || strcmp(profileOut, 'TDL') || strcmp(profileOut, modelOut)
        profileOut = modelOut;
    end
    modelOut = 'TDL';
elseif localIsConcreteCDLProfile(modelOut)
    ch = localAdoptConcreteChannelProfile(ch, modelOut);
    if isempty(profileOut) || strcmp(profileOut, 'CDL') || strcmp(profileOut, modelOut)
        profileOut = modelOut;
    end
    modelOut = 'CDL';
elseif localIsTDLModelAlias(modelOut)
    modelOut = 'TDL';
elseif localIsCDLModelAlias(modelOut)
    modelOut = 'CDL';
end

if isempty(modelOut)
    if localIsConcreteTDLProfile(profileOut)
        modelOut = 'TDL';
    elseif localIsConcreteCDLProfile(profileOut)
        modelOut = 'CDL';
    end
end
end

function token = localNormalizeChannelToken(rawValue)
token = upper(strtrim(char(string(rawValue))));
end

function tf = localIsTDLModelAlias(model)
model = localNormalizeChannelToken(model);
tf = any(strcmp(model, {'TDL', 'NRTDL'}));
end

function tf = localIsCDLModelAlias(model)
model = localNormalizeChannelToken(model);
tf = any(strcmp(model, {'CDL', 'NRCDL'}));
end

function tf = localIsConcreteTDLProfile(profile)
profile = localNormalizeChannelToken(profile);
tf = startsWith(profile, 'TDL') && ~strcmp(profile, 'TDL');
end

function tf = localIsConcreteCDLProfile(profile)
profile = localNormalizeChannelToken(profile);
tf = startsWith(profile, 'CDL') && ~strcmp(profile, 'CDL');
end

function mode = localDefaultChannelComplianceMode(cfg)
if logical(sixgr.util.structGet(cfg, "run.strictMode", false))
    mode = "strict_38901";
else
    mode = "approximate_38901_plus";
end
end

function mode = localNormalizeChannelComplianceMode(value)
token = lower(strtrim(char(string(value))));
switch token
    case {"", "approximate", "approximate_38901", "approximate_38901_plus", "tr38901_plus"}
        mode = "approximate_38901_plus";
    case {"strict", "strict_38901", "tr38901_strict"}
        mode = "strict_38901";
    case {"legacy", "legacy_fallback", "fallback"}
        mode = "legacy_fallback";
    otherwise
        mode = string(value);
end
end
