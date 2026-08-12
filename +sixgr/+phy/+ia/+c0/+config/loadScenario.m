function [cfg,meta] = loadScenario(configPath,runMode)
%LOADSCENARIO Load, resolve, validate, and hash a C0 IA configuration.
arguments
    configPath (1,1) string = "simulator/configs/initial_access/c0/C0.yaml"
    runMode (1,1) string = ""
end
[cfg,sources] = sixgr.phy.ia.c0.config.resolveScenario(configPath,runMode);
sixgr.phy.ia.c0.config.validateScenario(cfg);
canonical = jsonencode(cfg);
meta = struct( ...
    "SourceFiles",sources, ...
    "ConfigHash",string(sixgr.util.sha256Hex(uint8(unicode2native(canonical,"UTF-8")))), ...
    "ResolvedUTC",string(datetime("now","TimeZone","UTC","Format","yyyy-MM-dd'T'HH:mm:ss'Z'")));
end
