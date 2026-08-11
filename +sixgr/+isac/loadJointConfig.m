function [cfg,sourcePath] = loadJointConfig(configPath,runMode)
%LOADJOINTCONFIG Load and validate the versioned joint ISAC master YAML.

arguments
    configPath (1,1) string = "configs/isac/joint_isac_tdoc_master.yaml"
    runMode (1,1) string = ""
end

sourcePath = string(configPath);
if exist(sourcePath,"file") ~= 2
    sourcePath = string(fullfile(localRepoRoot(),char(configPath)));
end
if exist(sourcePath,"file") ~= 2
    error("sixgr:isac:JointConfigNotFound", ...
        "Joint ISAC configuration not found: %s",configPath);
end
cfg = sixgr.lls6g.config.readConfigFile(sourcePath);
if strlength(runMode) > 0
    cfg.run.activeMode = char(lower(strtrim(runMode)));
end
cfg.provenance = struct( ...
    "SourcePath",char(sourcePath), ...
    "SourceSHA256",char(sixgr.util.sha256Hex(fileread(sourcePath))));
sixgr.isac.validateJointConfig(cfg);
end

function root = localRepoRoot()
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(here));
end
