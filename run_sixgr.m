function out = run_sixgr(configPath, outputDir, runTag)
%RUN_SIXGR YAML-selected LLS or SLS. No agenda-specific execution policy.
if nargin < 2, outputDir = 'results'; end
if nargin < 3, runTag = ''; end
request = sixgr.config.loadSimulationRequest(configPath);
if request.Mode == "LLS"
    out = run_6g_phy_lls_single(configPath,outputDir,runTag);
else
    out = sixgr.system.runConfiguredSLS(request,outputDir,runTag);
end
end
