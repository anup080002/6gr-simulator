function bundle = channelRFStrictAnchorResult(varargin)
%CHANNELRFSTRICTANCHORRESULT Cached strict Channel/RF mini-anchor execution.

p = inputParser;
p.addParameter("Refresh", false, @(x) islogical(x) || isnumeric(x));
p.addParameter("WriteArtifacts", false, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
refresh = logical(p.Results.Refresh);
writeArtifacts = logical(p.Results.WriteArtifacts);

persistent cachedNoArtifacts cachedArtifacts
if writeArtifacts
    if refresh || isempty(cachedArtifacts)
        cachedArtifacts = localRun(true);
    end
    bundle = cachedArtifacts;
else
    if refresh || isempty(cachedNoArtifacts)
        cachedNoArtifacts = localRun(false);
    end
    bundle = cachedNoArtifacts;
end
end

function bundle = localRun(writeArtifacts)
repoRoot = fileparts(fileparts(mfilename("fullpath")));
scenarioPath = fullfile(repoRoot, "configs", "lls", "lls_channel_rf_strict_mini_anchor.yaml");
runFolder = tempname;
mkdir(runFolder);
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, runFolder);
result = sixgr.channel.runStrictChannelRFValidation(cfg, ...
    "RunFolder", runFolder, ...
    "RunId", "strict_channel_rf_unit", ...
    "ScenarioName", "lls_channel_rf_strict_mini_anchor", ...
    "WriteArtifacts", writeArtifacts);
bundle = struct();
bundle.RepoRoot = repoRoot;
bundle.ScenarioPath = scenarioPath;
bundle.RunFolder = runFolder;
bundle.Config = cfg;
bundle.ScenarioConfig = scfg;
bundle.Result = result;
end
