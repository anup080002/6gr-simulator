function result=runPUCCHDetectorPilot(configPath,outputRoot)
% Backward-compatible development-only entry point to physical execution.
v=sixgr.lls6g.config.readConfigFile(configPath);
validatePUCCHDetectorPilotPolicy(v);
result=runPUCCHDetectorEpisodes(configPath,outputRoot);
end
