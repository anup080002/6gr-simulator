function campaign = loadCampaignConfig(configPath, modeOverride)
%LOADCAMPAIGNCONFIG Load and validate one YAML-owned PDCCH TDoc campaign.

arguments
    configPath (1,1) string
    modeOverride (1,1) string = ""
end

resolvedPath = localResolve(configPath);
raw = sixgr.lls6g.config.readConfigFile(resolvedPath);
if ~isfield(raw, "pdcch_tdoc10521")
    error("sixgr:phy:pdcch:tdoc:MissingConfigSection", ...
        "PDCCH TDoc YAML must contain pdcch_tdoc10521.");
end
cfg = raw.pdcch_tdoc10521;
if strlength(strtrim(modeOverride)) > 0
    cfg.campaign_mode = char(lower(strtrim(modeOverride)));
    raw.pdcch_tdoc10521 = cfg;
end
sixgr.phy.pdcch.tdoc.validateCampaignConfig(cfg);
canonical = jsonencode(raw);
hash = sixgr.util.sha256Hex(uint8(unicode2native(canonical, "UTF-8")));
[sourcePath, sourceHash] = localFindSource(cfg.source);
promptPath = string(cfg.source.implementation_prompt);
if ~isfile(promptPath)
    error("sixgr:phy:pdcch:tdoc:MissingImplementationPrompt", ...
        "Configured implementation prompt does not exist: %s.", promptPath);
end
promptHash = localHash(promptPath);
expectedPromptHash = upper(string(cfg.source.implementation_prompt_sha256));
if upper(promptHash) ~= expectedPromptHash
    error("sixgr:phy:pdcch:tdoc:PromptHashMismatch", ...
        "Implementation prompt SHA-256 mismatch: expected %s, measured %s.", ...
        expectedPromptHash, promptHash);
end
campaign = struct("Config", cfg, "Raw", raw, ...
    "ConfigPath", string(resolvedPath), "ConfigHash", string(hash), ...
    "Mode", lower(string(cfg.campaign_mode)), ...
    "ScenarioID", string(raw.meta.scenario_id), ...
    "SourcePath", sourcePath, "SourceHash", sourceHash, ...
    "SourceAvailable", strlength(sourcePath) > 0, ...
    "PromptPath", promptPath, "PromptHash", promptHash);
end

function path = localResolve(path)
path = string(path);
if isfile(path)
    path = string(char(java.io.File(char(path)).getCanonicalPath()));
    return;
end
candidate = fullfile(localRoot(), path);
if isfile(candidate)
    path = string(char(java.io.File(char(candidate)).getCanonicalPath()));
    return;
end
error("sixgr:phy:pdcch:tdoc:ConfigNotFound", ...
    "PDCCH TDoc config not found: %s.", path);
end

function [path, hash] = localFindSource(source)
name = string(source.controlling_document);
locations = string(source.expected_locations(:));
root = localRoot();
path = "";
hash = "";
for location = locations(:).'
    candidate = fullfile(location, name);
    if ~java.io.File(char(location)).isAbsolute()
        candidate = fullfile(root, candidate);
    end
    if isfile(candidate)
        path = string(char(java.io.File(char(candidate)).getCanonicalPath()));
        hash = localHash(path);
        return;
    end
end
end

function hash = localHash(path)
fid = fopen(char(path), "r");
if fid < 0
    error("sixgr:phy:pdcch:tdoc:HashReadFailed", "Cannot read %s.", path);
end
clean = onCleanup(@()fclose(fid)); %#ok<NASGU>
hash = string(sixgr.util.sha256Hex(fread(fid, Inf, "*uint8")));
end

function root = localRoot()
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(fileparts(here))));
end
