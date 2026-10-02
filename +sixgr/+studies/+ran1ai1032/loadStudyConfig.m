function [cfg, provenance] = loadStudyConfig(configPath)
%LOADSTUDYCONFIG Load and validate the AI 10.3.2 campaign contract.
arguments
    configPath (1,1) string = ...
        "configs/tdoc/ai_10_3_2_modulation/study.yaml"
end

root = localRepoRoot();
path = configPath;
if ~java.io.File(char(path)).isAbsolute()
    path = string(fullfile(root, path));
end
cfg = sixgr.lls6g.config.readConfigFile(path);
cfg = sixgr.studies.ran1ai1032.validateStudyConfig(cfg);
provenance = struct( ...
    "ConfigPath", path, ...
    "ConfigSHA256", sixgr.csi.studyFileSHA256(path), ...
    "GitCommit", localGitCommit(root));
end

function root = localRepoRoot()
root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end

function value = localGitCommit(root)
[status, text] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if status == 0
    value = strtrim(string(text));
else
    value = "UNKNOWN";
end
end
