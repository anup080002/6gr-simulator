function c = toCoderConfig(cfg)
% sixgr.config.toCoderConfig
% Emit a fixed-field struct suitable as a MATLAB Coder input.
%
% Notes:
% - MATLAB Coder requires fixed field names and prefers fixed-size arrays.
% - Strings/enums are mapped to integer codes.
% - Not every config parameter is exported yet; extend as modules are added.

if nargin < 1 || isempty(cfg) || ~isa(cfg,'struct')
    error('sixgr:config:toCoderConfig:BadInput','cfg must be a struct.');
end

% Ensure normalized before export
cfg = sixgr.config.normalizeConfig(cfg);
catalog = sixgr.config.loadCoreCatalog();

c = struct();

% -------------------------------------------------------------------------
% Run
% -------------------------------------------------------------------------
c.run = struct();
c.run.seed = uint32(cfg.run.seed);
c.run.shortRun = logical(cfg.run.shortRun);

c.run.mode = uint8(localMapEnum(lower(char(cfg.run.mode)), ...
    localCatalogEnumOrder(catalog, "run.mode", {'link','system','both'}), ...
    uint8(localCatalogDefaultCode(catalog, "run.mode", 0))));

% -------------------------------------------------------------------------
% Scenario
% -------------------------------------------------------------------------
c.scenario = struct();
c.scenario.name = uint8(localMapEnum(lower(char(cfg.scenario.name)), ...
    localCatalogEnumOrder(catalog, "scenario.name", ...
    {'indoorhotspot','urbanmacro','suburbanmacro','ruralmacro','denseurban'}), ...
    uint8(localCatalogDefaultCode(catalog, "scenario.name", 1))));

c.scenario.nUE = uint16(cfg.scenario.ue.nUE);
c.scenario.wrapAround = logical(cfg.scenario.layout.wrapAround);

% Mobility
c.scenario.mobilityEnable = logical(cfg.scenario.mobility.enable);
v = double(cfg.scenario.mobility.speed_kmh(:).');
if isempty(v), v = [0 0]; end
if numel(v) == 1, v = [v v]; end
v = v(1:2);
c.scenario.speedKmh = single(v);

% -------------------------------------------------------------------------
% Channel / carrier
% -------------------------------------------------------------------------
c.channel = struct();
c.channel.fc_Hz = double(cfg.channel.fc_Hz);
c.channel.bandwidth_Hz = double(cfg.channel.bandwidth_Hz);
c.channel.scs_kHz = double(cfg.phy.carrier.SubcarrierSpacing);

c.channel.type = uint8(localMapEnum(lower(char(cfg.channel.type)), ...
    localCatalogEnumOrder(catalog, "channel.type", ...
    {'tr38901','tdl','cdl','raytracing','awgn'}), ...
    uint8(localCatalogDefaultCode(catalog, "channel.type", 0))));

% -------------------------------------------------------------------------
% PHY essentials
% -------------------------------------------------------------------------
c.phy = struct();
c.phy.NCellID = uint16(cfg.phy.carrier.NCellID);
c.phy.NSizeGrid = uint16(cfg.phy.carrier.NSizeGrid);
c.phy.CyclicPrefix = uint8(localMapEnum(lower(char(cfg.phy.carrier.CyclicPrefix)), ...
    localCatalogEnumOrder(catalog, "phy.carrier.CyclicPrefix", {'normal','extended'}), ...
    uint8(localCatalogDefaultCode(catalog, "phy.carrier.CyclicPrefix", 0))));

% DL
c.phy.dl = struct();
c.phy.dl.pdschEnable = logical(cfg.phy.pdsch.enable);
c.phy.dl.nLayers = uint8(cfg.phy.pdsch.nLayers);
c.phy.dl.modulation = uint8(localMapEnum(upper(char(cfg.phy.pdsch.modulation)), ...
    localCatalogEnumOrder(catalog, "phy.pdsch.modulation", ...
    {'QPSK','16QAM','64QAM','256QAM','1024QAM','4096QAM'}), ...
    uint8(localCatalogDefaultCode(catalog, "phy.pdsch.modulation", 3))));
c.phy.dl.codeRate = single(cfg.phy.pdsch.codeRate);

% UL
c.phy.ul = struct();
c.phy.ul.puschEnable = logical(cfg.phy.pusch.enable);
c.phy.ul.nLayers = uint8(cfg.phy.pusch.nLayers);
c.phy.ul.modulation = uint8(localMapEnum(upper(char(cfg.phy.pusch.modulation)), ...
    localCatalogEnumOrder(catalog, "phy.pusch.modulation", ...
    {'QPSK','16QAM','64QAM','256QAM','1024QAM','4096QAM'}), ...
    uint8(localCatalogDefaultCode(catalog, "phy.pusch.modulation", 3))));
c.phy.ul.codeRate = single(cfg.phy.pusch.codeRate);
c.phy.ul.transformPrecoding = logical(cfg.phy.pusch.transformPrecoding);

% RACH/PRACH enable
c.phy.prachEnable = logical(cfg.phy.prach.enable);

% HARQ
c.phy.harqEnable = logical(cfg.phy.harq.enable);
c.phy.nHarq = uint8(cfg.phy.harq.nProcesses);

% -------------------------------------------------------------------------
% MAC essentials
% -------------------------------------------------------------------------
c.mac = struct();
c.mac.schedulerType = uint8(localMapEnum(upper(char(cfg.mac.scheduler.type)), ...
    localCatalogEnumOrder(catalog, "mac.scheduler.type", {'PF','RR','MAXCQI'}), ...
    uint8(localCatalogDefaultCode(catalog, "mac.scheduler.type", 0))));
c.mac.harqEnable = logical(cfg.mac.harq.enable);
c.mac.harqMaxRetx = uint8(cfg.mac.harq.maxRetx);

% -------------------------------------------------------------------------
% RF / energy
% -------------------------------------------------------------------------
c.rf = struct();
c.rf.enable = logical(cfg.rf.enable);
c.rf.noiseFigure_dB = single(cfg.rf.noiseFigure_dB);

c.energy = struct();
c.energy.enable = logical(cfg.energy.enable);
c.energy.bs_pStatic_W = single(cfg.energy.bs.pStatic_W);
c.energy.ue_pStatic_W = single(cfg.energy.ue.pStatic_W);

% -------------------------------------------------------------------------
% AI
% -------------------------------------------------------------------------
c.ai = struct();
c.ai.enable = logical(cfg.ai.enable);
c.ai.csiCompressionEnable = logical(cfg.ai.csiCompression.enable);
c.ai.beamSelectionEnable = logical(cfg.ai.beamSelection.enable);
c.ai.neuralReceiverEnable = logical(cfg.ai.neuralReceiver.enable);

end

% -------------------------------------------------------------------------
function code = localMapEnum(val, allowed, defaultCode)
% Map string to 0..N-1 code, else defaultCode.
code = defaultCode;
for i = 1:numel(allowed)
    if strcmp(val, allowed{i})
        code = uint8(i-1);
        return;
    end
end
end

function ordered = localCatalogEnumOrder(catalog, path, fallback)
ordered = fallback;
node = sixgr.util.structGet(catalog, "coder_enums." + string(path) + ".ordered_values", []);
if isempty(node)
    return;
end
ordered = cellstr(string(node(:).'));
end

function code = localCatalogDefaultCode(catalog, path, fallback)
code = fallback;
node = sixgr.util.structGet(catalog, "coder_enums." + string(path) + ".default_code", []);
if isempty(node)
    return;
end
code = double(node);
end
