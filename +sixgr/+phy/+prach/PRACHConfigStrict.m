function strictCfg = PRACHConfigStrict(baseCfg, varargin)
%PRACHCONFIGSTRICT Public strict PRACH configuration entry point.

strictCfg = sixgr.phy.prach.buildPRACHConfigFromScenario(baseCfg, varargin{:});
end
