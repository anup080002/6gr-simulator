function bundle = channelRFStrictAnchorResult(varargin)
%CHANNELRFSTRICTANCHORRESULT Cached strict Channel/RF mini-anchor execution.

p = inputParser;
p.addParameter("Refresh", false, @(x) islogical(x) || isnumeric(x));
p.addParameter("WriteArtifacts", false, @(x) islogical(x) || isnumeric(x));
p.addParameter("ChannelModel", "CDL", @(x) ischar(x) || isstring(x));
p.parse(varargin{:});
refresh = logical(p.Results.Refresh);
writeArtifacts = logical(p.Results.WriteArtifacts);
channelModel = upper(strtrim(string(p.Results.ChannelModel)));
assert(any(channelModel == ["CDL","TDL"]), ...
    "ChannelModel must be the configured CDL or TDL strict anchor.");

persistent cachedNoArtifactsCDL cachedArtifactsCDL
persistent cachedNoArtifactsTDL cachedArtifactsTDL
if channelModel == "TDL"
    if writeArtifacts
        if refresh || isempty(cachedArtifactsTDL)
            cachedArtifactsTDL = localRun(channelModel, true);
        end
        bundle = cachedArtifactsTDL;
    else
        if refresh || isempty(cachedNoArtifactsTDL)
            cachedNoArtifactsTDL = localRun(channelModel, false);
        end
        bundle = cachedNoArtifactsTDL;
    end
else
    if writeArtifacts
        if refresh || isempty(cachedArtifactsCDL)
            cachedArtifactsCDL = localRun(channelModel, true);
        end
        bundle = cachedArtifactsCDL;
    else
        if refresh || isempty(cachedNoArtifactsCDL)
            cachedNoArtifactsCDL = localRun(channelModel, false);
        end
        bundle = cachedNoArtifactsCDL;
    end
end
end

function bundle = localRun(channelModel, writeArtifacts)
repoRoot = fileparts(fileparts(mfilename("fullpath")));
if channelModel == "TDL"
    scenarioFile = "lls_channel_rf_strict_tdl_mini_anchor.yaml";
else
    scenarioFile = "lls_channel_rf_strict_mini_anchor.yaml";
end
scenarioPath = fullfile(repoRoot, "configs", "lls", scenarioFile);
runFolder = tempname;
mkdir(runFolder);
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, runFolder);
result = sixgr.channel.runStrictChannelRFValidation(cfg, ...
    "RunFolder", runFolder, ...
    "RunId", "strict_channel_rf_" + lower(channelModel) + "_unit", ...
    "ScenarioName", erase(scenarioFile, ".yaml"), ...
    "WriteArtifacts", writeArtifacts);
bundle = struct();
bundle.RepoRoot = repoRoot;
bundle.ScenarioPath = scenarioPath;
bundle.RunFolder = runFolder;
bundle.Config = cfg;
bundle.ScenarioConfig = scfg;
bundle.Result = result;
end
