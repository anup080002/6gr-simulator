function out = run_6g_phy_lls_single(configPath, outputDir, runTag)
%RUN_6G_PHY_LLS_SINGLE Front-door single-scenario CLI wrapper.

if nargin < 1 || strlength(string(configPath)) == 0
    error("sixgr:lls6g:runner:MissingConfigPath", ...
        "run_6g_phy_lls_single requires a scenario config path.");
end
if nargin < 2 || isempty(outputDir)
    outputDir = "results";
end
if nargin < 3
    runTag = "";
end
out = sixgr.lls6g.runners.runSingle(configPath, outputDir, runTag);
end
