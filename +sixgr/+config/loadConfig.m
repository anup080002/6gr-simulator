function cfg = loadConfig(cfgFile)
% sixgr.config.loadConfig
% Load JSON config, modular fragments, and optional presets.
% Then deep-merge with defaults, normalize, and validate.
%
% Usage:
%   cfg = sixgr.config.loadConfig("config/suite_config.json");

cfgDefault = sixgr.config.defaultConfig();
root = localProjectRoot();

userCfg = struct();
cfgFileUsed = "";

if nargin >= 1 && ~isempty(cfgFile)
    if builtin("isstruct", cfgFile) && isscalar(cfgFile)
        userCfg = cfgFile;
    else
        cfgFile = char(cfgFile);

        cfgFileResolved = localResolvePath(cfgFile);
        if isempty(cfgFileResolved)
            error("sixgr:config:FileNotFound","Config file not found: %s", cfgFile);
        end

        userCfg = sixgr.util.jsonRead(cfgFileResolved);
        cfgFileUsed = cfgFileResolved;
    end
end

if isempty(userCfg)
    userCfg = struct();
end
if ~builtin("isstruct", userCfg) || ~isscalar(userCfg)
    error("sixgr:config:BadConfigType","Top-level JSON must decode to a scalar struct/object.");
end

% Optional modular config fragments under config/.
useFragments = logical(sixgr.util.structGet(userCfg, "run.useConfigFragments", true));
fragCfg = struct();
fragFiles = strings(0,1);
if useFragments
    [fragCfg, fragFiles] = localLoadConfigFragments(root);
end

% Optional preset (config/presets/*.json).
presetName = localFindPresetName(userCfg);
[presetCfg, presetFile] = localLoadPreset(root, presetName);

% Merge order: defaults <- fragments <- preset <- user.
cfg = sixgr.util.mergeStruct(cfgDefault, fragCfg);
cfg = sixgr.util.mergeStruct(cfg, presetCfg);
cfg = sixgr.util.mergeStruct(cfg, userCfg);

% Apply selected traffic profile to active traffic section.
cfg = localApplyTrafficProfile(cfg);

% Keep provenance
cfg.run.configFile = string(cfgFileUsed);
cfg.run.preset = string(presetName);
cfg.run.presetFile = string(presetFile);
cfg.run.useConfigFragments = useFragments;
cfg.run.configFragments = cellstr(fragFiles);
cfg.run.projectRoot = string(root);

cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);

end

function p = localResolvePath(cfgFile)
% Try direct path first
if isfile(cfgFile)
    p = cfgFile;
    return;
end

% If relative, try relative to project root (folder containing +sixgr)
if ~isabsolute(cfgFile)
    here = fileparts(mfilename("fullpath"));              % .../+sixgr/+config
    root = fileparts(fileparts(fileparts(here)));         % project root

    cand = fullfile(root, cfgFile);
    if isfile(cand)
        p = cand;
        return;
    end

    % If user passed just a filename, also try root/config/<file>
    [~,~,ext] = fileparts(cfgFile);
    if ~isempty(ext)
        cand2 = fullfile(root, "config", cfgFile);
        if isfile(cand2)
            p = cand2;
            return;
        end
    end
end

p = "";

end

function root = localProjectRoot()
here = fileparts(mfilename("fullpath"));              % .../+sixgr/+config
root = fileparts(fileparts(fileparts(here)));         % project root
end

function [cfgFrag, files] = localLoadConfigFragments(root)
cfgFrag = struct();
files = strings(0,1);

% -------------------------- PHY fragments --------------------------
phyFiles = { ...
    "pdsch", "phy.pdsch"; ...
    "pdcch", "phy.pdcch"; ...
    "prach", "phy.prach"; ...
    "pusch", "phy.pusch"; ...
    "pucch", "phy.pucch"; ...
    "srs",   "phy.srs" ...
    };
for i = 1:size(phyFiles,1)
    name = phyFiles{i,1};
    path = fullfile(root, "config", "phy", name + ".json");
    [ok, s] = localReadStruct(path);
    if ok
        cfgFrag = localMergeAtPath(cfgFrag, phyFiles{i,2}, s);
        files(end+1,1) = string(path); %#ok<AGROW>
    end
end

% SSB/PBCH/MIB/SIB1 bundle.
ssbPath = fullfile(root, "config", "phy", "ssb_pbch.json");
[okSsb, ssbCfg] = localReadStruct(ssbPath);
if okSsb
    if isfield(ssbCfg, "ssb"), cfgFrag = localMergeAtPath(cfgFrag, "phy.ssb", ssbCfg.ssb); end
    if isfield(ssbCfg, "pbch"), cfgFrag = localMergeAtPath(cfgFrag, "phy.pbch", ssbCfg.pbch); end
    if isfield(ssbCfg, "mib"), cfgFrag = localMergeAtPath(cfgFrag, "phy.mib", ssbCfg.mib); end
    if isfield(ssbCfg, "sib1"), cfgFrag = localMergeAtPath(cfgFrag, "phy.sib1", ssbCfg.sib1); end
    files(end+1,1) = string(ssbPath); %#ok<AGROW>
end

% ------------------------ Channel fragments ------------------------
chPath = fullfile(root, "config", "channel", "tr38901_profiles.json");
[okCh, chCfg] = localReadStruct(chPath);
if okCh
    cfgFrag = localMergeAtPath(cfgFrag, "channel.tr38901Profiles", chCfg);
    files(end+1,1) = string(chPath); %#ok<AGROW>
end

abgPath = fullfile(root, "config", "channel", "fr3_abg_coeffs.csv");
if isfile(abgPath)
    cfgFrag = localMergeAtPath(cfgFrag, "channel.tables", struct("fr3ABGCoeffsCSV", string(abgPath)));
    files(end+1,1) = string(abgPath); %#ok<AGROW>
end
o2iPath = fullfile(root, "config", "channel", "o2i_materials.csv");
if isfile(o2iPath)
    cfgFrag = localMergeAtPath(cfgFrag, "channel.tables", struct("o2iMaterialsCSV", string(o2iPath)));
    files(end+1,1) = string(o2iPath); %#ok<AGROW>
end

% ------------------------ Traffic fragments ------------------------
trafficFiles = ["xr","genai","mmtc"];
for i = 1:numel(trafficFiles)
    name = trafficFiles(i);
    path = fullfile(root, "config", "traffic", name + ".json");
    [ok, s] = localReadStruct(path);
    if ok
        cfgFrag = localMergeAtPath(cfgFrag, "traffic.profiles." + name, s);
        files(end+1,1) = string(path); %#ok<AGROW>
    end
end

% ------------------------ Energy fragments -------------------------
bsPath = fullfile(root, "config", "energy", "bs_power_model.json");
[okBs, bsCfg] = localReadStruct(bsPath);
if okBs
    cfgFrag = localMergeAtPath(cfgFrag, "energy.bs", bsCfg);
    files(end+1,1) = string(bsPath); %#ok<AGROW>
end
uePath = fullfile(root, "config", "energy", "ue_power_model.json");
[okUe, ueCfg] = localReadStruct(uePath);
if okUe
    cfgFrag = localMergeAtPath(cfgFrag, "energy.ue", ueCfg);
    files(end+1,1) = string(uePath); %#ok<AGROW>
end

% -------------------------- AI fragments ---------------------------
aiCsiPath = fullfile(root, "config", "ai", "csi_ae.json");
[okCsi, csiCfg] = localReadStruct(aiCsiPath);
if okCsi
    cfgFrag = localMergeAtPath(cfgFrag, "ai.csiCompression", csiCfg);
    files(end+1,1) = string(aiCsiPath); %#ok<AGROW>
end
aiBeamPath = fullfile(root, "config", "ai", "beam_selection.json");
[okBeam, beamCfg] = localReadStruct(aiBeamPath);
if okBeam
    cfgFrag = localMergeAtPath(cfgFrag, "ai.beamSelection", beamCfg);
    files(end+1,1) = string(aiBeamPath); %#ok<AGROW>
end

% --------------------------- IO fragments --------------------------
ioPath = fullfile(root, "config", "io", "output_kpis.json");
[okIo, ioCfg] = localReadStruct(ioPath);
if okIo
    if isfield(ioCfg, "kpis")
        cfgFrag = localMergeAtPath(cfgFrag, "outputs.kpi.catalog", ioCfg.kpis);
    end
    if isfield(ioCfg, "export") && isstruct(ioCfg.export)
        ex = ioCfg.export;
        if isfield(ex, "csv"), cfgFrag = localMergeAtPath(cfgFrag, "outputs.saveCSV", logical(ex.csv)); end
        if isfield(ex, "mat"), cfgFrag = localMergeAtPath(cfgFrag, "outputs.saveMAT", logical(ex.mat)); end
        if isfield(ex, "figures"), cfgFrag = localMergeAtPath(cfgFrag, "outputs.saveFigures", logical(ex.figures)); end
        if isfield(ex, "png"), cfgFrag = localMergeAtPath(cfgFrag, "outputs.savePNG", logical(ex.png)); end
    end
    files(end+1,1) = string(ioPath); %#ok<AGROW>
end
end

function [presetCfg, presetFile] = localLoadPreset(root, presetName)
presetCfg = struct();
presetFile = "";

if strlength(string(presetName)) == 0
    return;
end

presetName = char(string(presetName));
[~,~,ext] = fileparts(presetName);
if isempty(ext)
    presetName = [presetName ".json"];
end

path = fullfile(root, "config", "presets", presetName);
if ~isfile(path)
    return;
end

[ok, s] = localReadStruct(path);
if ok
    presetCfg = s;
    presetFile = path;
end
end

function presetName = localFindPresetName(userCfg)
presetName = char(string(sixgr.util.structGet(userCfg, "run.preset", "")));
if strlength(string(presetName)) > 0
    return;
end

presetName = char(string(sixgr.util.structGet(userCfg, "run.configPreset", "")));
if strlength(string(presetName)) > 0
    return;
end

presetName = char(string(sixgr.util.structGet(userCfg, "scenario.preset", "")));
if strlength(string(presetName)) > 0
    return;
end

% Best-effort mapping from scenario.name to known preset.
sc = lower(strtrim(char(string(sixgr.util.structGet(userCfg, "scenario.name", "")))));
switch sc
    case {"urbanmacro","uma","uma_fr1"}
        presetName = "UMa_FR1";
    case {"indoorhotspot","inh","inh_fr3"}
        presetName = "InH_FR3";
    case {"suburbanmacro","sma","sma_fr3"}
        presetName = "SMa_FR3";
    case {"ruralmacro","rma","rma_700mhz"}
        presetName = "RMa_700MHz";
    otherwise
        presetName = "";
end
end

function cfg = localApplyTrafficProfile(cfg)
model = lower(strtrim(char(string(sixgr.util.structGet(cfg, "traffic.model", "")))));
if strlength(string(model)) == 0
    return;
end

profiles = sixgr.util.structGet(cfg, "traffic.profiles", struct());
if ~(builtin("isstruct", profiles) && isscalar(profiles))
    return;
end
if ~isfield(profiles, model)
    return;
end

p = profiles.(model);
cfg.traffic.profileName = string(model);
cfg.traffic.profile = p;

if isfield(p, "qos") && isstruct(p.qos)
    cfg.traffic.qos = sixgr.util.mergeStruct(sixgr.util.structGet(cfg, "traffic.qos", struct()), p.qos);
end
if isfield(p, "dl") && isstruct(p.dl)
    cfg.traffic.dl = sixgr.util.mergeStruct(sixgr.util.structGet(cfg, "traffic.dl", struct()), p.dl);
end
if isfield(p, "ul") && isstruct(p.ul)
    cfg.traffic.ul = sixgr.util.mergeStruct(sixgr.util.structGet(cfg, "traffic.ul", struct()), p.ul);
end
end

function s = localMergeAtPath(s, path, v)
if ~(builtin("isstruct", v) && isscalar(v))
    % For scalars/logicals placed directly at a path.
    s = sixgr.util.structSet(s, char(string(path)), v);
    return;
end
cur = sixgr.util.structGet(s, char(string(path)), struct());
if builtin("isstruct", cur) && isscalar(cur)
    v = sixgr.util.mergeStruct(cur, v);
end
s = sixgr.util.structSet(s, char(string(path)), v);
end

function [ok, s] = localReadStruct(path)
ok = false;
s = struct();
if ~isfile(path)
    return;
end
try
    s = sixgr.util.jsonRead(path);
    ok = builtin("isstruct", s) && isscalar(s);
catch
    ok = false;
    s = struct();
end
end

function tf = isabsolute(pth)
% Absolute path on Windows (C:\...) or UNC (\\server\share) or UNIX (/...)
if startsWith(pth, filesep)
    tf = true;
    return;
end
if length(pth) >= 2 && isletter(pth(1)) && pth(2) == ':'
    tf = true;
    return;
end
if startsWith(pth, "\\")
    tf = true;
    return;
end
tf = false;
end
