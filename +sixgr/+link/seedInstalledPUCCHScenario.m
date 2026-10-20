function source=seedInstalledPUCCHScenario(base,policy,seed)
% Compatibility entrypoint; seed validated YAML before constructing runtime.
source=sixgr.link.seedInstalledControlScenario(base,policy,seed,"PUCCH");
end
