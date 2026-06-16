function bundle = pdcchStrictAnchorResult(varargin)
%PDCCHSTRICTANCHORRESULT Cached strict PDCCH mini-anchor execution for tests.

p = inputParser;
p.addParameter("Refresh", false, @(x) islogical(x) || isnumeric(x));
p.addParameter("WriteArtifacts", false, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
writeArtifacts = logical(p.Results.WriteArtifacts);
refresh = logical(p.Results.Refresh);

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
scenarioPath = fullfile(repoRoot, "configs", "lls", "lls_pdcch_strict_mini_anchor.yaml");
runFolder = tempname;
mkdir(runFolder);
cfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
internalCfg = sixgr.lls6g.buildInternalConfig(cfg, runFolder);
result = sixgr.phy.pdcch.runStrictPDCCHValidation(internalCfg, ...
    "RunFolder", runFolder, ...
    "RunId", "strict_pdcch_unit", ...
    "ScenarioName", "lls_pdcch_strict_mini_anchor", ...
    "WriteArtifacts", writeArtifacts);
bundle = struct();
bundle.RepoRoot = repoRoot;
bundle.ScenarioPath = scenarioPath;
bundle.RunFolder = runFolder;
bundle.InternalConfig = internalCfg;
bundle.Config = result.Config;
bundle.Result = result;
end
