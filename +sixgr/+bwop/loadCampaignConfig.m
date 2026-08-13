function campaign = loadCampaignConfig(configPath,modeOverride)
%LOADCAMPAIGNCONFIG Load and hash one BWOP YAML authority.

arguments
    configPath (1,1) string
    modeOverride (1,1) string = ""
end

resolvedPath=localResolve(configPath);
raw=sixgr.lls6g.config.readConfigFile(resolvedPath);
sixgr.lls6g.config.validateScenarioConfig(raw,"Kind","scenario", ...
    "AllowPartial",true,"Context",resolvedPath);
if ~isfield(raw,"bwop")
    error("sixgr:bwop:MissingConfigSection", ...
        "BWOP campaign YAML must contain the bwop section.");
end
cfg=raw.bwop;
if strlength(strtrim(modeOverride))>0
    cfg.campaign_mode=char(lower(strtrim(modeOverride)));
    raw.bwop=cfg;
end
sixgr.bwop.validateCampaignConfig(cfg);
hash=sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(raw),"UTF-8")));
sourcePath=localFindSource(cfg.source);
campaign=struct("Config",cfg,"Raw",raw,"ConfigPath",string(resolvedPath), ...
    "ConfigHash",string(hash),"Mode",lower(string(cfg.campaign_mode)), ...
    "ScenarioID",string(raw.meta.scenario_id),"SourcePath",sourcePath, ...
    "SourceAvailable",strlength(sourcePath)>0);
end

function path=localResolve(path)
path=string(path);
if isfile(path),path=string(char(java.io.File(char(path)).getCanonicalPath()));return;end
root=localRoot();candidate=fullfile(root,path);
if isfile(candidate),path=string(char(java.io.File(char(candidate)).getCanonicalPath()));return;end
error("sixgr:bwop:ConfigNotFound","BWOP config not found: %s.",path);
end

function path=localFindSource(source)
name=string(source.controlling_document);locations=string(source.expected_locations(:));
root=localRoot();path="";
for location=locations(:).'
    candidate=fullfile(location,name);
    if ~java.io.File(char(location)).isAbsolute(),candidate=fullfile(root,candidate);end
    if isfile(candidate),path=string(char(java.io.File(char(candidate)).getCanonicalPath()));return;end
end
end

function root=localRoot()
here=fileparts(mfilename("fullpath"));root=fileparts(fileparts(fileparts(here)));
end
