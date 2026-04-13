function ok = testPresetHygiene()
%TESTPRESETHYGIENE Verify shipped full presets are explicit and non-contradictory.

setup6GRSimToolkit("Verbose", false);
root = fileparts(which("setup6GRSimToolkit"));
files = localEnumeratePresetFiles(root);
classes = strings(numel(files), 1);

for i = 1:numel(files)
    file = files{i};
    raw = jsondecode(fileread(file));
    rel = string(strrep(file, [root filesep], ""));
    localAssertPresetLabels(raw, rel);
    localAssertRawIntentHonest(raw, rel);

    cfg = sixgr_loadConfig(file);
    cfg = sixgr.config.normalizeConfig(cfg);
    sixgr.config.validateConfig(cfg);
    classes(i) = lower(string(sixgr.util.structGet(cfg, "meta.presetClass", "")));
end

assert(any(classes == "fading_truth"), "Expected at least one shipped fading/truth preset.");
assert(~any(classes == "smoke_awgn"), "Shipped smoke/AWGN presets should have been removed.");
assert(~any(classes == "stress_proxy"), "Stress/proxy shipped presets should have been removed.");
ok = true;
end

function files = localEnumeratePresetFiles(root)
suiteFiles = dir(fullfile(root, "config", "suite_config*.json"));
presetFiles = dir(fullfile(root, "config", "presets", "*.json"));

files = cell(0,1);
for i = 1:numel(suiteFiles)
    if strcmpi(suiteFiles(i).name, "suite_config.schema.json")
        continue;
    end
    files{end+1,1} = fullfile(suiteFiles(i).folder, suiteFiles(i).name); %#ok<AGROW>
end
for i = 1:numel(presetFiles)
    files{end+1,1} = fullfile(presetFiles(i).folder, presetFiles(i).name); %#ok<AGROW>
end
files = sort(files);
end

function localAssertPresetLabels(raw, rel)
presetClass = lower(string(localGetPath(raw, "meta.presetClass", "")));
presetIntent = string(localGetPath(raw, "meta.presetIntent", ""));
assert(strlength(presetClass) > 0, "%s must declare meta.presetClass.", rel);
assert(strlength(strtrim(presetIntent)) > 0, "%s must declare meta.presetIntent.", rel);
assert(any(presetClass == ["fading_truth"]), ...
    "%s has unsupported meta.presetClass='%s'.", rel, presetClass);
end

function localAssertRawIntentHonest(raw, rel)
awgnOnly = logical(localGetPath(raw, "channel.awgnOnly", false));
model = upper(strtrim(char(string(localGetPath(raw, "channel.model", "")))));
delayProfile = upper(strtrim(char(string(localGetPath(raw, "channel.delayProfile", "")))));
fadingEnableSpecified = localHasPath(raw, "channel.fading.enable");
fadingEnable = false;
if fadingEnableSpecified
    fadingEnable = logical(localGetPath(raw, "channel.fading.enable", false));
end
fadingModel = upper(strtrim(char(string(localGetPath(raw, "channel.fading.model", "")))));
fadingProfile = upper(strtrim(char(string(localGetPath(raw, "channel.fading.profile", "")))));
hasFadingClaim = localHasConcreteFadingToken(model) || localHasConcreteFadingToken(delayProfile) || ...
    localHasConcreteFadingToken(fadingModel) || localHasConcreteFadingToken(fadingProfile) || fadingEnable;
flatModel = any(strcmp(model, {'AWGN','NONE','OFF'}));

if awgnOnly
    assert(~hasFadingClaim, ...
        "%s raw JSON still mixes awgnOnly=true with TDL/CDL fading claims.", rel);
    assert(isempty(model) || flatModel, ...
        "%s raw JSON must use an explicit AWGN/None/Off model when awgnOnly=true.", rel);
end

if flatModel
    assert(~(fadingEnable || localHasConcreteFadingToken(delayProfile) || ...
        localHasConcreteFadingToken(fadingModel) || localHasConcreteFadingToken(fadingProfile)), ...
        "%s raw JSON cannot mix an AWGN model with TDL/CDL fading fields.", rel);
end

presetClass = lower(string(localGetPath(raw, "meta.presetClass", "")));
switch char(presetClass)
    case 'fading_truth'
        assert(~awgnOnly && (localHasConcreteFadingToken(model) || localHasConcreteFadingToken(delayProfile) || ...
            localHasConcreteFadingToken(fadingModel) || localHasConcreteFadingToken(fadingProfile)), ...
            "%s fading/truth preset must explicitly declare a concrete TDL/CDL profile in raw JSON.", rel);
end
end

function tf = localHasConcreteFadingToken(token)
tok = upper(strtrim(char(string(token))));
tf = (startsWith(tok, 'TDL') && ~strcmp(tok, 'TDL')) || ...
    (startsWith(tok, 'CDL') && ~strcmp(tok, 'CDL'));
end

function tf = localHasPath(s, pathStr)
parts = strsplit(char(pathStr), '.');
tf = true;
cur = s;
for i = 1:numel(parts)
    if ~isstruct(cur) || ~isfield(cur, parts{i})
        tf = false;
        return;
    end
    cur = cur.(parts{i});
end
end

function value = localGetPath(s, pathStr, defaultValue)
if nargin < 3
    defaultValue = [];
end
parts = strsplit(char(pathStr), '.');
cur = s;
for i = 1:numel(parts)
    if ~isstruct(cur) || ~isfield(cur, parts{i})
        value = defaultValue;
        return;
    end
    cur = cur.(parts{i});
end
value = cur;
end
